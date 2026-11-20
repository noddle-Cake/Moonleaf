import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'browser/browser_loader.dart';
import 'data/novel_api.dart';
import 'data/local_novel_service.dart';
import 'library/downloads.dart';
import 'library/library_store.dart';
import 'library/library_screen.dart';
import 'platform/background.dart';
import 'platform/device.dart';
import 'platform/share.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Device.load();
  await SharedLinks.start();
  runApp(const NovelApp(welcome: true));
}

class NovelApp extends StatefulWidget {
  const NovelApp({
    super.key,
    this.service,
    this.store,
    this.autoDownload = true,
    this.welcome = false,
  });
  final NovelService? service;
  final LibraryStore? store;

  /// Download newly added novels in the background (off in some tests).
  final bool autoDownload;

  /// Show the welcome guide on the first launch.
  final bool welcome;
  @override
  State<NovelApp> createState() => _NovelAppState();
}

class _NovelAppState extends State<NovelApp> {
  late final NovelService _service;
  LibraryStore? _store;
  DownloadManager? _downloads;
  BackgroundDownloads? _background;

  /// Loads pages for sites with a human check (Android, iOS and macOS).
  BrowserLoader? _browser;
  String? _loadError;
  @override
  void initState() {
    super.initState();
    if (widget.service == null && browserSupported) _browser = BrowserLoader();
    _service =
        widget.service ??
        (kIsWeb ? NovelApi() : LocalNovelService(browser: _browser));
    _store = widget.store;
    if (_store == null) {
      _load();
    } else {
      _startDownloads();
    }
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final store = await LibraryStore.load();
      if (mounted) {
        setState(() => _store = store);
        _startDownloads();
      } else {
        store.dispose();
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _loadError =
              'Your saved library could not be loaded. Please try again.',
        );
      }
    }
  }

  void _startDownloads() {
    final store = _store;
    if (store == null || !widget.autoDownload) return;
    _downloads = DownloadManager(
      store: store,
      service: _service,
      // The web client's server fetches covers itself.
      fetchCovers: !kIsWeb,
    );
    _background = BackgroundDownloads(_downloads!, store);
    // Finish downloads that stopped when the app last closed.
    _downloads!.resumeUnfinished().catchError((Object _) => 0);
  }

  @override
  void dispose() {
    _background?.dispose();
    _downloads?.dispose();
    _browser?.dispose();
    if (widget.service == null) _service.close();
    if (widget.store == null) _store?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = _store;
    if (store == null) {
      return MaterialApp(
        theme: novelTheme(Brightness.light),
        home: Scaffold(
          body: Center(
            child: _loadError == null
                ? const CupertinoActivityIndicator(radius: 14)
                : Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_loadError!),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _load,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      );
    }
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final mode = store.appearance;
        final ereader =
            mode == AppAppearance.ereaderLight ||
            mode == AppAppearance.ereaderDark;
        return MaterialApp(
          title: 'Moonleaf',
          debugShowCheckedModeBanner: false,
          theme: novelTheme(Brightness.light, ereader: ereader),
          darkTheme: novelTheme(Brightness.dark, ereader: ereader),
          themeMode: switch (mode) {
            AppAppearance.system => ThemeMode.system,
            AppAppearance.dark || AppAppearance.ereaderDark => ThemeMode.dark,
            _ => ThemeMode.light,
          },
          themeAnimationDuration: ereader
              ? Duration.zero
              : const Duration(milliseconds: 200),
          builder: (context, child) {
            // Reduce Motion: pages appear without sliding.
            if (MediaQuery.disableAnimationsOf(context) && !ereader) {
              child = Theme(
                data: withoutMotion(Theme.of(context)),
                child: child!,
              );
            }
            final browser = _browser;
            if (browser != null) {
              child = BrowserHost(loader: browser, child: child!);
            }
            if (!ereader) return child!;
            return MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(disableAnimations: true, accessibleNavigation: true),
              child: ColorFiltered(
                colorFilter: const ColorFilter.matrix([
                  .2126,
                  .7152,
                  .0722,
                  0,
                  0,
                  .2126,
                  .7152,
                  .0722,
                  0,
                  0,
                  .2126,
                  .7152,
                  .0722,
                  0,
                  0,
                  0,
                  0,
                  0,
                  1,
                  0,
                ]),
                child: child!,
              ),
            );
          },
          home: LibraryScreen(
            store: store,
            service: _service,
            downloads: _downloads,
            welcome: widget.welcome,
          ),
        );
      },
    );
  }
}
