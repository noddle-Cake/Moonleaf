import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:novel_to_epub/updates/app_updates.dart';
import 'package:novel_to_epub/updates/app_updates_screen.dart';
import 'package:novel_to_epub/updates/update_download_io.dart';
import 'package:novel_to_epub/theme.dart';

final trust = UpdateTrust(
  'com.noddlecake.novel_to_epub',
  'ab' * 32,
  Uri.parse('https://moonleaf.cjservin.com/app-update.json'),
);
final bytes = utf8.encode('signed APK fixture');
Map<String, dynamic> manifest({int build = 54}) => {
  'schema': 1,
  'package': trust.package,
  'certificate_sha256': trust.certificate,
  'build': build,
  'version_name': '1.0.0',
  'size': bytes.length,
  'sha256': sha256.convert(bytes).toString(),
  'apk_url': 'https://moonleaf.cjservin.com/download/moonleaf-$build.apk',
  'release_url':
      'https://github.com/noddle-Cake/Moonleaf/releases/tag/android-build-$build',
  'notes': 'Update checks and verified downloads.',
};
AppRelease release() => AppRelease.fromJson(manifest(), trust);

class Platform extends UpdatePlatform {
  Platform({this.build = 52, this.certificate, this.supported = true});
  final int build;
  final String? certificate;
  @override
  final bool supported;
  int installs = 0;
  bool permission = true;
  @override
  Future<InstalledVersion> installed() async =>
      InstalledVersion('1.0.0', build, certificate ?? trust.certificate);
  @override
  Future<bool> install(String path, String checksum) async {
    installs++;
    return permission;
  }
}

class Download extends UpdateDownloader {
  Completer<String>? pending;
  int starts = 0;
  bool cancelled = false;
  @override
  Future<String> download(
    AppRelease release,
    void Function(int) progress,
  ) async {
    starts++;
    progress(release.size);
    return pending?.future ?? '/cache/updates/moonleaf-${release.build}.apk';
  }

  @override
  void cancel() {
    cancelled = true;
  }
}

AppUpdateController controller({
  Platform? platform,
  Download? downloader,
  http.Client? client,
}) => AppUpdateController(
  platform: platform ?? Platform(),
  downloader: downloader ?? Download(),
  api: UpdateApi(
    trust: () async => trust,
    client:
        client ??
        MockClient((_) async => http.Response(jsonEncode(manifest()), 200)),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('manifest rejects off-site URLs, wrong identity, invalid size and unsigned builds', () {
    for (final entry in {
      'apk_url': 'https://evil.test/payload.apk',
      'release_url': 'https://evil.test/notes',
      'package': 'com.other.app',
      'certificate_sha256': 'cd' * 32,
      'build': 48,
      'size': -1,
      'sha256': 'invalid',
      'schema': 2,
    }.entries) {
      expect(
        () =>
            AppRelease.fromJson({...manifest(), entry.key: entry.value}, trust),
        throwsA(isA<UpdateException>()),
        reason: entry.key,
      );
    }
  });
  test('current or newer installed builds never offer a downgrade', () async {
    for (final build in [54, 80]) {
      final c = controller(platform: Platform(build: build));
      await c.check();
      expect(c.phase, UpdatePhase.current);
      await c.download();
      expect((c.downloader as Download).starts, 0);
      c.dispose();
    }
  });
  test(
    'wrong signing identity gives migration guidance and never downloads',
    () async {
      final c = controller(platform: Platform(certificate: 'old debug key'));
      addTearDown(c.dispose);
      await c.check();
      await c.download();
      expect(c.phase, UpdatePhase.incompatible);
      expect((c.downloader as Download).starts, 0);
    },
  );
  test('check and download suppress repeated taps; installer requires an explicit action', () async {
    var requests = 0;
    final response = Completer<http.Response>();
    final download = Download()..pending = Completer<String>();
    final platform = Platform();
    final c = controller(
      platform: platform,
      downloader: download,
      client: MockClient((_) {
        requests++;
        return response.future;
      }),
    );
    addTearDown(c.dispose);
    final checking = c.check();
    await c.check();
    response.complete(http.Response(jsonEncode(manifest()), 200));
    await checking;
    expect(requests, 1);
    final downloading = c.download();
    await c.download();
    expect(download.starts, 1);
    download.pending!.complete('/cache/updates/moonleaf-54.apk');
    await downloading;
    expect(c.phase, UpdatePhase.ready);
    expect(platform.installs, 0);
    platform.permission = false;
    await c.install();
    expect(c.phase, UpdatePhase.ready);
    expect(c.message, contains('Allow Moonleaf'));
    platform.permission = true;
    await c.install();
    expect(c.phase, UpdatePhase.installing);
  });
  test(
    'offline checking is retryable and does not invoke installation',
    () async {
      var fail = true;
      final c = controller(
        client: MockClient((_) async {
          if (fail) throw const SocketException('offline');
          return http.Response(jsonEncode(manifest()), 200);
        }),
      );
      addTearDown(c.dispose);
      await c.check();
      expect(c.phase, UpdatePhase.error);
      expect(c.message, contains('connection'));
      fail = false;
      await c.check();
      expect(c.phase, UpdatePhase.available);
    },
  );
  test('metadata redirects are refused', () async {
    final c = controller(
      client: MockClient(
        (_) async => http.Response(
          '',
          302,
          headers: {'location': 'https://evil.test/update.json'},
        ),
      ),
    );
    addTearDown(c.dispose);
    await c.check();
    expect(c.phase, UpdatePhase.error);
  });
  test('APK is streamed to an owned cache file and verified before it becomes ready', () async {
    final dir = await Directory.systemTemp.createTemp(
      'moonleaf-download-test-',
    );
    addTearDown(() => dir.delete(recursive: true));
    final d = ApkDownloader(
      directory: () async => dir,
      clientFactory: () =>
          MockClient((_) async => http.Response.bytes(bytes, 200)),
    );
    final path = await d.download(release(), (_) {});
    expect(await File(path).readAsBytes(), bytes);
    expect(File(path).parent.path, '${dir.path}/updates');
    expect(Directory('${dir.path}/updates').listSync().length, 1);
  });
  for (final kind in [
    'checksum',
    'truncated',
    'oversized',
    'redirect',
    'interrupted',
  ]) {
    test(
      'failed $kind download leaves no installable file or partial download',
      () async {
        final dir = await Directory.systemTemp.createTemp(
          'moonleaf-failed-update-',
        );
        addTearDown(() => dir.delete(recursive: true));
        final d = ApkDownloader(
          directory: () async => dir,
          clientFactory: () => MockClient.streaming((_, _) async {
            if (kind == 'redirect') {
              return http.StreamedResponse(const Stream.empty(), 302);
            }
            if (kind == 'interrupted') {
              return http.StreamedResponse(
                Stream.error(const SocketException('offline')),
                200,
              );
            }
            final data = switch (kind) {
              'checksum' => List.filled(bytes.length, 0),
              'truncated' => bytes.sublist(1),
              'oversized' => [...bytes, 1],
              _ => bytes,
            };
            return http.StreamedResponse(Stream.value(data), 200);
          }),
        );
        await expectLater(
          d.download(release(), (_) {}),
          throwsA(isA<UpdateException>()),
        );
        expect(Directory('${dir.path}/updates').listSync(), isEmpty);
      },
    );
  }
  test('cancelling a download removes its partial file', () async {
    final dir = await Directory.systemTemp.createTemp(
      'moonleaf-cancel-update-',
    );
    addTearDown(() => dir.delete(recursive: true));
    final stream = StreamController<List<int>>();
    final started = Completer<void>();
    final d = ApkDownloader(
      directory: () async => dir,
      clientFactory: () => MockClient.streaming((_, _) async {
        started.complete();
        return http.StreamedResponse(stream.stream, 200);
      }),
    );
    final result = d.download(release(), (_) {});
    final expectation = expectLater(result, throwsA(isA<UpdateException>()));
    await started.future;
    d.cancel();
    stream.add(bytes);
    await stream.close();
    await expectation;
    expect(Directory('${dir.path}/updates').listSync(), isEmpty);
  });
  testWidgets(
    'updates fit a small phone with large text and show both versions',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final c = controller();
      addTearDown(c.dispose);
      await tester.runAsync(c.check);
      await tester.pumpWidget(
        MaterialApp(
          theme: novelTheme(Brightness.light),
          home: AppUpdatesScreen(controller: c),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Update available'), findsOneWidget);
      expect(find.text('1.0.0 (build 52)'), findsOneWidget);
      expect(find.text('1.0.0 (build 54)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
