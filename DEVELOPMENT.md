# Developing Virtual Gears

This document covers building, testing and working on the source, including the
physical hardware measurements behind it. Rider instructions live in the
[README](README.md) and on the
[Virtual Gears website](https://sbroenne.github.io/VirtualGears/).

## Requirements

- macOS
- Xcode 26 or later
- Swift 6
- An iPhone running iOS 17 or later for Bluetooth and trainer testing

The simulator can build and display the app, but it cannot prove Bluetooth
behavior with a trainer, controller or fan.

The in-app Demo Mode is intentionally simulator-safe. `DemoRideState` contains
only a drivetrain and selected gear, while its `ConfigurationStore` has no
`UserDefaults` backing. Entering the demo stops discovery and the app suppresses
foreground reconnect and interrupted-ride reset work until the demo is closed.
The demo therefore checks product navigation and local gear behavior only; it
does not add any physical-hardware evidence.

## Build and test

Run the hardware-independent test suite:

```bash
swift test
```

Open the iPhone project:

```bash
open VirtualGears.xcodeproj
```

Select the `VirtualGears` scheme. To run on an iPhone:

1. Sign in to Xcode with the Apple ID used for device development.
2. Select the `VirtualGears` target.
3. Open **Signing & Capabilities** and choose the development team.
4. Select the physical iPhone as the run destination.
5. Run the app.

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

`DemoRideStateTests` cover the simulated gear ladder and drivetrain changes.
Bluetooth safety still depends on keeping Demo Mode outside `ProxyCoordinator`
and the CoreBluetooth services; do not replace its local state with staged
production services.

## Documentation website

Install the pinned dependencies and start the local site:

```bash
python3 -m pip install -r docs/requirements.txt
mkdocs serve
```

Build it with the same strict checks used by CI:

```bash
mkdocs build --strict
```

## Hardware measurements and tools

Close Virtual Gears on the iPhone before connecting a Mac tool. The trainer and
Zwift Click accept limited simultaneous Bluetooth connections.

Some of what follows is a historical record rather than a procedure. Before the
proxy existed, the trainer and controller were proven with a scratch diagnostic
app. The shipping app now performs those conversations and keeps its own
diagnostic log. The Mac tools under `Tools/` remain runnable.

## What the KICKR V5 range validation found

This was run once with the diagnostic app, on a quiet trainer that nothing else
was connected to. The app unlocked the KICKR, confirmed the fixed 2070 mm
neutral value, and then worked through ten wheel sizes one at a time, restoring
2070 mm between each one and never sending another command when the Bluetooth
write state was uncertain.

All ten were confirmed by the trainer. The sequence covered the previously
tested range, the 646.9–4735.1 mm range the 24 virtual gears need at a 2070 mm
baseline, and a 4800 mm upper safety margin.

The same ground can be covered today from a Mac with `Tools/KickrProbe`, which
also restores 2070 mm before it exits, including after a failure. Whatever is
used, reconnect before riding so the starting circumference is restored first.

## What a KICKR V5 puts in its advertisement

Measured on a woken KICKR V5 from this Mac, reading only - nothing was
connected to and nothing was written.

    FOUND "Wahoo KICKR 2A93" -73dBm services=[1818,1826] connectable=true

So the trainer names both Cycling Power (1818) and Fitness Machine (1826)
before anything connects to it, and a scan filtered on those two finds it every
time.

The app scans for those two services rather than looking at every Bluetooth
device in range. A trainer only has to name one of them to be found, because
Bluetooth matches any entry in the list rather than all of them - so a trainer
would have to name neither to be missed, and such a trainer could not be found
by Zwift or FulGaz either. That is stronger evidence than the measurement
above: every riding app discovers trainers this way.

## What the original Zwift Click proof found

This proof was independent of the KICKR and sent no trainer commands. Starting
from displayed gear 6, each tap of `+` and `-` moved exactly one gear and played
the single-shift sound. Holding a button kept the display moving while held and
stopped on release without adding gears afterwards. The repeat ran on a fixed
timer: half a second of hold before it started, then a gear every 300 ms,
whatever anything else was doing. Duplicate packets caused no extra shifts,
pressing both buttons did nothing, and a disconnect and reconnect changed none
of it.

The shipping app no longer repeats on a timer: holding a button asks for the
next gear only once the trainer has confirmed the last one, so a slow trainer
simply sweeps more slowly. That is a recent change and has not yet been
confirmed on a real ride.

`Tools/ClickTrace` below is the Mac equivalent, and it sees more than the app
ever could.

### Click buttons are not Zwift-native shifting

Virtual Gears reads button messages from an original Zwift Click and turns those
presses into Virtual Gears gear changes. The Click is an input device; those
button messages are not a virtual-shifting protocol and do not make the trainer
compatible with Zwift's native gear system.

Zwift-native shifting requires communication between the riding app and a
compatible trainer. Virtual Gears does not implement or emulate that proprietary
trainer-side communication. Wahoo says the KICKR V5 cannot support the required
"Zwift protocol":

<https://support.wahoofitness.com/hc/en-us/articles/16865097915666-Virtual-shifting-with-Wahoo-smart-trainers>

As of 7 August 2026, no public specification or working open-source
implementation was found for that trainer-side communication. Future
investigation therefore starts with hardware evidence, not guessed code: a
supported newer trainer, a Zwift or Rouvy native-shifting session, and a BLE
capture that identifies what the riding app and trainer exchange. Until then,
native Zwift support is explicitly out of scope.

## Recording what a Zwift Click really sends

`Tools/ClickTrace` connects a Mac straight to a Click and prints every packet
with the gap since the previous one. Nothing is interpreted, so it answers
questions the app's own logs cannot: by the time the app logs a shift, the press
has already been turned into one.

```bash
./Tools/ClickTrace/run.sh
```

Close Virtual Gears on the iPhone first. The Click accepts one connection at a
time, so the phone and the Mac cannot both hold it. Wake the Click by pressing a
button, then allow the Bluetooth prompt the first time.

The tool is wrapped in a small signed app bundle and launched with `open`,
because macOS judges Bluetooth permission by the program that started the
process. Run straight from a terminal, the terminal is judged, and it never
declared that it wants Bluetooth, so the tool is killed the moment it asks.
Output therefore goes to `/tmp/click-trace.log`, which the script tails.

`docs/zwift-click-button-trace.log` is a recording made this way. What it shows:

- This Click advertised only the generic name `Zwift Click`; a unique suffix is
  not guaranteed. Button state is available only after connection, not in the
  advertisement. The duplicate-name setup flow therefore tries candidates one
  at a time and confirms the one whose connected stream reports the rider's
  press.
- The Click streams its button state every 90-120 ms for about 1.3 seconds after
  anything changes, then goes quiet. It does not send an event per press.
- A button reads `0` when pressed and `1` when released.
- A firm press, of the kind used on the bike, lasts about 210 ms. Presses are
  clean: one press and one release each, with no bounce.
- A packet of `19 10 64` arrives every five seconds regardless of the buttons.
  It is the Click reporting its battery: the last byte is a percentage, so
  `64` in hex is 100%. Two independent projects that reverse-engineered these
  controllers, qdomyos-zwift and ajchellew/zwiftplay, both name message type 25
  the battery level message, which matched what the trace showed. The app uses
  this to keep the battery reading current while riding, because the standard
  Bluetooth battery reading is only reliable once, when the Click connects.

That recording is why holding a button now asks for the next gear only once the
trainer has confirmed the last one. Repeats used to be sent on a fixed 300 ms
timer that never waited for the trainer, so a hold could queue gears that kept
arriving after the rider let go.

## Measuring how the trainer itself responds

`Tools/KickrProbe` is a small Mac tool that connects straight to the trainer and
measures two things the app's own logs cannot show:

- how long the trainer takes to confirm a gear change, and
- whether the trainer takes control away when it is told to stop.

It shifts through real gears using the same gear engine the app uses, and it
always puts the wheel size back to 2070 mm before it exits, including after a
failure.

```bash
./Tools/KickrProbe/run.sh
```

Close the iPhone app first and wake the trainer by turning the pedals. A KICKR
accepts only one controlling connection, and the iPhone advertises itself as a
fitness machine too, so the tool picks the trainer by name.

### What a Wahoo KICKR 2A93 measured

Idle, with no riding app connected and nobody pedalling, eight consecutive gear
changes were confirmed in 59 to 238 ms, averaging 138 ms. So on an otherwise
quiet connection the old 300 ms repeat was *not* outrunning the trainer, and the
overshoot a rider sees must also owe something to a busier connection during a
real ride. Waiting for confirmation removes the question entirely: it cannot ask
for a gear the trainer has not yet applied, whatever the connection is doing.

The trainer also kept control through an FTMS Stop: a Wahoo write immediately
afterwards was still accepted. Refusing to re-take control during a stop is
therefore precautionary on this trainer rather than a fix for something it does.

### Why Virtual Gears uses Wahoo's command and not the standard one

The Bluetooth fitness-machine standard has a wheel-size command of its own
(opcode `0x12`, in tenths of a millimetre). Virtual Gears does not use it on the
trainer. This mode asks the trainer directly:

```bash
./Tools/KickrProbe/run.sh features
```

It reads what the trainer advertises, sends the standard wheel-size command at
the neutral value, and then sends a command the trainer never advertised, to see
whether a "yes" from this trainer means anything at all.

On a Wahoo KICKR 2A93 the answer was that it does not:

| Question | Answer |
| --- | --- |
| Feature bits | `03 40 00 00 0C 60 00 00` |
| Advertises wheel size? | Yes |
| Standard wheel-size command | Accepted (`80 12 01`) |
| Announced the change afterwards? | No |
| A command it never advertised | **Also accepted** (`80 14 01`) |

The last row is the important one. The trainer answered "success" to a target
cadence it does not claim to support, so its acceptance of the wheel-size
command proves nothing. It may work, it may be discarded; the reply cannot tell
them apart, and there is no way to read the wheel size back to check.

Wahoo's own command does not have this problem. It replies with the wheel size
it actually applied, which Virtual Gears compares against what it asked for
before reporting the gear as changed. Two further reasons to prefer it:

- It is a **separate channel**. The riding app's terrain commands occupy the
  standard control point, which carries one request at a time. Gear changes on
  their own characteristic never queue behind them.
- It is the route that has been **proven on hardware**, across ten wheel sizes
  from 647 mm to 4800 mm and timed at 59 to 238 ms per change.

This mode changes nothing and leaves the trainer on 2070 mm.

## What the riding app FTMS probe found

Before the proxy was built, the diagnostic app was made to pretend to be a
simple indoor bike, with nothing connected to the KICKR at the time. It was run
against RealVelo, which is the reference app here. Zwift, FulGaz, and MyWhoosh
speak the same standard FTMS interface, but the probe was not run against them
and they are not covered by what follows.

RealVelo found the foreground iPhone as a Bluetooth FTMS trainer, showed the
fixed speed, cadence, and power it published, and followed those values as they
were moved. It drove its normal start, pause, stop, ERG, resistance, simulation,
and wheel-circumference controls through it. It subscribed to the Control Point
before requesting control, and after a disconnect and reconnect it found the
probe again and repeated the same subscriptions and control request.

That is the shape the shipping app presents today, and it is why the proxy works
at all. If a riding app stops seeing Virtual Gears, the app's own diagnostic log
records the same writes in the same order, so read that before changing the FTMS
service shape on a hunch.

## What name a riding app shows for Virtual Gears

A rider reported that MyWhoosh listed the app as "iPhone sbroenne 17 D345"
rather than "Virtual Gears". A name can reach a riding app by two routes, so
`Tools/NameScan` reads both and tells them apart:

```
./Tools/NameScan/run.sh
```

Start a ride on the phone while it runs. Measured on 2026-08-05:

```
Found a fitness machine at -55 dBm.
  In the advertisement: local name "Virtual Gears"; services 1826
  CBPeripheral.name reads: iPhone sbroenne 17
```

So the advertisement is correct and this is not an app bug. The second name is
the GAP Device Name (0x2A00), which iOS fixes to the name of the phone; an app
cannot publish its own 0x1800 service to override it. A riding app that reads
that instead of the advertised local name will always show the phone.

There is no code fix. The ride screen now names both possibilities while
waiting to be found, and `docs/requirements.md` explains it. A rider who
minds can rename the phone in Settings.

Note that macOS keeps 0x1800 to itself, so the tool cannot read 0x2A00
directly; `CBPeripheral.name` showing the phone's name is the evidence that
the device name is what reaches a central.
