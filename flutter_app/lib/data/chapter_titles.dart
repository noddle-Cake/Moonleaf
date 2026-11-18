/// Tidies a chapter name taken from a site into "Chapter N: Name".
///
/// - Drops the book's title when the site repeats it in the chapter heading
///   ("My Novel Chapter 3" → "Chapter 3").
/// - Keeps the site's own chapter number when the name starts with one
///   ("Ch. 12 - The Fall", "12. The Fall" → "Chapter 12: The Fall").
/// - Otherwise numbers the chapter by its position ("Prologue" →
///   "Chapter 1: Prologue").
String cleanChapterTitle(String raw, String bookTitle, int position) {
  var title = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  final book = bookTitle.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (book.length >= 3) {
    title = title.replaceAll(
      RegExp(RegExp.escape(book), caseSensitive: false),
      ' ',
    );
  }
  title = _trimSeparators(title.replaceAll(RegExp(r'\s+'), ' '));
  final numbered = RegExp(
    r'^(?:chapter|chap|ch|episode|ep)\.?\s*#?\s*(\d+(?:\.\d+)?)(?![\d])\s*(.*)$',
    caseSensitive: false,
  ).firstMatch(title);
  final bare = RegExp(r'^#?(\d+(?:\.\d+)?)\s*(?:[:.\-–—|)]\s*|\s+-\s*)(.*)$')
      .firstMatch(title);
  final match = numbered ?? bare;
  if (match != null) {
    final number = match.group(1)!;
    final rest = _trimSeparators(match.group(2) ?? '');
    // "Chapter 3: Chapter 3" and similar repeats collapse to one.
    final repeat = RegExp(
      r'^(?:chapter|chap|ch)\.?\s*' + RegExp.escape(number) + r'$',
      caseSensitive: false,
    );
    return rest.isEmpty || repeat.hasMatch(rest)
        ? 'Chapter $number'
        : 'Chapter $number: $rest';
  }
  return title.isEmpty ? 'Chapter $position' : 'Chapter $position: $title';
}

String _trimSeparators(String value) => value
    .replaceAll(RegExp(r'^[\s:\-–—|·,.()\[\]]+'), '')
    .replaceAll(RegExp(r'[\s:\-–—|·,(\[]+$'), '')
    .trim();
