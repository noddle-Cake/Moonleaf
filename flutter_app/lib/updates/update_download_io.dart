import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'update_models.dart';

UpdateDownloader createUpdateDownloader() => ApkDownloader();

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

class ApkDownloader implements UpdateDownloader {
  ApkDownloader({
    this.clientFactory = http.Client.new,
    this.directory = getTemporaryDirectory,
  });
  final http.Client Function() clientFactory;
  final Future<Directory> Function() directory;
  http.Client? _client;
  bool _cancelled = false;
  @override
  void cancel() {
    _cancelled = true;
    _client?.close();
  }

  @override
  Future<String> download(
    AppRelease release,
    void Function(int) progress,
  ) async {
    if (_client != null) {
      throw const UpdateException('An update is already downloading.');
    }
    _cancelled = false;
    final client = _client = clientFactory();
    File? part;
    Directory? work;
    RandomAccessFile? output;
    try {
      final dir = Directory('${(await directory()).path}/updates');
      await dir.create(recursive: true);
      work = await dir.createTemp('.download-');
      part = File('${work.path}/update.apk.part');
      final request = http.Request('GET', release.apk)..followRedirects = false;
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw const UpdateException(
          'The update could not be downloaded. Please try again.',
        );
      }
      if (response.contentLength != null &&
          response.contentLength != release.size) {
        throw const UpdateException(
          'The update size does not match. Please try again later.',
        );
      }
      output = await part.open(mode: FileMode.write);
      final digest = _DigestSink();
      final hash = sha256.startChunkedConversion(digest);
      var received = 0;
      await for (final bytes in response.stream.timeout(
        const Duration(seconds: 30),
      )) {
        if (_cancelled) throw const UpdateException('Download cancelled.');
        received += bytes.length;
        if (received > release.size) {
          throw const UpdateException(
            'The update file is larger than expected.',
          );
        }
        hash.add(bytes);
        await output.writeFrom(bytes);
        progress(received);
      }
      hash.close();
      await output.close();
      output = null;
      if (_cancelled) throw const UpdateException('Download cancelled.');
      if (received != release.size ||
          digest.value.toString() != release.sha256) {
        throw const UpdateException(
          'The update failed verification. Please download it again.',
        );
      }
      return (await part.rename('${dir.path}/moonleaf-${release.build}.apk'))
          .path;
    } on UpdateException {
      rethrow;
    } on TimeoutException {
      throw const UpdateException(
        'The download stopped responding. Check your connection and try again.',
      );
    } catch (_) {
      throw UpdateException(
        _cancelled
            ? 'Download cancelled.'
            : 'The download failed. Check your connection and try again.',
      );
    } finally {
      try {
        await output?.close();
      } catch (_) {}
      try {
        if (work != null && await work.exists()) {
          await work.delete(recursive: true);
        }
      } catch (_) {}
      client.close();
      _client = null;
    }
  }
}
