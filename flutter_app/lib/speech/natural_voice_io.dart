import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'speech_engine.dart';

/// Where the natural voice can be used: sherpa-onnx runs natively on
/// Android, iOS and desktops.
const naturalVoiceSupported = true;

/// KittenTTS micro v0.8 (Apache 2.0), packaged for sherpa-onnx. It runs
/// several times faster than real time on a laptop and keeps up on phones,
/// unlike larger models such as Kokoro.
const _model = 'kitten-micro-en-v0_8';
const _url =
    'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/'
    '$_model.tar.bz2';

/// The download, in MB, as shown before downloading.
const naturalVoiceSize = 42;

/// The natural voice's speakers, by speaker id.
const naturalVoices = [
  SpeechVoice('1', 'Female 1'),
  SpeechVoice('0', 'Male 1'),
  SpeechVoice('3', 'Female 2'),
  SpeechVoice('2', 'Male 2'),
  SpeechVoice('5', 'Female 3'),
  SpeechVoice('4', 'Male 3'),
  SpeechVoice('7', 'Female 4'),
  SpeechVoice('6', 'Male 4'),
];

enum VoiceStatus { missing, downloading, installing, ready, failed }

/// Downloads, installs and removes the natural voice.
class NaturalVoiceStore extends ChangeNotifier {
  NaturalVoiceStore({http.Client? client, Future<Directory> Function()? root})
    : _client = client ?? http.Client(),
      _root = root ?? getApplicationSupportDirectory;

  static final instance = NaturalVoiceStore();

  final http.Client _client;
  final Future<Directory> Function() _root;
  VoiceStatus status = VoiceStatus.missing;

  /// Download progress from 0 to 1.
  double progress = 0;
  String? error;
  bool _checked = false, _cancelled = false;

  Future<Directory> get _voices async =>
      Directory('${(await _root()).path}/voices');

  /// The installed model's folder, or null.
  Future<String?> get modelDir async {
    final dir = '${(await _voices).path}/$_model';
    return File('$dir/.installed').existsSync() ? dir : null;
  }

  Future<void> check() async {
    if (_checked || status == VoiceStatus.downloading) return;
    _checked = true;
    try {
      if (await modelDir != null) _set(VoiceStatus.ready);
    } catch (_) {
      // No app storage (tests, unusual platforms): the voice stays missing.
    }
  }

  void _set(VoiceStatus s, {String? message}) {
    status = s;
    error = message;
    notifyListeners();
  }

  Future<void> download() async {
    if (status == VoiceStatus.downloading || status == VoiceStatus.installing) {
      return;
    }
    _cancelled = false;
    progress = 0;
    _set(VoiceStatus.downloading);
    final voices = await _voices;
    await voices.create(recursive: true);
    final archive = File('${voices.path}/$_model.tar.bz2');
    try {
      final response = await _client.send(http.Request('GET', Uri.parse(_url)));
      if (response.statusCode != 200) {
        throw HttpException('Download failed (${response.statusCode})');
      }
      final total = response.contentLength ?? naturalVoiceSize * 1048576;
      final sink = archive.openWrite();
      var received = 0;
      try {
        await for (final chunk in response.stream) {
          if (_cancelled) throw const _Cancelled();
          sink.add(chunk);
          received += chunk.length;
          final p = (received / total).clamp(0.0, 1.0);
          if (p - progress >= .01) {
            progress = p;
            notifyListeners();
          }
        }
      } finally {
        await sink.close();
      }
      _set(VoiceStatus.installing);
      final dir = '${voices.path}/$_model';
      await _install(archive.path, voices.path, dir);
      _set(VoiceStatus.ready);
    } on _Cancelled {
      _set(VoiceStatus.missing);
    } catch (e) {
      _set(
        VoiceStatus.failed,
        message: e is SocketException || e is http.ClientException
            ? 'Couldn’t download the voice. Check your internet connection.'
            : 'Couldn’t install the voice.',
      );
    } finally {
      if (archive.existsSync()) await archive.delete();
    }
  }

  /// Unpacks the archive in the background; it holds a few hundred files.
  static Future<void> _install(String archive, String into, String dir) =>
      Isolate.run(() async {
        final folder = Directory(dir);
        if (folder.existsSync()) folder.deleteSync(recursive: true);
        // Entries can't land outside the voices folder.
        await extractFileToDisk(archive, into);
        if (!File('$dir/model.onnx').existsSync()) {
          throw StateError('The voice download is incomplete.');
        }
        File('$dir/.installed').writeAsStringSync(_model);
      });

  void cancel() => _cancelled = true;

  Future<void> remove() async {
    await NaturalSpeech.release();
    final dir = Directory('${(await _voices).path}/$_model');
    if (dir.existsSync()) await dir.delete(recursive: true);
    _set(VoiceStatus.missing);
  }
}

class _Cancelled implements Exception {
  const _Cancelled();
}

/// Reads aloud with the downloaded natural voice. Audio is made in a
/// background isolate, a sentence ahead of what's playing.
class NaturalSpeech extends SpeechEngine {
  NaturalSpeech({required this.modelDir});
  final String modelDir;

  int speaker = 1;
  double rate = 1;

  final _player = AudioPlayer();
  final _ready = <String, Future<String>>{};
  Completer<bool>? _done;
  StreamSubscription<void>? _completion;
  int _files = 0;

  static _Worker? _worker;

  /// Frees the voice's memory, as when it's removed.
  static Future<void> release() async {
    final worker = _worker;
    _worker = null;
    await worker?.close();
  }

  String _key(String text) => '$speaker|$rate|$text';

  Future<String> _render(String text) {
    final key = _key(text);
    return _ready[key] ??= () async {
      final worker = _worker ??= await _Worker.start(modelDir);
      final dir = await getTemporaryDirectory();
      // A few files are reused in turn.
      final path = '${dir.path}/moonleaf-voice-${_files++ % 4}.wav';
      await worker.render(text, speaker, rate, path);
      return path;
    }();
  }

  @override
  void prepare(String text) {
    // Keep only what's playing and what's next.
    if (_ready.length > 2) _ready.remove(_ready.keys.first);
    _render(text).catchError((Object _) => '');
  }

  @override
  Future<bool> speak(String text) async {
    _finish(false);
    final done = _done = Completer<bool>();
    final String path;
    try {
      path = await _render(text);
    } finally {
      _ready.remove(_key(text));
    }
    if (done != _done) return false;
    _completion ??= _player.onPlayerComplete.listen((_) => _finish(true));
    await _player.play(DeviceFileSource(path));
    return done.future;
  }

  void _finish(bool finished) {
    final done = _done;
    _done = null;
    if (done != null && !done.isCompleted) done.complete(finished);
  }

  @override
  Future<void> stop() async {
    _finish(false);
    await _player.stop();
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _completion?.cancel();
    await _player.dispose();
  }
}

/// A long-lived isolate holding the voice model.
class _Worker {
  _Worker(this._isolate, this._requests, this._replies);
  final Isolate _isolate;
  final SendPort _requests;
  final ReceivePort _replies;
  final _pending = <int, Completer<void>>{};
  int _next = 0;

  static Future<_Worker> start(String modelDir) async {
    final replies = ReceivePort();
    final isolate = await Isolate.spawn(_main, (replies.sendPort, modelDir));
    final first = Completer<SendPort>();
    late final _Worker worker;
    replies.listen((message) {
      if (message is SendPort) {
        first.complete(message);
      } else if (message is (int, String?)) {
        final done = worker._pending.remove(message.$1);
        if (message.$2 == null) {
          done?.complete();
        } else {
          done?.completeError(StateError(message.$2!));
        }
      }
    });
    worker = _Worker(isolate, await first.future, replies);
    return worker;
  }

  Future<void> render(String text, int speaker, double rate, String path) {
    final id = _next++;
    final done = _pending[id] = Completer<void>();
    _requests.send((id, text, speaker, rate, path));
    return done.future;
  }

  Future<void> close() async {
    _isolate.kill();
    _replies.close();
    for (final p in _pending.values) {
      p.completeError(StateError('The voice was closed.'));
    }
    _pending.clear();
  }

  static void _main((SendPort, String) args) {
    final (replies, dir) = args;
    final requests = ReceivePort();
    replies.send(requests.sendPort);
    sherpa.OfflineTts? tts;
    requests.listen((message) {
      final (id, text, speaker, rate, path) =
          message as (int, String, int, double, String);
      try {
        tts ??= _open(dir);
        final audio = tts!.generate(text: text, sid: speaker, speed: rate);
        if (audio.samples.isEmpty) throw StateError('No audio for "$text"');
        sherpa.writeWave(
          filename: path,
          samples: audio.samples,
          sampleRate: audio.sampleRate,
        );
        replies.send((id, null));
      } catch (e) {
        replies.send((id, '$e'));
      }
    });
  }

  static sherpa.OfflineTts _open(String dir) {
    sherpa.initBindings();
    return sherpa.OfflineTts(
      sherpa.OfflineTtsConfig(
        model: sherpa.OfflineTtsModelConfig(
          kitten: sherpa.OfflineTtsKittenModelConfig(
            model: '$dir/model.onnx',
            voices: '$dir/voices.bin',
            tokens: '$dir/tokens.txt',
            dataDir: '$dir/espeak-ng-data',
          ),
          numThreads: Platform.numberOfProcessors >= 4 ? 2 : 1,
        ),
      ),
    );
  }
}
