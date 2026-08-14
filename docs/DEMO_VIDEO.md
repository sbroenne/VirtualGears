# Recording the demo video

Apple asked for this recording. It is not optional.

The first submission of 1.0 (build 5) was rejected on 14 August 2026 under
**Guideline 2.1 — Information Needed**, and the first thing App Review asked for
was "a screen recording captured on a physical device, running the latest
operating system, demonstrating the app's functionality". Demo Mode lets a
reviewer navigate the product without a trainer, but it did not spare us the
recording. Nothing can be resubmitted until this exists.

Aim for **90 seconds**. Longer and the reviewer stops watching.

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
  capabilities.** Virtual Gears asks for Bluetooth. Record on a phone that has
  not granted it yet, or reset it first with Settings → General → Transfer or
  Reset iPhone → Reset → Reset Location & Privacy, so the Bluetooth prompt
  appears on camera.

The remaining items in their list — account registration, purchases,
user-generated content — do not exist in this app. There is nothing to film.

## Before you start

- Bike on the trainer, trainer plugged in and awake.
- Riding app open on the computer, not yet paired.
- iPhone in Do Not Disturb, screen brightness up, battery over 50%.
- If you have a Zwift Click, fit it. If not, skip shots 7 and 8.

Record the phone with **iOS screen recording** (Control Centre → the record
button), not a camera pointed at the screen. For the two shots that need the
bike in frame, record those separately on a second phone or a camera and cut
them in.

!!! tip "Turn the microphone on"

    Hold the screen-record button and switch the microphone on, then narrate as
    you go. Spoken explanation is far more convincing to a reviewer than
    captions, and it takes no editing.

## The shot list

| # | Shot | What to say |
|---|---|---|
| 1 | Home screen, tap Virtual Gears | "This is Virtual Gears. It gives an indoor trainer gears it doesn't have." |
| 2 | The Bluetooth permission prompt appears. Allow it. | "It asks for Bluetooth, because that is how it reaches the trainer. That is the only permission it ever asks for." |
| 3 | The app finds and connects to the trainer on its own | "It finds my trainer and connects by itself. There's nothing to set up." |
| 4 | Cut to the computer: the riding app's pairing list, showing the iPhone offered as a trainer. Pair it. | "On the computer, my riding app sees the iPhone as a trainer, and pairs with it." |
| 5 | Back to the phone: the ride screen, power and cadence moving as you pedal | "Now I'm riding. Power and cadence come from the trainer, through the phone, to the riding app." |
| 6 | Pedal steadily, tap the harder button four or five times. Let the number change be visible. | "Shifting up. The trainer gets harder, and my chain hasn't moved." |
| 7 | Same again with the Zwift Click, if you have one | "The same gears, from a shifter on the handlebar." |
| 8 | Hold the Click button down, then let go | "Holding it sweeps through the gears and stops when I let go." |
| 9 | Camera shot of the bike: point at the chain, unmoving, in one gear | "The chain stays where it is all ride. No noise, no wear." |
| 10 | Phone: open the gears screen, switch to a real bike drivetrain | "I can ride the 24 virtual gears, or describe a real bike and ride its gears instead." |
| 11 | Phone: stop shifting | "Virtual shifting is now off." |

## What physical hardware evidence should show

Make these three points unmistakable:

1. **The iPhone appearing in the riding app's trainer list** (shot 4). This
   proves the app does what the description claims.
2. **The trainer responding to a shift** (shot 6) — the resistance changing
   while you pedal, with the gear number visible.
3. **The ride ending cleanly** (shot 11), which is the safety story.

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
> Bluetooth permission prompt, the app finding and connecting to the trainer on
> its own, the iPhone appearing in the riding app's trainer list on a computer,
> gears being shifted while pedalling with the trainer's resistance changing,
> and shifting being stopped cleanly at the end.
>
> The app has no account registration, login, account deletion, paid content,
> purchases, subscriptions or user-generated content, so there are none of those
> flows to record. Bluetooth is the only permission it ever requests.
>
> Full answers to your points 2 to 7 are in the App Review Information Notes
> field, which has been updated. In short: tested on iPhone 17 Pro with iOS 26.6,
> against a Wahoo KICKR V5 trainer, an original Zwift Click and a Wahoo KICKR
> HEADWIND, driven end to end by the FulGaz and RealVelo riding apps. The app
> uses no external services and contains no networking code. It behaves
> identically in every region. It is not a regulated industry and includes no
> protected third-party material; it speaks the public Bluetooth SIG Fitness
> Machine Service standard, and names hardware only to say what it works with.
>
> No hardware is needed to review the app: tap "Try Demo" on the first screen.

The build attached to the version is now 1.0 (6), not the rejected 1.0 (5).
