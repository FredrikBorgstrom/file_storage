import 'dart:convert';
import 'dart:developer';

import '../file_storage.dart';


/// Registers service extensions used by the DevTools companion.
void registerFileStorageDevTools({ final FileStorage? storage })
{
  _FileStorageDevTools.instance.register(storage ?? FileStorage());
}


const _extensionPrefix = 'ext.file_storage';

typedef _Handler = Future<Map<String, dynamic>> Function(Map<String, String>);


class _FileStorageDevTools
{
  static final _FileStorageDevTools instance = _FileStorageDevTools();

  void register(final FileStorage storage)
  {
    _storage = storage;
    if (_registered) return;
    _registered = true;
    _registerHandlers();
  }

  _FileStorageDevTools();

  void _registerHandlers()
  {
    _register('listFiles', _handleListFiles);
    _register('listFolders', _handleListFolders);
    _register('readFile', _handleReadFile);
    _register('saveFile', _handleSaveFile);
    _register('deleteFile', _handleDeleteFile);
  }

  void _register(final String name, final _Handler handler)
  {
    registerExtension(
      '$_extensionPrefix.$name',
      _wrapHandler(handler),
    );
  }

  ServiceExtensionHandler _wrapHandler(final _Handler handler) =>
  (final _, final parameters) async {
    try {
      final result = await handler(parameters);
      return _success(result);
    } catch (error, stackTrace) {
      return _error(error, stackTrace);
    }
  };

  ServiceExtensionResponse _success(final Map<String, dynamic> payload)
  {
    return ServiceExtensionResponse.result(jsonEncode(payload));
  }

  ServiceExtensionResponse _error(
    final Object error,
    final StackTrace stackTrace,
  )
  {
    final message = jsonEncode({
      'error': error.toString(),
      'stackTrace': stackTrace.toString(),
    });
    return ServiceExtensionResponse.error(
      ServiceExtensionResponse.extensionError,
      message,
    );
  }

  Future<Map<String, dynamic>> _handleListFiles(
    final Map<String, String> parameters,
  ) async
  {
    final request = _buildRequest(parameters);
    final recursive = parameters['recursive']?.toLowerCase() != 'false';
    final files = await _fetchEntries(request, recursive);
    return { 'files': files };
  }

  Future<Map<String, dynamic>> _handleListFolders(
    final Map<String, String> parameters,
  ) async
  {
    final request = _buildRequest(parameters);
    final folders = await _fetchTopLevelFolders(request);
    return { 'folders': folders };
  }

  Future<Map<String, dynamic>> _handleReadFile(
    final Map<String, String> parameters,
  ) async
  {
    final request = _buildRequest(parameters, requirePath: true);
    return await _readFileContents(request);
  }

  Future<Map<String, dynamic>> _handleSaveFile(
    final Map<String, String> parameters,
  ) async
  {
    final request = _buildRequest(parameters, requirePath: true);
    final encoding = (parameters['encoding'] ?? 'text').toLowerCase();
    final payload = parameters['payload'] ?? '';
    return await _saveFile(request, encoding, payload);
  }

  Future<Map<String, dynamic>> _handleDeleteFile(
    final Map<String, String> parameters,
  ) async
  {
    final request = _buildRequest(parameters, requirePath: true);
    return await _deleteFile(request);
  }

  Future<String> _resolve(final FileStorageArea area, {
    final String? path,
    final String? profile,
    final bool create = false,
  })
  {
    switch (area) {
      case FileStorageArea.files:
        return _storage!.getFilesPath(
          path: path,
          profile: profile,
          create: create,
        );
      case FileStorageArea.documents:
        return _storage!.getDocumentsPath(
          path: path,
          profile: profile,
          create: create,
        );
      case FileStorageArea.cache:
        return _storage!.getCachePath(
          path: path,
          profile: profile,
          create: create,
        );
    }
  }

  String _require(
    final Map<String, String> parameters,
    final String key,
  )
  {
    final value = parameters[key];
    if (value == null || value.isEmpty) {
      throw ArgumentError.value(value, key, 'Missing argument');
    }
    return value;
  }

  String? _clean(final String? value)
  {
    if (value == null || value.isEmpty) return null;
    return value;
  }

  String? _decodeText(final List<int> data)
  {
    try {
      return utf8.decode(data);
    } on FormatException {
      return null;
    }
  }

  _Request _buildRequest(final Map<String, String> parameters, {
    final bool requirePath = false,
  })
  {
    final areaName = _require(parameters, 'area');
    final area = FileStorageArea.fromName(areaName);
    final profile = _clean(parameters['profile']);
    final rawPath = requirePath
      ? _require(parameters, 'path')
      : _clean(parameters['path']);
    return _Request(area: area, profile: profile, path: rawPath);
  }

  Future<List<Map<String, dynamic>>> _fetchEntries(
    final _Request request,
    final bool recursive,
  ) async
  {
    final entries = await _storage!.listFiles(request.area,
      path: request.path,
      profile: request.profile,
      recursive: recursive,
    );
    return entries.map((entry) => entry.toJson()).toList();
  }

  Future<List<String>> _fetchTopLevelFolders(final _Request request) async
  {
    final entries = await _storage!.listFiles(
      request.area,
      profile: request.profile,
      recursive: true,
    );
    final folders = <String>{};
    for (final entry in entries) {
      final slashIndex = entry.path.indexOf('/');
      if (slashIndex > 0) {
        folders.add(entry.path.substring(0, slashIndex));
      }
    }
    return folders.toList()..sort();
  }

  Future<Map<String, dynamic>> _readFileContents(final _Request request) async
  {
    final target = await _resolveTarget(request);
    final data = await _storage!.loadData(target);
    if (data == null) return { 'data': null };
    return {
      'data': base64Encode(data),
      'text': _decodeText(data),
    };
  }

  Future<Map<String, dynamic>> _saveFile(
    final _Request request,
    final String encoding,
    final String payload,
  ) async
  {
    final target = await _resolveTarget(request, create: true);
    await _storage!.ensurePathExists(target);
    await (encoding == 'base64'
      ? _writeBinary(target, payload)
      : _writeText(target, payload)
    );
    return { 'status': 'ok' };
  }

  Future<Map<String, dynamic>> _deleteFile(final _Request request) async
  {
    final target = await _resolveTarget(request);
    await _storage!.removeFile(target);
    return { 'status': 'ok' };
  }

  Future<String> _resolveTarget(final _Request request, {
    final bool create = false,
  })
  {
    return _resolve(request.area,
      path: request.path,
      profile: request.profile,
      create: create,
    );
  }

  Future<void> _writeBinary(final String target, final String payload)
  {
    final bytes = base64Decode(payload);
    return _storage!.saveData(target, bytes);
  }

  Future<void> _writeText(final String target, final String payload)
  {
    return _storage!.saveText(target, payload);
  }

  var _registered = false;
  FileStorage? _storage;
}


class _Request
{
  final FileStorageArea area;
  final String? profile;
  final String? path;

  const _Request({
    required this.area,
    this.profile,
    this.path,
  });
}
