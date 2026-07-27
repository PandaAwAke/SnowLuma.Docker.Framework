# syntax=docker/dockerfile:1
# check=skip=SecretsUsedInArgOrEnv
ARG NODE_VERSION=22
ARG BASE_IMAGE=node:${NODE_VERSION}-bookworm-slim
ARG APT_MIRROR=http://mirrors.ustc.edu.cn/debian
ARG APT_SECURITY_MIRROR=http://mirrors.ustc.edu.cn/debian-security
FROM ${BASE_IMAGE}

ARG APT_MIRROR
ARG APT_SECURITY_MIRROR
ARG TARGETARCH
ARG QQ_VERSION=3.2.31-51102
ARG QQ_CHANNEL=c390e792
ARG QQ_BASE_URL=https://qqdl.gtimg.cn/qqfile/QQNT/9.9.32/beta
ARG QQ_DEB_NAME=

ENV DEBIAN_FRONTEND=noninteractive \
    VNC_PASSWD=vncpasswd \
    TZ=Asia/Shanghai \
    SNOWLUMA_HOME=/app/snowluma \
    SNOWLUMA_DATA=/app/snowluma-data \
    SNOWLUMA_WEBUI_PORT=5099 \
    SNOWLUMA_UID=1000 \
    SNOWLUMA_GID=1000 \
    SNOWLUMA_LOG_LEVEL=info \
    SNOWLUMA_SCREEN=1920x1080x24 \
    SNOWLUMA_HOOK_AUTOLOAD=1 \
    SNOWLUMA_EXTRA_QQ_HOMES="" \
    SNOWLUMA_QQ_FLAGS="--disable-gpu --disable-software-rasterizer --disable-gpu-compositing" \
    DISPLAY=:1

RUN rm -f /etc/apt/apt.conf.d/docker-clean; \
    if [ -f /etc/apt/sources.list.d/debian.sources ]; then \
      printf '%s\n' \
        'Types: deb' \
        "URIs: ${APT_MIRROR}" \
        'Suites: bookworm bookworm-updates' \
        'Components: main contrib non-free-firmware' \
        'Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg' \
        '' \
        'Types: deb' \
        "URIs: ${APT_SECURITY_MIRROR}" \
        'Suites: bookworm-security' \
        'Components: main contrib non-free-firmware' \
        'Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg' \
        > /etc/apt/sources.list.d/debian.sources; \
    fi; \
    if [ -f /etc/apt/sources.list ]; then \
      printf '%s\n' \
        "deb ${APT_MIRROR} bookworm main contrib non-free-firmware" \
        "deb ${APT_MIRROR} bookworm-updates main contrib non-free-firmware" \
        "deb ${APT_SECURITY_MIRROR} bookworm-security main contrib non-free-firmware" \
        > /etc/apt/sources.list; \
    fi; \
    echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
      aria2 \
      ca-certificates \
      dbus-user-session \
      ffmpeg \
      fluxbox \
      fonts-wqy-zenhei \
      gnutls-bin \
      iproute2 \
      libasound2 \
      libatspi2.0-0 \
      libcap2-bin \
      libgbm1 \
      libgtk-3-0 \
      libnotify4 \
      libnss3 \
      libsecret-1-0 \
      openbox \
      python3 \
      procps \
      supervisor \
      tzdata \
      unzip \
      x11vnc \
      xdg-utils \
      xorg \
      xvfb && \
    echo "${TZ}" > /etc/timezone && \
    ln -sf "/usr/share/zoneinfo/${TZ}" /etc/localtime && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

COPY vendor /tmp/vendor
COPY supervisord.conf /etc/supervisord.conf
COPY start.sh /root/start.sh
COPY scripts/prepare-vendor-snowluma.sh /usr/local/bin/prepare-vendor-snowluma.sh

RUN chmod +x /root/start.sh /usr/local/bin/prepare-vendor-snowluma.sh && \
    groupadd --gid 1001 snowluma && \
    useradd --no-log-init --uid 1001 --gid 1001 --home-dir /app --shell /bin/bash snowluma && \
    mkdir -p "${SNOWLUMA_HOME}" "${SNOWLUMA_DATA}" /app/.cache /app/.config /app/.local/share /etc/supervisor/conf.d /opt/noVNC/utils && \
    cp -a /tmp/vendor/noVNC/. /opt/noVNC/ && \
    rm -rf /opt/noVNC/utils/websockify && \
    cp -a /tmp/vendor/websockify /opt/noVNC/utils/websockify && \
    chmod +x /opt/noVNC/utils/novnc_proxy /opt/noVNC/utils/websockify/run && \
    cp /opt/noVNC/vnc.html /opt/noVNC/index.html && \
    /usr/local/bin/prepare-vendor-snowluma.sh /tmp/vendor/SnowLuma "${SNOWLUMA_HOME}" "$(dpkg --print-architecture)" && \
    qq_arch="$(dpkg --print-architecture)" && \
    case "${qq_arch}" in \
      amd64|arm64) ;; \
      *) echo "Unsupported Debian architecture: ${qq_arch}" >&2; exit 1 ;; \
    esac && \
    qq_deb="" && \
    if [ -n "${QQ_DEB_NAME}" ] && [ -f "/tmp/vendor/qq/${QQ_DEB_NAME}" ]; then \
      qq_deb="/tmp/vendor/qq/${QQ_DEB_NAME}"; \
    else \
      for candidate in \
        "/tmp/vendor/qq/linuxqq_${QQ_VERSION}_${qq_arch}.deb" \
        "/tmp/vendor/qq/linuxqq_${qq_arch}.deb" \
        "/tmp/vendor/qq/linuxqq.deb"; do \
        if [ -f "${candidate}" ]; then \
          qq_deb="${candidate}"; \
          break; \
        fi; \
      done; \
    fi && \
    if [ -n "${qq_deb}" ]; then \
      cp "${qq_deb}" /tmp/linuxqq.deb; \
    else \
      aria2c --check-certificate=false -x16 -s16 -o /tmp/linuxqq.deb "${QQ_BASE_URL}/${QQ_CHANNEL}/linuxqq_${QQ_VERSION}_${qq_arch}.deb" || \
        (echo "Failed to download Linux QQ. Put a local package at vendor/qq/linuxqq_${QQ_VERSION}_${qq_arch}.deb (or set QQ_DEB_NAME)." >&2; exit 1); \
    fi && \
    (dpkg -i /tmp/linuxqq.deb || (apt-get update && apt-get -f install -y --no-install-recommends)) && \
    rm -f /tmp/linuxqq.deb && \
    chmod 777 /opt/QQ && \
    test -f "${SNOWLUMA_HOME}/index.mjs" && \
    case "${qq_arch}" in \
      amd64) native_arch="x64" ;; \
      arm64) native_arch="arm64" ;; \
    esac && \
    test -f "${SNOWLUMA_HOME}/native/snowluma-linux-${native_arch}.node" && \
    test -f "${SNOWLUMA_HOME}/native/snowluma-linux-${native_arch}.so" && \
    test -f "${SNOWLUMA_HOME}/native/websocket-linux-${native_arch}.node" && \
    test -f "${SNOWLUMA_HOME}/native/ffmpeg/ffmpegAddon.linux.${native_arch}.node" && \
    setcap cap_sys_ptrace+ep /usr/local/bin/node && \
    rm -rf /tmp/vendor && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    chown -R snowluma:snowluma /app /opt/QQ

WORKDIR /app/snowluma-data

EXPOSE 5900 6081 5099 3000 3001

VOLUME ["/app/snowluma-data", "/app/.config", "/app/.local/share"]

CMD ["/root/start.sh"]
