# Recording the demo video

Apple's reviewer will not own a smart trainer. Without one the app sits on
"Looking for your trainer" forever, and the submission gets rejected as
untestable. This video is what stops that happening. It is also the best thing
to put on the website.

Aim for **90 seconds**. Longer and the reviewer stops watching.

!!! danger "An animation will not do"

    The website has an animated explainer, and it is not a substitute here. The
    reviewer is not asking what the app would look like; they are asking whether
    it really drives the hardware it names. Only footage of the real thing
    answers that, and offering an animation instead invites a harder rejection
    than sending nothing.

## Before you start

- Bike on the trainer, trainer plugged in and awake.
- Riding app open on the computer, not yet paired.
- iPhone in Do Not Disturb, screen brightness up, battery over 50%.
- If you have a Zwift Click, fit it. If not, skip shots 6 and 7.

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
| 1 | Home screen, tap VirtualShift | "This is VirtualShift. It gives an indoor trainer gears it doesn't have." |
| 2 | The app finds and connects to the trainer on its own | "It finds my trainer and connects by itself. There's nothing to set up." |
| 3 | Cut to the computer: the riding app's pairing list, showing the iPhone offered as a trainer. Pair it. | "On the computer, my riding app sees the iPhone as a trainer, and pairs with it." |
| 4 | Back to the phone: the ride screen, power and cadence moving as you pedal | "Now I'm riding. Power and cadence come from the trainer, through the phone, to the riding app." |
| 5 | Pedal steadily, tap the harder button four or five times. Let the number change be visible. | "Shifting up. The trainer gets harder, and my chain hasn't moved." |
| 6 | Same again with the Zwift Click, if you have one | "The same gears, from a shifter on the handlebar." |
| 7 | Hold the Click button down, then let go | "Holding it sweeps through the gears and stops when I let go." |
| 8 | Camera shot of the bike: point at the chain, unmoving, in one gear | "The chain stays where it is all ride. No noise, no wear." |
| 9 | Phone: open the gears screen, switch to a real bike drivetrain | "I can ride the 24 virtual gears, or describe a real bike and ride its gears instead." |
| 10 | Phone: stop the ride | "Ending the ride puts the trainer back exactly as it was." |

## What the reviewer specifically needs to see

Make sure these three are unmistakable, because they are what the rejection
risks are about:

1. **The iPhone appearing in the riding app's trainer list** (shot 3). This
   proves the app does what the description claims.
2. **The trainer responding to a shift** (shot 5) — the resistance changing
   while you pedal, with the gear number visible.
3. **The ride ending cleanly** (shot 10), which is the safety story.

## Where to put the file

Export as **MP4, 1080p**, and keep it under 100 MB.

Do not commit it to the repository — a video in git stays in the history
forever and makes every clone slow. Instead:

1. Create a release on GitHub tagged `demo`.
2. Attach the MP4 to it as a release asset.
3. The public link is then
   `https://github.com/sbroenne/VirtualShift/releases/download/demo/virtualshift-demo.mp4`

That link needs no account to open, which is exactly what Apple requires.

Then:

- Put the link in **App Review Information → Notes** in App Store Connect,
  replacing `<ADD LINK>` in [the App Store guide](APP_STORE.md).
- Uncomment the video block in `docs/demo.md` so it plays on the website.
