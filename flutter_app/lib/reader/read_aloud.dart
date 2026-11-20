import 'dart:async';

import 'package:flutter/foundation.dart';

import '../speech/speech_engine.dart';

/// What's being read: a range of a chapter's plain text.
typedef Spoken = ({int chapter, int start, int end});

/// Reads a book aloud sentence by sentence, from a place in a chapter
/// onwards into the next chapters. The reader follows [current] to show
/// and highlight what's being read.
class ReadAloud extends ChangeNotifier {
  ReadAloud({required this.chapters, required this.engine, this.onError});

  /// The chapters' plain text. A function, so chapters added while the
  /// book downloads are read too.
  final List<String> Function() chapters;

  /// The voice, looked up for each sentence so voice changes apply at once.
  final Future<SpeechEngine> Function() engine;

  /// Called when the voice fails, with the error.
  final void Function(Object error)? onError;

  int _chapter = 0, _index = 0;
  List<TextRange> _sentences = const [];
  String _text = '';
  bool _playing = false, _disposed = false;

  /// Increases on every start, stop and skip, so an older reading loop
  /// stops when a newer one begins.
  int _run = 0;

  bool get playing => _playing;

  /// The sentence being read (or that will be read on resume).
  Spoken? get current {
    if (_index >= _sentences.length) return null;
    final s = _sentences[_index];
    return (chapter: _chapter, start: s.start, end: s.end);
  }

  /// The words of [current].
  String get currentText {
    final c = current;
    return c == null ? '' : _text.substring(c.start, c.end);
  }

  /// The chapter being read is now number [chapter], after chapters were
  /// added before it while the book downloads.
  void chapterMoved(int chapter) => _chapter = chapter;

  /// Begins reading at [offset] in [chapter].
  void start(int chapter, int offset) {
    _open(chapter);
    _index = _sentences.indexWhere((s) => s.end > offset);
    if (_index < 0) {
      // Past the last sentence: start at the next chapter.
      if (!_openNext()) _index = _sentences.length;
    }
    play();
  }

  void play() {
    if (_disposed) return;
    if (current == null && !_openNext()) return;
    _playing = true;
    notifyListeners();
    unawaited(_loop(++_run));
  }

  Future<void> pause() async {
    if (!_playing) return;
    _playing = false;
    _run++;
    notifyListeners();
    await (await engine()).stop();
  }

  /// Moves [by] sentences (negative to go back), crossing chapters.
  Future<void> skip(int by) async {
    final was = _playing;
    _run++;
    var to = _index + by;
    while (to < 0 && _chapter > 0) {
      _open(_chapter - 1);
      to += _sentences.length;
    }
    while (to >= _sentences.length) {
      final rest = to - _sentences.length;
      if (!_openNext()) {
        to = _sentences.length - 1;
        break;
      }
      to = rest;
    }
    _index = to.clamp(0, _sentences.isEmpty ? 0 : _sentences.length - 1);
    notifyListeners();
    await (await engine()).stop();
    if (was) {
      _playing = true;
      unawaited(_loop(++_run));
    }
  }

  void _open(int chapter) {
    final all = chapters();
    _chapter = chapter.clamp(0, all.isEmpty ? 0 : all.length - 1);
    _text = all.isEmpty ? '' : all[_chapter];
    _sentences = sentenceRanges(_text);
    _index = 0;
  }

  /// Opens the next chapter that has something to read.
  bool _openNext() {
    final all = chapters();
    for (var c = _chapter + 1; c < all.length; c++) {
      final sentences = sentenceRanges(all[c]);
      if (sentences.isEmpty) continue;
      _chapter = c;
      _text = all[c];
      _sentences = sentences;
      _index = 0;
      return true;
    }
    return false;
  }

  Future<void> _loop(int run) async {
    while (run == _run && _playing) {
      if (current == null && !_openNext()) {
        // The end of the book (or of what has downloaded so far).
        _playing = false;
        notifyListeners();
        return;
      }
      final text = currentText;
      final next = _peek();
      try {
        final voice = await engine();
        if (run != _run) return;
        if (next != null) voice.prepare(next);
        final finished = await voice.speak(text);
        if (run != _run) return;
        if (!finished) {
          _playing = false;
          notifyListeners();
          return;
        }
      } catch (e) {
        if (run != _run) return;
        _playing = false;
        notifyListeners();
        onError?.call(e);
        return;
      }
      _index++;
      if (current == null) _openNext();
      notifyListeners();
    }
  }

  /// The sentence after the current one, to prepare.
  String? _peek() {
    if (_index + 1 < _sentences.length) {
      final s = _sentences[_index + 1];
      return _text.substring(s.start, s.end);
    }
    final all = chapters();
    for (var c = _chapter + 1; c < all.length; c++) {
      final sentences = sentenceRanges(all[c]);
      if (sentences.isNotEmpty) {
        return all[c].substring(sentences.first.start, sentences.first.end);
      }
    }
    return null;
  }

  @override
  void dispose() {
    _disposed = true;
    _playing = false;
    _run++;
    unawaited(engine().then((e) => e.stop()).catchError((Object _) {}));
    super.dispose();
  }
}
