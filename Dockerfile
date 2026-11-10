
# ==============================================================
#  ⚠️  USAGE: TRIGGERED BY MAKEFILE
#  This file is executed via the 'linux-release-docker' command.
# ==============================================================

FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

COPY linux_deps.list /tmp/linux_deps.list

RUN apt-get update && \
    DEPS=$(cat /tmp/linux_deps.list | tr -d '\r' | sed 's/#.*//g' | xargs) && \
    \
    apt-get install -y --no-install-recommends $DEPS && \
    \
    rm -rf /var/lib/apt/lists/* && \
    echo "root ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

ARG TARGETARCH
RUN ARCH="$TARGETARCH"; \
    [ "$ARCH" = "amd64" ] && ARCH=x86_64; \
    [ "$ARCH" = "arm64" ] && ARCH=aarch64; \
    wget -O /usr/local/bin/appimagetool \
      "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-${ARCH}.AppImage" && \
    chmod +x /usr/local/bin/appimagetool

# Flutter lives in the linux-flutter-sdk-cache volume (see Makefile / ~/development/linux/env.sh).
ENV PATH="/root/develop/flutter/bin:/root/.pub-cache/bin:${PATH}"
ENV APPIMAGE_EXTRACT_AND_RUN=1
WORKDIR /app
