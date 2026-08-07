# Safety

Virtual Gears changes one setting on your trainer: its idea of your wheel size.
It never touches resistance directly, and it never overrides what your riding
app asks for.

## The range was measured, not guessed

The selected 500–4800 mm operating range was confirmed on a physical KICKR V5,
every value acknowledged by the trainer, with the reference restored between
each probe. These are the edges we chose to test, not a claim that the KICKR
rejects values outside them. Virtual Gears never asks for anything outside the
selected riding range.

A later boundary search reached both ends of Wahoo's two-byte command, with
samples throughout the range acknowledged by the same KICKR V5. The search
restored 2070 mm after every probe and again at the end.

That result proves what the command accepts; it does not prove that the extreme
values produce useful, predictable gears while someone is pedalling. Virtual Gears
therefore keeps its narrower riding range until the wider gears are physically
ride-tested.

Wheel size is sent in tenths of a millimetre, so what the trainer receives is
exactly what the safety check judged.

## How a virtual gear is removed

The KICKR does not expose its current wheel circumference through FTMS, so
Virtual Gears cannot read that setting when it connects. It starts from a
2070 mm reference unless the riding app supplies a different wheel size.

Ending virtual shifting sends that baseline again, removing the scale applied
for the selected gear. This matters because leaving a virtual gear's wheel size
behind would distort speed and distance.

Wheel size is part of the standard interface available to every riding app.
Whenever one sets it, Virtual Gears rebuilds every gear around it. That number
belongs to the riding app, and stopping Virtual Gears does not stop the app's
ride, so the trainer returns to that number when virtual shifting ends.

!!! info "If the app is interrupted"

    If iOS ends Virtual Gears, the riding app's Bluetooth link cannot survive.
    The baseline used for that ride is still written down, so the next launch
    can remove the virtual gear left on the trainer.

## What it is not

Virtual Gears is not a medical device and not a safety device. It controls
exercise equipment, and you use it at your own risk.
