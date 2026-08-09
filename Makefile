SHELL:=/usr/bin/env bash

.PHONY: all help test compile-mql4 compile-mql5 requirements \
		set-none set-testing \
		set-lite set-advanced set-rider set-elite \
		set-lite-release set-advanced-release set-rider-release set-elite-release \
		set-lite-backtest set-advanced-backtest set-rider-backtest set-elite-backtest \
		set-lite-optimize set-advanced-optimize set-rider-optimize set-elite-optimize \
		clean clean-src clean-releases \
		indicators-mql4 indicators-mql5 mt4-install mt5-install mt5-install-indicators \
		EA Lite Advanced Rider Elite \
		Release Lite-Release Advanced-Release Rider-Release Elite-Release \
		Backtest Lite-Backtest Advanced-Backtest Rider-Backtest Elite-Backtest \
		Optimize Lite-Optimize Advanced-Optimize Rider-Optimize Elite-Optimize \
		All Lite-All Advanced-All Rider-All Elite-All

# MetaEditor binary to compile with. MT4's metaeditor.exe is preferred when
# present: recent MT5 editors reject the pinned framework under their newer
# language rules (method hiding, struct copying), whereas MT4's compiler
# accepts it and handles the MQL4 targets built by default.
MTE?=$(if $(wildcard metaeditor.exe),metaeditor.exe,metaeditor64.exe)
# MetaEditor for the MQL5 targets. MT4's editor cannot compile .mq5 at all, so
# these never fall back to MTE when it resolves to metaeditor.exe.
MTE5?=$(if $(wildcard metaeditor64.exe),metaeditor64.exe,$(MTE))
MTV=5.0.0.2361
SRC=src
MQL4=$(wildcard $(SRC)/*.mq4)
MQL5=$(wildcard $(SRC)/*.mq5)
EA=EA31337
# Custom indicators embedded by the __resource__ mode. #resource references the
# compiled binary, so these must be built before an EA that enables that mode.
# ATR_MA_Trend and SuperTrend are MQL5-only; EA31337.mq4 omits both.
INDI5=Other/Misc/ATR_MA_Trend Other/Oscillators/Arrows/ATR_MA_Slope \
	Other/Oscillators/Multi/Elliott_Wave_Oscillator2 \
	Other/Oscillators/Multi/SVE_Bollinger_Bands Other/Price/Range/TMA+CG_mladen_NRP \
	Other/Price/Range/TMA_True Other/Price/Range/SAWA Other/Price/SuperTrend
INDI4=Other/Oscillators/Arrows/ATR_MA_Slope \
	Other/Oscillators/Multi/Elliott_Wave_Oscillator2 \
	Other/Oscillators/Multi/SVE_Bollinger_Bands Other/Price/Range/TMA+CG_mladen_NRP \
	Other/Price/Range/TMA_True Other/Price/Range/SAWA
# Wine prefixes holding the platform installs, used by the mt?-install targets.
MT4_PREFIX?=$(HOME)/.wine
MT5_PREFIX?=$(HOME)/.mt5
MT4_DIR=$(shell find $(MT4_PREFIX) -name terminal.exe -execdir pwd ';' -quit 2> /dev/null)
MT5_DIR=$(shell find $(MT5_PREFIX) -name terminal64.exe -execdir pwd ';' -quit 2> /dev/null)
EX4=$(SRC)/$(EA).ex4
EX5=$(SRC)/$(EA).ex5
VER=v$(shell grep 'define ea_version' $(SRC)/include/common/define.h | grep -o '[0-9].*[0-9]')
FILE=$(lastword $(MAKEFILE_LIST)) # Determine this Makefile's path.
OUT=.
MKFILE=$(abspath $(lastword $(MAKEFILE_LIST)))
CWD=$(notdir $(patsubst %/,%,$(dir $(MKFILE))))
WINEDEBUG=fixme-all
# Wine binary. Builds since Wine 10 are WoW64 and ship "wine" only, with no
# separate wine64, so fall back to it when wine64 is absent.
WINE?=$(shell command -v wine64 2> /dev/null || command -v wine 2> /dev/null)

# Shown when make runs with no target. Keep it before any other target so that
# it stays the default goal.
help:
	@echo "EA31337 $(VER) - build an Expert Advisor with MetaEditor under Wine."
	@echo
	@echo "Editions:   Lite  Advanced  Rider  Elite"
	@echo "Variants:   <Edition>-Release  <Edition>-Backtest  <Edition>-Optimize"
	@echo "            <Edition>-All        (all four variants of one edition)"
	@echo "Groups:     EA  Release  Backtest  Optimize  All"
	@echo
	@echo "Compiling:  compile-mql4  compile-mql5  test"
	@echo "            indicators-mql4  indicators-mql5   (custom indicators)"
	@echo "Modes:      set-none  set-testing  set-<edition>[-release|-backtest|-optimize]"
	@echo "Installing: mt4-install  mt5-install  mt5-install-indicators"
	@echo "Other:      clean-src  requirements  help"
	@echo
	@echo "Variables:  MTE=$(MTE)   (MQL4)"
	@echo "            MTE5=$(MTE5)   (MQL5)"
	@echo "            WINE=$(WINE)"
	@echo "            OUT=$(OUT)  SRC=$(SRC)"
	@echo
	@echo "Output:     $(OUT)/$(EA)-<Edition>-$(VER).ex4"
	@echo
	@echo "Build one edition per invocation. Combining goals (make Lite Advanced)"
	@echo "yields identical binaries, as the set-* targets share state in mode.h."

requirements:
	type -a git ex &> /dev/null
	@test -n "$(WINE)" || { echo "Wine not found. Install wine (or wine-staging)."; exit 1; }

Lite:				$(OUT)/$(EA)-Lite-%.ex4
Advanced:			$(OUT)/$(EA)-Advanced-%.ex4
Rider:				$(OUT)/$(EA)-Rider-%.ex4
Elite:				$(OUT)/$(EA)-Elite-%.ex4

Lite-Release: 			$(OUT)/$(EA)-Lite-Release-%.ex4
Advanced-Release:		$(OUT)/$(EA)-Advanced-Release-%.ex4
Rider-Release:			$(OUT)/$(EA)-Rider-Release-%.ex4
Elite-Release:			$(OUT)/$(EA)-Elite-Release-%.ex4

Lite-Backtest:			$(OUT)/$(EA)-Lite-Backtest-%.ex4
Advanced-Backtest:		$(OUT)/$(EA)-Advanced-Backtest-%.ex4
Rider-Backtest:			$(OUT)/$(EA)-Rider-Backtest-%.ex4
Elite-Backtest:			$(OUT)/$(EA)-Elite-Backtest-%.ex4

Lite-Optimize:			$(OUT)/$(EA)-Lite-Optimize-%.ex4
Advanced-Optimize:		$(OUT)/$(EA)-Advanced-Optimize-%.ex4
Rider-Optimize:			$(OUT)/$(EA)-Rider-Optimize-%.ex4
Elite-Optimize:			$(OUT)/$(EA)-Elite-Optimize-%.ex4

Lite-All:			Lite Lite-Release Lite-Backtest Lite-Optimize
Advanced-All:			Advanced Advanced-Release Advanced-Backtest Advanced-Optimize
Rider-All:			Rider Rider-Release Rider-Backtest Rider-Optimize
Elite-All:			Elite Elite-Release Elite-Backtest Elite-Optimize

All:				requirements $(MTE) Lite-All Advanced-All Rider-All Elite-All

test: requirements set-mode $(MTE)
	$(WINE) $(MTE) .exe /s /i:$(SRC) /mql4 $(MQL4)
	$(WINE) $(MTE5) /s /i:$(SRC) /mql5 $(MQL5)

# Fetching MetaEditor this way no longer works: the MT-Platforms repository was
# taken down (HTTP 451), so -f turns the 451 into a readable failure instead of
# unzip choking on an HTML error page. Supply MetaEditor yourself instead, by
# copying metaeditor.exe from an MT4 installation into this directory.
$(MTE):
	curl -fLO https://github.com/EA31337/MT-Platforms/releases/download/$(MTV)/mt-$(MTV).zip \
		|| { echo "Cannot download $(MTE). Copy it from a MetaTrader installation into $(CURDIR)."; exit 1; }
	unzip -o mt-$(MTV).zip */$(MTE)
	cp -v */$(MTE) .

# E.g.: make set-mode MODE="__advanced__"
set-mode:
ifdef MODE
	test -w .git && git checkout -- $(SRC)/include/common/mode.h || true
	ex +"%s@^\zs.*\ze#define \($(MODE)\)@@g" -scwq! $(SRC)/include/common/mode.h
endif

set-none:
	@echo Reverting modes.
	test -w .git && git checkout -- $(SRC)/include/common/mode.h || true
	test -w $(SRC) && ex +":g@^#define@s@^@//" -scwq! $(SRC)/include/common/mode.h || true

set-lite: set-none
	@$(MAKE) -f $(FILE) requirements

set-advanced: set-none
	@$(MAKE) -f $(FILE) set-mode MODE="__advanced__"

set-rider: set-none
	@$(MAKE) -f $(FILE) set-mode MODE="__rider__"

set-lite-release: set-none
	@$(MAKE) -f $(FILE) set-mode MODE="__release__"

set-advanced-release: set-none
	@$(MAKE) -f $(FILE) set-mode MODE="__release__\|__advanced__"

set-rider-release: set-none
	@$(MAKE) -f $(FILE) set-mode MODE="__release__\|__rider__"

set-lite-backtest: set-none
	@$(MAKE) -f $(FILE) set-mode MODE="__backtest__"

set-advanced-backtest: set-none
	@$(MAKE) -f $(FILE) set-mode MODE="__backtest__\|__advanced__"

set-rider-backtest: set-none
	@$(MAKE) -f $(FILE) set-mode MODE="__backtest__\|__rider__"

set-lite-optimize: set-none
	@$(MAKE) -f $(FILE) set-mode MODE="__optimize__"

set-advanced-optimize: set-none
	@$(MAKE) -f $(FILE) set-mode MODE="__optimize__\|__advanced__"

set-rider-optimize: set-none
	@$(MAKE) -f $(FILE) set-mode MODE="__optimize__\|__rider__"

set-elite: set-none
	@$(MAKE) -f $(FILE) set-mode MODE="__elite__"

set-elite-release: set-none
	@$(MAKE) -f $(FILE) set-mode MODE="__release__\|__elite__"

set-elite-backtest: set-none
	@$(MAKE) -f $(FILE) set-mode MODE="__backtest__\|__elite__"

set-elite-optimize: set-none
	@$(MAKE) -f $(FILE) set-mode MODE="__optimize__\|__elite__"

set-testing:
	@$(MAKE) -f $(FILE) set-mode MODE="__testing__"

clean-all: clean-src

clean-src:
	@echo Cleaning src...
	find $(SRC)/ -maxdepth 1 '(' -name '*.ex4' -or -name '*.ex5' ')' -delete -print

EA: $(MTE) \
		clean-all \
		$(OUT)/$(EA)-Lite-%.ex4 \
		$(OUT)/$(EA)-Advanced-%.ex4 \
		$(OUT)/$(EA)-Rider-%.ex4 \
		$(OUT)/$(EA)-Elite-%.ex4

Release: $(MTE) \
		clean-all \
		$(OUT)/$(EA)-Lite-Release-%.ex4 \
		$(OUT)/$(EA)-Advanced-Release-%.ex4 \
		$(OUT)/$(EA)-Rider-Release-%.ex4 \
		$(OUT)/$(EA)-Elite-Release-%.ex4

Backtest: $(MTE) \
		clean-all \
		$(OUT)/$(EA)-Lite-Backtest-%.ex4 \
		$(OUT)/$(EA)-Advanced-Backtest-%.ex4 \
		$(OUT)/$(EA)-Rider-Backtest-%.ex4 \
		$(OUT)/$(EA)-Elite-Backtest-%.ex4

Optimize: $(MTE) \
		clean-all \
		$(OUT)/$(EA)-Lite-Optimize-%.ex4 \
		$(OUT)/$(EA)-Advanced-Optimize-%.ex4 \
		$(OUT)/$(EA)-Rider-Optimize-%.ex4 \
		$(OUT)/$(EA)-Elite-Optimize-%.ex4

compile-mql4: requirements $(MTE) $(SRC)/$(EA).mq4 $(SRC)/include/common/mode.h clean-src
	file='$(MQL4)'; $(WINE) $(MTE) /log:CON /compile:"$${file//\//\\}" /inc:"$(SRC)" || true
	test -s $(SRC)/$(EA).ex4 && echo $(MQL4) compiled.

compile-mql5: requirements $(SRC)/$(EA).mq5 $(SRC)/include/common/mode.h clean-src
	@test -s "$(MTE5)" || { echo "$(MTE5) not found; copy metaeditor64.exe from an MT5 installation."; exit 1; }
	file='$(MQL5)'; $(WINE) $(MTE5) /log:CON /compile:"$${file//\//\\}" /inc:"$(SRC)" || true
	test -s $(SRC)/$(EA).ex5 && echo $(MQL5) compiled.

$(OUT)/$(EA)-Lite-%.ex4: \
		set-lite \
		compile-mql4 \
		set-none
		cp -v "$(EX4)" "$(OUT)/$(EA)-Lite-$(VER).ex4"

$(OUT)/$(EA)-Advanced-%.ex4: \
		set-advanced \
		compile-mql4 \
		set-none
		cp -v "$(EX4)" "$(OUT)/$(EA)-Advanced-$(VER).ex4"

$(OUT)/$(EA)-Rider-%.ex4: \
		set-rider \
		compile-mql4 \
		set-none
		cp -v "$(EX4)" "$(OUT)/$(EA)-Rider-$(VER).ex4"

$(OUT)/$(EA)-Lite-Release-%.ex4: \
		set-lite-release \
		compile-mql4 \
		set-none
		cp -v "$(EX4)" "$(OUT)/$(EA)-Lite-Release-$(VER).ex4"

$(OUT)/$(EA)-Advanced-Release-%.ex4: \
		set-advanced-release \
		compile-mql4 \
		set-none
		cp -v "$(EX4)" "$(OUT)/$(EA)-Advanced-Release-$(VER).ex4"

$(OUT)/$(EA)-Rider-Release-%.ex4: \
		set-rider-release \
		compile-mql4 \
		set-none
		cp -v "$(EX4)" "$(OUT)/$(EA)-Rider-Release-$(VER).ex4"

$(OUT)/$(EA)-Lite-Backtest-%.ex4: \
		set-lite-backtest \
		compile-mql4 \
		set-none
		cp -v "$(EX4)" "$(OUT)/$(EA)-Lite-Backtest-$(VER).ex4"

$(OUT)/$(EA)-Advanced-Backtest-%.ex4: \
		set-advanced-backtest \
		compile-mql4 \
		set-none
		cp -v "$(EX4)" "$(OUT)/$(EA)-Advanced-Backtest-$(VER).ex4"

$(OUT)/$(EA)-Rider-Backtest-%.ex4: \
		set-rider-backtest \
		compile-mql4 \
		set-none
		cp -v "$(EX4)" "$(OUT)/$(EA)-Rider-Backtest-$(VER).ex4"

$(OUT)/$(EA)-Lite-Optimize-%.ex4: \
		set-lite-optimize \
		compile-mql4 \
		set-none
		cp -v "$(EX4)" "$(OUT)/$(EA)-Lite-Optimize-$(VER).ex4"

$(OUT)/$(EA)-Advanced-Optimize-%.ex4: \
		set-advanced-optimize \
		compile-mql4 \
		set-none
		cp -v "$(EX4)" "$(OUT)/$(EA)-Advanced-Optimize-$(VER).ex4"

$(OUT)/$(EA)-Rider-Optimize-%.ex4: \
		set-rider-optimize \
		compile-mql4 \
		set-none
		cp -v "$(EX4)" "$(OUT)/$(EA)-Rider-Optimize-$(VER).ex4"

$(OUT)/$(EA)-Elite-%.ex4: \
		set-elite \
		compile-mql4 \
		set-none
		cp -v "$(EX4)" "$(OUT)/$(EA)-Elite-$(VER).ex4"

$(OUT)/$(EA)-Elite-Release-%.ex4: \
		set-elite-release \
		compile-mql4 \
		set-none
		cp -v "$(EX4)" "$(OUT)/$(EA)-Elite-Release-$(VER).ex4"

$(OUT)/$(EA)-Elite-Backtest-%.ex4: \
		set-elite-backtest \
		compile-mql4 \
		set-none
		cp -v "$(EX4)" "$(OUT)/$(EA)-Elite-Backtest-$(VER).ex4"

$(OUT)/$(EA)-Elite-Optimize-%.ex4: \
		set-elite-optimize \
		compile-mql4 \
		set-none
		cp -v "$(EX4)" "$(OUT)/$(EA)-Elite-Optimize-$(VER).ex4"

mt4-install:
		@test -n "$(MT4_DIR)" || { echo "No MT4 found under $(MT4_PREFIX); set MT4_PREFIX."; exit 1; }
		install -v "$(EX4)" "$(MT4_DIR)/MQL4/Experts"

mt5-install: compile-mql5
		@test -n "$(MT5_DIR)" || { echo "No MT5 found under $(MT5_PREFIX); set MT5_PREFIX."; exit 1; }
		install -v "$(EX5)" "$(MT5_DIR)/MQL5/Experts"

# Without __resource__ the EA loads these by plain name via iCustom, so they must
# sit in the terminal's Indicators folder. Run indicators-mql5 first.
mt5-install-indicators:
		@test -n "$(MT5_DIR)" || { echo "No MT5 found under $(MT5_PREFIX); set MT5_PREFIX."; exit 1; }
		@for i in $(INDI5); do \
			test -s "$(SRC)/indicators/$$i.ex5" \
				&& install -v "$(SRC)/indicators/$$i.ex5" "$(MT5_DIR)/MQL5/Indicators" \
				|| echo "missing $$i.ex5 - run: make indicators-mql5"; \
		done

# The indicators include <EA31337-classes/...>, the layout CI builds them in, so
# expose the framework submodule under that name within the include root.
$(SRC)/include/EA31337-classes:
		ln -sfn classes $@

# Compiles the custom indicators embedded by the __resource__ mode. Needs an MT5
# MetaEditor, so it overrides MTE when the auto-detected one is MT4's.
indicators-mql5: $(SRC)/include/EA31337-classes
		@test -s metaeditor64.exe || { echo "metaeditor64.exe required; copy it from an MT5 installation."; exit 1; }
		@for i in $(INDI5); do \
			$(WINE) metaeditor64.exe /log:CON /compile:"$(SRC)\\indicators\\$${i//\//\\}.mq5" /inc:"$(SRC)" > /dev/null 2>&1 || true; \
			test -s "$(SRC)/indicators/$$i.ex5" && echo "compiled $$i.ex5" || echo "FAILED $$i.mq5"; \
		done

indicators-mql4: $(SRC)/include/EA31337-classes
		@for i in $(INDI4); do \
			$(WINE) $(MTE) /log:CON /compile:"$(SRC)\\indicators\\$${i//\//\\}.mq4" /inc:"$(SRC)" > /dev/null 2>&1 || true; \
			test -s "$(SRC)/indicators/$$i.ex4" && echo "compiled $$i.ex4" || echo "FAILED $$i.mq4"; \
		done
