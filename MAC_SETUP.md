# Mac setup

The iPhone application and KICKR V5 proof must be created and run on macOS.

1. Install the current stable Xcode release.
2. Sign in to Xcode with the Apple ID used for device development.
3. Clone or copy this repository to the Mac.
4. Run the platform-independent tests:

   ```bash
   swift test
   ```

5. Open `VirtualShift.xcodeproj`.
6. Select the `VirtualShift Hardware Lab` target, open Signing & Capabilities,
   and choose the development team for the connected iPhone.
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
   tested range, the exact 646.9–4735.1 mm range required by the default
   24-speed profile at a 2070 mm baseline, and a 4800 mm upper safety margin.
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
4. Hold either button. After 500 ms, the display must continue moving one gear
   every 300 ms and play the multi-shift sound until released or gear 1/12.
5. Confirm that duplicate packets do not cause extra shifts and pressing both
   buttons does nothing.
6. Disconnect, reconnect, and repeat one tap in each direction.
7. Copy the Click diagnostic log and record the controller firmware and iOS
   version with the result.

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

Do not build the full proxy before the isolated riding app and KICKR FTMS probes
pass.
