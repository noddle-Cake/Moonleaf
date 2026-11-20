import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_to_epub/reader/read_aloud.dart';
import 'package:novel_to_epub/speech/speech_engine.dart';

/// A voice that finishes each sentence only when the test says so.
class FakeVoice extends SpeechEngine {
  final spoken = <String>[];
  final prepared = <String>[];
  Completer<bool>? _now;
  int stops = 0;
  Object? failWith;

  bool get speaking => _now != null && !_now!.isCompleted;

  @override
  Future<bool> speak(String text) {
    if (failWith case final e?) return Future.error(e);
    spoken.add(text);
    return (_now = Completer<bool>()).future;
  }

  @override
  void prepare(String text) => prepared.add(text);

  /// Finishes the sentence being read (in widget tests, pump after).
  void complete() => _now?.complete(true);

  /// Finishes the sentence being read.
  Future<void> finish() async {
    _now?.complete(true);
    await pumpEventQueue();
  }

  @override
  Future<void> stop() async {
    stops++;
    if (speaking) _now!.complete(false);
  }
}

List<String> sentences(String text) => [
  for (final r in sentenceRanges(text)) text.substring(r.start, r.end),
];

void main() {
  group('sentences', () {
    test('split at sentence ends and paragraphs', () {
      expect(sentences('It rained. "Run!" she said? Fine…\nNew paragraph'), [
        'It rained.',
        '"Run!"',
        'she said?',
        'Fine…',
        'New paragraph',
      ]);
    });

    test('keep titles and initials in the sentence', () {
      expect(sentences('Mr. Lee met J. K. Smith. Then left.'), [
        'Mr. Lee met J. K. Smith.',
        'Then left.',
      ]);
    });

    test('leave out images and punctuation-only pieces', () {
      expect(sentences('Before.\n￼\n* * *\nAfter.'), ['Before.', 'After.']);
    });

    test('split very long sentences at commas', () {
      final long = List.filled(30, 'and the river ran on').join(', ');
      final parts = sentenceRanges(long, maxLength: 100);
      expect(parts.length, greaterThan(3));
      for (final p in parts) {
        expect(p.end - p.start, lessThanOrEqualTo(100));
      }
      // Nothing is lost between pieces but the commas' spaces.
      expect(parts.map((p) => long.substring(p.start, p.end)).join(' '), long);
    });

    test('ranges point into the text', () {
      const text = '  Hello there.  General Kenobi!';
      final r = sentenceRanges(text);
      expect(text.substring(r[1].start, r[1].end), 'General Kenobi!');
    });
  });

  group('ReadAloud', () {
    late FakeVoice voice;
    late List<String> chapters;
    late ReadAloud aloud;
    final errors = <Object>[];

    setUp(() {
      voice = FakeVoice();
      chapters = ['One. Two. Three.', '￼', 'Four. Five.'];
      errors.clear();
      aloud = ReadAloud(
        chapters: () => chapters,
        engine: () async => voice,
        onError: errors.add,
      );
    });

    tearDown(() => aloud.dispose());

    test('reads from a place onwards, across chapters', () async {
      aloud.start(0, 5); // In "Two."
      await pumpEventQueue();
      expect(voice.spoken, ['Two.']);
      expect(voice.prepared.last, 'Three.');
      await voice.finish();
      expect(voice.spoken.last, 'Three.');
      // The next chapter has only an image, so it's skipped.
      expect(voice.prepared.last, 'Four.');
      await voice.finish();
      expect(voice.spoken.last, 'Four.');
      expect(aloud.current, (chapter: 2, start: 0, end: 5));
      await voice.finish();
      await voice.finish();
      expect(voice.spoken, ['Two.', 'Three.', 'Four.', 'Five.']);
      expect(aloud.playing, isFalse);
    });

    test('pauses and resumes the same sentence', () async {
      aloud.start(0, 0);
      await pumpEventQueue();
      await aloud.pause();
      expect(aloud.playing, isFalse);
      expect(voice.stops, greaterThan(0));
      aloud.play();
      await pumpEventQueue();
      expect(voice.spoken, ['One.', 'One.']);
    });

    test('skips forward and back', () async {
      aloud.start(0, 0);
      await pumpEventQueue();
      await aloud.skip(1);
      await pumpEventQueue();
      expect(voice.spoken.last, 'Two.');
      await aloud.skip(3);
      await pumpEventQueue();
      expect(voice.spoken.last, 'Five.');
      await aloud.skip(-2);
      await pumpEventQueue();
      expect(voice.spoken.last, 'Three.');
      expect(aloud.playing, isTrue);
    });

    test('reads chapters added while the book downloads', () async {
      chapters = ['Only.'];
      aloud.start(0, 0);
      await pumpEventQueue();
      chapters = ['Only.', 'Arrived.'];
      await voice.finish();
      expect(voice.spoken, ['Only.', 'Arrived.']);
    });

    test('stops and reports a voice that fails', () async {
      voice.failWith = StateError('no voice');
      aloud.start(0, 0);
      await pumpEventQueue();
      expect(aloud.playing, isFalse);
      expect(errors, hasLength(1));
    });
  });
}
