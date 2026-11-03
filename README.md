# Graupel

Graupel is a free, native text editor for the Mac that understands code. It talks to *language servers*, the same
programs that power error checking and completion in larger editors, so it can underline mistakes as you type and
suggest names that fit where the cursor is.

Graupel was made first for [Boreas](https://github.com/ryanromanov/boreas), a Fortran-inspired language, and
supports it out of the box. It works with any language that has a language server.

- __Requirement__: macOS Tahoe 26 or later
- __Status__: early development (0.1). There is no signed release yet; build it from source.


## Features

- Everything CotEditor offers: syntax highlighting, themes, find and replace with regular expressions, outline,
  split editor, scripting, and much more.
- __Problems as you type__: errors from the language server are underlined, and the one at the cursor is shown in
  the status bar.
- __Completion__: suggestions from the language server as you type; with Boreas, the names in your file, record
  fields after a dot, built-ins, and keywords. Press Esc to show the list at any time.
- __Language Servers settings__: Graupel finds the servers of the languages it comes with by itself; use a
  different command, or add a server for another language, in Settings > Language Servers. If a server is
  missing or stops, the status bar says so.


## Building

Open `CotEditor.xcodeproj` in Xcode and build the `CotEditor` scheme, or run:

```sh
xcodebuild -project CotEditor.xcodeproj -scheme CotEditor -configuration Debug -derivedDataPath build \
    -skipPackagePluginValidation -skipMacroValidation build
```

The app is built as `build/Build/Products/Debug/Graupel.app`. (The project, scheme, and code still use
CotEditor's names, which keeps the code close to CotEditor's.)


## Based on CotEditor

Graupel is a modified version of [CotEditor](https://github.com/coteditor/CotEditor) 7.2 by the CotEditor
Project, and owes nearly all of its editing features to it. Graupel is independent: it isn't affiliated with or
endorsed by the CotEditor Project, so please don't report Graupel's issues to CotEditor.

Graupel's own changes include language server support, the removal of the App Sandbox (so that language servers can
run without the menu bar showing each one as a running script), and its own name, icon, and settings.
The full history of changes is in this repository's commit log.

Graupel's Help is being rewritten; some pages still read like CotEditor's.


## License

The source code is licensed under the __Apache License, Version 2.0__, both CotEditor's code and Graupel's changes.
Image resources from CotEditor are © CotEditor Project and licensed under the
[__Creative Commons Attribution-NonCommercial-NoDerivatives 4.0 International License__](https://creativecommons.org/licenses/by-nc-nd/4.0/);
Graupel uses them unmodified. The Graupel app icon is © Ryan Romanosky. See [LICENSE](LICENSE) for details.
