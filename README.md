<p align="center">
  <img src="docs/banner.png" alt="Virtual Gears — virtual shifting for KICKR V5">
</p>

# Virtual Gears

**[Read the full Virtual Gears documentation](https://sbroenne.github.io/VirtualGears/)**

Virtual Gears gives you gears on an indoor trainer that has none.

Use the smaller front ring if your bike has one, then pick a rear gear that keeps
the chain straight and leave it there. Shifting happens on your iPhone instead,
which changes how hard the trainer feels. Nothing on the bike moves, so there is
no chain noise, no dropped chain, and no wear.

```text
riding app on your computer  <->  iPhone running Virtual Gears  <->  KICKR V5
                                              ^
                                              |
                                     Zwift Click (optional)
                                     Headwind fan (optional)
```

Your riding app connects to the iPhone instead of to the trainer. Virtual Gears
passes everything through in both directions, and applies your chosen gear on
top. The riding app still controls the road: hills feel like hills.

<p align="center">
  <img src="docs/screenshots/starting.png" width="24%" alt="The saved trainer connecting while the Zwift Click and Headwind are connected">
  <img src="docs/screenshots/riding.png" width="24%" alt="The ride screen, showing gear 12 of 24 with trainer, Click, Headwind and riding app connected">
  <img src="docs/screenshots/gears.png" width="24%" alt="The 24 virtual gears drawn as bars">
  <img src="docs/screenshots/gears-real-bike.png" width="24%" alt="A real 50/34 with 11-34, drawn as sixteen gears">
</p>

<p align="center">
  <img src="docs/screenshots/riding-landscape.png" width="80%" alt="The landscape ride screen, with gear 12 between large Easier and Harder buttons">
</p>

<p align="center">
  <img src="docs/screenshots/headwind-control.png" width="24%" alt="Headwind manual fan control at 50 percent in portrait">
  <img src="docs/screenshots/headwind-control-landscape.png" width="56%" alt="Headwind manual fan control at 50 percent in landscape">
</p>

## What you get

**Gears you can see.** Either a 24-step virtual ladder, tuned with extra room for
easy climbing, or a copy of a real bike described by its chainrings and
cassette. A real 50/34 with an 11-34 cassette gives sixteen gears, running 34x34
up to 50x11 — the gears you would really ride, not every possible pairing of a
ring with a cog.

Whichever you choose is drawn rather than listed: one bar per gear, easiest to
hardest, on a scale where a tall step is a jump the legs will notice. How far
the gears reach and how evenly they are spread are visible at a glance, which no
list of tooth counts can tell you.

**Shifting.** Two large buttons on the phone, placed for sweaty hands and a
locked-out gaze. An original Zwift Click can be added and shifts the same
gears, but it is never required and nothing ever waits for it.

**Optional Headwind control.** Add a Wahoo Headwind and choose Automatic or
Manual from the ride screen. Manual has a slider, one-tap common speeds, and
large Slower and Faster buttons in portrait. Returning control to the fan's
sensor is explicitly confirmed before Virtual Gears disconnects. The controls
work in both portrait and landscape.

**Nothing to set up.** Open the app. It looks for your trainer, connects to it,
starts the session and appears to your riding app, all on its own. There is no
setup to complete and no button to press.

The only question it ever asks is which trainer, and only when it genuinely
cannot tell: one trainer nearby is simply used, several are only chosen
automatically when one is clearly closest. Bluetooth reaches through walls, and
connecting to a neighbour's trainer would change their wheel size, so anything
ambiguous is asked rather than guessed.

**Everything changeable mid-ride.** Trainer, gears, Click and Headwind can all be
changed from the ride screen. Changing gears rebuilds them in place, without
interrupting the ride, so the riding app on your PC never notices.

**A ride survives an interruption.** Taking a call, tapping a notification or
switching to another app does not end your ride. The trainer stays connected and
your riding app stays paired, so you can come back to the same gear.

## What it does not do

ERG mode. A workout that sets a target power is refused, because holding a power
target and holding a gear are two different ideas of what the trainer should
feel like. Virtual Gears still tells riding apps it is a trainer they can steer,
so it appears in their trainer list rather than as a bare power sensor.

## How the gears work

The KICKR has no virtual-shifting protocol of its own. Virtual Gears uses a Wahoo
command that changes the trainer's idea of your wheel size: a smaller wheel
covers less ground per pedal stroke, which feels like an easier gear. The riding
app's own terrain command is left untouched, so the two never fight.

Every gear is scaled away from a 2070 mm reference. The default ladder reaches
about four times easier and 2.3 times harder while keeping gear 12 as the
starting point. A drivetrain too wide to fit is refused at setup rather than
mid-ride.

Wheel size is part of the standard interface available to every riding app.
Whenever one sets it, Virtual Gears honours it: that size becomes the new
reference and every gear is rebuilt around it, so the gear you are in keeps
feeling the way it did. If virtual shifting stops while the riding app keeps
running, its number is what the trainer is left sitting at. If the gears would no
longer fit inside the proven range around that size, the request is declined and
the ride carries on at the size it already had.

## Safety

The selected 500-4800 mm operating range was confirmed on a physical KICKR V5,
every value acknowledged by the trainer, with the reference restored between
each probe. These are the edges we chose to test, not a claim that the KICKR
rejects values outside them. Virtual Gears never asks for anything outside the
selected riding range. Ending virtual shifting removes Virtual Gears' gear and
returns to the riding app's latest wheel size, or to the trainer's starting size
if the riding app did not set one.

A later boundary search reached both ends of Wahoo's two-byte command, with
samples throughout the range acknowledged by this KICKR. That proves broad
command acceptance, not that every extreme value makes a useful riding gear.

Wheel size is sent in tenths of a millimetre, so what the trainer receives is
what the safety check judges.

The trainer works out its speed from that wheel size, so a value left behind
would quietly distort the speed and distance of any ride that did not use
Virtual Gears. If iOS ends the app before a ride can stop, the size the ride
borrowed is still written down, and the next launch puts it back without saying
anything about it.

## Why it exists

Zwift added virtual shifting in 2024 and Wahoo brought it to their newer
trainers. The KICKR V5 was left out, and Wahoo's
[support page](https://support.wahoofitness.com/hc/en-us/articles/16865097915666-Virtual-shifting-with-Wahoo-smart-trainers)
says so permanently:

> We have reviewed the hardware and firmware capabilities of KICKR v5 (2020) and
> preceding KICKR versions. Unfortunately, these older models are unable to
> support the required protocols for virtual shifting using the Zwift protocol
> and will not be receiving a future update for this functionality.

Virtual Gears gives a KICKR V5 gears anyway, and does it in every riding app
rather than only Zwift and Rouvy. The riding app will not display the gear —
there is no message in the Bluetooth standard for reporting one — so the phone
shows it instead.

## Requirements

- iPhone running iOS 17 or later, which is any iPhone from the XS onwards
- Wahoo KICKR V5. Other Wahoo KICKR models should work but are untested; the
  KICKR Snap and KICKR Bike do not, because they change gear other ways. See
  [Which trainers work](https://sbroenne.github.io/VirtualGears/requirements/#which-trainers-work).
- A riding app that supports FTMS trainers. Development is validated against
  RealVelo; Zwift, FulGaz and others use the same interface.
- Optionally, an original Zwift Click
- Optionally, a Wahoo KICKR HEADWIND

## Repository

- `Sources/VirtualGearsCore` — the parts with no iPhone in them: command
  encoding, gear ratios, drivetrain building, trainer limits, and the ride
  itself. This is where the tests live. The ride reaches the trainer, the
  riding app and the Click through narrow protocols, so a whole session can be
  run against stand-ins with no hardware in the room.
- `VirtualGearsProduct` — the app you ride with: the screens, and the real
  Bluetooth behind those protocols.
- `docs/screenshots` — the screens above, captured from the simulator.
- `docs/` — also the source of the website, built with MkDocs Material.

## Development

```bash
swift test
```

The app is written in Swift 6 language mode, so the compiler checks that the two
Bluetooth conversations — one to the trainer, one to the riding app — never
touch the same data at the same time. That class of bug otherwise shows up as a
freeze in the middle of a ride and is close to impossible to reproduce. Building
needs Xcode 26 or later.

The trainer facts in these docs were measured before the app existed, using a
scratch diagnostic app that talked to the trainer and to the riding app on its
own. That app has since been removed: the shipping app is the proxy now and
keeps its own diagnostic log, and the remaining Mac tools under `Tools/` cover
what is left. The measurements it produced still stand.

The app itself must be built and signed in Xcode. Open `VirtualGears.xcodeproj`,
choose the `VirtualGears` scheme and a physical iPhone, and select your
development team under Signing & Capabilities. See `MAC_SETUP.md` for the
hardware procedures.

A successful build or a successful CoreBluetooth write is not hardware evidence.
A trainer command counts as proven only when the trainer replies to confirm it.

To work on the website:

```bash
pip install -r docs/requirements.txt
mkdocs serve
```

## Licence

Copyright &copy; 2026 Stefan Broenner. All rights reserved.

The source is public so it can be read and checked, but it is not open source:
you may not redistribute it or publish an app derived from it. See
[LICENSE](LICENSE) for the exact terms.
