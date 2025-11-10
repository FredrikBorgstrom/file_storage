import 'dart:async';
import 'dart:convert';

import 'package:idb_shim/idb_browser.dart';

import 'platformed.dart';
import 'storage_entry.dart';

FileStorage createFileStorage() => FileStorageWeb();

class FileStorageWeb implements FileStorage {
  static const storeName = 'filestorage';
  static const filesPath = 'common';
  static const documentsPath = 'documents';
  static const cachePath = 'cache';

  @override
  Future<String> getFilesPath({
    final String? path,
    final String? profile,
    final bool create = false,
  }) =>
      _buildPath(
        filesPath,
        path: path,
        profile: profile,
      );

  @override
  Future<String> getDocumentsPath({
    final String? path,
    final String? profile,
    final bool create = false,
  }) =>
      _buildPath(
        documentsPath,
        path: path,
        profile: profile,
      );

  @override
  Future<String> getCachePath({
    final String? path,
    final String? profile,
    final bool create = false,
  }) =>
      _buildPath(
        cachePath,
        path: path,
        profile: profile,
      );

  @override
  Future<void> ensurePathExists(final String fileName) async {}

  @override
  Future<bool> fileExists(final String fileName) async {
    final db = await _getDatabase();
    final transaction = db.transaction([storeName], idbModeReadOnly);
    final store = transaction.objectStore(storeName);
    final count = await store.count(fileName);
    return count > 0;
  }

  @override
  Future<List<int>?> loadData(final String fileName) async {
    final db = await _getDatabase();
    final transaction = db.transaction([storeName], idbModeReadOnly);
    final store = transaction.objectStore(storeName);
    final data = await store.getObject(fileName);
    if (data == null) return null;
    if (data is! List<int>) return null;
    return data;
  }

  @override
  Future<String?> loadText(final String fileName) async {
    final data = await loadData(fileName);
    if (data == null) return null;
    return utf8.decode(data);
  }

  @override
  Future<Object?> loadJson(final String fileName) async {
    final data = await loadData(fileName);
    if (data == null || data.isEmpty) return null;
    final objects = await Stream.value(data)
        .transform(utf8.decoder)
        .transform(json.decoder)
        .toList();
    return objects.isEmpty ? null : objects.first;
  }

  @override
  Future<void> saveData(final String fileName, final List<int> data) async {
    final db = await _getDatabase();
    final transaction = db.transaction([storeName], idbModeReadWrite);
    final store = transaction.objectStore(storeName);
    await store.put(data, fileName);
  }

  @override
  Future<void> saveText(final String fileName, final String text) {
    return saveData(fileName, utf8.encode(text));
  }

  @override
  Future<void> saveJson(
    final String fileName,
    final dynamic jsonValue, {
    Object? Function(dynamic)? toEncodable,
  }) {
    final stream = Stream.value(jsonValue)
        .transform(JsonEncoder(toEncodable))
        .transform(const Utf8Encoder());
    return saveStream(fileName, stream);
  }

  @override
  Future<void> saveStream(
    final String fileName,
    final Stream<List<int>> stream,
  ) async {
    final data = (await stream.toList()).expand((e) => e).toList();
    await saveData(fileName, data);
  }

  @override
  Future<void> removeFile(final String fileName) async {
    final db = await _getDatabase();
    final transaction = db.transaction([storeName], idbModeReadWrite);
    final store = transaction.objectStore(storeName);
    await store.delete(fileName);
  }

  @override
  Future<List<FileStorageEntry>> listFiles(
    final FileStorageArea area, {
    final String? path,
    final String? profile,
    final bool recursive = true,
  }) async {
    final bucket = _bucketForArea(area);
    final root = await _buildPath(
      bucket,
      path: path,
      profile: profile,
    );
    return await _readEntries(root, recursive);
  }

  Future<String> _buildPath(
    final String basePath, {
    final String? path,
    final String? profile,
  }) async {
    var fullPath = basePath;
    if (profile != null && profile.isNotEmpty) {
      fullPath += '/$profile';
    }
    if (path != null && path.isNotEmpty) {
      fullPath += '/$path';
    }
    return fullPath;
  }

  Future<Database> _getDatabase() async {
    _database ??= await idbFactoryNative.open(
      'filestorage.db',
      version: 1,
      onUpgradeNeeded: _onUpgradeNeeded,
      onBlocked: _onBlocked,
    );
    return _database!;
  }

  FutureOr<void> _onUpgradeNeeded(final VersionChangeEvent event) {
    for (var v = event.oldVersion + 1; v <= event.newVersion; ++v) {
      switch (v) {
        case 1:
          _upgradeToVersion1(event.database);
        default:
          throw UnimplementedError(
              'Migration the database to version $v is not implemented');
      }
    }
  }

  void _upgradeToVersion1(final Database database) {
    database.createObjectStore(storeName);
  }

  void _onBlocked(final Event event) {
    _database?.close();
    _database = null;
  }

  Database? _database;

  String _bucketForArea(final FileStorageArea area) {
    switch (area) {
      case FileStorageArea.files:
        return filesPath;
      case FileStorageArea.documents:
        return documentsPath;
      case FileStorageArea.cache:
        return cachePath;
    }
  }

  Future<List<FileStorageEntry>> _readEntries(
    final String root,
    final bool recursive,
  ) async {
    final transaction = await _readOnlyTransaction();
    final store = transaction.objectStore(storeName);
    final entries = await _collectEntries(store, root, recursive);
    await transaction.completed;
    entries.sort((a, b) => a.path.compareTo(b.path));
    return entries;
  }

  Future<Transaction> _readOnlyTransaction() async {
    final db = await _getDatabase();
    return db.transaction([storeName], idbModeReadOnly);
  }

  Future<List<FileStorageEntry>> _collectEntries(
    final ObjectStore store,
    final String root,
    final bool recursive,
  ) async {
    final entries = <FileStorageEntry>[];
    await for (final cursor in store.openCursor(autoAdvance: true)) {
      final entry = await _cursorToEntry(root, recursive, cursor);
      if (entry != null) entries.add(entry);
    }
    return entries;
  }

  Future<FileStorageEntry?> _cursorToEntry(
    final String root,
    final bool recursive,
    final CursorWithValue cursor,
  ) async {
    final key = cursor.key;
    if (key is! String) return null;
    final relativePath = _deriveRelativePath(root, key);
    if (relativePath == null) return null;
    if (!recursive && relativePath.contains('/')) return null;
    final value = cursor.value;
    final length = value is List
        ? value.length
        : (value is List<int> ? value.length : null);
    return FileStorageEntry(path: relativePath, byteLength: length);
  }

  String? _deriveRelativePath(final String root, final String key) {
    if (key == root) return '';
    final prefix = '$root/';
    if (!key.startsWith(prefix)) return null;
    return key.substring(prefix.length);
  }
}
