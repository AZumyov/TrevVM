FROM ghcr.io/linuxserver/baseimage-kasmvnc:ubuntujammy

# Set version label
ARG BUILD_DATE
ARG VERSION
LABEL build_version="[Mollomm1 Mod] Linuxserver.io version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="mollomm1"

ARG DEBIAN_FRONTEND="noninteractive"

# Copy supporting files first.
COPY root/ /

# Explicit copies come after the broad copy so these versions are used.
COPY root/etc/apt/preferences.d/firefox-no-snap /etc/apt/preferences.d/firefox-no-snap
COPY root/install-de.sh /install-de.sh
COPY options.json /options.json

RUN \
  echo "**** install packages ****" && \
  add-apt-repository -y ppa:mozillateam/ppa && \
  rm -f /etc/apt/sources.list.d/nodesource.list && \
  apt-get update && \
  DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y firefox jq wget && \
  chmod +x /install-de.sh && \
  bash /install-de.sh

RUN \
  chmod +x /installapps.sh && \
  /installapps.sh && \
  rm /installapps.sh

RUN \
  echo "**** cleanup ****" && \
  apt-get autoclean && \
  rm -rf \
    /config/.cache \
    /var/lib/apt/lists/* \
    /var/tmp/* \
    /tmp/*

# Ports and volumes
EXPOSE 3000
VOLUME /config
