import 'dart:async';
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;

/// One meaning of a word.
class Sense {
  const Sense(this.definition, [this.example]);
  final String definition;
  final String? example;
}

/// The senses of a word as one part of speech.
class Meaning {
  const Meaning(this.partOfSpeech, this.senses, {this.lemma});
  final String partOfSpeech;
  final List<Sense> senses;

  /// The dictionary form when it differs from the word looked up, such as
  /// "run" for "ran".
  final String? lemma;
}

/// What a dictionary says about a word.
class Definition {
  const Definition(this.word, this.meanings, {required this.offline});
  final String word;
  final List<Meaning> meanings;

  /// From the dictionary built into the app rather than Wiktionary.
  final bool offline;
}

/// Looks words up on Wiktionary, falling back to WordNet (built in, English
/// only) when offline or when Wiktionary doesn't know the word.
class Dictionary {
  Dictionary({http.Client? client, Future<ByteData> Function()? wordNet})
    : _client = client ?? http.Client(),
      _loadWordNet = wordNet ?? (() => rootBundle.load(wordNetAsset));

  /// Shared by the reader; tests swap in one without the network.
  static Dictionary instance = Dictionary();
  static const wordNetAsset = 'assets/dictionary/wordnet.txt.gz';

  /// How long to wait for Wiktionary before using the built-in dictionary.
  static const _timeout = Duration(seconds: 4);

  final http.Client _client;
  final Future<ByteData> Function() _loadWordNet;
  final _cache = <String, Future<Definition?>>{};
  Future<_WordNet?>? _wordNet;

  /// The word or short phrase in selected [text] worth looking up, without
  /// surrounding punctuation, or null if it isn't one. Hold-to-define only
  /// looks up single words ([words] = 1).
  static String? lookupText(String text, {int words = 3}) {
    final t = text
        .replaceAll('’', "'")
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(
          RegExp(r"^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$", unicode: true),
          '',
        );
    if (t.isEmpty || t.length > 60) return null;
    final parts = t.split(' ');
    if (parts.length > words) return null;
    final word = RegExp(r"^\p{L}[\p{L}\p{M}'\-]*$", unicode: true);
    return parts.every(word.hasMatch) ? t : null;
  }

  /// Defines [word] in the book's [language] (a code such as "en").
  Future<Definition?> define(String word, {String language = 'en'}) {
    final lang = language.split('-').first.toLowerCase();
    final key = '$lang:$word';
    return _cache[key] ??= _define(word, lang).then((d) {
      // Only remember definitive answers, so going online later helps.
      if (d == null || d.offline) _cache.remove(key);
      return d;
    });
  }

  Future<Definition?> _define(String word, String lang) async {
    try {
      final online = await _online(word, lang).timeout(_timeout);
      if (online != null) return online;
    } catch (_) {
      // Offline or Wiktionary is unreachable: use the built-in dictionary.
    }
    // WordNet is English, and only loaded when needed (it takes memory).
    return lang == 'en' ? _offline(word) : null;
  }

  // ---------------------------------------------------------------------------
  // Wiktionary.

  Future<Definition?> _online(String word, String lang) async {
    final lower = word.toLowerCase();
    // Lowercase first, so "Running" at the start of a sentence isn't taken
    // for a name; names are still found as written.
    for (final title in {lower, word}) {
      final uri = Uri.https(
        'en.wiktionary.org',
        '/api/rest_v1/page/definition/${title.replaceAll(' ', '_')}',
        {'redirect': 'true'},
      );
      final response = await _client.get(
        uri,
        headers: {
          // Browsers don't allow setting User-Agent; Wikimedia accepts this.
          if (kIsWeb)
            'Api-User-Agent': 'Moonleaf-Reader/1.0'
          else
            'User-Agent': 'Moonleaf-Reader/1.0',
        },
      );
      if (response.statusCode == 404) continue;
      if (response.statusCode != 200) {
        throw http.ClientException('Wiktionary: ${response.statusCode}', uri);
      }
      final definition = parseWiktionary(
        word,
        utf8.decode(response.bodyBytes),
        lang,
      );
      if (definition != null) return definition;
    }
    return null;
  }

  /// Reads a Wiktionary REST definition response.
  @visibleForTesting
  static Definition? parseWiktionary(String word, String body, String lang) {
    final data = jsonDecode(body);
    if (data is! Map) return null;
    final entries = data[lang];
    if (entries is! List) return null;
    final meanings = <Meaning>[];
    for (final entry in entries.whereType<Map>()) {
      final senses = <Sense>[];
      for (final d in (entry['definitions'] as List? ?? []).whereType<Map>()) {
        final text = _plain(d['definition'] as String? ?? '');
        if (text.isEmpty) continue;
        final examples = d['examples'];
        final example = examples is List && examples.isNotEmpty
            ? _plain('${examples.first}')
            : null;
        senses.add(
          Sense(text, example == null || example.isEmpty ? null : example),
        );
      }
      if (senses.isEmpty) continue;
      meanings.add(
        Meaning((entry['partOfSpeech'] as String? ?? '').toLowerCase(), senses),
      );
    }
    return meanings.isEmpty ? null : Definition(word, meanings, offline: false);
  }

  /// Text of a Wiktionary HTML snippet, without nested sub-senses and
  /// quotations.
  static String _plain(String fragment) {
    final node = html.parseFragment(fragment);
    for (final e in node.querySelectorAll('ol, ul, dl, sup, style')) {
      e.remove();
    }
    return (node.text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  // ---------------------------------------------------------------------------
  // WordNet.

  Future<Definition?> _offline(String word) async {
    try {
      final wn = await (_wordNet ??= _openWordNet());
      return wn?.define(word);
    } catch (_) {
      return null;
    }
  }

  Future<_WordNet?> _openWordNet() async {
    try {
      final data = await _loadWordNet();
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      return await compute(_WordNet.parse, bytes);
    } catch (_) {
      _wordNet = null;
      return null;
    }
  }
}

/// WordNet as built by tool/build_dictionary.py.
class _WordNet {
  _WordNet(this.glosses, this.words, this.forms);

  /// "pos\tgloss" by gloss number.
  final List<String> glosses;

  /// Gloss numbers by word, comma-separated.
  final Map<String, String> words;

  /// Base forms by "pos\tirregular form".
  final Map<String, List<String>> forms;

  static _WordNet parse(Uint8List gzipped) {
    final text = utf8.decode(const GZipDecoder().decodeBytes(gzipped));
    final glosses = <String>[];
    final words = <String, String>{};
    final forms = <String, List<String>>{};
    var section = 0;
    for (final line in const LineSplitter().convert(text)) {
      if (line == '%%') {
        section++;
        continue;
      }
      if (line.isEmpty) continue;
      switch (section) {
        case 0:
          glosses.add(line);
        case 1:
          final tab = line.indexOf('\t');
          words[line.substring(0, tab)] = line.substring(tab + 1);
        default:
          final parts = line.split('\t');
          forms['${parts[0]}\t${parts[1]}'] = parts[2].split(',');
      }
    }
    return _WordNet(glosses, words, forms);
  }

  static const _names = {
    'n': 'noun',
    'v': 'verb',
    'a': 'adjective',
    'r': 'adverb',
  };

  // WordNet's "morphy" rules for regular endings.
  static const _endings = {
    'n': [
      ('s', ''),
      ('ses', 's'),
      ('xes', 'x'),
      ('zes', 'z'),
      ('ches', 'ch'),
      ('shes', 'sh'),
      ('men', 'man'),
      ('ies', 'y'),
    ],
    'v': [
      ('s', ''),
      ('ies', 'y'),
      ('es', 'e'),
      ('es', ''),
      ('ed', 'e'),
      ('ed', ''),
      ('ing', 'e'),
      ('ing', ''),
    ],
    'a': [('er', ''), ('est', ''), ('er', 'e'), ('est', 'e')],
    'r': <(String, String)>[],
  };

  /// The dictionary forms of [word] as [pos]: the word itself, irregular
  /// forms (ran → run), then regular endings (cities → city).
  List<String> _bases(String word, String pos) {
    final out = <String>[word, ...?forms['$pos\t$word']];
    for (final (ending, replacement) in _endings[pos]!) {
      if (word.length > ending.length + 1 && word.endsWith(ending)) {
        out.add(word.substring(0, word.length - ending.length) + replacement);
      }
    }
    // "stopped" → "stop", "bigger" → "big".
    for (final b in List.of(out)) {
      final n = b.length;
      if (n > 3 && b[n - 1] == b[n - 2] && b != word) {
        out.add(b.substring(0, n - 1));
      }
    }
    return out;
  }

  Definition? define(String word) {
    final w = word.toLowerCase();
    final meanings = <Meaning>[];
    for (final pos in _names.keys) {
      final seen = <int>{};
      for (final base in _bases(w, pos)) {
        final ids = words[base];
        if (ids == null) continue;
        final senses = <Sense>[];
        for (final id in ids.split(',').map(int.parse)) {
          final line = glosses[id];
          if (!line.startsWith('$pos\t') || !seen.add(id)) continue;
          senses.add(_sense(line.substring(2)));
        }
        if (senses.isEmpty) continue;
        meanings.add(
          Meaning(_names[pos]!, senses, lemma: base == w ? null : base),
        );
        // The first base that exists is the right one for this pos.
        break;
      }
    }
    return meanings.isEmpty ? null : Definition(word, meanings, offline: true);
  }

  /// Splits 'a definition; "an example"; "another"'.
  static Sense _sense(String gloss) {
    final quote = gloss.indexOf('; "');
    if (quote < 0) return Sense(gloss);
    final rest = gloss.substring(quote + 3);
    final end = rest.indexOf('"');
    return Sense(
      gloss.substring(0, quote),
      end < 0 ? rest : rest.substring(0, end),
    );
  }
}

/// Lists WordNet's license with the app's other licenses.
void registerDictionaryLicense() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'WordNet',
    ], await rootBundle.loadString('assets/dictionary/WordNet-LICENSE.txt'));
  });
}
