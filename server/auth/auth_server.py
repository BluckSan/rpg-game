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
CREATE TABLE IF NOT EXISTS market_listings (
  id BIGSERIAL PRIMARY KEY,
  seller_char BIGINT NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
  seller_name TEXT NOT NULL,
  item JSONB NOT NULL,
  item_uid TEXT NOT NULL,
  price BIGINT NOT NULL CHECK (price > 0),
  slot INT NOT NULL, cls TEXT NOT NULL, ilvl INT NOT NULL, rarity INT NOT NULL, set_id TEXT NOT NULL, name_lc TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'active',
  buyer_char BIGINT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX IF NOT EXISTS market_active ON market_listings(status, expires_at);
CREATE INDEX IF NOT EXISTS market_seller ON market_listings(seller_char, status);
CREATE UNIQUE INDEX IF NOT EXISTS market_uid_active ON market_listings(item_uid) WHERE status = 'active';
CREATE TABLE IF NOT EXISTS market_mail (
  id BIGSERIAL PRIMARY KEY,
  char_id BIGINT NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
  kind TEXT NOT NULL,
  gold BIGINT NOT NULL DEFAULT 0,
  item JSONB,
  note TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  claimed BOOLEAN NOT NULL DEFAULT false
);
CREATE INDEX IF NOT EXISTS market_mail_char ON market_mail(char_id, claimed);
"""

# ---------- v0.9.2: рынок ----------
# Все операции — одной транзакцией вместе с записью героя (строки блокируются FOR UPDATE): предмет
# переходит атомарно; повтор/гонка запросов не дублирует ни вещь, ни золото.
MARKET_TTL_H = 48
MARKET_MAX_ACTIVE = 20
MARKET_TAX = 0.07           # налог с продажи (уходит из игры)
MARKET_PRICE_MAX = 50_000_000


def market_fee(price: int) -> int:
    """Плата за выставление (не возвращается): 2%, от 5 до 5000 золота."""
    return max(5, min(5000, int(round(price * 0.02))))


def market_sweep(cur):
    """Истёкшие лоты: вещь возвращается продавцу почтой."""
    cur.execute("UPDATE market_listings SET status = 'expired' WHERE status = 'active' AND expires_at < now() "
                "RETURNING seller_char, item")
    for ch, item in cur.fetchall():
        cur.execute("INSERT INTO market_mail(char_id, kind, item, note) VALUES (%s, 'expired', %s, %s)",
                    (ch, Json(item), "Срок лота истёк: %s" % str(item.get("name", "предмет"))))


def lock_char(cur, cid: int, aid: int):
    cur.execute("SELECT data FROM characters WHERE id = %s AND account_id = %s FOR UPDATE", (cid, aid))
    row = cur.fetchone()
    return row[0] if row else None


def rev_ok(old: dict, new: dict) -> bool:
    return int(new.get("_rev", 0)) > int(old.get("_rev", 0))


def write_char(cur, cid: int, new: dict):
    new["id"] = "n%d" % cid
    cur.execute("UPDATE characters SET data = %s, updated_at = now() WHERE id = %s", (Json(new), cid))


def uids(data: dict):
    out = set()
    for k in ("inventory", "equipped", "stash"):
        for it in data.get(k, []) or []:
            if isinstance(it, dict):
                out.add(str(it.get("uid", "")))
    return out


def listing_pub(r):
    return {"id": r[0], "seller": r[1], "item": r[2], "price": int(r[3]), "expires": r[4].isoformat(), "status": r[5]}


LIST_COLS = "id, seller_name, item, price, expires_at, status"


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
    if "_rev" in old and not rev_ok(old, new):
        return "stale"   # v0.9.2: устаревшее сохранение (после сделки на рынке) не перезаписывает героя
    return ""


class Handler(BaseHTTPRequestHandler):
    internal = False
    server_version = "OskolkiAuth/0.8"
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
            return self._send(200, {"ok": True, "version": "0.9.2"})
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
        if method == "POST" and path.startswith("/internal/market/"):
            return self._market(path[len("/internal/market/"):], self._body())
        return self._send(404, {"error": "not found"})

    def _market(self, op, b):
        cid_m = re.match(r"^n(\d+)$", str(b.get("char_id", "")))
        cid = int(cid_m.group(1)) if cid_m else 0
        aid = int(b.get("account_id", 0))
        if op == "search":
            f = b.get("filters", {}) or {}
            def search(cur):
                market_sweep(cur)
                q = "SELECT " + LIST_COLS + " FROM market_listings WHERE status = 'active'"
                a = []
                if f.get("slot", -1) not in (-1, None, ""):
                    q += " AND slot = %s"; a.append(int(f["slot"]))
                if f.get("cls"):
                    q += " AND (cls = %s OR cls = '')"; a.append(str(f["cls"])[:12])
                if f.get("lvl_min"):
                    q += " AND ilvl >= %s"; a.append(int(f["lvl_min"]))
                if f.get("lvl_max"):
                    q += " AND ilvl <= %s"; a.append(int(f["lvl_max"]))
                if f.get("rarity", -1) not in (-1, None, ""):
                    q += " AND rarity = %s"; a.append(int(f["rarity"]))
                if f.get("set_only"):
                    q += " AND set_id <> ''"
                if f.get("text"):
                    q += " AND name_lc LIKE %s"; a.append("%" + str(f["text"]).lower()[:40].replace("%", "") + "%")
                if f.get("mine"):
                    q += " AND seller_char = %s"; a.append(cid)
                q += {"price": " ORDER BY price ASC", "price_desc": " ORDER BY price DESC", "level": " ORDER BY ilvl DESC"}.get(str(f.get("sort", "")), " ORDER BY id DESC")
                q += " LIMIT %s OFFSET %s"; a += [min(60, int(f.get("limit", 40))), max(0, int(f.get("offset", 0)))]
                cur.execute(q, a)
                return [listing_pub(r) for r in cur.fetchall()]
            return self._send(200, {"ok": True, "list": db(search)})
        if op == "get":
            r = db(lambda cur: (market_sweep(cur), cur.execute("SELECT " + LIST_COLS + ", seller_char FROM market_listings WHERE id = %s", (int(b.get("id", 0)),)), cur.fetchone())[2])
            if not r:
                return self._send(404, {"ok": False, "error": "лот не найден"})
            d = listing_pub(r); d["seller_char"] = "n%d" % r[6]
            return self._send(200, {"ok": True, "listing": d})
        if op == "mine":
            def mine(cur):
                market_sweep(cur)
                cur.execute("SELECT " + LIST_COLS + " FROM market_listings WHERE seller_char = %s AND status = 'active' ORDER BY id DESC", (cid,))
                lst = [listing_pub(r) for r in cur.fetchall()]
                cur.execute("SELECT id, kind, gold, item, note FROM market_mail WHERE char_id = %s AND NOT claimed ORDER BY id", (cid,))
                mail = [{"id": r[0], "kind": r[1], "gold": int(r[2]), "item": r[3], "note": r[4]} for r in cur.fetchall()]
                return {"ok": True, "list": lst, "mail": mail}
            return self._send(200, db(mine))
        new = b.get("data")
        if op == "list":
            item = b.get("item"); price = int(b.get("price", 0))
            if not isinstance(item, dict) or not isinstance(new, dict) or not (1 <= price <= MARKET_PRICE_MAX):
                return self._send(400, {"ok": False, "error": "неверный лот"})
            uid = str(item.get("uid", ""))
            def lst(cur):
                old = lock_char(cur, cid, aid)
                if old is None: return "нет героя"
                if not rev_ok(old, new): return "stale"
                if uid == "" or uid not in uids(old) or uid in uids(new): return "предмета нет у героя"
                if int(old.get("gold", 0)) - int(new.get("gold", 0)) != market_fee(price): return "плата не списана"
                cur.execute("SELECT count(*) FROM market_listings WHERE seller_char = %s AND status = 'active'", (cid,))
                if cur.fetchone()[0] >= MARKET_MAX_ACTIVE: return "не больше %d лотов" % MARKET_MAX_ACTIVE
                cur.execute("SELECT 1 FROM market_listings WHERE item_uid = %s AND status = 'active'", (uid,))
                if cur.fetchone(): return "предмет уже выставлен"
                cur.execute("INSERT INTO market_listings(seller_char, seller_name, item, item_uid, price, slot, cls, ilvl, rarity, set_id, name_lc, expires_at) "
                            "VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s, now() + %s * interval '1 hour') RETURNING id",
                            (cid, str(old.get("name", "?"))[:20], Json(item), uid, price, int(item.get("slot", 0)), str(item.get("cls", "")),
                             int(item.get("ilvl", 1)), int(item.get("rarity", 0)), str(item.get("set", "")), str(item.get("name", "")).lower()[:60], MARKET_TTL_H))
                lid = cur.fetchone()[0]
                write_char(cur, cid, new)
                return lid
            r = db(lst)
            return self._send(200 if isinstance(r, int) else 400, {"ok": isinstance(r, int), "id": r if isinstance(r, int) else 0, "error": "" if isinstance(r, int) else r})
        if op == "buy":
            lid = int(b.get("id", 0))
            def buy(cur):
                market_sweep(cur)
                cur.execute("SELECT seller_char, item, price, item_uid FROM market_listings WHERE id = %s AND status = 'active' FOR UPDATE", (lid,))
                row = cur.fetchone()
                if not row: return "лот уже продан или снят"
                seller, item, price, uid = row
                if seller == cid: return "это ваш лот"
                old = lock_char(cur, cid, aid)
                if old is None: return "нет героя"
                if not isinstance(new, dict) or not rev_ok(old, new): return "stale"
                if uid in uids(old) or uid not in uids(new): return "предмет не передан"
                if int(old.get("gold", 0)) - int(new.get("gold", 0)) != int(price): return "цена не совпадает"
                if int(new.get("gold", 0)) < 0: return "не хватает золота"
                cur.execute("UPDATE market_listings SET status = 'sold', buyer_char = %s WHERE id = %s", (cid, lid))
                net = int(price) - int(round(int(price) * MARKET_TAX))
                cur.execute("INSERT INTO market_mail(char_id, kind, gold, note) VALUES (%s, 'sold', %s, %s)",
                            (seller, net, "Продано: %s за %d (налог %d)" % (str(item.get("name", "")), int(price), int(price) - net)))
                write_char(cur, cid, new)
                return ""
            err = db(buy)
            return self._send(200 if not err else 400, {"ok": not err, "error": err})
        if op == "cancel":
            lid = int(b.get("id", 0))
            def cancel(cur):
                cur.execute("UPDATE market_listings SET status = 'cancelled' WHERE id = %s AND seller_char = %s AND status = 'active' RETURNING item", (lid, cid))
                row = cur.fetchone()
                if not row: return "лот не найден"
                cur.execute("INSERT INTO market_mail(char_id, kind, item, note) VALUES (%s, 'cancelled', %s, %s)",
                            (cid, Json(row[0]), "Лот снят: %s" % str(row[0].get("name", ""))))
                return ""
            err = db(cancel)
            return self._send(200 if not err else 400, {"ok": not err, "error": err})
        if op == "claim":
            ids = [int(x) for x in (b.get("ids") or [])][:60]
            def claim(cur):
                old = lock_char(cur, cid, aid)
                if old is None: return "нет героя"
                if not isinstance(new, dict) or not rev_ok(old, new): return "stale"
                cur.execute("SELECT id, gold, item FROM market_mail WHERE char_id = %s AND NOT claimed AND id = ANY(%s) FOR UPDATE", (cid, ids))
                rows = cur.fetchall()
                if len(rows) != len(ids): return "почта уже получена"
                gold = sum(int(r[1]) for r in rows)
                if int(new.get("gold", 0)) - int(old.get("gold", 0)) != gold: return "золото не совпадает"
                have = uids(new)
                for r in rows:
                    if r[2] and str(r[2].get("uid", "")) not in have: return "предмет не получен"
                cur.execute("UPDATE market_mail SET claimed = true WHERE id = ANY(%s)", (ids,))
                write_char(cur, cid, new)
                return ""
            err = db(claim)
            return self._send(200 if not err else 400, {"ok": not err, "error": err})
        return self._send(404, {"ok": False, "error": "нет такой операции"})


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
