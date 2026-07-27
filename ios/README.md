# Starlight iOS host

This directory contains the native iOS host for Starlight. The default target builds the host shell
without private RMGE01-derived code. It already owns the Apple platform responsibilities: the Metal
layer, Retina output sizing, safe areas, adaptive touch input, controller and motion input,
AVAudioEngine output, haptics, lifecycle behavior, and Files-visible storage.

The Files app exposes:

- `Starlight/Game/*.iso` or `*.wbfs` — validated USA RMGE01 disc images
- `Starlight/Game/RMGE01` — extracted game tree containing `sys/main.dol`
- `Starlight/User/Wii/title/00010000/524d4745/data` — save data
- `Starlight/User/Load/Textures/RMGE01` — replacement textures

The cache stays in `Library/Caches/Starlight/RMGE01` and is excluded from device backups.

## Local build on macOS

```sh
cmake -S ios -B build/ios -G Xcode \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=16.0

xcodebuild \
  -project build/ios/StarlightIOS.xcodeproj \
  -scheme StarlightIOS \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

The unsigned workflow artifact verifies the device build but is not installable as-is. A signed IPA
requires an Apple Developer certificate and a provisioning profile matching the bundle identifier.

## GitHub Actions signing

Set these repository values:

- Variable `IOS_BUNDLE_ID`
- Secret `IOS_TEAM_ID`
- Secret `IOS_BUILD_CERTIFICATE_BASE64`
- Secret `IOS_BUILD_CERTIFICATE_PASSWORD`
- Secret `IOS_PROVISIONING_PROFILE_BASE64`
- Secret `IOS_PROVISIONING_PROFILE_NAME`
- Secret `IOS_KEYCHAIN_PASSWORD`

Run the `iOS` workflow manually with `signed` enabled. To attach an installable IPA to a GitHub
release, select a `v*` or `ios-*` tag as the workflow ref. Pushes and pull requests build an unsigned
device IPA for compile verification only.

## Runtime boundary

`StarlightPlatform.h` is the narrow boundary between UIKit and the Wii runtime. The final runtime
target must statically link the RMGE01 descriptor and call it through
`ModuleSource::AttachedDescriptor`. Loading a DLL or unsigned dylib at runtime is not an iOS design.

The production target is intentionally not enabled yet. The current Dolphin-derived chassis still
assumes AppKit in several Apple CMake branches, and the static core leases JitArm64 for runtime-loaded
RSO code. Both must be removed before supplying `STARLIGHT_RUNTIME_LIBRARY`.

The host can import ISO and WBFS files without loading the whole image into memory. It verifies the
Wii disc header, RMGE01 game ID, available storage, and the completed copy before selecting it.
Decoding either format during gameplay remains the responsibility of the statically linked
ModernGekko DiscIO runtime.
