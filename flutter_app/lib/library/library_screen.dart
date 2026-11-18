import 'package:flutter/material.dart';

import '../data/novel_service.dart';
import '../screens/convert_screen.dart';
import 'add_novel_dialog.dart';
import 'library_store.dart';
import 'novel_cover.dart';
import 'novel_detail_screen.dart';
import '../browser/browser_loader.dart';
import 'downloads.dart';
import 'reading.dart';

const appearanceLabels = {
  AppAppearance.system: 'Follow system',
  AppAppearance.light: 'Light',
  AppAppearance.dark: 'Dark',
  AppAppearance.ereaderLight: 'E-reader light',
  AppAppearance.ereaderDark: 'E-reader dark',
};

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
  int _destination = 0;
  String _shelf = 'All';
  final _search = TextEditingController();
  bool _searching = false;
  static const _destinations = [
    (
      'Library',
      Icons.collections_bookmark_outlined,
      Icons.collections_bookmark,
    ),
    ('Updates', Icons.new_releases_outlined, Icons.new_releases),
    ('History', Icons.history_outlined, Icons.history),
    ('Browse', Icons.explore_outlined, Icons.explore),
    ('More', Icons.more_horiz, Icons.more_horiz),
  ];
  LibraryStore get store => widget.store;
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _save(Future<void> action) async {
    try {
      await action;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not save this change on your device. Please try again.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _add() async {
    final added = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AddNovelDialog(store: store, service: widget.service),
    );
    if (added == null || !mounted) return;
    setState(() {
      _destination = 0;
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
    Navigator.push(
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

  Future<void> _display() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => ListenableBuilder(
        listenable: store,
        builder: (context, _) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: Text(
                  'Library display',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              SwitchListTile(
                title: const Text('Cover grid'),
                subtitle: const Text('Turn off for a compact list'),
                value: store.grid,
                onChanged: (v) => _save(store.setAppearance(grid: v)),
              ),
              SwitchListTile(
                title: const Text('Sort by title'),
                subtitle: const Text('Otherwise, show newest additions first'),
                value: store.sortByTitle,
                onChanged: (v) => _save(store.setAppearance(sortByTitle: v)),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _appearance() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => ListenableBuilder(
        listenable: store,
        builder: (context, _) => SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                  child: Text(
                    'Appearance',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: Text(
                    'E-reader modes use monochrome colors, higher contrast, and reduced motion.',
                  ),
                ),
                for (final entry in appearanceLabels.entries)
                  ListTile(
                    key: Key('appearance-${entry.key.name}'),
                    leading: Icon(switch (entry.key) {
                      AppAppearance.system => Icons.brightness_auto_outlined,
                      AppAppearance.light => Icons.light_mode_outlined,
                      AppAppearance.dark => Icons.dark_mode_outlined,
                      _ => Icons.chrome_reader_mode_outlined,
                    }),
                    title: Text(entry.value),
                    trailing: store.appearance == entry.key
                        ? const Icon(Icons.check_rounded)
                        : null,
                    onTap: () => _save(store.setAppearance(theme: entry.key)),
                  ),
                const SizedBox(height: 24),
              ],
            ),
          ),
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
        final ereader =
            store.appearance == AppAppearance.ereaderLight ||
            store.appearance == AppAppearance.ereaderDark;
        final content = Scaffold(
          appBar: AppBar(
            title: _destination == 0 && _searching
                ? TextField(
                    key: const Key('library-search'),
                    controller: _search,
                    autofocus: true,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      hintText: 'Search your library',
                      border: InputBorder.none,
                      filled: false,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          _destinations[_destination].$1,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_destination == 0 &&
                          store.novels.isNotEmpty &&
                          constraints.maxWidth >= 400)
                        Padding(
                          padding: const EdgeInsets.only(left: 10),
                          child: Text(
                            '${store.novels.length}',
                            style: TextStyle(
                              fontSize: 16,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
            actions: [
              if (_destination == 0) ...[
                IconButton(
                  tooltip: 'Open an EPUB file',
                  icon: const Icon(Icons.file_open_outlined),
                  onPressed: () => importEpub(context, store),
                ),
                IconButton(
                  tooltip: _searching ? 'Close search' : 'Search library',
                  icon: Icon(_searching ? Icons.close : Icons.search),
                  onPressed: () => setState(() {
                    _searching = !_searching;
                    _search.clear();
                  }),
                ),
                IconButton(
                  tooltip: 'Library display',
                  icon: const Icon(Icons.filter_list),
                  onPressed: _display,
                ),
              ],
              IconButton(
                tooltip: 'Appearance',
                icon: const Icon(Icons.contrast),
                onPressed: _appearance,
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: switch (_destination) {
            0 => _library(),
            1 => _updates(),
            2 => _history(),
            3 => _browse(),
            _ => _more(),
          },
          floatingActionButton: _destination == 0 && store.novels.isNotEmpty
              ? FloatingActionButton.extended(
                  onPressed: _add,
                  icon: const Icon(Icons.add),
                  label: const Text('Add novel'),
                )
              : null,
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  animationDuration: ereader
                      ? Duration.zero
                      : const Duration(milliseconds: 250),
                  selectedIndex: _destination,
                  onDestinationSelected: (i) =>
                      setState(() => _destination = i),
                  destinations: _destinations
                      .map(
                        (d) => NavigationDestination(
                          icon: Icon(d.$2),
                          selectedIcon: Icon(d.$3),
                          label: d.$1,
                        ),
                      )
                      .toList(),
                ),
        );
        if (!wide) return content;
        return Scaffold(
          body: Row(
            children: [
              SafeArea(
                child: NavigationRail(
                  selectedIndex: _destination,
                  onDestinationSelected: (i) =>
                      setState(() => _destination = i),
                  labelType: NavigationRailLabelType.all,
                  leading: Padding(
                    padding: const EdgeInsets.only(top: 16, bottom: 28),
                    child: Tooltip(
                      message: 'Moonleaf',
                      child: Icon(
                        Icons.auto_stories_rounded,
                        size: 30,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                  destinations: _destinations
                      .map(
                        (d) => NavigationRailDestination(
                          icon: Icon(d.$2),
                          selectedIcon: Icon(d.$3),
                          label: Text(d.$1),
                        ),
                      )
                      .toList(),
                ),
              ),
              VerticalDivider(
                width: 1,
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              Expanded(child: content),
            ],
          ),
        );
      },
    ),
  );

  Widget _library() {
    final query = _search.text.trim().toLowerCase();
    final novels = store.novels
        .where(
          (n) =>
              (_shelf == 'All' || n.shelf == _shelf) &&
              '${n.title} ${n.author} ${n.source}'.toLowerCase().contains(
                query,
              ),
        )
        .toList();
    novels.sort(
      store.sortByTitle
          ? (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase())
          : (a, b) => b.addedAt.compareTo(a.addedAt),
    );
    return Column(
      children: [
        SizedBox(
          height: 58,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: ['All', ...shelves]
                .map(
                  (s) => Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: ChoiceChip(
                      label: Text(
                        '$s  ${s == 'All' ? store.novels.length : store.novels.where((n) => n.shelf == s).length}',
                      ),
                      selected: _shelf == s,
                      onSelected: (_) => setState(() => _shelf = s),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        Expanded(
          child: novels.isEmpty
              ? _empty(
                  icon: Icons.auto_stories_outlined,
                  title: store.novels.isEmpty
                      ? 'Your next story starts here'
                      : 'No novels here yet',
                  message: store.novels.isEmpty
                      ? 'Build a little world of your own. Add a light novel from a supported source, or open an EPUB file you already have.'
                      : query.isNotEmpty
                      ? 'Try another title, author, or source.'
                      : 'Move a novel to this shelf from its detail page.',
                  action: store.novels.isEmpty ? 'Browse sources' : null,
                  onAction: () => setState(() => _destination = 3),
                )
              : store.grid
              ? LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth < 500
                        ? 2
                        : (constraints.maxWidth / 195).floor().clamp(3, 7);
                    return GridView.builder(
                      key: const PageStorageKey('library-grid'),
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 16,
                        childAspectRatio: .64,
                      ),
                      itemCount: novels.length,
                      itemBuilder: (context, i) => Semantics(
                        button: true,
                        label: 'Open ${novels[i].title}',
                        child: InkWell(
                          key: ValueKey(novels[i].url),
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => _open(novels[i]),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              NovelCover(novel: novels[i], overlay: true),
                              if (widget.downloads?.statusOf(novels[i].url)
                                  case final status?)
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: _DownloadBadge(status),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
                  itemCount: novels.length,
                  itemBuilder: (context, i) => _novelRow(novels[i]),
                ),
        ),
      ],
    );
  }

  Widget _novelRow(LibraryNovel novel, {String? subtitle}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: ListTile(
      minVerticalPadding: 12,
      leading: SizedBox(width: 44, height: 66, child: NovelCover(novel: novel)),
      title: Text(novel.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          subtitle ??
              [
                novel.source,
                novel.shelf,
                if ((novel.progress ?? 0) > 0.001)
                  '${(novel.progress! * 100).round()}% read',
              ].join(' · '),
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _open(novel),
    ),
  );
  Widget _updates() => _empty(
    icon: Icons.new_releases_outlined,
    title: 'A quiet chapter',
    message: 'Open a novel and choose Update EPUB to collect new chapters. Automatic update checks will live here.',
    action: 'Go to library',
    onAction: () => setState(() => _destination = 0),
  );
  Widget _history() {
    final novels = store.novels.where((n) => n.openedAt != null).toList()
      ..sort((a, b) => b.openedAt!.compareTo(a.openedAt!));
    if (novels.isEmpty) {
      return _empty(
        icon: Icons.history,
        title: 'Every story leaves a trail',
        message: 'Books you open from your library appear here with your reading progress.',
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            'Recently Opened',
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        ...novels.map(
          (n) => _novelRow(
            n,
            subtitle: [
              n.source,
              if ((n.progress ?? 0) > 0.001) '${(n.progress! * 100).round()}%',
              MaterialLocalizations.of(context).formatMediumDate(n.openedAt!),
            ].join(' · '),
          ),
        ),
      ],
    );
  }

  Widget _browse() => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 960),
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Find your next world',
            style: Theme.of(context).textTheme.headlineMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Text(
            'Web novels, fan fiction and classics.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: _add,
                icon: const Icon(Icons.add_link),
                label: const Text('Add novel URL'),
              ),
              OutlinedButton.icon(
                onPressed: () => importEpub(context, store),
                icon: const Icon(Icons.file_open_outlined),
                label: const Text('Open an EPUB file'),
              ),
            ],
          ),
          const SizedBox(height: 36),
          Text(
            'Sources',
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          _source(
            'Royal Road',
            'Original fiction & web novels',
            'RR',
            'https://www.royalroad.com',
            const Color(0xFFE5B567),
          ),
          _source(
            'Scribble Hub',
            browserSupported
                ? 'Original web novels · may ask for a quick human check'
                : 'Original web novels · needs the Android, iOS or macOS app',
            'SH',
            'https://www.scribblehub.com',
            const Color(0xFF7FB7C9),
          ),
          _source(
            'FanFiction.net',
            browserSupported
                ? 'Fan fiction & FictionPress · may ask for a quick human check'
                : 'Fan fiction · needs the Android, iOS or macOS app',
            'FF',
            'https://www.fanfiction.net',
            const Color(0xFF8FA6D6),
          ),
          _source(
            'AO3',
            'Archive of Our Own · uses AO3’s own EPUB',
            'AO3',
            'https://archiveofourown.org',
            const Color(0xFFD98C8C),
          ),
          _source(
            'Standard Ebooks',
            'Free public-domain classics · uses their EPUB',
            'SE',
            'https://standardebooks.org',
            const Color(0xFF9CC58F),
          ),
          _source(
            'RoliaScan',
            'Translated light novels',
            'RS',
            'https://roliascan.com',
            const Color(0xFFAC9BD1),
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Text(
                      'Browse a source in your browser, then paste a novel page or any chapter link here. Moonleaf saves it and downloads the chapters. Only publicly accessible text stories are supported.',
                      style: TextStyle(height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
  Widget _source(
    String title,
    String subtitle,
    String initials,
    String url,
    Color color,
  ) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: .18),
        child: Text(
          initials,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle),
      trailing: IconButton(
        tooltip: 'Browse $title website',
        icon: const Icon(Icons.open_in_new),
        onPressed: () => openSource(context, url),
      ),
      onTap: () => openSource(context, url),
    ),
  );
  Widget _more() => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 900),
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 12),
          Icon(
            Icons.auto_stories_rounded,
            size: 48,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            'Moonleaf',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontFamily: 'Fraunces'),
          ),
          const SizedBox(height: 8),
          const Text(
            'A home for your light novels',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.palette_outlined),
                  title: const Text('Appearance'),
                  subtitle: Text(appearanceLabels[store.appearance]!),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _appearance,
                ),
                ListTile(
                  leading: const Icon(Icons.grid_view),
                  title: const Text('Library display'),
                  subtitle: Text(store.grid ? 'Cover grid' : 'Compact list'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _display,
                ),
                ListTile(
                  leading: const Icon(Icons.file_open_outlined),
                  title: const Text('Open an EPUB file'),
                  subtitle: const Text('Read any EPUB in the built-in reader'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => importEpub(context, store),
                ),
                ListTile(
                  leading: const Icon(Icons.file_download_outlined),
                  title: const Text('Create an EPUB'),
                  subtitle: const Text('Export a novel to read in another app'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _export(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          ListTile(
            leading: const Icon(Icons.phone_android_outlined),
            title: const Text('Your library stays here'),
            subtitle: const Text(
              'Saved on this device. No account or cloud sync.',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.favorite_outline),
            title: const Text('Inspired by Mihon'),
            subtitle: const Text('Library, navigation, and detail-page design'),
            trailing: const Icon(Icons.open_in_new),
            onTap: () =>
                openSource(context, 'https://github.com/mihonapp/mihon'),
          ),
          ListTile(
            leading: const Icon(Icons.chrome_reader_mode_outlined),
            title: const Text('Reader inspired by KOReader'),
            subtitle: const Text('Typesetting, menus, gestures and statistics'),
            trailing: const Icon(Icons.open_in_new),
            onTap: () =>
                openSource(context, 'https://github.com/koreader/koreader'),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Open-source licenses'),
            onTap: () =>
                showLicensePage(context: context, applicationName: 'Moonleaf'),
          ),
        ],
      ),
    ),
  );
  Widget _empty({
    required IconData icon,
    required String title,
    required String message,
    String? action,
    VoidCallback? onAction,
  }) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer
                    .withValues(alpha: .5),
                borderRadius: BorderRadius.circular(32),
              ),
              child: Icon(
                icon,
                size: 42,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 28),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.6,
              ),
            ),
            if (action != null)
              Padding(
                padding: const EdgeInsets.only(top: 28),
                child: FilledButton(onPressed: onAction, child: Text(action)),
              ),
          ],
        ),
      ),
    ),
  );
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
            ? const Icon(Icons.error_outline, size: 16, color: Colors.white)
            : const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
      ),
    );
  }
}
