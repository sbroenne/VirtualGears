# Support

Virtual Gears is a free app written by one person. Support runs in the open on
GitHub, so answers stay visible to the next rider with the same question.

| I want to… | Go here |
|---|---|
| Ask a question | [Q&A discussions][qa] |
| Report something broken | [Open an issue][issues] |
| Suggest a feature | [Ideas discussions][ideas] |
| Say it works on my trainer | [Show and tell][showandtell] |

Both need a free GitHub account. There is no email address to write to and no
support desk — everything happens on those pages.

## Before you write

Most problems have a known answer already:

- **The trainer is not found.** Turn the pedals to wake it, and close any other
  app that may already be connected to it. A trainer can only talk to one thing
  at a time.
- **The riding app shows your iPhone's name instead of "Virtual Gears".** That
  is normal and it is the right device to pick. See
  [What name to look for](requirements.md#what-name-to-look-for).
- **Your trainer is not a KICKR V5.** Check
  [which trainers work](requirements.md#which-trainers-work) first. Several
  models cannot work at all, and the page says which.
- **Every gear feels too hard, or too easy, by about the same amount.** Check
  the **Gear the bike is in** setting matches the gear the chain is actually
  parked in. Every virtual gear is scaled from that ratio, so if it is wrong the
  steps still feel right but the whole ladder is shifted. Tapping the
  recommended gear and parking the chain there fixes it.
- **The Start button says "Set the gear you are in".** Virtual Gears needs to
  know which gear the bike is parked in before it can build the gears. Open
  Settings, park the chain in the gear it recommends and confirm.
- **Gears feel wrong after using the app.** Set **Wheel circumference**
  in Virtual Gears Settings to the value you use in the Wahoo app. Virtual
  Gears uses 2105 mm (700×25 road) by default. See
  [If you set a custom wheel circumference](requirements.md#if-you-set-a-custom-wheel-circumference).
- **A Windows riding app disconnected mid-ride and won't come back.** A weak
  Bluetooth link can time out, and some riding apps on Windows do not scan for
  your phone again on their own afterwards. Restart the riding app to make it
  look again. This has been confirmed to be the riding app's own reconnect
  behaviour, not a Virtual Gears fault — the trainer stayed connected and
  working the whole time.

## What to include in a bug report

The more of this you can give, the better the odds of a fix:

- Your trainer model, and your iPhone and iOS version
- The riding app you were using, and on what computer
- What you did, what you expected, and what happened instead
- Whether the app showed an error, and its exact wording
- Whether a Zwift Click or Headwind was connected

## What to expect

This is a spare-time project, so there is no guaranteed response time. Bugs that
affect safety or make the app unusable come first. Questions in the open often
get answered by other riders before I get there.

## Trying the app without a trainer

If you are asking whether the app suits you, tap **Try Demo** on the trainer
search screen. It shows the real shifting behaviour with a simulated trainer,
without any Bluetooth or hardware. See [See it working](demo.md).

## Privacy and safety

Virtual Gears collects no data at all — see [Privacy](PRIVACY.md). For what the
app does and does not do to your trainer, see [Safety](safety.md).

  [qa]: https://github.com/sbroenne/VirtualGears/discussions/categories/q-a
  [issues]: https://github.com/sbroenne/VirtualGears/issues/new/choose
  [ideas]: https://github.com/sbroenne/VirtualGears/discussions/categories/ideas
  [showandtell]: https://github.com/sbroenne/VirtualGears/discussions/categories/show-and-tell
