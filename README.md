<p align="center">
  <img src="docs/banner.png" alt="Virtual Gears — virtual shifting for Wahoo KICKR">
</p>

# Virtual Gears

**Virtual shifting for Wahoo KICKR trainers — even in riding apps that do not
offer it.**

Virtual Gears puts an iPhone between your trainer and the app you ride with.
Your riding app still controls the route and its hills; Virtual Gears adds the
gears. Because it appears as a normal FTMS trainer, the riding app does not need
to know anything about virtual shifting.

![Your riding app connects to Virtual Gears, which connects to a Wahoo KICKR and optional accessories](docs/how-it-works.svg)

Leave the bike in a quiet, straight chain line and shift virtually instead.
Nothing moves on the bike, so shifting is silent and cannot drop the chain.

**[Read the full documentation](https://sbroenne.github.io/VirtualGears/)**

## Why it exists

Wahoo brought native virtual shifting to newer trainers but has said the KICKR
V5 will not receive it. Native shifting also depends on support inside the
riding app. Virtual Gears fills both gaps: it gives a KICKR gears and makes them
available to ordinary FTMS riding apps without changing their route data.

[Read Wahoo's compatibility statement](https://support.wahoofitness.com/hc/en-us/articles/16865097915666-Virtual-shifting-with-Wahoo-smart-trainers)

## What you need

| | Requirement |
|---|---|
| **iPhone** | iOS 17 or later |
| **Trainer** | A compatible direct-drive Wahoo KICKR |
| **Riding app** | An app that can connect to an FTMS trainer |
| **Shifting** | Large iPhone buttons; optional original Zwift Click |
| **Fan** | Optional Wahoo KICKR HEADWIND |

Virtual Gears was built and physically tested with a KICKR V5. Other
direct-drive KICKR models are expected to work but have not yet been physically
tested. The KICKR SNAP, KICKR BIKE and trainers from other brands are not
supported.

On the riding-app side, FulGaz on macOS and Windows, plus RealVelo and MyWhoosh
on Windows, have been ridden end to end. Other FTMS riding apps are expected to
work but have not been tested.

[Detailed compatibility information](https://sbroenne.github.io/VirtualGears/requirements/#which-trainers-work)

## Your first ride

1. Wake the KICKR by turning the pedals.
2. Open Virtual Gears on the iPhone. It finds the KICKR, connects and makes it
   available to your riding app.
3. In your riding app, connect to the trainer named **Virtual Gears**. Some apps
   may show the iPhone's name instead.
4. Tap **Start Shifting**, then shift with the large **Easier** and **Harder**
   buttons.

There is no setup wizard. Virtual Gears is a transparent trainer connection as
soon as the KICKR is ready. **Start Shifting** engages the gears; **Stop Shifting**
removes them without disconnecting or stopping the ride in your riding app. If it
finds more than one trainer, it asks you to choose yours by name.

The iPhone screen stays awake while the trainer proxy is available. This keeps
Virtual Gears discoverable to riding apps on Windows and other computers before
they connect.

The same rule applies to optional equipment: one Click or Headwind is used
automatically; if several are found, Virtual Gears asks instead of guessing.

No trainer nearby? Tap **Try Demo** on the looking-for-trainer screen. Demo Mode
is clearly marked as simulated and lets you try the ride controls, gear ladder,
gear choices, Settings and example accessory controls. It does not scan,
connect, advertise or send Bluetooth commands, and it does not change saved
equipment. Demo Mode shows how the app works; it does not prove compatibility
with physical hardware.

## What it can do

- **24 ready-made virtual gears**, with extra range for climbing.
- **App-independent shifting** for FTMS riding apps that have no virtual gears
  of their own.
- **Real-bike gearing**, built from your chainrings and cassette.
- **On-phone shifting** with large controls in portrait and landscape.
- **Accessible ride controls** with VoiceOver gear feedback, adjustable gear
  control and support for larger text.
- **Persistent equipment statuses** that keep the trainer, Click, fan and
  riding app visible independently, including while the riding app is waiting.
- **Automatic optional-equipment discovery** for an original Zwift Click and
  Wahoo KICKR HEADWIND.
- **Optional Zwift Click shifting** from the handlebar.
- **Headwind control** with Automatic, Off, 25%, 50%, 75% and 100% settings.
- **Careful Headwind hand-back** that restores the fan's exact pre-shifting
  state when shifting stops, without stopping the riding app.
- **Mid-ride changes** to the trainer, gears, Click or Headwind.
- **Ride continuity** when you answer a call or briefly switch apps.
- **A Bluetooth-free Demo Mode** for exploring the app without equipment.

## Screenshots

<table>
  <tr>
    <td width="50%" align="center">
      <a href="docs/screenshots/riding-landscape.png">
        <img src="docs/screenshots/riding-landscape.png" width="100%" alt="Virtual Gears ride controls in landscape">
      </a>
      <br>
      <strong>Ride and shift</strong>
    </td>
    <td width="50%" align="center">
      <a href="docs/screenshots/headwind-control-landscape.png">
        <img src="docs/screenshots/headwind-control-landscape.png" width="100%" alt="Wahoo Headwind manual control in landscape">
      </a>
      <br>
      <strong>Control the Headwind</strong>
    </td>
  </tr>
</table>

<details>
  <summary><strong>More screenshots</strong></summary>
  <br>
  <p align="center">
    <a href="docs/screenshots/riding.png">
      <img src="docs/screenshots/riding.png" width="28%" alt="Virtual Gears ride screen">
    </a>
    <a href="docs/screenshots/gears.png">
      <img src="docs/screenshots/gears.png" width="28%" alt="The 24-step virtual gear ladder">
    </a>
    <a href="docs/screenshots/gears-real-bike.png">
      <img src="docs/screenshots/gears-real-bike.png" width="28%" alt="Virtual gears based on a real drivetrain">
    </a>
  </p>
</details>

## How it works

Virtual Gears acts as a Bluetooth FTMS trainer for the riding app and as a
controller for the real KICKR. It passes the riding app's commands and trainer
data through, then applies the selected gear by changing the wheel
circumference configured on the KICKR.

Every gear change waits for confirmation from the trainer.

[How the gears work](https://sbroenne.github.io/VirtualGears/how-it-works/) ·
[Safety details](https://sbroenne.github.io/VirtualGears/safety/) ·
[Accessibility](https://sbroenne.github.io/VirtualGears/accessibility/)

## Important limitations

- **ERG workouts are not supported.** ERG mode controls target power, while
  Virtual Gears controls how hard a gear feels.
- **The riding app cannot display the selected gear.** Bluetooth FTMS has no
  message for reporting it, so the gear is shown on the iPhone.
- **This is not Zwift's native virtual shifting.** It works independently of the
  riding app. Virtual Gears supplies and displays the gears itself.
- **Virtual Gears cannot read the trainer's current wheel circumference.** It
  uses the **Normal wheel circumference** saved in Settings, 2070 mm by default,
  unless the riding app supplies another size. If you use a custom value in the
  Wahoo app, enter the same value in Virtual Gears before shifting.

## Support

Questions go in [Q&A discussions][qa]; bugs go in [Issues][newissue]. The
[support page](https://sbroenne.github.io/VirtualGears/support/) lists the
common problems and their answers first.

  [qa]: https://github.com/sbroenne/VirtualGears/discussions/categories/q-a
  [newissue]: https://github.com/sbroenne/VirtualGears/issues/new/choose

## Independent project

Virtual Gears is not affiliated with Wahoo Fitness or Zwift. Wahoo, KICKR,
HEADWIND, Zwift and Zwift Click are trademarks of their respective owners.

## Acknowledgements

The FulGaz-on-Windows compatibility investigation was informed by the outward
Bluetooth behavior of [QZ (qdomyos-zwift)](https://github.com/cagnulein/qdomyos-zwift),
an independent GPL-3.0 project. Virtual Gears implements the standard Bluetooth
services independently; no QZ source code is copied or bundled.

## Licence

Copyright &copy; 2026 Stefan Broenner. All rights reserved.

The source is public so it can be read and checked, but it is not open source.
Redistribution and publishing derived applications are not permitted. See
[LICENSE](LICENSE) for the exact terms.

[Development and hardware-testing documentation](DEVELOPMENT.md)
