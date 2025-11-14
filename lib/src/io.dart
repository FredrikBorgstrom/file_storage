import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

import 'platformed.dart';
import 'storage_entry.dart';


FileStorage createFileStorage() => FileStorageIO();


class FileStorageIO implements FileStorage
{
  @override
  Future<String> getFilesPath({
    final String? path,
    final String? profile,
    final bool create = false,
  }) async
  {
    final areaPath = await _resolveAreaPath(FileStorageArea.files);
    return await _buildPath(areaPath,
      path: path,
      profile: profile,
      create: create,
    );
  }

  @override
  Future<String> getDocumentsPath({
    final String? path,
    final String? profile,
    final bool create = false,
  }) async
  {
    _docsRootDir ??= await getApplicationDocumentsDirectory();
    return await _buildPath(_docsRootDir!.path,
      path: path,
      profile: profile,
      create: create,
    );
  }

  @override
  Future<String> getCachePath({
    final String? path,
    final String? profile,
    final bool create = false,
  }) async
  {
    _cacheRootDir ??= await getTemporaryDirectory();
    return await _buildPath(_cacheRootDir!.path,
      path: path,
      profile: profile,
      create: create,
    );
  }

  @override
  Future<void> ensurePathExists(final String fileName) async
  {
    await Directory(dirname(fileName)).create(recursive: true);
  }

  @override
  Future<bool> fileExists(final String fileName)
  {
    final file = File(fileName);
    return file.exists();
  }

  @override
  Future<List<int>?> loadData(final String fileName) async
  {
    final file = File(fileName);
    final fileExists = await file.exists();
    if (!fileExists) {
      return null;
    }
    return await file.readAsBytes();
  }

  @override
  Future<String?> loadText(final String fileName) async
  {
    final file = File(fileName);
    final fileExists = await file.exists();
    if (!fileExists) {
      return null;
    }
    return await file.readAsString(encoding: utf8);
  }

  @override
  Future<Object?> loadJson(final String fileName) async
  {
    final file = File(fileName);
    final fileExists = await file.exists();
    if (!fileExists) {
      return null;
    }
    final size = await file.length();
    if (size <= 0) {
      return null;
    }
    final objects = await file.openRead()
      .transform(utf8.decoder)
      .transform(json.decoder)
      .toList();
    return objects.isEmpty ? null : objects.first;
  }

  @override
  Future<void> saveData(final String fileName, final List<int> data) async
  {
    final file = File(fileName);
    await file.writeAsBytes(data, flush: true);
  }

  @override
  Future<void> saveText(final String fileName, final String text) async
  {
    final file = File(fileName);
    await file.writeAsString(text, flush: true);
  }

  @override
  Future<void> saveJson(final String fileName, final dynamic jsonValue, {
    Object? Function(dynamic)? toEncodable,
  }) async
  {
    final file = File(fileName);
    final sink = file.openWrite();
    final stream = Stream.value(jsonValue)
      .transform(JsonEncoder(toEncodable))
      .transform(const Utf8Encoder());
    await sink.addStream(stream);
    await sink.flush();
    await sink.close();
  }

  @override
  Future<void> saveStream(
    final String fileName,
    final Stream<List<int>> stream,
  ) async
  {
    final file = File(fileName);
    final sink = file.openWrite();
    await sink.addStream(stream);
    await sink.flush();
    await sink.close();
  }

  @override
  Future<void> removeFile(final String fileName) async
  {
    final file = File(fileName);
    final fileExists = await file.exists();
    if (!fileExists) return;
    await file.delete(recursive: true);
  }

  @override
  Future<List<FileStorageEntry>> listFiles(final FileStorageArea area, {
    final String? path,
    final String? profile,
    final bool recursive = true,
  }) async
  {
    final areaPath = await _resolveAreaPath(area);
    final filesPath = await _buildPath(areaPath,
      path: path,
      profile: profile,
      create: false,
    );
    return await _collectEntries(filesPath, recursive);
  }

  Future<String> _resolveAreaPath(final FileStorageArea area) async
  {
    switch (area) {
      case FileStorageArea.files:
        _filesRootDir ??= await getApplicationSupportDirectory();
        return _filesRootDir!.path;
      case FileStorageArea.documents:
        _docsRootDir ??= await getApplicationDocumentsDirectory();
        return _docsRootDir!.path;
      case FileStorageArea.cache:
        _cacheRootDir ??= await getTemporaryDirectory();
        return _cacheRootDir!.path;
    }
  }

  Future<String> _buildPath(final String areaPath, {
    final String? path,
    final String? profile,
    final bool create = false,
  }) async
  {
    var fullPath = areaPath;
    if (profile != null && profile.isNotEmpty) {
      fullPath += '/$profile';
    }
    if (path != null && path.isNotEmpty) {
      fullPath += '/$path';
    }
    if (create) {
      await Directory(fullPath).create(recursive: true);
    }
    return fullPath;
  }

  Future<List<FileStorageEntry>> _collectEntries(
    final String path,
    final bool recursive,
  ) async
  {
    final directory = Directory(path);
    if (!await directory.exists()) return [];
    final files = await directory
      .list(recursive: recursive, followLinks: false)
      .where((e) => e is File)
      .toList();
    final entries = await Future.wait(
      files.map((file) => _buildEntry(path, file))
    );
    entries.sort((a, b) => a.path.compareTo(b.path));
    return entries;
  }

  Future<FileStorageEntry> _buildEntry(
    final String root,
    final FileSystemEntity file,
  ) async
  {
    final stat = await file.stat();
    final relativePath = relative(file.path, from: root);
    return FileStorageEntry(
      path: relativePath,
      byteLength: stat.size,
      lastModified: stat.modified.toUtc(),
    );
  }

  Directory? _filesRootDir;
  Directory? _docsRootDir;
  Directory? _cacheRootDir;
}
