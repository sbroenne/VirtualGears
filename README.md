<p align="center">
  <img src="docs/banner.png" alt="VirtualShift — virtual gears for your smart trainer">
</p>

# VirtualShift

VirtualShift gives you gears on an indoor trainer that has none.

Your chain stays in one quiet, straight gear all ride. Shifting happens on your
iPhone instead, which changes how hard the trainer feels. Nothing on the bike
moves, so there is no chain noise, no dropped chain, and no wear.

```text
riding app on your computer  <->  iPhone running VirtualShift  <->  KICKR V5
                                              ^
                                              |
                                     Zwift Click (optional)
```

Your riding app connects to the iPhone instead of to the trainer. VirtualShift
passes everything through in both directions, and applies your chosen gear on
top. The riding app still controls the road: hills feel like hills.

## What you get

**Gears.** Either the 24 virtual gears Zwift and Wahoo use, which suit any bike
and are the starting choice, or a copy of a real bike described by its
chainrings and cassette. A real 50/34 with an 11-34 cassette gives sixteen
gears, running 34x34 up to 50x11 — the gears you would really ride, not every
possible pairing of a ring with a cog.

**Shifting.** Two large buttons on the phone, placed for sweaty hands and a
locked-out gaze. An original Zwift Click can be added and shifts the same
gears, but it is never required and nothing ever waits for it.

**Nothing to start.** Open the app and it connects to your trainer, starts the
session, and appears to your riding app on its own.

## What it does not do

ERG mode. A workout that sets a target power is refused, because holding a power
target and holding a gear are two different ideas of what the trainer should
feel like. VirtualShift still tells riding apps it is a trainer they can steer,
so it appears in their trainer list rather than as a bare power sensor.

## How the gears work

The KICKR has no virtual-shifting protocol of its own. VirtualShift uses a Wahoo
command that changes the trainer's idea of your wheel size: a smaller wheel
covers less ground per pedal stroke, which feels like an easier gear. The riding
app's own terrain command is left untouched, so the two never fight.

Every gear is scaled away from a 2070 mm reference. The trainer accepts
that scaling over a lopsided range — about 2.3 times harder but 3.2 times easier
— so the starting gear is placed where the tighter end has the most room, rather
than in the middle. A drivetrain too wide to fit is refused at setup rather than
mid-ride.

Some riding apps, FulGaz among them, set a wheel size of their own. VirtualShift
honours it: that size becomes the new reference and every gear is rebuilt around
it, so the gear you are in keeps feeling the way it did and the app's number is
what the trainer is left sitting at. If the gears would no longer fit inside the
proven range around that size, the request is declined and the ride carries on
at the size it already had.

## Safety

The 646.9-4800 mm range was confirmed on a physical KICKR V5, every value
acknowledged by the trainer, with the reference restored between each probe.
VirtualShift never asks for anything outside it, and every ride ends by putting
the trainer back to where it started: 2070 mm, or the wheel size the riding app
set if it set one.

Wheel size is sent in tenths of a millimetre, so what the trainer receives is
what the safety check judges.

## Requirements

- iPhone running iOS 26
- Wahoo KICKR V5
- A riding app that supports FTMS trainers. Development is validated against
  RealVelo; Zwift, FulGaz and others use the same interface.
- Optionally, an original Zwift Click

## Repository

- `Sources/VirtualShiftCore` — the parts with no iPhone in them: command
  encoding, gear ratios, drivetrain building, trainer limits. This is where the
  tests live.
- `VirtualShiftProduct` — the app you ride with.
- `VirtualShift` — a hardware lab used to prove trainer behaviour. It is not
  the product and is not needed to ride.

## Development

```bash
swift test
```

The app itself must be built and signed in Xcode. Open `VirtualShift.xcodeproj`,
choose the `VirtualShift` scheme and a physical iPhone, and select your
development team under Signing & Capabilities. See `MAC_SETUP.md` for the
hardware procedures.

A successful build or a successful CoreBluetooth write is not hardware evidence.
A trainer command counts as proven only when the trainer replies to confirm it.
