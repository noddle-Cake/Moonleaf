# Moonleaf

Convert supported web novels to EPUB while preserving chapter formatting.

| Source | How Moonleaf gets the book |
|---|---|
| Royal Road | Follows the chapters |
| Scribble Hub | Follows the chapters in the app's built-in browser |
| FanFiction.net / FictionPress | Follows the chapters in the app's built-in browser |
| AO3 (Archive of Our Own) | Downloads AO3's own EPUB of the work |
| Standard Ebooks | Downloads the book's compatible EPUB |
| RoliaScan | Follows the chapters |
| Indra Translations | Follows publicly readable chapters |

Indra Translations accepts novel and chapter links. Paragraphs retain their
displayed order, and hidden filler is excluded. Premium or login-only chapters
stop the download with an access message.

Scribble Hub and FanFiction.net ask every visitor to pass a human check
(Cloudflare), so plain requests are blocked. The Android, iOS and macOS apps
load their pages in a hidden WebView instead. If a check doesn't pass on its
own, the app shows it so you can complete it, then keeps downloading at a
gentle pace (one page every 1.5 seconds). The web client and Python API can't
show the check, so they explain that these sites need the app. AO3 works that
only signed-in members can see can't be downloaded. Wattpad isn't supported
because its terms of service prohibit scraping.

Paste a novel's main page, or a link to any of its chapters. A chapter link
finds its novel and downloads the whole book from chapter 1. Royal Road chapter
addresses contain the novel's address; RoliaScan chapter pages link it in their
breadcrumbs. The extractor reads the first-chapter link and follows explicit
next links, so the dynamically loaded chapter list is not needed. Image-only manga and pages
without accessible novel text raise an error.

## Download for Android

[![Download Android APK](https://img.shields.io/badge/Download-Android_APK-193E36?logo=android&logoColor=white)](https://github.com/noddle-Cake/Moonleaf/releases/latest/download/chapter-and-verse.apk)

**[Download the latest APK](https://github.com/noddle-Cake/Moonleaf/releases/latest/download/chapter-and-verse.apk)** · [All releases and checksums](https://github.com/noddle-Cake/Moonleaf/releases)

Install the APK on your Android phone and open it. **No server or Python
installation is needed.** The app fetches novels and creates EPUBs on your
phone. Internet is needed to fetch chapters; saved EPUBs can be read offline.
Android may ask you to allow installation from your browser. Published APKs
use a permanent signing key. **Settings → App Updates** checks your installed
version against the latest verified release, shows release notes, and downloads
the APK with progress and cancellation. Tap **Install Update** and confirm in
Android. You can also download the APK from the website.
Android shows **Update**, and your library, progress, highlights and settings
stay in place. Checks run only when you open App Updates or tap Check Again;
installation always needs your confirmation. Android may first ask you to allow
Moonleaf to install apps. Return to App Updates and tap Install Update after
granting that permission. A failed download can be retried without uninstalling.

Builds 48 and earlier used temporary debug keys. Moving from one of those to
the first signed release requires one final reinstall. Save EPUB files outside
the app before uninstalling; uninstalling removes the local library, reading
progress, highlights and settings.

Merges affecting the app automatically build and publish a universal
signed release APK. The download link always points to the latest release, and a
SHA-256 checksum accompanies each APK. The **Android APK** workflow can also
be run manually from GitHub Actions on `master`.

## Light-novel library UI

The Flutter app uses a Mihon-inspired library layout with cover grids or lists,
search, sorting, and **Plan to read / Reading / Completed** shelves. Add a novel
from **Browse → Add novel URL** (a novel page or any chapter link): Moonleaf
opens its page and downloads the chapters in the background, so the book is
ready to read without a separate export step. Like Mihon, the novel page lists
its chapters, newest first by default, dims the ones you've read, and marks
where you are. Tap a chapter to open it, or **Start / Resume**. Chapter names
are tidied to **Chapter N: Name**, dropping the book title when a site repeats
it. **Check for new chapters**, **Save EPUB file**, and **Customize EPUB…** are
in the novel page menu, and **More → Create an EPUB** opens the standalone
export tool.

Library metadata, shelves, recently opened novels, reading progress, and
appearance preferences are saved locally. Automatic update checking is planned;
use **Update EPUB** on a novel to collect new chapters. No sample books are
installed.

## Built-in reader

Moonleaf includes a KOReader-inspired EPUB reader, so the app covers finding,
downloading, and reading a novel:

- Added novels download automatically and are kept with the novel. Open any
  chapter from the novel's page, or use **Start / Resume**. **Save EPUB file**
  exports it for other apps.
- **Open an EPUB file** (library toolbar, Browse, or More) imports any EPUB on
  the device into the library and opens it.
- Paginated or continuous view, with instant, slide, or fade page turns.
- Typesetting: font (including your own TTF/OTF files), size, weight, line,
  word, and letter spacing, first-line indent, paragraph spacing, margins,
  justification, and publisher alignment.
- Page colors: Paper, Sepia, Sage, Dusk, Night, E-ink, and E-ink dark, or match
  the app appearance.
- Configurable tap zones (standard, left-handed, or tap anywhere to go
  forward), swipes, pinch-to-zoom text, and mouse wheel.
- Hardware buttons (**Typeset → Controls → Buttons**): volume buttons turn
  pages (reversible, and they don't change the volume while reading);
  keyboards and Bluetooth page turners work with arrows, Page Up/Down, Space,
  and media next/previous; and any other button, such as e-reader page keys,
  a camera key, or a remote's buttons, can be assigned to next or previous
  page by pressing it. The power button is reserved by the device.
- A status bar with page numbers, pages and time left in the chapter or book,
  progress, chapter title, clock, and a progress bar with chapter marks.
- Contents, bookmarks, highlights in several colors with notes, full-text
  search, go to page or percentage, a skim slider, footnote previews, and a
  **Back to where you were** shortcut after jumps.
- Dictionary, Wikipedia, and translation look-ups for selected text, which open
  in your browser. Highlights can be copied as Markdown.
- Reading statistics: time read, speed, daily history, and time-left estimates
  based on your own pace.

Reading positions, bookmarks, highlights, and statistics are stored on the
device. In the browser client, kept and imported books last only until the tab
closes.

Choose **Appearance** in the toolbar or More to select **Follow system**,
**Light**, **Dark**, **E-reader light**, or **E-reader dark**. E-reader modes
provide grayscale visuals, black/white surfaces, stronger contrast, and reduced
motion. They do not control hardware e-ink refresh behavior.

Phone navigation becomes a side rail on desktop. The design reference and
scope are documented in [flutter_app/DESIGN.md](flutter_app/DESIGN.md).

## Run the standalone app

Install Flutter 3.47.7 or newer, then:

```sh
cd flutter_app
flutter pub get
flutter run -d macos       # on macOS
flutter run -d windows     # on Windows
flutter run -d linux       # on Linux
flutter devices
flutter run -d DEVICE_ID   # Android or iOS device / simulator
```

Native apps extract directly on the device. Paste a novel homepage, find its
details, edit the title/author/starting chapter, optionally choose a JPEG or
PNG cover, and create an EPUB. Save the finished book using the native file
dialog. Keep the app open while extracting and save before closing or starting
another book: jobs and unsaved EPUBs are held in memory, with one extraction
at a time. Cancellation discards the result after the current request returns.

Desktop builds require the platform's Flutter build tools. Android needs the
Android SDK; iOS and macOS need Xcode. Build on the corresponding host:

```sh
flutter build apk --debug
flutter build ios --release
flutter build macos --release
flutter build windows --release
flutter build linux --release
```

iOS installation on physical devices requires your own Apple signing setup.
Configure application identifiers and release signing before app-store
publication. The downloadable Android package is a signed release build.

## Optional web client

Browsers restrict requests to novel websites, so the web client uses the
Python API. Native phone and desktop apps do not use this API.

With Python 3.10+ installed, run from the repository root:

```sh
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn api.main:app --host 127.0.0.1 --port 8000
```

In a second terminal:

```sh
cd flutter_app
flutter pub get
flutter run -d chrome
```

For a built web app, run `flutter build web --release`, then start/restart the
API and open `http://localhost:8000`. It serves `flutter_app/build/web/`.
Hosted web defaults to the same origin for its API; localhost defaults to
`http://localhost:8000`. The web app's **Server connection** button changes
that address. To host the app and API separately, build with
`--dart-define=API_BASE_URL=https://your-api.example` and set
`CORS_ORIGINS=https://your-web-app.example` on the API. `WEB_BUILD_DIR` overrides
the static web directory. API documentation is at `/docs`.

The API keeps jobs in memory: run one worker. Two extractions run concurrently,
with at most 16 retained/queued jobs; results expire after one hour. Restarting
the API clears jobs. The web UI saves its library metadata in browser storage; server jobs are
separate and temporary. There is no user account system.

## Add a site

For native apps, implement `SiteExtractor` in
`flutter_app/lib/data/site_extractors.dart` and register the exact host in
`extractorFor`. Supply pure `book` and `chapter` parsers, update the novel-boundary
validation, and add fixture tests in `flutter_app/test/`. Fetching, progress,
cancellation, and EPUB packaging are shared and need no site-specific changes.

For the optional Python/web service:

1. Add a module in `extractors/` with a class inheriting `BaseExtractor`.
2. Declare exact supported `hosts`, including `www` if appropriate.
3. Implement `parse_book(soup, url)` and `parse_chapter(soup, url, count)`.
4. Import the class and append it to `EXTRACTORS` in `extractors/registry.py`.
5. Add offline parsing tests with representative HTML, including the final
   chapter and missing content.

`parse_book` returns `BookMetadata` with `title`, `author`, `description`,
`cover_url`, and `chapter_1` (use `None` for unavailable values).
`parse_chapter` returns the shared `models.chapter.Chapter` with a title,
HTML body, and `next_url=None` at the end. Raise `ExtractionError` when the
expected content is missing; do not silently export an empty or blocked page.

Use `self.link(url, href)` to resolve relative links. Select the reading body
and explicit next-chapter navigation, rather than relying on button counts or
URL title guesses. Parsing methods do not fetch pages, so they are easy to test.
The base class handles HTTP status checks, a 30-second timeout, and a reusable
session. A custom session can be injected with `Extractor(session=...)`.

`ExtractionService` checks chapter hosts and detects repeated URLs to prevent
navigation loops. `EpubBuilder` uses numbered chapter filenames so repeated
or path-like titles do not collide.

## Test

```sh
pip install -r requirements-dev.txt
python -m pytest tests -q
cd flutter_app
flutter analyze
flutter test
```

Generate phone and desktop screenshots using Flutter's renderer:

```sh
cd flutter_app
flutter test tool/preview_test.dart --update-goldens
```

Previews are saved in `flutter_app/screenshots/`. Bundled DM Sans and Fraunces
fonts use the SIL Open Font License; their licenses are included alongside
font assets.

## Android download automation

Pull requests run Flutter analysis, tests, an Android debug build, and native
Windows/Linux release builds. Desktop bundles are available as workflow
artifacts for 14 days (download the entire bundle). Pushes
to `master` run the same checks and publish the APK and its SHA-256 checksum to
GitHub Releases. Workflow actions and the Flutter SDK are pinned. Pull-request
APKs are also available as workflow artifacts for 14 days.

Public downloads are release APKs signed with a permanent private key. The
workflow restores the key only for trusted `master` builds, removes its
temporary copy after signing, and verifies the certificate, application ID,
version code and non-debuggable build before publishing. PR builds remain
debug APKs and receive no signing credentials; they are testing artifacts.

The repository's Actions secrets are `ANDROID_KEYSTORE_BASE64`,
`ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` and `ANDROID_KEY_PASSWORD`.
`ANDROID_SIGNING_CERT_SHA256` is a repository variable pinning the public
certificate fingerprint. Back up the private keystore and its password;
replacing or losing it breaks updates for existing installations.

For a local signed Android release, set `MOONLEAF_KEYSTORE_PATH`,
`MOONLEAF_KEYSTORE_PASSWORD`, `MOONLEAF_KEY_ALIAS` and `MOONLEAF_KEY_PASSWORD`
in the build environment, then run `flutter build apk --release`. Release
signing fails when credentials are missing; there is no debug-key fallback.

Builds use the workflow run number as Android's version code. Native builds
contain the Dart extractors and EPUB writer; no backend address is configured.

## APK mirror and update metadata

`tools/moonleaf_publish.py` owns both website deployment and APK mirroring.
Both commands take `/run/lock/moonleaf-publish.lock`, outside the served tree
and the executable being updated. Deployments preserve downloaded APKs,
partial downloads and the last verified `app-update.json`.

The publisher fetches a stable GitHub release, checks its checksum, signing
certificate, package ID, non-debuggable flag and build number, then atomically
renames the APK into place. Only then does it atomically publish the app-update
manifest and rewrite website download links. A stale release response cannot
roll the manifest back, and a published version cannot change its APK bytes.
No private signing credentials are used by the publisher. Its public identity
pin is `flutter_app/assets/android-update.json`, also bundled with the app.

On the existing host, deploy with `sudo python3 tools/deploy_moonleaf.py` from
the checked-out repository. It updates the source, migrates the timer to the
tracked publisher, and restarts the timer even if deployment fails. The old
`32-moonleaf.sh` entry point delegates to this command. An optional
`--expected-build N` prevents publishing before GitHub exposes a new release.
The timer continues to check every ten minutes. Android SDK tools must be
available at `/home/chris/Android/Sdk` (or pass `--sdk` to the publisher).

Update `.github/android-release-notes.md` when publishing app features. Those
notes become both the GitHub release notes and the in-app release summary.
The app downloads to its own cache, checks size and SHA-256, and asks Android
to recheck the package, version and signing identity before opening its normal
installation UI. Unsupported platforms and differently signed installations
get instructions instead of an install action. The updater never uninstalls
Moonleaf or deletes its library data.
