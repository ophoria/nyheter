# Translations

Each language is one file: `<code>.lproj/Localizable.strings` (Apple's standard format).
English (`en.lproj`) is the source; keys are the English texts.

To add or improve a language:
1. Copy `en.lproj` to `<code>.lproj` (e.g. `fi.lproj`) and translate the right-hand side of every line.
2. Keep placeholders: `%@` (text) and `%d` (number). To change their order, use `%1$@`, `%2$@` ….
3. Add the language with its flag to `L10n.languages` in `Shared/L10n.swift`.
4. Run `tools/check-l10n.py` (also run by `build.sh`); it reports missing keys and broken placeholders.

The app follows the macOS language automatically; it can be overridden in the app.
