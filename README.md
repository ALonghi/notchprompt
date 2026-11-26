# Notchprompt

<p align="center">
  <img src="assets/banner.png" alt="Notchprompt Banner" width="100%">
</p>

Native macOS notch-adjacent teleprompter for presentations and recordings.

## Quick Demo

> Demo assets below are placeholders. Replace with real captures before public
> launch.

<!--
![Notchprompt hero screenshot](docs/media/hero.png)
*Hero view of the overlay panel and settings workflow.*

![Notchprompt scrolling demo GIF](docs/media/notchprompt-demo.gif)
*In-use scrolling demo with start/pause and speed adjustments.*
-->

## Features

- Menu bar utility workflow (`NP` status item).
- Notch-adjacent floating overlay with transport controls.
- One window for the script editor and settings.
- Paste a script straight from the clipboard, type it, or import a document.
- Move the overlay to any connected display.
- Start/pause, reset, and jump back 5 seconds.
- Adjustable speed, font size, overlay width, and overlay height.
- Optional countdown before scrolling starts.
- Import/export scripts (TXT, Markdown, RTF, Word, Pages, PDF).
- Privacy mode (`NSWindow.SharingType`, best-effort/app-dependent).

## Using Notchprompt

**Add your script.** Notchprompt opens its window on first launch. Copy your
transcript from anywhere and click **Paste from Clipboard** (or click in the
editor and press `⌘V`), type it, or click **Import File…**. You can also paste
from the overlay itself: its **Paste from Clipboard** button, `⌘V` after
clicking it, or its `…` menu. To open the editor later, click the pencil on the
overlay, double-click the overlay, or choose **Edit Script…** from the `NP`
menu.

**Choose the display.** The overlay sits at the top center of the built-in
display by default. To move it:

- drag the overlay onto another screen,
- click the display button on the overlay (shown when more than one display is
  connected),
- use **Display** in the `NP` menu, or
- click a display in the map under **Settings → Display**.

**Prompt.** Press play on the overlay, **Start Prompting** in the editor, or
`⌥⌘P`. Pausing switches to manual mode: scroll on the overlay with the
trackpad to move through the script.

## Requirements

- macOS version supported by the current deployment target in
  `notchprompt.xcodeproj`.
- Apple Silicon or Intel Mac.

## Run Safely (Sandboxed Build From Source)

Notchprompt is a native macOS app, so it cannot run in Docker (Docker runs
Linux containers). Instead, this builds it from source and locks it inside the
macOS App Sandbox, which the kernel enforces:

- no network access at all (no network entitlement is granted)
- file access only to files you pick in an Open/Save dialog
- hardened runtime, no helper executables in the bundle

Requirements: macOS 14+ and full Xcode (App Store; open it once).

```bash
make run       # build, verify, launch
make install   # build, verify, copy to /Applications
make verify    # re-check the built app (or: scripts/sandboxed.sh verify /Applications/notchprompt.app)
```

The script stops with an error, without producing an app, if the result is not
sandboxed with exactly the permissions in `scripts/sandbox.entitlements`, or if
the app source differs from the security-reviewed commit (override with
`ALLOW_UNREVIEWED=1` after reviewing the diff). Locally built apps are not
quarantined, so the `xattr -cr` step below is not needed.

## Install (Recommended)

1. Open GitHub Releases:
   `https://github.com/saif0200/notchprompt/releases`
2. Download the latest `.dmg` release asset.
3. Open the DMG and drag `notchprompt.app` to `Applications`.
4. Launch `notchprompt.app`.

### Unsigned Build Note

This build is currently unsigned/unnotarized, so macOS may show security prompts.

If macOS shows:

- `Apple could not verify "notchprompt" is free of malware...`
- or `"notchprompt" is damaged and can’t be opened`

run:

```bash
xattr -cr /Applications/notchprompt.app
open /Applications/notchprompt.app
```

If it is still blocked:

1. Open `System Settings -> Privacy & Security`.
2. Click **Open Anyway** for `notchprompt`.
3. Launch again.

## Keyboard Shortcuts

| Shortcut | Action |
| --- | --- |
| `⌥⌘P` | Start / Pause |
| `⌥⌘R` | Reset scroll |
| `⌥⌘J` | Jump back 5s |
| `⌥⌘H` | Toggle Privacy Mode |
| `⌥⌘O` | Show / hide the overlay |
| `⌥⌘=` | Increase speed |
| `⌥⌘-` | Decrease speed |

## Build From Source

```bash
git clone https://github.com/saif0200/notchprompt.git
cd notchprompt
open notchprompt.xcodeproj
```

CLI build:

```bash
xcodebuild -project notchprompt.xcodeproj -scheme notchprompt -configuration Debug build
```

## License

MIT. See `LICENSE`.
