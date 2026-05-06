#!/usr/bin/env bash
#
# wiki-thothlab / setup-vps.sh
# Добавить блок wiki.thothlab.tech в Caddyfile на VPS, валидировать, перезагрузить.
#
# Запускать на VPS под sudo (или root).
# Идемпотентный: повторный запуск заменяет блок, не дублирует.

set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/thothlab/wiki-thothlab/main"
DOMAIN="wiki.thothlab.tech"
WIKI_PORT_DEFAULT="3010"

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

# --- 0. права ---
if [ "$(id -u)" -ne 0 ]; then
    err "Запустите под sudo (или от root)."
    exit 1
fi
command -v caddy >/dev/null 2>&1 || { err "Caddy не установлен."; exit 1; }
[ -f /etc/caddy/Caddyfile ] || { err "/etc/caddy/Caddyfile не найден."; exit 1; }

WIKI_PORT=$(ask "Порт wiki.js на VPS (через туннель)" "$WIKI_PORT_DEFAULT")

# --- 1. собрать блок ---
BLOCK=$(cat <<EOF
# >>> wiki-thothlab >>>
${DOMAIN} {
    encode zstd gzip
    reverse_proxy 127.0.0.1:${WIKI_PORT} {
        header_up X-Real-IP {remote_host}
    }
}
# <<< wiki-thothlab <<<
EOF
)

# --- 2. вставить в Caddyfile ---
CFG=/etc/caddy/Caddyfile
BACKUP="${CFG}.backup-$(date +%Y%m%d-%H%M%S)"
cp -p "$CFG" "$BACKUP"
ok "Бэкап: $BACKUP"

BLOCK="$BLOCK" CFG="$CFG" python3 - <<'PY'
import os, re, pathlib
path = os.environ["CFG"]
block = os.environ["BLOCK"].rstrip("\n") + "\n"
text = pathlib.Path(path).read_text()
text = re.sub(r"# >>> wiki-thothlab >>>.*?# <<< wiki-thothlab <<<\n?",
              "", text, flags=re.DOTALL)
if not text.endswith("\n"):
    text += "\n"
text += "\n" + block
pathlib.Path(path).write_text(text)
print(f"OK: блок вставлен в {path}")
PY

# --- 3. валидация ---
say "Валидирую конфиг..."
if ! caddy validate --config "$CFG" --adapter caddyfile 2>&1; then
    err "Конфиг невалиден. Откатываюсь к ${BACKUP}."
    cp -p "$BACKUP" "$CFG"
    exit 1
fi
ok "Конфиг валиден."

# --- 4. reload ---
say "systemctl reload caddy..."
systemctl reload caddy
sleep 2
if ! systemctl is-active --quiet caddy; then
    err "Caddy не запущен. Откатываюсь к ${BACKUP}."
    cp -p "$BACKUP" "$CFG"
    systemctl reload caddy || true
    exit 1
fi
ok "Caddy перезагружен."

# --- 5. локальный смоук-тест ---
say "Локальный тест: Caddy → 127.0.0.1:${WIKI_PORT}..."
if curl -fsS -o /dev/null -w "%{http_code}\n" -H "Host: ${DOMAIN}" "http://127.0.0.1" 2>/dev/null | grep -qE '^(200|302|308)$'; then
    ok "Caddy отвечает локально."
else
    warn "Caddy локально не отвечает на ${DOMAIN}. Проверьте: туннель с Mac Mini поднят? curl -I http://127.0.0.1:${WIKI_PORT}"
fi

cat <<EOF

${C_BOLD}Готово на VPS.${C_RESET}

Осталось:
  1. У регистратора thothlab.tech: A-запись ${C_BOLD}${DOMAIN}${C_RESET} → 153.80.185.242
  2. После пропагации DNS — открыть https://${DOMAIN}
     (Caddy сам получит TLS-сертификат при первом запросе)

Проверка DNS:    dig +short ${DOMAIN}
Логи Caddy:      journalctl -u caddy -f
Логи домена:     tail -f /var/log/caddy/${DOMAIN}.log

EOF
