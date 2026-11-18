part of '../library_screen.dart';

const _sources = [
  (
    'Royal Road',
    'Original fiction and web novels',
    'https://www.royalroad.com',
  ),
  ('Scribble Hub', 'Original web novels', 'https://www.scribblehub.com'),
  (
    'FanFiction.net',
    'Fan fiction and FictionPress',
    'https://www.fanfiction.net',
  ),
  ('AO3', 'Archive of Our Own, using its EPUBs', 'https://archiveofourown.org'),
  (
    'Standard Ebooks',
    'Free public-domain classics',
    'https://standardebooks.org',
  ),
  ('RoliaScan', 'Translated light novels', 'https://roliascan.com'),
];

extension _SearchTab on _LibraryScreenState {
  Widget _searchTab() {
    final p = Palette.of(context);
    final side = Space.margin(MediaQuery.sizeOf(context).width);
    final query = _globalSearch.text.trim();
    final uri = Uri.tryParse(query);
    final isLink =
        uri != null &&
        {'http', 'https'}.contains(uri.scheme) &&
        uri.host.isNotEmpty;
    final matches = query.isEmpty || isLink
        ? const <LibraryNovel>[]
        : store.novels
              .where(
                (n) => '${n.title} ${n.author}'.toLowerCase().contains(
                  query.toLowerCase(),
                ),
              )
              .toList();
    final browser = browserSupported;
    return _page(
      title: 'Search',
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(side, 4, side, 20),
            child: CupertinoSearchTextField(
              key: const Key('global-search'),
              controller: _globalSearch,
              placeholder: 'Your library, or paste a link',
              style: TextStyles.body.copyWith(color: p.label),
              onChanged: (_) => _rebuild(),
              onSubmitted: (_) {
                if (isLink) _add(query);
              },
            ),
          ),
        ),
        if (isLink)
          SliverToBoxAdapter(
            child: GroupedSection(
              children: [
                GroupedRow(
                  icon: CupertinoIcons.add_circled_solid,
                  title: 'Add This Link',
                  subtitle: uri.host,
                  chevron: true,
                  onTap: () => _add(query),
                ),
              ],
            ),
          )
        else if (query.isNotEmpty)
          matches.isEmpty
              ? SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      'No books in your library match “$query”.',
                      textAlign: TextAlign.center,
                      style: TextStyles.body.copyWith(color: p.secondaryLabel),
                    ),
                  ),
                )
              : SliverToBoxAdapter(
                  child: GroupedSection(
                    header: 'In Your Library',
                    children: [for (final n in matches) _row(n)],
                  ),
                )
        else ...[
          SliverToBoxAdapter(
            child: GroupedSection(
              children: [
                GroupedRow(
                  icon: CupertinoIcons.link,
                  title: 'Add a Novel by Link',
                  subtitle: 'A story page or any chapter',
                  chevron: true,
                  onTap: _add,
                ),
                GroupedRow(
                  icon: CupertinoIcons.doc,
                  title: 'Open an EPUB File',
                  chevron: true,
                  onTap: () => importEpub(context, store),
                ),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: GroupedSection(
              header: 'Sources',
              footer:
                  'Find a story on one of these sites, then paste its link. '
                  '${browser ? 'Scribble Hub and FanFiction.net may ask you to confirm you’re human.' : 'Scribble Hub and FanFiction.net need the Android, iOS or macOS app.'} '
                  'Only publicly readable text stories are supported.',
              children: [
                for (final (name, about, site) in _sources)
                  GroupedRow(
                    title: name,
                    subtitle: about,
                    trailing: Icon(
                      CupertinoIcons.arrow_up_right,
                      size: 16,
                      color: p.tertiaryLabel,
                    ),
                    onTap: () => openSource(context, site),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
