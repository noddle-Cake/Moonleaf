import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ReaderView { paged, scroll }

enum TextAlignment { justify, left }

enum TapLayout { standard, inverted, forwardAnywhere }

enum PageAnimation { none, slide, fade }

enum FooterItem {
  pageInChapter('Page in chapter'),
  pagesLeftChapter('Pages left in chapter'),
  bookPercent('Book progress (%)'),
  timeLeftChapter('Time left in chapter'),
  timeLeftBook('Time left in book'),
  chapterTitle('Chapter title'),
  clock('Clock'),
  bookmarks('Bookmark count'),
  progressBar('Progress bar');

  const FooterItem(this.label);
  final String label;
}

class ReaderPalette {
  const ReaderPalette(
    this.label,
    this.background,
    this.text,
    this.muted,
    this.highlight, {
    this.dark = false,
    this.eink = false,
  });
  final String label;
  final Color background, text, muted, highlight;
  final bool dark, eink;
}

const readerPalettes = {
  'paper': ReaderPalette(
    'Paper',
    Color(0xFFFBFAF6),
    Color(0xFF1F1E1B),
    Color(0xFF6E6A60),
    Color(0x66F2C94C),
  ),
  'sepia': ReaderPalette(
    'Sepia',
    Color(0xFFF3E7CF),
    Color(0xFF4A3727),
    Color(0xFF85705A),
    Color(0x66E0A458),
  ),
  'sage': ReaderPalette(
    'Sage',
    Color(0xFFE4EBDD),
    Color(0xFF263125),
    Color(0xFF5E6C5B),
    Color(0x669FC07A),
  ),
  'dusk': ReaderPalette(
    'Dusk',
    Color(0xFF22252B),
    Color(0xFFD8D6CF),
    Color(0xFF9A9A94),
    Color(0x669C83C9),
    dark: true,
  ),
  'night': ReaderPalette(
    'Night',
    Color(0xFF000000),
    Color(0xFFC9C9C9),
    Color(0xFF858585),
    Color(0x667A6A9E),
    dark: true,
  ),
  'eink': ReaderPalette(
    'E-ink',
    Color(0xFFFFFFFF),
    Color(0xFF000000),
    Color(0xFF333333),
    Color(0x55000000),
    eink: true,
  ),
  'eink-dark': ReaderPalette(
    'E-ink dark',
    Color(0xFF000000),
    Color(0xFFFFFFFF),
    Color(0xFFDDDDDD),
    Color(0x77FFFFFF),
    dark: true,
    eink: true,
  ),
};

class ReaderFont {
  const ReaderFont(this.label, this.family, [this.fallback = const []]);
  final String label;
  final String? family;
  final List<String> fallback;
}

const builtInFonts = {
  'serif': ReaderFont('Book serif', 'Georgia', [
    'Noto Serif',
    'Times New Roman',
    'serif',
  ]),
  'fraunces': ReaderFont('Fraunces', 'Fraunces'),
  'sans': ReaderFont('System sans', null),
  'dmsans': ReaderFont('DM Sans', 'DM Sans'),
  'mono': ReaderFont('Monospace', 'Menlo', [
    'Roboto Mono',
    'Consolas',
    'Courier New',
    'monospace',
  ]),
};

/// Typesetting, controls and status bar preferences shared by every book.
class ReaderSettings extends ChangeNotifier {
  ReaderSettings([Map<String, dynamic> data = const {}]) {
    _apply(data);
  }
  static const storageKey = 'moonleaf_reader_settings_v1';
  SharedPreferences? _preferences;

  String font = 'serif';
  double fontSize = 19, lineHeight = 1.5, indent = 1.5, paragraphSpacing = .2;
  double wordSpacing = 0, letterSpacing = 0;
  int fontWeight = 400;
  TextAlignment align = TextAlignment.justify;
  bool publisherAlignment = true;
  double marginSide = 22, marginTop = 18, marginBottom = 14;
  ReaderView view = ReaderView.paged;

  /// Palette key, or `app` to follow the app appearance.
  String palette = 'app';
  bool invertImages = false;
  PageAnimation animation = PageAnimation.slide;
  TapLayout tapLayout = TapLayout.standard;
  double backZone = .3;
  bool swipe = true, pinch = true, keys = true, fullscreen = true;
  bool header = true, footer = true;
  Set<FooterItem> footerItems = {
    FooterItem.clock,
    FooterItem.pageInChapter,
    FooterItem.timeLeftChapter,
    FooterItem.bookPercent,
    FooterItem.progressBar,
  };

  /// User-added fonts: family name → font file path.
  Map<String, String> customFonts = {};

  static Future<ReaderSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    Map<String, dynamic> data = {};
    try {
      if (raw != null) data = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {}
    return ReaderSettings(data).._preferences = prefs;
  }

  ReaderFont get readerFont {
    if (font.startsWith('custom:')) {
      final name = font.substring(7);
      return ReaderFont(name, name);
    }
    return builtInFonts[font] ?? builtInFonts['serif']!;
  }

  T _enum<T extends Enum>(List<T> values, Object? name, T fallback) =>
      values.where((v) => v.name == name).firstOrNull ?? fallback;

  void _apply(Map<String, dynamic> d) {
    double n(String k, double v, double lo, double hi) =>
        ((d[k] as num?)?.toDouble() ?? v).clamp(lo, hi);
    font = d['font'] as String? ?? font;
    fontSize = n('fontSize', fontSize, 10, 48);
    lineHeight = n('lineHeight', lineHeight, 1, 2.6);
    indent = n('indent', indent, 0, 4);
    paragraphSpacing = n('paragraphSpacing', paragraphSpacing, 0, 2);
    wordSpacing = n('wordSpacing', wordSpacing, -3, 12);
    letterSpacing = n('letterSpacing', letterSpacing, -1, 4);
    fontWeight = n('fontWeight', fontWeight.toDouble(), 300, 800).round();
    align = _enum(TextAlignment.values, d['align'], align);
    publisherAlignment = d['publisherAlignment'] as bool? ?? publisherAlignment;
    marginSide = n('marginSide', marginSide, 0, 120);
    marginTop = n('marginTop', marginTop, 0, 120);
    marginBottom = n('marginBottom', marginBottom, 0, 120);
    view = _enum(ReaderView.values, d['view'], view);
    palette = d['palette'] as String? ?? palette;
    if (palette != 'app' && !readerPalettes.containsKey(palette)) {
      palette = 'app';
    }
    invertImages = d['invertImages'] as bool? ?? invertImages;
    animation = _enum(PageAnimation.values, d['animation'], animation);
    tapLayout = _enum(TapLayout.values, d['tapLayout'], tapLayout);
    backZone = n('backZone', backZone, .15, .5);
    swipe = d['swipe'] as bool? ?? swipe;
    pinch = d['pinch'] as bool? ?? pinch;
    keys = d['keys'] as bool? ?? keys;
    fullscreen = d['fullscreen'] as bool? ?? fullscreen;
    header = d['header'] as bool? ?? header;
    footer = d['footer'] as bool? ?? footer;
    final items = d['footerItems'] as List?;
    if (items != null) {
      footerItems = {
        for (final i in items) ...FooterItem.values.where((f) => f.name == i),
      };
    }
    customFonts = Map<String, String>.from(
      d['customFonts'] as Map? ?? customFonts,
    );
  }

  Map<String, dynamic> toJson() => {
    'font': font,
    'fontSize': fontSize,
    'lineHeight': lineHeight,
    'indent': indent,
    'paragraphSpacing': paragraphSpacing,
    'wordSpacing': wordSpacing,
    'letterSpacing': letterSpacing,
    'fontWeight': fontWeight,
    'align': align.name,
    'publisherAlignment': publisherAlignment,
    'marginSide': marginSide,
    'marginTop': marginTop,
    'marginBottom': marginBottom,
    'view': view.name,
    'palette': palette,
    'invertImages': invertImages,
    'animation': animation.name,
    'tapLayout': tapLayout.name,
    'backZone': backZone,
    'swipe': swipe,
    'pinch': pinch,
    'keys': keys,
    'fullscreen': fullscreen,
    'header': header,
    'footer': footer,
    'footerItems': footerItems.map((f) => f.name).toList(),
    'customFonts': customFonts,
  };

  /// Typesetting fingerprint: when it changes, pages must be recomputed.
  String get layoutKey => jsonEncode([
    font,
    fontSize,
    lineHeight,
    indent,
    paragraphSpacing,
    wordSpacing,
    letterSpacing,
    fontWeight,
    align.name,
    publisherAlignment,
    marginSide,
    marginTop,
    marginBottom,
    header,
    footer,
  ]);

  void update(void Function(ReaderSettings s) change) {
    change(this);
    notifyListeners();
    _preferences?.setString(storageKey, jsonEncode(toJson()));
  }

  void reset() => update((s) => s._apply(ReaderSettings().toJson()));
}

class Bookmark {
  Bookmark(this.chapter, this.offset, this.snippet, this.created);
  final int chapter, offset;
  final String snippet;
  final DateTime created;
  Map<String, dynamic> toJson() => {
    'c': chapter,
    'o': offset,
    's': snippet,
    't': created.toIso8601String(),
  };
  factory Bookmark.fromJson(Map<String, dynamic> j) => Bookmark(
    j['c'] as int,
    j['o'] as int,
    j['s'] as String? ?? '',
    DateTime.tryParse(j['t'] as String? ?? '') ?? DateTime.now(),
  );
}

const highlightColors = {
  'yellow': Color(0x66F2C94C),
  'green': Color(0x6687C26B),
  'blue': Color(0x6672A8E0),
  'pink': Color(0x66E58BB0),
  'underline': Color(0x00000000),
};

class Highlight {
  Highlight(
    this.chapter,
    this.start,
    this.end,
    this.text,
    this.created, {
    this.note = '',
    this.color = 'yellow',
  });
  final int chapter, start, end;
  final String text;
  final DateTime created;
  String note, color;
  Map<String, dynamic> toJson() => {
    'c': chapter,
    's': start,
    'e': end,
    'x': text,
    't': created.toIso8601String(),
    'n': note,
    'k': color,
  };
  factory Highlight.fromJson(Map<String, dynamic> j) => Highlight(
    j['c'] as int,
    j['s'] as int,
    j['e'] as int,
    j['x'] as String? ?? '',
    DateTime.tryParse(j['t'] as String? ?? '') ?? DateTime.now(),
    note: j['n'] as String? ?? '',
    color: j['k'] as String? ?? 'yellow',
  );
}

/// Where you are in one book, plus its annotations and reading statistics.
class BookState {
  BookState(this.id, [Map<String, dynamic> d = const {}])
    : chapter = d['chapter'] as int? ?? 0,
      offset = d['offset'] as int? ?? 0,
      progress = (d['progress'] as num?)?.toDouble() ?? 0,
      bookmarks = [
        for (final b in d['bookmarks'] as List? ?? [])
          Bookmark.fromJson(Map<String, dynamic>.from(b as Map)),
      ],
      highlights = [
        for (final h in d['highlights'] as List? ?? [])
          Highlight.fromJson(Map<String, dynamic>.from(h as Map)),
      ],
      seconds = d['seconds'] as int? ?? 0,
      charsRead = d['charsRead'] as int? ?? 0,
      pagesTurned = d['pagesTurned'] as int? ?? 0,
      daily = Map<String, int>.from(d['daily'] as Map? ?? {}),
      started = DateTime.tryParse(d['started'] as String? ?? ''),
      finished = DateTime.tryParse(d['finished'] as String? ?? '');
  final String id;
  int chapter, offset, seconds, charsRead, pagesTurned;
  double progress;
  final List<Bookmark> bookmarks;
  final List<Highlight> highlights;

  /// Seconds read per day, keyed by yyyy-mm-dd.
  final Map<String, int> daily;
  DateTime? started, finished;

  static String key(String id) => 'moonleaf_reader_book_$id';

  static Future<BookState> load(String id) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final raw = prefs.getString(key(id));
      if (raw != null) {
        return BookState(id, jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (_) {}
    return BookState(id);
  }

  static Future<void> forget(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key(id));
  }

  /// Characters per minute, with a sensible default for new readers.
  double get speed =>
      seconds < 120 || charsRead < 2000 ? 1100 : charsRead / (seconds / 60);

  void addTime(int secs, int chars) {
    if (secs <= 0) return;
    seconds += secs;
    charsRead += chars.clamp(0, 1 << 30);
    final now = DateTime.now();
    final day =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    daily[day] = (daily[day] ?? 0) + secs;
    if (daily.length > 60) {
      final keys = daily.keys.toList()..sort();
      for (final k in keys.take(daily.length - 60)) {
        daily.remove(k);
      }
    }
  }

  Map<String, dynamic> toJson() => {
    'chapter': chapter,
    'offset': offset,
    'progress': progress,
    'bookmarks': bookmarks.map((b) => b.toJson()).toList(),
    'highlights': highlights.map((h) => h.toJson()).toList(),
    'seconds': seconds,
    'charsRead': charsRead,
    'pagesTurned': pagesTurned,
    'daily': daily,
    'started': started?.toIso8601String(),
    'finished': finished?.toIso8601String(),
  };

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key(id), jsonEncode(toJson()));
  }
}
