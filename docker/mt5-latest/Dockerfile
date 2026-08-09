# syntax=docker/dockerfile:1
#
# Backtest image: Ubuntu 24.04 + current WineHQ + latest MetaTrader 5.
#
# Replaces ea31337/ea-tester for MQL5 work. That image ships Wine 6.0, which
# current winetricks can no longer install MetaTrader onto, and its Ansible
# dependency chain resolves ea31337.wine v1.0.4 through the Galaxy index where
# that version is absent. Both failures are upstream and unfixable from here.
#
# Layers are ordered cheapest-to-rebuild last, and apt/installer downloads use
# BuildKit caches, so editing the entrypoint or the install step does not refetch
# WineHQ or the MetaTrader installer.
FROM ubuntu:24.04 AS wine-base

ENV DEBIAN_FRONTEND=noninteractive

# --- Layer 1: base tooling. Rarely changes. ------------------------------------
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        cabextract \
        curl \
        jq \
        p7zip-full \
        procps \
        python3 \
        unzip \
        xvfb

# --- Layer 2: WineHQ. Changes only when the distro or Wine channel changes. ----
# winehq-devel, not winehq-stable: the MT5 installer's anti-tamper protection
# false-positives on Wine 11.0 stable ("A debugger has been found running in
# your system") but passes on 11.14+, the same series that works on the host.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    dpkg --add-architecture i386 \
    && mkdir -pm755 /etc/apt/keyrings \
    && curl -fsSL https://dl.winehq.org/wine-builds/winehq.key \
        -o /etc/apt/keyrings/winehq-archive.key \
    && curl -fsSL https://dl.winehq.org/wine-builds/ubuntu/dists/noble/winehq-noble.sources \
        -o /etc/apt/sources.list.d/winehq-noble.sources \
    && apt-get update \
    && apt-get install -y --install-recommends winehq-devel

# Pinned uid so the BuildKit cache mount below can be owned correctly.
RUN useradd -m -u 1001 -s /bin/bash trader
USER trader
WORKDIR /home/trader

# Disabling mscoree/mshtml stops Wine prompting to download Mono and Gecko on
# first run; MetaTrader needs neither for headless testing.
ENV WINEPREFIX=/home/trader/.mt5 \
    WINEARCH=win64 \
    WINEDEBUG=-all \
    WINEDLLOVERRIDES="mscoree,mshtml=" \
    MT5_DIR="/home/trader/.mt5/drive_c/Program Files/MetaTrader 5"

# --- Layer 3: empty Wine prefix. -----------------------------------------------
# wineserver -k, not -w: since Wine 11.x explorer.exe outlives wineboot, so
# waiting on the server blocks forever.
RUN xvfb-run -a wineboot --init && wineserver -k && wineserver -w || true

# Everything above is the reusable Wine runtime; build it alone with
#   docker build --target wine-base -t mt5-winebase:local docker/mt5-latest/
# which is handy for debugging the install without repeating it.
FROM wine-base AS with-mt5

# --- Layer 4: fetch the installer, cached separately from running it. ----------
# Same URL the project's own install-mt5.yml uses, so this tracks the current
# MetaTrader 5 build rather than a pinned one.
RUN --mount=type=cache,target=/home/trader/.cache/dl,uid=1001,gid=1001 \
    if [ ! -s /home/trader/.cache/dl/mt5setup.exe ]; then \
        curl -fL https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe \
            -o /home/trader/.cache/dl/mt5setup.exe; \
    fi; \
    cp /home/trader/.cache/dl/mt5setup.exe /home/trader/mt5setup.exe

# --- Layer 5: install, driving the wizard with AutoHotkey. See the script. -----
COPY --chown=trader:trader install-mt5.sh /home/trader/install-mt5.sh
RUN --mount=type=cache,target=/home/trader/.cache/ahk,uid=1001,gid=1001 \
    /home/trader/install-mt5.sh && rm -f /home/trader/mt5setup.exe

# --- Layer 6: entrypoint. Edited most often, so it comes last. -----------------
COPY --chown=trader:trader entrypoint.sh /home/trader/entrypoint.sh
ENTRYPOINT ["/home/trader/entrypoint.sh"]
