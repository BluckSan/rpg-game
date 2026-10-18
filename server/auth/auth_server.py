#!/usr/bin/env python3
"""Осколки Эфира — сервис аккаунтов (v0.7.0).

HTTPS (самоподписанный сертификат, клиент закрепляет его) на :7780 для игроков:
  POST /api/register {username, password}      -> {token, username}
  POST /api/login    {username, password}      -> {token, username}
  POST /api/logout                              (Bearer)
  GET  /api/characters                          (Bearer) -> {characters: [data...]}
  POST /api/characters {data}                   (Bearer) -> {character: data}   новый герой 1 ур.
  DELETE /api/characters/<id>                   (Bearer)
HTTP только на 127.0.0.1:7781 для игрового сервера (заголовок X-Internal-Key):
  POST /internal/session {token, char_id}      -> {account_id, username, character}
  PUT  /internal/characters/<id> {data}        -> {ok}
Пароли — scrypt (соль 16 байт), токены — 32 случайных байта, в БД хранится только SHA-256 токена.
"""
import hashlib, hmac, json, os, re, secrets, ssl, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import psycopg2
import psycopg2.pool
from psycopg2.extras import Json

DSN = os.environ.get("RPG_DSN", "dbname=rpg user=rpg host=/var/run/postgresql")
INTERNAL_KEY = os.environ.get("RPG_INTERNAL_KEY", "")
CERT = os.environ.get("RPG_CERT", "/etc/rpg/cert.pem")
KEY = os.environ.get("RPG_KEY", "/etc/rpg/key.pem")
PUBLIC_PORT = int(os.environ.get("RPG_AUTH_PORT", "7780"))
INTERNAL_PORT = int(os.environ.get("RPG_INTERNAL_PORT", "7781"))
TOKEN_TTL = 30 * 24 * 3600
MAX_CHARS = 6
MAX_BODY = 256 * 1024
USER_RE = re.compile(r"^[A-Za-z0-9_\-а-яА-ЯёЁ]{3,20}$")
CLASSES = {"warrior", "mage", "archer"}

pool = psycopg2.pool.ThreadedConnectionPool(1, 6, DSN)

SCHEMA = """
CREATE TABLE IF NOT EXISTS accounts (
  id BIGSERIAL PRIMARY KEY,
  username TEXT NOT NULL,
  username_lc TEXT NOT NULL UNIQUE,
  pw_hash TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_login TIMESTAMPTZ
);
CREATE TABLE IF NOT EXISTS tokens (
  token_hash BYTEA PRIMARY KEY,
  account_id BIGINT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  expires_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX IF NOT EXISTS tokens_account ON tokens(account_id);
CREATE TABLE IF NOT EXISTS characters (
  id BIGSERIAL PRIMARY KEY,
  account_id BIGINT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  data JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS characters_account ON characters(account_id);
"""


def db(fn):
    conn = pool.getconn()
    try:
        with conn:
            with conn.cursor() as cur:
                return fn(cur)
    finally:
        pool.putconn(conn)


def hash_pw(pw: str) -> str:
    salt = secrets.token_bytes(16)
    h = hashlib.scrypt(pw.encode(), salt=salt, n=2 ** 14, r=8, p=1, dklen=32)
    return "scrypt$16384$8$1$%s$%s" % (salt.hex(), h.hex())


def check_pw(pw: str, stored: str) -> bool:
    try:
        _, n, r, p, salt, h = stored.split("$")
        got = hashlib.scrypt(pw.encode(), salt=bytes.fromhex(salt), n=int(n), r=int(r), p=int(p), dklen=32)
        return hmac.compare_digest(got.hex(), h)
    except Exception:
        return False


def new_token(cur, account_id: int) -> str:
    tok = secrets.token_urlsafe(32)
    cur.execute("INSERT INTO tokens(token_hash, account_id, expires_at) VALUES (%s, %s, now() + %s * interval '1 second')",
                (hashlib.sha256(tok.encode()).digest(), account_id, TOKEN_TTL))
    cur.execute("DELETE FROM tokens WHERE expires_at < now()")
    return tok


def account_of(cur, tok: str):
    if not tok:
        return None
    cur.execute("SELECT a.id, a.username FROM tokens t JOIN accounts a ON a.id = t.account_id "
                "WHERE t.token_hash = %s AND t.expires_at > now()", (hashlib.sha256(tok.encode()).digest(),))
    return cur.fetchone()


# ограничение частоты входов: не больше 10 попыток в минуту с адреса
_attempts = {}
_attempts_lock = threading.Lock()


def rate_ok(ip: str) -> bool:
    now = time.time()
    with _attempts_lock:
        lst = [t for t in _attempts.get(ip, []) if now - t < 60]
        if len(lst) >= 10:
            _attempts[ip] = lst
            return False
        lst.append(now)
        _attempts[ip] = lst
        if len(_attempts) > 5000:
            _attempts.clear()
    return True


def valid_new_character(d) -> str:
    if not isinstance(d, dict):
        return "нет данных героя"
    name = str(d.get("name", "")).strip()
    if not (2 <= len(name) <= 20):
        return "имя героя: 2–20 символов"
    if d.get("class") not in CLASSES:
        return "неизвестный класс"
    if int(d.get("level", 1)) != 1 or int(d.get("xp", 0)) != 0 or int(d.get("gold", 0)) > 100:
        return "новый герой должен быть 1 уровня"
    if len(d.get("inventory", [])) > 10 or len(d.get("stash", [])) > 0:
        return "лишние предметы у нового героя"
    return ""


def valid_save(old: dict, new: dict) -> str:
    """Серверная проверка сохранения: нельзя «накрутить» уровень/золото скачком."""
    if not isinstance(new, dict):
        return "bad data"
    if new.get("class") != old.get("class"):
        return "class changed"
    if int(new.get("level", 1)) > int(old.get("level", 1)) + 5:
        return "level jump"
    if int(new.get("gold", 0)) > int(old.get("gold", 0)) + 200000:
        return "gold jump"
    if len(json.dumps(new)) > MAX_BODY:
        return "too big"
    return ""


class Handler(BaseHTTPRequestHandler):
    internal = False
    server_version = "OskolkiAuth/0.7"
    protocol_version = "HTTP/1.1"
    timeout = 20

    def setup(self):
        super().setup()
        if isinstance(self.request, ssl.SSLSocket):
            self.request.do_handshake()   # рукопожатие TLS — в потоке запроса, а не в accept()

    def log_message(self, fmt, *args):
        pass  # без логов с паролями/токенами

    def _send(self, code: int, obj):
        body = json.dumps(obj, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _body(self):
        n = int(self.headers.get("Content-Length", "0") or 0)
        if n <= 0:
            return {}
        if n > MAX_BODY:
            raise ValueError("слишком большой запрос")
        return json.loads(self.rfile.read(n).decode() or "{}")

    def _bearer(self):
        a = self.headers.get("Authorization", "")
        return a[7:].strip() if a.startswith("Bearer ") else ""

    def _route(self, method: str):
        try:
            path = self.path.split("?")[0].rstrip("/")
            if self.internal:
                if not INTERNAL_KEY or not hmac.compare_digest(self.headers.get("X-Internal-Key", ""), INTERNAL_KEY):
                    return self._send(403, {"error": "forbidden"})
                return self._internal(method, path)
            return self._public(method, path)
        except ValueError as e:
            return self._send(400, {"error": str(e)})
        except Exception as e:  # noqa
            print("error:", type(e).__name__, e, flush=True)
            return self._send(500, {"error": "внутренняя ошибка сервера"})

    def do_GET(self): self._route("GET")
    def do_POST(self): self._route("POST")
    def do_PUT(self): self._route("PUT")
    def do_DELETE(self): self._route("DELETE")

    # ---------- для игроков ----------
    def _public(self, method, path):
        ip = self.client_address[0]
        if path == "/api/health":
            return self._send(200, {"ok": True, "version": "0.7.0"})
        if method == "POST" and path in ("/api/register", "/api/login"):
            if not rate_ok(ip):
                return self._send(429, {"error": "слишком много попыток, подождите минуту"})
            b = self._body()
            user = str(b.get("username", "")).strip()
            pw = str(b.get("password", ""))
            if not USER_RE.match(user):
                return self._send(400, {"error": "логин: 3–20 букв, цифр, _ или -"})
            if not (6 <= len(pw) <= 128):
                return self._send(400, {"error": "пароль: от 6 до 128 символов"})
            if path == "/api/register":
                def reg(cur):
                    cur.execute("SELECT 1 FROM accounts WHERE username_lc = %s", (user.lower(),))
                    if cur.fetchone():
                        return None
                    cur.execute("INSERT INTO accounts(username, username_lc, pw_hash, last_login) VALUES (%s, %s, %s, now()) RETURNING id",
                                (user, user.lower(), hash_pw(pw)))
                    return new_token(cur, cur.fetchone()[0])
                tok = db(reg)
                if tok is None:
                    return self._send(409, {"error": "такой логин уже занят"})
                return self._send(200, {"token": tok, "username": user})
            def login(cur):
                cur.execute("SELECT id, username, pw_hash FROM accounts WHERE username_lc = %s", (user.lower(),))
                row = cur.fetchone()
                if not row or not check_pw(pw, row[2]):
                    return None
                cur.execute("UPDATE accounts SET last_login = now() WHERE id = %s", (row[0],))
                return (new_token(cur, row[0]), row[1])
            r = db(login)
            if r is None:
                return self._send(401, {"error": "неверный логин или пароль"})
            return self._send(200, {"token": r[0], "username": r[1]})
        tok = self._bearer()
        acc = db(lambda cur: account_of(cur, tok))
        if acc is None:
            return self._send(401, {"error": "нужно войти заново"})
        aid, uname = acc
        if method == "POST" and path == "/api/logout":
            db(lambda cur: cur.execute("DELETE FROM tokens WHERE token_hash = %s", (hashlib.sha256(tok.encode()).digest(),)))
            return self._send(200, {"ok": True})
        if method == "GET" and path == "/api/me":
            return self._send(200, {"username": uname})
        if method == "GET" and path == "/api/characters":
            rows = db(lambda cur: (cur.execute("SELECT id, data FROM characters WHERE account_id = %s ORDER BY id", (aid,)), cur.fetchall())[1])
            out = []
            for cid, data in rows:
                data["id"] = "n%d" % cid
                out.append(data)
            return self._send(200, {"characters": out, "username": uname})
        if method == "POST" and path == "/api/characters":
            d = self._body().get("data")
            err = valid_new_character(d)
            if err:
                return self._send(400, {"error": err})
            def create(cur):
                cur.execute("SELECT count(*) FROM characters WHERE account_id = %s", (aid,))
                if cur.fetchone()[0] >= MAX_CHARS:
                    return None
                cur.execute("INSERT INTO characters(account_id, name, data) VALUES (%s, %s, %s) RETURNING id",
                            (aid, str(d["name"]).strip(), Json(d)))
                cid = cur.fetchone()[0]
                d["id"] = "n%d" % cid
                cur.execute("UPDATE characters SET data = %s WHERE id = %s", (Json(d), cid))
                return d
            r = db(create)
            if r is None:
                return self._send(400, {"error": "все слоты заняты"})
            return self._send(200, {"character": r})
        m = re.match(r"^/api/characters/n(\d+)$", path)
        if method == "DELETE" and m:
            cid = int(m.group(1))
            n = db(lambda cur: (cur.execute("DELETE FROM characters WHERE id = %s AND account_id = %s", (cid, aid)), cur.rowcount)[1])
            return self._send(200 if n else 404, {"ok": bool(n)})
        return self._send(404, {"error": "нет такого метода"})

    # ---------- для игрового сервера ----------
    def _internal(self, method, path):
        if method == "POST" and path == "/internal/session":
            b = self._body()
            tok = str(b.get("token", ""))
            m = re.match(r"^n(\d+)$", str(b.get("char_id", "")))
            if not m:
                return self._send(400, {"error": "bad char"})
            cid = int(m.group(1))
            def sess(cur):
                acc = account_of(cur, tok)
                if acc is None:
                    return None
                cur.execute("SELECT data FROM characters WHERE id = %s AND account_id = %s", (cid, acc[0]))
                row = cur.fetchone()
                if not row:
                    return None
                d = row[0]; d["id"] = "n%d" % cid
                return {"account_id": acc[0], "username": acc[1], "character": d}
            r = db(sess)
            if r is None:
                return self._send(401, {"error": "bad session"})
            return self._send(200, r)
        m = re.match(r"^/internal/characters/n(\d+)$", path)
        if method == "PUT" and m:
            cid = int(m.group(1))
            b = self._body()
            new = b.get("data")
            aid = int(b.get("account_id", 0))
            def save(cur):
                cur.execute("SELECT data FROM characters WHERE id = %s AND account_id = %s FOR UPDATE", (cid, aid))
                row = cur.fetchone()
                if not row:
                    return "no character"
                err = valid_save(row[0], new)
                if err:
                    return err
                new["id"] = "n%d" % cid
                cur.execute("UPDATE characters SET data = %s, name = %s, updated_at = now() WHERE id = %s",
                            (Json(new), str(new.get("name", ""))[:20], cid))
                return ""
            err = db(save)
            return self._send(200 if not err else 400, {"ok": not err, "error": err})
        return self._send(404, {"error": "not found"})


class InternalHandler(Handler):
    internal = True


def main():
    db(lambda cur: cur.execute(SCHEMA))
    pub = ThreadingHTTPServer(("0.0.0.0", PUBLIC_PORT), Handler)
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.minimum_version = ssl.TLSVersion.TLSv1_2
    ctx.load_cert_chain(CERT, KEY)
    pub.socket = ctx.wrap_socket(pub.socket, server_side=True, do_handshake_on_connect=False)
    pub.daemon_threads = True
    internal = ThreadingHTTPServer(("127.0.0.1", INTERNAL_PORT), InternalHandler)
    internal.daemon_threads = True
    threading.Thread(target=internal.serve_forever, daemon=True).start()
    print("auth: https :%d, internal 127.0.0.1:%d" % (PUBLIC_PORT, INTERNAL_PORT), flush=True)
    pub.serve_forever()


if __name__ == "__main__":
    main()
