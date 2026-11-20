part of '../library_screen.dart';

extension _ReadingTab on _LibraryScreenState {
  Widget _readingTab() {
    final opened = store.novels.where((n) => n.openedAt != null).toList()
      ..sort((a, b) => b.openedAt!.compareTo(a.openedAt!));
    final inProgress = [
      for (final n in opened)
        if ((n.progress ?? 0) > 0.001 && (n.progress ?? 0) < .999) n,
    ];
    final finished = [
      for (final n in opened)
        if ((n.progress ?? 0) >= .999) n,
    ];
    final recent = [
      for (final n in opened)
        if ((n.progress ?? 0) <= 0.001) n,
    ];
    String date(LibraryNovel n) =>
        MaterialLocalizations.of(context).formatMediumDate(n.openedAt!);
    Widget resume(LibraryNovel n) => IconButton(
      tooltip: 'Resume ${n.title}',
      icon: const Icon(CupertinoIcons.play_circle_fill, size: 30),
      onPressed: () =>
          readNovel(context, store, n, downloads: widget.downloads),
    );
    return _page(
      title: 'Reading',
      slivers: [
        if (opened.isEmpty)
          _empty(
            icon: CupertinoIcons.book,
            title: 'Every story leaves a trail',
            message:
                'Books you open appear here with your progress, so you can '
                'pick up where you left off.',
          )
        else ...[
          if (inProgress.isNotEmpty)
            SliverToBoxAdapter(
              child: GroupedSection(
                header: 'Continue Reading',
                children: [
                  for (final n in inProgress)
                    _row(
                      n,
                      subtitle: '${(n.progress! * 100).round()}% · ${date(n)}',
                      progress: n.progress,
                      trailing: n.epub == null ? null : resume(n),
                    ),
                ],
              ),
            ),
          if (recent.isNotEmpty)
            SliverToBoxAdapter(
              child: GroupedSection(
                header: 'Recently Opened',
                children: [
                  for (final n in recent)
                    _row(n, subtitle: '${n.source} · ${date(n)}'),
                ],
              ),
            ),
          if (finished.isNotEmpty)
            SliverToBoxAdapter(
              child: GroupedSection(
                header: 'Finished',
                children: [
                  for (final n in finished)
                    _row(n, subtitle: '${n.source} · ${date(n)}'),
                ],
              ),
            ),
        ],
      ],
    );
  }
}
