import 'dart:async';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../platform/device.dart';
import '../theme.dart';
import '../ui/components.dart';
import '../ui/tokens.dart';
import 'book_files.dart';
import 'epub_document.dart';
import 'reader_settings.dart';
import 'typesetter.dart';

part 'reader_panels.dart';

/// Parses an EPUB and opens it in the reader. Returns false if it could not be
/// opened (an error message has been shown).
Future<bool> openReader(
  BuildContext context, {
  required String bookId,
  required Uint8List bytes,
  bool ereaderApp = false,
  void Function(double progress)? onProgress,
  int? chapter,
  int? offset,
  Stream<Uint8List>? updates,
  ValueListenable<bool>? downloading,
}) async {
  final EpubDocument document;
  try {
    document = await parseEpub(bytes);
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is FormatException
                ? error.message
                : 'This EPUB could not be opened.',
          ),
        ),
      );
    }
    return false;
  }
  if (!context.mounted) return false;
  await Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => ReaderScreen(
        bookId: bookId,
        document: document,
        ereaderApp: ereaderApp,
        onProgress: onProgress,
        initialChapter: chapter,
        initialOffset: offset,
        updates: updates,
        downloading: downloading,
      ),
    ),
  );
  return true;
}

/// Parses off the UI thread where isolates are available (not on the web).
Future<EpubDocument> parseEpub(Uint8List bytes) async {
  if (kIsWeb) return EpubDocument.parse(bytes);
  try {
    return await compute(EpubDocument.parse, bytes);
  } on FormatException {
    rethrow;
  } catch (_) {
    return EpubDocument.parse(bytes);
  }
}

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({
    super.key,
    required this.bookId,
    required this.document,
    this.settings,
    this.ereaderApp = false,
    this.onProgress,
    this.initialChapter,
    this.initialOffset,
    this.updates,
    this.downloading,
  });
  final String bookId;
  final EpubDocument document;

  /// Newer versions of the book while it downloads. The reader adds their
  /// chapters without losing the place.
  final Stream<Uint8List>? updates;

  /// Whether more chapters are on their way.
  final ValueListenable<bool>? downloading;
  final ReaderSettings? settings;
  final bool ereaderApp;
  final void Function(double progress)? onProgress;
  final int? initialChapter, initialOffset;
  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

typedef _Mark = (int, int, Color, bool);

class _ReaderScreenState extends State<ReaderScreen>
    with WidgetsBindingObserver {
  late EpubDocument _doc = widget.document;
  EpubDocument get doc => _doc;
  StreamSubscription<Uint8List>? _updates;
  Uint8List? _nextBytes;
  bool _parsing = false;

  /// More chapters are downloading.
  bool get _growing => widget.downloading?.value ?? false;
  ReaderSettings? _settings;
  BookState? _state;
  Typesetter? _ts;
  String _tsKey = '';
  int _gen = 0;

  /// Changes when pages are laid out again, to reset page transitions.
  int _view = 0;
  final _layouts = <int, ChapterLayout>{};
  final _pending = <int, Future<ChapterLayout?>>{};

  /// Pages per chapter, filled in the background for book page numbers.
  List<int?> _counts = [];
  int _chapter = 0, _offset = 0, _page = 0;
  bool _menu = false;
  int _direction = 1;

  /// Selected chapter range and whether the user is still dragging.
  (int, int, int)? _selection;
  int? _anchor;
  bool _selecting = false;
  (int, int, int)? _searchHit;
  (int, int)? _returnTo;
  int _movesSinceJump = 0;
  DateTime _shownAt = DateTime.now();
  Timer? _clock, _saveTimer;
  ScrollController? _scroll;
  String _scrollKey = '';
  double? _pinchBase, _pinchSize;
  Offset _swipe = Offset.zero;
  int _pointers = 0;
  final _area = GlobalKey();

  /// Context below the reader theme, so menus, sheets and dialogs use it.
  final _themed = GlobalKey();
  BuildContext get _ctx => _themed.currentContext ?? context;
  Rect _content = Rect.zero;
  EdgeInsets? _pagePad;
  String? _searchQuery;
  bool _systemUiHidden = false;

  ReaderSettings get s => _settings!;
  ChapterLayout? get _layout => _layouts[_chapter];
  bool get _scrollMode => s.view == ReaderView.scroll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _counts = List.filled(doc.chapters.length, null);
    _updates = widget.updates?.listen((bytes) {
      _nextBytes = bytes;
      _takeUpdate();
    });
    widget.downloading?.addListener(_rebuild);
    _init();
  }

  /// Parses the newest version of the book, one at a time.
  Future<void> _takeUpdate() async {
    if (_parsing) return;
    _parsing = true;
    try {
      while (_nextBytes != null && mounted) {
        final bytes = _nextBytes!;
        _nextBytes = null;
        try {
          final next = await parseEpub(bytes);
          if (mounted) _replaceDocument(next);
        } catch (_) {}
      }
    } finally {
      _parsing = false;
    }
  }

  /// Switches to a newer version of the book. Chapters keep their pages
  /// (layouts are reused), so the open page doesn't change or redraw, and
  /// the place, bookmarks and highlights follow their chapters.
  void _replaceDocument(EpubDocument next) {
    final old = [for (final c in doc.chapters) c.path];
    final paths = [for (final c in next.chapters) c.path];
    final index = {for (var i = 0; i < paths.length; i++) paths[i]: i};
    int? map(int c) => c >= 0 && c < old.length ? index[old[c]] : null;
    final layouts = <int, ChapterLayout>{};
    for (final entry in _layouts.entries) {
      final moved = map(entry.key);
      if (moved == null) {
        entry.value.dispose();
      } else {
        layouts[moved] = entry.value;
      }
    }
    final counts = List<int?>.filled(paths.length, null);
    for (var c = 0; c < _counts.length; c++) {
      if (map(c) case final moved?) counts[moved] = _counts[c];
    }
    final state = _state;
    if (state != null) {
      state
        ..chapter = _chapter
        ..offset = _offset;
      if (state.spine.isEmpty) state.spine = old;
      state.follow(paths);
    }
    final ts = _ts;
    setState(() {
      // Layouts being made for the old version are dropped.
      _gen++;
      _pending.clear();
      _layouts
        ..clear()
        ..addAll(layouts);
      _counts = counts;
      _doc = next;
      if (ts != null) _ts = Typesetter(next, s, ts.palette, ts.page);
      _chapter = map(_chapter) ?? _chapter.clamp(0, paths.length - 1);
      _selection = null;
      _searchHit = null;
      if (_returnTo case (final c, final o)?) {
        _returnTo = map(c) == null ? null : (map(c)!, o);
      }
    });
    if (_layouts[_chapter] == null) {
      _goTo(_chapter, _offset, remember: false);
    } else {
      _preload();
    }
    _countPages(_gen);
    if (state != null) _scheduleSave();
  }

  Future<void> _init() async {
    final settings = widget.settings ?? await ReaderSettings.load();
    final state = await BookState.load(widget.bookId);
    for (final entry in settings.customFonts.entries) {
      try {
        final bytes = await readFont(entry.value);
        if (bytes == null) continue;
        final loader = FontLoader(entry.key)
          ..addFont(Future.value(ByteData.sublistView(bytes)));
        await loader.load();
      } catch (_) {}
    }
    if (!mounted) return;
    // Follow chapters added before the saved place since it was saved.
    if (state.follow([for (final c in doc.chapters) c.path])) state.save();
    state.started ??= DateTime.now();
    final chapter = (widget.initialChapter ?? state.chapter).clamp(
      0,
      doc.chapters.length - 1,
    );
    setState(() {
      _settings = settings;
      _state = state;
      _chapter = chapter;
      _offset = widget.initialChapter != null
          ? widget.initialOffset ?? 0
          : state.offset;
    });
    settings.addListener(_settingsChanged);
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && s.footer) setState(() {});
    });
    _applySystemUi();
  }

  void _settingsChanged() {
    if (mounted) setState(() {});
    _applySystemUi();
  }

  void _applySystemUi() {
    if (!mounted || _settings == null) return;
    // On e-ink the system bars stay hidden with the menu open: showing them
    // redraws the whole screen.
    final hide = s.fullscreen && (!_menu || _eink);
    if (hide == _systemUiHidden) return;
    _systemUiHidden = hide;
    SystemChrome.setEnabledSystemUIMode(
      hide ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _record(forward: false);
      _save();
    } else if (state == AppLifecycleState.resumed) {
      _shownAt = DateTime.now();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _updates?.cancel();
    widget.downloading?.removeListener(_rebuild);
    _settings?.removeListener(_settingsChanged);
    if (widget.settings == null) _settings?.dispose();
    _clock?.cancel();
    _saveTimer?.cancel();
    if (_state != null) {
      _record(forward: false);
      _save();
    }
    _scroll?.dispose();
    for (final l in _layouts.values) {
      l.dispose();
    }
    if (_systemUiHidden) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  ReaderPalette get palette {
    final key = _settings?.palette ?? 'app';
    if (key != 'app') return readerPalettes[key]!;
    final dark = Theme.of(_ctx).brightness == Brightness.dark;
    if (widget.ereaderApp) {
      return readerPalettes[dark ? 'eink-dark' : 'eink']!;
    }
    return readerPalettes[dark ? 'dusk' : 'paper']!;
  }

  /// E-ink screen mode: automatic on e-ink devices, the e-reader app
  /// appearance and E-ink page colors, unless the reader turned it on or off.
  bool get _eink =>
      s.eink ?? (Device.eink || widget.ereaderApp || palette.eink);

  /// Sheets and menus appear instantly on e-ink so the screen doesn't flash.
  AnimationStyle? get _motion => _eink ? AnimationStyle.noAnimation : null;

  bool get _animate =>
      s.animation != PageAnimation.none &&
      !_eink &&
      !MediaQuery.of(context).disableAnimations;

  // ---------------------------------------------------------------------------
  // Layout and navigation.

  void _relayout(Size page, ReaderPalette pal) {
    final key =
        '${s.layoutKey}|${page.width.round()}x${page.height.round()}|'
        '${pal.label}';
    if (key == _tsKey) return;
    _tsKey = key;
    _gen++;
    _view++;
    for (final l in _layouts.values) {
      l.dispose();
    }
    _layouts.clear();
    _pending.clear();
    _counts = List.filled(doc.chapters.length, null);
    _ts = Typesetter(doc, s, pal, page);
    final gen = _gen;
    _load(_chapter).then((layout) {
      if (layout == null || gen != _gen || !mounted) return;
      setState(() => _page = layout.pageOf(_offset));
      _shownAt = DateTime.now();
      _preload();
      _countPages(gen);
    });
  }

  Future<ChapterLayout?> _load(int chapter) {
    final ready = _layouts[chapter];
    if (ready != null) return SynchronousFuture(ready);
    final gen = _gen, ts = _ts!;
    return _pending[chapter] ??= () async {
      final layout = await ts.layout(chapter);
      if (gen != _gen || !mounted) {
        layout.dispose();
        return null;
      }
      _pending.remove(chapter);
      _layouts[chapter] = layout;
      _counts[chapter] = layout.pages.length;
      return layout;
    }();
  }

  void _evict() {
    for (final c in _layouts.keys.toList()) {
      if ((c - _chapter).abs() > 1) _layouts.remove(c)!.dispose();
    }
  }

  void _preload() {
    if (_chapter + 1 < doc.chapters.length) _load(_chapter + 1);
    if (_chapter > 0) _load(_chapter - 1);
  }

  Future<void> _countPages(int gen) async {
    final ts = _ts;
    if (ts == null) return;
    for (var c = 0; c < doc.chapters.length; c++) {
      await Future<void>.delayed(Duration.zero);
      if (gen != _gen || !mounted) return;
      if (_counts[c] != null) continue;
      final layout = await ts.layout(c, decode: false);
      if (gen != _gen || !mounted) {
        layout.dispose();
        return;
      }
      _counts[c] ??= layout.pages.length;
      layout.dispose();
    }
    if (mounted && gen == _gen) setState(() {});
  }

  bool get _counted => _counts.every((c) => c != null);
  int get _bookPage {
    var page = 0;
    for (var c = 0; c < _chapter; c++) {
      page += _counts[c] ?? 0;
    }
    return page + _page + 1;
  }

  int get _bookPages => _counts.fold(0, (a, b) => a + (b ?? 0));

  int _bookPageAt(int chapter, int offset) {
    var page = 0;
    for (var c = 0; c < chapter; c++) {
      page += _counts[c] ?? 0;
    }
    final l = _layouts[chapter];
    return page + (l?.pageOf(offset) ?? 0) + 1;
  }

  PageInfo? get _pageInfo {
    final l = _layout;
    if (l == null || _page >= l.pages.length) return null;
    return l.pages[_page];
  }

  void _record({required bool forward}) {
    final state = _state;
    if (state == null) return;
    final secs = math.min(DateTime.now().difference(_shownAt).inSeconds, 120);
    final info = _pageInfo;
    final chars = forward && info != null ? info.end - info.start : 0;
    state.addTime(secs, chars);
    if (forward) state.pagesTurned++;
    _shownAt = DateTime.now();
  }

  void _show(int chapter, int page, int direction) {
    final l = _layouts[chapter];
    if (l == null) return;
    _record(forward: direction > 0);
    setState(() {
      _direction = direction;
      _chapter = chapter;
      _page = page.clamp(0, l.pages.length - 1);
      _offset = l.pages[_page].start;
      _selection = null;
      if (_returnTo != null && ++_movesSinceJump > 6) _returnTo = null;
    });
    _evict();
    _preload();
    _scheduleSave();
  }

  Future<void> _next() async {
    if (_selection != null) return setState(() => _selection = null);
    if (_scrollMode) return _scrollBy(1);
    final l = _layout;
    if (l == null) return;
    if (_page + 1 < l.pages.length) return _show(_chapter, _page + 1, 1);
    if (_chapter + 1 >= doc.chapters.length) return _finished();
    final next = await _load(_chapter + 1);
    if (next != null && mounted) _show(_chapter + 1, 0, 1);
  }

  Future<void> _previous() async {
    if (_selection != null) return setState(() => _selection = null);
    if (_scrollMode) return _scrollBy(-1);
    if (_layout == null) return;
    if (_page > 0) return _show(_chapter, _page - 1, -1);
    if (_chapter == 0) return;
    final prev = await _load(_chapter - 1);
    if (prev != null && mounted) {
      _show(_chapter - 1, prev.pages.length - 1, -1);
    }
  }

  void _finished() {
    if (_growing) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'The next chapter is still downloading. It will appear here '
              'in a moment.',
            ),
          ),
        );
      return;
    }
    final state = _state!;
    state.finished ??= DateTime.now();
    _save();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('You reached the end of this book.')),
      );
  }

  /// Jump to a chapter position. With [remember], the reader offers a way back.
  Future<void> _goTo(
    int chapter,
    int offset, {
    bool remember = true,
    (int, int, int)? hit,
  }) async {
    chapter = chapter.clamp(0, doc.chapters.length - 1);
    if (remember) {
      _returnTo = (_chapter, _offset);
      _movesSinceJump = 0;
    }
    _record(forward: false);
    final l = await _load(chapter);
    if (l == null || !mounted) return;
    setState(() {
      _direction = chapter >= _chapter ? 1 : -1;
      _chapter = chapter;
      _page = l.pageOf(offset);
      _offset = _scrollMode ? offset : l.pages[_page].start;
      _searchHit = hit;
      _selection = null;
    });
    if (_scrollMode) _jumpScroll(offset);
    _evict();
    _preload();
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), _save);
  }

  void _save() {
    final state = _state;
    if (state == null) return;
    state
      ..chapter = _chapter
      ..offset = _offset
      ..progress = _progress;
    if (_progress >= .999 && !_growing) state.finished ??= DateTime.now();
    state.save();
    widget.onProgress?.call(_progress);
  }

  /// Progress as shown to the reader: by page once book pages are counted,
  /// like KOReader, otherwise by characters.
  double get _shownProgress {
    if (_counted && !_scrollMode && _bookPages > 0) {
      return (_bookPage / _bookPages).clamp(0.0, 1.0);
    }
    return _progress;
  }

  double get _progress {
    if (doc.length == 0) return 0;
    final info = _scrollMode ? null : _pageInfo;
    final at = info == null
        ? _offset
        : (_chapter == doc.chapters.length - 1 &&
                  _page == (_layout?.pages.length ?? 1) - 1
              ? doc.chapters[_chapter].length
              : info.start);
    return doc.progressOf(_chapter, at);
  }

  // ---------------------------------------------------------------------------
  // Continuous (scroll) view.

  List<double> _scrollExtents(ChapterLayout l) {
    final extents = <double>[_chapter > 0 ? 64 : 8];
    for (var i = 0; i < l.blocks.length; i++) {
      final b = l.blocks[i];
      final gap = i == 0 ? 0.0 : math.max(b.before, l.blocks[i - 1].after);
      extents.add(gap + b.height);
    }
    extents.add(140);
    return extents;
  }

  double _scrollOffsetFor(ChapterLayout l, int offset) {
    final extents = _scrollExtents(l);
    final block = l.blockAt(offset);
    var y = 0.0;
    for (var i = 0; i <= block; i++) {
      y += extents[i];
    }
    final lb = l.blocks[block];
    final gap = block == 0
        ? 0.0
        : math.max(lb.before, l.blocks[block - 1].after);
    y += gap;
    final painter = lb.painter;
    if (painter != null) {
      final local = (offset - lb.block.charStart).clamp(0, lb.block.length);
      y += painter
          .getOffsetForCaret(
            TextPosition(offset: lb.localToPainter(local)),
            Rect.zero,
          )
          .dy;
    }
    return math.max(0, y - 8);
  }

  void _jumpScroll(int offset) {
    final l = _layout, c = _scroll;
    if (l == null || c == null || !c.hasClients) return;
    c.jumpTo(_scrollOffsetFor(l, offset).clamp(0, c.position.maxScrollExtent));
  }

  void _scrollBy(int direction) {
    final c = _scroll;
    if (c == null || !c.hasClients) return;
    final target = (c.offset + direction * _content.height * .9).clamp(
      0.0,
      c.position.maxScrollExtent,
    );
    if (_animate) {
      c.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    } else {
      c.jumpTo(target);
    }
  }

  void _scrolled() {
    final l = _layout, c = _scroll;
    if (l == null || c == null || !c.hasClients || l.blocks.isEmpty) return;
    final extents = _scrollExtents(l);
    final probe = c.offset + 8;
    var y = extents[0];
    var block = 0;
    for (var i = 0; i < l.blocks.length; i++) {
      block = i;
      if (y + extents[i + 1] > probe) break;
      y += extents[i + 1];
    }
    final lb = l.blocks[block];
    var offset = lb.block.charStart;
    final painter = lb.painter;
    final inside = probe - y - (extents[block + 1] - lb.height);
    if (painter != null && inside > 0) {
      offset += lb.painterToLocal(
        painter.getPositionForOffset(Offset(0, inside)).offset,
      );
    }
    final state = _state;
    if (state != null) {
      final secs = math.min(DateTime.now().difference(_shownAt).inSeconds, 120);
      state.addTime(secs, offset > _offset ? offset - _offset : 0);
      _shownAt = DateTime.now();
    }
    setState(() => _offset = offset);
    _scheduleSave();
  }

  // ---------------------------------------------------------------------------
  // Gestures.

  Offset _toContent(Offset global) {
    final box = _area.currentContext?.findRenderObject() as RenderBox?;
    final local = box?.globalToLocal(global) ?? global;
    return local - _content.topLeft;
  }

  void _zoneTap(Offset global) {
    if (_selection != null) {
      setState(() => _selection = null);
      return;
    }
    if (_menu) {
      _setMenu(false);
      return;
    }
    final box = _area.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final p = box.globalToLocal(global);
    final x = p.dx / box.size.width, y = p.dy / box.size.height;
    if (y < .14) return _setMenu(true);
    if (y > .9) {
      _themes();
      return;
    }
    final back = s.tapLayout == TapLayout.inverted
        ? x > 1 - s.backZone
        : x < s.backZone;
    final forwardZone = s.tapLayout == TapLayout.inverted
        ? x < s.backZone
        : x > 1 - s.backZone;
    if (s.tapLayout == TapLayout.forwardAnywhere) {
      if (x < s.backZone * .6) {
        _previous();
      } else {
        _next();
      }
      return;
    }
    if (back) {
      _previous();
    } else if (forwardZone || !_scrollMode) {
      // The wide middle column also turns forward, like KOReader's defaults,
      // except in continuous view where it shows the menu.
      if (!forwardZone && (x > .35 && x < .65 && y > .4 && y < .6)) {
        _setMenu(true);
      } else {
        _next();
      }
    } else {
      _setMenu(true);
    }
  }

  void _setMenu(bool open) {
    setState(() => _menu = open);
    _applySystemUi();
  }

  /// Handles a tap that landed on text: links, highlights, search hits.
  bool _tapText(({int block, int local, int offset})? hit) {
    if (hit == null || _selection != null || _menu) return false;
    final l = _layout!;
    for (final h in _state!.highlights) {
      if (h.chapter == _chapter &&
          hit.offset >= h.start &&
          hit.offset < h.end) {
        _editHighlight(h);
        return true;
      }
    }
    final href = l.blocks[hit.block].linkAt(hit.local);
    if (href != null) {
      _openLink(href, l.blocks[hit.block]);
      return true;
    }
    return false;
  }

  void _selectAt(({int block, int local, int offset})? hit) {
    if (hit == null) return;
    final lb = _layout!.blocks[hit.block];
    final painter = lb.painter;
    if (painter == null) return;
    final word = painter.getWordBoundary(
      TextPosition(offset: lb.localToPainter(hit.local)),
    );
    final start = lb.block.charStart + lb.painterToLocal(word.start);
    final end = lb.block.charStart + lb.painterToLocal(word.end);
    HapticFeedback.selectionClick();
    setState(() {
      _anchor = start;
      _selection = (_chapter, start, math.max(end, start + 1));
      _selecting = true;
      if (_menu) _menu = false;
    });
  }

  void _extendTo(({int block, int local, int offset})? hit) {
    final anchor = _anchor;
    if (hit == null || anchor == null) return;
    final lb = _layout!.blocks[hit.block];
    final painter = lb.painter;
    var offset = hit.offset;
    if (painter != null) {
      final word = painter.getWordBoundary(
        TextPosition(offset: lb.localToPainter(hit.local)),
      );
      offset =
          lb.block.charStart +
          lb.painterToLocal(offset >= anchor ? word.end : word.start);
    }
    setState(
      () => _selection = offset >= anchor
          ? (_chapter, anchor, math.max(offset, anchor + 1))
          : (_chapter, offset, anchor + 1),
    );
  }

  String get _selectedText {
    final sel = _selection;
    if (sel == null) return '';
    final text = doc.chapters[sel.$1].plainText;
    return text
        .substring(sel.$2.clamp(0, text.length), sel.$3.clamp(0, text.length))
        .replaceAll('￼', '')
        .trim();
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent || _settings == null) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      if (_selection != null || _menu) {
        setState(() {
          _selection = null;
          _menu = false;
        });
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    switch (s.actionFor(key)) {
      case KeyAction.next:
        _next();
      case KeyAction.previous:
        _previous();
      case KeyAction.menu:
        _setMenu(!_menu);
      case null:
        return KeyEventResult.ignored;
    }
    // Handled keys are consumed, so volume buttons don't change the volume.
    return KeyEventResult.handled;
  }

  // ---------------------------------------------------------------------------
  // Building.

  List<_Mark> _marks() {
    final state = _state!;
    return [
      for (final h in state.highlights)
        if (h.chapter == _chapter)
          (
            h.start,
            h.end,
            h.color == 'underline'
                ? palette.text
                : palette.eink
                ? palette.highlight
                : highlightColors[h.color] ?? palette.highlight,
            h.color == 'underline',
          ),
      if (_searchHit case final hit? when hit.$1 == _chapter)
        (hit.$2, hit.$3, const Color(0x88FF9800), false),
      if (_selection case final sel? when sel.$1 == _chapter)
        (
          sel.$2,
          sel.$3,
          palette.eink
              ? palette.text.withValues(alpha: .3)
              : const Color(0x664A90E2),
          false,
        ),
    ];
  }

  bool get _bookmarked {
    final info = _pageInfo;
    if (info == null || _scrollMode) {
      return _state!.bookmarks.any(
        (b) => b.chapter == _chapter && (b.offset - _offset).abs() < 200,
      );
    }
    return _state!.bookmarks.any(
      (b) =>
          b.chapter == _chapter &&
          b.offset >= info.start &&
          (b.offset < info.end || info.end <= info.start),
    );
  }

  void _toggleBookmark() {
    final state = _state!;
    final info = _scrollMode ? null : _pageInfo;
    setState(() {
      if (_bookmarked) {
        state.bookmarks.removeWhere(
          (b) =>
              b.chapter == _chapter &&
              (info == null
                  ? (b.offset - _offset).abs() < 200
                  : b.offset >= info.start &&
                        b.offset < math.max(info.end, info.start + 1)),
        );
      } else {
        final start = info?.start ?? _offset;
        final text = doc.chapters[_chapter].plainText;
        final snippet = text
            .substring(
              start.clamp(0, text.length),
              math.min(text.length, start + 160),
            )
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        state.bookmarks.add(Bookmark(_chapter, start, snippet, DateTime.now()));
        state.bookmarks.sort(
          (a, b) => a.chapter != b.chapter
              ? a.chapter.compareTo(b.chapter)
              : a.offset.compareTo(b.offset),
        );
      }
    });
    _save();
  }

  String _duration(double minutes) {
    if (minutes < 1) return '<1m';
    if (minutes < 60) return '${minutes.round()}m';
    final h = minutes ~/ 60, m = (minutes % 60).round();
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  Widget _footer() {
    final state = _state!;
    final l = _layout;
    final items = s.footerItems;
    final info = _pageInfo;
    final chapterLength = doc.chapters[_chapter].length;
    final position = _scrollMode ? _offset : info?.start ?? _offset;
    final parts = <String>[];
    if (items.contains(FooterItem.pageInChapter)) {
      if (_scrollMode) {
        parts.add(
          '${(chapterLength == 0 ? 100 : position * 100 / chapterLength).round()}% of chapter',
        );
      } else if (l != null) {
        parts.add(
          _counted
              ? '$_bookPage / $_bookPages'
              : '${_page + 1} / ${l.pages.length}',
        );
      }
    }
    if (items.contains(FooterItem.pagesLeftChapter) &&
        l != null &&
        !_scrollMode) {
      final left = l.pages.length - _page - 1;
      parts.add(left == 0 ? 'Last page of chapter' : '$left left in chapter');
    }
    if (items.contains(FooterItem.timeLeftChapter)) {
      parts.add(
        '${_duration((chapterLength - position) / state.speed)} left in chapter',
      );
    }
    if (items.contains(FooterItem.timeLeftBook)) {
      final left = doc.length - (doc.chapterStarts[_chapter] + position);
      parts.add('${_duration(left / state.speed)} left in book');
    }
    if (items.contains(FooterItem.bookPercent)) {
      parts.add(
        '${(_shownProgress * 100).toStringAsFixed(_shownProgress < .1 ? 1 : 0)}%',
      );
    }
    if (items.contains(FooterItem.bookmarks)) {
      parts.add('${state.bookmarks.length} bookmarks');
    }
    if (items.contains(FooterItem.clock)) {
      parts.add(TimeOfDay.now().format(context));
    }
    final style = TextStyle(
      color: palette.muted,
      fontSize: 11.5,
      fontFamily: 'DM Sans',
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            if (items.contains(FooterItem.chapterTitle))
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Text(
                    doc.chapterTitle(_chapter, position),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: style,
                  ),
                ),
              ),
            if (items.contains(FooterItem.chapterTitle))
              Text(parts.join('  ·  '), style: style, maxLines: 1)
            else
              Expanded(
                child: Text(
                  parts.join('  ·  '),
                  style: style,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
        if (items.contains(FooterItem.progressBar))
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: SizedBox(
              height: 4,
              width: double.infinity,
              child: CustomPaint(
                painter: _ProgressPainter(_shownProgress, [
                  for (final t in doc.toc.where((t) => t.depth == 0))
                    doc.progressOf(t.chapter, t.offset),
                ], palette),
              ),
            ),
          ),
      ],
    );
  }

  Widget _pageView(ChapterLayout l) {
    final info = l.pages[_page.clamp(0, l.pages.length - 1)];
    final key = ValueKey('$_view-${doc.chapters[_chapter].path}-$_page');
    final page = ColoredBox(
      key: key,
      color: palette.background,
      child: CustomPaint(
        size: _content.size,
        painter: PagePainter(
          layout: l,
          slices: info.slices,
          palette: palette,
          marks: _marks(),
          invertImages: s.invertImages,
        ),
      ),
    );
    return ClipRect(
      child: AnimatedSwitcher(
        duration: _animate ? const Duration(milliseconds: 220) : Duration.zero,
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          if (s.animation == PageAnimation.fade) {
            return FadeTransition(opacity: animation, child: child);
          }
          final incoming = child.key == key;
          final dir = _direction.toDouble();
          return SlideTransition(
            position: Tween(
              begin: Offset(incoming ? dir : -dir, 0),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          );
        },
        layoutBuilder: (current, previous) =>
            Stack(children: [...previous, ?current]),
        child: page,
      ),
    );
  }

  /// The current page's text, for screen readers.
  String _pageText(ChapterLayout l) {
    final info = l.pages[_page.clamp(0, l.pages.length - 1)];
    final text = doc.chapters[_chapter].plainText;
    final start = info.start.clamp(0, text.length);
    return text.substring(start, info.end.clamp(start, text.length)).trim();
  }

  Widget _scrollView(ChapterLayout l) {
    final key = '$_view-${doc.chapters[_chapter].path}';
    if (_scrollKey != key) {
      _scrollKey = key;
      final old = _scroll;
      if (old != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
      }
      _scroll = ScrollController(
        initialScrollOffset: _scrollOffsetFor(l, _offset),
      );
    }
    final extents = _scrollExtents(l);
    final marks = _marks();
    return NotificationListener<ScrollEndNotification>(
      onNotification: (_) {
        _scrolled();
        return false;
      },
      child: ListView.builder(
        key: ValueKey(key),
        controller: _scroll,
        padding: EdgeInsets.zero,
        itemCount: extents.length,
        itemExtentBuilder: (i, _) => i < extents.length ? extents[i] : null,
        itemBuilder: (context, i) {
          if (i == 0) {
            return _chapter == 0
                ? const SizedBox.shrink()
                : Center(
                    child: TextButton.icon(
                      onPressed: () async {
                        final prev = await _load(_chapter - 1);
                        if (prev != null) {
                          _goTo(
                            _chapter - 1,
                            prev.pages.last.start,
                            remember: false,
                          );
                        }
                      },
                      icon: const Icon(CupertinoIcons.chevron_up),
                      label: const Text('Previous chapter'),
                      style: TextButton.styleFrom(
                        foregroundColor: palette.muted,
                      ),
                    ),
                  );
          }
          if (i == extents.length - 1) {
            final last = _chapter + 1 >= doc.chapters.length;
            return Center(
              child: last
                  ? Text(
                      'The end',
                      style: TextStyle(
                        color: palette.muted,
                        fontFamily: 'Fraunces',
                      ),
                    )
                  : FilledButton.tonalIcon(
                      onPressed: () => _goTo(_chapter + 1, 0, remember: false),
                      icon: const Icon(CupertinoIcons.chevron_down),
                      label: Text(
                        'Next: ${doc.chapterTitle(_chapter + 1, 0)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
            );
          }
          final index = i - 1;
          final lb = l.blocks[index];
          final gap = extents[i] - lb.height;
          ({int block, int local, int offset})? hit(Offset local) =>
              l.hitBlock(index, local - Offset(0, gap));
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) {
              if (!_tapText(hit(d.localPosition))) _zoneTap(d.globalPosition);
            },
            onLongPressStart: (d) => _selectAt(hit(d.localPosition)),
            onLongPressMoveUpdate: (d) => _extendTo(hit(d.localPosition)),
            onLongPressEnd: (_) => setState(() => _selecting = false),
            child: Padding(
              padding: EdgeInsets.only(top: gap),
              child: Semantics(
                label: lb.block.text.trim(),
                child: CustomPaint(
                  size: Size(_content.width, lb.height),
                  painter: BlockPainter(lb, palette, marks, s.invertImages),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_settings == null || _state == null) {
      return const Scaffold(
        body: Center(child: CupertinoActivityIndicator(radius: 14)),
      );
    }
    final pal = palette;
    final readerTheme = _readerTheme(pal, eink: _eink);
    return Theme(
      data: readerTheme,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: pal.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        child: PopScope(
          canPop: _selection == null,
          onPopInvokedWithResult: (popped, _) {
            if (!popped) setState(() => _selection = null);
          },
          child: Scaffold(
            key: _themed,
            backgroundColor: pal.background,
            body: Focus(
              autofocus: true,
              onKeyEvent: _key,
              child: LayoutBuilder(builder: (context, box) => _body(box, pal)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(BoxConstraints box, ReaderPalette pal) {
    final live = MediaQuery.viewPaddingOf(context);
    // The page keeps its insets while the menu is open, so system bars
    // appearing with the menu never reflow the text underneath.
    if (!_menu || _pagePad == null) _pagePad = live;
    final pad = _pagePad!;
    // The header and status bar grow with the system text size.
    final line = MediaQuery.textScalerOf(context).scale(11.5) * 1.45;
    final headerH = s.header ? line + 10 : 0.0;
    final footerH = s.footer
        ? line + (s.footerItems.contains(FooterItem.progressBar) ? 13.0 : 4.0)
        : 0.0;
    final left = pad.left + s.marginSide, right = pad.right + s.marginSide;
    final top = pad.top + headerH + s.marginTop;
    final bottom = pad.bottom + footerH + s.marginBottom;
    _content = Rect.fromLTRB(
      left,
      top,
      math.max(left + 80, box.maxWidth - right),
      math.max(top + 80, box.maxHeight - bottom),
    );
    _relayout(_content.size, pal);
    final l = _layout;
    final info = _pageInfo;
    final chapterTitle = doc.chapterTitle(
      _chapter,
      _scrollMode ? _offset : info?.start ?? _offset,
    );
    return Stack(
      key: _area,
      children: [
        Positioned.fill(
          child: Listener(
            onPointerSignal: (event) {
              if (event is PointerScrollEvent && !_scrollMode) {
                if (event.scrollDelta.dy > 0) {
                  _next();
                } else if (event.scrollDelta.dy < 0) {
                  _previous();
                }
              }
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) {
                final p = _toContent(d.globalPosition);
                final hit = l == null || _scrollMode ? null : l.hit(_page, p);
                if (!_tapText(hit)) _zoneTap(d.globalPosition);
              },
              onLongPressStart: _scrollMode || l == null
                  ? null
                  : (d) =>
                        _selectAt(l.hit(_page, _toContent(d.globalPosition))),
              onLongPressMoveUpdate: _scrollMode || l == null
                  ? null
                  : (d) =>
                        _extendTo(l.hit(_page, _toContent(d.globalPosition))),
              onLongPressEnd: _scrollMode
                  ? null
                  : (_) => setState(() => _selecting = false),
              onScaleStart: _scrollMode
                  ? null
                  : (d) {
                      _pointers = d.pointerCount;
                      _swipe = Offset.zero;
                      _pinchBase = s.fontSize;
                    },
              onScaleUpdate: _scrollMode
                  ? null
                  : (d) {
                      _pointers = math.max(_pointers, d.pointerCount);
                      if (_pointers >= 2 && s.pinch) {
                        setState(
                          () => _pinchSize = (_pinchBase! * d.scale)
                              .clamp(10.0, 48.0)
                              .roundToDouble(),
                        );
                      } else {
                        _swipe += d.focalPointDelta;
                      }
                    },
              onScaleEnd: _scrollMode
                  ? null
                  : (d) {
                      final size = _pinchSize;
                      if (size != null) {
                        setState(() => _pinchSize = null);
                        if (size != s.fontSize) {
                          s.update((s) => s.fontSize = size);
                        }
                      } else if (s.swipe &&
                          _pointers == 1 &&
                          _swipe.dx.abs() > 40 &&
                          _swipe.dx.abs() > _swipe.dy.abs()) {
                        final forward = _swipe.dx < 0;
                        if (forward != (s.tapLayout == TapLayout.inverted)) {
                          _next();
                        } else {
                          _previous();
                        }
                      } else if (_pointers == 1 &&
                          _swipe.dy > 80 &&
                          _swipe.dy.abs() > _swipe.dx.abs() * 2) {
                        _setMenu(true);
                      }
                      _pointers = 0;
                    },
              child: ColoredBox(color: pal.background),
            ),
          ),
        ),
        Positioned.fromRect(
          rect: _content,
          child: l == null
              ? Center(child: CupertinoActivityIndicator(color: pal.muted))
              : _scrollMode
              ? _scrollView(l)
              // Taps reach the reader's gesture layer; screen readers still
              // get the page's text.
              : Semantics(
                  container: true,
                  label: _pageText(l),
                  child: IgnorePointer(child: _pageView(l)),
                ),
        ),
        if (s.header)
          Positioned(
            left: left,
            right: right,
            top: pad.top + 6,
            height: headerH - 6,
            child: IgnorePointer(
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      chapterTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: pal.muted,
                        fontSize: 11.5,
                        fontFamily: 'DM Sans',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (_bookmarked)
          Positioned(
            top: 0,
            right: pad.right + 10,
            child: IgnorePointer(
              child: CustomPaint(
                size: const Size(22, 34),
                painter: _DogEarPainter(
                  pal.dark ? pal.muted : const Color(0xFFB4483C),
                ),
              ),
            ),
          ),
        if (s.footer)
          Positioned(
            left: left,
            right: right,
            bottom: pad.bottom + 6,
            height: footerH - 4,
            child: IgnorePointer(child: _footer()),
          ),
        if (_pinchSize != null)
          Center(
            child: IgnorePointer(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                  child: Text(
                    'Font size ${_pinchSize!.round()}',
                    style: Theme.of(_ctx).textTheme.titleMedium,
                  ),
                ),
              ),
            ),
          ),
        if (_returnTo != null && !_menu && _selection == null)
          Positioned(
            left: 0,
            right: 0,
            bottom: pad.bottom + footerH + 8,
            child: Center(
              child: InputChip(
                avatar: const Icon(CupertinoIcons.arrow_uturn_left, size: 18),
                label: const Text('Back to where you were'),
                onPressed: () {
                  final back = _returnTo!;
                  setState(() => _returnTo = null);
                  _goTo(back.$1, back.$2, remember: false);
                },
                onDeleted: () => setState(() => _returnTo = null),
              ),
            ),
          ),
        if (_selection != null && !_selecting) _selectionBar(live),
        if (_menu) ..._menus(live, chapterTitle),
      ],
    );
  }

  List<Widget> _menus(EdgeInsets pad, String chapterTitle) {
    final p = Palette.of(_ctx);
    final pages = _counted && !_scrollMode
        ? 'Page $_bookPage of $_bookPages'
        : _scrollMode
        ? 'Chapter ${_chapter + 1} of ${doc.chapters.length}'
        : 'Page ${_page + 1} of ${_layout?.pages.length ?? '…'} in chapter';
    final state = _state!;
    final title = TextStyles.headline.copyWith(color: p.label);
    final small = TextStyles.caption1.copyWith(color: p.secondaryLabel);
    // Bar text grows with the text size, up to 1.5x.
    Widget clamp(Widget child) =>
        MediaQuery.withClampedTextScaling(maxScaleFactor: 1.5, child: child);
    return [
      // Top: close on the leading edge, the book in the middle, and search
      // and bookmark grouped on the trailing edge.
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: clamp(
          GlassBar(
            child: Padding(
              padding: EdgeInsets.only(
                top: pad.top,
                left: pad.left + 4,
                right: pad.right + 4,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 52),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Close book',
                      icon: const Icon(CupertinoIcons.xmark),
                      onPressed: () => Navigator.maybePop(context),
                    ),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            doc.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: title,
                          ),
                          Text(
                            chapterTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: small,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Search in book',
                      icon: const Icon(CupertinoIcons.search),
                      onPressed: _search,
                    ),
                    IconButton(
                      tooltip: _bookmarked
                          ? 'Remove bookmark'
                          : 'Bookmark this page',
                      icon: Icon(
                        _bookmarked
                            ? CupertinoIcons.bookmark_fill
                            : CupertinoIcons.bookmark,
                      ),
                      onPressed: _toggleBookmark,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      // Bottom: contents, the scrubber, Themes & Settings and More.
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: clamp(
          GlassBar(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: pad.bottom + 4,
                left: pad.left + 4,
                right: pad.right + 4,
                top: 8,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$pages · ${(_shownProgress * 100).toStringAsFixed(1)}%',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: small,
                  ),
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Contents',
                        icon: const Icon(CupertinoIcons.list_bullet),
                        onPressed: () => _navigate(0),
                      ),
                      Expanded(child: _Skimmer(this)),
                      IconButton(
                        tooltip: 'Themes & Settings',
                        icon: const Icon(CupertinoIcons.textformat_size),
                        onPressed: _themes,
                      ),
                      PopupMenuButton<String>(
                        popUpAnimationStyle: _motion,
                        tooltip: 'More',
                        icon: const Icon(CupertinoIcons.ellipsis_circle),
                        onSelected: (v) => switch (v) {
                          'notes' => _navigate(1),
                          'goto' => _goToDialog(),
                          'previous' => _goTo(_chapter - 1, 0, remember: false),
                          'next' => _goTo(_chapter + 1, 0, remember: false),
                          'stats' => _stats(),
                          'info' => _info(),
                          'export' => _exportNotes(),
                          _ => null,
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'notes',
                            child: Text('Bookmarks & Highlights'),
                          ),
                          const PopupMenuItem(
                            value: 'goto',
                            child: Text('Go to Page or %'),
                          ),
                          PopupMenuItem(
                            value: 'previous',
                            enabled: _chapter > 0,
                            child: const Text('Previous Chapter'),
                          ),
                          PopupMenuItem(
                            value: 'next',
                            enabled: _chapter + 1 < doc.chapters.length,
                            child: const Text('Next Chapter'),
                          ),
                          const PopupMenuItem(
                            value: 'stats',
                            child: Text('Reading Statistics'),
                          ),
                          const PopupMenuItem(
                            value: 'info',
                            child: Text('Book Information'),
                          ),
                          PopupMenuItem(
                            value: 'export',
                            enabled: state.highlights.isNotEmpty,
                            child: const Text('Copy Highlights & Notes'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ];
  }

  /// The selected text's bounds on screen (paged view), for placing the
  /// selection menu next to it.
  Rect? _selectionRect() {
    final sel = _selection, l = _layout, info = _pageInfo;
    if (sel == null || l == null || info == null || _scrollMode) return null;
    if (sel.$1 != _chapter) return null;
    Rect? box;
    for (final slice in info.slices) {
      final lb = l.blocks[slice.block];
      final painter = lb.painter;
      if (painter == null) continue;
      final start = lb.block.charStart, end = start + lb.block.length;
      if (sel.$3 <= start || sel.$2 >= end) continue;
      final boxes = painter.getBoxesForSelection(
        TextSelection(
          baseOffset: lb.localToPainter(math.max(sel.$2, start) - start),
          extentOffset: lb.localToPainter(math.min(sel.$3, end) - start),
        ),
      );
      for (final b in boxes) {
        final r = b.toRect().shift(Offset(lb.left, slice.y - slice.top));
        if (r.bottom < slice.y || r.top > slice.y + slice.bottom - slice.top) {
          continue;
        }
        box = box == null ? r : box.expandToInclude(r);
      }
    }
    return box?.shift(_content.topLeft);
  }

  /// The edit menu for selected text, placed just above the selection (or
  /// below it near the top of the page), like the system menu on iPhone.
  Widget _selectionBar(EdgeInsets pad) {
    final text = _selectedText;
    const menuHeight = 46.0;
    final screen = MediaQuery.sizeOf(_ctx);
    final anchor = _selectionRect();
    double? top, bottom;
    if (anchor == null) {
      bottom = pad.bottom + 40;
    } else if (anchor.top - menuHeight - 12 > pad.top + 8) {
      top = anchor.top - menuHeight - 12;
    } else {
      top = math.min(anchor.bottom + 12, screen.height - menuHeight - 24);
    }
    const ink = Color(0xFF2C2C2E);
    Widget action(String label, VoidCallback onTap) => TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        minimumSize: const Size(minTarget, menuHeight),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        textStyle: TextStyles.subheadline.copyWith(fontWeight: FontWeight.w500),
        shape: const RoundedRectangleBorder(),
      ),
      child: Text(label),
    );
    Widget divider() => Container(width: .5, height: 22, color: Colors.white24);
    final actions = [
      action('Copy', () {
        Clipboard.setData(ClipboardData(text: text));
        setState(() => _selection = null);
        _toast('Copied');
      }),
      action('Highlight', () => _highlight()),
      action('Note', () => _highlight(note: true)),
      action('Look Up', () => _lookUp(text, 'dictionary')),
      action('Translate', () => _lookUp(text, 'translate')),
      action('Search', () {
        setState(() => _selection = null);
        _search(initial: text);
      }),
      action('Wikipedia', () => _lookUp(text, 'wikipedia')),
    ];
    return Positioned(
      left: 12 + pad.left,
      right: 12 + pad.right,
      top: top,
      bottom: bottom,
      child: Center(
        child: Material(
          color: palette.eink ? palette.background : ink,
          elevation: palette.eink ? 0 : 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: palette.eink
                ? BorderSide(color: palette.text)
                : BorderSide.none,
          ),
          clipBehavior: Clip.antiAlias,
          child: Theme(
            data: palette.eink
                ? Theme.of(_ctx).copyWith(
                    textButtonTheme: TextButtonThemeData(
                      style: TextButton.styleFrom(
                        foregroundColor: palette.text,
                      ),
                    ),
                  )
                : Theme.of(_ctx),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) divider(),
                    actions[i],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _rebuild() => setState(() {});
}

/// App theme recolored so menus and sheets sit naturally on the page color.
ThemeData _readerTheme(ReaderPalette pal, {bool eink = false}) {
  final base = novelTheme(
    pal.dark ? Brightness.dark : Brightness.light,
    ereader: pal.eink,
  );
  if (pal.eink) return base;
  final themed = _pageTheme(base, pal, eink);
  return eink ? withoutMotion(themed) : themed;
}

ThemeData _pageTheme(ThemeData base, ReaderPalette pal, bool eink) {
  Color tint(double a) =>
      Color.alphaBlend(pal.text.withValues(alpha: a), pal.background);
  final colors = base.colorScheme.copyWith(
    surface: tint(.03),
    surfaceContainerLowest: pal.background,
    surfaceContainerLow: tint(.04),
    surfaceContainer: tint(.06),
    surfaceContainerHigh: tint(.09),
    surfaceContainerHighest: tint(.12),
    onSurface: pal.text,
    onSurfaceVariant: pal.muted,
    outlineVariant: tint(.18),
  );
  final app = Palette.ofTheme(base);
  // Menus, sheets and the glass bars take their colors from the page.
  final page = Palette(
    dark: pal.dark,
    background: tint(.03),
    cell: tint(.06),
    elevated: tint(.05),
    label: pal.text,
    secondaryLabel: pal.muted,
    tertiaryLabel: pal.muted.withValues(alpha: .6),
    separator: pal.text.withValues(alpha: .16),
    fill: pal.text.withValues(alpha: .08),
    accent: app.accent,
    onAccent: app.onAccent,
    destructive: app.destructive,
    bar: tint(.05).withValues(alpha: .86),
    epaper: eink,
  );
  return base.copyWith(
    colorScheme: colors.copyWith(
      surfaceContainerLow: page.cell,
      surfaceContainerHigh: page.elevated,
    ),
    extensions: [PaletteExtension(page)],
    bottomSheetTheme: base.bottomSheetTheme.copyWith(
      backgroundColor: page.elevated,
      modalBackgroundColor: page.elevated,
    ),
    dialogTheme: DialogThemeData(backgroundColor: colors.surfaceContainerHigh),
    popupMenuTheme: PopupMenuThemeData(color: colors.surfaceContainerHigh),
  );
}

/// Book-wide progress slider that previews the destination while dragging.
class _Skimmer extends StatefulWidget {
  const _Skimmer(this.reader);
  final _ReaderScreenState reader;
  @override
  State<_Skimmer> createState() => _SkimmerState();
}

class _SkimmerState extends State<_Skimmer> {
  double? _value;
  @override
  Widget build(BuildContext context) {
    final r = widget.reader;
    final value = _value ?? r._progress;
    final (chapter, offset) = r.doc.locate(value);
    return Slider(
      value: value.clamp(0.0, 1.0),
      label: _value == null
          ? null
          : '${(value * 100).round()}% · ${r.doc.chapterTitle(chapter, offset)}',
      divisions: 1000,
      onChanged: (v) => setState(() => _value = v),
      onChangeEnd: (v) {
        setState(() => _value = null);
        final (c, o) = r.doc.locate(v);
        r._goTo(c, o);
      },
    );
  }
}

class _ProgressPainter extends CustomPainter {
  _ProgressPainter(this.progress, this.ticks, this.palette);
  final double progress;
  final List<double> ticks;
  final ReaderPalette palette;
  @override
  void paint(Canvas canvas, Size size) {
    final track = Paint()..color = palette.muted.withValues(alpha: .25);
    final fill = Paint()..color = palette.muted;
    final y = size.height / 2;
    canvas.drawRRect(
      RRect.fromLTRBR(0, y - 1, size.width, y + 1, const Radius.circular(1)),
      track,
    );
    canvas.drawRRect(
      RRect.fromLTRBR(
        0,
        y - 1,
        size.width * progress,
        y + 1,
        const Radius.circular(1),
      ),
      fill,
    );
    if (ticks.length < 120) {
      final tick = Paint()
        ..color = palette.muted.withValues(alpha: .6)
        ..strokeWidth = 1;
      for (final t in ticks.skip(1)) {
        canvas.drawLine(
          Offset(size.width * t, 0),
          Offset(size.width * t, size.height),
          tick,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_ProgressPainter old) =>
      old.progress != progress || old.palette != palette;
}

class _DogEarPainter extends CustomPainter {
  _DogEarPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(size.width / 2, size.height * .75)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_DogEarPainter old) => old.color != color;
}
