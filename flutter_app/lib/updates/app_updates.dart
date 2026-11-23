import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'update_download.dart';
import 'update_models.dart';
export 'update_models.dart';

class AndroidUpdatePlatform implements UpdatePlatform {
  static const channel = MethodChannel('moonleaf/updates');
  @override
  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  @override
  Future<InstalledVersion> installed() async {
    final data = (await channel.invokeMapMethod<String, dynamic>('installed'))!;
    return InstalledVersion(
      data['name'] as String,
      data['build'] as int,
      data['certificate'] as String,
    );
  }

  @override
  Future<bool> install(String path, String sha256) async =>
      await channel.invokeMethod<String>('install', {
        'path': path,
        'sha256': sha256,
      }) ==
      'opened';
}

class UpdateApi {
  UpdateApi({http.Client? client, Future<UpdateTrust> Function()? trust})
    : _client = client ?? http.Client(),
      _trust = trust ?? _loadTrust;
  final http.Client _client;
  final Future<UpdateTrust> Function() _trust;
  static Future<UpdateTrust> _loadTrust() async => UpdateTrust.fromJson(
    jsonDecode(await rootBundle.loadString('assets/android-update.json'))
        as Map<String, dynamic>,
  );
  Future<UpdateTrust> trust() => _trust();
  Future<AppRelease> latest(UpdateTrust trust) async {
    try {
      final request = http.Request('GET', trust.manifest)
        ..followRedirects = false
        ..headers['Cache-Control'] = 'no-cache';
      final response = await _client
          .send(request)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw const UpdateException(
          'Update information is unavailable. Please try again later.',
        );
      }
      final bytes = <int>[];
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 20),
      )) {
        bytes.addAll(chunk);
        if (bytes.length > 65536) {
          throw const UpdateException('The update information is invalid.');
        }
      }
      return AppRelease.fromJson(
        jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>,
        trust,
      );
    } on UpdateException {
      rethrow;
    } catch (_) {
      throw const UpdateException(
        'Could not check for updates. Check your connection and try again.',
      );
    }
  }

  void close() => _client.close();
}

enum UpdatePhase {
  idle,
  checking,
  unsupported,
  current,
  available,
  incompatible,
  downloading,
  ready,
  installing,
  error,
}

class AppUpdateController extends ChangeNotifier {
  AppUpdateController({
    UpdateApi? api,
    UpdatePlatform? platform,
    UpdateDownloader? downloader,
  }) : api = api ?? UpdateApi(),
       platform = platform ?? AndroidUpdatePlatform(),
       downloader = downloader ?? createUpdateDownloader();
  final UpdateApi api;
  final UpdatePlatform platform;
  final UpdateDownloader downloader;
  UpdatePhase phase = UpdatePhase.idle;
  InstalledVersion? installed;
  AppRelease? release;
  String? message, _apk;
  int received = 0;
  bool _disposed = false, _cancelled = false;
  bool get busy => [
    UpdatePhase.checking,
    UpdatePhase.downloading,
    UpdatePhase.installing,
  ].contains(phase);
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> check() async {
    if (busy || _disposed) return;
    if (!platform.supported) {
      phase = UpdatePhase.unsupported;
      _notify();
      return;
    }
    phase = UpdatePhase.checking;
    message = null;
    _notify();
    try {
      installed = await platform.installed();
      final trust = await api.trust();
      final latest = await api.latest(trust);
      if (_disposed) return;
      if (release?.build != latest.build) _apk = null;
      release = latest;
      phase = installed!.certificate != trust.certificate
          ? UpdatePhase.incompatible
          : latest.build <= installed!.build
          ? UpdatePhase.current
          : _apk == null
          ? UpdatePhase.available
          : UpdatePhase.ready;
    } catch (error) {
      if (_disposed) return;
      phase = UpdatePhase.error;
      message = error is UpdateException
          ? error.message
          : 'Could not read the installed app version. Please try again.';
    }
    _notify();
  }

  Future<void> download() async {
    if (phase != UpdatePhase.available || release == null || _disposed) return;
    phase = UpdatePhase.downloading;
    message = null;
    received = 0;
    _cancelled = false;
    _notify();
    try {
      final path = await downloader.download(release!, (bytes) {
        received = bytes;
        _notify();
      });
      if (_disposed) return;
      _apk = path;
      phase = _cancelled ? UpdatePhase.available : UpdatePhase.ready;
    } catch (error) {
      if (_disposed) return;
      phase = UpdatePhase.available;
      message = _cancelled
          ? null
          : error is UpdateException
          ? error.message
          : 'The update download failed. Please try again.';
    }
    _notify();
  }

  void cancel() {
    _cancelled = true;
    downloader.cancel();
  }

  Future<void> install() async {
    if (phase != UpdatePhase.ready || _apk == null || _disposed) return;
    phase = UpdatePhase.installing;
    message = null;
    _notify();
    try {
      if (!await platform.install(_apk!, release!.sha256) && !_disposed) {
        phase = UpdatePhase.ready;
        message = 'Allow Moonleaf to install apps in Android Settings, then return here and tap Install Update.';
      }
    } catch (_) {
      if (_disposed) return;
      phase = UpdatePhase.available;
      _apk = null;
      message = 'Android could not open this update. Please download it again.';
    }
    _notify();
  }

  Future<void> resumed() async {
    if (phase == UpdatePhase.installing) {
      phase = UpdatePhase.ready;
      await check();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    downloader.cancel();
    api.close();
    super.dispose();
  }
}
