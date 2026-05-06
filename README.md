# wiki-thothlab

Self-hosted [Wiki.js](https://js.wiki/) на домашнем сервере (Mac Mini),
доступный снаружи как **https://wiki.thothlab.tech**.

Архитектура:

```
браузер ──TLS──▶ Caddy (VPS, 153.80.185.242) ──reverse SSH tunnel──▶ Mac Mini
                                                                        └─ docker compose
                                                                            ├─ wiki.js (127.0.0.1:3010)
                                                                            └─ postgres
```

Внешний доступ идёт через тот же reverse SSH-туннель, что и остальные домашние
сервисы — см. [`thothlab/self-hosted-tunnel`](https://github.com/thothlab/self-hosted-tunnel).

---

## Состав репозитория

```
wiki-thothlab/
├── install.sh                    # меню-лаунчер (точка входа)
├── setup-mac.sh                  # на Mac Mini: docker stack
├── setup-tunnel.sh               # на Mac Mini: RemoteForward в ~/.ssh/config
├── setup-vps.sh                  # на VPS: блок в /etc/caddy/Caddyfile
├── compose/
│   ├── docker-compose.yml        # wiki.js + postgres
│   └── .env.example              # шаблон секретов
├── caddy/
│   └── wiki.thothlab.tech.caddy  # сниппет для VPS (исходник)
├── .gitignore
├── LICENSE                       # MIT
└── README.md
```

`postgres/` (данные БД) и `compose/.env` (секреты) **не коммитятся**.

---

## Развёртывание (рекомендуемый путь)

Один и тот же `install.sh` запускается на двух разных устройствах и сам определяет, что делать.

### Mac Mini

```bash
wget -qO install.sh https://raw.githubusercontent.com/thothlab/wiki-thothlab/main/install.sh
chmod +x install.sh
./install.sh   # → пункт 1 (docker stack)
./install.sh   # → пункт 2 (RemoteForward через self-hosted-tunnel)
```

Скрипты идемпотентны: повторный запуск не ломает уже настроенное (`.env` сохраняется, блок маркеров `# >>> wiki-thothlab >>>` … `# <<< wiki-thothlab <<<` заменяется целиком).

### VPS (под root/sudo)

```bash
wget -qO install.sh https://raw.githubusercontent.com/thothlab/wiki-thothlab/main/install.sh
sudo bash install.sh   # → пункт 3 (Caddy)
```

Caddy сам получит TLS-сертификат через Let's Encrypt при первом запросе — после того как DNS будет указывать на VPS.

### DNS (вручную, у регистратора)

```
wiki.thothlab.tech.   A   153.80.185.242
```

Открыть https://wiki.thothlab.tech — должна появиться форма создания админа Wiki.js.

---

## Развёртывание (вручную, без install.sh)

Если хочется делать руками, шаги те же:

1. **Mac Mini, docker:** `cd compose && cp .env.example .env`, сгенерировать `POSTGRES_PASSWORD` (`openssl rand -base64 32`), `docker compose up -d`.
2. **Mac Mini, туннель:** в `~/.ssh/config` в Host-блоке VPS добавить `RemoteForward 3010 127.0.0.1:3010`, перезапустить autossh (`launchctl kickstart -k gui/$(id -u)/<label>`).
3. **DNS:** A-запись `wiki.thothlab.tech` → `153.80.185.242`.
4. **VPS, Caddy:** скопировать `caddy/wiki.thothlab.tech.caddy` в `/etc/caddy/Caddyfile` (или импортнуть), `sudo systemctl reload caddy`.

Подробности — в самих скриптах (`setup-mac.sh`, `setup-tunnel.sh`, `setup-vps.sh`).

---

## Обновление

```bash
cd ~/Documents/Projects/wiki-thothlab/compose
docker compose pull
docker compose up -d
```

`ghcr.io/requarks/wiki:2` — стабильный major-tag, апдейтится в рамках 2.x.

---

## Бэкап

Постгрес-том лежит в `~/Documents/Projects/wiki-thothlab/postgres/`.
Минимальный бэкап:

```bash
docker exec wiki-thothlab-postgres \
  pg_dump -U wikijs -d wiki -Fc -f /tmp/wiki.dump
docker cp wiki-thothlab-postgres:/tmp/wiki.dump ./wiki-$(date +%F).dump
```

---

## Лицензия

MIT — см. [LICENSE](LICENSE).
