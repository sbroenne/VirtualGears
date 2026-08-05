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

Every ride ends by returning the trainer to where it started: 2070 mm, or the
wheel size the riding app set if it set one.

This matters because the trainer works out its speed from that setting. A value
left behind would quietly distort the speed and distance of any ride that did
not use VirtualShift.

!!! info "If the app is interrupted"

    If iOS ends the app before a ride can stop, the size the ride borrowed is
    still written down. The next launch puts the trainer back, without saying
    anything about it.

## What it is not

VirtualShift is not a medical device and not a safety device. It controls
exercise equipment, and you use it at your own risk.
