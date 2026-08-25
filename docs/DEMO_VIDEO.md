# Recording the demo video

Apple asked for this recording. It is not optional.

The first submission of 1.0 (build 5) was rejected on 14 August 2026 under
**Guideline 2.1 — Information Needed**, and the first thing App Review asked for
was "a screen recording captured on a physical device, running the latest
operating system, demonstrating the app's functionality". Demo Mode lets a
reviewer navigate the product without a trainer, but it did not spare us the
recording. Nothing can be resubmitted until this exists.

Aim for **two minutes**. Longer and the reviewer stops watching.

!!! warning "Simulation is not hardware evidence"

    Demo Mode and the website animation can show screens and local gear behavior.
    Only footage of a physical ride can add evidence that the app drives the
    named hardware. Never present the simulation as that evidence.

## What Apple specifically requires

Their wording, and what it means here:

- **It must start with launching the app.** Begin recording on the Home screen
  and tap the icon. Do not join a session already running.
- **It must be a physical device on the latest OS.** An iPhone 17 Pro on iOS 26.6
  is what the app is tested on.
- **It must show the typical user flow through the core features.** For this app
  that is: connect to the trainer, appear to a riding app, and shift gears.
- **It must include any prompt asking for sensitive data or device
  capabilities.** Virtual Gears asks for Bluetooth, and that is the only prompt
  it ever shows. iOS only asks once per install, so the app has to be deleted
  and reinstalled before recording — see below.

The remaining items in their list — account registration, purchases,
user-generated content — do not exist in this app. There is nothing to film.

## Before you start

**Delete the app from the phone first.** Deleting it takes its Bluetooth
permission with it, so the prompt appears again on the next launch, and the app
starts with no remembered trainer — exactly what an App Review device sees.
Then install the latest TestFlight build, currently 1.0 (18), but **do not open
it**. The
recording has to start from the Home screen.

Also:

- Trainer plugged in and awake. Turn the pedals once to wake it. You do not need
  to ride: the trainer confirms a gear change whether or not you are pedalling.
- iPhone in Do Not Disturb, screen brightness up, battery over 50%.
- If you have a Zwift Click, fit it and switch it on.
- Riding app open on the computer only if you want the optional act 4.

Record the phone with **iOS screen recording** (Control Centre → the record
button), not a camera pointed at the screen. For the chain shot, record that
separately on a camera and cut it in.

!!! tip "Turn the microphone on"

    Hold the screen-record button and switch the microphone on, then narrate as
    you go. Spoken explanation is far more convincing to a reviewer than
    captions, and it takes no editing.

## The shot list

### Act 1 — launch and connect (required by Apple)

| # | Shot | What to say |
|---|---|---|
| 1 | Home screen, tap Virtual Gears | "This is Virtual Gears. It gives an indoor trainer gears it doesn't have." |
| 2 | The Bluetooth permission prompt appears. Allow it. | "It asks for Bluetooth, because that's how it reaches the trainer. That's the only permission it ever asks for." |
| 3 | The app finds and connects to the trainer on its own | "It finds my Wahoo KICKR and connects by itself. There's nothing to set up." |

### Act 2 — the core feature, on the real trainer

No pedalling needed. The trainer acknowledges each gear either way.

| # | Shot | What to say |
|---|---|---|
| 4 | Tap Harder four or five times, slowly enough that each number lands | "Shifting. Each gear resizes the trainer's wheel, and the trainer confirms it before the number changes." |
| 5 | Tap Easier back down again | "And back down. My chain hasn't moved once." |
| 6 | With a Zwift Click: shift with the handlebar buttons, then hold one down | "The same gears from a shifter on the handlebar. Holding it sweeps through them." |
| 7 | Camera shot of the bike: the chain, unmoving, in one gear | "The chain stays where it is. No shifting noise, no wear." |
| 8 | Stop shifting | "Stopping removes the virtual gear and restores the normal wheel size. The riding app stays connected." |

### Act 3 — how a reviewer tests it with no hardware

This is the part that matters for App Review, because they have no trainer.

| # | Shot | What to say |
|---|---|---|
| 9 | On the first screen, tap **Try Demo** | "Nobody reviewing this will have a trainer, so the app ships a demo. It's on the first screen." |
| 10 | The Demo Mode banner | "It says plainly that it's simulated and uses no Bluetooth." |
| 11 | Shift Easier and Harder a few times | "This is the real gear engine. The wheel sizes and the command bytes on screen are the exact ones the app just sent to the trainer — only the radio is simulated." |
| 12 | Open the gears screen, switch to a real-bike drivetrain, come back | "24 virtual gears, or describe a real bike and ride its gears instead." |
| 13 | Open Settings, then Exit Demo | "Everything else in the app is reachable from here too." |

### Act 4 — the riding app (optional, only if one is running)

| # | Shot | What to say |
|---|---|---|
| 14 | Cut to the computer: the riding app's pairing list, with the iPhone offered as a trainer. Pair it. | "On the computer, my riding app sees the iPhone as a standard trainer and pairs with it." |

## What the video must make unmistakable

Three things, or it will not do its job:

1. **It starts on the Home screen** and the Bluetooth prompt is on camera.
   Apple asked for both in as many words.
2. **The real trainer confirms a shift** (act 2), with the gear number visible.
   This is the app doing its actual job on real hardware.
3. **Try Demo is reachable from the first screen** (act 3). This is the answer
   to "how do we review an app that needs a trainer we don't have?"

## Where to put the file

Export as **MP4, 1080p**, and keep it under 100 MB.

Do not commit it to the repository — a video in git stays in the history
forever and makes every clone slow. Instead:

1. Create a release on GitHub tagged `demo`.
2. Attach the MP4 to it as a release asset.
3. The public link is then
   `https://github.com/sbroenne/VirtualGears/releases/download/demo/virtual-gears-demo.mp4`

That link needs no account to open.

Then:

- Add a video block to `docs/demo.md` if the recording should play on the website.

## Replying to App Review

Attach the MP4 to the reply itself in App Store Connect → App Review → the
rejected submission → **Reply to App Review**. A link is second best; give them
the file if it is under Apple's attachment limit, and the GitHub link as well so
they have both.

The seven answers App Review asked for are already saved in **App Review
Information → Notes**, so the reply only has to point at them and carry the
video:

> Thank you. A screen recording made on a physical iPhone 17 Pro running iOS 26.6
> is attached. It starts by launching the app from the Home screen, shows the
> Bluetooth permission prompt, the app finding and connecting to a Wahoo KICKR V5
> trainer on its own, gears being shifted on that trainer with each change
> confirmed by the trainer before it appears on screen, and shifting being
> stopped cleanly at the end, which returns the trainer's wheel size to where it
> was.
>
> The recording then shows Demo Mode, which is how the app can be reviewed
> without a trainer. Demo Mode is reached with the "Try Demo" button on the first
> screen. It runs the shipping gear engine, the shipping command encoder and the
> shipping response decoder, so the wheel sizes and command bytes it displays are
> the real ones; only the Bluetooth radio is simulated, and the screen says so.
> No hardware, account or sample file is needed to use it.
>
> The app has no account registration, login, account deletion, paid content,
> purchases, subscriptions or user-generated content, so there are none of those
> flows to record. Bluetooth is the only permission it ever requests.
>
> Full answers to your points 2 to 7 are in the App Review Information Notes
> field, which has been updated. In short: tested on iPhone 17 Pro with iOS 26.6,
> against a Wahoo KICKR V5 trainer, an original Zwift Click and a Wahoo KICKR
> HEADWIND, driven end to end by FulGaz on macOS and Windows, plus RealVelo and
> MyWhoosh on Windows. The app
> uses no external services and contains no networking code. It behaves
> identically in every region. It is not a regulated industry and includes no
> protected third-party material; it speaks the public Bluetooth SIG Fitness
> Machine Service standard, and names hardware only to say what it works with.
>
> No hardware is needed to review the app: tap "Try Demo" on the first screen.

Attach build 1.0 (18), not the rejected 1.0 (5), to the version before
resubmitting.
