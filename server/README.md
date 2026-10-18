# Сервер онлайн-режима (v0.7.0)

- `auth/auth_server.py` — сервис аккаунтов: HTTPS :7780 (самоподписанный сертификат, CN `oskolki-auth`, клиент закрепляет `net/auth_cert.pem`), внутренний HTTP 127.0.0.1:7781 для игрового сервера. PostgreSQL (`accounts`, `tokens`, `characters`), пароли — scrypt, токены — 32 байта (в БД только SHA-256).
- Игровой сервер — тот же проект Godot: `godot --headless --main-pack oskolki-server.pck -- --server --port=7777` (ENet UDP, до 10 игроков). Пакет собирается пресетом «Linux Server»: `godot --headless --export-pack "Linux Server" build/server/oskolki-server.pck`.
- `deploy/` — юниты systemd (пользователь `rpg`, MemoryMax: игра 512M, аккаунты 160M, PostgreSQL 384M) и настройки PostgreSQL. Секреты (`/etc/rpg/key.pem`, `/etc/rpg/rpg.env` с `RPG_INTERNAL_KEY`) в репозиторий не входят.
- Порты: 7777/udp (игра), 7780/tcp (аккаунты); 7781 и 5432 — только localhost.
