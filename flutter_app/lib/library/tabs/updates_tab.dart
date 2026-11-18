part of '../library_screen.dart';

extension _UpdatesTab on _LibraryScreenState {
  String _when(DateTime time) {
    final now = DateTime.now();
    final day = DateTime(time.year, time.month, time.day);
    final today = DateTime(now.year, now.month, now.day);
    final days = today.difference(day).inDays;
    if (days == 0) return 'Today';
    if (days == 1) return 'Yesterday';
    return MaterialLocalizations.of(context).formatMediumDate(time);
  }

  Widget _updatesTab() {
    final downloads = widget.downloads;
    final active = [
      for (final n in store.novels)
        if (downloads?.statusOf(n.url) case final status?) (n, status),
    ];
    final updated =
        store.novels
            .where(
              (n) => n.updatedAt != null && downloads?.statusOf(n.url) == null,
            )
            .toList()
          ..sort((a, b) => b.updatedAt!.compareTo(a.updatedAt!));
    final checkable = store.novels.any((n) => !n.isLocal && n.epub != null);
    void checkAll() {
      final queued = downloads?.checkAll() ?? 0;
      _say(
        queued == 0
            ? 'Everything is already being checked.'
            : 'Checking $queued ${queued == 1 ? 'book' : 'books'} for new chapters',
      );
    }

    return _page(
      title: 'Updates',
      actions: [
        if (downloads != null && checkable)
          IconButton(
            tooltip: 'Check for new chapters',
            icon: const Icon(CupertinoIcons.arrow_clockwise),
            onPressed: checkAll,
          ),
      ],
      slivers: [
        if (active.isEmpty && updated.isEmpty)
          _empty(
            icon: CupertinoIcons.bell,
            title: 'No updates yet',
            message: checkable
                ? 'Check your books for newly released chapters. New chapters '
                      'are added to the books you already have.'
                : 'Books you download from a website appear here when they '
                      'get new chapters.',
            action: downloads != null && checkable
                ? 'Check for New Chapters'
                : null,
            onAction: checkAll,
          )
        else ...[
          if (active.isNotEmpty)
            SliverToBoxAdapter(
              child: GroupedSection(
                header: 'Downloading',
                children: [
                  for (final (novel, status) in active)
                    _row(
                      novel,
                      subtitle: switch (status.phase) {
                        DownloadPhase.queued => 'Waiting',
                        DownloadPhase.running =>
                          '${status.chapters} ${status.chapters == 1 ? 'chapter' : 'chapters'}',
                        DownloadPhase.failed =>
                          status.error ?? 'The download stopped.',
                      },
                      progress: status.phase == DownloadPhase.queued ? 0 : null,
                      busy: status.phase == DownloadPhase.running,
                      trailing: status.phase == DownloadPhase.failed
                          ? TextButton(
                              onPressed: () => downloads?.enqueue(novel.url),
                              child: const Text('Retry'),
                            )
                          : IconButton(
                              tooltip: 'Cancel download',
                              icon: const Icon(CupertinoIcons.xmark_circle),
                              onPressed: () => downloads?.cancel(novel.url),
                            ),
                    ),
                ],
              ),
            ),
          if (updated.isNotEmpty)
            SliverToBoxAdapter(
              child: GroupedSection(
                header: 'Recently Updated',
                children: [
                  for (final novel in updated.take(50))
                    _row(
                      novel,
                      subtitle: [
                        if (novel.newChapters > 0)
                          '${novel.newChapters} new ${novel.newChapters == 1 ? 'chapter' : 'chapters'}'
                        else if (novel.chapterCount != null)
                          '${novel.chapterCount} chapters',
                        _when(novel.updatedAt!),
                      ].join(' · '),
                    ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}
