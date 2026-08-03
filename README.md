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
connecting directly to the KICKR. VirtualShift forwards terrain, ERG, and
trainer data while applying virtual gears independently.

## Current milestone

The first milestone is a hardware proof, not a finished cycling application:

1. Verify that the KICKR V5 accepts Wahoo's wheel-circumference command.
2. Verify that an iPhone can connect to the KICKR while advertising an FTMS
   trainer that RealVelo can discover on Windows.
3. Continue with the complete proxy only if both checks pass.

The repository contains the platform-independent command encoding,
gear-ratio scaling, and two native iPhone targets:

- `VirtualShift` is the product app. It intentionally contains only a minimal
  shell until the FTMS proxy work begins.
- `VirtualShift Hardware Lab` contains the KICKR and original Zwift Click
  investigation tools. It is not the product interface.

## Important distinction

KICKR V5 does not support Zwift's native virtual-shifting protocol.
VirtualShift is investigating a separate Wahoo trainer command that changes
effective wheel circumference while leaving the cycling application's terrain
command intact.

## Development

Run the core tests on a Mac with Swift installed:

```bash
swift test
```

The iPhone hardware proof must be built and signed in Xcode. Open
`VirtualShift.xcodeproj`, choose the `VirtualShift Hardware Lab` scheme and a
physical iPhone, select your development team under Signing & Capabilities, and
run the app. Follow the hardware procedure in `MAC_SETUP.md`.

Do not treat a successful build or CoreBluetooth write as proof that resistance
changed. Record the physical result on issue #1. If the V5 rejects or ignores
the command, stop rather than building the full proxy.
