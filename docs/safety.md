# Safety

Virtual Gears changes one setting on your trainer: its idea of your wheel size.
It never touches resistance directly, and it never overrides what your riding
app asks for.

Demo Mode is separate from this hardware path. It uses local simulated gear
state, does not use Bluetooth, does not run the interrupted-ride baseline reset
and cannot send a command to exercise equipment.

## The range was measured, not guessed

The wheel sizes Virtual Gears actually sends were confirmed on a physical
KICKR V5, with the 2070 mm reference reset between every probe.

Ten values from 647 mm to 4800 mm were confirmed in the first run. A later run
covered the easy end the gears reach — 517.5, 525, 550, 575, 600, 625 and
647 mm — and the trainer acknowledged every one, in 60 to 180 ms. That run is
recorded in `docs/kickr-wheel-size-sweep.log` in the repository.

Those two runs stopped at 517.5 mm, while the app's own operating range went
down to 500 mm. A third run closed that gap: 500, 502.5, 505, 507.5, 510, 512.5,
515 and 517.5 mm were all acknowledged, in 58 to 181 ms, and it is recorded in
`docs/kickr-wheel-size-sweep-low-end.log`. The bottom of the range is now
measured rather than assumed.

A fourth run raised the top. It stepped from 4800 mm to 5000 mm in 25 mm steps
— nine values, every one acknowledged in 59 to 152 ms, none refused — and is
recorded in `docs/kickr-wheel-size-sweep-high-end.log`.

The 24 virtual gears span 517.5 mm to 4735.1 mm at a 2070 mm reference, so both
ends of the ladder have been confirmed on real hardware. These are the edges we
chose to test, not a claim that the KICKR rejects values outside them. Virtual
Gears keeps its own operating range at 500–5000 mm and never asks for anything
outside it. Every value at both edges of that range has been confirmed.

## Why the range is wider than the gears need

The gears themselves only reach 517.5 mm to 4735.1 mm, so the range looks
generous at both ends. That spare room is not for gears; it is for the riding
app.

A riding app may set its own wheel size, and the reference app really does.
Virtual Gears rebuilds the whole ladder around whatever size it is given, so the
range has to hold not just the ladder but the ladder shifted up or down by that
request. At a 4800 mm ceiling the ladder could only be rebuilt for wheels
between 2000 mm and 2098 mm, which turned a 700x25c wheel at 2105 mm — an
ordinary road wheel — into a refusal. Raising the ceiling to 5000 mm widens that
window to 2000–2186 mm.

Measured against real wheel sizes, that window now covers the road sizes:

| Wheel | Circumference | Accepted |
| --- | --- | --- |
| 650b | 1900 mm | no |
| 26 inch | 2070 mm | yes |
| 700x23c | 2096 mm | yes |
| 700x25c | 2105 mm | yes |
| 700x28c | 2136 mm | yes |
| 700x38c | 2180 mm | yes |
| 29 inch | 2300 mm | no |

A 29er and a 650b are still refused. That is a real limitation, not an
oversight: covering them would mean either measuring a wider range on the
trainer or narrowing the gears, and neither has been done.

Nothing here is a limit of the gears or of the trainer. Both would go further —
the trainer acknowledged 5000 mm on the first ask. It is a limit of what has
been measured, which is the only thing this app is willing to send.

A request that falls outside the window is refused rather than clamped, and the
trainer keeps the wheel size it already had. Nothing unproven is ever sent. The
rider is not told when this happens; it appears only in the app's own log.

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
