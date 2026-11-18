import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../browser/browser_loader.dart';
import '../data/novel_service.dart';
import '../screens/convert_screen.dart';
import '../ui/components.dart';
import '../ui/tokens.dart';
import 'add_novel_dialog.dart';
import 'downloads.dart';
import 'library_store.dart';
import 'novel_cover.dart';
import 'novel_detail_screen.dart';
import 'reading.dart';

part 'tabs/library_tab.dart';
part 'tabs/updates_tab.dart';
part 'tabs/reading_tab.dart';
part 'tabs/settings_tab.dart';
part 'tabs/search_tab.dart';

const appearanceLabels = {
  AppAppearance.system: 'Follow System',
  AppAppearance.light: 'Light',
  AppAppearance.dark: 'Dark',
  AppAppearance.ereaderLight: 'E-reader Light',
  AppAppearance.ereaderDark: 'E-reader Dark',
};

enum _Tab {
  library(
    'Library',
    CupertinoIcons.collections,
    CupertinoIcons.collections_solid,
  ),
  updates('Updates', CupertinoIcons.bell, CupertinoIcons.bell_fill),
  reading('Reading', CupertinoIcons.book, CupertinoIcons.book_fill),
  settings('Settings', CupertinoIcons.gear, CupertinoIcons.gear_solid),
  search('Search', CupertinoIcons.search, CupertinoIcons.search);

  const _Tab(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon, selectedIcon;
}

/// The app's home: five tabs (Library, Updates, Reading, Settings and
/// Search) on a translucent tab bar, or a sidebar on wide screens.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    required this.store,
    required this.service,
    this.downloads,
  });
  final LibraryStore store;
  final NovelService service;

  /// Downloads added novels in the background. Without it, novels are only
  /// saved and books are made from the export tool.
  final DownloadManager? downloads;
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  _Tab _tab = _Tab.library;
  String _shelf = 'All';
  final _search = TextEditingController();
  final _globalSearch = TextEditingController();
  LibraryStore get store => widget.store;

  @override
  void dispose() {
    _search.dispose();
    _globalSearch.dispose();
    super.dispose();
  }

  void _rebuild() => setState(() {});

  void _go(_Tab tab) => setState(() => _tab = tab);

  void _say(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  Future<void> _save(Future<void> action) async {
    try {
      await action;
    } catch (_) {
      if (mounted) {
        _say('Could not save this change on your device. Please try again.');
      }
    }
  }

  /// Opens the Add a Novel sheet, then the novel's page while it downloads.
  Future<void> _add([String? initial]) async {
    final added = await showAppleSheet<String>(
      context: context,
      builder: (context, _) => AddNovelDialog(
        store: store,
        service: widget.service,
        initialUrl: initial,
      ),
    );
    if (added == null || !mounted) return;
    setState(() {
      _tab = _Tab.library;
      _shelf = 'All';
      _search.clear();
    });
    final novel = store.find(added);
    if (novel == null) return;
    // Adding a link means you want to read it: start downloading right away
    // and show the book's page while chapters arrive.
    if (novel.epub == null) widget.downloads?.enqueue(novel.url);
    await _open(novel);
  }

  void _export([LibraryNovel? novel]) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ConvertScreen(
          service: widget.service,
          store: store,
          initialUrl: novel?.url,
          initialBook: novel?.metadata,
        ),
      ),
    );
  }

  Future<void> _open(LibraryNovel novel) async {
    await _save(store.opened(novel.url));
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => NovelDetailScreen(
          url: novel.url,
          store: store,
          onExport: _export,
          downloads: widget.downloads,
        ),
      ),
    );
  }

  /// Actions for a book, shown on long-press like a context menu.
  Future<void> _actions(LibraryNovel novel) async {
    final choice = await showCupertinoModalPopup<String>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: Text(novel.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        actions: [
          if (novel.epub != null)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(context, 'read'),
              child: Text((novel.progress ?? 0) > 0.001 ? 'Resume' : 'Read'),
            ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, 'open'),
            child: const Text('Show Details'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, 'shelf'),
            child: const Text('Change Shelf'),
          ),
          if (!novel.isLocal && novel.epub != null && widget.downloads != null)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(context, 'update'),
              child: const Text('Check for New Chapters'),
            ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, 'remove'),
            child: const Text('Remove from Library'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'read':
        await readNovel(context, store, novel);
      case 'open':
        await _open(novel);
      case 'shelf':
        await _pickShelf(novel);
      case 'update':
        widget.downloads?.enqueue(novel.url);
        _say('Checking ${novel.title} for new chapters');
      case 'remove':
        await _remove(novel);
    }
  }

  Future<void> _pickShelf(LibraryNovel novel) async {
    final shelf = await showCupertinoModalPopup<String>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('Move to Shelf'),
        actions: [
          for (final s in shelves)
            CupertinoActionSheetAction(
              isDefaultAction: s == novel.shelf,
              onPressed: () => Navigator.pop(context, s),
              child: Text(s),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ),
    );
    if (shelf != null) await _save(store.setShelf(novel.url, shelf));
  }

  Future<void> _remove(LibraryNovel novel) async {
    final confirm = await showAppleAlert<bool>(
      context: context,
      title: 'Remove “${novel.title}”?',
      message:
          'Its reading progress, bookmarks and highlights are removed too. '
          'EPUB files you saved elsewhere stay on your device.',
      actions: const [
        AlertAction('Cancel', false),
        AlertAction('Remove', true, destructive: true),
      ],
    );
    if (confirm != true) return;
    await widget.downloads?.cancel(novel.url);
    await _save(store.remove(novel.url));
    await forgetBook(novel);
  }

  /// A tab's page: a large title that shrinks on scroll, then its content.
  Widget _page({
    required String title,
    List<Widget> actions = const [],
    required List<Widget> slivers,
  }) {
    final p = Palette.of(context);
    return CustomScrollView(
      key: PageStorageKey('tab-$title'),
      slivers: [
        CupertinoSliverNavigationBar(
          largeTitle: Text(title),
          backgroundColor: p.background.withValues(alpha: p.eink ? 1 : .94),
          border: null,
          automaticallyImplyLeading: false,
          automaticallyImplyTitle: false,
          trailing: actions.isEmpty
              ? null
              : Row(mainAxisSize: MainAxisSize.min, children: actions),
        ),
        ...slivers,
        // Room for the floating tab bar.
        const SliverToBoxAdapter(child: SizedBox(height: 96)),
      ],
    );
  }

  Widget _empty({
    required IconData icon,
    required String title,
    required String message,
    String? action,
    VoidCallback? onAction,
  }) {
    final p = Palette.of(context);
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 56, color: p.tertiaryLabel),
                const SizedBox(height: 20),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyles.title2.copyWith(color: p.label),
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyles.body.copyWith(color: p.secondaryLabel),
                ),
                if (action != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: CapsuleButton(label: action, onPressed: onAction),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// A compact book row: cover, title and detail line.
  Widget _row(
    LibraryNovel novel, {
    String? subtitle,
    Widget? trailing,
    double? progress,
    bool busy = false,
  }) {
    final p = Palette.of(context);
    return InkWell(
      key: ValueKey('row-${novel.url}'),
      onTap: () => _open(novel),
      onLongPress: () => _actions(novel),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            SizedBox(width: 44, height: 64, child: NovelCover(novel: novel)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    novel.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyles.headline.copyWith(color: p.label),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle ?? '${novel.source} · ${novel.shelf}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyles.subheadline.copyWith(
                      color: p.secondaryLabel,
                    ),
                  ),
                  if (progress != null || busy) ...[
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: busy ? null : progress,
                      minHeight: 3,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ],
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([store, ?widget.downloads]),
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 840;
        final body = switch (_tab) {
          _Tab.library => _libraryTab(),
          _Tab.updates => _updatesTab(),
          _Tab.reading => _readingTab(),
          _Tab.settings => _settingsTab(),
          _Tab.search => _searchTab(),
        };
        final p = Palette.of(context);
        if (wide) {
          final extended = constraints.maxWidth >= 1100;
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  extended: extended,
                  selectedIndex: _tab.index,
                  onDestinationSelected: (i) => _go(_Tab.values[i]),
                  labelType: extended
                      ? NavigationRailLabelType.none
                      : NavigationRailLabelType.all,
                  selectedIconTheme: IconThemeData(color: p.accent),
                  unselectedIconTheme: IconThemeData(color: p.secondaryLabel),
                  destinations: [
                    for (final t in _Tab.values)
                      NavigationRailDestination(
                        icon: Icon(t.icon),
                        selectedIcon: Icon(t.selectedIcon),
                        label: Text(t.label),
                      ),
                  ],
                ),
                VerticalDivider(width: .5, thickness: .5, color: p.separator),
                Expanded(child: body),
              ],
            ),
          );
        }
        return Scaffold(
          extendBody: true,
          body: body,
          bottomNavigationBar: _TabBar(
            current: _tab,
            onSelect: _go,
            badge: widget.downloads?.busy ?? false ? _Tab.updates : null,
          ),
        );
      },
    ),
  );
}

/// The floating, translucent tab bar.
class _TabBar extends StatelessWidget {
  const _TabBar({required this.current, required this.onSelect, this.badge});
  final _Tab current;
  final ValueChanged<_Tab> onSelect;

  /// A tab showing activity (a small dot), such as Updates while downloading.
  final _Tab? badge;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    // Tab labels grow only a little with the text size, like on iPhone.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: GlassBar(
        child: Padding(
          padding: EdgeInsets.only(bottom: bottom > 0 ? bottom - 6 : 4, top: 4),
          child: Row(
            children: [
              for (final t in _Tab.values)
                Expanded(
                  child: Semantics(
                    selected: t == current,
                    button: true,
                    label: t.label,
                    excludeSemantics: true,
                    child: InkResponse(
                      onTap: () => onSelect(t),
                      radius: 36,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 49),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Icon(
                                  t == current ? t.selectedIcon : t.icon,
                                  size: 25,
                                  color: t == current
                                      ? p.accent
                                      : p.secondaryLabel,
                                ),
                                if (t == badge)
                                  Positioned(
                                    right: -3,
                                    top: -1,
                                    child: Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: p.accent,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            // Labels keep one line on slim phones.
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                t.label,
                                maxLines: 1,
                                style: TextStyles.caption2.copyWith(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w500,
                                  color: t == current
                                      ? p.accent
                                      : p.secondaryLabel,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DownloadBadge extends StatelessWidget {
  const _DownloadBadge(this.status);
  final DownloadStatus status;
  @override
  Widget build(BuildContext context) {
    final failed = status.phase == DownloadPhase.failed;
    return Tooltip(
      message: failed
          ? 'Download stopped'
          : status.phase == DownloadPhase.queued
          ? 'Waiting to download'
          : 'Downloading · ${status.chapters} chapters',
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .65),
          shape: BoxShape.circle,
        ),
        child: failed
            ? const Icon(
                CupertinoIcons.exclamationmark,
                size: 16,
                color: Colors.white,
              )
            : const CupertinoActivityIndicator(
                radius: 8,
                color: Colors.white,
              ),
      ),
    );
  }
}
