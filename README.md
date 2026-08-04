# VirtualShift

VirtualShift is a focused iPhone FTMS proxy for a Wahoo KICKR V5 and Zwift
Click.

```text
Windows cycling app <-> iPhone running VirtualShift <-> KICKR V5
                                      ^
                                      |
                                  Zwift Click
```

The cycling application connects to the iPhone's virtual trainer instead of
connecting directly to the KICKR. VirtualShift forwards terrain and trainer
data while applying virtual gears independently. ERG mode is intentionally not
supported.

## Current milestone

The production FTMS proxy is implemented. Physical testing confirmed that the
KICKR V5 accepts the complete 646.9–4800 mm range required by the default
24-speed profile and safely returns to the 2070 mm neutral value after every
test.

The repository contains the platform-independent command encoding,
gear-ratio scaling, and two native iPhone targets:

- `VirtualShift` is the production ride app.
- `VirtualShift Hardware Lab` contains the KICKR, original Zwift Click, and
  riding app FTMS validation tools. It is not the product interface.

VirtualShift appears to the riding app as a standard FTMS indoor bike, so any
app that supports FTMS trainers can use it. Development is validated against
RealVelo, and the same interface serves Zwift, FulGaz, and other FTMS apps.

## Important distinction

KICKR V5 does not support Zwift's native virtual-shifting protocol.
VirtualShift uses a separate Wahoo trainer command to approximate the published
Zwift 24-gear ratios by changing effective wheel circumference while leaving
the cycling application's terrain command intact.

## Development

Run the core tests on a Mac with Swift installed:

```bash
swift test
```

The iPhone hardware proof must be built and signed in Xcode. Open
`VirtualShift.xcodeproj`, choose the `VirtualShift Hardware Lab` scheme and a
physical iPhone, select your development team under Signing & Capabilities, and
run the app. Follow the hardware procedure in `MAC_SETUP.md`.

Do not treat a successful build or CoreBluetooth write as hardware evidence.
The Hardware Lab requires both the write callback and a matching successful
KICKR reply for every command.
