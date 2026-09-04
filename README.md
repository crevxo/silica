# Silica

A minimalist plain-text editor for macOS. Tabs, a blank page, and nothing else on
screen unless you ask for it.

Your notes are `.md` files in a folder you pick (`~/Documents/Silica` by default).
No database, no cloud, no account — the folder is the app's entire state, so it
works with Finder, iCloud Drive, Dropbox, or a git repo without knowing about any
of them.

## Features

- **Tabs** — rename inline (double-click), reorder-free, restored on launch
- **Focus mode** (⇧⌘F) — hides every control; Esc, or the bar that appears when
  you move the pointer to the top of the window, brings them back
- **Light / Dark / Auto** (⇧⌘D to flip, Auto follows macOS)
- **Quick Note** (⌥⌘N from anywhere) — a menu-bar scratch pad; ⌘⏎ promotes it to
  a real note
- **Search** (⌘F) — one field across every note; results show the matching line
  and jump straight to it
- **Version history** (⌘Y) — a snapshot every five minutes of writing, last 30 per
  note, kept in `.manila-versions` beside the notes
- **Words written today** — in the status bar, on by default
- **Typewriter scrolling** — keeps the caret at the middle of the window
- **Export** — Markdown or paginated PDF
- **Autosave** — 600ms after you stop typing, straight to the file
- **Automatic updates** — Sparkle checks a signed appcast once release settings
  are configured

## Build

```
./build.sh
```

Produces `dist/Silica.app`, ad-hoc signed, using the quartz icon in
`Resources/Silica.icns`.

The default version is `1.0.0` with build number `1`. Override either without
editing source:

```sh
SILICA_VERSION=1.0.1 SILICA_BUILD=2 ./build.sh
```

The default feed points at
`https://github.com/crevxo/silica/releases/latest/download/appcast.xml`. Generate
Sparkle's EdDSA key before the first release, then pass its public half when
building:

```sh
SILICA_PUBLIC_ED_KEY=BASE64_PUBLIC_KEY \
./build.sh
```

Until the public key is supplied, the updater stays dormant and the update menu
is hidden. Keep the EdDSA private key out of the repository. Override
`SILICA_APPCAST_URL` only if the feed moves elsewhere.
