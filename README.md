# Nomen

Names your screenshots by what they show, on your Mac, as you take them.

`Screenshot 2026-10-01 at 18.12.09.png` becomes `pentagon-aerial-view.png`. The naming happens on your Mac. Nothing is uploaded, there is no account, and there is no limit.

## Requirements

- macOS 14 (Sonoma) or later. Universal binary (Apple silicon and Intel).
- For the best names: an Apple silicon Mac with macOS 26 or later and Apple Intelligence turned on.
  - On macOS 27, the on-device model looks at the screenshot itself and at the text in it.
  - On macOS 26, the model reads the text in the screenshot only.
  - Without Apple Intelligence, Nomen makes names from the app the screenshot came from and the first words in it.

## Installation

Download the [installer](https://github.com/PerpetualBeta/Nomen/releases/latest/download/Nomen.pkg), or:

1. Download `Nomen.zip` from the [latest release](https://github.com/PerpetualBeta/Nomen/releases/latest).
2. Unzip it and drag `Nomen.app` to your Applications folder.
3. Open Nomen. A tag appears in the menu bar.

Or install it with [Homebrew](https://brew.sh):

```
brew install --cask perpetualbeta/jorvik/nomen
```

## How It Works

Take a screenshot the way you always do, for example with `shift` `command` `4`. A few seconds later, when macOS has saved it, Nomen gives it a name that says what is in it.

- **Only new screenshots are renamed.** Nomen does not touch screenshots that were in the folder before it started.
- **Nomen follows macOS.** It watches the folder that macOS saves screenshots to. To change that folder, press `shift` `command` `5`, then choose Options.
- **Every rename can be undone.** The menu shows the last five renames. You can show each one in Finder or put back its original name.
- **Two screenshots of the same thing** get `-2`, `-3` and so on. One never replaces the other.

## Menu Bar Icon

Nomen shows a tag in the menu bar. A tag with a line through it means that naming is paused.

The menu has these items:

- **Recently Renamed**: the last five renames. Each one has **Show in Finder** and **Undo**.
- **Pause Naming**: stops renaming until you choose it again. Screenshots that you take while Nomen is paused keep their macOS names.
- **Open Screenshot Folder**.
- **Check for Updates…**, **Settings…** and **Quit Nomen**.

## Settings

- **Names come from**: shows whether names come from Apple Intelligence or from simple rules, and why.
- **Keep the date in the name**: adds the time that you took the screenshot, in the same form that macOS uses: `stripe-dashboard 2026-10-01 at 14.04.21.png`. This setting is off by default.
- **Folder**: the folder that Nomen watches, with a button that shows it in Finder.
- **Launch at Login**, **Menu Bar** visibility and the **Menu Bar Icon** background.

Updates come through [Sparkle](https://sparkle-project.org/). Nomen checks for a new version once a day. To check now, choose **Check for Updates…** from the menu.

## Permissions

Nomen asks for no permissions in the usual setup.

- If macOS saves your screenshots to the Desktop, Documents or Downloads folder, macOS asks one time if Nomen can see that folder.
- Nomen finds the app that a screenshot came from without Screen Recording permission. It does not ask for Screen Recording.

## Privacy

Screenshots often show private things: conversations, documents and error messages from work. Nomen keeps all of it on your Mac.

- Vision reads the text on your Mac.
- The name comes from the on-device model of Apple Intelligence. Nomen does not use Private Cloud Compute, which is Apple's server-side model.
- Nomen has no analytics and no network connection, except the daily update check.

## Quitting

Choose **Quit Nomen** from the menu, or press `command` `Q` while the menu is open. Screenshots that you take while Nomen is not running keep their macOS names.

## Building from Source

The build uses the shared Jorvik release makefile. You must check it out next to this repository. The build also needs GNU Make 4 or later. The `make` that macOS supplies is version 3.81, which is too old, so install GNU Make from Homebrew and use it as `gmake`.

```
brew install make
git clone https://github.com/PerpetualBeta/jorvik-release.git
git clone https://github.com/PerpetualBeta/Nomen.git
cd Nomen
gmake build
open .build/Nomen.app
```

To run the tests, put the Sparkle framework on the search path:

```
swift test -Xswiftc -F -Xswiftc "$PWD" -Xlinker -F -Xlinker "$PWD" -Xlinker -rpath -Xlinker @executable_path/../Frameworks
```

## How It Works (Technical)

- **Finding screenshots.** macOS writes three extended attributes on each screenshot that it saves: `kMDItemIsScreenCapture`, `kMDItemScreenCaptureType` (selection, window or display) and `kMDItemScreenCaptureGlobalRect`. Nomen reads them from the file. Thus it recognises a screenshot whatever its name or language, and it does not wait for Spotlight. A vnode watcher on the folder reports new files.
- **Which app.** macOS saves the file about five seconds after the capture. So Nomen does not use the app that is in front when the file arrives. It compares the captured rectangle with the windows on screen, front to back. It ignores the capture interface and system surfaces, for example the full-screen Dock window on macOS 27. A window must cover at least half of the capture. A capture of a whole display uses the frontmost app.
- **Naming.** Vision recognises the text. Then the on-device `SystemLanguageModel` from Apple's Foundation Models framework works in two steps:
  1. It describes the screenshot in one sentence, from the image (on macOS 27), the text, and the app.
  2. It changes that description into a short name.

  The app name is context only. The model mentions it only when the screenshot is about the app, for example its error message or its settings. A request for a name in one step made the model ignore the picture: a photo with no text became `main-image`.
- **Cleaning the name.** Nomen changes each reply into a lowercase name of up to eight words, joined by hyphens. It removes quotes, extensions and repeated words. If the model is not available, fails, or takes more than 20 seconds for the two steps, Nomen uses a name from rules.
- **Browser names.** A screenshot that you take in a web browser shows the page, not the browser. So Nomen removes the name of the browser from the final name: `jonathan-hollin-safari` becomes `jonathan-hollin`. This applies to the common Mac browsers, and to names from the model and from the rules. Other apps keep their names, because in Outlook or Teams the app is often the subject of the screenshot. A name always keeps at least two words.
- **Renaming.** Nomen renames each file one time only. It marks a renamed file with the extended attribute `cc.jorviksoftware.Nomen.renamed`. It also tracks files by inode. Thus an undo, or a rename that you do yourself, does not look like a new screenshot.
- **History.** Nomen keeps the last 20 renames in `~/Library/Application Support/Nomen/history.json`.

### Tuning

You can change the instructions for the two steps without a rebuild. `describeInstructions` is the first step, and `namingInstructions` is the second step. To go back to the default, delete the key.

```
defaults write cc.jorviksoftware.Nomen describeInstructions "Your instructions here"
defaults write cc.jorviksoftware.Nomen namingInstructions "Your instructions here"
defaults delete cc.jorviksoftware.Nomen describeInstructions
```

## Troubleshooting

- **A screenshot was not renamed.** Make sure that naming is not paused, and that Nomen was running when you took the screenshot. Nomen renames only screenshots that macOS saves. Images that other apps save are not screenshots to Nomen.
- **The first screenshot after login is slow.** Vision loads its models the first time that it is used. This can take about 30 seconds. After that, Nomen names a screenshot in a few seconds.
- **A name is wrong.** Undo it from the menu. A small model sometimes chooses the wrong words.
- **Debug log.** To write a log to `~/Library/Logs/Nomen/nomen.log`, use `defaults write cc.jorviksoftware.Nomen debugLogging -bool YES`. The log contains file names, descriptions and names, so it is off by default. At 4 MB, Nomen moves the log to `nomen.log.1` and starts a new one. Thus the two files never use more than 8 MB. To change the limit, use `defaults write cc.jorviksoftware.Nomen debugLogMaxBytes -int <bytes>`.

## Acknowledgements

Inspired by [Nevorago's AI Screenshot Renamer](https://www.nevorago.com/), which renames screenshots in the browser.

---

Nomen is provided by [Jorvik Software](https://jorviksoftware.cc/). If you find it useful, consider [buying me a coffee](https://jorviksoftware.cc/donate).
