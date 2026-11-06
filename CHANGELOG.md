# Change Log

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
