import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:novel_to_epub/reader/dictionary.dart';

Future<ByteData> _wordNet() async {
  final bytes = await File(Dictionary.wordNetAsset).readAsBytes();
  return ByteData.sublistView(bytes);
}

/// A dictionary that can't reach Wiktionary, so WordNet answers.
Dictionary _offline() => Dictionary(
  client: MockClient((_) async => throw const SocketException('offline')),
  wordNet: _wordNet,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('picks the word out of a selection', () {
    expect(Dictionary.lookupText('“Hello,”'), 'Hello');
    expect(Dictionary.lookupText(' wizard’s '), "wizard's");
    expect(Dictionary.lookupText('give up', words: 1), isNull);
    expect(Dictionary.lookupText('give up'), 'give up');
    expect(Dictionary.lookupText('chapter 7'), isNull);
    expect(Dictionary.lookupText('...'), isNull);
    expect(Dictionary.lookupText('Ångström'), 'Ångström');
  });

  test('reads Wiktionary definitions without sub-senses or markup', () {
    final body = File('test/fixtures/wiktionary_running.json')
        .readAsStringSync();
    final d = Dictionary.parseWiktionary('running', body, 'en')!;
    expect(d.offline, isFalse);
    expect(d.meanings.map((m) => m.partOfSpeech), contains('adjective'));
    final adjective = d.meanings.firstWhere(
      (m) => m.partOfSpeech == 'adjective',
    );
    expect(adjective.senses.first.definition, 'Moving or advancing at a run.');
    for (final m in d.meanings) {
      for (final s in m.senses) {
        expect(s.definition, isNot(contains('<')));
        expect(s.definition, isNotEmpty);
      }
    }
    expect(Dictionary.parseWiktionary('running', body, 'fr'), isNull);
  });

  test('asks Wiktionary, lowercase first', () async {
    final asked = <String>[];
    final dictionary = Dictionary(
      client: MockClient((request) async {
        asked.add(request.url.path.split('/').last);
        if (request.url.path.endsWith('/lantern')) {
          return http.Response(
            '{"en":[{"partOfSpeech":"Noun","definitions":'
            '[{"definition":"A case for a <b>light</b>."}]}]}',
            200,
          );
        }
        return http.Response('{}', 404);
      }),
      wordNet: _wordNet,
    );
    final d = (await dictionary.define('Lantern'))!;
    expect(asked, ['lantern']);
    expect(d.meanings.single.partOfSpeech, 'noun');
    expect(d.meanings.single.senses.single.definition, 'A case for a light.');
  });

  group('offline (WordNet)', () {
    test('defines a word with examples', () async {
      final d = (await _offline().define('lantern'))!;
      expect(d.offline, isTrue);
      expect(d.meanings.first.partOfSpeech, 'noun');
      expect(d.meanings.first.senses.first.definition, contains('light'));
    });

    test('finds dictionary forms of inflected words', () async {
      final dictionary = _offline();
      Future<String?> lemma(String word, String pos) async {
        final d = await dictionary.define(word);
        final m = d?.meanings.where((m) => m.partOfSpeech == pos);
        return m == null || m.isEmpty ? null : (m.first.lemma ?? word);
      }

      expect(await lemma('ran', 'verb'), 'run');
      expect(await lemma('running', 'verb'), 'run');
      expect(await lemma('cities', 'noun'), 'city');
      expect(await lemma('stopped', 'verb'), 'stop');
      expect(await lemma('redder', 'adjective'), 'red');
      expect(await lemma('Swords', 'noun'), 'sword');
    });

    test('knows nothing of made-up words or other languages', () async {
      final dictionary = _offline();
      expect(await dictionary.define('qzxvbnm'), isNull);
      expect(await dictionary.define('lantern', language: 'fr'), isNull);
    });
  });
}
