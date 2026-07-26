# RMGE01 bring-up record

## Exact target

- Disc ID: `RMGE01`
- Entry point: `0x8000403C`
- ISO SHA-256: `b47683440931bcf1a604c20fbad22b918977e20db4965df108050342f4857b8e`
- `main.dol` SHA-256: `2c680585a8f58e1cc9c5521b579057f12b124ff0ef409e470a57606c50a93c09`

## Pinned sources

- DolRecomp: `3606fbd226951631fd258e81fb26854ae9bbd21f`
- ModernGekko: `11237c119a5d8e907a20e9cae1c357df149aaa47`
- ModernGekko RecompCore: `1873066167f3d03b39771b547f280d2b970427b6`

## Implemented runtime bridge

- Win32 NoGUI platform support and deterministic MSVC builds
- Exact-revision gate before module generation or execution
- SPR runtime bridge and canonical MEM1 executable aliases
- Interpreter exception-vector fallback that returns to native dispatch
- Dynamic PPC idle-loop analysis tied to CoreTiming
- Fingerprinted DolRecomp cache identity, including the local patch-set revision
- Broadway cycle accounting in every generated chunk

## Verified module

- Artifact key: `88d4a9dd78c252a7`
- DLL SHA-256: `b0fe56cc10e04ae4236e85a304eb2d18f0bf57efcb3934c89c9d9894e24e5b57`
- Module ABI: `2`; CPU ABI: `2`; CPU state: `3504` bytes
- Code ranges: `2`; SMC ranges: `19`; chunk ranges: `331`
- The `SelectThread` loop at `0x804AB358` charges exactly three cycles.
- Generated code carries two dispatch optimizations: `ctx->pc` is stored only
  at control transfers (branch terminators and exception helpers receive the
  instruction address as an argument), and exception-free cache maintenance
  (`dcbst`/`dcbf`/`icbi`) falls through natively instead of bouncing through
  the dispatcher. On the same runtime this module executes ~50% more
  dispatches per second than the unoptimized `f42699ab1d7e8687`.

## Native smoke result

The automatic-idle test on 2026-07-16 executed `76,070,591` native dispatches, reached `3,252,807,094` guest ticks, detected 12 idle loops, kept interpreter fallback to 1.15%, and reported zero failed SMC verifications.

The first fallback at `0x00000C00` is expected Wii system-call exception handling. It returns to native code at `0x804A2F4C`; a nonzero bounded fallback count is therefore correct.

## First rendered frame

The static-recompiled module renders the Wii Remote safety screen under D3D, byte-for-byte matching the JIT reference by the frame-brightness oracle (mean 245 at unique valid present 120). Capture: `work/rmge01-fixed-static-capture.png`.

Root cause of the previous black frame: two DolRecomp emitter defects, fixed in `patches/dolrecomp/0002-paired-single-slot-semantics.patch`.

1. Cross-slot write hazards. `ps_merge00/10`, `ps_sum1`, `ps_muls0`, and `ps_madds0` emitted the ps0 store before reading operands for ps1, so when the destination aliased a source (`ps_merge00 f2, f4, f2` in `PSMTXRotTrig`'s Z case at `0x804B6258`) the second slot read the clobbered value. Every Z-rotation matrix row became `[cos, cos, ...]` instead of `[cos, -sin, ...]`, degenerating all 2D safety-screen geometry. All cross-slot paired ops now compute both slots into temporaries before writing.
2. Missing single-precision replication. `fadds/fsubs/fmuls/fdivs/frsp` wrote only ps0, while Gekko (and Dolphin) duplicate single-precision results into both slots; `fres` and the `fmadds` family already replicated.

The defect was isolated with a forced-interpreter address-range bisection (`STATICRECOMP_INTERPRET_START/END`) driven by a D3D frame-brightness oracle: full-range interpretation rendered identically to JIT, exonerating the runtime bridge, and thirteen probes narrowed the culprit to the 192-byte window containing `PSMTXRotTrig`.

## Diagnostic tooling

- `Run-Game.ps1 -TraceVideo` reports XFB/VI/present/draw statistics at shutdown.
- `Run-Game.ps1 -CaptureFrame <png> -CaptureFrameAfter <n>` saves the renderer output at the n-th unique valid present.
- `Run-Game.ps1 -TraceGather <bin> -TraceGatherBursts <n>` records the first n 32-byte gather-pipe bursts with FNV hashes, dispatch context, and CoreTiming tick stamps (format `MGFIFOH6`); `tools/diag/Compare-GatherTrace.ps1` diffs two traces.
- `Run-Game.ps1 -CpuCore jit|static|cached-interpreter|interpreter` selects the reference or recompiled CPU for A/B comparison.
- `--stop-after-ms` first requests a graceful STM shutdown, which RMGE01 rejects and spins on; after five seconds the runner escalates to a forced stop.
- `STATICRECOMP_INTERPRET_START/END` forces an address range through the interpreter fallback; `tools/diag/Run-InterpProbe.ps1` automates one bisection probe with the brightness oracle.

## Input and menu progression

Dolphin's emulated Wii Remote works out of the box: Wiimote 1 defaults to Emulated with the stock keyboard/mouse profile (A = left click, B = right click, IR pointer = mouse, shake = middle click, D-Pad = arrows, 1/2 = keys 1/2, -/+ = Q/E, Home = Enter, Nunchuk attached with WASD stick and Ctrl/Shift for C/Z). With synthesized clicks the native module advances strap screen (A) → title screen (A + B together) → "Please choose a file." file select, with the star pointer tracking the mouse. `tools/Play-Game.ps1` launches this configuration; `config.ini`'s `controller=` key generates a sideways-Wiimote SDL gamepad mapping instead.

## JIT-slice fallback for out-of-module code

RMGE01 loads `HomeButtonMenuWrapperRSO.rso` into MEM2 (~0x91F00000) and runs it every frame. Single-step interpreting it cost ~24% of all guest instructions and capped menus below 20 FPS. Out-of-module PCs (exception vectors, MEM2 modules) now lease one CoreTiming slice at a time to the already-instantiated fallback Jit64: `Jit64AsmRoutineManager` gained an exit-after-slice flag so `Run()` returns at the slice boundary, `StaticRecompCore::HandleFault` forwards fastmem faults to the fallback JIT, and BLR optimization stays disarmed on the leased instance. Interpreter fallback drops to zero (`jit_slices` counts leases; the smoke test's 5-second run leases ~16k).

Two hard-won invariants:

- `JitInterface::UpdateMembase` picks `ppc_state.mem_ptr` from the ACTIVE core's `jo`. The static core must call `InitFastmemArena()` and mirror `jo.fastmem`, or leased JIT code (compiled against the arena base) writes through the page-mappings base — silent host-memory corruption, then an unhandled access violation at the first unmapped hole.
- Adding a virtual to `JitBase` (or otherwise reshaping those vtables) requires a CLEAN rebuild; ninja left stale objects that produced wandering heap corruption until `ninja -t clean`.

The interpreter path remains available for diagnostics via `STATICRECOMP_INTERP_FALLBACK=1` (and is selected automatically when a forced-interpreter bisection range is set).

## Next observation point

File-select input (pointing at a save file and pressing A), file creation, and the Logo → intro-cutscene path are unexplored. Performance is the other axis: the JIT reference runs 58 FPS / 1.09x on this host while the static core reaches ~20 FPS in menus — the deficit is recompiled-code quality, not the GPU. The remaining large levers, in expected order of value: keep backward local branches in-chunk with a downcount-seeded exit check instead of returning to the dispatcher per loop iteration (requires seeding `ctx->downcount` from `ppc.downcount` at burst start), cache hot guest registers in locals within basic blocks, and reduce the residual `hook_fb` traffic (~48k/s, mostly unmodeled `mfspr`/`mtspr`).

A 240-second menu soak (strap → title → file select and back) executes 1.005 billion native dispatches with zero SMC failures, zero interpreter fallback steps, and a clean shutdown.

`tools/Play-Game.ps1` launches the direct runner by default; the ImGui launcher (`ModernGekko.exe`, game/controller/resolution/save management UI) is opt-in via `-Launcher`. Frontend `config.ini` keys: `resolution`, `show_performance_overlay`, `enable_graphics_mods`, `load_custom_textures`, `controller`.
