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
swift test --enable-code-coverage
```

CI requires at least 90% line coverage for `Sources/VirtualGearsCore`, excluding
tests and hardware investigation tools.

Run the simulator UI regression suite:

```bash
xcodebuild test \
  -project VirtualGears.xcodeproj \
  -scheme VirtualGears \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -parallel-testing-enabled NO
```

`VirtualGearsUITests` launches deterministic debug fixtures rather than pretending
the simulator has Bluetooth hardware. Its 30 scenarios cover every primary
screen, portrait and landscape status visibility, Accessibility Dynamic Type,
startup failure, trainer reconnect, a riding app waiting, low Click battery,
pending shifts, accepted Click press feedback, navigation, stop confirmation and
cancellation, gear-mode switching, Headwind controls and Demo Mode interactions
in both shift directions. Six of them are regression guards with measured
assertions rather than existence checks: the ride status must be wide enough to
be read as words rather than collapsing to an icon, cancelling the stop
confirmation must return to the ride, every equipment status must sit on one
row, a low Click battery must be drawn at warning weight, the Easier/Harder
buttons in Demo Mode must be drawn with the same distinct visual weight as the
ride screen's (sampled by pixel colour, since button styling isn't exposed via
the accessibility tree), and the chain-position reminder must never appear or
disappear across startup states (it previously vanished the instant the
trainer connected, making the button above it jump). Screenshots are
attached to every test result. Protocol
behavior and equipment lifecycle remain covered by the package tests and
physical-hardware evidence.

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
| `VirtualGearsUITests` | Simulator UI, navigation, accessibility and layout regression tests |
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
tested range and a 4800 mm upper safety margin.

A second run covered the easy end of the ladder, which the first did not reach:
517.5, 525, 550, 575, 600, 625 and 647 mm. The trainer confirmed every one, in
60 to 180 ms, resetting to 2070 mm between each and again at the end. The full
output is in `docs/kickr-wheel-size-sweep.log`, and the run can be repeated with
`Tools/KickrProbe/run.sh sweep`.

Between the two runs, both ends of the 517.5–4735.1 mm span the 24 virtual gears
need at a 2070 mm baseline have been confirmed on hardware.

A third run closed a gap the first two left: `TrainerSafety` declared an
operating range starting at 500 mm, but nothing below 517.5 mm had ever been
sent to a trainer. Eight values from 500 mm to 517.5 mm in 2.5 mm steps were all
confirmed, in 58 to 181 ms, with the reference reset between each and again at
the end. The output is in `docs/kickr-wheel-size-sweep-low-end.log`.

Two further runs pushed the top to 5350 mm and then covered both ends at once,
425 to 500 mm and 5350 to 5525 mm. Every value was confirmed. They are in
`docs/kickr-wheel-size-sweep-fulgaz.log` and
`docs/kickr-wheel-size-sweep-full-window.log`.

### The range these runs were measuring did not exist

All of this was chasing a limit the trainer does not have.

An earlier boundary probe had already shown the KICKR V5 acknowledging values
from **0.1 mm to 6553.5 mm** — the entire span the command can express. That
result was never written into the code or the docs, so the app went on carrying
a narrow range described as what the trainer had been "proven to accept", and
went on being widened one refused wheel at a time.

Worse, that number was doing a second job nobody had noticed. The 24 gears are
positioned inside it, so its width silently decided which wheel sizes a riding
app was allowed to set. That is why every widening was triggered by a real rider
or a real app hitting a refusal.

Both jobs are now separated and stated outright. `TrainerSafety` declares the
wheel sizes Virtual Gears supports — 1800 mm to 2400 mm — and a test walks every
tenth of a millimetre of that window checking all 24 gears build. The only limit
left on the trainer side is the one that is real: 6553.5 mm is the largest wheel
size the command can carry. The starting gear was pinned at the same time, after
changing the range was found to move the shipped gears and make the easiest one
13% harder.

The same ground can be covered today from a Mac with `Tools/KickrProbe`, which
also restores 2070 mm before it exits, including after a failure. Whatever is
used, reconnect before riding so the 2070 mm baseline is set first.

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
- It is the route that has been **proven on hardware**, across seventeen wheel
  sizes from 517.5 mm to 4800 mm and timed at 59 to 238 ms per change.

This mode changes nothing and leaves the trainer on 2070 mm.

## What the riding app FTMS probe found

Before the proxy was built, the diagnostic app was made to pretend to be a
simple indoor bike, with nothing connected to the KICKR at the time. It was run
against RealVelo. Zwift and MyWhoosh speak the same standard FTMS interface, but
the probe was not run against them and they are not covered by what follows.
FulGaz is covered separately in the next section.

RealVelo found the foreground iPhone as a Bluetooth FTMS trainer, showed the
fixed speed, cadence, and power it published, and followed those values as they
were moved. It drove its normal start, pause, stop, ERG, resistance, and
simulation controls through it. It subscribed to the Control Point before
requesting control, and after a disconnect and reconnect it found the probe
again and repeated the same subscriptions and control request.

This section used to claim RealVelo drove wheel-circumference controls too.
That was wrong: RealVelo does not support setting the wheel size at all. The
claim mattered more than a stray sentence should, because it was the only
evidence behind the app's assumption that a riding app can change the wheel size
at any moment, and a good deal of state exists to cope with that. Nothing else
supported it. It has been replaced by the measurement below, and independently
confirmed by the wire capture in "What RealVelo sends": across a five-minute
ride it sent no wheel size at all.

That is the shape the shipping app presents today, and it is why the proxy works
at all. If a riding app stops seeing Virtual Gears, the app's own diagnostic log
records the same writes in the same order, so read that before changing the FTMS
service shape on a hunch.

## When a riding app sets the wheel size

Rather than reason about this, a riding app was watched. `Tools/AppTap` makes a
Mac pretend to be an indoor trainer, so a riding app pairs with it directly and
every command it sends is written down and timed. No phone, trainer or bike is
involved. Run it with `./Tools/AppTap/run.sh`.

**The riding app has to be on a different machine.** macOS does not loop
Bluetooth advertisements back to itself, so a riding app running on this Mac can
never see a tap advertising from this Mac — it will happily find the phone
instead and report itself connected while the tap sits silent. FulGaz and
RealVelo were traced from another device for this reason. MyWhoosh is installed
on this Mac and cannot be traced from it.

It advertises as "AppTap", not as "Virtual Gears". The phone is usually
advertising the real name a few feet away, and a riding app that picks the phone
instead looks exactly like a tap that sees nothing: connected on one screen,
silent on the other. Pass `--name "Virtual Gears"` to check whether a riding app
treats the real name differently — for RealVelo it did not — and quit the app on
the phone first when doing so.

It also calls out anything unusual as it happens, so a surprise is not left
buried in a list of opcodes: a reset, repeated control requests, commands sent
without asking for control first, commands after a stop or pause, a wheel size
that is implausible or that changes mid-ride, command bytes it does not
recognise, and writes to characteristics that are not the control point.

FulGaz was observed for five minutes across two rides. The full capture is in
`docs/fulgaz-app-tap-run.log`. It starts a ride with the same four commands in
the same order:

```
147.7s  0x00 request control
147.9s  0x07 start or resume
148.1s  0x12 SET WHEEL SIZE 2200.0 mm
148.2s  0x04 set resistance 0
```

Two things follow from this, and both matter.

**The wheel size is sent when a ride starts, and never again.** It was sent at
17.9 s and again at 148.1 s, each time within a fifth of a second of a start
command, and not once in between despite hundreds of terrain updates. So no
riding app has yet been seen changing the wheel size part-way through its own
ride.

That is *not* the same as saying it never arrives while Virtual Gears is already
running. FulGaz sends it when *its* ride starts, which need not line up with
ours: a rider who starts Virtual Gears first and then starts a course gets the
wheel size mid-ride from our point of view. The rebuilding machinery is
therefore still needed. What is wrong is the explanation attached to it, not the
code.

**The wheel size was refused**, so Virtual Gears and FulGaz could not have
worked together at all, and no amount of reading the code would have found it.

The 2200 mm in the capture is not a FulGaz constant: it is a rider setting, and
this rider had changed it from the 2098 mm default. That is the important part.
A riding app sends whatever its rider typed, so the app has to accept a range of
wheel sizes rather than a list of known values. See `docs/safety.md`.

Beyond the wheel size, FulGaz re-requests control every ten seconds for the
whole ride, and drives resistance through simulation parameters rather than
resistance commands — it sent exactly one of those, at startup.

## What RealVelo sends

RealVelo was watched the same way on 2026-08-14, over a five-minute ride the
rider stopped and restarted part-way through. The capture is in
`docs/realvelo-app-tap-run.log`. It behaves nothing like FulGaz:

```
    1.7s  0x00 request control
    1.8s  0x01 reset
    1.9s  0x00 request control
    2.0s  0x07 start or resume
```

That first run advertised as "AppTap" so the rider could tell it apart from the
real thing, which is a deviation worth ruling out: a riding app may treat a
trainer name it does not recognise differently. It was run again under the
shipping name "Virtual Gears" and behaved identically, down to the order and the
timing — `docs/realvelo-app-tap-run-shipping-name.log`:

```
    1.3s  0x00 request control
    1.5s  0x01 reset
    1.6s  0x00 request control
    1.7s  0x07 start or resume
```

**There is no name-dependent behaviour here.** What follows was seen in both
runs.

**RealVelo never sets a wheel size at all**: not once in 281 seconds and 147
terrain updates, nor in the second run's 137 seconds and 58. So one riding app
sends the wheel size at every ride start and another never sends it; the app
cannot assume either.

**It sends a reset while connecting.** By the FTMS rules a reset returns a
machine to its defaults, which would include the wheel size the gears ride on,
and it arrives a second and a half after the riding app appears — which for a
rider who starts Virtual Gears first lands while gears are already set up. That
looked like a silent way to break every gear, so it was measured rather than
argued about. See the next section: it does not.

**It asks for control twice**, either side of the reset. That is correct of it,
because a reset drops the claim. A trainer that refused the second request would
lock the riding app out for the whole ride; `FTMSControlOwnership` grants a
repeat request from the app that already holds the claim, so it does not.

The rider stopped and restarted their ride during the capture and no stop, pause
or second start reached the trainer. A riding app's own ride controls are not
reliably visible from down here, so nothing may depend on seeing them.

## Does a riding app's reset wipe the wheel size?

Measured on a real KICKR V5 on 2026-08-14, because the answer decides whether
Virtual Gears may keep passing resets through to the trainer while it is
shifting. `docs/kickr-reset-test.log`:

```
./Tools/KickrProbe/run.sh reset-test
```

It sets 4000 mm, a size no trainer defaults to, sends the same reset RealVelo
sends, and then works out what the trainer is really riding on. The trainer
accepted the reset and handed control straight back. Afterwards the speed fell
by a third the moment the wheel size was set to a known 2070 mm, so the trainer
was still on a large, non-default size.

**A reset does not touch the wheel size**, so passing one through does not break
the gears. The estimate the probe printed was 3230 mm against the 4000 mm set,
and that gap is the method rather than the trainer: a hand spin is slowing down
throughout, which biases the figure low. It is not precise enough to quote as a
measurement, but it is far too large to be a default, which is all this asked.

## Does the trainer keep the wheel size across a power cut?

Yes. The trainer cannot be asked what wheel size it is using, so this takes two
runs with the plug pulled in between:

```
./Tools/KickrProbe/run.sh set 3105     # leave a size nothing defaults to
# unplug the trainer, wait ten seconds, plug it back in
./Tools/KickrProbe/run.sh read         # work out what it is using now
```

Measured on 2026-08-14 in `docs/kickr-power-cut-read.log`: roughly 2967 mm
against the 3105 mm left behind, within a few percent and nowhere near the
2096 mm default. **The odd wheel size survived the power cut.** So putting the
wheel size back after a crash genuinely matters — nothing else will do it, and a
trainer left on a gear's wheel size reports the wrong speed and distance to
every app that connects to it afterwards.

An earlier run of this measurement was made with a probe that could not wait:
`run()` executes inside `settleTask`, and subscribing to the speed channel
part-way through fired the callback that cancels it. A cancelled task's sleeps
return immediately, so every timed wait collapsed. The figures above are from
after that was fixed. Treat any hardware evidence recorded before it with
suspicion.

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

## Why the three Bluetooth services still look alike

The trainer, fan and shifter each have their own central service, and at a
glance they repeat each other. Most of that repetition has now been removed:
the decisions they share live in `ConnectionPolicy.swift` and are covered by
tests, and the Mac tools share `Sources/ToolSupport`.

What is left was measured and deliberately kept. Only about eighty lines are
still identical in all three, so sharing them would save under a hundred lines
once the machinery to share them is written. The cost is higher than that
sounds: those functions write to `state`, `selectedID`, `selectedName` and
`connectionIsStalled`, which are `private(set)` precisely so the screens can
read them and nothing else can change them. Sharing through a protocol opens
all twelve of those for writing anywhere in the app. Sharing through a helper
object keeps them closed, but restructures the reconnect path that caused
real ride disconnects, and no test can prove that path correct — only a ride
can.

Some things that look duplicated are not, and should not be merged:

- `resetConnection` genuinely differs; each device has its own
  characteristics and queues.
- Scanning differs. A HEADWIND does not advertise its control service, so it
  cannot be filtered by UUID, and the fan hands itself back before scanning.
- The fan reconnects through `resumeSavedConnection` rather than
  `retrieveAndConnect`. The two are equivalent today, but making them the
  same call would be a behaviour change wearing a refactor's clothes.
