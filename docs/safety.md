# Safety

VirtualShift changes one setting on your trainer: its idea of your wheel size.
It never touches resistance directly, and it never overrides what your riding
app asks for.

## The range was measured, not guessed

The 646.9–4800 mm range was confirmed on a physical KICKR V5, every value
acknowledged by the trainer, with the reference restored between each probe.
VirtualShift never asks for anything outside it.

Wheel size is sent in tenths of a millimetre, so what the trainer receives is
exactly what the safety check judged.

## The trainer is always put back

Ending virtual shifting returns the trainer to the riding app's latest wheel
size, or to the size VirtualShift borrowed if the riding app did not set one.

This matters because the trainer works out its speed from that setting. A
virtual gear left behind would quietly distort speed and distance. A wheel size
set by the riding app is different: that app still owns the ride, so its latest
number remains the baseline when virtual shifting ends.

Wheel size is part of the standard interface available to every riding app.
Whenever one sets it, VirtualShift rebuilds every gear around it. That number
belongs to the riding app, and stopping VirtualShift does not stop the app's
ride, so the trainer returns to that number when virtual shifting ends.

!!! info "If the app is interrupted"

    If iOS ends VirtualShift, the riding app's Bluetooth link cannot survive.
    The size VirtualShift originally borrowed is still written down, so the next
    launch puts the trainer back without saying anything about it.

## What it is not

VirtualShift is not a medical device and not a safety device. It controls
exercise equipment, and you use it at your own risk.
