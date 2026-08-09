ARG BUILD_FROM
FROM ${BUILD_FROM}

ARG BUILD_ARCH
ARG FRP_VERSION

RUN set -eux; \
    case "${BUILD_ARCH}" in \
        amd64)   frp_arch="amd64" ;; \
        aarch64) frp_arch="arm64" ;; \
        armv7)   frp_arch="arm_hf" ;; \
        armhf)   frp_arch="arm" ;; \
        *) echo "unsupported architecture: ${BUILD_ARCH}" >&2; exit 1 ;; \
    esac; \
    pkg="frp_${FRP_VERSION}_linux_${frp_arch}"; \
    base="https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}"; \
    curl -fsSL -o /tmp/frp.tar.gz "${base}/${pkg}.tar.gz"; \
    curl -fsSL -o /tmp/checksums.txt "${base}/frp_sha256_checksums.txt"; \
    expected="$(grep -E "[[:space:]]${pkg}\.tar\.gz$" /tmp/checksums.txt | cut -d' ' -f1)"; \
    test -n "${expected}"; \
    echo "${expected}  /tmp/frp.tar.gz" | sha256sum -c -; \
    tar xzf /tmp/frp.tar.gz -C /tmp; \
    install -m 0755 "/tmp/${pkg}/frpc" /usr/local/bin/frpc; \
    rm -rf /tmp/frp.tar.gz /tmp/checksums.txt "/tmp/${pkg}"; \
    frpc --version

COPY run.sh /run.sh
RUN chmod a+x /run.sh

CMD ["/run.sh"]
