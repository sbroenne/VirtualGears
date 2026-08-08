# See it working

## Try it without equipment

Open Virtual Gears and tap **Try Demo** while it is looking for a trainer. The
blue notice and every equipment status make clear that the ride is simulated and
that no trainer is connected.

In Demo Mode you can:

- shift easier and harder with the same large controls used on a real ride;
- see the current gear move along the full gear ladder;
- watch the wheel size the trainer would be set to, and the exact command bytes
  that carry it, change with every shift;
- see a gear appear only after the simulated trainer confirms it, which is the
  rule a real ride follows;
- watch a simulated riding app work its way over hills on its own channel,
  without ever disturbing the gears;
- switch between the 24 virtual gears and a real-bike drivetrain;
- open Settings and inspect the simulated trainer, Click, Headwind and riding-app
  status; and
- try simulated Headwind Automatic and Manual controls.

The wheel sizes and command bytes are not illustrations. Demo Mode drives the
same `ConfirmedGearEngine` a real ride uses, and the stand-in trainer answers in
the KICKR's own wire format, so the numbers on screen are the ones that would go
out over Bluetooth. Only the radio is missing.

Tap **Exit Demo** to return to normal trainer discovery. Demo choices stay only
inside that demo and are discarded when it closes. Demo Mode does not scan,
advertise, connect or send Bluetooth commands.

!!! warning "Simulation is not hardware evidence"

    Demo Mode shows the product screens and local gear behavior. It does not
    prove that a trainer, Click, Headwind or riding app is physically compatible.
    The compatibility claims on this site remain based on the recorded hardware
    evidence in the repository.

## What a ride looks like

<figure markdown>
  ![The saved trainer connecting while the Zwift Click and Headwind are connected](screenshots/starting.png){ width="280" }
  <figcaption>Open the app and it goes looking for your trainer. There is
  nothing to press for a real ride. Try Demo is available when no trainer is
  nearby. Optional equipment reconnects by itself.</figcaption>
</figure>

<figure markdown>
  ![The ride screen, showing gear 12 of 24](screenshots/riding.png){ width="280" }
  <figcaption>The ride screen. Two large buttons, a gear number big enough to
  read from the saddle, a fan button when a Headwind is added, and live
  connection state along the bottom.</figcaption>
</figure>

<figure markdown>
  ![Headwind manual fan control at 50 percent](screenshots/headwind-control.png){ width="280" }
  <figcaption>An optional Headwind can stay on Automatic or use a manual speed.
  Common speeds take one tap, and Slower and Faster are large enough to use on
  the bike.</figcaption>
</figure>

<figure markdown>
  ![Settings with trainer, Zwift Click and Wahoo Headwind](screenshots/settings.png){ width="280" }
  <figcaption>One compact Settings screen shows every piece of equipment and its
  connection state.</figcaption>
</figure>

<figure markdown>
  ![The 24 virtual gears drawn as bars](screenshots/gears.png){ width="280" }
  <figcaption>Your gears, drawn rather than listed. A tall step is a jump your
  legs will notice.</figcaption>
</figure>

<figure markdown>
  ![A real 50/34 with 11-34 drawn as sixteen gears](screenshots/gears-real-bike.png){ width="280" }
  <figcaption>Or describe a real bike, and ride its gears instead.</figcaption>
</figure>
