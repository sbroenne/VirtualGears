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

## KICKR V5 proof procedure

1. Make sure no other phone, watch, computer, or cycling app is connected to
   the KICKR.
2. Open VirtualShift, tap **Scan for KICKR**, and select the intended trainer.
3. Enter the wheel circumference currently configured for the trainer and tap
   **Confirm starting value**. The field starts at 2070 mm, but do not assume
   that value is correct for the user's setup.
4. Wait until the app says **Ready for proof commands**. This means the unlock
   and initial restore of the confirmed starting value both received matching
   replies from the KICKR.
5. Record the exact KICKR model and firmware in the app.
6. While pedalling steadily, send the value 500 mm lower, the confirmed starting
   value, and the value 500 mm higher one at a time. Wait for **KICKR verified**
   in the log for each command, hold cadence as steady as possible, and compare
   the live watt reading. Record whether resistance changes in the expected
   easier/baseline/harder direction.
7. Capture any notification shown in the diagnostic log.
8. Tap **Stop and restore**. Do not close the app until the log says the
   starting value was restored and the trainer disconnected safely.
9. Reconnect once. Confirm that the app restores the same starting value before
   enabling the test buttons, then stop safely again.
10. Tap **Copy result summary** and add it to issue #1 with the exact iOS
   version, discovered UUID and properties, command results, notifications,
   physical resistance result, and restoration result.

If a write fails, the expected control characteristic is missing, physical
resistance does not change, or the restore warning appears, stop the proof and
record that result. Do not proceed with the full proxy.

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

Do not build the full proxy before the two proof gates in the README pass.
