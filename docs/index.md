# Virtual Gears

<p align="center">
  <img src="banner.png" alt="Virtual Gears — virtual shifting for Wahoo KICKR">
</p>

**Virtual Gears gives you gears on a trainer — and in a riding app — that has
none.**

Use the smaller front ring if your bike has one, then pick a rear gear that keeps
the chain straight and leave it there. Shifting happens on your iPhone instead,
which changes how hard the trainer feels. Nothing on the bike moves, so there is
no chain noise, no dropped chain, and no wear.

!!! quote "Why this exists"

    Zwift added virtual shifting in 2024, and Wahoo brought it to their newer
    trainers. The KICKR V5 was left out, [permanently][wahoo]:

    > "We have reviewed the hardware and firmware capabilities of KICKR v5
    > (2020) and preceding KICKR versions. Unfortunately, these older models
    > are unable to support the required protocols for virtual shifting using
    > the Zwift protocol and will not be receiving a future update for this
    > functionality."

    Virtual Gears gives a KICKR V5 gears anyway. Because it appears as a normal
    FTMS trainer, it also brings virtual shifting to riding apps that do not
    provide their own.

    The app was built and physically tested with a KICKR V5. Other direct-drive
    KICKR models are expected to work but have not yet been physically tested.

  [wahoo]: https://support.wahoofitness.com/hc/en-us/articles/16865097915666-Virtual-shifting-with-Wahoo-smart-trainers

[See it working](demo.md){ .md-button .md-button--primary }
[What you need](requirements.md){ .md-button }

---

## What it is

Your riding app connects to the iPhone instead of to the trainer. Virtual Gears
passes everything through in both directions, and applies your chosen gear on
top. The riding app still controls the road: hills feel like hills. It does not
need special virtual-shifting support; ordinary FTMS trainer support is enough.

![How Virtual Gears sits between your riding app and your trainer](how-it-works.svg)

Wake an original Zwift Click or Wahoo Headwind before opening Virtual Gears and
the app finds and remembers it automatically. The Click shifts from the
handlebar. The Headwind can stay with its own sensor control or use a manual fan
speed. Both remain optional and never hold up a ride.

<p align="center">
  <img src="screenshots/riding.png" width="30%" alt="The ride screen, showing gear 12 of 24 with the Headwind connected">
  <img src="screenshots/gears.png" width="30%" alt="The 24 virtual gears drawn as bars">
  <img src="screenshots/gears-real-bike.png" width="30%" alt="A real 50/34 with 11-34, drawn as sixteen gears">
</p>

## What you get

### Gears you can see

Either a 24-step virtual ladder, tuned with extra room for easy climbing, or a
copy of a real bike described by its chainrings and cassette. A real 50/34 with
an 11-34 cassette gives sixteen gears, running 34x34 up to 50x11 — the gears you
would really ride, not every possible pairing of a ring with a cog.

Whichever you choose is drawn rather than listed: one bar per gear, easiest to
hardest, on a scale where a tall step is a jump the legs will notice. How far
the gears reach and how evenly they are spread are visible at a glance, which no
list of tooth counts can tell you.

### Shifting

Two large buttons on the phone, placed for sweaty hands and a locked-out gaze.
An original Zwift Click can be added and shifts the same gears, but it is never
required and nothing ever waits for it.

The current gear is also an adjustable VoiceOver control: swipe up for a harder
gear and down for an easier one. Confirmed gear changes are announced, so the
ride can be controlled without looking at the screen. [Accessibility
details](accessibility.md) cover larger text and other iPhone settings.

### Headwind control

An optional Wahoo Headwind can use Automatic control from its paired sensor or a
manual speed from the ride screen. Manual offers a slider and one-tap common
speeds. It stays on the fan even after Bluetooth disconnects, so Virtual Gears
explicitly returns control to the sensor and waits for confirmation before
switching to another fan.

<p align="center">
  <img src="screenshots/headwind-control.png" width="30%" alt="Headwind manual fan control at 50 percent in portrait">
  <img src="screenshots/headwind-control-landscape.png" width="60%" alt="Headwind manual fan control at 50 percent in landscape">
</p>

### Nothing to set up

Open the app. It looks for your trainer, connects to it, starts the session and
appears to your riding app, all on its own. There is no setup to complete and no
button to press.

The only question it asks is which device, and only when it finds more than one
trainer, Click or Headwind. A single device is simply used. Bluetooth signal
strength does not measure distance reliably, so multiple devices are listed by
name rather than ranked or guessed.

If no trainer is available, **Try Demo** opens a clearly marked simulated ride.
It includes the ride screen, shifting, gear choices, Settings and example Click,
Headwind and riding-app status. Demo Mode never uses Bluetooth and never changes
saved equipment. It is a tour of the product, not evidence that untested
physical hardware works.

### Everything changeable mid-ride

Trainer, gears, Click and Headwind can all be changed from the ride screen.
Changing gears rebuilds them in place, without interrupting the ride, so the
riding app on your PC never notices. If the trainer will not take the new gears, the ride carries on
with the old ones rather than ending.

### A ride survives an interruption

Taking a call, tapping a notification or switching to another app does not end
your ride. The trainer stays connected and your riding app stays paired, so you
can come back to the same gear.

## What it does not do

**Zwift-native virtual shifting.** Virtual Gears supplies and displays its own
gears over ordinary FTMS; it does not support Zwift's native gear system.

**ERG mode.** A workout that sets a target power is refused, because holding a
power target and holding a gear are two different ideas of what the trainer
should feel like. Virtual Gears still tells riding apps it is a trainer they can
steer, so it appears in their trainer list rather than as a bare power sensor.

**Trainers other than a Wahoo KICKR.** The way Virtual Gears makes gears is not
something every trainer can do, and the KICKR Snap and KICKR Bike cannot do it
either. [Which trainers work](requirements.md#which-trainers-work) has the
detail.

!!! note "Not affiliated with Wahoo or Zwift"

    Virtual Gears is an independent app. Wahoo, KICKR, Zwift and Zwift Click are
    the trademarks of their respective owners, named here only to say which
    hardware the app works with.
