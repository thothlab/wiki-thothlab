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
├── compose/
│   ├── docker-compose.yml      # wiki.js + postgres
│   └── .env.example            # шаблон секретов
├── caddy/
│   └── wiki.thothlab.tech.caddy  # сниппет для VPS
├── .gitignore
├── LICENSE                       # MIT
└── README.md
```

`postgres/` (данные БД) и `compose/.env` (секреты) **не коммитятся**.

---

## Развёртывание

Развёртывание состоит из четырёх независимых шагов на трёх машинах. Делать в любом порядке, но Wiki будет доступен только когда выполнены все четыре.

### 1. Mac Mini — поднять стек

```bash
cd ~/Documents/Projects/wiki-thothlab/compose
cp .env.example .env
# отредактируйте .env — обязательно сгенерируйте POSTGRES_PASSWORD:
#   openssl rand -base64 32
docker compose up -d
docker compose logs -f wiki   # дождаться "HTTP Server: [ ready ]"
```

Проверка: `curl -I http://127.0.0.1:3010` должен вернуть `200 OK` (после первой инициализации Wiki.js — редирект на `/login`).

### 2. Mac Mini → VPS — добавить порт в reverse SSH-туннель

В `~/.ssh/config` на Mac Mini, в блоке host'а VPS (между маркерами `# >>> self-hosted-tunnel >>>` … `# <<< self-hosted-tunnel <<<`) добавить:

```sshconfig
RemoteForward 3010 127.0.0.1:3010
```

Затем перезапустить autossh:

```bash
launchctl kickstart -k gui/$(id -u)/com.shaukat.autossh.tunnel
```

Проверка с VPS: `ssh admin@vps 'curl -I http://127.0.0.1:3010'` → `200 OK`.

### 3. DNS — A-запись

У регистратора `thothlab.tech` создать:

```
wiki.thothlab.tech.   A   153.80.185.242
```

Проверка: `dig +short wiki.thothlab.tech` → `153.80.185.242`.

### 4. VPS — Caddy

```bash
ssh admin@vps
sudo install -m 644 wiki.thothlab.tech.caddy /etc/caddy/conf.d/   # если используется conf.d
# или вручную добавить содержимое в /etc/caddy/Caddyfile
sudo caddy validate --config /etc/caddy/Caddyfile
sudo systemctl reload caddy
```

Caddy сам получит TLS-сертификат через Let's Encrypt при первом запросе.

Открыть https://wiki.thothlab.tech — должна появиться форма создания админа Wiki.js.

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
