# Developing Virtual Gears

This document covers building, testing and working on the source. Rider
instructions live in the [README](README.md) and on the
[Virtual Gears website](https://sbroenne.github.io/VirtualGears/).

## Requirements

- macOS
- Xcode 26 or later
- Swift 6
- An iPhone running iOS 17 or later for Bluetooth and trainer testing

The simulator can build and display the app, but it cannot prove Bluetooth
behavior with a trainer, controller or fan.

## Build and test

Run the hardware-independent test suite:

```bash
swift test
```

Open the iPhone project:

```bash
open VirtualGears.xcodeproj
```

Select the `VirtualGears` scheme. To run on an iPhone, choose your development
team under **Signing & Capabilities**, select the physical phone as the
destination, and run the app.

CI performs the same package tests and builds the app for an iPhone simulator
without code signing.

## Repository layout

| Path | Purpose |
|---|---|
| `Sources/VirtualGearsCore` | Gear calculations, trainer commands, ride coordination and other hardware-independent logic |
| `VirtualGearsProduct` | SwiftUI screens and the real Bluetooth services |
| `Tests/VirtualGearsCoreTests` | Hardware-independent unit and ride-lifecycle tests |
| `Tools` | macOS tools for inspecting the KICKR, Zwift Click and advertised trainer name |
| `docs` | MkDocs website, screenshots and hardware findings |
| `VirtualGears.xcodeproj` | iPhone app project |

## Documentation website

Install the pinned documentation dependencies and run the local server:

```bash
python3 -m pip install -r docs/requirements.txt
mkdocs serve
```

Build it with the same strict link and navigation checks used by CI:

```bash
mkdocs build --strict
```

## Hardware development

Read [MAC_SETUP.md](MAC_SETUP.md) before running anything against physical
equipment. It documents:

- installing and signing the app on an iPhone;
- the KICKR V5 wheel-circumference measurements;
- tracing an original Zwift Click;
- measuring trainer response times;
- checking the advertised FTMS trainer name; and
- the Mac diagnostic tools under `Tools`.

Close Virtual Gears on the iPhone before connecting a Mac tool. The trainer,
Click and Headwind accept limited simultaneous Bluetooth connections.

## Evidence standard

A successful build or CoreBluetooth write is not proof that hardware performed
the requested action. A trainer command is treated as confirmed only when the
trainer replies with the value it applied. Hardware claims in this repository
must identify what was physically measured and what remains an expectation.
