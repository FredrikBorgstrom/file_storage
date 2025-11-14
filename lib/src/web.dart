import 'dart:async';
import 'dart:convert';

import 'package:idb_shim/idb_browser.dart';

import 'platformed.dart';
import 'storage_entry.dart';


FileStorage createFileStorage() => FileStorageWeb();


class FileStorageWeb implements FileStorage
{
  static const storeName = 'filestorage';
  static const filesPath = 'common';
  static const documentsPath = 'documents';
  static const cachePath = 'cache';

  @override
  Future<String> getFilesPath({
    final String? path,
    final String? profile,
    final bool create = false,
  }) async => _buildPath(filesPath,
    path: path,
    profile: profile,
  );

  @override
  Future<String> getDocumentsPath({
    final String? path,
    final String? profile,
    final bool create = false,
  }) async => _buildPath(documentsPath,
    path: path,
    profile: profile,
  );

  @override
  Future<String> getCachePath({
    final String? path,
    final String? profile,
    final bool create = false,
  }) async => _buildPath(cachePath,
    path: path,
    profile: profile,
  );

  @override
  Future<void> ensurePathExists(final String fileName) async
  {
  }

  @override
  Future<bool> fileExists(final String fileName) async
  {
    final transaction = await _getReadOnlyTransaction();
    final store = transaction.objectStore(storeName);
    final count = await store.count(fileName);
    return count > 0;
  }

  @override
  Future<List<int>?> loadData(final String fileName) async
  {
    final transaction = await _getReadOnlyTransaction();
    final store = transaction.objectStore(storeName);
    final data = await store.getObject(fileName);
    if (data == null) return null;
    if (data is! List<int>) return null;
    return data;
  }

  @override
  Future<String?> loadText(final String fileName) async
  {
    final data = await loadData(fileName);
    if (data == null) return null;
    return utf8.decode(data);
  }

  @override
  Future<Object?> loadJson(final String fileName) async
  {
    final data = await loadData(fileName);
    if (data == null || data.isEmpty) return null;
    final objects = await Stream.value(data)
      .transform(utf8.decoder)
      .transform(json.decoder)
      .toList();
    return objects.isEmpty ? null : objects.first;
  }

  @override
  Future<void> saveData(final String fileName, final List<int> data) async
  {
    final transaction = await _getReadWriteTransaction();
    final store = transaction.objectStore(storeName);
    await store.put(data, fileName);
  }

  @override
  Future<void> saveText(final String fileName, final String text)
  {
    return saveData(fileName, utf8.encode(text));
  }

  @override
  Future<void> saveJson(final String fileName, final dynamic jsonValue, {
    Object? Function(dynamic)? toEncodable,
  })
  {
    final stream = Stream.value(jsonValue)
      .transform(JsonEncoder(toEncodable))
      .transform(const Utf8Encoder());
    return saveStream(fileName, stream);
  }

  @override
  Future<void> saveStream(
    final String fileName,
    final Stream<List<int>> stream,
  ) async
  {
    final data = (await stream.toList()).expand((e) => e).toList();
    await saveData(fileName, data);
  }

  @override
  Future<void> removeFile(final String fileName) async
  {
    final transaction = await _getReadWriteTransaction();
    final store = transaction.objectStore(storeName);
    await store.delete(fileName);
  }

  @override
  Future<List<FileStorageEntry>> listFiles(final FileStorageArea area, {
    final String? path,
    final String? profile,
    final bool recursive = true,
  }) async
  {
    final areaPath = _resolveAreaPath(area);
    final basePath = _buildPath(areaPath,
      path: path,
      profile: profile,
    );
    return await _readEntries(basePath, recursive: recursive);
  }

  String _resolveAreaPath(final FileStorageArea area) => switch (area) {
    FileStorageArea.files => filesPath,
    FileStorageArea.documents => documentsPath,
    FileStorageArea.cache => cachePath,
  };

  String _buildPath(final String areaPath, {
    final String? path,
    final String? profile,
  })
  {
    var fullPath = areaPath;
    if (profile != null && profile.isNotEmpty) {
      fullPath += '/$profile';
    }
    if (path != null && path.isNotEmpty) {
      fullPath += '/$path';
    }
    return fullPath;
  }

  Future<Database> _getDatabase() async
  {
    _database ??= await idbFactoryNative.open('filestorage.db',
      version: 1,
      onUpgradeNeeded: _onUpgradeNeeded,
      onBlocked: _onBlocked,
    );
    return _database!;
  }

  FutureOr<void> _onUpgradeNeeded(final VersionChangeEvent event)
  {
    for (var v = event.oldVersion + 1; v <= event.newVersion; ++v) {
      switch (v) {
        case 1: _upgradeToVersion1(event.database);
        default: throw UnimplementedError(
          'Migration the database to version $v is not implemented'
        );
      }
    }
  }

  void _upgradeToVersion1(final Database database)
  {
    database.createObjectStore(storeName);
  }

  void _onBlocked(final Event event)
  {
    _database?.close();
    _database = null;
  }

  Future<List<FileStorageEntry>> _readEntries(final String path, {
    final bool recursive = true,
  }) async
  {
    final transaction = await _getReadOnlyTransaction();
    final store = transaction.objectStore(storeName);
    final entries = await _collectEntries(path,
      store: store,
      recursive: recursive,
    );
    await transaction.completed;
    entries.sort((a, b) => a.path.compareTo(b.path));
    return entries;
  }

  Future<Transaction> _getReadOnlyTransaction() async
  {
    final db = await _getDatabase();
    return db.transaction([ storeName ], idbModeReadOnly);
  }

  Future<Transaction> _getReadWriteTransaction() async
  {
    final db = await _getDatabase();
    return db.transaction([ storeName ], idbModeReadWrite);
  }

  Future<List<FileStorageEntry>> _collectEntries(final String path, {
    required final ObjectStore store,
    final bool recursive = true,
  }) async
  {
    final entries = <FileStorageEntry>[];
    await for (final cursor in store.openCursor(autoAdvance: true)) {
      final entry = _cursorToEntry(path, cursor: cursor, recursive: recursive);
      if (entry != null) entries.add(entry);
    }
    return entries;
  }

  FileStorageEntry? _cursorToEntry(final String basePath, {
    required final CursorWithValue cursor,
    final bool recursive = true,
  })
  {
    final key = cursor.key;
    if (key is! String) return null;
    final relativePath = _deriveRelativePath(basePath, key);
    if (relativePath == null) return null;
    if (!recursive && relativePath.contains('/')) return null;
    final value = cursor.value;
    final length = value is List ? value.length : null;
    return FileStorageEntry(path: relativePath, byteLength: length);
  }

  String? _deriveRelativePath(final String basePath, final String fullPath)
  {
    if (fullPath == basePath) return '';
    final prefix = '$basePath/';
    if (!fullPath.startsWith(prefix)) return null;
    return fullPath.substring(prefix.length);
  }

  Database? _database;
}
