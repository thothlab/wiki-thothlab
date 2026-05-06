#!/usr/bin/env bash
#
# wiki-thothlab / setup-mac.sh
# Поднять стек wiki.js + postgres на Mac Mini.
#
# Идемпотентный: повторный запуск не ломает существующий .env.

set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/thothlab/wiki-thothlab/main"

if [ -t 1 ]; then
    C_RESET='\033[0m'; C_BOLD='\033[1m'
    C_RED='\033[31m'; C_GREEN='\033[32m'; C_YELLOW='\033[33m'; C_BLUE='\033[34m'
else
    C_RESET=''; C_BOLD=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''
fi
say()  { printf "${C_BLUE}[i]${C_RESET} %s\n" "$*"; }
ok()   { printf "${C_GREEN}[+]${C_RESET} %s\n" "$*"; }
warn() { printf "${C_YELLOW}[!]${C_RESET} %s\n" "$*"; }
err()  { printf "${C_RED}[x]${C_RESET} %s\n" "$*" >&2; }
ask()  { local p="$1" d="${2-}" v; if [ -n "$d" ]; then read -r -p "$p [$d]: " v; echo "${v:-$d}"; else read -r -p "$p: " v; echo "$v"; fi; }

# --- 0. sanity ---
[ "$(uname -s)" = "Darwin" ] || warn "Скрипт рассчитан на macOS (Mac Mini), но запущен на $(uname -s). Продолжаем на свой страх и риск."

if ! command -v docker >/dev/null 2>&1; then
    err "Не найден docker. Установите Docker Desktop: https://docs.docker.com/desktop/install/mac-install/"
    exit 1
fi
if ! docker compose version >/dev/null 2>&1; then
    err "Не найден 'docker compose' (v2). Обновите Docker Desktop."
    exit 1
fi
if ! docker info >/dev/null 2>&1; then
    err "Docker daemon недоступен. Запустите Docker Desktop и попробуйте снова."
    exit 1
fi

# --- 1. Где будет проект ---
DEFAULT_DIR="$HOME/Documents/Projects/wiki-thothlab"
PROJECT_DIR=$(ask "Куда поставить wiki-thothlab?" "$DEFAULT_DIR")
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"

# Если репо ещё не клонирован — клонируем; если файлы уже на месте, ничего не делаем.
if [ ! -f compose/docker-compose.yml ]; then
    if [ -d .git ]; then
        warn "Папка под git, но compose/docker-compose.yml не найден — необычно. Продолжаю и докачаю файлы."
    fi
    say "Скачиваю файлы репозитория..."
    if command -v git >/dev/null 2>&1; then
        if [ ! -d .git ]; then
            git clone --depth 1 https://github.com/thothlab/wiki-thothlab.git .
        fi
    else
        mkdir -p compose caddy
        curl -fsSL "${REPO_RAW}/compose/docker-compose.yml" -o compose/docker-compose.yml
        curl -fsSL "${REPO_RAW}/compose/.env.example"      -o compose/.env.example
        curl -fsSL "${REPO_RAW}/caddy/wiki.thothlab.tech.caddy" -o caddy/wiki.thothlab.tech.caddy
    fi
    ok "Файлы готовы."
else
    ok "Файлы репозитория уже на месте."
fi

cd "$PROJECT_DIR/compose"

# --- 2. .env ---
if [ ! -f .env ]; then
    say "Создаю .env из .env.example..."
    cp .env.example .env
    PASS=$(openssl rand -base64 32 | tr -d '/+=' | cut -c1-32)
    # Замена POSTGRES_PASSWORD
    if [ "$(uname -s)" = "Darwin" ]; then
        sed -i '' "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=${PASS}|" .env
    else
        sed -i "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=${PASS}|" .env
    fi
    chmod 600 .env
    ok "Сгенерирован POSTGRES_PASSWORD (длина 32, файл .env: 600)."
else
    ok ".env уже существует — оставляю без изменений."
    if grep -q '^POSTGRES_PASSWORD=CHANGE_ME' .env; then
        warn "В .env всё ещё CHANGE_ME — отредактируйте вручную и перезапустите."
        exit 1
    fi
fi

# --- 3. compose up ---
say "Запускаю docker compose up -d..."
docker compose up -d

# --- 4. ждём healthy ---
say "Жду готовности wiki.js (до 90 сек)..."
WIKI_PORT=$(grep -E '^WIKI_HOST_PORT=' .env | cut -d= -f2)
WIKI_PORT="${WIKI_PORT:-3010}"

for i in $(seq 1 30); do
    if curl -fsS -o /dev/null -w "%{http_code}" "http://127.0.0.1:${WIKI_PORT}" 2>/dev/null | grep -qE '^(200|302)$'; then
        ok "Wiki.js отвечает на http://127.0.0.1:${WIKI_PORT}"
        break
    fi
    sleep 3
    [ "$i" = "30" ] && warn "Wiki.js ещё не отвечает. Проверьте: docker compose logs wiki"
done

cat <<EOF

${C_BOLD}Готово на Mac Mini.${C_RESET}

Дальше:

  1. На этом же Mac Mini: ${C_BOLD}./install.sh${C_RESET} → пункт 2 (туннель)
  2. На VPS под root/sudo:   ${C_BOLD}./install.sh${C_RESET} → пункт 3 (Caddy)
  3. У регистратора DNS:     A-запись wiki.thothlab.tech → 153.80.185.242

Локальный URL:  http://127.0.0.1:${WIKI_PORT}
Папка проекта:  ${PROJECT_DIR}

EOF
