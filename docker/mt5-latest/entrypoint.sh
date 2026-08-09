#!/usr/bin/env bash
# Drives the MetaTrader 5 strategy tester headlessly.
#
# With no arguments it runs a backtest built from the BT_* environment
# variables; any argument is executed verbatim instead, so the image doubles as
# a shell for poking at the prefix.
set -euo pipefail

if [ $# -gt 0 ]; then
  exec "$@"
fi

# The tester refuses to start without a logged-in account ("tester not started
# because the account is not specified"), and accounts.dat copied on its own
# gets "deleted due security reason" - the credentials only survive inside the
# Wine prefix that created them. So mount a prefix from a machine where the
# terminal has logged in once (e.g. a copy of ~/.mt5 from the host) at
# /opt/prefix; it is copied in because the mount's owner uid rarely matches.
if [ -d /opt/prefix/drive_c ]; then
  echo "INFO: seeding logged-in Wine prefix from /opt/prefix"
  cp -a /opt/prefix /home/trader/.mt5-seeded
  export WINEPREFIX=/home/trader/.mt5-seeded
fi

TERMINAL_DIR="$WINEPREFIX/drive_c/Program Files/MetaTrader 5"
TERMINAL_EXE="$TERMINAL_DIR/terminal64.exe"

: "${BT_EXPERT:?BT_EXPERT is required, e.g. EA31337}"
BT_SYMBOL=${BT_SYMBOL:-EURUSD}
BT_PERIOD=${BT_PERIOD:-M1}
BT_FROM=${BT_FROM:-2024.01.01}
BT_TO=${BT_TO:-2024.12.31}
BT_DEPOSIT=${BT_DEPOSIT:-10000}
BT_CURRENCY=${BT_CURRENCY:-USD}
BT_LEVERAGE=${BT_LEVERAGE:-100}
# 0 = every tick, 1 = 1 minute OHLC, 2 = open prices, 4 = every tick based on
# real ticks. Matches the platform's own Model numbering.
BT_MODEL=${BT_MODEL:-0}
BT_REPORT=${BT_REPORT:-report}
BT_DEST=${BT_DEST:-/opt/_results}

# A freshly installed terminal has no price history and no account, so the
# tester would have nothing to run against. Mount a populated Bases tree at
# /opt/bases (read-only is fine, it gets copied in) to supply it. The copy
# overlays the skeleton Bases/Default a fresh install ships with.
if [ -d /opt/bases ]; then
  echo "INFO: seeding price history from /opt/bases"
  cp -a /opt/bases/. "$TERMINAL_DIR/Bases/"
  du -sh "$TERMINAL_DIR/Bases" | sed 's/^/INFO: /'
fi
# Likewise for terminal config (servers, and the saved account) when supplied.
if [ -d /opt/config ]; then
  echo "INFO: seeding terminal config from /opt/config"
  mkdir -p "$TERMINAL_DIR/Config"
  cp -a /opt/config/. "$TERMINAL_DIR/Config/" 2> /dev/null || true
fi

# The tester only loads experts from inside the terminal's own MQL5 tree,
# which a fresh install does not have until the terminal first runs.
mkdir -p "$TERMINAL_DIR/MQL5/Experts" "$TERMINAL_DIR/MQL5/Indicators"
if [ -n "${EA_PATH:-}" ]; then
  install -v -m 644 "$EA_PATH" "$TERMINAL_DIR/MQL5/Experts/"
fi
if [ -n "${INDI_DIR:-}" ] && [ -d "$INDI_DIR" ]; then
  find "$INDI_DIR" -name '*.ex5' -exec install -v -m 644 {} "$TERMINAL_DIR/MQL5/Indicators/" \;
fi

# The terminal is a Windows process, so the config path must be one it can
# resolve; keep the file inside drive_c and hand it over as C:\tester.ini.
CFG="$WINEPREFIX/drive_c/tester.ini"
CFG_WIN='C:\tester.ini'
cat > "$CFG" << EOF
[Common]
Login=
ProxyEnable=0
CertInstall=0
NewsEnable=0

[Tester]
Expert=$BT_EXPERT
Symbol=$BT_SYMBOL
Period=$BT_PERIOD
Model=$BT_MODEL
FromDate=$BT_FROM
ToDate=$BT_TO
Deposit=$BT_DEPOSIT
Currency=$BT_CURRENCY
Leverage=1:$BT_LEVERAGE
Optimization=0
ShutdownTerminal=1
Report=$BT_REPORT
ReplaceReport=1
EOF

echo "INFO: $BT_EXPERT on $BT_SYMBOL $BT_PERIOD, $BT_FROM..$BT_TO, deposit $BT_DEPOSIT"
cd "$TERMINAL_DIR"
xvfb-run -a wine terminal64.exe /config:"$CFG_WIN" /portable || true
# -k then -w: explorer.exe outlives the terminal on Wine 11.x, so waiting
# without killing first blocks forever.
wineserver -k 2> /dev/null || true
wineserver -w 2> /dev/null || true

mkdir -p "$BT_DEST"
found=0
for ext in htm html xml png; do
  for f in "$TERMINAL_DIR/$BT_REPORT."$ext; do
    [ -f "$f" ] && {
      install -v -m 644 "$f" "$BT_DEST/"
      found=1
    }
  done
done
[ "$found" = 1 ] || echo "WARN: no report produced; check the terminal logs below"
find "$TERMINAL_DIR/Tester/logs" "$TERMINAL_DIR/logs" -name '*.log' -newermt '-1 hour' \
  -exec sh -c 'echo "--- {} ---"; iconv -f UTF-16LE -t UTF-8 "{}" 2>/dev/null | tail -30' \; 2> /dev/null || true
