import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

const persistentBooks = true;

Future<Directory> _dir(String name) async {
  final base = await getApplicationSupportDirectory();
  final dir = Directory('${base.path}/$name');
  if (!await dir.exists()) await dir.create(recursive: true);
  return dir;
}

String _safe(String id) => id.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

/// Saves a book and returns the key used to read it back.
Future<String> saveBook(
  String id,
  Uint8List bytes, {
  String ext = 'epub',
}) async {
  final dir = await _dir('books');
  final name = '${_safe(id)}.$ext';
  final file = File('${dir.path}/$name');
  final temp = File('${file.path}.part');
  await temp.writeAsBytes(bytes, flush: true);
  await temp.rename(file.path);
  return name;
}

Future<Uint8List?> readBook(String key) async {
  final file = File('${(await _dir('books')).path}/${_safe(key)}');
  return await file.exists() ? file.readAsBytes() : null;
}

Future<void> deleteBook(String key) async {
  final file = File('${(await _dir('books')).path}/${_safe(key)}');
  if (await file.exists()) await file.delete();
}

Future<String> saveFont(String name, Uint8List bytes) async {
  final dir = await _dir('fonts');
  final file = File('${dir.path}/${_safe(name)}');
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

Future<Uint8List?> readFont(String path) async {
  final file = File(path);
  return await file.exists() ? file.readAsBytes() : null;
}

/// Small data files grouped in a folder, such as a book's downloaded
/// chapters.
Future<void> saveData(String folder, String name, Uint8List bytes) async {
  final dir = await _dir('data/${_safe(folder)}');
  final file = File('${dir.path}/${_safe(name)}');
  final temp = File('${file.path}.part');
  await temp.writeAsBytes(bytes, flush: true);
  await temp.rename(file.path);
}

Future<Uint8List?> readData(String folder, String name) async {
  final file = File(
    '${(await _dir('data/${_safe(folder)}')).path}/${_safe(name)}',
  );
  return await file.exists() ? file.readAsBytes() : null;
}

Future<void> deleteData(String folder) async {
  final base = await getApplicationSupportDirectory();
  final dir = Directory('${base.path}/data/${_safe(folder)}');
  if (await dir.exists()) await dir.delete(recursive: true);
}
