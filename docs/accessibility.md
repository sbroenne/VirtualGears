# Accessibility

Virtual Gears is designed so the ride can be controlled without having to see
or precisely tap the screen. The on-screen controls remain available even when
optional hardware is disconnected.

## VoiceOver

The current gear is a VoiceOver adjustable control. Focus the gear readout,
then swipe up for a harder gear or down for an easier gear. Virtual Gears
announces a gear only after the trainer confirms it, so the spoken result is
the gear that is actually active.

The two on-screen shift buttons have explicit labels and hints. Their labels
say which direction they shift, and their hints explain that holding the
button continues shifting. Equipment, connection problems, battery warnings
and Bluetooth errors have spoken descriptions rather than relying only on
icons or colour.

## Display and motion

The ride controls use large targets in portrait and landscape. At Accessibility
Dynamic Type sizes, the ride screen uses its vertical layout even when the
phone is sideways so controls have room to reflow instead of being compressed.

Virtual Gears respects the iPhone's Reduce Motion setting for the gear-number
transition. Connection and status states use names and symbols alongside
colour; the gear rail adds an outline when Differentiate Without Color is on.

## Other iPhone accessibility features

The app uses standard SwiftUI buttons, menus, pickers, sliders and navigation
controls. These retain their normal support for Switch Control, Voice Control,
Bold Text, Larger Text and other system accessibility settings.

## Before riding

Try these settings with **Try Demo** before a real ride:

1. Turn on VoiceOver in **Settings > Accessibility > VoiceOver** and adjust
   the simulated gear readout.
2. Choose an Accessibility text size in **Settings > Accessibility > Display &
   Text Size > Larger Text**, then rotate the phone.
3. Turn on **Reduce Motion** and **Differentiate Without Color** in **Settings
   > Accessibility > Display & Text Size**.

Demo Mode does not connect to Bluetooth equipment or control exercise
equipment. It lets you check the interface, not the compatibility of a
particular trainer or accessory.
