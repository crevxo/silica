# Silica

Silica is a small writing app for macOS. Open it and start typing.

It saves each note as a Markdown (`.md`) or rich-text (`.rtf`) file in a folder
you choose. The default is `~/Documents/Silica`. There is no database or Silica
account. You can open the same folder in Finder, sync it with iCloud or Dropbox,
or put it in a git repo.

## Features

- Markdown and rich-text notes
- Live Markdown styling as you type, with the syntax folded away except on the line you are editing
- Settings window (⌘,) for font family, text size, theme, and library folder
- Formatting shortcuts for bold, italic, underline, and strikethrough
- Tabs that keep their order between launches
- Open any `.md`, `.txt`, or `.rtf` from Finder; it becomes a tab and is edited in place
- Search across every note with ⌘F
- A Quick Note scratch pad from anywhere with ⌥⌘N
- Version snapshots every five minutes, with the latest 30 kept per note
- Focus mode and typewriter scrolling
- Light, dark, and system themes
- Markdown and PDF export
- Autosave 600 ms after you stop typing
- Signed automatic updates through Sparkle

## Build

```
./build.sh
```

This produces `dist/Silica.app`. The local build is ad-hoc signed and uses
`Resources/Silica.icns`.

The default version is `1.1.1` with build number `4`. Override either without
editing source:

```sh
SILICA_VERSION=1.1.2 SILICA_BUILD=5 ./build.sh
```

Release builds use the appcast at
`https://github.com/crevxo/silica/releases/latest/download/appcast.xml`. The
Sparkle public key is embedded in the app. The private key stays in the
maintainer's macOS Keychain.

Override the public key only when intentionally rotating it:

```sh
SILICA_PUBLIC_ED_KEY=BASE64_PUBLIC_KEY \
./build.sh
```

Keep the EdDSA private key out of the repository. Set `SILICA_APPCAST_URL` if the
feed moves.
