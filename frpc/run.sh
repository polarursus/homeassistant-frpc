#!/usr/bin/env bashio
# Generates an frpc configuration from the add-on options, then runs frpc.
# With configMode=file the user-supplied TOML file is used verbatim instead.
set -e

GENERATED_CONFIG="/tmp/frpc.toml"

# Escapes a value for use inside a TOML basic string.
toml_escape() {
    printf '%s' "${1}" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

run_with_user_config() {
    local config_file
    config_file="$(bashio::config 'configFile')"

    if ! bashio::fs.file_exists "${config_file}"; then
        bashio::log.error "configMode is 'file' but ${config_file} does not exist."
        bashio::log.error "Create the file first, for example via the Samba or File editor add-on."
        bashio::exit.nok
    fi

    bashio::log.info "Using user-supplied configuration: ${config_file}"
    exec frpc -c "${config_file}"
}

write_generated_config() {
    local server_addr server_port auth_token protocol tls log_level
    local proxy_name proxy_type custom_domain remote_port
    local local_ip local_port use_encryption use_compression

    server_addr="$(bashio::config 'serverAddr')"
    server_port="$(bashio::config 'serverPort')"
    auth_token="$(bashio::config 'authToken')"
    protocol="$(bashio::config 'protocol')"
    tls="$(bashio::config 'tls')"
    log_level="$(bashio::config 'logLevel')"
    proxy_name="$(bashio::config 'proxyName')"
    proxy_type="$(bashio::config 'proxyType')"
    custom_domain="$(bashio::config 'customDomain')"
    remote_port="$(bashio::config 'remotePort')"
    local_ip="$(bashio::config 'localIP')"
    local_port="$(bashio::config 'localPort')"
    use_encryption="$(bashio::config 'useEncryption')"
    use_compression="$(bashio::config 'useCompression')"

    if bashio::var.is_empty "${server_addr}"; then
        bashio::log.error "serverAddr is empty - set the frps server address in the add-on configuration."
        bashio::exit.nok
    fi

    if [ "${proxy_type}" != "tcp" ] && bashio::var.is_empty "${custom_domain}"; then
        bashio::log.error "proxyType '${proxy_type}' needs customDomain to be set."
        bashio::log.error "Use proxyType 'tcp' with a remotePort if your frps has no vhost ports."
        bashio::exit.nok
    fi

    if bashio::var.is_empty "${auth_token}"; then
        bashio::log.warning "authToken is empty - connecting without authentication."
        bashio::log.warning "This only works if your frps server has no token configured."
    fi

    touch "${GENERATED_CONFIG}"
    chmod 600 "${GENERATED_CONFIG}"

    {
        echo "serverAddr = \"$(toml_escape "${server_addr}")\""
        echo "serverPort = ${server_port}"
        if ! bashio::var.is_empty "${auth_token}"; then
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
        if [ "${proxy_type}" = "tcp" ]; then
            echo "remotePort = ${remote_port}"
        else
            echo "customDomains = [\"$(toml_escape "${custom_domain}")\"]"
        fi
    } > "${GENERATED_CONFIG}"

    bashio::log.info "frps: ${server_addr}:${server_port} over ${protocol} (tls=${tls})"
    if [ "${proxy_type}" = "tcp" ]; then
        bashio::log.info "proxy: ${proxy_name} (tcp) ${local_ip}:${local_port} -> remote port ${remote_port}"
    else
        bashio::log.info "proxy: ${proxy_name} (${proxy_type}) ${local_ip}:${local_port} for ${custom_domain}"
    fi
}

if [ "$(bashio::config 'configMode')" = "file" ]; then
    run_with_user_config
fi

write_generated_config
exec frpc -c "${GENERATED_CONFIG}"
