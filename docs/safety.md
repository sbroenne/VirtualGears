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

## The trainer is always put back

Ending virtual shifting returns the trainer to the riding app's latest wheel
size, or to the size Virtual Gears borrowed if the riding app did not set one.

This matters because the trainer works out its speed from that setting. A
virtual gear left behind would quietly distort speed and distance. A wheel size
set by the riding app is different: that app still owns the ride, so its latest
number remains the baseline when virtual shifting ends.

Wheel size is part of the standard interface available to every riding app.
Whenever one sets it, Virtual Gears rebuilds every gear around it. That number
belongs to the riding app, and stopping Virtual Gears does not stop the app's
ride, so the trainer returns to that number when virtual shifting ends.

!!! info "If the app is interrupted"

    If iOS ends Virtual Gears, the riding app's Bluetooth link cannot survive.
    The size Virtual Gears originally borrowed is still written down, so the next
    launch puts the trainer back without saying anything about it.

## What it is not

Virtual Gears is not a medical device and not a safety device. It controls
exercise equipment, and you use it at your own risk.
