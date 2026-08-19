# What you need

| | |
|---|---|
| **iPhone** | Running iOS 17 or later — any iPhone from the XS onwards |
| **Trainer** | A compatible direct-drive Wahoo KICKR. [See below](#which-trainers-work). |
| **Riding app** | An app that can connect to an FTMS trainer. |
| **Shifting** | Large buttons on the iPhone. An original Zwift Click is optional. |
| **Fan** | Optional. A Wahoo KICKR HEADWIND. |

## Which trainers work

Virtual Gears shifts gears by changing the wheel size the trainer is set up for.
That is not how every trainer with KICKR written on it works, so the model
matters.

| Trainer | Works? |
|---|---|
| **KICKR V5** | **Yes** — the trainer the app was built and physically tested with |
| Other direct-drive **Wahoo KICKR** models, including CORE and MOVE | Expected to work, but not yet physically tested |
| **KICKR ROLLR** | Unknown. The app allows you to try it but does not claim support |
| **KICKR Snap** | No. It changes gear a different way |
| **KICKR Bike** | No. It has its own gear levers already |
| Tacx, Elite, Saris, Zwift Hub, anything else | No |

The app lists every KICKR it can see and tells you plainly if yours is one it
cannot work with, rather than leaving you to wonder why nothing happens.

### If you set a custom wheel circumference

Virtual Gears cannot read the wheel circumference previously set through the
Wahoo app. Set **Normal wheel circumference** in Virtual Gears Settings to the
same value before shifting. The default is 2070 mm and the available range is
1800–2400 mm. A wheel size supplied by the riding app takes precedence.

Stopping shifting restores that normal value, or the latest value from the
riding app, without disconnecting the riding app from Virtual Gears.

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

That is the gap Virtual Gears fills. Three differences worth knowing:

- **Your riding app will not display the gear.** Zwift can show it because Zwift
  decides it. Virtual Gears decides it, and there is no way to tell a riding app
  what gear you are in — the Bluetooth standard has no such message. The gear is
  shown large on the phone instead.
- **Virtual Gears does not require virtual-shifting support in the riding app.**
  It appears as an ordinary FTMS trainer, bringing gears to compatible apps that
  do not provide their own.
- **Virtual Gears does not support Zwift-native virtual shifting.** It supplies
  and displays its own gears on the iPhone.

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
course profile drift away from the truth. Virtual Gears changes the trainer's own
idea of the bike and leaves the road alone.

## Which riding apps work

Virtual Gears appears as an ordinary FTMS trainer, so a riding app needs no
special support for it. Compatibility still depends on the riding app and
computer:

| Riding app | Status |
|---|---|
| FulGaz on macOS | Works, including power and cadence |
| FulGaz on Windows | Works, including power and cadence |
| RealVelo on Windows | Works |
| MyWhoosh on Windows | Works, including power and cadence |
| Others | Expected to work, not tested |

MyWhoosh ignored FTMS ride data in direct testing and read power and cadence
from Cycling Power Service instead. Virtual Gears now publishes that service,
and the complete iPhone-to-Windows path has been ridden end to end.

## Your first ride

1. Put your bike on the trainer and wake the trainer by turning the pedals.
2. Open Virtual Gears on your iPhone. It finds the trainer and connects on its
   own, then appears as a trainer. If it finds more than one trainer, it asks
   you which one.
3. On your computer, open your riding app and pair with the trainer it offers.
   That will be your iPhone, appearing as a trainer.
4. Tap **Start Shifting** when you want gears. Shift with the two large buttons
   on the phone.

The first-run setup guide can be completed or deferred. Trainer pass-through
does not depend on it, but virtual shifting needs safe gearing and a confirmed
parked gear. Start and Stop control only virtual shifting. Virtual Gears remains
connected as a transparent trainer proxy, so stopping shifting does not pause,
stop or disconnect the ride in your riding app.

You can explore the app without any equipment by tapping **Try Demo** while it
looks for a trainer. The simulated ride does not use Bluetooth or control
exercise equipment. A real ride still requires the compatible hardware above.

### What name to look for

Virtual Gears tells your riding app it is called **Virtual Gears**, and most apps
show that. Some show your iPhone's own name instead — "iPhone Anna", say —
and a few add a short code after it.

Either name is the right one to pick. There is only ever one of them in the
list, because your trainer itself is already busy talking to Virtual Gears and
so does not appear.

This is not something the app can fix. iPhones report their own name over
Bluetooth, and Apple does not let an app change it. If seeing "Virtual Gears"
in the list matters to you, rename the phone itself in Settings → General →
About → Name — but that changes its name everywhere else too.

## Adding a Zwift Click

Wake the Click by pressing a button before opening Virtual Gears. The app finds,
connects and remembers it automatically. It shifts the same gears as the
on-screen buttons, and pressing it visibly presses the matching phone button.
The gear number still changes only after the trainer confirms the shift.
Nothing ever waits for the Click, so one that runs out of battery mid-ride
costs you nothing but the buttons on the handlebar.

If the app finds more than one Click, choose yours in Settings rather than
letting it guess. Some Clicks advertise the same name. In that case, keep
pressing either button on the Click you want while Virtual Gears briefly tries
each one; it confirms the Click whose connected button stream reports the press.

The app shows the Click's battery level in Settings, and warns you on the ride
screen if it drops below 20%.

## Adding a Wahoo Headwind

Turn on the Headwind before opening Virtual Gears. The app finds, connects and
remembers it automatically. During a ride, the fan button switches between
Automatic control from the Headwind's paired sensor and a manual speed from
0–100%. Manual has a slider and one-tap buttons for Off, 25%, 50%, 75% and 100%.

If the app finds more than one Headwind, choose yours by name in Settings.

Manual mode remains on the Headwind after Bluetooth disconnects. Virtual Gears
therefore sends an explicit sensor-control command and waits for the fan to
confirm it before switching to another Headwind.

## Choosing your gears

The starting choice is a 24-step virtual ladder with extra room for easy
climbing. If you would rather ride the gears of a real bike, pick a groupset
from Shimano, SRAM or Campagnolo — or set the chainrings and cassette yourself
if your bike is not listed — and the app builds that instead.

The ladder is built the way Shimano Synchronized Shift and SRAM AXS Sequential
build theirs: one cog per press, with the front change folded in and paired with
a compensating rear jump. Campagnolo has no synchronised mode, so its entries
model Campagnolo gearing and shift points rather than a Campagnolo algorithm.

Virtual Gears also asks which gear your bike is parked in, because the bike never
shifts and that ratio is what every virtual gear is scaled from. It recommends
the quietest gear that works, so this is normally one tap.

Virtual Gears is not affiliated with or endorsed by Zwift, Wahoo, Shimano, SRAM
or Campagnolo.

You can change this mid-ride without interrupting the riding app. The trainer
must confirm the newly selected gear before the app shows it.
