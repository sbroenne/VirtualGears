# Safety

Virtual Gears changes one setting on your trainer: its idea of your wheel size.
It never touches resistance directly, and it never overrides what your riding
app asks for.

Demo Mode is separate from this hardware path. It uses local simulated gear
state, does not use Bluetooth, does not run the interrupted-ride baseline reset
and cannot send a command to exercise equipment.

## The trainer has no wheel-size limit we could find

This is worth stating plainly, because Virtual Gears got it wrong for a long
time.

A physical KICKR V5 was probed across the whole span the command can express,
and it acknowledged **every value from 0.1 mm to 6553.5 mm**. 6553.5 mm is
simply the largest number that fits in the command. Six later runs staged
sixty-four more values — 425 to 500 mm, 500 to 647 mm, 647 to 4800 mm, 4800 to
5350 mm, and 5350 to 5525 mm — with the 2070 mm reference reset between every
probe. Not one was refused, and replies came back in 58 to 268 ms.

The runs are recorded in `docs/kickr-wheel-size-sweep.log`,
`docs/kickr-wheel-size-sweep-low-end.log`,
`docs/kickr-wheel-size-sweep-high-end.log`,
`docs/kickr-wheel-size-sweep-fulgaz.log` and
`docs/kickr-wheel-size-sweep-full-window.log`.

So there is exactly one hard limit, and it belongs to the protocol rather than
the trainer: a wheel size larger than 6553.5 mm cannot be expressed at all.

Virtual Gears used to carry a narrower range and describe it as what the trainer
had been "proven to accept". That was not true. It was a record of which values
someone had happened to probe, and it was quietly doing a second job it was
never designed for — see below. It has been removed.

## What Virtual Gears supports, and why that is a decision

Because the trainer takes anything, the only question left is which wheel sizes
make sense for a bicycle. Virtual Gears accepts wheel sizes from a riding app
between **1800 mm and 2400 mm**.

That is a product decision, not a measurement, and it is stated in one place in
the code with a test that walks every tenth of a millimetre in it and checks all
24 gears can be built. Its width is bounded by one real thing: at 2400 mm the
hardest gear reaches 5490 mm, and the command stops at 6553.5 mm.

| Wheel | Circumference | Accepted |
| --- | --- | --- |
| 650b | 1900 mm | yes |
| 26 inch | 2070 mm | yes |
| 700x23c | 2096 mm | yes |
| 700x25c | 2105 mm | yes |
| 700x28c | 2136 mm | yes |
| 700x38c | 2180 mm | yes |
| FulGaz | 2200 mm | yes |
| 29 inch | 2326 mm | yes |

### Why this needed fixing

Virtual Gears rebuilds its whole gear ladder around whatever wheel size the
riding app asks for. The wheel sizes it would accept were never written down
anywhere. They fell out of where the 24 gears happened to sit inside that old
"proven range", so nobody could look them up, and nothing failed until a real
riding app asked for one that did not fit.

It kept costing real riders, one at a time. A 700x25c wheel at 2105 mm — an
ordinary road wheel — was refused. So was a 650b. And FulGaz, which was watched
directly by having a Mac pretend to be the trainer it connects to, asks for
**2200 mm** whenever a ride starts; that was refused too, which meant Virtual
Gears and FulGaz could not have worked together at all. The capture is in
`docs/fulgaz-app-tap-run.log`.

All three are now accepted, and the window is declared rather than emergent, so
the next one cannot be discovered by a rider.

A request outside the window is still refused rather than clamped, and the
trainer keeps the wheel size it already had. The rider is not told when this
happens; it appears only in the app's own log.

Wheel size is sent in tenths of a millimetre, so what the trainer receives is
exactly what the safety check judged.

## If you set a custom wheel circumference

The KICKR does not expose its current wheel circumference through FTMS, so
Virtual Gears cannot read that setting when it connects. It starts from a
2070 mm reference unless the riding app supplies a different wheel size.

That means Virtual Gears overwrites a custom circumference set through the
Wahoo app and cannot put that unknown value back automatically. If you use a
custom value, write it down and set it again in the Wahoo app after using
Virtual Gears. Most riders never change this setting.

## What it is not

Virtual Gears is not a medical device and not a safety device. It controls
exercise equipment, and you use it at your own risk.
