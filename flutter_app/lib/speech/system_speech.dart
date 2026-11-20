import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';

import 'speech_engine.dart';

/// The phone's own text-to-speech (Google, Samsung, Apple voices...).
class SystemSpeech extends SpeechEngine {
  SystemSpeech({FlutterTts? tts}) : _tts = tts ?? FlutterTts() {
    _tts.setCompletionHandler(() => _finish(true));
    _tts.setCancelHandler(() => _finish(false));
    _tts.setPauseHandler(() => _finish(false));
    _tts.setErrorHandler((message) {
      final done = _done;
      _done = null;
      if (done != null && !done.isCompleted) {
        done.completeError(StateError('Text-to-speech failed: $message'));
      }
    });
  }

  final FlutterTts _tts;
  Completer<bool>? _done;
  bool _ready = false;
  double _rate = 1;
  String? _voice;

  /// Speaking rate, where 1 is normal speed.
  Future<void> setRate(double rate) async {
    _rate = rate;
    if (_ready) await _applyRate();
  }

  /// A voice id from [voices], or null for the phone's default.
  Future<void> setVoice(String? id) async {
    _voice = id;
    if (_ready) await _applyVoice();
  }

  Future<void> _applyRate() =>
      // Android and Apple both treat 0.5 as normal speed.
      _tts.setSpeechRate((_rate * .5).clamp(.1, 1.0));

  Future<void> _applyVoice() async {
    final id = _voice;
    if (id == null) return;
    final (name, locale) = _split(id);
    await _tts.setVoice({'name': name, 'locale': locale});
  }

  static (String, String) _split(String id) {
    final bar = id.indexOf('|');
    return bar < 0 ? (id, '') : (id.substring(0, bar), id.substring(bar + 1));
  }

  Future<void> _setUp() async {
    if (_ready) return;
    _ready = true;
    // Completion is reported through the handlers instead.
    await _tts.awaitSpeakCompletion(false);
    await _applyRate();
    await _applyVoice();
  }

  void _finish(bool finished) {
    final done = _done;
    _done = null;
    if (done != null && !done.isCompleted) done.complete(finished);
  }

  @override
  Future<bool> speak(String text) async {
    await _setUp();
    _finish(false);
    final done = _done = Completer<bool>();
    final result = await _tts.speak(text);
    // 1 means the text was queued; anything else is a failure.
    if (result != 1 && result != null) {
      _finish(false);
      throw StateError('Text-to-speech is not available.');
    }
    return done.future;
  }

  @override
  Future<void> stop() async {
    _finish(false);
    if (_ready) await _tts.stop();
  }

  /// Installed voices, best for [language] (such as "en") first.
  Future<List<SpeechVoice>> voices(String language) async {
    final raw = await _tts.getVoices;
    if (raw is! List) return const [];
    final voices = <SpeechVoice>[];
    for (final v in raw.whereType<Map>()) {
      final name = '${v['name'] ?? ''}';
      final locale = '${v['locale'] ?? ''}';
      if (name.isEmpty) continue;
      if (language.isNotEmpty &&
          !locale.toLowerCase().startsWith(language.toLowerCase())) {
        continue;
      }
      // Android marks voices that need the internet.
      final online = '${v['network_required'] ?? ''}' == '1';
      voices.add(
        SpeechVoice(
          '$name|$locale',
          _pretty(name),
          detail: [locale, if (online) 'needs internet'].join(' · '),
        ),
      );
    }
    voices.sort((a, b) => a.detail.compareTo(b.detail));
    return voices;
  }

  /// "en-us-x-sfg-local" → "en-us-x-sfg"; Apple names are already readable.
  static String _pretty(String name) =>
      name.endsWith('-local') ? name.substring(0, name.length - 6) : name;
}
