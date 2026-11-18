// Stores EPUBs and user fonts in app-private storage. On the web there is no
// file system, so files only live for the browser session.
export 'book_files_memory.dart' if (dart.library.io) 'book_files_io.dart';
