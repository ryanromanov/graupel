# Graupel

Graupel is a free, native text editor for the Mac that understands code. It talks to *language servers*, the same
programs that power error checking and completion in larger editors, so it can underline mistakes as you type and
suggest names that fit where the cursor is.

Graupel was made first for [Boreas](https://github.com/ryanromanov/boreas), a Fortran-inspired language, and comes
with its syntax. It works with any language that has a language server.

- __Requirement__: macOS Tahoe 26 or later, on Apple Silicon or Intel
- __Status__: early development (0.1)


## Install

With [Homebrew](https://brew.sh):

```sh
brew install --cask ryanromanov/tap/graupel
```

`brew upgrade` keeps it current. Or get the latest `Graupel-x.y.z.zip` from
[Releases](https://github.com/ryanromanov/graupel/releases). Graupel doesn't update itself, so if you install it this
way, download new versions from there.

Language servers are installed separately. For Boreas, install `boreas` as its
[README](https://github.com/ryanromanov/boreas#install-and-run) describes, and Graupel finds it by itself.


## Features

- Syntax highlighting, themes, find and replace with regular expressions, outline, split editor, scripting, and much
  more.
- __Problems as you type__: errors from the language server are marked in the text, and the one at the cursor is
  shown in the status bar. What's found depends on the server: `boreas lsp` reports syntax and link errors, and names
  that were never declared.
- __Completion__: suggestions from the language server as you type; with Boreas, the names in your file, record
  fields after a dot, built-ins, and keywords. Press Esc to show the list at any time.
- __Go to definition and hover__: Command-click a name (or Find > Jump to Definition, Control-Command-J) to go to its
  declaration, and rest the pointer on it to see what it is, when the language server supports it, as `boreas lsp`
  does.
- __Run__: Run > Run (Command-R) saves the document and runs it, with the output in a panel below the editor, a field
  for typing input, and Stop. Boreas files run with `boreas`; set the command for another language in
  Settings > Language Servers.
- __Language Servers settings__: Graupel finds the servers of the languages it comes with by itself; use a
  different command, or add a server for another language, in Settings > Language Servers. If a server is
  missing or stops, the status bar says so.
- __Format Document__: Text > Format Document asks the language server to format the file, if the server can.
- __Indentation that fits the file__: Graupel follows `.editorconfig` files, detects the indentation a file already
  uses, indents after a block opens, and lets each syntax set a default width.


## Building

Open `Graupel.xcodeproj` in Xcode and build the `Graupel` scheme, or run:

```sh
xcodebuild -project Graupel.xcodeproj -scheme Graupel -configuration Debug -derivedDataPath build \
    -skipPackagePluginValidation -skipMacroValidation build
```

The app is built as `build/Build/Products/Debug/Graupel.app`.

Builds from source are signed ad hoc, so no certificate is needed. `Scripts/release.sh` makes a signed and notarized
release, which needs a Developer ID certificate.


## Based on CotEditor

Graupel is a modified version of [CotEditor](https://github.com/coteditor/CotEditor) 7.2 by the CotEditor
Project, and owes nearly all of its editing features to it. Graupel is independent: it isn't affiliated with or
endorsed by the CotEditor Project, so please don't report Graupel's issues to CotEditor.

Graupel's own changes include language server support, the removal of the App Sandbox (so that language servers can
run without the menu bar showing each one as a running script), and its own name, icons, settings, and Help.
It doesn't include CotEditor's settings copies in iCloud, remote editing, or automatic updates.
The full history of changes is in this repository's commit log.


## License

The source code is licensed under the __Apache License, Version 2.0__, both CotEditor's code and Graupel's changes.
Graupel's images, from the app icon to the Help book's graphics, were made for Graupel and are © Ryan Romanosky.
CotEditor's own images, which are in this repository's history, are © CotEditor Project and licensed under the
[__Creative Commons Attribution-NonCommercial-NoDerivatives 4.0 International License__](https://creativecommons.org/licenses/by-nc-nd/4.0/).
See [LICENSE](LICENSE) for details.
