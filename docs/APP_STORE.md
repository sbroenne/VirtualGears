# Putting VirtualShift on the App Store

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

    https://sbroenne.github.io/VirtualShift/PRIVACY/

The site is built from `docs/` by `.github/workflows/docs.yml` and republishes
itself whenever `main` changes, so the policy cannot drift out of date.

## Stage 3 — Create the app record

<https://appstoreconnect.apple.com> → Apps → **+** → New App.

| Field | Value |
|---|---|
| Platform | iOS |
| Name | `VirtualShift` |
| Primary language | English (U.S.) |
| Bundle ID | `com.sbroenne.VirtualShift` |
| SKU | `virtualshift-001` (any private string; never shown to anyone) |
| User access | Full Access |

If the name `VirtualShift` is taken, App Store Connect says so immediately. A
fallback such as `VirtualShift Gears` keeps the app's own name intact.

## Stage 4 — Fill in the listing

### Subtitle (30 characters max)

    Gears for your smart trainer

### Promotional text (170 characters max, editable any time without review)

    Adds 24 virtual gears to a Wahoo KICKR V5 — the trainer Wahoo confirmed will never get virtual shifting of its own. Open the app and ride.

### Description

    Your smart trainer has no gears. VirtualShift gives it some.

    Newer trainers gained virtual shifting in 2024. The Wahoo KICKR V5 did not, and
    Wahoo has confirmed it never will — the older hardware cannot support it. This app
    gives a KICKR V5 gears anyway, in whichever app you ride with.

    Sit the app between your iPhone and the app you ride with on your computer, and
    you get a full set of gears you can shift through mid-ride — either the 24 evenly
    spaced virtual gears used by indoor riding apps, or an exact copy of the gears on
    your real bike.

    NOTHING TO SET UP
    Open the app and it starts. It finds your trainer, connects to it, starts the
    session and appears to your riding app on its own. If more than one trainer is
    nearby it asks which is yours, because connecting to your neighbour's trainer
    would change their settings, not yours.

    GEARS YOU CAN SEE
    Your gears are drawn, not listed as numbers — one bar per gear, short bars for
    small steps and tall bars for the ones your legs will notice. Choose the 24
    virtual gears, or pick your real chainrings and cassette and get exactly the gears
    you would actually ride. Cross-chained and duplicate combinations are left out.

    BUILT FOR RIDING, NOT FOR READING
    Two shift buttons fill most of the screen, so you can hit them without looking
    down or sitting up. Hold one to keep shifting. The screen stays awake for the
    whole ride.

    WORKS WITH THE APPS YOU ALREADY USE
    VirtualShift appears as an ordinary indoor trainer, so any app that pairs with a
    standard trainer can use it. Apps that set their own wheel size are honoured — the
    gears are rebuilt around whatever size the app asks for.

    OPTIONAL SHIFT BUTTONS
    If you have a handlebar shift controller, VirtualShift will use it alongside the
    on-screen buttons. It is never required and the app never waits for it.

    CAREFUL WITH YOUR TRAINER
    A gear is only shown after your trainer confirms it. Every gear stays inside a
    range tested on a real trainer. When you stop, your trainer is put back exactly
    as it was found, and the app tells you if anything could not be restored.

    NO ACCOUNTS, NO INTERNET, NO TRACKING
    The app has no networking code in it at all. Nothing about your ride leaves your
    iPhone.

    Requires a Wahoo KICKR V5. VirtualShift is not made by, endorsed by or affiliated
    with Wahoo Fitness.

### Keywords (100 characters max, comma separated, no spaces)

    trainer,gears,shifting,cycling,indoor,bike,turbo,gearing,shifter,virtual,kickr,ride

### URLs

- Support URL: `https://github.com/sbroenne/VirtualShift/issues`
- Marketing URL: `https://sbroenne.github.io/VirtualShift/`
- Privacy Policy URL: `https://sbroenne.github.io/VirtualShift/PRIVACY/`

### Category and rating

- Primary category: **Health & Fitness**
- Secondary category: **Sports**
- Age rating: answer "None" to every question → **4+**

### Screenshots

Required: **6.9-inch iPhone**. All five images in `docs/screenshots/` are already
1320 × 2868, captured on an iPhone 17 Pro Max simulator, so they can be uploaded as
they are. Apple scales them down for smaller phones; one set is enough.

Upload these three, in this order:

1. `riding.png` — the ride screen, which is what the app is for.
2. `gears.png` — the 24 virtual gears drawn as bars.
3. `gears-real-bike.png` — a real 50/34 with 11-34 turned into sixteen gears.

Do **not** upload `settings.png` or `starting.png` as they stand. Both were captured
with no trainer present, so one shows an orange "your trainer is not connected"
warning and the other shows an endless "Looking for your trainer" spinner. Accurate
for the documentation, a poor advertisement.

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

The reviewer will not have a smart trainer. Without one the app shows "Looking for
your trainer" and nothing else, and the review will be rejected as untestable unless
you explain it. Paste this into **App Review Information → Notes**:

    This app controls a Wahoo KICKR V5 indoor bicycle trainer over Bluetooth. Without
    that hardware present the app stays on its "looking for your trainer" screen,
    because there is nothing for it to connect to.

    A video showing the full app in use on real hardware is here: <ADD LINK>

    How it works: the iPhone connects to the trainer as a Bluetooth client, and at the
    same time presents itself as a standard FTMS indoor trainer to a riding app on a
    computer. It passes the riding app's resistance instructions through to the
    trainer and relays the trainer's data back, while applying the rider's chosen gear
    by rescaling the trainer's wheel-circumference setting. This is what produces the
    virtual gears.

    No account, no login, no server. The app contains no networking code.

    Bluetooth background mode is used because a ride is a continuous Bluetooth session
    that must survive an incoming call or a notification. Losing it mid-ride would
    disconnect the rider's trainer.

**Record the video before you submit.** `DEMO_VIDEO.md` in this folder is a
shot-by-shot script for it, including what to say, what the reviewer specifically
needs to see, and where to host the file so it opens without an account.

## Likely rejection reasons, and what to say

| Reason | Response |
|---|---|
| "We were unable to review because we don't have the hardware" | The notes and video above. If it happens anyway, reply in Resolution Center with the video timestamped. |
| Trademark concern over "KICKR" or "Wahoo" | The app name and subtitle contain no third-party brand. The description names the required hardware factually and states plainly that there is no affiliation, which is permitted. |
| Bluetooth background mode questioned | Answer as in the notes: the ride is a live session that must survive interruptions. |
| Safety of controlling exercise equipment | The app cannot change resistance beyond what the riding app already asks for; it only rescales a wheel-size setting within a range verified on real hardware, and restores it when the ride ends. |

## Later versions

For each update, raise `MARKETING_VERSION` (1.0 → 1.1) and `CURRENT_PROJECT_VERSION`
(1 → 2) in the Xcode target's Build Settings, then archive and upload again.
`CURRENT_PROJECT_VERSION` must increase on every single upload, even a re-upload of
the same version.
