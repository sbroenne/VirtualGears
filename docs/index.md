# VirtualShift

<p align="center">
  <img src="banner.png" alt="VirtualShift — virtual gears for your smart trainer">
</p>

**VirtualShift gives you gears on an indoor trainer that has none.**

Your chain stays in one quiet, straight gear all ride. Shifting happens on your
iPhone instead, which changes how hard the trainer feels. Nothing on the bike
moves, so there is no chain noise, no dropped chain, and no wear.

[See it working](demo.md){ .md-button .md-button--primary }
[What you need](requirements.md){ .md-button }

---

## What it is

Your riding app connects to the iPhone instead of to the trainer. VirtualShift
passes everything through in both directions, and applies your chosen gear on
top. The riding app still controls the road: hills feel like hills.

```text
riding app on your computer  <->  iPhone running VirtualShift  <->  KICKR V5
                                              ^
                                              |
                                     Zwift Click (optional)
```

<p align="center">
  <img src="screenshots/riding.png" width="30%" alt="The ride screen, showing gear 12 of 24">
  <img src="screenshots/gears.png" width="30%" alt="The 24 virtual gears drawn as bars">
  <img src="screenshots/gears-real-bike.png" width="30%" alt="A real 50/34 with 11-34, drawn as sixteen gears">
</p>

## What you get

### Gears you can see

Either the 24 virtual gears Zwift and Wahoo use, which suit any bike and are the
starting choice, or a copy of a real bike described by its chainrings and
cassette. A real 50/34 with an 11-34 cassette gives sixteen gears, running 34x34
up to 50x11 — the gears you would really ride, not every possible pairing of a
ring with a cog.

Whichever you choose is drawn rather than listed: one bar per gear, easiest to
hardest, on a scale where a tall step is a jump the legs will notice. How far
the gears reach and how evenly they are spread are visible at a glance, which no
list of tooth counts can tell you.

### Shifting

Two large buttons on the phone, placed for sweaty hands and a locked-out gaze.
An original Zwift Click can be added and shifts the same gears, but it is never
required and nothing ever waits for it.

### Nothing to set up

Open the app. It looks for your trainer, connects to it, starts the session and
appears to your riding app, all on its own. There is no setup to complete and no
button to press.

The only question it ever asks is which trainer, and only when it genuinely
cannot tell: one trainer nearby is simply used, several are only chosen
automatically when one is clearly closest. Bluetooth reaches through walls, and
connecting to a neighbour's trainer would change their wheel size, so anything
ambiguous is asked rather than guessed.

### Everything changeable mid-ride

Trainer, gears and Click can all be changed from the ride screen. Changing gears
quietly restarts the session, so the trainer is always put back before the new
gears are applied.

### A ride survives an interruption

Taking a call, tapping a notification or switching to another app does not end
your ride. The trainer stays connected and your riding app stays paired, so you
can come back to the same gear.

## What it does not do

**ERG mode.** A workout that sets a target power is refused, because holding a
power target and holding a gear are two different ideas of what the trainer
should feel like. VirtualShift still tells riding apps it is a trainer they can
steer, so it appears in their trainer list rather than as a bare power sensor.

!!! note "Not affiliated with Wahoo or Zwift"

    VirtualShift is an independent app. Wahoo, KICKR, Zwift and Zwift Click are
    the trademarks of their respective owners, named here only to say which
    hardware the app works with.
