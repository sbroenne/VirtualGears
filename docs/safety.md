# Safety

Virtual Gears changes one setting on your trainer: its idea of your wheel size.
It never touches resistance directly, and it never overrides what your riding
app asks for.

Demo Mode is separate from this hardware path. It uses local simulated gear
state, does not use Bluetooth, does not run the interrupted-ride baseline reset
and cannot send a command to exercise equipment.

## The range was measured, not guessed

Ten wheel sizes between 647 mm and 4800 mm were sent to a physical KICKR V5 and
every one was acknowledged by the trainer, with the 2070 mm reference reset
between each probe. These are the edges we chose to test, not a claim that the
KICKR rejects values outside them.

Virtual Gears keeps its own operating range at 500–4800 mm and never asks for
anything outside it. The easiest of the 24 virtual gears works out at 517.5 mm,
which sits below the lowest value on that recorded run, so the easy end of the
ladder has not yet been individually confirmed on hardware.

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
