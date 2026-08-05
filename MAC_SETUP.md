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
timer, which is quicker than the trainer can confirm a shift, so a hold queued
gears that kept arriving after the rider let go.

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
