# Moonleaf

Standalone Flutter app for Android, iOS, macOS, Windows, and Linux. Installed
apps fetch supported novel sites directly and create EPUBs on the device.
The optional browser client uses the Python API to avoid browser CORS limits.
See the [repository README](../README.md) for setup and builds.

- `lib/library/`: local UI library, navigation, novel details, and source browsing.
- `lib/theme.dart`: app theme built from the design tokens.
- `lib/ui/`: design tokens and shared components (Apple HIG based).
- `DESIGN.md`: Mihon and KOReader design references and reader architecture.
- `lib/reader/`: EPUB parsing, typesetting/pagination, and the reader UI.
- `lib/library/reading.dart`: keeping, importing, and opening books.
- `lib/library/downloads.dart`: background downloads of added novels.
- `lib/browser/browser_loader.dart`: in-app browser for sites with a human
  check (Scribble Hub, FanFiction.net); Android, iOS and macOS.
- `integration_test/browser_live_test.dart`: opt-in live check of that browser
  (`--dart-define=LIVE_URL=…`).
- `lib/data/novel_service.dart`: shared models and service interface.
- `lib/data/local_novel_service.dart`: native fetching, progress, cancellation.
- `lib/data/site_extractors.dart`: pure site parsers and navigation guards.
- `lib/data/epub_writer.dart`: EPUB 3 packaging and HTML-to-XHTML conversion.
- `lib/data/novel_api.dart`: optional web API client.
- `lib/screens/convert_screen.dart`: metadata, cover selection, progress, export.
- `lib/widgets/book_art.dart`: offline book-jacket artwork.
- `lib/theme.dart`: shared colors; `lib/main.dart`: app theme and entry point.
- `test/`: local extraction, EPUB structure, API, reader, and workflow tests.
- `tool/preview_test.dart`, `tool/reader_preview_test.dart`: rendered previews.
