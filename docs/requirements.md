# What you need

| | |
|---|---|
| **iPhone** | Running iOS 17 or later — any iPhone from the XS onwards |
| **Trainer** | Wahoo KICKR V5. Other KICKRs, [see below](#which-trainers-work) |
| **Riding app** | Anything that supports FTMS trainers. Development is validated against RealVelo; Zwift, FulGaz and others use the same interface. |
| **Shift buttons** | Optional. An original Zwift Click. |
| **Fan** | Optional. A Wahoo KICKR HEADWIND. |

## Which trainers work

VirtualShift shifts gears by changing the wheel size the trainer is set up for.
That is not how every trainer with KICKR written on it works, so the model
matters.

| Trainer | Works? |
|---|---|
| **KICKR V5** | **Yes** — the trainer the app was built and measured against |
| Other **Wahoo KICKR** models, including the Core | Should work. Not tested, and the app will say so |
| **KICKR Snap** | No. It changes gear a different way |
| **KICKR Bike** | No. It has its own gear levers already |
| Tacx, Elite, Saris, Zwift Hub, anything else | No |

The app lists every KICKR it can see and tells you plainly if yours is one it
cannot work with, rather than leaving you to wonder why nothing happens.

### If your KICKR is not the V5

Try it. Nothing bad happens if it turns out not to work: every gear change has
to be confirmed by the trainer before the app accepts it, so a trainer that
ignores the instruction will fail visibly rather than quietly give you the wrong
gear. If it does work, it would be good to hear about it.

### What about Zwift's own virtual shifting?

Zwift has virtual shifting of its own, and where it is available it is the
better option: Zwift shows the gear on screen, because Zwift is the one choosing
it. Rouvy supports it too.

It is not available on a KICKR V5, and never will be. Wahoo's own
[support page][wahoo] lists the trainers that can do it — KICKR MOVE, KICKR V6,
KICKR CORE 1 and 2 — and then answers the obvious question directly:

> "We have reviewed the hardware and firmware capabilities of KICKR v5 (2020)
> and preceding KICKR versions. Unfortunately, these older models are unable to
> support the required protocols for virtual shifting using the Zwift protocol
> and will not be receiving a future update for this functionality."

That is the gap VirtualShift fills. Two differences worth knowing:

- **Your riding app will not display the gear.** Zwift can show it because Zwift
  decides it. VirtualShift decides it, and there is no way to tell a riding app
  what gear you are in — the Bluetooth standard has no such message. The gear is
  shown large on the phone instead.
- **VirtualShift works in every riding app.** Zwift's virtual shifting works in
  Zwift and Rouvy only, by Wahoo's own account.

  [wahoo]: https://support.wahoofitness.com/hc/en-us/articles/16865097915666-Virtual-shifting-with-Wahoo-smart-trainers

### Why not other brands

Tacx trainers do not speak this part of the Bluetooth standard at all — they use
a different protocol inherited from ANT+. Elite, Saris and most others do speak
it, but no trainer is known to actually act on the wheel-size instruction, and a
KICKR will answer "yes" to instructions it has no intention of carrying out, so
asking politely proves nothing.

Other apps get around this by lying about the hill instead: you ask for a harder
gear and they tell the trainer the road is steeper than it is. That works
anywhere, but your riding app then has the wrong gradient, so your speed and the
course profile drift away from the truth. VirtualShift changes the trainer's own
idea of the bike and leaves the road alone.

## Your first ride

1. Put your bike on the trainer and wake the trainer by turning the pedals.
2. Open VirtualShift on your iPhone. It finds the trainer and connects on its
   own. If more than one trainer is nearby and none is clearly closest, it asks
   you which one.
3. On your computer, open your riding app and pair with the trainer it offers.
   That will be your iPhone, appearing as a trainer.
4. Ride. Shift with the two large buttons on the phone.

There is no setup screen to complete first and no start button to press.

### What name to look for

VirtualShift tells your riding app it is called **VirtualShift**, and most apps
show that. Some show your iPhone's own name instead — "iPhone Anna", say —
and a few add a short code after it.

Either name is the right one to pick. There is only ever one of them in the
list, because your trainer itself is already busy talking to VirtualShift and
so does not appear.

This is not something the app can fix. iPhones report their own name over
Bluetooth, and Apple does not let an app change it. If seeing "VirtualShift"
in the list matters to you, rename the phone itself in Settings → General →
About → Name — but that changes its name everywhere else too.

## Adding a Zwift Click

Open Settings in the app and add the Click there. It shifts the same gears as
the on-screen buttons. Nothing ever waits for it, so a Click that runs out of
battery mid-ride costs you nothing but the buttons on the handlebar.

The app shows the Click's battery level in Settings, and warns you on the ride
screen if it drops below 20%.

## Adding a Wahoo Headwind

Open Settings, choose Wahoo Headwind, and select the nearby fan. During a ride,
the fan button switches between the Headwind's own sensor control and a manual
speed from 0–100%.

Manual mode remains on the Headwind after Bluetooth disconnects. VirtualShift
therefore sends an explicit Sensors command and waits for the fan to confirm it
before removing or replacing a saved Headwind.

## Choosing your gears

The starting choice is a 24-step virtual ladder with extra room for easy
climbing. If you would rather ride the gears of a real bike, describe it by its
chainrings and cassette and the app builds that instead.

You can change this mid-ride. The trainer is always put back to normal before
the new gears are applied.
