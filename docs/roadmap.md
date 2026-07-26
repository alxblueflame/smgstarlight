# Port roadmap

## 1. Correct native execution

- Keep RMGE01 revision gating mandatory.
- Reach the first visible frame with native CPU dispatch and zero failed SMC checks.
- Validate IOS, DVD, audio, VI, GX, and the bundled `HomeButtonMenuWrapperRSO.rso` path.
- Reach the title screen, start a file, enter gameplay, and save/reload successfully.
- Add focused regression tests for exception return, timers, polling loops, and module-cache identity.

Exit criterion: a deterministic 60 Hz playthrough path from boot to a saved first star.

## 2. Controller layer

Expose Galaxy actions independently of physical devices. The baseline mapping is left stick to Nunchuk, right stick to pointer, south face button to A, right trigger to B, left trigger to Z, left shoulder to C, and west face button to spin.

- Xbox, DualShock, DualSense, Switch Pro, and generic SDL gamepads
- Stick pointer with recenter, sensitivity, dead-zone, and optional gyro assist
- Button spin/shake so motion hardware is never required
- Optional DualShock/DualSense gyro with calibration and drift compensation
- Per-device profiles and runtime rebinding

Exit criterion: the full game is controllable on a normal Xbox-style pad without motion.

## 3. Resolution and presentation

- Preserve native 16:9 projection and HUD behavior first.
- Separate projection, culling, post-processing, and 2D-layout fixes for ultrawide.
- Decouple internal render resolution from window/output resolution.
- Add borderless, fullscreen, integer UI scaling, anti-aliasing, and anisotropic filtering controls.

Exit criterion: correct 16:9 and ultrawide framing without stretched HUD, missing geometry, or broken effects.

## 4. High-refresh output

Galaxy simulation, input, VI, and audio remain at their original 60 Hz cadence. Host frames interpolate presentation state between completed simulation ticks. Raising the emulated VBI rate is not an uncapped-FPS implementation and must not be used as one.

- Timestamp simulation snapshots
- Interpolate camera and render transforms without changing gameplay state
- Audit particles, skeletal animation, cutscenes, UI, and motion blur separately
- Support 60/90/120/144/165/240 Hz and uncapped presentation

Exit criterion: identical gameplay outcomes at 60 and high refresh, with stable audio and frame pacing.

## 5. HD assets and quality of life

- Reuse Dolphin-compatible texture hashes for dumping and replacement.
- Use PNG authoring sources with mipmapped BC7/DDS runtime caches.
- Load replacements asynchronously with validation and a configurable memory budget.
- Add faster boot, skippable previously viewed movies, configurable autosave, accessibility options, and camera/input tuning only after compatibility is stable.

Exit criterion: enhancements are optional, cacheable, and cannot alter the clean original-behavior profile.
