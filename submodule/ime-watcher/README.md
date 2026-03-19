# ime-watcher

Listens for macOS input source change notifications (`kTISNotifySelectedKeyboardInputSourceChanged`) via `CFNotificationCenterGetDistributedCenter` and prints the current input source ID to stdout on each change.

Used by Neovim's IME keeper to enforce ABC input source in normal mode.

## Build

```bash
./build.sh
```

## Usage

```bash
./ime_watcher_mac
```

Switch input source and observe output:

```
com.apple.keylayout.ABC
com.apple.inputmethod.SCIM.ITABC
com.apple.keylayout.ABC
```
