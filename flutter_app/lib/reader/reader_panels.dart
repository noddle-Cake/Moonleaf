part of 'reader_screen.dart';

extension _Panels on _ReaderScreenState {
  void _refresh() => _rebuild();

  // ---------------------------------------------------------------------------
  // Typesetting, theme, controls and status bar (KOReader's bottom menu).

  Future<void> _typeset({int tab = 0}) async {
    _setMenu(false);
    final settings = s;
    await showModalBottomSheet<void>(
      context: _ctx,
      isScrollControlled: true,
      showDragHandle: true,
      barrierColor: Colors.black12,
      constraints: const BoxConstraints(maxWidth: 720),
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .52,
        child: DefaultTabController(
          length: 5,
          initialIndex: tab,
          child: ListenableBuilder(
            listenable: settings,
            builder: (context, _) => Column(
              children: [
                const TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.center,
                  tabs: [
                    Tab(text: 'Text'),
                    Tab(text: 'Layout'),
                    Tab(text: 'Theme'),
                    Tab(text: 'Controls'),
                    Tab(text: 'Status bar'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _textTab(settings),
                      _layoutTab(settings),
                      _themeTab(settings),
                      _controlsTab(settings),
                      _statusTab(settings),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _panel(List<Widget> children) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
    children: children,
  );

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 6),
    child: Text(
      text.toUpperCase(),
      style: Theme.of(_ctx).textTheme.labelMedium?.copyWith(letterSpacing: 1.3),
    ),
  );

  Widget _textTab(ReaderSettings settings) => _panel([
    _heading('Font'),
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final entry in builtInFonts.entries)
          ChoiceChip(
            label: Text(
              entry.value.label,
              style: TextStyle(
                fontFamily: entry.value.family,
                fontFamilyFallback: entry.value.fallback,
              ),
            ),
            selected: settings.font == entry.key,
            onSelected: (_) => settings.update((s) => s.font = entry.key),
          ),
        for (final name in settings.customFonts.keys)
          InputChip(
            label: Text(name, style: TextStyle(fontFamily: name)),
            selected: settings.font == 'custom:$name',
            onSelected: (_) => settings.update((s) => s.font = 'custom:$name'),
            onDeleted: () => settings.update((s) {
              s.customFonts.remove(name);
              if (s.font == 'custom:$name') s.font = 'serif';
            }),
          ),
        if (persistentBooks)
          ActionChip(
            avatar: const Icon(Icons.add, size: 18),
            label: const Text('Add font file'),
            onPressed: () => _addFont(settings),
          ),
      ],
    ),
    _Stepper(
      label: 'Font size',
      value: settings.fontSize,
      min: 10,
      max: 48,
      step: 1,
      format: (v) => v.toStringAsFixed(0),
      onChanged: (v) => settings.update((s) => s.fontSize = v),
    ),
    _Stepper(
      label: 'Font weight',
      value: settings.fontWeight.toDouble(),
      min: 300,
      max: 800,
      step: 50,
      format: (v) => v == 400
          ? 'Regular'
          : v < 400
          ? 'Lighter (${v.round()})'
          : 'Bolder (${v.round()})',
      onChanged: (v) => settings.update((s) => s.fontWeight = v.round()),
    ),
    _Stepper(
      label: 'Line spacing',
      value: settings.lineHeight,
      min: 1,
      max: 2.6,
      step: .05,
      format: (v) => '${(v * 100).round()}%',
      onChanged: (v) => settings.update((s) => s.lineHeight = v),
      presets: const {'Tight': 1.25, 'Normal': 1.5, 'Loose': 1.8},
    ),
    _Stepper(
      label: 'Word spacing',
      value: settings.wordSpacing,
      min: -3,
      max: 12,
      step: .5,
      format: (v) => v == 0 ? 'Default' : '${v > 0 ? '+' : ''}$v',
      onChanged: (v) => settings.update((s) => s.wordSpacing = v),
    ),
    _Stepper(
      label: 'Letter spacing',
      value: settings.letterSpacing,
      min: -1,
      max: 4,
      step: .1,
      format: (v) => v.abs() < .05
          ? 'Default'
          : '${v > 0 ? '+' : ''}${v.toStringAsFixed(1)}',
      onChanged: (v) => settings.update((s) => s.letterSpacing = v),
    ),
  ]);

  Widget _layoutTab(ReaderSettings settings) => _panel([
    _heading('View mode'),
    SegmentedButton<ReaderView>(
      segments: const [
        ButtonSegment(
          value: ReaderView.paged,
          icon: Icon(Icons.auto_stories_outlined),
          label: Text('Pages'),
        ),
        ButtonSegment(
          value: ReaderView.scroll,
          icon: Icon(Icons.swap_vert),
          label: Text('Continuous'),
        ),
      ],
      selected: {settings.view},
      onSelectionChanged: (v) => settings.update((s) => s.view = v.first),
    ),
    _heading('Alignment'),
    SegmentedButton<TextAlignment>(
      segments: const [
        ButtonSegment(
          value: TextAlignment.justify,
          icon: Icon(Icons.format_align_justify),
          label: Text('Justified'),
        ),
        ButtonSegment(
          value: TextAlignment.left,
          icon: Icon(Icons.format_align_left),
          label: Text('Ragged'),
        ),
      ],
      selected: {settings.align},
      onSelectionChanged: (v) => settings.update((s) => s.align = v.first),
    ),
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text("Use the book's alignment"),
      subtitle: const Text('Keep centered headings, captions and scene breaks'),
      value: settings.publisherAlignment,
      onChanged: (v) => settings.update((s) => s.publisherAlignment = v),
    ),
    _Stepper(
      label: 'First-line indent',
      value: settings.indent,
      min: 0,
      max: 4,
      step: .5,
      format: (v) => v == 0 ? 'None' : '${v}em',
      onChanged: (v) => settings.update((s) => s.indent = v),
    ),
    _Stepper(
      label: 'Paragraph spacing',
      value: settings.paragraphSpacing,
      min: 0,
      max: 2,
      step: .1,
      format: (v) => v == 0 ? 'None' : '${v.toStringAsFixed(1)}em',
      onChanged: (v) => settings.update((s) => s.paragraphSpacing = v),
    ),
    _Stepper(
      label: 'Side margins',
      value: settings.marginSide,
      min: 0,
      max: 120,
      step: 2,
      format: (v) => v.toStringAsFixed(0),
      onChanged: (v) => settings.update((s) => s.marginSide = v),
    ),
    _Stepper(
      label: 'Top margin',
      value: settings.marginTop,
      min: 0,
      max: 120,
      step: 2,
      format: (v) => v.toStringAsFixed(0),
      onChanged: (v) => settings.update((s) => s.marginTop = v),
    ),
    _Stepper(
      label: 'Bottom margin',
      value: settings.marginBottom,
      min: 0,
      max: 120,
      step: 2,
      format: (v) => v.toStringAsFixed(0),
      onChanged: (v) => settings.update((s) => s.marginBottom = v),
    ),
  ]);

  Widget _themeTab(ReaderSettings settings) {
    Widget swatch(String key, String label, Color bg, Color fg) {
      final selected = settings.palette == key;
      return Semantics(
        button: true,
        selected: selected,
        label: '$label theme',
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => settings.update((s) => s.palette = key),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 58,
                height: 58,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    width: selected ? 3 : 1,
                    color: selected
                        ? Theme.of(_ctx).colorScheme.primary
                        : Theme.of(_ctx).colorScheme.outlineVariant,
                  ),
                ),
                child: Text(
                  'Aa',
                  style: TextStyle(
                    color: fg,
                    fontFamily: 'Fraunces',
                    fontSize: 20,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(label, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      );
    }

    final dark = Theme.of(_ctx).brightness == Brightness.dark;
    return _panel([
      _heading('Page color'),
      Wrap(
        spacing: 14,
        runSpacing: 14,
        children: [
          swatch(
            'app',
            'Match app',
            dark
                ? readerPalettes['dusk']!.background
                : readerPalettes['paper']!.background,
            dark ? readerPalettes['dusk']!.text : readerPalettes['paper']!.text,
          ),
          for (final e in readerPalettes.entries)
            swatch(e.key, e.value.label, e.value.background, e.value.text),
        ],
      ),
      _heading('Page turns'),
      SegmentedButton<PageAnimation>(
        segments: const [
          ButtonSegment(value: PageAnimation.none, label: Text('Instant')),
          ButtonSegment(value: PageAnimation.slide, label: Text('Slide')),
          ButtonSegment(value: PageAnimation.fade, label: Text('Fade')),
        ],
        selected: {settings.animation},
        onSelectionChanged: (v) =>
            settings.update((s) => s.animation = v.first),
      ),
      const SizedBox(height: 4),
      Text(
        'E-ink themes always turn pages instantly to avoid ghosting.',
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(_ctx).colorScheme.onSurfaceVariant,
        ),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Invert images in dark themes'),
        value: settings.invertImages,
        onChanged: (v) => settings.update((s) => s.invertImages = v),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Full screen'),
        subtitle: const Text('Hide system bars while reading'),
        value: settings.fullscreen,
        onChanged: (v) => settings.update((s) => s.fullscreen = v),
      ),
    ]);
  }

  Widget _controlsTab(ReaderSettings settings) => _panel([
    _heading('Tap zones'),
    RadioGroup<TapLayout>(
      groupValue: settings.tapLayout,
      onChanged: (v) => settings.update((s) => s.tapLayout = v!),
      child: const Column(
        children: [
          RadioListTile(
            contentPadding: EdgeInsets.zero,
            value: TapLayout.standard,
            title: Text('Left goes back, right goes forward'),
          ),
          RadioListTile(
            contentPadding: EdgeInsets.zero,
            value: TapLayout.inverted,
            title: Text('Left-handed (mirrored)'),
          ),
          RadioListTile(
            contentPadding: EdgeInsets.zero,
            value: TapLayout.forwardAnywhere,
            title: Text('Tap anywhere to go forward'),
            subtitle: Text('Only the far left edge goes back'),
          ),
        ],
      ),
    ),
    _Stepper(
      label: 'Back zone width',
      value: settings.backZone,
      min: .15,
      max: .5,
      step: .05,
      format: (v) => '${(v * 100).round()}% of the screen',
      onChanged: (v) => settings.update((s) => s.backZone = v),
    ),
    Text(
      'Tap the top of the page for the menu and the bottom for typesetting.',
      style: TextStyle(
        fontSize: 12,
        color: Theme.of(_ctx).colorScheme.onSurfaceVariant,
      ),
    ),
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Swipe to turn pages'),
      value: settings.swipe,
      onChanged: (v) => settings.update((s) => s.swipe = v),
    ),
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Pinch to change font size'),
      value: settings.pinch,
      onChanged: (v) => settings.update((s) => s.pinch = v),
    ),
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Keyboard and volume keys turn pages'),
      subtitle: const Text('Arrows, Page Up/Down and Space'),
      value: settings.keys,
      onChanged: (v) => settings.update((s) => s.keys = v),
    ),
  ]);

  Widget _statusTab(ReaderSettings settings) => _panel([
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Chapter title at the top'),
      value: settings.header,
      onChanged: (v) => settings.update((s) => s.header = v),
    ),
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Status bar'),
      value: settings.footer,
      onChanged: (v) => settings.update((s) => s.footer = v),
    ),
    _heading('Status bar items'),
    for (final item in FooterItem.values)
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(item.label),
        value: settings.footerItems.contains(item),
        onChanged: settings.footer
            ? (v) => settings.update(
                (s) => v == true
                    ? s.footerItems.add(item)
                    : s.footerItems.remove(item),
              )
            : null,
      ),
    const SizedBox(height: 16),
    OutlinedButton.icon(
      onPressed: settings.reset,
      icon: const Icon(Icons.restart_alt),
      label: const Text('Reset all reader settings'),
    ),
  ]);

  Future<void> _addFont(ReaderSettings settings) async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['ttf', 'otf'],
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final name = file.name.replaceFirst(
        RegExp(r'\.(ttf|otf)$', caseSensitive: false),
        '',
      );
      final loader = FontLoader(name)
        ..addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
      final path = await saveFont(file.name, bytes);
      settings.update((s) {
        s.customFonts[name] = path;
        s.font = 'custom:$name';
      });
    } catch (_) {
      _toast('That font could not be added.');
    }
  }

  // ---------------------------------------------------------------------------
  // Contents, bookmarks and highlights.

  Future<void> _navigate(int tab) async {
    _setMenu(false);
    final state = _state!;
    final current = doc.toc.lastIndexWhere(
      (t) =>
          t.chapter < _chapter ||
          (t.chapter == _chapter && t.offset <= _offset),
    );
    await showModalBottomSheet<void>(
      context: _ctx,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 720),
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .82,
        child: DefaultTabController(
          length: 3,
          initialIndex: tab,
          child: StatefulBuilder(
            builder: (context, setSheet) => Column(
              children: [
                TabBar(
                  tabs: [
                    const Tab(text: 'Contents'),
                    Tab(text: 'Bookmarks (${state.bookmarks.length})'),
                    Tab(text: 'Highlights (${state.highlights.length})'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      ListView.builder(
                        controller: ScrollController(
                          initialScrollOffset: math.max(0, current - 3) * 52.0,
                        ),
                        itemCount: doc.toc.length,
                        itemExtent: 52,
                        itemBuilder: (context, i) {
                          final t = doc.toc[i];
                          final here = i == current;
                          return ListTile(
                            selected: here,
                            contentPadding: EdgeInsets.only(
                              left: 20 + t.depth * 18.0,
                              right: 20,
                            ),
                            title: Text(
                              t.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: here ? FontWeight.w700 : null,
                              ),
                            ),
                            trailing: _counted
                                ? Text('${_bookPageAt(t.chapter, t.offset)}')
                                : null,
                            onTap: () {
                              Navigator.pop(context);
                              _goTo(t.chapter, t.offset);
                            },
                          );
                        },
                      ),
                      state.bookmarks.isEmpty
                          ? _emptyNote(
                              Icons.bookmark_border,
                              'No bookmarks yet',
                              'Tap the bookmark icon in the menu to mark a page.',
                            )
                          : ListView(
                              children: [
                                for (final b in state.bookmarks)
                                  ListTile(
                                    leading: const Icon(Icons.bookmark),
                                    title: Text(
                                      b.snippet,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(
                                      '${doc.chapterTitle(b.chapter, b.offset)} · ${MaterialLocalizations.of(context).formatShortDate(b.created)}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: IconButton(
                                      tooltip: 'Delete bookmark',
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: () {
                                        setSheet(
                                          () => state.bookmarks.remove(b),
                                        );
                                        _refresh();
                                        _save();
                                      },
                                    ),
                                    onTap: () {
                                      Navigator.pop(context);
                                      _goTo(b.chapter, b.offset);
                                    },
                                  ),
                              ],
                            ),
                      state.highlights.isEmpty
                          ? _emptyNote(
                              Icons.border_color_outlined,
                              'No highlights yet',
                              'Long-press a word, drag to select more, then choose Highlight or Note.',
                            )
                          : ListView(
                              children: [
                                for (final h
                                    in state.highlights.toList()..sort(
                                      (a, b) => a.chapter != b.chapter
                                          ? a.chapter.compareTo(b.chapter)
                                          : a.start.compareTo(b.start),
                                    ))
                                  ListTile(
                                    leading: Container(
                                      width: 6,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: h.color == 'underline'
                                            ? Theme.of(_ctx).colorScheme.outline
                                            : highlightColors[h.color]!
                                                  .withValues(alpha: 1),
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                    ),
                                    title: Text(
                                      h.text,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(
                                      [
                                        if (h.note.isNotEmpty) '✎ ${h.note}',
                                        doc.chapterTitle(h.chapter, h.start),
                                      ].join('\n'),
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: IconButton(
                                      tooltip: 'Edit highlight',
                                      icon: const Icon(Icons.more_vert),
                                      onPressed: () async {
                                        await _editHighlight(h);
                                        setSheet(() {});
                                      },
                                    ),
                                    onTap: () {
                                      Navigator.pop(context);
                                      _goTo(h.chapter, h.start);
                                    },
                                  ),
                              ],
                            ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyNote(IconData icon, String title, String body) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: Theme.of(_ctx).colorScheme.primary),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(_ctx).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(body, textAlign: TextAlign.center),
        ],
      ),
    ),
  );

  Future<void> _highlight({bool note = false}) async {
    final sel = _selection;
    if (sel == null) return;
    final text = _selectedText;
    var body = '';
    if (note) {
      final value = await _noteDialog('');
      if (value == null) return;
      body = value;
    }
    final state = _state!;
    state.highlights.add(
      Highlight(sel.$1, sel.$2, sel.$3, text, DateTime.now(), note: body),
    );
    _selection = null;
    _refresh();
    _save();
  }

  Future<String?> _noteDialog(String initial) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: _ctx,
      builder: (context) => AlertDialog(
        title: const Text('Note'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: controller,
            autofocus: true,
            minLines: 3,
            maxLines: 8,
            decoration: const InputDecoration(hintText: 'Your thoughts…'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  Future<void> _editHighlight(Highlight h) async {
    await showModalBottomSheet<void>(
      context: _ctx,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '“${h.text}”',
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'Fraunces', height: 1.4),
                ),
                if (h.note.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('✎ ${h.note}'),
                ],
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  children: [
                    for (final e in highlightColors.entries)
                      ChoiceChip(
                        avatar: e.key == 'underline'
                            ? const Icon(Icons.format_underline, size: 18)
                            : CircleAvatar(
                                backgroundColor: e.value.withValues(alpha: 1),
                                radius: 7,
                              ),
                        label: Text(
                          e.key[0].toUpperCase() + e.key.substring(1),
                        ),
                        selected: h.color == e.key,
                        onSelected: (_) {
                          setSheet(() => h.color = e.key);
                          _refresh();
                          _save();
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: () async {
                        final note = await _noteDialog(h.note);
                        if (note == null) return;
                        setSheet(() => h.note = note);
                        _save();
                      },
                      icon: const Icon(Icons.edit_note),
                      label: Text(h.note.isEmpty ? 'Add note' : 'Edit note'),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: h.text));
                        Navigator.pop(context);
                        _toast('Copied');
                      },
                      icon: const Icon(Icons.copy),
                      label: const Text('Copy'),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        _state!.highlights.remove(h);
                        Navigator.pop(context);
                        _refresh();
                        _save();
                      },
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Delete'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _exportNotes() {
    final state = _state!;
    final buffer = StringBuffer('# ${doc.title}\n');
    if (doc.author.isNotEmpty) buffer.writeln('_${doc.author}_');
    String? last;
    final sorted = state.highlights.toList()
      ..sort(
        (a, b) => a.chapter != b.chapter
            ? a.chapter.compareTo(b.chapter)
            : a.start.compareTo(b.start),
      );
    for (final h in sorted) {
      final title = doc.chapterTitle(h.chapter, h.start);
      if (title != last) buffer.writeln('\n## $title\n');
      last = title;
      buffer.writeln('> ${h.text.replaceAll('\n', '\n> ')}');
      if (h.note.isNotEmpty) buffer.writeln('\n${h.note}');
      buffer.writeln();
    }
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    _toast('Copied ${sorted.length} highlights as Markdown');
  }

  // ---------------------------------------------------------------------------
  // Search, go to, links and look-up.

  Future<void> _search({String? initial}) async {
    _setMenu(false);
    final controller = TextEditingController(text: initial ?? _searchQuery);
    var matchCase = false;
    var results = <(int, int, int, String)>[];
    var truncated = false;
    void run(String query) {
      results = [];
      truncated = false;
      _searchQuery = query;
      if (query.trim().length < 2) return;
      final needle = matchCase ? query : query.toLowerCase();
      for (final c in doc.chapters) {
        final text = matchCase ? c.plainText : c.plainText.toLowerCase();
        var at = text.indexOf(needle);
        while (at >= 0) {
          final from = math.max(0, at - 40);
          final to = math.min(text.length, at + needle.length + 60);
          results.add((
            c.index,
            at,
            at + needle.length,
            '${from > 0 ? '…' : ''}${c.plainText.substring(from, to).replaceAll(RegExp(r'\s+'), ' ')}${to < text.length ? '…' : ''}',
          ));
          if (results.length >= 500) {
            truncated = true;
            return;
          }
          at = text.indexOf(needle, at + needle.length);
        }
      }
    }

    if (controller.text.isNotEmpty) run(controller.text);
    await showModalBottomSheet<void>(
      context: _ctx,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 720),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .8,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: TextField(
                    controller: controller,
                    autofocus: initial == null,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Search this book',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(
                        tooltip: 'Match case',
                        isSelected: matchCase,
                        icon: const Icon(Icons.text_fields),
                        onPressed: () => setSheet(() {
                          matchCase = !matchCase;
                          run(controller.text);
                        }),
                      ),
                    ),
                    onSubmitted: (v) => setSheet(() => run(v)),
                  ),
                ),
                if (controller.text.trim().length >= 2)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        results.isEmpty
                            ? 'No matches'
                            : '${results.length}${truncated ? '+' : ''} matches',
                        style: Theme.of(_ctx).textTheme.labelMedium,
                      ),
                    ),
                  ),
                Expanded(
                  child: ListView.builder(
                    itemCount: results.length,
                    itemBuilder: (context, i) {
                      final (chapter, start, end, snippet) = results[i];
                      return ListTile(
                        title: Text(snippet, maxLines: 3),
                        subtitle: Text(
                          doc.chapterTitle(chapter, start),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          _goTo(chapter, start, hit: (chapter, start, end));
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    controller.dispose();
  }

  Future<void> _goToDialog() async {
    final controller = TextEditingController();
    var byPage = _counted && !_scrollMode;
    final target = await showDialog<double>(
      context: _ctx,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('Go to'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_counted && !_scrollMode)
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('Page')),
                    ButtonSegment(value: false, label: Text('Percent')),
                  ],
                  selected: {byPage},
                  onSelectionChanged: (v) => setDialog(() => byPage = v.first),
                ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: byPage
                      ? 'Page (1–$_bookPages)'
                      : 'Percent (0–100)',
                ),
                onSubmitted: (v) =>
                    Navigator.pop(context, double.tryParse(v.trim())),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                double.tryParse(controller.text.trim()),
              ),
              child: const Text('Go'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (target == null) return;
    if (!byPage) {
      final (c, o) = doc.locate(target / 100);
      return _goTo(c, o);
    }
    var page = target.round().clamp(1, _bookPages) - 1;
    for (var c = 0; c < _counts.length; c++) {
      final count = _counts[c] ?? 0;
      if (page < count) {
        final layout = await _load(c);
        if (layout == null) return;
        return _goTo(
          c,
          layout.pages[page.clamp(0, layout.pages.length - 1)].start,
        );
      }
      page -= count;
    }
  }

  Future<void> _openLink(String href, LaidBlock from) async {
    final chapter = doc.chapters[_chapter];
    final target = doc.resolve(chapter.path, href);
    if (target == null) {
      final uri = Uri.tryParse(href);
      if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
        return;
      }
      final open = await showDialog<bool>(
        context: _ctx,
        builder: (context) => AlertDialog(
          title: const Text('Open link?'),
          content: Text(href),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Open in browser'),
            ),
          ],
        ),
      );
      if (open == true) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return;
    }
    final (c, o) = target;
    final text = doc.chapters[c].plainText;
    final start = o.clamp(0, text.length);
    var end = math.min(text.length, start + 700);
    final nextBreak = text.indexOf('\n', start + 1);
    if (nextBreak > 0 && nextBreak - start < 700) end = nextBreak;
    final excerpt = text.substring(start, end).trim();
    // Short targets read as footnotes: preview them in place, like KOReader.
    if (excerpt.isNotEmpty &&
        excerpt.length < 700 &&
        (c != _chapter || (o - _offset).abs() > 0)) {
      final go = await showModalBottomSheet<bool>(
        context: _ctx,
        showDragHandle: true,
        constraints: const BoxConstraints(maxWidth: 640),
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  doc.chapterTitle(c, o),
                  style: Theme.of(_ctx).textTheme.labelLarge,
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    child: Text(excerpt, style: const TextStyle(height: 1.5)),
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => Navigator.pop(context, true),
                    icon: const Icon(Icons.arrow_forward),
                    label: const Text('Go there'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      if (go != true) return;
    }
    await _goTo(c, o);
  }

  Future<void> _lookUp(String text, String kind) async {
    final query = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (query.isEmpty) return;
    final word = query.replaceAll(RegExp(r'''^[^\w]+|[^\w]+$'''), '');
    final lang = doc.language.split('-').first.toLowerCase();
    final wiki = RegExp(r'^[a-z]{2,3}$').hasMatch(lang) ? lang : 'en';
    final uri = switch (kind) {
      'dictionary' => Uri.https('en.wiktionary.org', '/wiki/Special:Search', {
        'search': word.contains(' ') ? word : word.toLowerCase(),
        'go': 'Go',
      }),
      'wikipedia' => Uri.https('$wiki.wikipedia.org', '/wiki/Special:Search', {
        'search': query,
      }),
      _ => Uri.https('translate.google.com', '/', {
        'sl': 'auto',
        'text': query,
        'op': 'translate',
      }),
    };
    _selection = null;
    _refresh();
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError('Cannot open');
      }
    } catch (_) {
      _toast('Could not open your browser.');
    }
  }

  // ---------------------------------------------------------------------------
  // Statistics and book information.

  Future<void> _stats() async {
    _setMenu(false);
    _record(forward: false);
    final state = _state!;
    final words = state.charsRead / 5.7;
    final wpm = state.seconds < 60 ? null : words / (state.seconds / 60);
    final position = doc.chapterStarts[_chapter] + _offset;
    final today = DateTime.now();
    final days = [
      for (var i = 13; i >= 0; i--) today.subtract(Duration(days: i)),
    ];
    String key(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final daily = [for (final d in days) state.daily[key(d)] ?? 0];
    final peak = daily.fold(60, math.max);
    String time(int secs) => _duration(secs / 60);
    await showModalBottomSheet<void>(
      context: _ctx,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 720),
      builder: (context) {
        final colors = Theme.of(_ctx).colorScheme;
        Widget stat(String value, String label) => SizedBox(
          width: 150,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: Theme.of(_ctx).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(label, style: TextStyle(color: colors.onSurfaceVariant)),
            ],
          ),
        );
        return SizedBox(
          height: MediaQuery.sizeOf(context).height * .75,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
            children: [
              Text(
                'Reading statistics',
                style: Theme.of(_ctx).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(doc.title, style: TextStyle(color: colors.onSurfaceVariant)),
              const SizedBox(height: 20),
              Wrap(
                spacing: 16,
                runSpacing: 20,
                children: [
                  stat('${(_shownProgress * 100).toStringAsFixed(1)}%', 'Read'),
                  stat(time(state.seconds), 'Time reading'),
                  stat(time(state.daily[key(today)] ?? 0), 'Today'),
                  stat(
                    wpm == null ? '—' : '${wpm.round()}',
                    'Words per minute',
                  ),
                  stat(
                    _duration((doc.length - position) / state.speed),
                    'Left in book',
                  ),
                  stat(
                    _duration(
                      (doc.chapters[_chapter].length - _offset) / state.speed,
                    ),
                    'Left in chapter',
                  ),
                  stat('${state.pagesTurned}', 'Pages turned'),
                  stat(
                    '${state.highlights.length} / ${state.bookmarks.length}',
                    'Highlights / bookmarks',
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Text('Last 14 days', style: Theme.of(_ctx).textTheme.titleMedium),
              const SizedBox(height: 12),
              SizedBox(
                height: 120,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < days.length; i++)
                      Expanded(
                        child: Tooltip(
                          message:
                              '${MaterialLocalizations.of(context).formatShortMonthDay(days[i])}: ${time(daily[i])}',
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Container(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 3,
                                ),
                                height: math.max(2, 92 * daily[i] / peak),
                                decoration: BoxDecoration(
                                  color: daily[i] == 0
                                      ? colors.outlineVariant
                                      : colors.primary,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                MaterialLocalizations.of(context)
                                    .narrowWeekdays[days[i].weekday % 7],
                                style: const TextStyle(fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              if (state.started != null)
                Text(
                  'Started ${MaterialLocalizations.of(context).formatMediumDate(state.started!)}'
                  '${state.finished != null ? ' · Finished ${MaterialLocalizations.of(context).formatMediumDate(state.finished!)}' : ''}',
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
              const SizedBox(height: 8),
              Text(
                'Time estimates use your own reading speed once you have read for a few minutes.',
                style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _info() async {
    final words = (doc.length / 5.7).round();
    await showDialog<void>(
      context: _ctx,
      builder: (context) {
        final cover = doc.cover;
        return AlertDialog(
          title: Text(doc.title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (cover != null)
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.memory(
                        cover,
                        height: 180,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                if (doc.author.isNotEmpty) Text('By ${doc.author}'),
                if (doc.language.isNotEmpty) Text('Language: ${doc.language}'),
                Text(
                  '${doc.chapters.length} sections · ${doc.toc.length} contents entries',
                ),
                Text(
                  'About ${(words / 1000).toStringAsFixed(words < 10000 ? 1 : 0)}k words',
                ),
                if (_counted)
                  Text('$_bookPages pages at your current settings'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }
}

/// A labeled value with −/+ buttons and a slider, applied when released.
class _Stepper extends StatefulWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.format,
    required this.onChanged,
    this.presets = const {},
  });
  final String label;
  final double value, min, max, step;
  final String Function(double) format;
  final ValueChanged<double> onChanged;
  final Map<String, double> presets;
  @override
  State<_Stepper> createState() => _StepperState();
}

class _StepperState extends State<_Stepper> {
  double? _drag;
  double _snap(double v) {
    final snapped = (v / widget.step).round() * widget.step;
    return double.parse(
      snapped.clamp(widget.min, widget.max).toStringAsFixed(3),
    );
  }

  @override
  Widget build(BuildContext context) {
    final value = _drag ?? widget.value;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.label,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Text(widget.format(value)),
            ],
          ),
          Row(
            children: [
              IconButton(
                tooltip: 'Decrease ${widget.label.toLowerCase()}',
                icon: const Icon(Icons.remove),
                onPressed: value <= widget.min
                    ? null
                    : () => widget.onChanged(_snap(value - widget.step)),
              ),
              Expanded(
                child: Slider(
                  value: value.clamp(widget.min, widget.max),
                  min: widget.min,
                  max: widget.max,
                  divisions: ((widget.max - widget.min) / widget.step).round(),
                  onChanged: (v) => setState(() => _drag = _snap(v)),
                  onChangeEnd: (v) {
                    setState(() => _drag = null);
                    widget.onChanged(_snap(v));
                  },
                ),
              ),
              IconButton(
                tooltip: 'Increase ${widget.label.toLowerCase()}',
                icon: const Icon(Icons.add),
                onPressed: value >= widget.max
                    ? null
                    : () => widget.onChanged(_snap(value + widget.step)),
              ),
            ],
          ),
          if (widget.presets.isNotEmpty)
            Wrap(
              spacing: 8,
              children: [
                for (final p in widget.presets.entries)
                  ChoiceChip(
                    label: Text(p.key),
                    selected: (value - p.value).abs() < .001,
                    onSelected: (_) => widget.onChanged(p.value),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
