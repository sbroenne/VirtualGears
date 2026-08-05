# How the gears work

The KICKR has no virtual-shifting protocol of its own. VirtualShift uses a Wahoo
command that changes the trainer's idea of your wheel size: a smaller wheel
covers less ground per pedal stroke, which feels like an easier gear. The riding
app's own terrain command is left untouched, so the two never fight.

## Where the gears sit

Every gear is scaled away from a 2070 mm reference. The trainer accepts that
scaling over a lopsided range — about 2.3 times harder but 3.2 times easier — so
the starting gear is placed where the tighter end has the most room, rather than
in the middle. A drivetrain too wide to fit is refused at setup rather than
mid-ride.

## When the riding app has its own idea

Some riding apps, FulGaz among them, set a wheel size of their own. VirtualShift
honours it: that size becomes the new reference and every gear is rebuilt around
it, so the gear you are in keeps feeling the way it did and the app's number is
what the trainer is left sitting at. If the gears would no longer fit inside the
proven range around that size, the request is declined and the ride carries on
at the size it already had.

## Shifting waits for the trainer

Asking for a gear and getting it are not the same thing. VirtualShift asks for
the next gear only once the trainer has confirmed the last one, so holding a
shift button sweeps through gears at whatever pace the trainer can really manage
and stops the moment you let go. It cannot run ahead and hand you gears you did
not ask for.

Measured on a Wahoo KICKR V5, a gear change is confirmed in 59 to 238 ms,
averaging 138 ms.
