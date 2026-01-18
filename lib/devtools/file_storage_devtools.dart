import 'dart:convert';
import 'dart:developer' as developer;

import '../file_storage.dart';

const _extensionPrefix = 'ext.file_storage';

/// Registers service extensions used by the DevTools companion.
void registerFileStorageDevTools({final FileStorage? storage}) {
  _FileStorageDevTools.instance.register(storage ?? FileStorage());
}

class _FileStorageDevTools {
  _FileStorageDevTools();

  static final _FileStorageDevTools instance = _FileStorageDevTools();

  FileStorage? _storage;
  var _registered = false;

  void register(final FileStorage storage) {
    _storage = storage;
    if (_registered) return;
    _registered = true;
    _registerHandlers();
  }

  void _registerHandlers() {
    _register('listFiles', _handleListFiles);
    _register('listFolders', _handleListFolders);
    _register('readFile', _handleReadFile);
    _register('saveFile', _handleSaveFile);
    _register('deleteFile', _handleDeleteFile);
  }

  void _register(
    final String name,
    final Future<Map<String, Object?>> Function(Map<String, String>) handler,
  ) {
    developer.registerExtension(
      '$_extensionPrefix.$name',
      _wrapHandler(handler),
    );
  }

  Future<developer.ServiceExtensionResponse> Function(
    String,
    Map<String, String>,
  ) _wrapHandler(
    final Future<Map<String, Object?>> Function(Map<String, String>) handler,
  ) =>
      (final _, final parameters) async {
        try {
          final result = await handler(parameters);
          return _success(result);
        } catch (error, stackTrace) {
          return _error(error, stackTrace);
        }
      };

  developer.ServiceExtensionResponse _success(
    final Map<String, Object?> payload,
  ) {
    return developer.ServiceExtensionResponse.result(jsonEncode(payload));
  }

  developer.ServiceExtensionResponse _error(
    final Object error,
    final StackTrace stackTrace,
  ) {
    final message = jsonEncode({
      'error': error.toString(),
      'stackTrace': stackTrace.toString(),
    });
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      message,
    );
  }

  Future<Map<String, Object?>> _handleListFiles(
    final Map<String, String> parameters,
  ) async {
    final request = _buildRequest(parameters);
    final recursive = parameters['recursive'] != 'false';
    final files = await _fetchEntries(request, recursive);
    return {'files': files};
  }

  Future<Map<String, Object?>> _handleListFolders(
    final Map<String, String> parameters,
  ) async {
    final area = _parseArea(parameters['area']);
    final profile = _clean(parameters['profile']);
    final folders = await _fetchTopLevelFolders(area, profile);
    return {'folders': folders};
  }

  Future<List<String>> _fetchTopLevelFolders(
    final FileStorageArea area,
    final String? profile,
  ) async {
    // Get all files at root level (non-recursive to be faster)
    final entries = await _storage!.listFiles(
      area,
      profile: profile,
      recursive: true,
    );

    // Extract unique top-level folder names from paths
    final folders = <String>{};
    for (final entry in entries) {
      final path = entry.path;
      final slashIndex = path.indexOf('/');
      if (slashIndex > 0) {
        folders.add(path.substring(0, slashIndex));
      }
    }

    final sortedFolders = folders.toList()..sort();
    return sortedFolders;
  }

  Future<Map<String, Object?>> _handleReadFile(
    final Map<String, String> parameters,
  ) async {
    final request = _buildRequest(parameters, requirePath: true);
    return await _readFileContents(request);
  }

  Future<Map<String, Object?>> _handleSaveFile(
    final Map<String, String> parameters,
  ) async {
    final request = _buildRequest(parameters, requirePath: true);
    final encoding = (parameters['encoding'] ?? 'text').toLowerCase();
    final payload = parameters['payload'] ?? '';
    return await _saveFile(request, encoding, payload);
  }

  Future<Map<String, Object?>> _handleDeleteFile(
    final Map<String, String> parameters,
  ) async {
    final request = _buildRequest(parameters, requirePath: true);
    return await _deleteFile(request);
  }

  Future<String> _resolve(
    final FileStorageArea area, {
    final String? path,
    final String? profile,
    final bool create = false,
  }) {
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

  FileStorageArea _parseArea(final String? value) {
    switch (value?.toLowerCase()) {
      case 'files':
        return FileStorageArea.files;
      case 'documents':
        return FileStorageArea.documents;
      case 'cache':
        return FileStorageArea.cache;
      default:
        throw ArgumentError.value(value, 'area', 'Unknown storage area');
    }
  }

  String _require(
    final Map<String, String> parameters,
    final String key,
  ) {
    final value = parameters[key];
    if (value == null || value.isEmpty) {
      throw ArgumentError.value(value, key, 'Missing argument');
    }
    return value;
  }

  String? _clean(final String? value) {
    if (value == null || value.isEmpty) return null;
    return value;
  }

  String? _decodeText(final List<int> data) {
    try {
      return utf8.decode(data);
    } on FormatException {
      return null;
    }
  }

  _Request _buildRequest(
    final Map<String, String> parameters, {
    final bool requirePath = false,
  }) {
    final area = _parseArea(parameters['area']);
    final profile = _clean(parameters['profile']);
    final rawPath =
        requirePath ? _require(parameters, 'path') : _clean(parameters['path']);
    return _Request(area: area, profile: profile, path: rawPath);
  }

  Future<List<Map<String, Object?>>> _fetchEntries(
    final _Request request,
    final bool recursive,
  ) async {
    final entries = await _storage!.listFiles(
      request.area,
      path: request.path,
      profile: request.profile,
      recursive: recursive,
    );
    return entries.map((entry) => entry.toJson()).toList();
  }

  Future<Map<String, Object?>> _readFileContents(
    final _Request request,
  ) async {
    final target = await _resolveTarget(request);
    final data = await _storage!.loadData(target);
    if (data == null) return {'data': null};
    return {
      'data': base64Encode(data),
      'text': _decodeText(data),
    };
  }

  Future<Map<String, Object?>> _saveFile(
    final _Request request,
    final String encoding,
    final String payload,
  ) async {
    final target = await _resolveTarget(request, create: true);
    await _storage!.ensurePathExists(target);
    await (encoding == 'base64'
        ? _writeBinary(target, payload)
        : _writeText(target, payload));
    return {'status': 'ok'};
  }

  Future<Map<String, Object?>> _deleteFile(final _Request request) async {
    final target = await _resolveTarget(request);
    await _storage!.removeFile(target);
    return {'status': 'ok'};
  }

  Future<String> _resolveTarget(
    final _Request request, {
    final bool create = false,
  }) {
    return _resolve(
      request.area,
      path: request.path,
      profile: request.profile,
      create: create,
    );
  }

  Future<void> _writeBinary(
    final String target,
    final String payload,
  ) async {
    final bytes = base64Decode(payload);
    await _storage!.saveData(target, bytes);
  }

  Future<void> _writeText(
    final String target,
    final String payload,
  ) =>
      _storage!.saveText(target, payload);
}

class _Request {
  const _Request({
    required this.area,
    this.profile,
    this.path,
  });

  final FileStorageArea area;
  final String? profile;
  final String? path;
}
