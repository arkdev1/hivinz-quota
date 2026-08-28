# Quota

A native macOS menu bar companion that hangs a small vertical rail off the edge of
your screen and shows, at a glance, how much of each AI provider's rate limit you
have burned through. Hovering a ring opens a bubble with the individual windows —
current session, weekly — each with its own bar and reset time.

---

## ⚠️ Read this first

**This project is 100% AI-generated code.** Every line of Swift, every comment, this
README included, was written by Claude (Anthropic) in a single Claude Code session.
No human wrote or reviewed the implementation line by line.

**It is a demonstration, and nothing more.** It is not a product, it is not
maintained, it has no tests, it has never been audited, and it should not be
trusted with anything that matters. Treat it as a sketch of an idea rendered in
working code — interesting to read, interesting to run once, not something to
depend on.

It depends on undocumented, unofficial behaviour of third-party tools (see
[How it reads usage](#how-it-reads-usage)). That behaviour can change without
notice, at which point this app simply stops reporting numbers.

## Credit

The idea and the visual design come from
[this post by @hivinz\_](https://x.com/hivinz_/status/2092996055248126353).
This repository is an attempt to build that concept as a real, native macOS app.
All credit for the concept belongs there; any clumsiness in the execution belongs
here.

## What it does

- A vertical rail anchored flush to the left or right edge of the screen, with one
  ring per provider. The concave fillet where the rail meets the menu bar is there
  to echo the shape of the notch, so the widget reads as part of the system rather
  than a window parked in the corner.
- Ring colour reports **state, not brand**: green below 50%, yellow to 70%, red
  above. Both thresholds are adjustable.
- Hovering a ring opens a bubble whose tail points at that exact ring, listing each
  rate-limit window with a bar, a percentage and a reset time.
- Drag the rail to slide it up and down the edge; drag it past the middle of the
  screen and it flips to the other side.
- A menu bar item mirrors the same figures as text, and holds Settings and Quit.
- Providers can be enabled, disabled and reordered. Any provider can instead be fed
  by a shell command of your own (see [Custom providers](#custom-providers)).

## How it reads usage

The guiding rule is **no bulk scanning of your filesystem**. Each provider is read
the cheapest honest way available:

| Provider | Source | Exact? |
| --- | --- | --- |
| Claude | The OAuth session Claude Code already holds in the login keychain, used against Anthropic's usage endpoint | Yes — the same figures `/usage` prints |
| Codex | The `rate_limits` the server writes into the newest `~/.codex/sessions/**/rollout-*.jsonl` | Yes — server-computed, read from the tail of one file |
| Gemini, OpenAI | Not available locally — supply a command | Depends on your command |

### The keychain prompt

Claude Code stores its OAuth credentials as a generic password named
`Claude Code-credentials`. Quota is a different binary, so the first time it reads
that item macOS will ask for your permission. Allowing it once is enough. Quota
reads the access token, sends it to `api.anthropic.com` and nowhere else, and never
writes it anywhere.

**This endpoint is not part of Anthropic's published API.** It is what the CLI
itself uses. It may change or disappear at any time.

### The fallback, and why it is off

There is a second path that adds up `message.usage` from the transcripts under
`~/.claude/projects`, weights the tokens by relative cost and infers your ceiling
from the heaviest 5-hour block on record. It works, but it is an *estimate*, and it
costs a scan of your home folder. It stays off unless you turn it on in Settings.

## Custom providers

Any provider can point at a shell command. The command must print a JSON object to
stdout:

```json
{
  "windows": [
    { "label": "Current session", "used": 0.73, "resets_in_seconds": 3060 },
    { "label": "All models", "used_percent": 7, "resets_at": "2026-08-29T00:00:00Z" }
  ]
}
```

`used` (0–1) or `used_percent` (0–100); `resets_in_seconds` or an ISO-8601
`resets_at`. Anything else is ignored. That is the whole contract — adding a
provider is configuration, not code.

## Building

Requires macOS 14 or later, Xcode 15 or later, and
[XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
xcodegen generate
xcodebuild -project Quota.xcodeproj -scheme Quota -configuration Release \
           -derivedDataPath build build
open build/Build/Products/Release/Quota.app
```

The app is signed ad hoc and is not sandboxed — it has to read files and keychain
items that a sandboxed app could not reach.

## Design notes

A few decisions that are not obvious from the outside:

- **Two panels, not one.** The rail is a small interactive `NSPanel`; the bubble is
  a separate panel with `ignoresMouseEvents`. A single panel large enough to hold
  both would swallow every click landing on its transparent half.
- **Hover comes from AppKit, not SwiftUI.** `.onHover` only fires while the app is
  frontmost, and this app is never frontmost. An `NSTrackingArea` with
  `.activeAlways` is what actually works.
- **The bubble's geometry is computed, not measured.** The tail has to point at the
  exact centre of a ring; deriving that from asynchronous layout gives a visible
  jump on the first frame, so both the rail and the bubble are laid out from
  arithmetic in `RailMetrics`.
- **The notch is measured, never hard-coded.** `auxiliaryTopLeftArea` and
  `auxiliaryTopRightArea` give the real cutout on any Mac that has one.

## Not implemented

Launch at login, threshold notifications, usage history, and any kind of test
suite. See the disclaimer at the top: this is a demo.

---

Written by Claude (Anthropic), from an idea by
[@hivinz\_](https://x.com/hivinz_/status/2092996055248126353).
