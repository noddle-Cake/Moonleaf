import 'update_models.dart';

UpdateDownloader createUpdateDownloader() => _UnsupportedDownloader();

class _UnsupportedDownloader implements UpdateDownloader {
  @override
  Future<String> download(
    AppRelease release,
    void Function(int) progress,
  ) async => throw const UpdateException(
    'APK updates are available in the Android app.',
  );
  @override
  void cancel() {}
}
