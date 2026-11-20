/// A voice that reads text aloud: the phone's own text-to-speech or the
/// natural voice downloaded into the app.
abstract class SpeechEngine {
  /// Reads [text] aloud. Completes with true when it finished, or false
  /// when [stop] cut it short.
  Future<bool> speak(String text);

  /// Gets ready to read [text] next, so there's no pause before it. Engines
  /// that need no preparation ignore it.
  void prepare(String text) {}

  /// Stops reading at once.
  Future<void> stop();

  Future<void> dispose() => stop();
}

/// A voice offered in the voice picker.
class SpeechVoice {
  const SpeechVoice(this.id, this.name, {this.detail = ''});

  /// Stable identifier saved in settings.
  final String id;
  final String name;

  /// Language or description shown under the name.
  final String detail;
}

/// A sentence (or a piece of a long one) to read: its range in the
/// chapter's plain text.
typedef TextRange = ({int start, int end});

/// Splits [text] into sentences to read one at a time, as ranges into
/// [text]. Paragraph breaks end a sentence, very long sentences are split at
/// commas or spaces, and pieces with nothing to say (images, punctuation)
/// are left out.
List<TextRange> sentenceRanges(String text, {int maxLength = 280}) {
  final out = <TextRange>[];
  final speakable = RegExp(r'[\p{L}\p{N}]', unicode: true);
  void add(int start, int end) {
    while (start < end && _isSpace(text.codeUnitAt(start))) {
      start++;
    }
    while (end > start && _isSpace(text.codeUnitAt(end - 1))) {
      end--;
    }
    if (end <= start) return;
    // Split long runs at the last comma, semicolon or space that fits.
    while (end - start > maxLength) {
      var cut = -1;
      for (final mark in const [';', ',', ':', ' ']) {
        cut = text.lastIndexOf(mark, start + maxLength);
        if (cut > start + maxLength ~/ 3) break;
        cut = -1;
      }
      if (cut < 0) cut = start + maxLength - 1;
      add(start, cut + 1);
      start = cut + 1;
      while (start < end && _isSpace(text.codeUnitAt(start))) {
        start++;
      }
    }
    if (speakable.hasMatch(text.substring(start, end))) {
      out.add((start: start, end: end));
    }
  }

  // A sentence ends at . ! ? … (with closing quotes or brackets after it)
  // followed by a space, or at a line break.
  final end = RegExp('[.!?…]+[\'"”’)\\]]*(?=\\s)|\\n+|￼');
  var start = 0;
  for (final m in end.allMatches(text)) {
    final isBreak = m.group(0)!.startsWith('\n') || m.group(0) == '￼';
    final stop = isBreak ? m.start : m.end;
    // "Mr." and single initials don't end a sentence.
    if (!isBreak && _abbreviation(text, m.start)) continue;
    add(start, stop);
    start = m.end;
  }
  add(start, text.length);
  return out;
}

bool _isSpace(int c) => c == 32 || c == 9 || c == 10 || c == 13 || c == 160;

const _abbreviations = {
  'mr', 'mrs', 'ms', 'dr', 'st', 'sr', 'jr', 'vs', 'etc', 'prof', 'mt', //
};

bool _abbreviation(String text, int dot) {
  if (text.codeUnitAt(dot) != 46) return false; // Only '.'.
  var i = dot;
  while (i > 0 && RegExp(r'\w').hasMatch(text[i - 1])) {
    i--;
  }
  final word = text.substring(i, dot).toLowerCase();
  if (word.length == 1 && RegExp(r'[a-z]').hasMatch(word)) {
    // An initial ("J. K."), but not the end of "a." etc. after a space.
    return word.toUpperCase() == text.substring(i, dot);
  }
  return _abbreviations.contains(word);
}
