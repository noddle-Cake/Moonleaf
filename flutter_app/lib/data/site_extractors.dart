import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import 'novel_service.dart';

class NovelChapter {
  const NovelChapter(this.title, this.content, this.url, this.next);
  final String title;
  final String content;
  final Uri url;
  final Uri? next;
}

/// Add a site's parser here and register it in [extractorFor].
abstract class SiteExtractor {
  const SiteExtractor();

  /// The site's name for messages.
  String get name;

  /// Sites that ask every visitor to pass a human check (Cloudflare) are
  /// loaded through the in-app browser instead of plain requests.
  bool get needsBrowser => false;

  /// Sites that publish their own EPUB: Moonleaf downloads that file instead
  /// of collecting chapters.
  bool get officialEpub => false;

  /// The address to request for a page (for example with consent flags).
  Uri fetchUrl(Uri url) => url;

  /// The official EPUB file linked from a book page.
  Uri? epubLink(String source, Uri page) => null;
  BookMetadata book(String source, Uri url);
  NovelChapter chapter(String source, Uri url, int number);

  /// Whether [url] is a chapter page rather than the novel's main page.
  bool isChapter(Uri url);

  /// The novel's main page when the chapter address alone is enough.
  Uri? novelFromPath(Uri chapter) => null;

  /// The novel's main page as linked from a downloaded chapter page.
  Uri? novelFromChapter(String source, Uri chapter);
}

/// [base]'s site with a new path and no query or fragment.
Uri _page(Uri base, String path) => Uri(
  scheme: base.scheme,
  host: base.host,
  port: base.hasPort ? base.port : null,
  path: path,
);

List<String> _segments(Uri url) =>
    url.pathSegments.where((s) => s.isNotEmpty).toList();

/// The page a breadcrumb trail (schema.org BreadcrumbList) links to just
/// above the current page, or null.
Uri? _breadcrumbParent(Document doc, Uri url, bool Function(Uri) accept) {
  for (final data in structuredData(doc)) {
    if (data['@type'] != 'BreadcrumbList') continue;
    final items =
        (data['itemListElement'] as List? ?? [])
            .whereType<Map<String, dynamic>>()
            .toList()
          ..sort(
            (a, b) => ((a['position'] as num?) ?? 0).compareTo(
              (b['position'] as num?) ?? 0,
            ),
          );
    for (final item in items.reversed) {
      final link = resolveLink(url, valueText(item['item'], '@id'));
      if (link != null && accept(link)) return link;
    }
  }
  return null;
}

SiteExtractor extractorFor(Uri url) {
  if (!['http', 'https'].contains(url.scheme) || url.userInfo.isNotEmpty) {
    throw const ApiException('Enter an HTTP or HTTPS novel URL.');
  }
  switch (url.host.toLowerCase().replaceFirst(RegExp(r'^(www|m)\.'), '')) {
    case 'roliascan.com':
      return const RoliaExtractor();
    case 'royalroad.com':
      return const RoyalRoadExtractor();
    case 'scribblehub.com':
      return const ScribbleHubExtractor();
    case 'fanfiction.net' || 'fictionpress.com':
      return const FanFictionExtractor();
    case 'archiveofourown.org' || 'ao3.org':
      return const Ao3Extractor();
    case 'standardebooks.org':
      return const StandardEbooksExtractor();
    default:
      throw const ApiException(
        'This site is not supported yet. Try Royal Road, Scribble Hub, '
        'FanFiction.net, AO3, Standard Ebooks or RoliaScan.',
      );
  }
}

Uri? resolveLink(Uri base, String? href) {
  if (href == null || href.trim().isEmpty || href.startsWith('#')) return null;
  final url = base.resolve(href.trim());
  return ['http', 'https'].contains(url.scheme) ? url.removeFragment() : null;
}

List<Map<String, dynamic>> structuredData(Document doc) {
  final result = <Map<String, dynamic>>[];
  void visit(dynamic value) {
    if (value is List) {
      for (final item in value) {
        visit(item);
      }
    }
    if (value is Map<String, dynamic>) {
      result.add(value);
      visit(value['@graph']);
    }
  }

  for (final script in doc.querySelectorAll(
    'script[type="application/ld+json"]',
  )) {
    try {
      visit(jsonDecode(script.text));
    } on FormatException {
      /* Ignore malformed site metadata. */
    }
  }
  return result;
}

String valueText(dynamic value, String key) {
  if (value is String) return value;
  if (value is List) {
    return value
        .map((v) => valueText(v, key))
        .where((s) => s.isNotEmpty)
        .join(', ');
  }
  if (value is Map) return valueText(value[key], key);
  return '';
}

NovelChapter parseChapter(
  Document doc,
  Uri url,
  int number,
  String selector,
  Element? next, {
  String? title,
}) {
  final content = doc.querySelector(selector);
  if (content == null) {
    throw const ApiException(
      'No readable chapter text found. This chapter may be restricted or image-only.',
    );
  }
  for (final element in content.querySelectorAll(
    'script,style,iframe,form,.rolia-ad-slot',
  )) {
    element.remove();
  }
  if (content.text.trim().isEmpty) {
    throw const ApiException('This chapter has no readable text.');
  }
  final heading = (title ?? doc.querySelector('h1')?.text ?? '').trim();
  return NovelChapter(
    heading.isEmpty ? 'Chapter $number' : heading,
    content.innerHtml,
    url,
    resolveLink(url, next?.attributes['href']),
  );
}

class RoliaExtractor extends SiteExtractor {
  const RoliaExtractor();

  static bool _isNovelPage(Uri url) {
    final s = _segments(url);
    return url.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '') ==
            'roliascan.com' &&
        ['http', 'https'].contains(url.scheme) &&
        s.length == 2 &&
        s[0] == 'manga';
  }

  @override
  bool isChapter(Uri url) {
    final s = _segments(url);
    return s.length >= 3 && s[0] == 'read';
  }

  @override
  Uri? novelFromChapter(String source, Uri chapter) {
    final doc = html.parse(source);
    final fromCrumbs = _breadcrumbParent(doc, chapter, _isNovelPage);
    if (fromCrumbs != null) return fromCrumbs;
    final slug = _segments(chapter)[1];
    final links = doc
        .querySelectorAll('a[href*="/manga/"]')
        .map((a) => resolveLink(chapter, a.attributes['href']))
        .whereType<Uri>()
        .where(_isNovelPage)
        .toList();
    // Prefer the link for this chapter's own novel over sidebar suggestions.
    return links.where((u) => _segments(u)[1] == slug).firstOrNull ??
        (links.length == 1 ? links.single : null) ??
        _page(chapter, '/manga/$slug/');
  }

  @override
  String get name => 'RoliaScan';

  static bool _isNovelPage(Uri url) {
    final s = _segments(url);
    return url.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '') ==
            'roliascan.com' &&
        ['http', 'https'].contains(url.scheme) &&
        s.length == 2 &&
        s[0] == 'manga';
  }

  @override
  bool isChapter(Uri url) {
    final s = _segments(url);
    return s.length >= 3 && s[0] == 'read';
  }

  @override
  Uri? novelFromChapter(String source, Uri chapter) {
    final doc = html.parse(source);
    final fromCrumbs = _breadcrumbParent(doc, chapter, _isNovelPage);
    if (fromCrumbs != null) return fromCrumbs;
    final slug = _segments(chapter)[1];
    final links = doc
        .querySelectorAll('a[href*="/manga/"]')
        .map((a) => resolveLink(chapter, a.attributes['href']))
        .whereType<Uri>()
        .where(_isNovelPage)
        .toList();
    // Prefer the link for this chapter's own novel over sidebar suggestions.
    return links.where((u) => _segments(u)[1] == slug).firstOrNull ??
        (links.length == 1 ? links.single : null) ??
        _page(chapter, '/manga/$slug/');
  }

  @override
  BookMetadata book(String source, Uri url) {
    final doc = html.parse(source);
    final data =
        structuredData(doc)
            .where(
              (d) =>
                  d['@type'] == 'Book' ||
                  (d['@type'] is List && (d['@type'] as List).contains('Book')),
            )
            .firstOrNull ??
        {};
    final first = resolveLink(
      url,
      doc
          .querySelector(
            'a#start-reading-btn[href],a.mobile-start-reading-btn[href]',
          )
          ?.attributes['href'],
    );
    final image = valueText(data['image'], 'url');
    return BookMetadata(
      title:
          doc.querySelector('h1')?.text.trim() ??
          valueText(data['name'], 'name'),
      author: valueText(data['author'], 'name'),
      firstChapter: first?.toString() ?? '',
      coverUrl: resolveLink(
        url,
        image.isEmpty
            ? doc
                  .querySelector('meta[property="og:image"]')
                  ?.attributes['content']
            : image,
      )?.toString(),
      description:
          doc.querySelector('#description-content-tab')?.text.trim() ??
          valueText(data['description'], 'description'),
    );
  }

  @override
  NovelChapter chapter(String source, Uri url, int number) {
    final doc = html.parse(source);
    final next =
        doc.querySelector(
          'a[title="Next Chapter"][href],a[rel~="next"][href]',
        ) ??
        doc
            .querySelectorAll('a[href]')
            .where(
              (a) => (a.attributes['title'] ?? '').startsWith('Next: Chapter'),
            )
            .firstOrNull;
    return parseChapter(doc, url, number, '.reader-text', next);
  }
}

class RoyalRoadExtractor extends SiteExtractor {
  const RoyalRoadExtractor();

  @override
  bool isChapter(Uri url) {
    final s = _segments(url);
    return s.isNotEmpty && s[0] == 'fiction' && s.contains('chapter');
  }

  /// `/fiction/<id>/<slug>/chapter/<id>/<slug>` → `/fiction/<id>/<slug>`.
  @override
  Uri? novelFromPath(Uri chapter) {
    final s = _segments(chapter);
    final at = s.indexOf('chapter');
    if (at < 2 || int.tryParse(s[1]) == null) return null;
    return _page(chapter, '/${s.sublist(0, at).join('/')}');
  }

  /// Short links such as `/fiction/chapter/<id>` name only the chapter, so
  /// read the full address from the page itself.
  @override
  Uri? novelFromChapter(String source, Uri chapter) {
    final doc = html.parse(source);
    for (final href in [
      doc.querySelector('link[rel="canonical"]')?.attributes['href'],
      doc.querySelector('meta[property="og:url"]')?.attributes['content'],
    ]) {
      final full = resolveLink(chapter, href);
      final novel = full == null ? null : novelFromPath(full);
      if (novel != null) return novel;
    }
    for (final a in doc.querySelectorAll('a[href^="/fiction/"]')) {
      final link = resolveLink(chapter, a.attributes['href']);
      final s = link == null ? const <String>[] : _segments(link);
      if (link != null &&
          s.length >= 2 &&
          !s.contains('chapter') &&
          int.tryParse(s[1]) != null) {
        return _page(link, link.path);
      }
    }
    return null;
  }

  @override
  String get name => 'Royal Road';

  @override
  bool isChapter(Uri url) {
    final s = _segments(url);
    return s.isNotEmpty && s[0] == 'fiction' && s.contains('chapter');
  }

  /// `/fiction/<id>/<slug>/chapter/<id>/<slug>` → `/fiction/<id>/<slug>`.
  @override
  Uri? novelFromPath(Uri chapter) {
    final s = _segments(chapter);
    final at = s.indexOf('chapter');
    if (at < 2 || int.tryParse(s[1]) == null) return null;
    return _page(chapter, '/${s.sublist(0, at).join('/')}');
  }

  /// Short links such as `/fiction/chapter/<id>` name only the chapter, so
  /// read the full address from the page itself.
  @override
  Uri? novelFromChapter(String source, Uri chapter) {
    final doc = html.parse(source);
    for (final href in [
      doc.querySelector('link[rel="canonical"]')?.attributes['href'],
      doc.querySelector('meta[property="og:url"]')?.attributes['content'],
    ]) {
      final full = resolveLink(chapter, href);
      final novel = full == null ? null : novelFromPath(full);
      if (novel != null) return novel;
    }
    for (final a in doc.querySelectorAll('a[href^="/fiction/"]')) {
      final link = resolveLink(chapter, a.attributes['href']);
      final s = link == null ? const <String>[] : _segments(link);
      if (link != null &&
          s.length >= 2 &&
          !s.contains('chapter') &&
          int.tryParse(s[1]) != null) {
        return _page(link, link.path);
      }
    }
    return null;
  }

  @override
  BookMetadata book(String source, Uri url) {
    final doc = html.parse(source);
    final data =
        structuredData(doc).where((d) => d['name'] != null).firstOrNull ?? {};
    String? href = doc
        .querySelector('#chapters tbody a[href*="/chapter/"]')
        ?.attributes['href'];
    final action = data['potentialAction'];
    if (href == null && action is Map && action['target'] is Map) {
      href = action['target']['urlTemplate'] as String?;
    }
    return BookMetadata(
      title: valueText(data['name'], 'name').isNotEmpty
          ? valueText(data['name'], 'name')
          : doc.querySelector('h1')?.text.trim() ?? '',
      author:
          doc.querySelector('a[href^="/profile/"]')?.text.trim() ??
          valueText(data['author'], 'name'),
      firstChapter: resolveLink(url, href)?.toString() ?? '',
      coverUrl: resolveLink(
        url,
        valueText(data['thumbnailUrl'], 'url'),
      )?.toString(),
    );
  }

  @override
  NovelChapter chapter(String source, Uri url, int number) {
    final doc = html.parse(source);
    final next =
        doc.querySelector('a[rel~="next"][href]') ??
        doc
            .querySelectorAll('a[href*="/chapter/"]')
            .where((a) => a.text.trim().toLowerCase() == 'next chapter')
            .firstOrNull;
    return parseChapter(doc, url, number, '.chapter-content', next);
  }
}

String _text(Element? e) =>
    e?.text.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';

/// Scribble Hub: original web novels. Pages sit behind a human check, so
/// they load through the in-app browser.
class ScribbleHubExtractor extends SiteExtractor {
  const ScribbleHubExtractor();
  @override
  String get name => 'Scribble Hub';
  @override
  bool get needsBrowser => true;

  @override
  bool isChapter(Uri url) {
    final s = _segments(url);
    return s.length >= 3 && s[0] == 'read' && s.contains('chapter');
  }

  /// `/read/<id>-<slug>/chapter/<n>/` → `/series/<id>/<slug>/`.
  @override
  Uri? novelFromPath(Uri chapter) {
    final s = _segments(chapter);
    final m = s.length >= 2 ? RegExp(r'^(\d+)-(.+)$').firstMatch(s[1]) : null;
    return m == null ? null : _page(chapter, '/series/${m[1]}/${m[2]}/');
  }

  @override
  Uri? novelFromChapter(String source, Uri chapter) => novelFromPath(chapter);

  @override
  BookMetadata book(String source, Uri url) {
    final doc = html.parse(source);
    var first = doc
        .querySelectorAll('a[href*="/chapter/"]')
        .where((a) => _text(a).toLowerCase().contains('read first'))
        .firstOrNull
        ?.attributes['href'];
    if (first == null) {
      // The contents list is ordered by chapter number in `order`.
      final items = doc.querySelectorAll('li.toc_w[order]').toList()
        ..sort(
          (a, b) => (int.tryParse(a.attributes['order']!) ?? 1 << 30).compareTo(
            int.tryParse(b.attributes['order']!) ?? 1 << 30,
          ),
        );
      first = items.firstOrNull
          ?.querySelector('a.toc_a[href]')
          ?.attributes['href'];
    }
    return BookMetadata(
      title: _text(doc.querySelector('.fic_title')),
      author: _text(doc.querySelector('.auth_name_fic')),
      firstChapter: resolveLink(url, first)?.toString() ?? '',
      coverUrl: resolveLink(
        url,
        doc.querySelector('.fic_image img')?.attributes['src'],
      )?.toString(),
      description: _text(doc.querySelector('.wi_fic_desc')),
    );
  }

  @override
  NovelChapter chapter(String source, Uri url, int number) {
    final doc = html.parse(source);
    final next = doc
        .querySelectorAll('a.btn-next[href]')
        .where(
          (a) =>
              !a.classes.contains('disabled') &&
              (a.attributes['href'] ?? '').contains('/chapter/'),
        )
        .firstOrNull;
    return parseChapter(
      doc,
      url,
      number,
      '#chp_raw',
      next,
      title: _text(doc.querySelector('.chapter-title')),
    );
  }
}

/// FanFiction.net and FictionPress share one layout. A story's "main page"
/// is its first chapter. Pages load through the in-app browser.
class FanFictionExtractor extends SiteExtractor {
  const FanFictionExtractor();
  @override
  String get name => 'FanFiction.net';
  @override
  bool get needsBrowser => true;

  /// Mobile pages use a different layout; always ask for the desktop one.
  @override
  Uri fetchUrl(Uri url) => url.host.startsWith('m.')
      ? url.replace(host: 'www.${url.host.substring(2)}')
      : url;

  static Uri? _chapterPage(Uri url, int chapter) {
    final s = _segments(url);
    if (s.length < 2 || s[0] != 's' || int.tryParse(s[1]) == null) {
      return null;
    }
    return _page(
      url,
      ['', 's', s[1], '$chapter', if (s.length > 3) s[3]].join('/'),
    );
  }

  @override
  bool isChapter(Uri url) {
    final s = _segments(url);
    // Mobile links count too, so they're saved under the desktop address.
    return s.length >= 3 &&
        s[0] == 's' &&
        (s[2] != '1' || url.host.startsWith('m.'));
  }

  @override
  Uri? novelFromPath(Uri chapter) {
    final first = _chapterPage(chapter, 1);
    return first == null ? null : fetchUrl(first);
  }
  @override
  Uri? novelFromChapter(String source, Uri chapter) => novelFromPath(chapter);

  @override
  BookMetadata book(String source, Uri url) {
    final doc = html.parse(source);
    final profile = doc.querySelector('#profile_top');
    final cover = profile?.querySelector('img.cimage');
    return BookMetadata(
      title: _text(profile?.querySelector('b.xcontrast_txt')),
      author: _text(profile?.querySelector('a[href^="/u/"]')),
      firstChapter: (_chapterPage(url, 1) ?? url).toString(),
      coverUrl: resolveLink(
        url,
        cover?.attributes['data-original'] ?? cover?.attributes['src'],
      )?.toString(),
      description: _text(profile?.querySelector('div.xcontrast_txt')),
    );
  }

  @override
  NovelChapter chapter(String source, Uri url, int number) {
    final doc = html.parse(source);
    // Navigation buttons use onclick="self.location='/s/1/2/slug'".
    Element? next;
    for (final b in doc.querySelectorAll('[onclick*="self.location"]')) {
      if (!_text(b).toLowerCase().startsWith('next')) continue;
      final m = RegExp(r"""self\.location\s*=\s*['"]([^'"]+)""")
          .firstMatch(b.attributes['onclick']!);
      if (m != null) {
        next = Element.tag('a')..attributes['href'] = m[1]!;
        break;
      }
    }
    final selected = doc.querySelector(
      'select[name="chapter"] option[selected]',
    );
    final title = selected == null
        ? _text(doc.querySelector('#profile_top b.xcontrast_txt'))
        : _text(selected).replaceFirst(RegExp(r'^\d+\.\s*'), '');
    return parseChapter(doc, url, number, '#storytext', next, title: title);
  }
}

/// Archive of Our Own publishes an EPUB of every work; Moonleaf downloads it.
class Ao3Extractor extends SiteExtractor {
  const Ao3Extractor();
  @override
  String get name => 'AO3';
  @override
  bool get officialEpub => true;

  /// Skips the "this work may have adult content" notice.
  @override
  Uri fetchUrl(Uri url) => url.replace(
    queryParameters: {...url.queryParameters, 'view_adult': 'true'},
  );

  int? _workId(Uri url) {
    final s = _segments(url);
    final at = s.indexOf('works');
    return at >= 0 && at + 1 < s.length ? int.tryParse(s[at + 1]) : null;
  }

  @override
  bool isChapter(Uri url) => _workId(url) != null && _segments(url).length > 2;

  /// `/works/1/chapters/2` and `/collections/x/works/1` → `/works/1`.
  @override
  Uri? novelFromPath(Uri chapter) {
    final id = _workId(chapter);
    return id == null ? null : _page(chapter, '/works/$id');
  }

  @override
  Uri? novelFromChapter(String source, Uri chapter) => novelFromPath(chapter);

  @override
  BookMetadata book(String source, Uri url) {
    if (source.contains('only available to registered users')) {
      throw const ApiException(
        'This AO3 work is visible only to signed-in members, so Moonleaf can’t download it.',
      );
    }
    final doc = html.parse(source);
    final title = _text(doc.querySelector('h2.title.heading'));
    if (title.isEmpty) {
      throw const ApiException('This doesn’t look like an AO3 work page.');
    }
    return BookMetadata(
      title: title,
      author: doc
          .querySelectorAll(
            'h3.byline a[rel^="author"], h3.heading a[rel^="author"]',
          )
          .map(_text)
          .toSet()
          .join(', '),
      firstChapter: (novelFromPath(url) ?? url).toString(),
      description: _text(doc.querySelector('.summary blockquote.userstuff')),
    );
  }

  @override
  Uri? epubLink(String source, Uri page) {
    final doc = html.parse(source);
    final link = doc
        .querySelectorAll('li.download a[href*="/downloads/"]')
        .map((a) => resolveLink(page, a.attributes['href']))
        .whereType<Uri>()
        .where((u) => u.path.toLowerCase().endsWith('.epub'))
        .firstOrNull;
    if (link != null) return link;
    // AO3 serves downloads by work id; the file name is cosmetic.
    final id = _workId(page);
    return id == null ? null : _page(page, '/downloads/$id/work.epub');
  }

  @override
  NovelChapter chapter(String source, Uri url, int number) =>
      throw const ApiException('AO3 books are downloaded as one EPUB.');
}

/// Standard Ebooks: free, carefully produced public-domain EPUBs.
class StandardEbooksExtractor extends SiteExtractor {
  const StandardEbooksExtractor();
  @override
  String get name => 'Standard Ebooks';
  @override
  bool get officialEpub => true;

  /// The book page is `/ebooks/<author>/<title>[/<translator>…]`; reading
  /// pages and downloads hang off it.
  @override
  bool isChapter(Uri url) {
    final s = _segments(url);
    return s.isNotEmpty &&
        s[0] == 'ebooks' &&
        (s.contains('text') || s.contains('downloads'));
  }

  @override
  Uri? novelFromPath(Uri chapter) {
    final s = _segments(chapter);
    final end = s.indexWhere((p) => p == 'text' || p == 'downloads');
    return end < 3 ? null : _page(chapter, '/${s.sublist(0, end).join('/')}');
  }

  @override
  Uri? novelFromChapter(String source, Uri chapter) => novelFromPath(chapter);

  @override
  BookMetadata book(String source, Uri url) {
    final doc = html.parse(source);
    final title = _text(doc.querySelector('h1[property="schema:name"]'));
    if (title.isEmpty) {
      throw const ApiException(
        'Open a book’s page on Standard Ebooks, not a list of books.',
      );
    }
    final cover = doc
        .querySelectorAll('img[src*="/images/covers/"]')
        .map((i) => i.attributes['src']!)
        .where((src) => src.endsWith('/cover.jpg'))
        .firstOrNull;
    return BookMetadata(
      title: title,
      author: doc
          .querySelectorAll(
            '[property="schema:author"] [property="schema:name"]',
          )
          .map(_text)
          .where((n) => n.isNotEmpty)
          .toSet()
          .join(', '),
      firstChapter: url.toString(),
      coverUrl: resolveLink(url, cover)?.toString(),
      description: _text(
        doc.querySelector('#description [property="schema:description"] p') ??
            doc.querySelector('#description [property="schema:description"]'),
      ),
    );
  }

  /// The "compatible" EPUB, which works in every reader.
  @override
  Uri? epubLink(String source, Uri page) => html
      .parse(source)
      .querySelectorAll('a[href\$=".epub"]')
      .map((a) => resolveLink(page, a.attributes['href']))
      .whereType<Uri>()
      .where(
        (u) =>
            !u.path.endsWith('.kepub.epub') &&
            !u.path.endsWith('_advanced.epub'),
      )
      .firstOrNull;

  @override
  NovelChapter chapter(String source, Uri url, int number) =>
      throw const ApiException(
        'Standard Ebooks books are downloaded as one EPUB.',
      );
}

/// Prevent a navigation link from silently extracting a different novel.
bool sameNovel(Uri first, Uri next) {
  String host(Uri u) =>
      u.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
  if (host(first) != host(next) ||
      !['http', 'https'].contains(next.scheme) ||
      next.userInfo.isNotEmpty) {
    return false;
  }
  final a = first.pathSegments.where((s) => s.isNotEmpty).toList();
  final b = next.pathSegments.where((s) => s.isNotEmpty).toList();
  switch (host(first).replaceFirst(RegExp(r'^m\.'), '')) {
    case 'scribblehub.com':
      String? story(List<String> s) =>
          s.length >= 3 && s[0] == 'read' ? s[1].split('-').first : null;
      return story(a) != null && story(a) == story(b);
    case 'fanfiction.net' || 'fictionpress.com':
      return a.length >= 3 &&
          b.length >= 3 &&
          a[0] == 's' &&
          b[0] == 's' &&
          a[1] == b[1];
    case 'archiveofourown.org' || 'ao3.org':
      String? work(List<String> s) {
        final at = s.indexOf('works');
        return at >= 0 && at + 1 < s.length ? s[at + 1] : null;
      }
      return work(a) != null && work(a) == work(b);
    case 'standardebooks.org':
      return a.length >= 3 && a.join('/') == b.join('/');
  }
  if (host(first) == 'roliascan.com') {
    return a.length >= 3 &&
        b.length >= 3 &&
        a[0] == 'read' &&
        b[0] == 'read' &&
        a[1] == b[1];
  }
  return a.length >= 4 &&
      b.length >= 4 &&
      a[0] == 'fiction' &&
      b[0] == 'fiction' &&
      a[1] == b[1] &&
      b.contains('chapter');
}
