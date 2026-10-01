# Nomen

Names your screenshots by what they show, on your Mac, as you take them.

`Screenshot 2026-10-01 at 14.04.21.png` becomes `safari-github-pull-request-48.png`. Nothing is uploaded, there is no account, and there is no limit.

## Requirements

- macOS 14 (Sonoma) or later
- For the best names: macOS 26 or later with Apple Intelligence turned on. macOS 27 lets the model look at the screenshot itself; macOS 26 gives it the text in the screenshot. Without Apple Intelligence, Nomen names screenshots from the app they came from and the first words in them.

## Installation

Nomen is not released yet. See [Building from Source](#building-from-source).

## How It Works

Take a screenshot the way you always do. A few seconds later, once macOS has saved it, Nomen gives it a name that says what is in it.

- **Only new screenshots are renamed.** Nomen never touches screenshots that were already in the folder when it started.
- **It follows macOS.** Nomen watches whichever folder macOS saves screenshots to. Change that folder in the Screenshot app: press `shift` `command` `5`, then choose Options.
- **Every rename can be undone.** The menu lists the last few renames. Each one can be shown in Finder or put back to its original name.
- **Two screenshots of the same thing** get `-2`, `-3` and so on, rather than one replacing the other.

## Menu Bar Icon

Nomen shows a tag in the menu bar. A crossed-out tag means naming is paused.

The menu has:

- **Recently Renamed**: the last five renames, each with **Show in Finder** and **Undo**.
- **Pause Naming**: stops renaming until you choose it again. Screenshots taken while paused keep their macOS names.
- **Open Screenshot Folder**.
- **Check for Updates…**, **Settings…** and **Quit Nomen**.

## Settings

- **Names come from**: shows whether names come from Apple Intelligence or from simple rules, and why.
- **Keep the date in the name**: adds the time the screenshot was taken, as macOS does: `stripe-dashboard 2026-10-01 at 14.04.21.png`. Off by default.
- **Folder**: the folder Nomen is watching, with a button to show it.
- **Launch at Login** and **Menu Bar** visibility.

## Permissions

Nomen asks for none in the usual setup.

- If your screenshots are saved to the Desktop, Documents or Downloads, macOS asks once whether Nomen may see that folder.
- Nomen reads which app a screenshot came from without Screen Recording permission. It does not ask for Screen Recording.

## Quitting

Choose **Quit Nomen** from the menu, or press `command` `Q` while its menu is open. Screenshots taken while Nomen is not running keep their macOS names.

## Building from Source

The build uses the shared Jorvik release makefile, which must be checked out next to this repository, and GNU Make 4 or later. The `make` that ships with macOS is version 3.81, which is too old, so install GNU Make from Homebrew and run it as `gmake`.

```
brew install make
git clone https://github.com/PerpetualBeta/jorvik-release.git
git clone https://github.com/PerpetualBeta/Nomen.git
cd Nomen
gmake build
open .build/Nomen.app
```

Run the tests with the Sparkle framework on the search path:

```
swift test -Xswiftc -F -Xswiftc "$PWD" -Xlinker -F -Xlinker "$PWD" -Xlinker -rpath -Xlinker @executable_path/../Frameworks
```

## How It Works (Technical)

- **Finding screenshots.** macOS stores three extended attributes on every screenshot it saves: `kMDItemIsScreenCapture`, `kMDItemScreenCaptureType` (selection, window or display) and `kMDItemScreenCaptureGlobalRect`. Nomen reads them from the file directly, so it recognises a screenshot whatever its name or language, and never waits for Spotlight to index it. A vnode watcher on the folder reports new files.
- **Which app.** The captured rectangle is matched against the windows on screen, front to back, ignoring the capture UI and system surfaces such as the Dock's full-screen window on macOS 27. A window must cover at least half of the capture. Whole-display captures use the frontmost app.
- **Naming.** Vision recognises the text. The on-device `SystemLanguageModel` from Apple's Foundation Models framework then works in two steps: it describes the screenshot in one sentence from the image (on macOS 27), the text and the app, and then turns that description into a short name. Asking for a name in one step made the model ignore the picture: a photo with no text came back as `main-image`. Nomen never uses the framework's Private Cloud Compute model. Replies are cleaned into a lowercase, hyphenated name of up to eight words. If the model is unavailable, fails, or takes more than 20 seconds for both steps, a rule-based name is used instead.
- **Renaming.** Each file is renamed once. Nomen marks renamed files with the extended attribute `cc.jorviksoftware.Nomen.renamed`, and tracks files by inode, so neither an undo nor a rename of your own is mistaken for a new screenshot.
- **History.** The last 20 renames are kept in `~/Library/Application Support/Nomen/history.json`.

### Tuning

The instructions for both steps can be changed without a rebuild. `describeInstructions` is the first step, `namingInstructions` the second. Delete a key to go back to the default.

```
defaults write cc.jorviksoftware.Nomen describeInstructions "Your instructions here"
defaults write cc.jorviksoftware.Nomen namingInstructions "Your instructions here"
defaults delete cc.jorviksoftware.Nomen describeInstructions
```

## Troubleshooting

- **A screenshot was not renamed.** Check that naming is not paused, and that the screenshot was taken while Nomen was running. Screenshots saved by other apps, rather than by macOS, are not screenshots to Nomen and are left alone.
- **The first screenshot after login takes a while.** Vision loads its models the first time it is used, which can take about 30 seconds. Later screenshots are named within a few seconds.
- **A name is wrong.** Undo it from the menu. A small model sometimes picks the wrong words.
- **Debug log.** `defaults write cc.jorviksoftware.Nomen debugLogging -bool YES` writes a log to `~/Library/Logs/Nomen/nomen.log`. It contains file names and model replies, so it stays off unless you turn it on. At 4 MB the log is moved to `nomen.log.1` and a new one starts, so the two files never take more than 8 MB. Change the limit with `defaults write cc.jorviksoftware.Nomen debugLogMaxBytes -int <bytes>`.

## Acknowledgements

Inspired by [Nevorago's AI Screenshot Renamer](https://www.nevorago.com/), which does this in the browser.

---

Nomen is provided by [Jorvik Software](https://jorviksoftware.cc/). If you find it useful, consider [buying me a coffee](https://jorviksoftware.cc/donate).
