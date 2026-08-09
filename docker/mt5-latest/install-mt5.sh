#!/usr/bin/env bash
# Installs MetaTrader 5 into the Wine prefix, headlessly.
#
# The installer has no working silent mode - /auto still puts up the wizard -
# so AutoHotkey clicks through it on a virtual display, an approach borrowed
# from EA31337's own ansible-role-metatrader (templates/mt5_install.verb.j2)
# and reimplemented here without winetricks or ansible, both broken upstream
# (Wine 6.0 in ea-tester; ea31337.wine v1.0.4 missing from the Galaxy index).
# An opensymbol font stands in for wingdings.ttf (Wine bug 7156). Wine must be
# 11.14+/devel: the installer's anti-tamper check false-positives on 11.0
# stable with "A debugger has been found running in your system".
set -uo pipefail

# The first wine command boots wineserver, and explorer.exe inherits its
# DISPLAY. Booted headless, the desktop comes up on the null driver and every
# later GUI process fails no matter how it is launched (AutoHotkey dies with
# code 2 before it can even show an error). So the whole script must run under
# one X server: re-exec under xvfb-run before touching wine.
if [ -z "${DISPLAY:-}" ]; then
  exec xvfb-run -a "$0" "$@"
fi

AHK_VER=1.1.36.01
AHK_DIR=/home/trader/.cache/ahk
# Both the installer and the script have to live inside the prefix: AutoHotkey
# is a Windows binary and only takes Windows paths.
WORK="$WINEPREFIX/drive_c/windows/temp/mt5"
WORK_WIN='C:\windows\temp\mt5'
TARGET="$MT5_DIR/terminal64.exe"

mkdir -p "$AHK_DIR" "$WORK"

# Do NOT set HideWineExports here, current installers need the opposite. The
# ansible role set it for 2020-era installers, but today's installer runs its
# anti-tamper checks on the "real Windows" path when Wine is masked, and those
# false-positive under Wine with "A debugger has been found running in your
# system". Left visible as Wine, the installer takes its Wine-compat path and
# proceeds (the same reason mt5linux.sh works on the host without the key).

# Same prefix setting MetaQuotes' own mt5linux.sh applies before installing.
echo "INFO: setting Windows version to 11"
wine winecfg -v=win11 > /dev/null 2>&1

echo "INFO: installing opensymbol font (Wine bug 7156 workaround)"
FONTS="$WINEPREFIX/drive_c/windows/Fonts"
mkdir -p "$FONTS"
curl -fsSL -o "$FONTS/opensymbol.ttf" \
  "https://raw.githubusercontent.com/apache/openoffice/5f13fa00702a0abe48858d443bc306f5c5ba26d8/main/extras/source/truetype/symbol/opens___.ttf" \
  && wine reg add 'HKLM\Software\Microsoft\Windows NT\CurrentVersion\Fonts' \
    /v "OpenSymbol (TrueType)" /t REG_SZ /d opensymbol.ttf /f > /dev/null 2>&1 || true

if [ ! -f "$AHK_DIR/AutoHotkeyU64.exe" ]; then
  echo "INFO: fetching AutoHotkey $AHK_VER"
  curl -fL "https://github.com/AutoHotkey/AutoHotkey/releases/download/v${AHK_VER}/AutoHotkey_${AHK_VER}_setup.exe" \
    -o "$AHK_DIR/setup.exe"
  7z x "$AHK_DIR/setup.exe" -o"$AHK_DIR" AutoHotkeyU64.exe -y > /dev/null
fi

cp -f /home/trader/mt5setup.exe "$WORK/"

# The wizard window is titled "mt5setup.exe" under Wine, never "MetaTrader 5",
# so it is matched by owning process instead of title. Alt+N accepts the
# licence page; the window closing (the installer launches the terminal and
# exits) marks the end. The installer is named explicitly: globbing *.exe here
# would match AutoHotkeyU64.exe first and relaunch AutoHotkey instead.
# Exit codes: 1 = no wizard window, 3 = anti-tamper "debugger found" dialog,
# 4 = wizard never finished (2 is AutoHotkey's own critical-error code).
cat > "$WORK/install.ahk" << 'AHK'
SetTitleMatchMode, 2
Run, C:\windows\temp\mt5\mt5setup.exe
WinWait, ahk_exe mt5setup.exe,, 120
if ErrorLevel
    ExitApp, 1
Sleep, 3000
WinGetText, PageText, ahk_exe mt5setup.exe
IfInString, PageText, debugger
    ExitApp, 3
WinActivate, ahk_exe mt5setup.exe
Send, !n
WinWaitClose, ahk_exe mt5setup.exe,, 900
if ErrorLevel
    ExitApp, 4
ExitApp, 0
AHK

cp -f "$AHK_DIR/AutoHotkeyU64.exe" "$WORK/"
echo "INFO: driving the installer with AutoHotkey"
cd "$WORK"
timeout 1200 wine "$WORK_WIN\\AutoHotkeyU64.exe" "$WORK_WIN\\install.ahk" \
  > /tmp/mt5-install.log 2>&1
rc=$?
echo "INFO: AutoHotkey exited with $rc"

# The installer starts the terminal on completion, so Wine is still busy.
wineserver -k 2> /dev/null || true
sleep 5

if [ ! -s "$TARGET" ]; then
  echo "ERROR: MetaTrader 5 was not installed"
  echo "--- installer output ---"
  tail -40 /tmp/mt5-install.log 2> /dev/null || echo "(none)"
  echo "--- Program Files ---"
  ls -la "$WINEPREFIX/drive_c/Program Files/" 2> /dev/null || true
  exit 1
fi

rm -rf "$WORK"
echo "INFO: installed MetaTrader 5"
du -sh "$MT5_DIR" 2> /dev/null || true
