import 'dart:typed_data';

const persistentBooks = false;

final _books = <String, Uint8List>{};
final _fonts = <String, Uint8List>{};

Future<String> saveBook(
  String id,
  Uint8List bytes, {
  String ext = 'epub',
}) async {
  final key = '$id.$ext';
  _books[key] = bytes;
  return key;
}

Future<Uint8List?> readBook(String key) async => _books[key];

Future<void> deleteBook(String key) async => _books.remove(key);

Future<String> saveFont(String name, Uint8List bytes) async {
  _fonts[name] = bytes;
  return name;
}

Future<Uint8List?> readFont(String path) async => _fonts[path];
