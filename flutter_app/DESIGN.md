# UI design reference

The library navigation, category controls, cover-grid layout, and novel detail
hierarchy are inspired by [Mihon](https://github.com/mihonapp/mihon), an
Apache-2.0 project. Reference screens: Library, HomeScreen navigation, and
MangaScreen. This is an original Flutter implementation; no Mihon Kotlin code,
logos, screenshots, or cover artwork is bundled. The app includes a visible
credit and link in More.

The light-novel UI has Library, Updates, History, Browse, and More destinations.
A local UI library stores metadata, shelves, recently opened novels, display
preferences, appearance, and reading progress. Automatic update checks are
reserved for a later phase. The EPUB exporter remains usable from a book or
More.

## Reader

The reader in `lib/reader/` follows the depth and interaction model of
[KOReader](https://github.com/koreader/koreader) (AGPL-3.0): tap zones with a
top menu and a bottom typesetting menu, a configurable status bar, skim
slider, contents, bookmarks with dog-ears, highlights and notes, footnote
previews, search, look-ups, and reading statistics. It is an original Flutter
implementation: no KOReader Lua or C/C++ code, crengine code, icons, fonts,
or style tweaks are copied or ported. Keep it that way unless the project
chooses to become AGPL-licensed. The More screen credits KOReader with a link.

- `epub_document.dart`: EPUB 2/3 parsing (OPF, spine, nav or NCX contents)
  into a block model of styled text runs, images, and rules with stable
  character offsets. Positions, bookmarks, and highlights use
  (chapter, offset), so they survive font and layout changes.
- `typesetter.dart`: lays out blocks with `TextPainter` and paginates by whole
  lines. Pages are vertical windows into each laid-out paragraph, so justified
  text stays consistent across page breaks. Headings stay with the text that
  follows them. Book page numbers are counted in the background.
- `reader_screen.dart` / `reader_panels.dart`: gestures, menus, and sheets.
- `reader_settings.dart`: global typesetting preferences and per-book state.
- `book_files*.dart`: app-private EPUB and font storage (in memory on the web).

Known limits: CSS stylesheets are not applied beyond inline alignment and
emphasis, there is no automatic hyphenation, and look-ups use online sources
rather than offline dictionaries.

Appearance supports system, light, dark, e-reader light, and e-reader dark.
E-reader appearances use grayscale rendering, black/white surfaces, increased
contrast, and reduced animation. These are visual modes, not device-specific
e-ink refresh controls. The reader's **Match app** page color follows them,
using its E-ink palettes for the e-reader modes.

First-run libraries and published previews are empty. Do not seed books, use
personal reading selections in examples, or capture an existing user's library
for screenshots. Reader previews and tests use a generated book of original
filler text. Live smoke checks require an explicitly supplied URL.
