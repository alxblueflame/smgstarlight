# Architecture

## Runtime path

`RMGE01 main.dol` -> DolRecomp generated C -> native DLL -> ModernGekko static-recomp CPU core -> Dolphin Wii runtime -> Windows host.

ModernGekko supplies the existing Wii CPU state, OS, IOS, GX, audio, filesystem, and emulated Wii Remote machinery. Game-specific work stays in isolated compatibility, input-profile, presentation, and asset-override layers.

## Invariants

- The exact `main.dol` SHA-256 selects compatibility data.
- The extracted game tree is immutable during normal runs.
- Generated C is build output and is never edited.
- Simulation and input remain at 60 Hz.
- High-refresh presentation must not advance game state.
- Petari names and behavior may guide analysis, but Korean addresses are never reused for RMGE01.

## Native execution performance

Static recompilation removes runtime PowerPC decoding and code generation, but it is only fast when
the generated host code has compact control flow and inexpensive runtime boundaries. This project
uses page-sized guest-code chunks, direct forward edges within a chunk, and a module-local dispatcher
for calls, backward branches, and cross-chunk edges. The host runtime receives control when the timing
budget expires, an exception occurs, code leaves the module, or a polling cycle needs idle detection.

Guest instruction costs accumulate in the shared CPU state. The runtime charges those costs to
Dolphin CoreTiming before starting another burst, so optimization cannot change Wii timing. Data-cache
maintenance instructions are host no-ops; instruction-cache invalidation still returns to the host so
self-modifying code is reverified before native execution resumes.

The JIT build remains a reference implementation and performance baseline. A static module is not
assumed to be faster merely because it was built ahead of time; every optimization is checked against
native boot invariants, video cadence, fallback count, self-modifying-code verification, and measured
wall-clock performance.

For RMGE01, 4 KB guest-code pages produce 1,322 generated functions. On the Ryzen 5 PRO 3400G test
machine, the same 15-second D3D trace improved from 14.47 FPS / 16.73 VPS to 55.87 FPS / 61.27 VPS
at 3x internal resolution after shader-cache warmup. The static core therefore reaches full Wii
simulation speed and closely matches the JIT reference; new performance work should target measured
scene-specific stalls rather than replacing exact timing with an unlocked emulation-speed multiplier.

## Bring-up order

1. Load and validate the native RMGE01 module.
2. Reach the first game-system initialization milestone.
3. Confirm audio and wave-data completion.
4. Confirm async DVD reads and the first Logo scene request.
5. Confirm GX initialization, retrace, and first visible frame.
6. Validate saves and a full 60 Hz gameplay path before enhancements.

## References

- [DolRecomp](https://github.com/ExpansionPak/DolRecomp)
- [ModernGekko](https://github.com/ExpansionPak/ModernGekko)
- [Petari](https://github.com/SMGCommunity/Petari)
- [Galaxy formats](https://www.lumasworkshop.com/wiki/Category:File_formats)
- [USA instruction manual](https://m1.nintendo.net/docvc/RVL/USA/RMGE/RMGE_E.pdf)
