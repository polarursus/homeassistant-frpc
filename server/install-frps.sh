#!/usr/bin/env bash
# Menu-driven installer for the frp server (frps).
# Run without arguments: it asks one question at a time and remembers
# your previous answers, so repeat runs are mostly pressing Enter.
set -euo pipefail

FRP_REPO="fatedier/frp"
FALLBACK_VERSION="0.70.1"
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/frp"
CONFIG_FILE="${CONFIG_DIR}/frps.toml"
STATE_FILE="${CONFIG_DIR}/.install-state"
SERVICE_NAME="frps"
UNIT_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
SERVICE_USER="frps"

if [[ -t 1 ]]; then
    B=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GREEN=$'\033[32m'
    YELLOW=$'\033[33m'; RESET=$'\033[0m'
else
    B=""; DIM=""; RED=""; GREEN=""; YELLOW=""; RESET=""
fi

info()  { printf '%s\n' "$*"; }
good()  { printf '%s%s%s\n' "$GREEN" "$*" "$RESET"; }
warn()  { printf '%s%s%s\n' "$YELLOW" "$*" "$RESET"; }
die()   { printf '%s%s%s\n' "$RED" "$*" "$RESET" >&2; exit 1; }
title() { printf '\n%s%s%s\n' "$B" "$*" "$RESET"; }

# ---------------------------------------------------------------- prompting --

ask() {
    local prompt="$1" default="${2:-}" reply
    if [[ -n "$default" ]]; then
        read -r -p "  ${prompt} [${default}]: " reply
        printf '%s' "${reply:-$default}"
    else
        while :; do
            read -r -p "  ${prompt}: " reply
            [[ -n "$reply" ]] && break
            printf '  a value is required\n' >&2
        done
        printf '%s' "$reply"
    fi
}

ask_port() {
    local prompt="$1" default="$2" value
    while :; do
        value="$(ask "$prompt" "$default")"
        if [[ "$value" =~ ^[0-9]+$ ]] && (( value >= 0 && value <= 65535 )); then
            printf '%s' "$value"
            return
        fi
        printf '  enter a port between 0 and 65535\n' >&2
    done
}

confirm() {
    local prompt="$1" default="${2:-n}" reply hint
    if [[ "$default" == "y" ]]; then hint="[Y/n]"; else hint="[y/N]"; fi
    read -r -p "  ${prompt} ${hint}: " reply
    reply="${reply:-$default}"
    [[ "$reply" =~ ^[Yy] ]]
}

# Escapes a value for use inside a TOML basic string.
toml_escape() {
    printf '%s' "${1}" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

random_token() {
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -hex 24
    else
        head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n'
    fi
}

# ------------------------------------------------------------------- state --

state_get() {
    local key="$1" default="${2:-}" line
    [[ -f "$STATE_FILE" ]] || { printf '%s' "$default"; return; }
    line="$(grep -E "^${key}=" "$STATE_FILE" | tail -n1 || true)"
    if [[ -n "$line" ]]; then printf '%s' "${line#*=}"; else printf '%s' "$default"; fi
}

state_set() {
    local key="$1" value="$2" tmp
    mkdir -p "$CONFIG_DIR"
    touch "$STATE_FILE"
    tmp="$(mktemp)"
    grep -vE "^${key}=" "$STATE_FILE" > "$tmp" || true
    printf '%s=%s\n' "$key" "$value" >> "$tmp"
    mv "$tmp" "$STATE_FILE"
    chmod 600 "$STATE_FILE"
}

# ------------------------------------------------------------------ system --

require_root() {
    [[ "$(id -u)" -eq 0 ]] || die "Run this as root: sudo $0"
}

require_systemd() {
    command -v systemctl >/dev/null 2>&1 || die "This installer needs systemd."
}

detect_arch() {
    case "$(uname -m)" in
        x86_64|amd64)   printf 'amd64' ;;
        aarch64|arm64)  printf 'arm64' ;;
        armv7l)         printf 'arm_hf' ;;
        armv6l)         printf 'arm' ;;
        riscv64)        printf 'riscv64' ;;
        *) die "Unsupported architecture: $(uname -m)" ;;
    esac
}

latest_version() {
    local tag
    tag="$(curl -fsSL --max-time 15 \
        "https://api.github.com/repos/${FRP_REPO}/releases/latest" 2>/dev/null \
        | sed -n 's/.*"tag_name": *"v\{0,1\}\([^"]*\)".*/\1/p' | head -n1)"
    printf '%s' "${tag:-$FALLBACK_VERSION}"
}

installed_version() {
    if [[ -x "${INSTALL_DIR}/frps" ]]; then
        "${INSTALL_DIR}/frps" --version 2>/dev/null | head -n1
    else
        printf 'not installed'
    fi
}

download_frps() {
    local version="$1" arch pkg base tmp expected
    arch="$(detect_arch)"
    pkg="frp_${version}_linux_${arch}"
    base="https://github.com/${FRP_REPO}/releases/download/v${version}"
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' RETURN

    info "  downloading ${pkg}.tar.gz"
    curl -fsSL -o "${tmp}/frp.tar.gz" "${base}/${pkg}.tar.gz" \
        || die "Download failed. Does version ${version} exist for ${arch}?"

    info "  verifying checksum"
    curl -fsSL -o "${tmp}/checksums.txt" "${base}/frp_sha256_checksums.txt" \
        || die "Could not fetch the checksum file."
    expected="$(grep -E "[[:space:]]${pkg}\.tar\.gz$" "${tmp}/checksums.txt" | cut -d' ' -f1)"
    [[ -n "$expected" ]] || die "No checksum listed for ${pkg}.tar.gz"
    printf '%s  %s\n' "$expected" "${tmp}/frp.tar.gz" | sha256sum -c - >/dev/null \
        || die "Checksum mismatch - refusing to install."

    tar xzf "${tmp}/frp.tar.gz" -C "$tmp"
    install -m 0755 "${tmp}/${pkg}/frps" "${INSTALL_DIR}/frps"
    good "  installed $("${INSTALL_DIR}/frps" --version)"
}

ensure_user() {
    if ! id -u "$SERVICE_USER" >/dev/null 2>&1; then
        useradd --system --no-create-home --shell /usr/sbin/nologin "$SERVICE_USER" 2>/dev/null \
            || useradd --system --no-create-home --shell /sbin/nologin "$SERVICE_USER"
        info "  created system user ${SERVICE_USER}"
    fi
}

# ------------------------------------------------------------ configuration --

collect_config() {
    title "Server identity"
    PUBLIC_HOST="$(ask "Public hostname or IP of this server" "$(state_get public_host)")"

    title "Control port"
    info "  ${DIM}This is where frpc connects. Pick anything that is not already in use.${RESET}"
    BIND_PORT="$(ask_port "TCP control port (0 disables TCP)" "$(state_get bind_port 7000)")"

    info ""
    info "  ${DIM}KCP and QUIC run over UDP. They survive lossy links better than TCP,${RESET}"
    info "  ${DIM}and they get through when TCP to this port is blocked or throttled.${RESET}"
    if confirm "Enable KCP (UDP)?" "$(state_get kcp_enabled n)"; then
        KCP_ENABLED="y"
        KCP_PORT="$(ask_port "KCP port" "$(state_get kcp_port "${BIND_PORT:-7000}")")"
    else
        KCP_ENABLED="n"; KCP_PORT=""
    fi

    if confirm "Enable QUIC (UDP)?" "$(state_get quic_enabled n)"; then
        QUIC_ENABLED="y"
        QUIC_PORT="$(ask_port "QUIC port" "$(state_get quic_port 7001)")"
    else
        QUIC_ENABLED="n"; QUIC_PORT=""
    fi

    title "Authentication"
    local suggested
    suggested="$(state_get auth_token)"
    [[ -n "$suggested" ]] || suggested="$(random_token)"
    AUTH_TOKEN="$(ask "Shared token (clients must match this)" "$suggested")"
    if confirm "Refuse clients that do not use TLS?" "$(state_get tls_force y)"; then
        TLS_FORCE="true"; state_set tls_force y
    else
        TLS_FORCE="false"; state_set tls_force n
    fi

    title "Routing by domain name"
    info "  ${DIM}vhost ports let several tunnels share one port, routed by hostname.${RESET}"
    info "  ${DIM}Put 8080/8443 here and a reverse proxy in front if you want${RESET}"
    info "  ${DIM}automatic HTTPS certificates - see docs/frps-server.md.${RESET}"
    VHOST_HTTP="$(ask_port "vhost HTTP port (0 disables)" "$(state_get vhost_http 80)")"
    VHOST_HTTPS="$(ask_port "vhost HTTPS port (0 disables)" "$(state_get vhost_https 0)")"
    SUBDOMAIN_HOST="$(ask "Wildcard subdomain host (empty to skip)" "$(state_get subdomain_host "-")")"
    [[ "$SUBDOMAIN_HOST" == "-" ]] && SUBDOMAIN_HOST=""

    title "Plain TCP tunnels"
    info "  ${DIM}Clients asking for a remotePort get one from this range only.${RESET}"
    ALLOW_FROM="$(ask_port "Lowest allowed remote port" "$(state_get allow_from 8000)")"
    ALLOW_TO="$(ask_port "Highest allowed remote port" "$(state_get allow_to 9000)")"

    if confirm "Bind tunnel ports to 127.0.0.1 only (reverse proxy in front)?" \
               "$(state_get loopback_only n)"; then
        PROXY_BIND="127.0.0.1"; state_set loopback_only y
    else
        PROXY_BIND="0.0.0.0"; state_set loopback_only n
    fi

    title "Dashboard"
    if confirm "Enable the frps dashboard?" "$(state_get dash_enabled n)"; then
        DASH_ENABLED="y"
        DASH_PORT="$(ask_port "Dashboard port" "$(state_get dash_port 7500)")"
        DASH_USER="$(ask "Dashboard user" "$(state_get dash_user admin)")"
        DASH_PASS="$(ask "Dashboard password" "$(state_get dash_pass "$(random_token)")")"
        info "  ${DIM}The dashboard binds to 127.0.0.1 - reach it over an SSH tunnel.${RESET}"
    else
        DASH_ENABLED="n"
    fi

    state_set public_host "$PUBLIC_HOST"
    state_set bind_port "$BIND_PORT"
    state_set kcp_enabled "$KCP_ENABLED"
    state_set kcp_port "$KCP_PORT"
    state_set quic_enabled "$QUIC_ENABLED"
    state_set quic_port "$QUIC_PORT"
    state_set auth_token "$AUTH_TOKEN"
    state_set vhost_http "$VHOST_HTTP"
    state_set vhost_https "$VHOST_HTTPS"
    state_set subdomain_host "${SUBDOMAIN_HOST:--}"
    state_set allow_from "$ALLOW_FROM"
    state_set allow_to "$ALLOW_TO"
    state_set dash_enabled "$DASH_ENABLED"
    if [[ "$DASH_ENABLED" == "y" ]]; then
        state_set dash_port "$DASH_PORT"
        state_set dash_user "$DASH_USER"
        state_set dash_pass "$DASH_PASS"
    fi
}

write_config() {
    mkdir -p "$CONFIG_DIR"
    if [[ -f "$CONFIG_FILE" ]]; then
        cp -a "$CONFIG_FILE" "${CONFIG_FILE}.bak"
        info "  previous config kept as ${CONFIG_FILE}.bak"
    fi

    {
        printf 'bindAddr = "0.0.0.0"\n'
        [[ "$BIND_PORT" != "0" ]] && printf 'bindPort = %s\n' "$BIND_PORT"
        [[ "$KCP_ENABLED" == "y" ]] && printf 'kcpBindPort = %s\n' "$KCP_PORT"
        [[ "$QUIC_ENABLED" == "y" ]] && printf 'quicBindPort = %s\n' "$QUIC_PORT"
        printf 'proxyBindAddr = "%s"\n' "$PROXY_BIND"
        printf '\n'
        printf 'auth.method = "token"\n'
        printf 'auth.token = "%s"\n' "$(toml_escape "$AUTH_TOKEN")"
        printf 'transport.tls.force = %s\n' "$TLS_FORCE"
        printf '\n'
        [[ "$VHOST_HTTP"  != "0" ]] && printf 'vhostHTTPPort = %s\n' "$VHOST_HTTP"
        [[ "$VHOST_HTTPS" != "0" ]] && printf 'vhostHTTPSPort = %s\n' "$VHOST_HTTPS"
        [[ -n "$SUBDOMAIN_HOST" ]]  && printf 'subDomainHost = "%s"\n' "$(toml_escape "$SUBDOMAIN_HOST")"
        printf '\n'
        printf 'allowPorts = [{ start = %s, end = %s }]\n' "$ALLOW_FROM" "$ALLOW_TO"
        printf '\n'
        if [[ "$DASH_ENABLED" == "y" ]]; then
            printf 'webServer.addr = "127.0.0.1"\n'
            printf 'webServer.port = %s\n' "$DASH_PORT"
            printf 'webServer.user = "%s"\n' "$(toml_escape "$DASH_USER")"
            printf 'webServer.password = "%s"\n' "$(toml_escape "$DASH_PASS")"
            printf '\n'
        fi
        printf 'log.to = "console"\n'
        printf 'log.level = "info"\n'
    } > "$CONFIG_FILE"

    chown root:"$SERVICE_USER" "$CONFIG_FILE"
    chmod 640 "$CONFIG_FILE"
    good "  wrote ${CONFIG_FILE}"
}

write_unit() {
    cat > "$UNIT_FILE" <<EOF
[Unit]
Description=frp server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${SERVICE_USER}
Restart=on-failure
RestartSec=5s
ExecStart=${INSTALL_DIR}/frps -c ${CONFIG_FILE}
AmbientCapabilities=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
PrivateDevices=true
ProtectKernelTunables=true
ProtectControlGroups=true
RestrictAddressFamilies=AF_INET AF_INET6
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    good "  wrote ${UNIT_FILE}"
}

open_firewall() {
    local -a tcp_ports=() udp_ports=()
    [[ "$BIND_PORT"    != "0" ]] && tcp_ports+=("$BIND_PORT")
    [[ "$VHOST_HTTP"   != "0" ]] && tcp_ports+=("$VHOST_HTTP")
    [[ "$VHOST_HTTPS"  != "0" ]] && tcp_ports+=("$VHOST_HTTPS")
    [[ "$KCP_ENABLED"  == "y" ]] && udp_ports+=("$KCP_PORT")
    [[ "$QUIC_ENABLED" == "y" ]] && udp_ports+=("$QUIC_PORT")

    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "^Status: active"; then
        title "Firewall (ufw)"
        info "  to open: ${tcp_ports[*]:-none}/tcp  ${udp_ports[*]:-none}/udp"
        info "  ${DIM}the tcp range ${ALLOW_FROM}-${ALLOW_TO} stays closed - open only what you use${RESET}"
        if confirm "Open these ports now?" "y"; then
            local p
            for p in ${tcp_ports[@]+"${tcp_ports[@]}"}; do
                ufw allow "${p}/tcp" >/dev/null && info "  opened ${p}/tcp"
            done
            for p in ${udp_ports[@]+"${udp_ports[@]}"}; do
                ufw allow "${p}/udp" >/dev/null && info "  opened ${p}/udp"
            done
        fi
    elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
        title "Firewall (firewalld)"
        info "  to open: ${tcp_ports[*]:-none}/tcp  ${udp_ports[*]:-none}/udp"
        if confirm "Open these ports now?" "y"; then
            local p
            for p in ${tcp_ports[@]+"${tcp_ports[@]}"}; do
                firewall-cmd --permanent --add-port="${p}/tcp" >/dev/null
            done
            for p in ${udp_ports[@]+"${udp_ports[@]}"}; do
                firewall-cmd --permanent --add-port="${p}/udp" >/dev/null
            done
            firewall-cmd --reload >/dev/null
            good "  firewalld reloaded"
        fi
    else
        title "Firewall"
        warn "  No active ufw or firewalld found."
        info "  Open these yourself: ${tcp_ports[*]:-none}/tcp  ${udp_ports[*]:-none}/udp"
        info "  Cloud providers usually have a separate security group as well."
    fi
}

start_service() {
    systemctl enable "$SERVICE_NAME" >/dev/null 2>&1 || true
    systemctl restart "$SERVICE_NAME"
    sleep 2
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        good "  ${SERVICE_NAME} is running"
    else
        warn "  ${SERVICE_NAME} failed to start:"
        journalctl -u "$SERVICE_NAME" -n 20 --no-pager || true
    fi
}

# --------------------------------------------------------------- reporting --

show_client_settings() {
    local host port protocol
    host="$(state_get public_host)"
    if [[ "$(state_get kcp_enabled n)" == "y" ]]; then
        protocol="kcp"; port="$(state_get kcp_port)"
    elif [[ "$(state_get quic_enabled n)" == "y" ]]; then
        protocol="quic"; port="$(state_get quic_port)"
    else
        protocol="tcp"; port="$(state_get bind_port 7000)"
    fi

    title "Home Assistant add-on settings"
    printf '  %-16s %s\n' "serverAddr"  "$host"
    printf '  %-16s %s\n' "serverPort"  "$port"
    printf '  %-16s %s\n' "protocol"    "$protocol"
    printf '  %-16s %s\n' "authToken"   "$(state_get auth_token)"
    printf '  %-16s %s\n' "tls"         "true"
    if [[ "$(state_get vhost_http 0)" != "0" || "$(state_get vhost_https 0)" != "0" ]]; then
        printf '  %-16s %s\n' "proxyType"    "http"
        printf '  %-16s %s\n' "customDomain" "ha.${host}"
    else
        printf '  %-16s %s\n' "proxyType"  "tcp"
        printf '  %-16s %s\n' "remotePort" "$(state_get allow_from 8000)"
    fi
    printf '\n'
    info "  ${DIM}Point the domain's DNS A record at this server before connecting.${RESET}"
}

show_status() {
    title "Status"
    printf '  %-16s %s\n' "binary" "$(installed_version)"
    printf '  %-16s %s\n' "config" "$([[ -f "$CONFIG_FILE" ]] && echo "$CONFIG_FILE" || echo "missing")"
    if systemctl list-unit-files 2>/dev/null | grep -q "^${SERVICE_NAME}.service"; then
        printf '  %-16s %s\n' "service" "$(systemctl is-active "$SERVICE_NAME" 2>/dev/null || true) / $(systemctl is-enabled "$SERVICE_NAME" 2>/dev/null || true)"
    else
        printf '  %-16s %s\n' "service" "not installed"
    fi
    printf '\n'
    info "  Listening sockets:"
    (ss -lnptu 2>/dev/null || netstat -lnptu 2>/dev/null) | grep -i frps || info "  ${DIM}  none${RESET}"
    [[ -f "$STATE_FILE" ]] && show_client_settings
}

uninstall() {
    title "Uninstall"
    warn "  This stops frps and removes the binary and the systemd unit."
    confirm "Continue?" "n" || { info "  cancelled"; return; }

    systemctl disable --now "$SERVICE_NAME" >/dev/null 2>&1 || true
    rm -f "$UNIT_FILE"
    systemctl daemon-reload
    rm -f "${INSTALL_DIR}/frps"
    good "  service and binary removed"

    if confirm "Also delete ${CONFIG_DIR} (config, token, saved answers)?" "n"; then
        rm -rf "$CONFIG_DIR"
        good "  ${CONFIG_DIR} deleted"
    else
        info "  ${CONFIG_DIR} kept"
    fi
}

install_or_upgrade() {
    local version
    title "Version"
    info "  currently installed: $(installed_version)"
    version="$(ask "Version to install" "$(latest_version)")"

    title "Download"
    download_frps "$version"
    ensure_user

    collect_config
    write_config
    write_unit
    open_firewall

    title "Service"
    start_service
    show_client_settings
}

reconfigure() {
    [[ -x "${INSTALL_DIR}/frps" ]] || die "frps is not installed yet - choose option 1 first."
    ensure_user
    collect_config
    write_config
    write_unit
    open_firewall
    title "Service"
    start_service
    show_client_settings
}

main_menu() {
    while :; do
        title "frps installer"
        info "  1) Install or upgrade frps"
        info "  2) Reconfigure the existing server"
        info "  3) Show status and client settings"
        info "  4) Uninstall"
        info "  5) Quit"
        case "$(ask "Choose" "1")" in
            1) install_or_upgrade ;;
            2) reconfigure ;;
            3) show_status ;;
            4) uninstall ;;
            5) exit 0 ;;
            *) warn "  pick a number from the list" ;;
        esac
    done
}

require_root
require_systemd
command -v curl >/dev/null 2>&1 || die "curl is required."
main_menu
