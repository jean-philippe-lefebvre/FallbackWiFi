# FallbackWiFi

Tiny macOS menu bar app that switches to a selected backup Wi-Fi when the current connection loses internet access.

## MVP

- Pick a backup Wi-Fi from the Mac's preferred networks.
- Save the backup Wi-Fi password once in the app's Keychain item.
- Keep the menu bar icon monochrome during normal use.
- Tint the selected shield/Wi-Fi icon when fallback is active.
- Configure the fallback active color in Settings.
- Run periodic connection checks and manually test from the menu.

## Development

```sh
swift test
swift build -c release
./script/build_and_run.sh --verify
```

The bundled app is created by:

```sh
make all
```
