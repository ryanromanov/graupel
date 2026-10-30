# Change Log

0.1.0 (unreleased)
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

### Changes

- Rename the app to Graupel, with its own icon and accent color.
- Turn off the App Sandbox, so that language servers run without the menu bar showing them as running scripts.
- Suggest completions while typing by default for code.
