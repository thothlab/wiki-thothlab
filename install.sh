#!/usr/bin/env bash
#
# wiki-thothlab: установка Wiki.js на Mac Mini + публикация через VPS
#
# Использование:
#   wget -O install.sh https://raw.githubusercontent.com/thothlab/wiki-thothlab/main/install.sh
#   chmod +x install.sh
#   ./install.sh

set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/thothlab/wiki-thothlab/main"

if [ -t 1 ]; then
    C_RESET='\033[0m'; C_BOLD='\033[1m'
    C_RED='\033[31m'; C_GREEN='\033[32m'; C_YELLOW='\033[33m'
    C_BLUE='\033[34m'; C_CYAN='\033[36m'
else
    C_RESET=''; C_BOLD=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_CYAN=''
fi

say()  { printf "${C_BLUE}[i]${C_RESET} %s\n" "$*"; }
ok()   { printf "${C_GREEN}[+]${C_RESET} %s\n" "$*"; }
warn() { printf "${C_YELLOW}[!]${C_RESET} %s\n" "$*"; }
err()  { printf "${C_RED}[x]${C_RESET} %s\n" "$*" >&2; }

banner() {
    printf "\n${C_BOLD}${C_CYAN}"
    cat <<'EOF'
╔══════════════════════════════════════════════════════════════════╗
║                                                                  ║
║     wiki-thothlab                                                ║
║     Self-hosted Wiki.js → https://wiki.thothlab.tech             ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝
EOF
    printf "${C_RESET}\n"
}

download_and_run() {
    local script="$1"; shift
    local tmp
    tmp=$(mktemp -t "${script%.sh}.XXXXXX")
    trap 'rm -f "$tmp"' EXIT

    say "Скачиваю ${script}..."
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "${REPO_RAW}/${script}" -o "$tmp"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp" "${REPO_RAW}/${script}"
    else
        err "Нужен curl или wget."
        exit 1
    fi

    chmod +x "$tmp"
    ok "Запускаю ${script}..."
    echo
    bash "$tmp" "$@"
}

menu() {
    cat <<EOF

${C_BOLD}Что вы хотите сделать?${C_RESET}

  ${C_BOLD}1)${C_RESET} Поднять стек на ${C_BOLD}Mac Mini${C_RESET} (docker compose: wiki.js + postgres)
  ${C_BOLD}2)${C_RESET} Прокинуть порт через reverse SSH-туннель (на ${C_BOLD}Mac Mini${C_RESET})
  ${C_BOLD}3)${C_RESET} Настроить ${C_BOLD}Caddy на VPS${C_RESET} (TLS + reverse proxy для wiki.thothlab.tech)
  ${C_BOLD}4)${C_RESET} Показать README в GitHub
  ${C_BOLD}q)${C_RESET} Выйти

EOF
}

detect_suggestion() {
    local uname_s id_u
    uname_s=$(uname -s 2>/dev/null || echo "?")
    id_u=$(id -u 2>/dev/null || echo "?")
    if [ "$uname_s" = "Linux" ] && [ "$id_u" = "0" ]; then
        echo "3"
    fi
}

main() {
    banner
    cat <<EOF
Этот мастер настроит Wiki.js на домашнем Mac Mini и опубликует его
наружу через reverse SSH-туннель + Caddy на VPS.

Полный порядок (на двух разных устройствах):

  ${C_BOLD}1.${C_RESET} На ${C_BOLD}Mac Mini${C_RESET}: пункт 1 (docker), затем пункт 2 (туннель)
  ${C_BOLD}2.${C_RESET} На ${C_BOLD}VPS${C_RESET} (под root/sudo): пункт 3 (Caddy)
  ${C_BOLD}3.${C_RESET} В DNS: A-запись wiki.thothlab.tech → 153.80.185.242 (вручную у регистратора)

EOF
    local suggestion
    suggestion=$(detect_suggestion)
    [ -n "$suggestion" ] && say "Похоже, вы на VPS — предлагаю пункт ${C_BOLD}${suggestion}${C_RESET}."

    while true; do
        menu
        local prompt="Ваш выбор"
        [ -n "$suggestion" ] && prompt="$prompt [${suggestion}]"
        read -r -p "$prompt: " choice
        [ -z "$choice" ] && choice="$suggestion"

        case "$choice" in
            1) download_and_run "setup-mac.sh"    "$@"; break ;;
            2) download_and_run "setup-tunnel.sh" "$@"; break ;;
            3) download_and_run "setup-vps.sh"    "$@"; break ;;
            4)
                echo "https://github.com/thothlab/wiki-thothlab#readme"
                exit 0
                ;;
            q|Q|quit|exit) exit 0 ;;
            *) warn "Неизвестный пункт: '${choice}'." ;;
        esac
    done
}

main "$@"
