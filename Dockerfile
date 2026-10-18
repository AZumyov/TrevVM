FROM ghcr.io/linuxserver/baseimage-kasmvnc:ubuntujammy

ARG BUILD_DATE
ARG VERSION
ARG DEBIAN_FRONTEND=noninteractive

LABEL build_version="[Mollomm1 Mod] Linuxserver.io version:- ${VERSION} Build-date:- ${BUILD_DATE}" \
      maintainer="mollomm1"

# Copies the contents of root/ into the image filesystem.
COPY root/ /
COPY options.json /options.json

RUN set -eux; \
    rm -f /etc/apt/sources.list.d/nodesource.list; \
    apt-get update; \
    apt-get install --no-install-recommends -y software-properties-common; \
    add-apt-repository -y ppa:mozillateam/ppa; \
    apt-get update; \
    apt-get install --no-install-recommends -y firefox jq wget; \
    chmod +x /installapps.sh; \
    bash /install-de.sh; \
    /installapps.sh; \
    rm -f /installapps.sh; \
    apt-get autoclean; \
    apt-get clean; \
    rm -rf \
      /config/.cache \
      /var/lib/apt/lists/* \
      /var/tmp/* \
      /tmp/*

EXPOSE 3000
VOLUME /config
