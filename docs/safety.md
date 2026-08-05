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

Every ride ends by returning the trainer to the wheel size it had before that
ride started, which is 2070 mm.

This matters because the trainer works out its speed from that setting. A value
left behind would quietly distort the speed and distance of any ride that did
not use VirtualShift.

Some riding apps, FulGaz among them, set their own wheel size mid-ride.
VirtualShift honours it while the ride is running and rebuilds every gear around
it — but that number belongs to that app and that session, so it is not what the
trainer gets back at the end. The size put back is always the one the ride
borrowed.

!!! info "If the app is interrupted"

    If iOS ends the app before a ride can stop, the size the ride borrowed is
    still written down. The next launch puts the trainer back, without saying
    anything about it.

## What it is not

VirtualShift is not a medical device and not a safety device. It controls
exercise equipment, and you use it at your own risk.
