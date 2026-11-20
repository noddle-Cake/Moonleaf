import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:novel_to_epub/speech/natural_voice.dart';

/// A tiny stand-in for the voice download, packed like the real one.
List<int> fakeVoice() {
  final archive = Archive();
  for (final name in [
    'model.onnx',
    'voices.bin',
    'tokens.txt',
    'espeak-ng-data/en_dict',
  ]) {
    archive.addFile(
      ArchiveFile.bytes(
        'kitten-micro-en-v0_8/$name',
        utf8.encode('fake $name'),
      ),
    );
  }
  return BZip2Encoder().encodeBytes(TarEncoder().encodeBytes(archive));
}

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('moonleaf-voice'));
  tearDown(() => root.deleteSync(recursive: true));

  test('downloads, installs and removes the natural voice', () async {
    final bytes = fakeVoice();
    final seen = <double>[];
    final store = NaturalVoiceStore(
      client: MockClient.streaming((request, _) async {
        expect(request.url.path, endsWith('kitten-micro-en-v0_8.tar.bz2'));
        return http.StreamedResponse(
          Stream.fromIterable([
            for (var i = 0; i < bytes.length; i += 64)
              bytes.sublist(i, (i + 64).clamp(0, bytes.length)),
          ]),
          200,
          contentLength: bytes.length,
        );
      }),
      root: () async => root,
    );
    store.addListener(() => seen.add(store.progress));
    expect(await store.modelDir, isNull);
    await store.download();
    expect(store.status, VoiceStatus.ready, reason: '${store.error}');
    expect(seen.last, greaterThan(.9));
    final dir = (await store.modelDir)!;
    expect(File('$dir/model.onnx').readAsStringSync(), 'fake model.onnx');
    expect(File('$dir/espeak-ng-data/en_dict').existsSync(), isTrue);
    // The archive is deleted once installed.
    expect(
      Directory('${root.path}/voices').listSync().map((e) => e.path),
      everyElement(isNot(endsWith('.bz2'))),
    );
    await store.remove();
    expect(store.status, VoiceStatus.missing);
    expect(await store.modelDir, isNull);
  });

  test('a failed download says so and leaves nothing behind', () async {
    final store = NaturalVoiceStore(
      client: MockClient((_) async => http.Response('nope', 404)),
      root: () async => root,
    );
    await store.download();
    expect(store.status, VoiceStatus.failed);
    expect(store.error, isNotNull);
    expect(await store.modelDir, isNull);
    expect(Directory('${root.path}/voices').listSync(), isEmpty);
  });

  test('a download that isn\'t the voice is not installed', () async {
    final archive = Archive()
      ..addFile(ArchiveFile.bytes('something/else.txt', utf8.encode('hi')));
    final bytes = BZip2Encoder().encodeBytes(TarEncoder().encodeBytes(archive));
    final store = NaturalVoiceStore(
      client: MockClient((_) async => http.Response.bytes(bytes, 200)),
      root: () async => root,
    );
    await store.download();
    expect(store.status, VoiceStatus.failed);
    expect(await store.modelDir, isNull);
  });
}
