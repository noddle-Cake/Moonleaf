class UpdateException implements Exception {
  const UpdateException(this.message);
  final String message;
  @override
  String toString() => message;
}

class InstalledVersion {
  const InstalledVersion(this.name, this.build, this.certificate);
  final String name;
  final int build;
  final String certificate;
  String get label => '$name (build $build)';
}

class UpdateTrust {
  const UpdateTrust(this.package, this.certificate, this.manifest);
  factory UpdateTrust.fromJson(Map<String, dynamic> data) => UpdateTrust(
    data['package'] as String,
    data['certificate_sha256'] as String,
    Uri.parse(data['manifest_url'] as String),
  );
  final String package, certificate;
  final Uri manifest;
}

class AppRelease {
  const AppRelease({
    required this.name,
    required this.build,
    required this.size,
    required this.sha256,
    required this.apk,
    required this.notes,
    required this.page,
  });
  factory AppRelease.fromJson(Map<String, dynamic> data, UpdateTrust trust) {
    final build = data['build'];
    final size = data['size'];
    final checksum = data['sha256'];
    final name = data['version_name'];
    final notes = data['notes'];
    final origin = trust.manifest.origin;
    if (data['schema'] != 1 ||
        data['package'] != trust.package ||
        data['certificate_sha256'] != trust.certificate ||
        build is! int ||
        build < 52 ||
        size is! int ||
        size <= 0 ||
        size > 1073741824 ||
        checksum is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(checksum) ||
        name is! String ||
        name.isEmpty ||
        name.length > 80 ||
        notes is! String ||
        notes.length > 16000 ||
        data['apk_url'] != '$origin/download/moonleaf-$build.apk' ||
        data['release_url'] !=
            'https://github.com/noddle-Cake/Moonleaf/releases/tag/android-build-$build') {
      throw const UpdateException(
        'The update information could not be verified. Try again later.',
      );
    }
    return AppRelease(
      name: name,
      build: build,
      size: size,
      sha256: checksum,
      apk: Uri.parse(data['apk_url'] as String),
      notes: notes,
      page: Uri.parse(data['release_url'] as String),
    );
  }
  final String name, sha256, notes;
  final int build, size;
  final Uri apk, page;
  String get label => '$name (build $build)';
  String get sizeLabel => '${(size / 1000000).toStringAsFixed(0)} MB';
}

abstract class UpdateDownloader {
  Future<String> download(
    AppRelease release,
    void Function(int bytes) progress,
  );
  void cancel();
}

abstract class UpdatePlatform {
  bool get supported;
  Future<InstalledVersion> installed();

  /// Returns false when Android's install permission needs the user's attention.
  Future<bool> install(String path, String sha256);
}
