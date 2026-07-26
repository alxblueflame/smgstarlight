# Wii recompilation research notes

## Execution model

A Wii game is a PowerPC Broadway program that talks to emulated hardware and IOS services; recompiling `main.dol` alone does not replace that environment. This project translates the fixed RMGE01 code ranges to native host code while retaining ModernGekko's Dolphin-derived memory, exception, CoreTiming, IPC, IOS, GX, audio, DVD, and Wii Remote systems.

Generated code is disposable build output. Compatibility changes belong in reviewed runtime patches or a separate RMGE01 layer, selected by the exact DOL hash.

## Timing

DolRecomp's RecompCore backend emits Dolphin-equivalent cycle costs at basic-block leaders. The native dispatcher subtracts those costs from `downcount`, allowing CoreTiming events to fire at Wii timing boundaries. Proven self-polling blocks call CoreTiming's idle path so the host can jump to the next scheduled event.

The high-refresh design must preserve 60 Hz game simulation and interpolate only presentation. Dolphin's timing work is a useful reference because changing VBI frequency changes game logic rather than simply drawing more frames.

## Input

Dolphin's emulated Wii Remote remains the compatibility endpoint. A clean host layer should produce normalized Galaxy actions and then synthesize Nunchuk, pointer, buttons, shake, and optional gyro data. SDL3 exposes standardized gamepads and sensor streams across the intended PC controllers.

## Graphics and textures

Widescreen work must distinguish projection matrices, CPU/GX culling, screen-space effects, and HUD layout. HD texture replacement should follow Dolphin's texture-information/hash rules so existing dumps remain inspectable and tools can be reused.

## Modules and symbols

RMGE01 includes `files/ModuleData/HomeButtonMenuWrapperRSO.rso`. DolRecomp focuses on DOL/REL translation, so RSO behavior must be observed during bring-up and either remain on the faithful runtime fallback path or receive an isolated native replacement. Petari targets Korean `RMGK01`; it is useful for names and intent, never for RMGE01 addresses.

## Primary references

- [DolRecomp](https://github.com/ExpansionPak/DolRecomp)
- [ModernGekko](https://github.com/ExpansionPak/ModernGekko)
- [RecompCore](https://github.com/ExpansionPak/RecompCore)
- [Dolphin source](https://github.com/dolphin-emu/dolphin)
- [Wii IOS](https://wiibrew.org/wiki/IOS)
- [Wii IPC](https://wiibrew.org/wiki/Hardware/IPC)
- [Wii GX](https://wiibrew.org/wiki/Hardware/GX)
- [SDL3 gamepad API](https://wiki.libsdl.org/SDL3/CategoryGamepad)
- [SDL3 sensor API](https://wiki.libsdl.org/SDL3/CategorySensor)
- [Petari](https://github.com/SMGCommunity/Petari)
