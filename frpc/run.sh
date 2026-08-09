#!/usr/bin/env bash
# Generates an frpc configuration from the add-on options, then runs frpc.
# With configMode=file the user-supplied TOML file is used verbatim instead.
#
# Options are read straight from /data/options.json, which the Supervisor
# writes before every start. Going through the Supervisor API instead would
# add a dependency that host-network add-ons cannot always satisfy.
set -euo pipefail

OPTIONS_FILE="${OPTIONS_FILE:-/data/options.json}"
GENERATED_CONFIG="${GENERATED_CONFIG:-/tmp/frpc.toml}"

log()   { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
fatal() { printf '[%s] FATAL: %s\n' "$(date +%H:%M:%S)" "$*" >&2; exit 1; }

# Reads one option, falling back to the given default when it is absent or null.
opt() {
    local key="$1" fallback="${2:-}" value
    value="$(jq -r --arg k "$key" '.[$k] // empty' "$OPTIONS_FILE")"
    printf '%s' "${value:-$fallback}"
}

# Escapes a value for use inside a TOML basic string.
toml_escape() {
    printf '%s' "${1}" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

run_with_user_config() {
    local config_file
    config_file="$(opt configFile /share/frpc.toml)"

    if [[ ! -f "${config_file}" ]]; then
        log "ERROR: configMode is 'file' but ${config_file} does not exist."
        fatal "Create the file first, for example via the Samba or File editor add-on."
    fi

    log "Using user-supplied configuration: ${config_file}"
    exec frpc -c "${config_file}"
}

write_generated_config() {
    local server_addr server_port auth_token protocol tls log_level
    local proxy_name proxy_type custom_domain remote_port
    local local_ip local_port use_encryption use_compression

    server_addr="$(opt serverAddr)"
    server_port="$(opt serverPort 7000)"
    auth_token="$(opt authToken)"
    protocol="$(opt protocol tcp)"
    tls="$(opt tls true)"
    log_level="$(opt logLevel info)"
    proxy_name="$(opt proxyName homeassistant)"
    proxy_type="$(opt proxyType http)"
    custom_domain="$(opt customDomain)"
    remote_port="$(opt remotePort 8123)"
    local_ip="$(opt localIP 127.0.0.1)"
    local_port="$(opt localPort 8123)"
    use_encryption="$(opt useEncryption true)"
    use_compression="$(opt useCompression true)"

    if [[ -z "${server_addr}" ]]; then
        fatal "serverAddr is empty - set the frps server address in the add-on configuration."
    fi

    if [[ "${proxy_type}" != "tcp" && -z "${custom_domain}" ]]; then
        log "ERROR: proxyType '${proxy_type}' needs customDomain to be set."
        fatal "Use proxyType 'tcp' with a remotePort if your frps has no vhost ports."
    fi

    if [[ -z "${auth_token}" ]]; then
        log "WARNING: authToken is empty - connecting without authentication."
        log "WARNING: This only works if your frps server has no token configured."
    fi

    touch "${GENERATED_CONFIG}"
    chmod 600 "${GENERATED_CONFIG}"

    {
        echo "serverAddr = \"$(toml_escape "${server_addr}")\""
        echo "serverPort = ${server_port}"
        if [[ -n "${auth_token}" ]]; then
            echo "auth.method = \"token\""
            echo "auth.token = \"$(toml_escape "${auth_token}")\""
        fi
        echo "transport.protocol = \"${protocol}\""
        echo "transport.tls.enable = ${tls}"
        echo
        echo "log.to = \"console\""
        echo "log.level = \"${log_level}\""
        echo
        echo "[[proxies]]"
        echo "name = \"$(toml_escape "${proxy_name}")\""
        echo "type = \"${proxy_type}\""
        echo "localIP = \"$(toml_escape "${local_ip}")\""
        echo "localPort = ${local_port}"
        echo "transport.useEncryption = ${use_encryption}"
        echo "transport.useCompression = ${use_compression}"
        if [[ "${proxy_type}" == "tcp" ]]; then
            echo "remotePort = ${remote_port}"
        else
            echo "customDomains = [\"$(toml_escape "${custom_domain}")\"]"
        fi
    } > "${GENERATED_CONFIG}"

    log "frps: ${server_addr}:${server_port} over ${protocol} (tls=${tls})"
    if [[ "${proxy_type}" == "tcp" ]]; then
        log "proxy: ${proxy_name} (tcp) ${local_ip}:${local_port} -> remote port ${remote_port}"
    else
        log "proxy: ${proxy_name} (${proxy_type}) ${local_ip}:${local_port} for ${custom_domain}"
    fi
}

[[ -f "${OPTIONS_FILE}" ]] || fatal "${OPTIONS_FILE} is missing - the Supervisor did not pass any options."

if [[ "$(opt configMode options)" == "file" ]]; then
    run_with_user_config
fi

write_generated_config
exec frpc -c "${GENERATED_CONFIG}"
