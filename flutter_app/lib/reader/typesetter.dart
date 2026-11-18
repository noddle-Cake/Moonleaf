import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'epub_document.dart';
import 'reader_settings.dart';

/// One block of a chapter laid out at the current page width.
class LaidBlock {
  LaidBlock(this.block, this.left, this.width, this.before, this.after);
  final Block block;
  final double left, width, before, after;
  TextPainter? painter;
  ui.Image? image;
  Size imageSize = Size.zero;

  /// Placeholder characters (first-line indent) before the block's own text.
  int prefix = 0;

  /// Top of every line within the block, plus the block's total height last.
  List<double> lineTops = const [0];
  double get height => lineTops.last;
  int get lineCount => lineTops.length - 1;

  int localToPainter(int local) => local + prefix;
  int painterToLocal(int index) =>
      (index - prefix).clamp(0, math.max(0, block.length));

  String? linkAt(int local) {
    final b = block;
    if (b is! TextBlock) return null;
    var at = 0;
    for (final r in b.runs) {
      if (local >= at && local < at + r.text.length) return r.href;
      at += r.text.length;
    }
    return null;
  }

  void dispose() {
    painter?.dispose();
    image?.dispose();
  }
}

/// A vertical window of one block placed on a page.
class PageSlice {
  const PageSlice(this.block, this.top, this.bottom, this.y);
  final int block;
  final double top, bottom, y;
}

class PageInfo {
  PageInfo(this.slices, this.start);
  final List<PageSlice> slices;

  /// Chapter offset of the first character on the page.
  final int start;

  /// Chapter offset where the next page starts.
  int end = 0;
}

class ChapterLayout {
  ChapterLayout(this.chapter, this.blocks, this.pages);
  final int chapter;
  final List<LaidBlock> blocks;
  final List<PageInfo> pages;

  int pageOf(int offset) {
    var page = 0;
    for (var i = 0; i < pages.length; i++) {
      if (pages[i].start <= offset) page = i;
    }
    return page;
  }

  /// Character position under a point on a page, if it lands on text.
  ({int block, int local, int offset})? hit(int page, Offset point) {
    for (final s in pages[page].slices) {
      final lb = blocks[s.block];
      if (point.dy < s.y || point.dy > s.y + s.bottom - s.top) continue;
      final painter = lb.painter;
      if (painter == null) return null;
      final local = painter.getPositionForOffset(
        Offset(point.dx - lb.left, point.dy - s.y + s.top),
      );
      final index = lb.painterToLocal(local.offset);
      return (block: s.block, local: index, offset: lb.block.charStart + index);
    }
    return null;
  }

  /// Like [hit], but for a point in a block painted whole (scroll view).
  ({int block, int local, int offset})? hitBlock(int block, Offset point) {
    final lb = blocks[block];
    final painter = lb.painter;
    if (painter == null) return null;
    final index = lb.painterToLocal(
      painter.getPositionForOffset(point - Offset(lb.left, 0)).offset,
    );
    return (block: block, local: index, offset: lb.block.charStart + index);
  }

  int blockAt(int offset) {
    var index = 0;
    for (var i = 0; i < blocks.length; i++) {
      if (blocks[i].block.charStart <= offset) index = i;
    }
    return index;
  }

  void dispose() {
    for (final b in blocks) {
      b.dispose();
    }
  }
}

Size? sniffImageSize(Uint8List b) {
  int u16(int i, [bool big = true]) =>
      big ? (b[i] << 8) | b[i + 1] : b[i] | (b[i + 1] << 8);
  int u32(int i) => (u16(i) << 16) | u16(i + 2);
  try {
    if (b.length > 24 && b[0] == 0x89 && b[1] == 0x50) {
      return Size(u32(16).toDouble(), u32(20).toDouble());
    }
    if (b.length > 10 && b[0] == 0x47 && b[1] == 0x49) {
      return Size(u16(6, false).toDouble(), u16(8, false).toDouble());
    }
    if (b.length > 4 && b[0] == 0xFF && b[1] == 0xD8) {
      var i = 2;
      while (i + 9 < b.length) {
        if (b[i] != 0xFF) {
          i++;
          continue;
        }
        final marker = b[i + 1];
        if (marker >= 0xC0 &&
            marker <= 0xCF &&
            marker != 0xC4 &&
            marker != 0xC8 &&
            marker != 0xCC) {
          return Size(u16(i + 7).toDouble(), u16(i + 5).toDouble());
        }
        i += 2 + u16(i + 2);
      }
    }
    if (b.length > 30 && b[8] == 0x57 && b[9] == 0x45) {
      final kind = String.fromCharCodes(b.sublist(12, 16));
      if (kind == 'VP8X') {
        return Size(
          (1 + (b[24] | b[25] << 8 | b[26] << 16)).toDouble(),
          (1 + (b[27] | b[28] << 8 | b[29] << 16)).toDouble(),
        );
      }
      if (kind == 'VP8 ') {
        return Size(
          (u16(26, false) & 0x3FFF).toDouble(),
          (u16(28, false) & 0x3FFF).toDouble(),
        );
      }
      if (kind == 'VP8L') {
        final bits = b[21] | b[22] << 8 | b[23] << 16 | b[24] << 24;
        return Size(
          ((bits & 0x3FFF) + 1).toDouble(),
          (((bits >> 14) & 0x3FFF) + 1).toDouble(),
        );
      }
    }
  } catch (_) {}
  return null;
}

/// Turns chapters into pages for a page size and set of reader settings.
class Typesetter {
  Typesetter(this.document, this.settings, this.palette, this.page);
  final EpubDocument document;
  final ReaderSettings settings;
  final ReaderPalette palette;

  /// Size of the text area, after margins, header and footer.
  final Size page;
  final _sizes = <String, Size?>{};

  double get em => settings.fontSize;

  TextStyle get baseStyle {
    final font = settings.readerFont;
    return TextStyle(
      fontFamily: font.family,
      fontFamilyFallback: font.fallback,
      fontSize: settings.fontSize,
      height: settings.lineHeight,
      wordSpacing: settings.wordSpacing,
      letterSpacing: settings.letterSpacing,
      fontWeight: _weight(settings.fontWeight),
      fontVariations: [FontVariation.weight(settings.fontWeight.toDouble())],
      color: palette.text,
      leadingDistribution: TextLeadingDistribution.even,
    );
  }

  static FontWeight _weight(int w) =>
      FontWeight.values[((w / 100).round() - 1).clamp(0, 8)];

  TextStyle _runStyle(TextRun r, TextStyle base) {
    var style = base;
    if (r.bold) {
      final w = math.max(700, settings.fontWeight + 300).clamp(100, 900);
      style = style.copyWith(
        fontWeight: _weight(w),
        fontVariations: [FontVariation.weight(w.toDouble())],
      );
    }
    if (r.italic) style = style.copyWith(fontStyle: FontStyle.italic);
    final decorations = [
      if (r.underline || r.href != null) TextDecoration.underline,
      if (r.strike) TextDecoration.lineThrough,
    ];
    if (decorations.isNotEmpty) {
      style = style.copyWith(
        decoration: TextDecoration.combine(decorations),
        decorationColor: r.href != null
            ? palette.muted
            : palette.text.withValues(alpha: .8),
        decorationStyle: r.href != null ? TextDecorationStyle.dotted : null,
      );
    }
    if (r.mono) {
      final mono = builtInFonts['mono']!;
      style = style.copyWith(
        fontFamily: mono.family,
        fontFamilyFallback: mono.fallback,
        fontSize: (style.fontSize ?? em) * .88,
      );
    }
    if (r.sup || r.sub) {
      style = style.copyWith(
        fontSize: (style.fontSize ?? em) * .68,
        fontFeatures: [
          r.sup
              ? const FontFeature.superscripts()
              : const FontFeature.subscripts(),
        ],
      );
    }
    if (r.small) {
      style = style.copyWith(fontSize: (style.fontSize ?? em) * .85);
    }
    return style;
  }

  Size? _imageSize(String path) => _sizes.putIfAbsent(path, () {
    final bytes = document.resource(path);
    return bytes == null ? null : sniffImageSize(bytes);
  });

  /// Lays out and paginates a chapter. With [decode], images are decoded for
  /// painting; without it only their sizes are read (for counting pages).
  Future<ChapterLayout> layout(int index, {bool decode = true}) async {
    final chapter = document.chapters[index];
    final images = <String, ui.Image>{};
    if (decode) {
      for (final b in chapter.blocks.whereType<ImageBlock>()) {
        if (images.containsKey(b.path)) continue;
        final bytes = document.resource(b.path);
        if (bytes == null) continue;
        try {
          final codec = await ui.instantiateImageCodec(bytes);
          final frame = await codec.getNextFrame();
          codec.dispose();
          images[b.path] = frame.image;
          _sizes[b.path] = Size(
            frame.image.width.toDouble(),
            frame.image.height.toDouble(),
          );
        } catch (_) {}
      }
    }
    final blocks = <LaidBlock>[];
    Block? previous;
    for (final block in chapter.blocks) {
      blocks.add(_layBlock(block, previous, images));
      previous = block;
      // Background page counting yields often so reading stays smooth.
      if (!decode && blocks.length % 16 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }
    // Each image block holds its own clone; release the decoded originals.
    for (final image in images.values) {
      image.dispose();
    }
    final pages = _paginate(blocks);
    for (var i = 0; i < pages.length; i++) {
      pages[i].end = i + 1 < pages.length ? pages[i + 1].start : chapter.length;
    }
    return ChapterLayout(index, blocks, pages);
  }

  LaidBlock _layBlock(
    Block block,
    Block? previous,
    Map<String, ui.Image> images,
  ) {
    final width = page.width;
    switch (block) {
      case ImageBlock b:
        final natural = _imageSize(b.path);
        final lb = LaidBlock(block, 0, width, em * .6, em * .6);
        if (natural == null || natural.isEmpty) {
          lb.lineTops = [0, 0];
          return lb;
        }
        final scale = math.min(
          math.min(width / natural.width, page.height / natural.height),
          // Small inline art is enlarged only modestly.
          natural.width < width / 3 ? 2.0 : double.infinity,
        );
        lb.imageSize = natural * scale;
        lb.image = images[b.path]?.clone();
        lb.lineTops = [0, lb.imageSize.height];
        return lb;
      case RuleBlock():
        final lb = LaidBlock(block, 0, width, em * .5, em * .5);
        lb.lineTops = [0, em * 1.2];
        return lb;
      case TextBlock b:
        final base = baseStyle;
        var style = base;
        var align = settings.align == TextAlignment.justify
            ? TextAlign.justify
            : TextAlign.left;
        var before = em * settings.paragraphSpacing;
        var after = 0.0;
        var left = 0.0;
        switch (b.kind) {
          case BlockKind.heading:
            final scale = switch (b.level) {
              1 => 1.45,
              2 => 1.3,
              3 => 1.15,
              _ => 1.05,
            };
            style = style.copyWith(
              fontSize: em * scale,
              height: 1.25,
              fontWeight: FontWeight.w700,
              fontVariations: const [FontVariation('wght', 700)],
            );
            align = settings.publisherAlignment
                ? TextAlign.center
                : TextAlign.left;
            before = previous == null ? 0 : em * 1.6;
            after = em * .9;
          case BlockKind.quote:
            left = em * 1.4 * b.depth.clamp(1, 4);
            style = style.copyWith(fontStyle: FontStyle.italic);
            before = math.max(before, em * .4);
          case BlockKind.listItem:
            left = em * 1.2 * b.depth.clamp(1, 5);
            align = TextAlign.left;
            before = em * .25;
          case BlockKind.preformatted:
            align = TextAlign.left;
            before = em * .4;
            final mono = builtInFonts['mono']!;
            style = style.copyWith(
              fontFamily: mono.family,
              fontFamilyFallback: mono.fallback,
              fontSize: em * .85,
            );
          case BlockKind.caption:
            style = style.copyWith(fontSize: em * .88, color: palette.muted);
            align = TextAlign.center;
          case BlockKind.paragraph:
            break;
        }
        if (settings.publisherAlignment && b.align != null) {
          align = switch (b.align!) {
            BlockAlign.center => TextAlign.center,
            BlockAlign.end => TextAlign.right,
            BlockAlign.justify => TextAlign.justify,
            BlockAlign.start => TextAlign.left,
          };
        }
        final indent =
            b.kind == BlockKind.paragraph &&
            align != TextAlign.center &&
            align != TextAlign.right &&
            settings.indent > 0 &&
            previous is TextBlock &&
            previous.kind == BlockKind.paragraph;
        final lb = LaidBlock(block, left, width - left, before, after);
        final spans = <InlineSpan>[
          if (indent)
            WidgetSpan(
              child: const SizedBox.shrink(),
              alignment: PlaceholderAlignment.middle,
            ),
          for (final r in b.runs)
            TextSpan(text: r.text, style: _runStyle(r, style)),
        ];
        final painter = TextPainter(
          text: TextSpan(style: style, children: spans),
          textAlign: align,
          textDirection: TextDirection.ltr,
        );
        if (indent) {
          lb.prefix = 1;
          painter.setPlaceholderDimensions([
            PlaceholderDimensions(
              size: Size(em * settings.indent, 1),
              alignment: PlaceholderAlignment.middle,
            ),
          ]);
        }
        painter.layout(minWidth: lb.width, maxWidth: lb.width);
        final tops = <double>[0];
        for (final line in painter.computeLineMetrics()) {
          tops.add(tops.last + line.height);
        }
        if (tops.length == 1) tops.add(painter.height);
        tops[tops.length - 1] = math.max(tops.last, painter.height);
        lb
          ..painter = painter
          ..lineTops = tops;
        return lb;
    }
  }

  int _lineStart(LaidBlock lb, int line) {
    final painter = lb.painter;
    if (painter == null || line == 0) return lb.block.charStart;
    final y = (lb.lineTops[line] + lb.lineTops[line + 1]) / 2;
    final pos = painter.getPositionForOffset(Offset(0, y));
    final start = painter.getLineBoundary(pos).start;
    return lb.block.charStart + lb.painterToLocal(start);
  }

  List<PageInfo> _paginate(List<LaidBlock> blocks) {
    final height = page.height;
    final pages = <PageInfo>[];
    var slices = <PageSlice>[];
    var start = 0;
    var y = 0.0;
    var lastAfter = 0.0;
    void newPage(int nextStart) {
      pages.add(PageInfo(slices, start));
      slices = [];
      start = nextStart;
      y = 0;
      lastAfter = 0;
    }

    for (var i = 0; i < blocks.length; i++) {
      final lb = blocks[i];
      var gap = slices.isEmpty ? 0.0 : math.max(lb.before, lastAfter);
      // Keep a heading with the first line of the text that follows it.
      final b = lb.block;
      if (b is TextBlock &&
          b.kind == BlockKind.heading &&
          slices.isNotEmpty &&
          i + 1 < blocks.length) {
        final next = blocks[i + 1];
        final nextLine = next.lineCount > 0 ? next.lineTops[1] : 0.0;
        final need =
            gap + lb.height + math.max(next.before, lb.after) + nextLine;
        if (need > height - y && lb.height + nextLine < height) {
          newPage(b.charStart);
          gap = 0;
        }
      }
      var line = 0;
      while (line < lb.lineCount) {
        final avail = height - y - gap;
        final top = lb.lineTops[line];
        var last = line - 1;
        while (last + 1 < lb.lineCount &&
            lb.lineTops[last + 2] - top <= avail + .5) {
          last++;
        }
        if (last < line) {
          if (slices.isNotEmpty) {
            newPage(_lineStart(lb, line));
            gap = 0;
            continue;
          }
          last = line; // A single line taller than the page.
        }
        if (slices.isEmpty) start = _lineStart(lb, line);
        final bottom = lb.lineTops[last + 1];
        slices.add(PageSlice(i, top, bottom, y + gap));
        y += gap + bottom - top;
        gap = 0;
        line = last + 1;
        if (line < lb.lineCount) newPage(_lineStart(lb, line));
      }
      if (lb.lineCount == 0 || lb.height == 0) continue;
      lastAfter = lb.after;
    }
    if (slices.isNotEmpty || pages.isEmpty) newPage(0);
    return pages;
  }
}

/// Paints one page: highlights, then text, images and rules.
class PagePainter extends CustomPainter {
  PagePainter({
    required this.layout,
    required this.slices,
    required this.palette,
    this.marks = const [],
    this.invertImages = false,
  });
  final ChapterLayout layout;
  final List<PageSlice> slices;
  final ReaderPalette palette;

  /// Chapter ranges to mark: (start, end, color, underline).
  final List<(int, int, Color, bool)> marks;
  final bool invertImages;

  static void paintBlock(
    Canvas canvas,
    LaidBlock lb,
    Offset origin,
    ReaderPalette palette,
    List<(int, int, Color, bool)> marks,
    bool invertImages,
  ) {
    final painter = lb.painter;
    if (painter != null) {
      final start = lb.block.charStart, end = start + lb.block.length;
      for (final (s, e, color, underline) in marks) {
        if (e <= start || s >= end) continue;
        final boxes = painter.getBoxesForSelection(
          TextSelection(
            baseOffset: lb.localToPainter(math.max(s, start) - start),
            extentOffset: lb.localToPainter(math.min(e, end) - start),
          ),
        );
        final paint = Paint()..color = color;
        for (final box in boxes) {
          final r = box.toRect().shift(origin + Offset(lb.left, 0));
          if (underline) {
            canvas.drawRect(
              Rect.fromLTRB(r.left, r.bottom - 2, r.right, r.bottom),
              Paint()..color = palette.text.withValues(alpha: .75),
            );
          } else {
            canvas.drawRRect(
              RRect.fromRectAndRadius(r.inflate(1), const Radius.circular(2)),
              paint,
            );
          }
        }
      }
      painter.paint(canvas, origin + Offset(lb.left, 0));
      return;
    }
    final image = lb.image;
    if (image != null) {
      final dst = Rect.fromLTWH(
        origin.dx + (lb.width - lb.imageSize.width) / 2,
        origin.dy,
        lb.imageSize.width,
        lb.imageSize.height,
      );
      final paint = Paint()..filterQuality = FilterQuality.medium;
      if (invertImages && palette.dark) {
        paint.colorFilter = const ColorFilter.matrix([
          -1, 0, 0, 0, 255, //
          0, -1, 0, 0, 255,
          0, 0, -1, 0, 255,
          0, 0, 0, 1, 0,
        ]);
      } else if (palette.eink) {
        paint.colorFilter = const ColorFilter.matrix([
          .2126, .7152, .0722, 0, 0, //
          .2126, .7152, .0722, 0, 0,
          .2126, .7152, .0722, 0, 0,
          0, 0, 0, 1, 0,
        ]);
      }
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        dst,
        paint,
      );
      return;
    }
    if (lb.block is RuleBlock) {
      final y = origin.dy + lb.height / 2;
      final w = lb.width * .3;
      canvas.drawLine(
        Offset(origin.dx + (lb.width - w) / 2, y),
        Offset(origin.dx + (lb.width + w) / 2, y),
        Paint()
          ..color = palette.muted
          ..strokeWidth = 1,
      );
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in slices) {
      final lb = layout.blocks[s.block];
      canvas.save();
      canvas.clipRect(
        Rect.fromLTRB(
          -200,
          s.y - .5,
          size.width + 200,
          s.y + s.bottom - s.top + .5,
        ),
      );
      paintBlock(
        canvas,
        lb,
        Offset(0, s.y - s.top),
        palette,
        marks,
        invertImages,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(PagePainter old) =>
      old.layout != layout ||
      old.slices != slices ||
      old.palette != palette ||
      old.invertImages != invertImages ||
      !_sameMarks(old.marks, marks);

  static bool _sameMarks(
    List<(int, int, Color, bool)> a,
    List<(int, int, Color, bool)> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class BlockPainter extends CustomPainter {
  BlockPainter(this.block, this.palette, this.marks, this.invertImages);
  final LaidBlock block;
  final ReaderPalette palette;
  final List<(int, int, Color, bool)> marks;
  final bool invertImages;
  @override
  void paint(Canvas canvas, Size size) => PagePainter.paintBlock(
    canvas,
    block,
    Offset.zero,
    palette,
    marks,
    invertImages,
  );
  @override
  bool shouldRepaint(BlockPainter old) =>
      old.block != block ||
      old.palette != palette ||
      !PagePainter._sameMarks(old.marks, marks);
}
