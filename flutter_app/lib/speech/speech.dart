import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'natural_voice.dart';
import 'speech_engine.dart';
import 'system_speech.dart';

enum VoiceKind {
  /// The phone's own text-to-speech.
  phone,

  /// The natural voice downloaded into the app.
  natural,
}

/// Which voice reads aloud and how fast, shared by Read Aloud and the
/// dictionary.
class Speech extends ChangeNotifier {
  Speech({this.engineFor});

  static Speech instance = Speech();
  static const _key = 'moonleaf_speech';

  /// Makes engines instead of the real ones (tests).
  final SpeechEngine Function(VoiceKind kind)? engineFor;

  VoiceKind kind = VoiceKind.phone;

  /// The phone voice's id, or null for the phone's default voice.
  String? phoneVoice;

  /// The natural voice's speaker id.
  String naturalVoice = '1';

  /// Reading speed, where 1 is normal.
  double rate = 1;

  bool _loaded = false;
  SpeechEngine? _engine;
  VoiceKind? _engineKind;

  /// The phone's voice. Only one is ever made: each one takes over the
  /// text-to-speech plugin's callbacks.
  SystemSpeech get phone => _phone ??= SystemSpeech();
  SystemSpeech? _phone;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return;
      final d = jsonDecode(raw) as Map<String, dynamic>;
      kind = d['kind'] == 'natural' ? VoiceKind.natural : VoiceKind.phone;
      phoneVoice = d['phoneVoice'] as String?;
      naturalVoice = d['naturalVoice'] as String? ?? naturalVoice;
      rate = ((d['rate'] as num?)?.toDouble() ?? rate).clamp(.5, 2.0);
    } catch (_) {}
  }

  Future<void> update(void Function(Speech s) change) async {
    await load();
    change(this);
    notifyListeners();
    await _configure();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({
        'kind': kind.name,
        'phoneVoice': phoneVoice,
        'naturalVoice': naturalVoice,
        'rate': rate,
      }),
    );
  }

  /// The voice to read with. Falls back to the phone's voice when the
  /// natural voice isn't downloaded.
  Future<SpeechEngine> engine() async {
    await load();
    var want = kind;
    String? dir;
    if (want == VoiceKind.natural && engineFor == null) {
      dir = await NaturalVoiceStore.instance.modelDir;
      if (dir == null) want = VoiceKind.phone;
    }
    if (_engine == null || _engineKind != want) {
      final old = _engine;
      if (old == _phone) {
        await old?.stop();
      } else {
        await old?.dispose();
      }
      _engineKind = want;
      _engine =
          engineFor?.call(want) ??
          (want == VoiceKind.natural ? NaturalSpeech(modelDir: dir!) : phone);
    }
    await _configure();
    return _engine!;
  }

  Future<void> _configure() async {
    final engine = _engine;
    if (engine is SystemSpeech) {
      await engine.setRate(rate);
      await engine.setVoice(phoneVoice);
    } else if (engine is NaturalSpeech) {
      engine
        ..speaker = int.tryParse(naturalVoice) ?? 1
        ..rate = rate;
    }
  }

  /// Reads [text] once, as the dictionary does for a word.
  Future<void> say(String text) async {
    final engine = await this.engine();
    await engine.stop();
    await engine.speak(text);
  }

  Future<void> stop() async => _engine?.stop();

  /// The phone's voices for [language], or none where text-to-speech isn't
  /// available.
  Future<List<SpeechVoice>> phoneVoices(String language) async {
    if (engineFor != null) return const [];
    try {
      return await phone.voices(language);
    } catch (_) {
      return const [];
    }
  }
}
