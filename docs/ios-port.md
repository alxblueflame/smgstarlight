# iOS port architecture

## Current state

The first native host slice is in `ios/`. It is an ARM64 iPhone/iPad application target using UIKit,
CAMetalLayer, MetalFX, Game Controller, Core Motion, Core Haptics, and AVAudioEngine. Its public C
boundary is `ios/include/StarlightPlatform.h`.

The default CI target deliberately excludes the private RMGE01 module. It verifies the Apple host
without publishing game-derived code.

## Non-negotiable runtime changes

### Static game module

The generated DOL chunks must become an ARM64 static library instead of a Windows DLL. The existing
module descriptor is already suitable for `ModuleSource::AttachedDescriptor`; no dynamic executable
loading is needed.

Use Clang with `-O2`, ThinLTO, hidden visibility, precise floating-point behavior, and no
architecture-specific x86 assumptions. NEON or ARM64 intrinsics belong only in measured host
hotspots, not in generated PowerPC semantic code.

### Runtime-loaded Wii code

The current desktop core leases JitArm64 for `HomeButtonMenuWrapperRSO.rso` and other code outside
the DOL. A normal iOS build cannot depend on that. Before gameplay:

1. Recompile the required RSO code into the app and register its address ranges, or
2. use the cached interpreter for uncovered code as a temporary correctness path.

The first option is the release path. The second is a bring-up tool and is unlikely to meet the
performance target.

### UIKit host platform

ModernGekko needs an iOS `Platform` implementation that receives the host's existing CAMetalLayer.
It must not create an AppKit window or own the UIApplication loop. UIKit stays on the main thread;
the Wii runtime runs on its worker thread and receives pause, resume, resize, and shutdown events
through the host boundary.

Add an iOS window-system type so controller initialization and presentation do not enter macOS
AppKit branches.

## Graphics

The output CAMetalLayer remains at native Retina resolution. Dynamic resolution changes the internal
render target only. MetalFX then upscales that target into the output texture.

The spatial scaler is the first safe integration because it needs only color. The temporal scaler
requires valid motion vectors, depth, jitter, exposure, and reset history. It must not be enabled
until the GX presentation path produces those inputs; fake motion data would create severe
ghosting.

Dynamic resolution uses smoothed GPU time with asymmetric steps: it lowers scale quickly when near
the frame budget and raises it slowly after sustained headroom. Thermal state and Low Power Mode
still need to clamp the maximum scale and preferred refresh rate.

HDR is optional. Galaxy's source lighting is SDR, so HDR output needs a controlled paper-white and
highlight mapping pass. Merely selecting a float drawable would produce incorrect brightness. The
host configures an extended-linear Display P3 layer; the tone-mapping pass remains a runtime task.

High refresh does not alter the 60 Hz simulation. Presentation interpolation must consume two
completed simulation snapshots and present at the display cadence. On iOS the requested range is
advisory and should be reduced when thermal pressure or Low Power Mode requires it.

## Input

The platform input state maps:

- left stick or touch stick to Nunchuk movement
- right stick, mouse, touch, or gyro to the Star Pointer
- south face button to Wii A
- right trigger to Wii B
- left trigger to Nunchuk Z
- left shoulder to Nunchuk C
- west face button to spin

Game Controller handles Xbox, PlayStation, and compatible MFi devices. Controller-provided motion
is preferred over device motion when present. Core Motion polls the latest device-motion sample at
game cadence. Touch controls hide when a physical controller is active and lay themselves out
inside safe-area insets.

The remaining input work is per-device glyphs, a visual layout editor, rebind persistence, pointer
calibration, controller haptic actuators, and accessibility layouts.

## Audio

The host accepts interleaved 48 kHz stereo floats into a lock-free single-producer/single-consumer
ring and renders through AVAudioSourceNode and AVAudioEngine. AVAudioSession requests a 256-frame
buffer for low latency. The runtime must resample once, outside the real-time callback, and respond
to route changes and interruptions without blocking the audio thread.

Faithful stereo is the default. Genuine Spatial Audio requires multichannel or object-level source
separation; applying an arbitrary stereo widening effect is not labeled as Spatial Audio. A later
mixing layer can route separable sources through AVAudioEnvironmentNode.

## Storage and lifecycle

`UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace` expose the app's Documents directory
in Files. Extracted data, Wii saves, and texture replacements have stable, named locations. Driver
and shader caches live in Library/Caches and are excluded from backups.

The native document picker accepts ISO and WBFS. Imports are copied on a worker queue, checked for
free storage, validated as USA RMGE01 both before and after the copy, and selected persistently.
Files placed directly in `Starlight/Game` are also discovered. The runtime receives either the
selected image path or the extracted `RMGE01` directory through the same stable host boundary.

Background suspend pauses the runtime when the app resigns active. No unsupported background
execution mode is requested. Idle sleep is an option backed by `UIApplication.idleTimerDisabled`
and is reset through normal lifecycle transitions.

## Delivery phases

1. Apple host compiles as an unsigned device app in CI.
2. ModernGekko compiles for `iphoneos` without AppKit, desktop launchers, or dynamic modules.
3. RMGE01 DOL links as an ARM64 static descriptor and reaches a headless deterministic boot.
4. CAMetalLayer presentation reaches the title screen with native Metal.
5. Touch, Game Controller, keyboard, mouse, gyro, audio, saves, and textures work end to end.
6. Runtime-loaded RSO code has no JIT dependency.
7. MetalFX spatial scaling and GPU-time dynamic resolution pass image-quality and pacing tests.
8. HDR tone mapping and temporal MetalFX are added with correct source data.
9. Signed device archives, IPA export, crash symbols, and long-session thermal tests pass.

The playable milestone is phase 6, not the existence of an IPA shell.
