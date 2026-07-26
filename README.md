# Super Mario Galaxy: Starlight

Starlight is a native Windows recompilation project for the USA release of Super Mario Galaxy
(`RMGE01`). DolRecomp translates the game DOL into native code, while ModernGekko provides the Wii
runtime, graphics, audio, input, filesystem, and timing services.

Game code, extracted data, saves, build products, and logs are kept outside source control.

## Features

- Native RMGE01 module with page-sized code chunks and original Broadway cycle accounting.
- Static-recompiler gameplay path with a fallback JIT for runtime-loaded Wii code.
- First-run shader preparation from a portable RMGE01 pipeline cache.
- Auto, Stretch, 4:3, 16:9, 21:9, and 32:9 presentation modes.
- Centered, proportion-correct game UI on ultrawide displays.
- Ultrawide culling correction for the extra horizontal view.
- Xbox, DualShock, DualSense, SDL gamepad, keyboard, mouse, rumble, and supported gyro input.
- Cubeb capture-compatible audio and optional WASAPI exclusive output.
- Native title frontend, in-game F2 settings, HD texture loading, save import/export, and
  high-refresh presentation.

The game simulation remains at its original 60 Hz. Display and interpolation work are presentation
features and do not advance game state faster.

## Build

Requirements:

- Windows 10 or 11
- Visual Studio 2022 Build Tools with the Desktop C++ workload
- CMake and Git
- An extracted USA `RMGE01` game tree

From PowerShell:

```powershell
git submodule update --init --recursive
.\tools\Apply-UpstreamPatches.ps1
.\tools\Build-Upstream.ps1 -Target DolRecomp
.\tools\Build-Upstream.ps1 -Target ModernGekko
.\tools\Build-Module.ps1
```

To extract and verify a supported disc image:

```powershell
.\tools\Extract-Game.ps1
```

Run the project:

```powershell
.\tools\Play-Game.ps1 -Launcher
```

The direct runner remains available through `.\tools\Play-Game.ps1`. Press F2 while playing to open
the in-game settings panel.

## Source layout

- `docs/` — architecture, bring-up notes, research, and roadmap
- `patches/moderngekko/0006-starlight-complete.patch` — complete ModernGekko changes
- `patches/recompcore/0008-starlight-complete.patch` — complete runtime changes
- `patches/dolrecomp/0005-starlight-complete.patch` — complete DolRecomp changes
- `tools/` — extraction, build, launch, benchmark, and diagnostics scripts

The numbered older patches are retained as development history where useful.
`Apply-UpstreamPatches.ps1` uses the complete patches so a clean checkout can be reproduced in one
pass per upstream repository.

See [architecture.md](docs/architecture.md), [bringup.md](docs/bringup.md),
[research.md](docs/research.md), and [roadmap.md](docs/roadmap.md).
