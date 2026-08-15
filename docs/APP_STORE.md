# Putting Virtual Gears on the App Store

Everything Apple will ask you for, written out so you can copy and paste it.
Work top to bottom.

---

## Stage 1 — Join the Apple Developer Program

<https://developer.apple.com/programs/enroll/>

- $99 a year, renews automatically.
- Enrol as an **individual** unless you want the app published under a company name;
  a company enrolment needs a D-U-N-S number and takes much longer.
- Apple usually approves within 24–48 hours. Everything below is blocked until then.

Once approved, open Xcode → Settings → Accounts and sign in with the same Apple ID.
Xcode creates the distribution certificate for you the first time you upload.

## Stage 2 — Publish the privacy policy page

Apple requires a public web address for a privacy policy, even for an app that
collects nothing.

This is already done. The policy is published as part of the project website:

    https://sbroenne.github.io/VirtualGears/PRIVACY/

The site is built from `docs/` by `.github/workflows/docs.yml` and republishes
itself whenever `main` changes, so the policy cannot drift out of date.

## Stage 3 — Create the app record

<https://appstoreconnect.apple.com> → Apps → **+** → New App.

| Field | Value |
|---|---|
| Platform | iOS |
| Name | `Virtual Gears` |
| Primary language | English (U.S.) |
| Bundle ID | `com.sbroenne.VirtualGears` |
| SKU | `virtualgears-001` (any private string; never shown to anyone) |
| User access | Full Access |

Apple accepted `Virtual Gears` as the public name. The app uses the same name on
the iPhone and when advertising itself as a trainer.

## Stage 4 — Fill in the listing

### Subtitle (30 characters max)

    Virtual shifting for KICKR

### Promotional text (170 characters max, editable any time without review)

    Give your Wahoo KICKR virtual gears in compatible FTMS riding apps. Shift on your iPhone with 24 virtual gears or your real-bike gearing.

### Description

    Your trainer has no gears. Your riding app may not offer virtual shifting.
    Virtual Gears fixes both.

    Newer trainers gained virtual shifting in 2024. The Wahoo KICKR V5 did not, and
    Wahoo has confirmed it never will — the older hardware cannot support it. Many
    riding apps do not provide virtual shifting either.

    Virtual Gears was built and physically tested with a KICKR V5. Other direct-drive
    KICKR models are expected to work but have not yet been physically tested. KICKR
    SNAP and KICKR BIKE are not supported.

    Virtual Gears sits between both. It appears to compatible riding apps as a normal
    FTMS trainer, so they need no special virtual-shifting support. Your riding app still
    controls the route and its hills; Virtual Gears adds the gears.

    NOT ZWIFT-NATIVE VIRTUAL SHIFTING
    Virtual Gears supplies and displays its own gears on the iPhone through an ordinary
    FTMS trainer connection; it does not support Zwift's native gear system.

    You get a full set of gears you can shift through mid-ride — either 24 evenly
    spaced gears with an extra-low climbing range or an exact copy of the gears on
    your real bike.

    NOTHING TO SET UP
    Open the app and it finds your trainer, connects to it and appears to your
    riding app. Tap Start Shifting when you want it to put your gears on. Optional original Zwift Click and
    Wahoo Headwind accessories are found and remembered automatically too. If more than
    one matching device is found, Virtual Gears asks rather than guessing. If Clicks have
    identical names, pressing a button identifies the one you want.

    GEARS YOU CAN SEE
    Your gears are drawn, not listed as numbers — one bar per gear, short bars for
    small steps and tall bars for the ones your legs will notice. Choose the 24
    virtual gears, or pick your real chainrings and cassette and get exactly the gears
    you would actually ride. Cross-chained and duplicate combinations are left out.

    BUILT FOR RIDING, NOT FOR READING
    Two large shift buttons stay easy to hit without looking down or sitting up,
    while the current gear is the biggest thing on screen. Hold one to keep shifting.
    The screen stays awake for the whole ride.

    ACCESSIBLE RIDE CONTROLS
    VoiceOver reads the current gear and announces confirmed changes. The gear readout
    is adjustable with VoiceOver gestures: swipe up for a harder gear and down for an
    easier one. The app uses standard iPhone controls and respects larger text, Reduce
    Motion and Differentiate Without Color.

    TRY IT WITHOUT A TRAINER
    Tap Try Demo for a clearly marked simulated ride without Bluetooth. Shift through
    the gear ladder and watch the trainer's wheel size change with every gear. Compare
    virtual and real-bike gearing, and try example Click, Headwind and riding-app
    controls. Demo choices never replace saved equipment.

    WORKS WITH THE APPS YOU ALREADY USE
    Virtual Gears appears as an ordinary FTMS indoor trainer. That adds virtual shifting
    to compatible apps that have none of their own, without requiring a plugin or
    account. Apps that set their own wheel size are honoured — the gears are rebuilt
    around whatever size the app asks for.

    OPTIONAL SHIFT BUTTONS
    Wake an original Zwift Click before opening Virtual Gears and it connects
    automatically. It shifts alongside the on-screen buttons and visibly presses
    the matching control, but is never required.

    OPTIONAL HEADWIND CONTROL
    Turn on a Wahoo KICKR HEADWIND before opening Virtual Gears and it connects
    automatically. Leave fan speed with the Headwind's own sensor, or choose a manual
    speed from the ride screen. The fan is optional and never blocks a ride.

    CAREFUL WITH YOUR TRAINER
    A gear is only shown after your trainer confirms it. Every gear stays inside a
    range tested on a real trainer.

    NOT AN ERG APP
    Workouts that set a target power are refused. Virtual Gears controls how hard a
    gear feels, not your wattage.

    NOTE ON WHEEL CIRCUMFERENCE
    Making gears overwrites any custom wheel circumference you set in the Wahoo app.
    Virtual Gears cannot read that value back, so write it down and set it again
    afterwards if you use one. Most riders never change this setting.

    NO ACCOUNTS, NO INTERNET, NO TRACKING
    The app has no networking code in it at all. Nothing about your ride leaves your
    iPhone.

    Requires a compatible Wahoo KICKR. Built and physically tested with KICKR V5.
    Virtual Gears is not made by, endorsed by or affiliated with Wahoo Fitness.

### Keywords (100 characters max, comma separated, no spaces)

    trainer,gears,shifting,cycling,indoor,bike,turbo,gearing,shifter,virtual,kickr,ride

### URLs

- Support URL: `https://sbroenne.github.io/VirtualGears/support/`
- Marketing URL: `https://sbroenne.github.io/VirtualGears/`
- Privacy Policy URL: `https://sbroenne.github.io/VirtualGears/PRIVACY/`

Support runs on the public GitHub repository: [Q&A discussions][supportqa] for
questions and [Issues][supportissues] for bugs. The support page linked above
routes users to the right one and answers the common problems first, so a
reviewer or a rider without a GitHub account still gets a useful page. Both
Issues and Discussions must stay enabled on the repository.

  [supportqa]: https://github.com/sbroenne/VirtualGears/discussions/categories/q-a
  [supportissues]: https://github.com/sbroenne/VirtualGears/issues

### Category and rating

- Primary category: **Health & Fitness**
- Secondary category: **Sports**
- Age rating: answer "None" to every question → **4+**

### Screenshots

Required: **6.9-inch iPhone**. The six portrait images in `docs/screenshots/`
are 1320 × 2868, captured on an iPhone 17 Pro Max simulator, so they can be
uploaded as they are. Apple scales them down for smaller phones; one set is
enough. The two landscape images are 2868 × 1320 documentation views; they are
not part of the portrait upload set below.

Upload these six, in this order:

1. `riding.png` — the ride screen, which is what the app is for.
2. `gears.png` — the 24 virtual gears drawn as bars.
3. `gears-real-bike.png` — a real 50/34 with 11-34 turned into sixteen gears.
4. `headwind-control.png` — optional Automatic/Manual Headwind control with
   one-tap speeds.
5. `starting.png` — automatic reconnect plus the Bluetooth-free Try Demo entry.
6. `settings.png` — the three remembered equipment rows and gear choice.

### Privacy answers ("App Privacy" section)

Answer **"No, we do not collect data from this app."** That is accurate: nothing is
collected and there is no networking code. This matches `PrivacyInfo.xcprivacy` in
the app.

## Stage 5 — Upload the build

In Xcode:

1. Choose **Any iOS Device** as the destination (not a simulator).
2. Product → **Archive**.
3. When the Organizer opens: **Distribute App** → **App Store Connect** → **Upload**.
4. Accept the automatic signing offers.

The build appears in App Store Connect after 5–15 minutes of processing. Attach it
to the version, then **Add for Review** → **Submit**.

## Stage 6 — The review notes (do not skip this)

The reviewer does not need a smart trainer to inspect the app. Paste this into
**App Review Information → Notes**:

    This app controls a compatible Wahoo KICKR indoor bicycle trainer over Bluetooth.
    It was built and physically tested with a KICKR V5.

    No hardware is required for review. On the first screen, tap "Try Demo". A blue
    "Demo Mode · Simulated" notice confirms that no trainer is connected and Bluetooth
    is not being used. The demo provides the production gear picker, visible gear
    ladder, large Easier and Harder controls, virtual and real-bike gearing choices,
    Settings, simulated trainer/Click/Headwind/riding-app status, and simulated
    Headwind controls. Tap "Exit Demo" to return to real trainer discovery.

    Demo Mode uses local in-memory state only. It does not scan, advertise, connect or
    send Bluetooth commands, and its choices do not replace saved equipment. The demo
    shows the app's interface and local gearing behavior; it is not a claim that
    simulated accessories prove physical compatibility.

    How it works: the iPhone connects to the trainer as a Bluetooth client, and at the
    same time presents itself as a standard FTMS indoor trainer to a riding app on a
    computer. It passes the riding app's resistance instructions through to the
    trainer and relays the trainer's data back, while applying the rider's chosen gear
    by rescaling the trainer's wheel-circumference setting. This is what produces the
    virtual gears.

    Virtual Gears supplies and displays these gears itself over ordinary FTMS. It does
    not support Zwift-native virtual shifting.

    A Wahoo KICKR HEADWIND fan can optionally be paired for sensor or manual speed
    control. It is not required to review the trainer and virtual-shifting features.

    No account, no login, no server. The app contains no networking code.

    Bluetooth background mode is used because a ride is a continuous Bluetooth session
    that must survive an incoming call or a notification. Losing it mid-ride would
    disconnect the rider's trainer.

`DEMO_VIDEO.md` remains an optional script for recording additional physical
hardware evidence. A video link is not required for the reviewer to navigate the
app because Demo Mode covers the reviewable interface without equipment.

## Likely rejection reasons, and what to say

| Reason | Response |
|---|---|
| "We were unable to review because we don't have the hardware" | Point to **Try Demo** on the first screen and repeat the review steps above. A physical-hardware video can be supplied later as supporting evidence, but is not required to navigate the app. |
| Trademark concern over "KICKR" or "Wahoo" | The app name and subtitle contain no third-party brand. The description names the required hardware factually and states plainly that there is no affiliation, which is permitted. |
| Bluetooth background mode questioned | Answer as in the notes: the ride is a live session that must survive interruptions. |
| Safety of controlling exercise equipment | The app cannot change resistance beyond what the riding app already asks for; it only rescales a wheel-size setting within a range verified on real hardware, and shows a gear only after the trainer confirms it. |

## Later versions

For each update, raise `MARKETING_VERSION` (1.0 → 1.1) and
`CURRENT_PROJECT_VERSION` in the Xcode target's Build Settings, then archive and
upload again. `CURRENT_PROJECT_VERSION` must increase on every single upload, even
a re-upload of the same version.

The current TestFlight build is 1.0 (8). Build 5 added the Demo Mode that shows
the wheel size and command bytes changing. Build 6 removed a wheel-size limit
that was never real: a physical KICKR V5 accepts every value the command can
express, so the app now states the range of riding-app wheel sizes it supports
instead of guessing at a trainer limit. It also stopped describing itself to
riders as starting a session, because it does not — it puts their gears on.
Build 7 mirrors an accepted Zwift Click press on the matching on-screen shift
button while keeping the gear number and haptic tied to trainer confirmation.
Build 8 restores the explicit Start Shifting step while making the transparent
trainer proxy available as soon as the KICKR is ready, and keeps every configured
equipment status visible on the shifting screen.

Source build 1.0 (9) has not yet been uploaded. It fixes the case where a riding
app waiting to connect replaced the KICKR, Click and fan statuses; each connection
now keeps its own status. It also adds adaptive status layout for
Accessibility Dynamic Type, clearer startup/status/gear/demo wording, and
deterministic UI coverage for failure, reconnect, waiting, low-battery,
pending-shift and physical-press states. It moves the ride status out of the
title bar, where it was squeezed until only a wordless warning icon remained, to
a legible line beside the gear, and gives the stop confirmation a visible Cancel
so a rider is never shown a destructive choice with no way out. The ride screen
was then reworked around what only it can show: the position rail fills in the
gears already ridden through so a position can be seen instead of counted, the
line under the gear became a caption rather than a rival to it, easier and harder
are told apart by weight as well as by symbol, every equipment status sits on one
row, and a low Click battery is drawn as a warning. Settings stopped saying
"Zwift Click" twice in one row, the gears row leads with the gears chosen rather
than a count of them, cassettes that share a name are told apart by their cog
count, and retrying a failed start says "Try Again".

The live App Store description still carries the old "starts the session"
sentence. It is corrected in this file and needs the same edit in App Store
Connect on the next metadata change.

Uploading without opening Xcode:

```sh
xcodebuild -project VirtualGears.xcodeproj -scheme VirtualGears \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath /tmp/VG.xcarchive archive
xcodebuild -exportArchive -archivePath /tmp/VG.xcarchive \
  -exportOptionsPlist TestFlightExportOptions.plist -exportPath /tmp/VGexport
```

The export options plist needs `destination: upload` and
`method: app-store-connect`. Signing is automatic and uses the Apple ID already
signed in to Xcode.
