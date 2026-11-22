<p align="center">
  <img src="docs/icon.png" alt="Halo app icon" width="160" height="160">
</p>

# Halo

An app that pushes an XDR or HDR Mac display past its normal maximum brightness, up to 2x SDR white.

## How it works

macOS holds back extra brightness on these panels for HDR content. Halo puts a one-point EDR
window in the screen's bottom-left corner, under the rounded corner where you can't see it.
That keeps the display in EDR mode, and Halo then scales the display's gamma table above 1.0 so
everything on screen uses the headroom.

The boost tops out at 2x. The XDR panel holds about 1000 nits across the whole screen against
500 for SDR white, and past that it can only brighten small areas, so full-screen content would
clip.

If you dim the built-in display below 80%, Halo pauses its boost and resumes once brightness is
at 100% again. You can turn that off in Settings.

An external display has to be in HDR mode before it has any headroom to use. Halo can switch it
to HDR while boosting and back when it stops. That's off by default, because the screen blanks
for a moment as it switches.

## Requirements

- macOS 14 or later
- A display with EDR headroom: the built-in XDR panel on a MacBook Pro, or an external HDR display

## Install

Download the latest zip from [Releases](https://github.com/kdbaustert/Halo/releases), unzip it and
move Halo.app to /Applications.

Releases aren't notarized, so macOS blocks the first launch. Launch Halo once and dismiss the
dialog, then click Open Anyway in System Settings > Privacy & Security. Or run
`xattr -cr /Applications/Halo.app`. Right-click > Open no longer works on current macOS. Halo asks for no folder or privacy
access, so there's nothing to approve after that.

## Updates

Halo checks for a new version once a day and asks before installing it. You can check by hand or
change both settings in Settings > About, where you can also opt in to beta updates. Every update is checked against Halo's signing key
before it installs.

A copy you build yourself never updates itself, so it can't be replaced by the published version.

## Using it

Click the sun in the menu bar. The built-in display and external displays each get their own
switch and strength slider, so you can boost one without the other.

In Settings (⌘, from the menu) you can:

- Launch Halo at login
- Turn the boost back on at launch if it was on when Halo quit
- Stop the boost pausing when the built-in display is dimmed
- Switch external displays to HDR while boosting
- Hide the menu bar icon. Open Halo again from Finder or Spotlight to get back to Settings.
- Set global shortcuts to toggle the boost or make it brighter or dimmer by 10%. They work from
  any app and need no Accessibility permission.

## Privacy

No telemetry, analytics, crash reporting or account. The only network request Halo makes on its
own is the update check, which fetches the release feed from GitHub Pages and sends nothing about
you or your Mac.

## Contributing

Issues and pull requests are welcome. To build and test:

```sh
./build.sh --install  # builds build/Halo.app, copies it to /Applications and launches it
swift test            # the test suite, which CI runs on every push and pull request
```

Building needs Xcode or the Xcode command line tools.

To cut a release, push a `v` tag such as `v0.2.0`. The release workflow builds, tests, publishes
the zip and adds it to the appcast. A tag with a hyphen, like `v0.3.0-beta`, ships to beta copies
only. To check a release locally first, run `VERSION=0.2.0 BUILD=40 ./release.sh` (add `--beta`
for a beta).

## License

Halo is licensed under the [GNU General Public License v3.0](LICENSE).

Built by [@kdbaustert](https://github.com/kdbaustert).
