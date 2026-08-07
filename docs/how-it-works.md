# How the gears work

![Your riding app talks to the iPhone, the iPhone talks to the trainer, and a shift changes the wheel size the trainer is running](how-it-works.svg)

Virtual Gears was built and physically tested with a KICKR V5. Other
direct-drive KICKR models are expected to work but have not yet been physically
tested. It uses a Wahoo command that changes the trainer's idea of your wheel
size: a smaller wheel covers less ground per pedal stroke, which feels like an
easier gear. The riding app's own terrain command is left untouched, so the two
never fight.

Virtual Gears chooses and displays the gear on the iPhone. The riding app sees an
ordinary FTMS trainer and does not need a virtual-shifting feature of its own.

## Where the gears sit

Every gear is scaled away from a 2070 mm reference. The default ladder reaches
about four times easier and 2.3 times harder while keeping gear 12 as the
starting point. A drivetrain too wide to fit is refused at setup rather than
mid-ride.

## When the riding app has its own idea

Wheel size is part of the standard interface available to every riding app.
Whenever one sets it, Virtual Gears honours it: that size becomes the new
reference and every gear is rebuilt around it, so the gear you are in keeps
feeling the way it did. If the gears would no longer fit inside the proven range
around that size, the request is declined and the ride carries on at the size it
already had.

That number belongs to the riding app. Stopping virtual shifting does not stop
that app's ride, so Virtual Gears removes its gear and leaves the trainer on the
riding app's latest size. If the app never set one, the trainer returns to the
2070 mm reference used to build the gears.

## Shifting waits for the trainer

Asking for a gear and getting it are not the same thing. Virtual Gears asks for
the next gear only once the trainer has confirmed the last one, so holding a
shift button sweeps through gears at whatever pace the trainer can really manage
and stops the moment you let go. It cannot run ahead and hand you gears you did
not ask for.

Measured on a Wahoo KICKR V5, a gear change is confirmed in 59 to 238 ms,
averaging 138 ms.
