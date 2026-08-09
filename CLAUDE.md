# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

EA31337 is a multi-strategy Forex trading robot (Expert Advisor) written in MQL4/MQL5 for
MetaTrader 4/5. The repository is mostly glue: the EA entry point, per-edition input
definitions, and build/test tooling. The bulk of the logic (framework classes, strategies,
indicators) lives in git submodules.

## Submodules are mandatory

Nothing compiles without them:

```sh
git submodule update --init --recursive
```

| Path | Repo | Contains |
| --- | --- | --- |
| `src/include/classes` | EA31337-classes | Framework (`EA`, `Strategy`, `Trade`, `Chart`, indicators) |
| `src/strategies` | EA31337-strategies | `Stg_*` strategy classes |
| `src/strategies-meta` | EA31337-strategies-meta | `Stg_Meta_*` composite strategies |
| `src/indicators` | EA31337-indicators | Custom indicator sources |
| `docs/wiki` | EA31337.wiki | Wiki content |

## Build

Compilation runs MetaEditor under Wine. Requires `git`, `ex`, Wine, and a MetaEditor
binary in the repo root — see "Supplying MetaEditor" below, because the Makefile can no
longer download one.

```sh
make Lite                 # Lite build -> ./EA31337-Lite-v3.000.ex4
make Advanced             # Advanced build
make Rider                # Rider build
make Lite-Release         # + __release__
make Advanced-Backtest    # + __backtest__
make Rider-Optimize       # + __optimize__
make All                  # every edition x every optional mode
make compile-mql4         # compile only, using current mode.h
make compile-mql5
make clean-src            # remove src/*.ex4, src/*.ex5
make mt4-install          # install the .ex4 into the Wine MT4 Experts folder
```

Without Wine, use the Docker wrappers instead (they mount the repo and run the same Makefile
targets in `ea31337/ea-tester`):

```sh
docker compose -f docker/compile/lite/docker-compose.yml up
```

Note the image bundles **no** MetaEditor and no Wine prefix — it installs MetaTrader at
runtime via Ansible (`/opt/scripts/install_mt{4,5}.sh` → `/opt/ansible/install-mt{4,5}.yml`,
role `ea31337.metatrader`, using the official MetaQuotes installer under xvfb). The MT5 URL
is unpinned and serves the current build, so Docker hits the same version problem described
below; only its MT4 URL is pinned.

The EA version string lives in `src/include/common/define.h` (`ea_version`); the Makefile's
`VER` is derived from it via grep, and it ends up in the output filename.

### Supplying MetaEditor

`make` used to fetch MetaEditor from `EA31337/MT-Platforms`, but that repository was taken
down and now returns **HTTP 451**, so the download fails permanently. Supply the binary
yourself by copying `metaeditor.exe` from an MT4 installation into the repo root; `MTE`
picks it up automatically, and `.gitignore`'s `*.ex?` keeps it untracked.

**Use MT4's MetaEditor, not MT5's.** Current MT5 editors (build 6104 tested) reject the
pinned `EA31337-classes` framework with ~100 errors — `error 226: not allowed for objects
with protected members or inheritance` and `warning 89: ... due to new rules of method
hiding` — concentrated in `DictStruct.mqh`, `Dict.mqh`, and `Indicator.mqh`. The framework
predates those language rules. MT4's compiler is frozen, accepts the code, and is the right
tool anyway since the default targets all build `.mq4`. This is not an MQL4-vs-MQL5 issue:
both dialects fail identically (101 vs 100 errors) under a modern MT5 editor.

The developers' own pinned MT4 build, from `install-mt4.yml`, installs headlessly:

```sh
curl -fLO https://download.mql5.com/cdn/web/3315/mt4/xm4setup.exe
WINEPREFIX=~/.mt4 wine xm4setup.exe /auto
cp ~/.mt4/drive_c/Program\ Files\ \(x86\)/XM\ MT4/metaeditor.exe .
```

Two Makefile variables absorb the environment differences, both overridable:

- `WINE` — prefers `wine64`, falls back to `wine`. Wine 10+ builds are WoW64 and ship only
  `wine`, while the Makefile historically hardcoded `wine64`. No symlink needed.
- `MTE` — prefers `metaeditor.exe` when present, else `metaeditor64.exe`.

Compiler diagnostics go to `logs/metaeditor.log` (UTF-16LE, summary only). For the full
error list, pass an explicit log file, since `/log:CON` does not reach stdout:

```sh
wine metaeditor.exe /log:logs/compile.log /compile:"src\EA31337.mq5" /inc:"src"
iconv -f UTF-16LE -t UTF-8 logs/compile.log | less
```

Build one edition per `make` invocation. `make Lite Advanced Rider` silently produces three
identical binaries, because the `set-*` targets mutate shared state in `mode.h` and multiple
goals do not serialise against it. Run `make Lite && make Advanced && make Rider` instead;
correct output has distinct sizes, ascending Lite < Advanced < Rider.

### Modern MT5 compatibility

MT5 build 5260 turned method hiding into a hard error: a derived method with a base method's
name now *hides* rather than overloads it, and `using Base::Method;` is the sanctioned
remedy. The same release tightened implicit copying of objects with protected members or
inheritance. See the [build 5260 release notes][mt5-5260]. This broke the framework, which
predates those rules — the compiler had warned for years via *"deprecated behavior, hidden
method calling will be disabled in a future MQL compiler version"*.

It is not an MQL4-versus-MQL5 problem: both dialects failed identically (101 vs 100 errors)
under a modern MT5 editor.

Getting to a clean build took three steps, each measured against build 6104:

| Step | Change | Errors |
| --- | --- | --- |
| — | pinned framework | 100 |
| 1 | `src/include/classes` → upstream `v3.000.2-dev` | 6 |
| 2 | `using PatternCandle::CheckPattern;` in `PatternCandle1..4` | 2 |
| 3 | converting constructor on `Retracement_BarOHLC` | 0 |

Step 1 does nearly all of it and is upstream's own work — commit `bd8f527d` *"Fixing
compilation errors due to more strict code syntax requirements in new MT5 editor"*. Note the
framework's `dev` and `master` branches are dormant since 2023; active development lives on
versioned `vX.Y-dev` branches, and `v3.000.2-dev` was updated in 2026.

Steps 2 and 3 are carried locally in `patches/`, because `strategies` has no matching update
(its newest branch is from 2024-10). The parent repo can only record submodule SHAs, never
their working-tree edits, so re-cloning or running `git submodule update` discards them:

```sh
git -C src/include/classes apply ../../../patches/0001-classes-mt5-build5260-method-hiding.patch
git -C src/strategies/Retracement apply ../../../patches/0002-retracement-derived-bar-ctor.patch
```

The `using` declarations are wrapped in `#ifdef __MQL5__`. That operator only exists from
build 5260, so MT4's compiler rejects it outright — leaving them unguarded builds MQL5 but
breaks every default (MQL4) target.

Verified after all three steps: MQL4 via MT4's editor, 0 errors / 0 warnings; MQL5 via build
6104, 0 errors / 1 warning.

[mt5-5260]: https://www.metatrader5.com/en/releasenotes/terminal/2403

## Build modes: how editions are selected

Everything is preprocessor-driven through `src/include/common/mode.h`. Uncommenting a
`#define` there selects the edition (`__advanced__`, `__rider__`, `__elite__`; Lite is the
default with none set) or an optional mode (`__backtest__`, `__optimize__`, `__release__`,
`__cli__`, `__debug__`, `__resource__`, `__input__`, ...).

**The Makefile rewrites `mode.h` in place** (`set-mode` uses `ex` to uncomment lines) and then
restores it with `git checkout -- src/include/common/mode.h` (`set-none`). Uncommitted manual
edits to `mode.h` will be silently discarded by any `make` target. CI instead overwrites the
file wholesale, e.g. `echo '#define __cli__' > src/include/common/mode.h`.

`src/include/common/code-conf.h` derives implied modes from the selected ones — `__rider__`
implies `__advanced__`, `__elite__` implies `__input2__`, `__release__`/`__optimize__` undefine
debug/backtest flags. Add new cross-mode implications there, not in `mode.h`.

## Architecture

`src/EA31337.mq4` is a thin shim that `#include`s `src/EA31337.mq5`; **all real code is the
`.mq5` file**, guarded with `#ifdef __MQL5__` where the platforms diverge. Edit the `.mq5`.

Include chain: `EA31337.mq5` → `include/ea.h` → `include/includes.h`, which pulls in
`common/mode.h` → `code-conf.h` → `define.h` → `enum.h` → framework classes → `common/struct.h`
→ submodule strategy enums → strategy managers → `include/inputs.h` → strategy includes.
Order matters — these headers depend on macros defined earlier in the chain.

- `include/ea.h` defines `class EA31337 : public EA` (the framework base class). It owns
  `StrategyAddToTf`/`StrategyAddToTfs` (strategy instantiation, magic-number assignment),
  `StrategyAddStops`, task creation from `ENUM_EA_ADV_COND`/`ENUM_EA_ADV_ACTION`, and chart
  display.
- `EA31337.mq5` holds the MQL event handlers (`OnInit`, `OnTick`, `OnTester*`, ...) plus
  `InitStrategies()`, which wires inputs to the EA instance. Note the two shapes:
  Lite/Advanced/Rider assign one strategy per timeframe (`Strategy_M1`, `Strategy_M5`, ...
  gated by the `EA_Strategy_Filter` bitmask); Elite (`__elite__`) runs a single main strategy
  (usually a meta strategy) across a timeframe bitmask (`EA_Strategy1_Tfs`).
- `common/strategies-manager.h` / `strategies-manager-meta.h` map `ENUM_STRATEGY` /
  `ENUM_STRATEGY_META` values to concrete `Stg_*` classes via a big switch, with a cache keyed
  by `<sid>@<tf>`. These files, plus `common/enum.h`, deliberately **override** the copies
  provided by the submodules (see the comments in `includes.h`). To add a strategy you must
  touch both the enum and the manager switch here, not only the submodule.
- Per-edition configuration is split into `common/{lite,advanced,rider,elite}/`:
  `defines.h` sets `ea_name`, `inputs.mqh` declares that edition's `input` parameters.
  `include/inputs.h` picks one of them based on the mode macros and then declares the
  shared risk/trade/logging inputs. Inputs are declared twice — `extern`/`input string`
  section headers for MQL4 vs `input group` for MQL5.

## Testing and CI

There is no unit-test suite; verification is compilation plus backtesting.

- `.github/workflows/check.yml` — pre-commit hooks on every push/PR.
- `.github/workflows/compile.yml` — Windows matrix: {Lite, Advanced, Elite, Rider} ×
  {`__input__`, `__resource__`} × {MQL4, MQL5}. This is the real compile gate.
- `.github/workflows/test.yml` — compiles, then runs MT5 backtests (EURUSD M1, 2 weeks of
  2022 and 2024) per edition via `fx31337/mql-tester-action`.
- `.github/workflows/backtest.yml` — triggered by releases and `v*-backtest` branches.
- `.github/workflows/optimize-*.yml` — each triggers only on a push to its own branch
  (`optimize-tf`, `optimize-risk`, `optimize-strats-oct`, `optimize-strats-soft`,
  `optimize-strats-stops`) and consumes the `.set` files under
  `sets/optimize/<Edition>/<group>/`.

Local backtesting via the `ea31337/ea-tester` image (needs the `.ex4`/`.ex5` built first);
settings come from the adjacent `EA-Tester.ini`, results land in `_results/`:

```sh
docker compose -f docker/tests/Advanced/docker-compose.yml up      # month-by-month, one year
docker compose -f docker/backtest/Lite/all-yearly/2021/docker-compose.yml up
```

Run `make test` to syntax-check both `.mq4` and `.mq5` through MetaEditor without producing
release artifacts.

## Conventions

- Lint everything with `pre-commit run --all-files`. Hooks: markdownlint (`.markdownlint.yaml`),
  yamllint (`.yamllint`), shfmt, `require-ascii`, `forbid-binary`, `git-check` (attributes in
  `.gitattributes`).
- MQL/C++ formatting: `.clang-format` — Google style, 120-column limit,
  `IndentPPDirectives: BeforeHash`.
- `.editorconfig`: LF, UTF-8, 2-space indent (tabs in the Makefile), final newline.
- `.mqproj` files are UTF-16LE-BOM per `.gitattributes`; `*.ex?` are binary and must not be
  committed (`forbid-binary` enforces this).
- `master` is the release branch; work merges into it via `dev`.
