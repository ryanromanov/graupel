# Change Log

0.4.0 (2026-11-09)
--------------------------

### New Features

- Graupel now updates itself. It checks for a new version once a day, or when you choose Graupel > Check for Updates,
  and shows what changed before installing. Change this under Updates in General settings.

### Notes

- Graupel 0.3.1 and earlier can't update themselves, so this version has to be installed by hand or with Homebrew.


0.3.1 (2026-11-09)
--------------------------

### Improvements

- Boreas: highlight the new built-in function `cshift`.

### Fixes

- Document windows no longer ask the App Store about a donation subscription, which was left over from CotEditor.
- Help: correct what the source code page says about images.


0.3.0 (2026-11-08)
--------------------------

### New Features

- Go to where a name is declared with Command-click or Find > Jump to Definition (Control-Command-J), and see what a
  name is by resting the pointer on it, when the language server supports it. The Boreas server does.

### Changes

- Add or remove an insertion point with Control-Shift-click; Command-click now goes to a definition.

### Improvements

- Add a Run/Stop button for the toolbar.
- Underline file locations in the Run panel's output, such as `tour.bor:12:5`; click one to go to that line.


0.2.0 (2026-11-08)
--------------------------

### New Features

- Run the document with Run > Run (Command-R): Graupel saves it and shows the program's output in a Run panel below
  the editor, with a field for input and a Stop command. Set the command for each language in Settings > Language
  Servers.

### Improvements

- Draw Graupel's own Help graphics, and use its own scroll icon for the Script menu.


0.1.0 (2026-11-06)
--------------------------

The first version of Graupel, based on CotEditor 7.2. For changes before Graupel, see
[CotEditor's change log](https://github.com/coteditor/CotEditor/blob/main/CHANGELOG.md).

### New Features

- Underline the problems that language servers report as you type, and show the one at the cursor in the status bar.
- Suggest completions from language servers; Esc shows the completion list.
- Find the language servers of the bundled syntaxes automatically, and set up servers in the new Language Servers
  settings.
- Tell users in the status bar when a language server is missing or has stopped.
- Bundle the Boreas syntax.
- Format the document through the language server, with Text > Format Document.
- Follow `.editorconfig` files for indentation (`indent_style`, `indent_size`, and `tab_width`).
- Detect the indent width a file already uses, and let syntaxes set a default.
- Indent after lines that open a block, with block delimiters that can be regular expressions.

### Changes

- Rename the app to Graupel, with its own icon and accent color.
- Turn off the App Sandbox, so that language servers run without the menu bar showing them as running scripts.
- Suggest completions while typing by default for code.
- Rewrite the Help in a shorter form, as Graupel's own.
- Rename the script variables to `GraupelXInput` and `GraupelXOutput`, and the script keys to `GraupelHandlers` and
  `GraupelExecutionModel`; CotEditor's names still work.

### Removed

- Leave out settings copies in iCloud, remote editing, and automatic updates for now.
