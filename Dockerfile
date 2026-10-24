# syntax=docker/dockerfile:1
ARG BASE_IMAGE=ghcr.io/linuxserver/baseimage-kasmvnc:ubuntujammy

FROM ${BASE_IMAGE}

ARG BUILD_DATE=""
ARG VERSION="dev"
ARG OPTIONS_JSON=""

LABEL org.opencontainers.image.title="TrevVM" \
      org.opencontainers.image.description="A Linux desktop in a container, streamed to the browser with KasmVNC." \
      org.opencontainers.image.source="https://github.com/AZumyov/TrevVM" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.licenses="Apache-2.0" \
      maintainer="TrevVM contributors"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Keep apt from installing the snap build of Firefox.
COPY root/etc/apt/preferences.d/firefox-no-snap /etc/apt/preferences.d/firefox-no-snap

# Versions float on purpose: this is a desktop image rebuilt from Ubuntu Jammy.
# hadolint ignore=DL3008
RUN set -eux; \
    rm -f /etc/apt/sources.list.d/nodesource.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        software-properties-common ca-certificates curl gnupg jq wget; \
    add-apt-repository -y ppa:mozillateam/ppa; \
    apt-get update; \
    apt-get install -y --no-install-recommends firefox; \
    rm -rf /var/lib/apt/lists/*

COPY root/ /
COPY apps.json /opt/trevvm/apps.json

RUN set -eux; \
    if [ -n "${OPTIONS_JSON:-}" ]; then \
        printf '%s' "$OPTIONS_JSON" >/options.json; \
    else \
        printf '%s' '{"DE":"cinnamon","packages":[]}' >/options.json; \
    fi; \
    mkdir -p /opt/trevvm; \
    cp -a /installable-apps /opt/trevvm/apps; \
    cp /installapps.sh /opt/trevvm/install-app.sh; \
    chmod +x /opt/trevvm/install-app.sh; \
    bash -n /install-de.sh; \
    bash -n /opt/trevvm/install-app.sh; \
    bash /install-de.sh; \
    bash /opt/trevvm/install-app.sh; \
    rm -rf /installable-apps /installapps.sh /install-de.sh; \
    apt-get autoclean; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /var/tmp/* /tmp/* /config/.cache

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD ["/bin/bash", "-c", "exec 3<>/dev/tcp/127.0.0.1/3000"]

EXPOSE 3000
VOLUME /config
