# Mac setup

The iPhone app and the hardware proofs must be built and run on macOS.

Riding needs only the `VirtualShift` scheme. The `VirtualShift Hardware Lab`
scheme is a separate app used to prove trainer and controller behaviour, and is
not needed to ride.

The proofs below were run before the proxy existed and are kept as the way to
isolate a fault. Riding itself needs none of them: install the app on the phone
and open it.

1. Install the current stable Xcode release.
2. Sign in to Xcode with the Apple ID used for device development.
3. Clone or copy this repository to the Mac.
4. Run the platform-independent tests:

   ```bash
   swift test
   ```

5. Open `VirtualShift.xcodeproj`.
6. Select the target you want, `VirtualShift` to ride or
   `VirtualShift Hardware Lab` to run the proofs below, open Signing &
   Capabilities, and choose the development team for the connected iPhone.
7. Select the physical iPhone as the run destination and run the app. The
   simulator cannot perform the required hardware proof.

## KICKR V5 range validation

1. Make sure no other phone, watch, computer, or cycling app is connected to
   the KICKR.
2. Open **VirtualShift Hardware Lab**, choose the **KICKR** tab, tap
   **Find my KICKR**, and select the intended trainer.
3. Wait until the app prepares the trainer. It automatically unlocks the KICKR
   and confirms the fixed 2070 mm neutral value.
4. Do not pedal. Tap **Run next check** and wait for the automatic 2070 mm
   restore before continuing.
5. Repeat until all ten values are confirmed. The sequence covers the previously
   tested range, the 646.9–4735.1 mm range the 24 virtual gears need at a
   2070 mm baseline, and a 4800 mm upper safety margin.
6. Tap **Copy test report** and save the complete list and diagnostic log.

Stop immediately if the red neutral-restore warning appears. The app disconnects
instead of issuing another command when the Bluetooth write state is uncertain.
Reconnect before riding so the starting circumference is restored first.

## Original Zwift Click proof

This proof is independent of the KICKR and does not send trainer commands.

1. Open the **Click** tab and press either physical Click button once to wake
   the controller.
2. Tap **Scan for Click**, select the original Zwift Click, and wait for
   **Click ready**.
3. Starting from displayed gear 6, tap `+` and `-`. Each tap must move exactly
   one gear and play the single-shift sound.
4. Hold either button. The display must keep moving while held and stop when
   released, without adding gears afterwards. The sweep runs at the trainer's
   pace, not a fixed rate, so a slow trainer simply sweeps more slowly.
5. Confirm that duplicate packets do not cause extra shifts and pressing both
   buttons does nothing.
6. Disconnect, reconnect, and repeat one tap in each direction.
7. Copy the Click diagnostic log and record the controller firmware and iOS
   version with the result.

## Recording what a Zwift Click really sends

`Tools/ClickTrace` connects a Mac straight to a Click and prints every packet
with the gap since the previous one. Nothing is interpreted, so it answers
questions the app's own logs cannot: by the time the app logs a shift, the press
has already been turned into one.

```bash
./Tools/ClickTrace/run.sh
```

Close VirtualShift on the iPhone first. The Click accepts one connection at a
time, so the phone and the Mac cannot both hold it. Wake the Click by pressing a
button, then allow the Bluetooth prompt the first time.

The tool is wrapped in a small signed app bundle and launched with `open`,
because macOS judges Bluetooth permission by the program that started the
process. Run straight from a terminal, the terminal is judged, and it never
declared that it wants Bluetooth, so the tool is killed the moment it asks.
Output therefore goes to `/tmp/click-trace.log`, which the script tails.

`docs/zwift-click-button-trace.log` is a recording made this way. What it shows:

- The Click streams its button state every 90-120 ms for about 1.3 seconds after
  anything changes, then goes quiet. It does not send an event per press.
- A button reads `0` when pressed and `1` when released.
- A firm press, of the kind used on the bike, lasts about 210 ms. Presses are
  clean: one press and one release each, with no bounce.
- A packet of `19 10 64` arrives every five seconds regardless of the buttons.
  It is the Click reporting its battery: the last byte is a percentage, so
  `64` in hex is 100%. Two independent projects that reverse-engineered these
  controllers, qdomyos-zwift and ajchellew/zwiftplay, both name message type 25
  the battery level message, which matched what the trace showed. The app uses
  this to keep the battery reading current while riding, because the standard
  Bluetooth battery reading is only reliable once, when the Click connects.

That recording is why holding a button now asks for the next gear only once the
trainer has confirmed the last one. Repeats used to be sent on a fixed 300 ms
timer that never waited for the trainer, so a hold could queue gears that kept
arriving after the rider let go.

## Measuring how the trainer itself responds

`Tools/KickrProbe` is a small Mac tool that connects straight to the trainer and
measures two things the app's own logs cannot show:

- how long the trainer takes to confirm a gear change, and
- whether the trainer takes control away when it is told to stop.

It shifts through real gears using the same gear engine the app uses, and it
always puts the wheel size back to 2070 mm before it exits, including after a
failure.

```bash
./Tools/KickrProbe/run.sh
```

Close the iPhone app first and wake the trainer by turning the pedals. A KICKR
accepts only one controlling connection, and the iPhone advertises itself as a
fitness machine too, so the tool picks the trainer by name.

### What a Wahoo KICKR 2A93 measured

Idle, with no riding app connected and nobody pedalling, eight consecutive gear
changes were confirmed in 59 to 238 ms, averaging 138 ms. So on an otherwise
quiet connection the old 300 ms repeat was *not* outrunning the trainer, and the
overshoot a rider sees must also owe something to a busier connection during a
real ride. Waiting for confirmation removes the question entirely: it cannot ask
for a gear the trainer has not yet applied, whatever the connection is doing.

The trainer also kept control through an FTMS Stop: a Wahoo write immediately
afterwards was still accepted. Refusing to re-take control during a stop is
therefore precautionary on this trainer rather than a fix for something it does.

### Why VirtualShift uses Wahoo's command and not the standard one

The Bluetooth fitness-machine standard has a wheel-size command of its own
(opcode `0x12`, in tenths of a millimetre). VirtualShift does not use it on the
trainer. This mode asks the trainer directly:

```bash
./Tools/KickrProbe/run.sh features
```

It reads what the trainer advertises, sends the standard wheel-size command at
the neutral value, and then sends a command the trainer never advertised, to see
whether a "yes" from this trainer means anything at all.

On a Wahoo KICKR 2A93 the answer was that it does not:

| Question | Answer |
| --- | --- |
| Feature bits | `03 40 00 00 0C 60 00 00` |
| Advertises wheel size? | Yes |
| Standard wheel-size command | Accepted (`80 12 01`) |
| Announced the change afterwards? | No |
| A command it never advertised | **Also accepted** (`80 14 01`) |

The last row is the important one. The trainer answered "success" to a target
cadence it does not claim to support, so its acceptance of the wheel-size
command proves nothing. It may work, it may be discarded; the reply cannot tell
them apart, and there is no way to read the wheel size back to check.

Wahoo's own command does not have this problem. It replies with the wheel size
it actually applied, which VirtualShift compares against what it asked for
before reporting the gear as changed. Two further reasons to prefer it:

- It is a **separate channel**. The riding app's terrain commands occupy the
  standard control point, which carries one request at a time. Gear changes on
  their own characteristic never queue behind them.
- It is the route that has been **proven on hardware**, across ten wheel sizes
  from 647 mm to 4800 mm and timed at 59 to 238 ms per change.

This mode changes nothing and leaves the trainer on 2070 mm.

## Independent riding app FTMS probe

This probe makes the iPhone pretend to be a simple indoor bike. Do not connect
the Hardware Lab to the KICKR during this test. Run it with whichever riding app
you are validating; RealVelo is the reference app, and Zwift, FulGaz, and other
FTMS apps use the same interface.

1. Open the **Riding App** tab and enter the riding app and Windows versions.
2. Tap **Start Probe** and keep the Hardware Lab open in the foreground.
3. In the riding app, search for a Bluetooth FTMS trainer named
   **VirtualShift Lab** and connect to it.
4. Confirm that the app shows the fixed speed, cadence, and power values. Move
   each slider in the Hardware Lab and confirm that the app follows it.
5. Exercise the app's normal start, pause, stop, ERG, resistance, simulation,
   and wheel-circumference controls.
6. In the trace, confirm that the app subscribed to the Control Point before
   requesting control. Record the exact order and raw bytes for every write.
7. Disconnect and reconnect the app once. Confirm that it can find the probe
   again and repeats the required subscriptions and control request.
8. Tap **Export JSON Trace** and save the complete trace with the test result.
9. Tap **Stop Probe** when finished.

If the riding app cannot discover the foreground iPhone, do not guess at a proxy
workaround. Save the trace and record the failure before changing the FTMS
service shape.

Both probes passed before the proxy was built, and the proxy is now the product.
Keep them as the way to isolate a fault: if a riding app stops seeing
VirtualShift, prove the FTMS shape here first rather than changing the proxy on
a hunch.

## What name a riding app shows for VirtualShift

A rider reported that MyWhoosh listed VirtualShift as "iPhone sbroenne 17 D345"
rather than "VirtualShift". A name can reach a riding app by two routes, so
`Tools/NameScan` reads both and tells them apart:

```
./Tools/NameScan/run.sh
```

Start a ride on the phone while it runs. Measured on 2026-08-05:

```
Found a fitness machine at -55 dBm.
  In the advertisement: local name "VirtualShift"; services 1826
  CBPeripheral.name reads: iPhone sbroenne 17
```

So the advertisement is correct and this is not an app bug. The second name is
the GAP Device Name (0x2A00), which iOS fixes to the name of the phone; an app
cannot publish its own 0x1800 service to override it. A riding app that reads
that instead of the advertised local name will always show the phone.

There is no code fix. The ride screen now names both possibilities while
waiting to be found, and `docs/requirements.md` explains it. A rider who
minds can rename the phone in Settings.

Note that macOS keeps 0x1800 to itself, so the tool cannot read 0x2A00
directly; `CBPeripheral.name` showing the phone's name is the evidence that
the device name is what reaches a central.
