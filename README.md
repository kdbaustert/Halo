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

If you dim the built-in display below 100%, Halo turns the boost off and turns it back on once
brightness is at 100% again.

## Requirements

- macOS 14 or later
- A display with EDR headroom, like the built-in XDR panel on a MacBook Pro

## Build and install

```sh
./build.sh            # builds build/Halo.app
./build.sh --install  # also copies it into /Applications and launches it
```

The app is signed ad-hoc. It asks for no folder or privacy access, so there's nothing to
approve.

Run the tests with `swift test`.

## Using it

Click the sun in the menu bar to turn the boost on and set its strength with the slider.

In Settings (⌘, from the menu) you can:

- Launch Halo at login
- Turn the boost back on at launch if it was on when Halo quit
- Hide the menu bar icon. Open Halo again from Finder or Spotlight to get back to Settings.
- Set global shortcuts to toggle the boost or make it brighter or dimmer by 10%. They work from
  any app and need no Accessibility permission.
