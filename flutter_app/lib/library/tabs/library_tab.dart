part of '../library_screen.dart';

extension _LibraryTab on _LibraryScreenState {
  Widget _libraryTab() {
    final p = Palette.of(context);
    final query = _search.text.trim().toLowerCase();
    final novels =
        store.novels
            .where(
              (n) =>
                  (_shelf == 'All' || n.shelf == _shelf) &&
                  '${n.title} ${n.author} ${n.source}'.toLowerCase().contains(
                    query,
                  ),
            )
            .toList()
          ..sort(
            store.sortByTitle
                ? (a, b) =>
                      a.title.toLowerCase().compareTo(b.title.toLowerCase())
                : (a, b) => b.addedAt.compareTo(a.addedAt),
          );
    final width = MediaQuery.sizeOf(context).width;
    final side = Space.margin(width);
    return _page(
      title: 'Library',
      actions: [
        IconButton(
          tooltip: 'Add a novel',
          icon: const Icon(CupertinoIcons.add),
          onPressed: _add,
        ),
        PopupMenuButton<String>(
          tooltip: 'Library options',
          icon: const Icon(CupertinoIcons.ellipsis_circle),
          onSelected: (v) => switch (v) {
            'grid' => _save(store.setAppearance(grid: !store.grid)),
            'sort' => _save(
              store.setAppearance(sortByTitle: !store.sortByTitle),
            ),
            'import' => importEpub(context, store),
            _ => null,
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'grid',
              child: ListTile(
                leading: Icon(
                  store.grid
                      ? CupertinoIcons.list_bullet
                      : CupertinoIcons.square_grid_2x2,
                ),
                title: Text(store.grid ? 'Show as List' : 'Show as Grid'),
              ),
            ),
            PopupMenuItem(
              value: 'sort',
              child: ListTile(
                leading: const Icon(CupertinoIcons.arrow_up_arrow_down),
                title: Text(
                  store.sortByTitle ? 'Sort by Date Added' : 'Sort by Title',
                ),
              ),
            ),
            const PopupMenuItem(
              value: 'import',
              child: ListTile(
                leading: Icon(CupertinoIcons.doc),
                title: Text('Open an EPUB File'),
              ),
            ),
          ],
        ),
      ],
      slivers: [
        if (store.novels.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(side, 4, side, 8),
              child: CupertinoSearchTextField(
                key: const Key('library-search'),
                controller: _search,
                placeholder: 'Titles, authors and sources',
                style: TextStyles.body.copyWith(color: p.label),
                onChanged: (_) => _rebuild(),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(horizontal: side, vertical: 6),
                children: [
                  for (final s in ['All', ...shelves])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        showCheckmark: false,
                        label: Text(
                          '$s  ${s == 'All' ? store.novels.length : store.novels.where((n) => n.shelf == s).length}',
                        ),
                        selected: _shelf == s,
                        onSelected: (_) {
                          _shelf = s;
                          _rebuild();
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
        if (novels.isEmpty)
          _empty(
            icon: CupertinoIcons.book,
            title: store.novels.isEmpty
                ? 'Your next story starts here'
                : 'Nothing here yet',
            message: store.novels.isEmpty
                ? 'Add a novel from a supported site, or open an EPUB file '
                      'you already have.'
                : query.isNotEmpty
                ? 'Try another title, author or source.'
                : 'Long-press a book to move it to this shelf.',
            action: store.novels.isEmpty ? 'Browse Sources' : null,
            onAction: () => _go(_Tab.search),
          )
        // At very large text sizes covers can't fit their captions, so the
        // library uses the list layout (Apple's Dynamic Type guidance).
        else if (store.grid &&
            MediaQuery.textScalerOf(context).scale(10) / 10 <= 1.35)
          SliverPadding(
            padding: EdgeInsets.fromLTRB(side, 8, side, 0),
            sliver: SliverGrid.builder(
              key: const Key('library-grid'),
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                // Two columns on slim phones, more as space allows.
                maxCrossAxisExtent: width < 400 ? (width - side * 2) / 2 : 180,
                crossAxisSpacing: 14,
                mainAxisSpacing: 18,
                childAspectRatio: .62,
              ),
              itemCount: novels.length,
              itemBuilder: (context, i) => _cover(novels[i]),
            ),
          )
        else
          SliverList.builder(
            itemCount: novels.length,
            itemBuilder: (context, i) => _row(
              novels[i],
              subtitle: [
                novels[i].source,
                novels[i].shelf,
                if ((novels[i].progress ?? 0) > 0.001)
                  '${(novels[i].progress! * 100).round()}% read',
              ].join(' · '),
            ),
          ),
      ],
    );
  }

  Widget _cover(LibraryNovel novel) {
    final p = Palette.of(context);
    final status = widget.downloads?.statusOf(novel.url);
    return Semantics(
      button: true,
      label: 'Open ${novel.title}',
      child: GestureDetector(
        key: ValueKey(novel.url),
        onTap: () => _open(novel),
        onLongPress: () => _actions(novel),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  NovelCover(novel: novel),
                  if (status != null)
                    Positioned(top: 8, right: 8, child: _DownloadBadge(status)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              novel.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyles.footnote.copyWith(
                color: p.label,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              (novel.progress ?? 0) > 0.001
                  ? '${(novel.progress! * 100).round()}%'
                  : novel.author.isEmpty
                  ? novel.source
                  : novel.author,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyles.caption1.copyWith(color: p.secondaryLabel),
            ),
          ],
        ),
      ),
    );
  }
}
