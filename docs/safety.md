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

The 24 virtual gears span 517.5 mm to 4735.1 mm at a 2070 mm reference, so both
ends of the ladder have been confirmed on real hardware. These are the edges we
chose to test, not a claim that the KICKR rejects values outside them. Virtual
Gears keeps its own operating range at 500–4800 mm and never asks for anything
outside it.

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
