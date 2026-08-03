# Mac setup

The iPhone application and KICKR V5 proof must be created and run on macOS.

1. Install the current stable Xcode release.
2. Sign in to Xcode with the Apple ID used for device development.
3. Clone or copy this repository to the Mac.
4. Run the platform-independent tests:

   ```bash
   swift test
   ```

5. Create an iOS SwiftUI application target named `VirtualShift` in this
   repository and add `VirtualShiftCore` as a local package dependency.
6. Enable the `bluetooth-central` and `bluetooth-peripheral` background modes.
7. Add Bluetooth usage descriptions to the application target.
8. Run the first build on the physical iPhone; the simulator cannot perform
   the required KICKR/FTMS hardware proof.

Do not build the full proxy before the two proof gates in the README pass.
