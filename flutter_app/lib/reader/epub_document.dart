import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:xml/xml.dart';

/// Inline formatting for a run of text inside a [TextBlock].
class TextRun {
  const TextRun(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strike = false,
    this.mono = false,
    this.sup = false,
    this.sub = false,
    this.small = false,
    this.href,
  });
  final String text;
  final bool bold, italic, underline, strike, mono, sup, sub, small;
  final String? href;
  TextRun withText(String value) => TextRun(
    value,
    bold: bold,
    italic: italic,
    underline: underline,
    strike: strike,
    mono: mono,
    sup: sup,
    sub: sub,
    small: small,
    href: href,
  );
  bool sameStyle(TextRun o) =>
      bold == o.bold &&
      italic == o.italic &&
      underline == o.underline &&
      strike == o.strike &&
      mono == o.mono &&
      sup == o.sup &&
      sub == o.sub &&
      small == o.small &&
      href == o.href;
}

enum BlockKind { paragraph, heading, quote, listItem, preformatted, caption }

enum BlockAlign { start, center, end, justify }

sealed class Block {
  const Block(this.charStart);

  /// Offset of this block's first character in the chapter's plain text.
  final int charStart;
  int get length;
  String get text;
}

class TextBlock extends Block {
  const TextBlock(
    super.charStart,
    this.runs, {
    this.kind = BlockKind.paragraph,
    this.level = 0,
    this.depth = 0,
    this.align,
  });
  final List<TextRun> runs;
  final BlockKind kind;

  /// Heading level (1-6) for headings.
  final int level;

  /// Nesting depth for quotes and list items.
  final int depth;

  /// Publisher alignment, when the source asked for one.
  final BlockAlign? align;
  @override
  String get text => runs.map((r) => r.text).join();
  @override
  int get length => text.length;
}

class ImageBlock extends Block {
  const ImageBlock(super.charStart, this.path, this.alt);
  final String path, alt;
  @override
  String get text => ' ';
  @override
  int get length => 1;
}

class RuleBlock extends Block {
  const RuleBlock(super.charStart);
  @override
  String get text => ' ';
  @override
  int get length => 1;
}

class Chapter {
  Chapter(this.index, this.path, this.blocks, this.anchors, this.title);
  final int index;
  final String path;
  final List<Block> blocks;

  /// Element id → chapter character offset, for links and contents entries.
  final Map<String, int> anchors;
  final String title;
  late final int length = blocks.isEmpty
      ? 0
      : blocks.last.charStart + blocks.last.length;
  late final String plainText = blocks.map((b) => b.text).join('\n');
}

class TocEntry {
  const TocEntry(this.title, this.chapter, this.offset, this.depth);
  final String title;
  final int chapter, offset, depth;
}

/// A parsed EPUB with chapters reduced to a typesetting-friendly block model.
class EpubDocument {
  EpubDocument._(
    this.title,
    this.author,
    this.language,
    this.chapters,
    this.toc,
    this._files,
    this.coverPath,
  );
  final String title, author, language;
  final List<Chapter> chapters;
  final List<TocEntry> toc;
  final Map<String, ArchiveFile> _files;
  final String? coverPath;
  late final List<int> chapterStarts = () {
    final starts = <int>[];
    var total = 0;
    for (final c in chapters) {
      starts.add(total);
      total += c.length + 1;
    }
    return starts;
  }();
  late final int length = chapters.isEmpty
      ? 0
      : chapterStarts.last + chapters.last.length;

  Uint8List? resource(String path) {
    final file = _files[path];
    if (file == null) return null;
    return Uint8List.fromList(file.content as List<int>);
  }

  Uint8List? get cover => coverPath == null ? null : resource(coverPath!);

  double progressOf(int chapter, int offset) => length == 0
      ? 0
      : ((chapterStarts[chapter] + offset) / length).clamp(0.0, 1.0);

  /// Chapter and offset at a fraction of the whole book.
  (int, int) locate(double fraction) {
    final target = (fraction.clamp(0.0, 1.0) * length).round();
    var chapter = 0;
    for (var i = 0; i < chapters.length; i++) {
      if (chapterStarts[i] <= target) chapter = i;
    }
    return (
      chapter,
      (target - chapterStarts[chapter]).clamp(0, chapters[chapter].length),
    );
  }

  /// Title of the innermost contents entry at or before a position.
  String chapterTitle(int chapter, int offset) {
    TocEntry? best;
    for (final e in toc) {
      if (e.chapter < chapter || (e.chapter == chapter && e.offset <= offset)) {
        best = e;
      }
    }
    return best?.title ?? chapters[chapter].title;
  }

  /// Resolve an href relative to a chapter to (chapter, offset).
  (int, int)? resolve(String fromPath, String href) {
    if (RegExp(r'^[a-z][a-z0-9+.-]*:', caseSensitive: false).hasMatch(href)) {
      return null;
    }
    final parts = href.split('#');
    final path = parts.first.isEmpty
        ? fromPath
        : _join(_dir(fromPath), Uri.decodeComponent(parts.first));
    final index = chapters.indexWhere((c) => c.path == path);
    if (index < 0) return null;
    final anchor = parts.length > 1 ? parts[1] : null;
    return (index, anchor == null ? 0 : chapters[index].anchors[anchor] ?? 0);
  }

  static EpubDocument parse(Uint8List bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const FormatException('This file is not a valid EPUB.');
    }
    final files = {
      for (final f in archive.files)
        if (f.isFile) f.name: f,
    };
    String? read(String path) {
      final f = files[path];
      if (f == null) return null;
      return utf8.decode(f.content as List<int>, allowMalformed: true);
    }

    final container = read('META-INF/container.xml');
    String? opfPath;
    if (container != null) {
      opfPath = XmlDocument.parse(container).descendantElements
          .where((e) => e.localName == 'rootfile')
          .firstOrNull
          ?.getAttribute('full-path');
    }
    opfPath ??= files.keys.where((k) => k.endsWith('.opf')).firstOrNull;
    final opfText = opfPath == null ? null : read(opfPath);
    if (opfPath == null || opfText == null) {
      throw const FormatException('This EPUB has no package document.');
    }
    final opf = XmlDocument.parse(opfText);
    final base = _dir(opfPath);
    String meta(String name) =>
        opf.descendantElements
            .where((e) => e.localName == name)
            .firstOrNull
            ?.innerText
            .trim() ??
        '';
    final manifest = <String, XmlElement>{
      for (final item in opf.descendantElements.where(
        (e) => e.localName == 'item',
      ))
        item.getAttribute('id') ?? '': item,
    };
    String href(XmlElement item) =>
        _join(base, Uri.decodeComponent(item.getAttribute('href') ?? ''));

    String? coverPath;
    final coverItem =
        manifest.values
            .where(
              (e) => (e.getAttribute('properties') ?? '')
                  .split(' ')
                  .contains('cover-image'),
            )
            .firstOrNull ??
        manifest[opf.descendantElements
                .where(
                  (e) =>
                      e.localName == 'meta' &&
                      e.getAttribute('name') == 'cover',
                )
                .firstOrNull
                ?.getAttribute('content') ??
            ''];
    if (coverItem != null) coverPath = href(coverItem);

    final spine = opf.descendantElements
        .where((e) => e.localName == 'itemref')
        .map((e) => manifest[e.getAttribute('idref')])
        .whereType<XmlElement>()
        .where(
          (e) =>
              (e.getAttribute('media-type') ?? '').contains('html') ||
              (e.getAttribute('href') ?? '').contains('.htm'),
        )
        .toList();
    final chapters = <Chapter>[];
    for (final item in spine) {
      final path = href(item);
      final source = read(path);
      if (source == null) continue;
      chapters.add(_Builder(path, files).build(chapters.length, source));
    }
    if (chapters.isEmpty) {
      throw const FormatException('This EPUB has no readable chapters.');
    }

    final document = EpubDocument._(
      meta('title').isEmpty ? 'Untitled' : meta('title'),
      meta('creator'),
      meta('language'),
      chapters,
      [],
      files,
      coverPath,
    );
    final nav = manifest.values
        .where(
          (e) =>
              (e.getAttribute('properties') ?? '').split(' ').contains('nav'),
        )
        .firstOrNull;
    final ncxId = opf.descendantElements
        .where((e) => e.localName == 'spine')
        .firstOrNull
        ?.getAttribute('toc');
    final ncx =
        manifest[ncxId ?? ''] ??
        manifest.values
            .where(
              (e) => e.getAttribute('media-type') == 'application/x-dtbncx+xml',
            )
            .firstOrNull;
    if (nav != null) {
      final path = href(nav);
      final source = read(path);
      if (source != null) {
        final root = html.parse(source);
        final toc =
            root
                .querySelectorAll('nav')
                .where(
                  (n) =>
                      n.attributes['epub:type'] == 'toc' ||
                      n.attributes['type'] == 'toc' ||
                      n.id == 'toc',
                )
                .firstOrNull ??
            root.querySelector('nav');
        void walk(dom.Element list, int depth) {
          for (final li in list.children.where((c) => c.localName == 'li')) {
            final link = li.children
                .where((c) => c.localName == 'a' || c.localName == 'span')
                .firstOrNull;
            final target = link?.attributes['href'];
            final at = target == null ? null : document.resolve(path, target);
            final title = _clean(link?.text ?? '');
            if (at != null && title.isNotEmpty) {
              document.toc.add(TocEntry(title, at.$1, at.$2, depth));
            }
            for (final child in li.children.where((c) => c.localName == 'ol')) {
              walk(child, depth + 1);
            }
          }
        }

        final list = toc?.querySelector('ol');
        if (list != null) walk(list, 0);
      }
    }
    if (document.toc.isEmpty && ncx != null) {
      final path = href(ncx);
      final source = read(path);
      if (source != null) {
        void walk(XmlElement parent, int depth) {
          for (final point in parent.childElements.where(
            (e) => e.localName == 'navPoint',
          )) {
            final label = _clean(
              point.descendantElements
                      .where((e) => e.localName == 'text')
                      .firstOrNull
                      ?.innerText ??
                  '',
            );
            final src = point.childElements
                .where((e) => e.localName == 'content')
                .firstOrNull
                ?.getAttribute('src');
            final at = src == null ? null : document.resolve(path, src);
            if (at != null && label.isNotEmpty) {
              document.toc.add(TocEntry(label, at.$1, at.$2, depth));
            }
            walk(point, depth + 1);
          }
        }

        final map = XmlDocument.parse(source).descendantElements
            .where((e) => e.localName == 'navMap')
            .firstOrNull;
        if (map != null) walk(map, 0);
      }
    }
    if (document.toc.isEmpty) {
      for (final c in chapters) {
        if (c.title.isNotEmpty) {
          document.toc.add(TocEntry(c.title, c.index, 0, 0));
        }
      }
    }
    return document;
  }
}

String _dir(String path) {
  final i = path.lastIndexOf('/');
  return i < 0 ? '' : path.substring(0, i + 1);
}

String _join(String dir, String relative) {
  final parts = <String>[];
  for (final p in '$dir$relative'.split('/')) {
    if (p == '..') {
      if (parts.isNotEmpty) parts.removeLast();
    } else if (p.isNotEmpty && p != '.') {
      parts.add(p);
    }
  }
  return parts.join('/');
}

String _clean(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();

const _blockTags = {
  'p', 'div', 'section', 'article', 'aside', 'header', 'footer', 'main', //
  'nav', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'blockquote', 'ul', 'ol',
  'li', 'pre', 'hr', 'table', 'tr', 'figure', 'figcaption', 'dl', 'dt',
  'dd', 'center', 'body', 'tbody', 'thead', 'tfoot', 'address', 'hgroup',
};

/// Walks one XHTML document and flattens it into blocks.
class _Builder {
  _Builder(this.path, this.files);
  final String path;
  final Map<String, ArchiveFile> files;
  final blocks = <Block>[];
  final anchors = <String, int>{};
  final _pendingAnchors = <String>[];
  var _runs = <TextRun>[];
  var _offset = 0;
  BlockKind _kind = BlockKind.paragraph;
  int _level = 0, _depth = 0;
  BlockAlign? _align;
  bool _pre = false;
  bool _onlyMarker = false;
  final _lists = <(bool, int)>[];

  Chapter build(int index, String source) {
    // XHTML allows <title/> or <a id="x"/>, which HTML parsing would treat as
    // an unclosed element that swallows the rest of the chapter.
    source = source.replaceAllMapped(
      RegExp(
        r'<(?!(?:br|hr|img|image|meta|link|input|col|area|base|wbr|source|param|embed|track)\b)([a-zA-Z][\w:-]*)(\s[^<>]*?)?\s*/>',
      ),
      (m) => '<${m[1]}${m[2] ?? ''}></${m[1]}>',
    );
    final doc = html.parse(source);
    final body = doc.body ?? doc.documentElement;
    if (body != null) _node(body, const TextRun(''));
    _flush();
    _resolveAnchors();
    var title = '';
    for (final b in blocks) {
      if (b is TextBlock && b.kind == BlockKind.heading) {
        title = _clean(b.text);
        break;
      }
    }
    if (title.isEmpty) {
      title = _clean(doc.querySelector('title')?.text ?? '');
    }
    return Chapter(index, path, blocks, anchors, title);
  }

  void _resolveAnchors() {
    for (final id in _pendingAnchors) {
      anchors[id] = _offset;
    }
    _pendingAnchors.clear();
  }

  void _add(Block block) {
    if (blocks.isNotEmpty) _offset += 1; // newline separator in plain text
    final start = blocks.isEmpty ? 0 : _offset;
    final placed = switch (block) {
      TextBlock b => TextBlock(
        start,
        b.runs,
        kind: b.kind,
        level: b.level,
        depth: b.depth,
        align: b.align,
      ),
      ImageBlock b => ImageBlock(start, b.path, b.alt),
      RuleBlock() => RuleBlock(start),
    };
    for (final id in _pendingAnchors) {
      anchors[id] = start;
    }
    _pendingAnchors.clear();
    blocks.add(placed);
    _offset = start + placed.length;
  }

  void _flush() {
    if (_runs.isEmpty || _onlyMarker) return;
    // Trim collapsible whitespace at the block edges and merge runs.
    final merged = <TextRun>[];
    for (final r in _runs) {
      if (r.text.isEmpty) continue;
      if (merged.isNotEmpty && merged.last.sameStyle(r)) {
        merged[merged.length - 1] = r.withText(merged.last.text + r.text);
      } else {
        merged.add(r);
      }
    }
    _runs = [];
    if (!_pre) {
      while (merged.isNotEmpty) {
        final t = merged.first.text.replaceFirst(RegExp(r'^[ \n]+'), '');
        if (t.isEmpty) {
          merged.removeAt(0);
        } else {
          merged[0] = merged.first.withText(t);
          break;
        }
      }
      while (merged.isNotEmpty) {
        final t = merged.last.text.replaceFirst(RegExp(r'[ \n]+$'), '');
        if (t.isEmpty) {
          merged.removeLast();
        } else {
          merged[merged.length - 1] = merged.last.withText(t);
          break;
        }
      }
    }
    if (merged.isEmpty || merged.every((r) => r.text.trim().isEmpty)) return;
    _add(
      TextBlock(
        0,
        merged,
        kind: _kind,
        level: _level,
        depth: _depth,
        align: _align,
      ),
    );
  }

  bool get _endsWithSpace =>
      _runs.isEmpty ||
      _runs.last.text.endsWith(' ') ||
      _runs.last.text.endsWith('\n');

  BlockAlign? _alignOf(dom.Element e) {
    if (e.localName == 'center') return BlockAlign.center;
    final style = (e.attributes['style'] ?? '').toLowerCase();
    final m = RegExp(r'text-align\s*:\s*(\w+)').firstMatch(style);
    final value = m?.group(1) ?? e.attributes['align']?.toLowerCase();
    return switch (value) {
      'center' => BlockAlign.center,
      'right' || 'end' => BlockAlign.end,
      'justify' => BlockAlign.justify,
      'left' || 'start' => BlockAlign.start,
      _ => null,
    };
  }

  void _node(dom.Node node, TextRun style) {
    if (node is dom.Text) {
      var text = node.text.replaceAll(' ', ' ');
      if (!_pre) {
        text = text.replaceAll(RegExp(r'[\s​]+'), ' ');
        if (text == ' ' && _endsWithSpace) return;
        if (_endsWithSpace) text = text.replaceFirst(RegExp(r'^ '), '');
      }
      if (text.isNotEmpty) {
        if (text.trim().isNotEmpty) _onlyMarker = false;
        _runs.add(style.withText(text));
      }
      return;
    }
    if (node is! dom.Element) return;
    final tag = node.localName ?? '';
    if (const {
      'script',
      'style',
      'head',
      'title',
      'noscript',
      'template',
    }.contains(tag)) {
      return;
    }
    final id = node.id;
    if (id.isNotEmpty) {
      if (_runs.isEmpty) {
        _pendingAnchors.add(id);
      } else {
        anchors[id] = _offset + (blocks.isEmpty ? 0 : 1) + _runText.length;
      }
    }
    final style0 = (node.attributes['style'] ?? '').toLowerCase();
    if (style0.contains('display:none') || style0.contains('display: none')) {
      return;
    }
    if (tag == 'img' || tag == 'image') {
      final src =
          node.attributes['src'] ??
          node.attributes.entries
              .where((a) => a.key.toString().endsWith('href'))
              .firstOrNull
              ?.value;
      if (src != null && !src.startsWith('data:')) {
        final target = _join(
          _dir(path),
          Uri.decodeComponent(src.split('#').first),
        );
        if (files.containsKey(target)) {
          _flush();
          _add(ImageBlock(0, target, node.attributes['alt'] ?? ''));
        }
      }
      return;
    }
    if (tag == 'br') {
      _runs.add(style.withText('\n'));
      return;
    }
    if (tag == 'hr') {
      _flush();
      _add(const RuleBlock(0));
      return;
    }
    if (!_blockTags.contains(tag)) {
      var next = style;
      bool on(Set<String> tags) => tags.contains(tag);
      final s = style0;
      next = TextRun(
        '',
        bold:
            next.bold ||
            on({'b', 'strong'}) ||
            s.contains('font-weight:bold') ||
            s.contains('font-weight: bold'),
        italic:
            next.italic ||
            on({'i', 'em', 'cite', 'dfn', 'var'}) ||
            s.contains('font-style:italic') ||
            s.contains('font-style: italic'),
        underline: next.underline || on({'u', 'ins'}),
        strike: next.strike || on({'s', 'strike', 'del'}),
        mono: next.mono || on({'code', 'kbd', 'samp', 'tt'}),
        sup: next.sup || on({'sup'}),
        sub: next.sub || on({'sub'}),
        small: next.small || on({'small'}),
        href: tag == 'a' ? node.attributes['href'] ?? next.href : next.href,
      );
      for (final child in node.nodes) {
        _node(child, next);
      }
      return;
    }

    // Block-level element.
    _flush();
    final saved = (_kind, _level, _depth, _align, _pre);
    final align = _alignOf(node);
    if (align != null) _align = align;
    switch (tag) {
      case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
        _kind = BlockKind.heading;
        _level = int.parse(tag.substring(1));
      case 'blockquote' || 'dd':
        _kind = BlockKind.quote;
        _depth += 1;
      case 'pre':
        _kind = BlockKind.preformatted;
        _pre = true;
      case 'figcaption':
        _kind = BlockKind.caption;
        _align ??= BlockAlign.center;
      case 'ul' || 'ol':
        _lists.add((
          tag == 'ol',
          int.tryParse(node.attributes['start'] ?? '') ?? 1,
        ));
        _depth += 1;
      case 'li':
        _kind = BlockKind.listItem;
        if (_lists.isNotEmpty) {
          final (ordered, n) = _lists.last;
          _runs.add(TextRun(ordered ? '$n. ' : '• '));
          _lists[_lists.length - 1] = (ordered, n + 1);
        } else {
          _runs.add(const TextRun('• '));
        }
        _onlyMarker = true;
      case 'tr':
        final cells = node.children
            .where((c) => c.localName == 'td' || c.localName == 'th')
            .toList();
        for (var i = 0; i < cells.length; i++) {
          if (i > 0) _runs.add(style.withText(' | '));
          for (final child in cells[i].nodes) {
            _node(
              child,
              cells[i].localName == 'th'
                  ? TextRun('', bold: true, href: style.href)
                  : style,
            );
          }
        }
        _flush();
        _restore(saved);
        return;
    }
    for (final child in node.nodes) {
      _node(
        child,
        tag == 'pre' ? TextRun('', mono: true, href: style.href) : style,
      );
    }
    _flush();
    if (tag == 'li') {
      _onlyMarker = false;
      _runs = [];
    }
    if (tag == 'ul' || tag == 'ol') _lists.removeLast();
    _restore(saved);
  }

  void _restore((BlockKind, int, int, BlockAlign?, bool) saved) {
    _kind = saved.$1;
    _level = saved.$2;
    _depth = saved.$3;
    _align = saved.$4;
    _pre = saved.$5;
  }

  String get _runText => _runs.map((r) => r.text).join();
}
