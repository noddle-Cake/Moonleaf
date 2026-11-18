part of '../library_screen.dart';

extension _SettingsTab on _LibraryScreenState {
  Future<void> _appearance() async {
    final choice = await showCupertinoModalPopup<AppAppearance>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('Appearance'),
        message: const Text(
          'E-reader modes use black and white, higher contrast and no '
          'animation, for e-paper screens.',
        ),
        actions: [
          for (final entry in appearanceLabels.entries)
            CupertinoActionSheetAction(
              key: Key('appearance-${entry.key.name}'),
              isDefaultAction: store.appearance == entry.key,
              onPressed: () => Navigator.pop(context, entry.key),
              child: Text(entry.value),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ),
    );
    if (choice != null) await _save(store.setAppearance(theme: choice));
  }

  Widget _settingsTab() {
    final p = Palette.of(context);
    return _page(
      title: 'Settings',
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Image.asset(
                    'assets/icon.png',
                    width: 76,
                    height: 76,
                    errorBuilder: (_, _, _) => Icon(
                      CupertinoIcons.book_fill,
                      size: 64,
                      color: p.accent,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Moonleaf',
                  style: TextStyles.title2.copyWith(
                    color: p.label,
                    fontFamily: 'Fraunces',
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'A home for your web novels',
                  style: TextStyles.subheadline.copyWith(
                    color: p.secondaryLabel,
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: GroupedSection(
            header: 'Display',
            children: [
              GroupedRow(
                icon: CupertinoIcons.circle_lefthalf_fill,
                title: 'Appearance',
                value: appearanceLabels[store.appearance],
                chevron: true,
                onTap: _appearance,
              ),
              SwitchRow(
                title: 'Show Library as Grid',
                value: store.grid,
                onChanged: (v) => _save(store.setAppearance(grid: v)),
              ),
              SwitchRow(
                title: 'Sort Library by Title',
                subtitle: store.sortByTitle ? null : 'Newest additions first',
                value: store.sortByTitle,
                onChanged: (v) => _save(store.setAppearance(sortByTitle: v)),
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: GroupedSection(
            header: 'Books',
            footer:
                'Reader settings, such as fonts, page colors and buttons, are '
                'in the reader: tap the bottom of a page.',
            children: [
              GroupedRow(
                icon: CupertinoIcons.add_circled,
                title: 'Add a Novel by Link',
                chevron: true,
                onTap: _add,
              ),
              GroupedRow(
                icon: CupertinoIcons.doc,
                title: 'Open an EPUB File',
                chevron: true,
                onTap: () => importEpub(context, store),
              ),
              GroupedRow(
                icon: CupertinoIcons.arrow_down_doc,
                title: 'Create an EPUB',
                subtitle: 'Customize the title, cover and first chapter',
                chevron: true,
                onTap: _export,
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: GroupedSection(
            header: 'About',
            footer:
                'Your library stays on this device. No account, ads or '
                'tracking.',
            children: [
              GroupedRow(
                icon: CupertinoIcons.heart,
                title: 'Inspired by Mihon',
                subtitle: 'Library and novel pages',
                trailing: Icon(
                  CupertinoIcons.arrow_up_right,
                  size: 16,
                  color: p.tertiaryLabel,
                ),
                onTap: () =>
                    openSource(context, 'https://github.com/mihonapp/mihon'),
              ),
              GroupedRow(
                icon: CupertinoIcons.book,
                title: 'Reader Inspired by KOReader',
                subtitle: 'Typesetting, menus and statistics',
                trailing: Icon(
                  CupertinoIcons.arrow_up_right,
                  size: 16,
                  color: p.tertiaryLabel,
                ),
                onTap: () =>
                    openSource(context, 'https://github.com/koreader/koreader'),
              ),
              GroupedRow(
                icon: CupertinoIcons.doc_text,
                title: 'Open-Source Licenses',
                chevron: true,
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'Moonleaf',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
