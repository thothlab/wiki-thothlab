#!/usr/bin/env bash
#
# wiki-thothlab / setup-tunnel.sh
# Прокинуть порт wiki.js (3010) через существующий reverse SSH-туннель к VPS.
#
# Добавляет блок wiki-thothlab в ~/.ssh/config (между маркерами).
# Не конфликтует с self-hosted-tunnel — у нас свой маркер.

set -euo pipefail

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

[ "$(uname -s)" = "Darwin" ] || warn "Скрипт рассчитан на macOS (Mac Mini), а вы на $(uname -s)."

SSH_CFG="${HOME}/.ssh/config"
[ -f "$SSH_CFG" ] || { err "Не найден $SSH_CFG. Сначала настройте self-hosted-tunnel."; exit 1; }

# --- 1. найти Host alias к VPS, который использует autossh (предлагаем кандидатов) ---
# Важно: RemoteForward должен идти в Host alias autossh-туннеля (например, vps-tunnel),
# а НЕ в обычный Host vps — иначе каждое ручное `ssh vps` будет выдавать
# "Warning: remote port forwarding failed for listen port ...".
CANDIDATES=$(awk '/^Host [^*]/{for(i=2;i<=NF;i++)print $i}' "$SSH_CFG" | sort -u)
say "Хосты из ~/.ssh/config:"
echo "$CANDIDATES" | sed 's/^/   /'
DEFAULT_HOST="vps-tunnel"
echo "$CANDIDATES" | grep -qx "vps-tunnel" || \
    { echo "$CANDIDATES" | grep -qx "vps" && DEFAULT_HOST="vps"; } || \
    DEFAULT_HOST=$(echo "$CANDIDATES" | head -1)
VPS_HOST=$(ask "В какой Host alias добавить RemoteForward (используется autossh)?" "$DEFAULT_HOST")
grep -qE "^Host[[:space:]]+.*\b${VPS_HOST}\b" "$SSH_CFG" || { err "Host '${VPS_HOST}' не найден в $SSH_CFG"; exit 1; }

LOCAL_PORT=$(ask "Локальный порт wiki.js на Mac Mini" "3010")
REMOTE_PORT=$(ask "Тот же порт на VPS (обычно совпадает)" "$LOCAL_PORT")

# --- 2. вставить блок маркеров в ~/.ssh/config ---
BACKUP="${SSH_CFG}.backup-$(date +%Y%m%d-%H%M%S)"
cp -p "$SSH_CFG" "$BACKUP"
ok "Бэкап: $BACKUP"

python3 - "$SSH_CFG" "$VPS_HOST" "$LOCAL_PORT" "$REMOTE_PORT" <<'PY'
import re, sys, pathlib
path, vps_host, local_port, remote_port = sys.argv[1:5]
text = pathlib.Path(path).read_text()

block = f"""    # >>> wiki-thothlab >>>
    RemoteForward {remote_port} 127.0.0.1:{local_port}
    # <<< wiki-thothlab <<<
"""

# Удалить старый блок маркеров где бы он ни был
text = re.sub(r"[ \t]*# >>> wiki-thothlab >>>.*?# <<< wiki-thothlab <<<\n?",
              "", text, flags=re.DOTALL)

# Найти Host-блок с нужным именем и вставить блок в его конце
pattern = re.compile(r"(^Host[ \t]+[^\n]*\b" + re.escape(vps_host) + r"\b[^\n]*\n)", re.MULTILINE)
m = pattern.search(text)
if not m:
    sys.exit(f"Host '{vps_host}' не найден")

start = m.end()
# Конец Host-блока — следующая строка, начинающаяся не с пробела/таба, или конец файла
end = len(text)
for nm in re.finditer(r"^[^ \t\n]", text[start:], re.MULTILINE):
    end = start + nm.start()
    break

new_text = text[:end] + block + text[end:]
pathlib.Path(path).write_text(new_text)
print(f"OK: блок wiki-thothlab вставлен в Host '{vps_host}'")
PY

ok "~/.ssh/config обновлён."

# --- 3. перезапустить autossh, если запущен через launchctl ---
LABEL=$(launchctl list 2>/dev/null | awk '/autossh/ {print $3; exit}')
if [ -n "$LABEL" ]; then
    say "Перезапускаю autossh ($LABEL)..."
    launchctl kickstart -k "gui/$(id -u)/$LABEL" || warn "Не удалось kickstart $LABEL — перезапустите вручную."
    sleep 3
    ok "autossh перезапущен."
else
    warn "Не нашёл autossh в launchctl. Если туннель запущен иначе — перезапустите вручную."
fi

# --- 4. тест ---
say "Проверяю проброс через VPS..."
if ssh -o ConnectTimeout=10 -o BatchMode=yes "$VPS_HOST" \
       "curl -fsS -o /dev/null -w '%{http_code}' http://127.0.0.1:${REMOTE_PORT}" 2>/dev/null \
       | grep -qE '^(200|302)$'; then
    ok "Порт ${REMOTE_PORT} на VPS отвечает — туннель работает."
else
    warn "С VPS пока не получается дёрнуть http://127.0.0.1:${REMOTE_PORT}. Подождите 10–15 сек или проверьте вручную: ssh ${VPS_HOST} 'curl -I http://127.0.0.1:${REMOTE_PORT}'"
fi

cat <<EOF

${C_BOLD}Готово на Mac Mini.${C_RESET}

Дальше: на ${C_BOLD}VPS${C_RESET} под root/sudo запустите:
  ${C_BOLD}wget -qO- https://raw.githubusercontent.com/thothlab/wiki-thothlab/main/install.sh | bash${C_RESET}
и выберите пункт 3 (Caddy).

EOF
