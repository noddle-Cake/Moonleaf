import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../reader/epub_document.dart';
import '../reader/reader_settings.dart';
import '../ui/components.dart';
import '../ui/tokens.dart';
import 'downloads.dart';
import 'library_store.dart';
import 'novel_cover.dart';
import 'reading.dart';

Future<void> openSource(BuildContext context, String url) async {
  try {
    if (!await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    )) {
      throw StateError('Cannot open link');
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open the source in your browser.'),
        ),
      );
    }
  }
}

typedef OpenBook = Future<void> Function(
  LibraryNovel novel, {
  int? chapter,
  int? offset,
});

/// A novel's page, laid out like Mihon's: details and actions, then the
/// chapter list with what you have read.
class NovelDetailScreen extends StatefulWidget {
  const NovelDetailScreen({
    super.key,
    required this.url,
    required this.store,
    required this.onExport,
    this.downloads,
    this.onRead,
    this.chapters,
  });
  final String url;
  final LibraryStore store;

  /// Opens the export tool to customize the EPUB (title, cover, chapter).
  final void Function(LibraryNovel) onExport;
  final DownloadManager? downloads;

  /// Overrides opening the reader, for tests.
  final OpenBook? onRead;

  /// Overrides reading the chapter list from the kept EPUB, for tests.
  final Future<List<TocEntry>> Function(LibraryNovel)? chapters;
  @override
  State<NovelDetailScreen> createState() => _NovelDetailScreenState();
}

class _NovelDetailScreenState extends State<NovelDetailScreen> {
  LibraryStore get store => widget.store;
  String get url => widget.url;
  BookState? _state;
  Future<List<TocEntry>>? _chapters;
  LibraryNovel? _chaptersFor;
  bool _newestFirst = true;
  bool _fullSynopsis = false;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    final state = await BookState.load(url);
    if (mounted) setState(() => _state = state);
  }

  Future<void> _read(LibraryNovel novel, {int? chapter, int? offset}) async {
    final open = widget.onRead;
    if (open != null) {
      await open(novel, chapter: chapter, offset: offset);
    } else {
      await readNovel(context, store, novel, chapter: chapter, offset: offset);
    }
    await _loadState();
  }

  void _say(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  Future<void> _shelf(LibraryNovel novel) async {
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
    if (shelf == null) return;
    try {
      await store.setShelf(url, shelf);
    } catch (_) {
      if (mounted) _say('Could not save the shelf change.');
    }
  }

  Future<void> _remove() async {
    final title = store.find(url)?.title ?? 'this book';
    final confirm = await showAppleAlert<bool>(
      context: context,
      title: 'Remove “$title”?',
      message:
          'Its reading progress, bookmarks and highlights are removed too. '
          'EPUB files you saved elsewhere stay on your device.',
      actions: const [
        AlertAction('Cancel', false),
        AlertAction('Remove', true, destructive: true),
      ],
    );
    if (confirm != true) return;
    try {
      final novel = store.find(url);
      await widget.downloads?.cancel(url);
      await store.remove(url);
      if (novel != null) await forgetBook(novel);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) _say('Could not remove this novel.');
    }
  }

  Future<List<TocEntry>> _chaptersOf(LibraryNovel novel) {
    // The store replaces a novel's entry when its book is downloaded again;
    // the parsed contents are cached, so asking again is cheap.
    if (_chapters == null || !identical(_chaptersFor, novel)) {
      _chaptersFor = novel;
      _chapters = (widget.chapters ?? loadChapters)(novel);
    }
    return _chapters!;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([store, ?widget.downloads]),
    builder: (context, _) {
      final novel = store.find(url);
      if (novel == null) return const Scaffold(body: SizedBox.shrink());
      final status = widget.downloads?.statusOf(url);
      return FutureBuilder<List<TocEntry>>(
        future: _chaptersOf(novel),
        builder: (context, snapshot) {
          final chapters = snapshot.data ?? const <TocEntry>[];
          return _page(novel, status, chapters, snapshot.hasData);
        },
      );
    },
  );

  /// Index of the chapter the reader is in, or -1 before the first read.
  int _current(List<TocEntry> chapters) {
    final state = _state;
    if (state == null || chapters.isEmpty) return -1;
    if (state.progress <= 0 && state.chapter == 0 && state.offset == 0) {
      return -1;
    }
    var current = 0;
    for (var i = 0; i < chapters.length; i++) {
      final c = chapters[i];
      if (c.chapter < state.chapter ||
          (c.chapter == state.chapter && c.offset <= state.offset)) {
        current = i;
      }
    }
    return current;
  }

  Widget _page(
    LibraryNovel novel,
    DownloadStatus? status,
    List<TocEntry> chapters,
    bool loaded,
  ) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final palette = Palette.of(context);
    final side = Space.margin(MediaQuery.sizeOf(context).width);
    final current = _current(chapters);
    final finished = (_state?.progress ?? 0) >= .999;
    final downloading = status?.active ?? false;
    final hasBook = novel.epub != null;
    final order = [
      for (var i = 0; i < chapters.length; i++)
        _newestFirst ? chapters.length - 1 - i : i,
    ];
    final menu = PopupMenuButton<String>(
      tooltip: 'More options',
      onSelected: (value) => switch (value) {
        'update' => widget.downloads?.enqueue(url),
        'export' => exportEpub(context, novel),
        'customize' => widget.onExport(novel),
        'shelf' => _shelf(novel),
        'remove' => _remove(),
        _ => null,
      },
      itemBuilder: (_) => [
        if (!novel.isLocal && widget.downloads != null)
          PopupMenuItem(
            value: 'update',
            enabled: !downloading,
            child: const Text('Check for New Chapters'),
          ),
        if (hasBook)
          const PopupMenuItem(value: 'export', child: Text('Save EPUB File')),
        if (!novel.isLocal)
          const PopupMenuItem(
            value: 'customize',
            child: Text('Customize EPUB…'),
          ),
        const PopupMenuItem(value: 'shelf', child: Text('Change Shelf')),
        PopupMenuItem(
          value: 'remove',
          child: Text(
            'Remove from Library',
            style: TextStyle(color: Palette.of(context).destructive),
          ),
        ),
      ],
    );
    final header = LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth < 320 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.25;
        final cover = SizedBox(
          width: stacked
              ? 130
              : constraints.maxWidth < 400
              ? 108
              : 160,
          height: stacked
              ? 195
              : constraints.maxWidth < 400
              ? 162
              : 240,
          child: NovelCover(novel: novel),
        );
        final details = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              novel.title,
              style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            Text(
              novel.author.isEmpty ? 'Unknown author' : novel.author,
              style: text.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              [
                novel.source,
                if (hasBook && chapters.isNotEmpty)
                  '${chapters.length} chapters',
              ].join(' · '),
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            ActionChip(
              avatar: const Icon(CupertinoIcons.collections, size: 18),
              label: Text(novel.shelf),
              onPressed: () => _shelf(novel),
            ),
          ],
        );
        return stacked
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [cover, const SizedBox(height: 24), details],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  cover,
                  const SizedBox(width: 24),
                  Expanded(child: details),
                ],
              );
      },
    );
    final synopsis = novel.description?.trim() ?? '';
    final top = <Widget>[
      header,
      const SizedBox(height: 20),
      // The main action, full width like Apple Books.
      if (hasBook)
        CapsuleButton(
          key: const Key('read-novel'),
          icon: CupertinoIcons.play_fill,
          label: finished
              ? 'Read Again'
              : current >= 0
              ? 'Resume'
              : 'Start Reading',
          onPressed: () => _read(novel),
        ),
      if (hasBook) const SizedBox(height: 12),
      if (status != null) _downloadCard(status),
      if (status == null && !hasBook && !novel.isLocal)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: LayoutBuilder(
              builder: (context, box) {
                final button = FilledButton(
                  key: const Key('download-novel'),
                  onPressed: widget.downloads == null
                      ? () => widget.onExport(novel)
                      : () => widget.downloads!.enqueue(url),
                  child: const Text('Download'),
                );
                final message = Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(CupertinoIcons.cloud_download, color: colors.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Not downloaded yet', style: text.titleMedium),
                          const SizedBox(height: 2),
                          Text(
                            'Download the chapters to read them here.',
                            style: text.bodyMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
                // Slim phones and large text: put the button under the text.
                final stacked =
                    box.maxWidth < 420 ||
                    MediaQuery.textScalerOf(context).scale(1) > 1.3;
                return stacked
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [message, const SizedBox(height: 12), button],
                      )
                    : Row(
                        children: [
                          Expanded(child: message),
                          const SizedBox(width: 12),
                          button,
                        ],
                      );
              },
            ),
          ),
        ),
      if (synopsis.isNotEmpty) ...[
        const SizedBox(height: 12),
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _fullSynopsis = !_fullSynopsis),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  synopsis,
                  maxLines: _fullSynopsis ? null : 4,
                  overflow: _fullSynopsis
                      ? TextOverflow.visible
                      : TextOverflow.ellipsis,
                  style: TextStyle(height: 1.6, color: colors.onSurfaceVariant),
                ),
                Text(
                  _fullSynopsis ? 'Show less' : 'Show more',
                  style: TextStyle(
                    color: colors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
      const SizedBox(height: 16),
      if (hasBook)
        Row(
          children: [
            Expanded(
              child: Text(
                loaded ? '${chapters.length} Chapters' : 'Chapters',
                style: text.titleLarge,
              ),
            ),
            IconButton(
              tooltip: _newestFirst ? 'Show oldest first' : 'Show newest first',
              icon: Icon(
                _newestFirst
                    ? CupertinoIcons.sort_down
                    : CupertinoIcons.sort_up,
              ),
              onPressed: () => setState(() => _newestFirst = !_newestFirst),
            ),
          ],
        ),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Details'),
        actions: [
          if (!novel.isLocal)
            IconButton(
              tooltip: 'Open source website',
              icon: const Icon(CupertinoIcons.globe),
              onPressed: () => openSource(context, url),
            ),
          menu,
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(side, 16, side, 0),
                sliver: SliverList.list(children: top),
              ),
              if (hasBook && !loaded)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CupertinoActivityIndicator()),
                  ),
                ),
              if (hasBook && loaded && chapters.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text("This book's chapter list couldn't be read."),
                  ),
                ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(side, 0, side, 48),
                sliver: DecoratedSliver(
                  decoration: BoxDecoration(
                    color: order.isEmpty ? null : palette.cell,
                    borderRadius: BorderRadius.circular(Radii.section),
                  ),
                  sliver: SliverList.builder(
                    itemCount: order.length,
                    itemBuilder: (context, i) {
                      final index = order[i];
                      final chapter = chapters[index];
                      final read = finished || index < current;
                      final here = index == current && !finished;
                      return ListTile(
                        key: ValueKey('chapter-$index'),
                        contentPadding: EdgeInsets.only(
                          left: 16 + chapter.depth * 16.0,
                          right: 16,
                        ),
                        title: Text(
                          chapter.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: read
                                ? FontWeight.w400
                                : FontWeight.w600,
                            color: read
                                ? colors.onSurface.withValues(alpha: .45)
                                : null,
                          ),
                        ),
                        subtitle: here
                            ? Text(
                                'Reading',
                                style: TextStyle(color: colors.primary),
                              )
                            : null,
                        trailing: here
                            ? Icon(
                                CupertinoIcons.bookmark_fill,
                                color: colors.primary,
                                size: 20,
                              )
                            : null,
                        onTap: () => _read(
                          novel,
                          chapter: chapter.chapter,
                          offset: chapter.offset,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _downloadCard(DownloadStatus status) {
    final colors = Theme.of(context).colorScheme;
    if (status.phase == DownloadPhase.failed) {
      return Card(
        child: ListTile(
          leading: Icon(
            CupertinoIcons.exclamationmark_circle,
            color: colors.error,
          ),
          title: const Text('Download stopped'),
          subtitle: Text(status.error ?? 'Something went wrong.'),
          trailing: TextButton(
            onPressed: () => widget.downloads?.enqueue(url),
            child: const Text('Retry'),
          ),
        ),
      );
    }
    final queued = status.phase == DownloadPhase.queued;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    queued
                        ? 'Waiting to download'
                        : 'Downloading · ${status.chapters} '
                              '${status.chapters == 1 ? 'chapter' : 'chapters'}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                TextButton(
                  onPressed: () => widget.downloads?.cancel(url),
                  child: const Text('Cancel'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const LinearProgressIndicator(),
            if (status.chapterTitle.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                status.chapterTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
