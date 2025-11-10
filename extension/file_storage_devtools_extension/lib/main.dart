import 'dart:async';

import 'package:devtools_app_shared/service.dart';
import 'package:devtools_app_shared/ui.dart';
import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const FileStorageDevToolsApp());
}

class FileStorageDevToolsApp extends StatelessWidget {
  const FileStorageDevToolsApp({super.key});

  @override
  Widget build(final BuildContext context) {
    return const DevToolsExtension(
      child: FileStorageHome(),
    );
  }
}

class FileStorageHome extends StatefulWidget {
  const FileStorageHome({super.key});

  @override
  State<FileStorageHome> createState() => _FileStorageHomeState();
}

class _FileStorageHomeState extends State<FileStorageHome> {
  static const int _maxTextPreviewBytes = 4 * 1024 * 1024;

  final _api = _FileStorageApi();
  final _profileController = TextEditingController();
  final _pathController = TextEditingController();
  final _editorController = TextEditingController();
  _StorageOption _selectedArea = _storageOptions.first;
  var _recursive = true;
  var _files = <_FileEntry>[];
  _FileEntry? _selectedEntry;
  _FilePayload? _payload;
  var _listLoading = false;
  var _fileLoading = false;
  var _savingFile = false;
  var _dirty = false;
  String? _listError;
  String? _fileError;
  var _wasConnected = false;
  var _updatingEditor = false;
  var _textTooLarge = false;

  bool get _isConnected => serviceManager.connectedState.value.connected;

  @override
  void initState() {
    super.initState();
    _editorController.addListener(_handleEditorChange);
    _wasConnected = _isConnected;
    serviceManager.connectedState.addListener(_handleConnectionChange);
    if (_wasConnected) {
      scheduleMicrotask(_refreshFiles);
    }
  }

  @override
  void dispose() {
    serviceManager.connectedState.removeListener(_handleConnectionChange);
    _profileController.dispose();
    _pathController.dispose();
    _editorController.dispose();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    return ValueListenableBuilder<ConnectedState>(
      valueListenable: serviceManager.connectedState,
      builder: (context, state, _) {
        if (!state.connected) {
          return _DisconnectedNotice(onRetry: _refreshFiles);
        }
        return Padding(
          padding: const EdgeInsets.all(defaultSpacing),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _FileStorageToolbar(
                options: _storageOptions,
                selected: _selectedArea,
                profileController: _profileController,
                pathController: _pathController,
                recursive: _recursive,
                refreshing: _listLoading,
                onAreaChanged: _changeArea,
                onRecursiveChanged: _changeRecursive,
                onRefresh: _refreshFiles,
              ),
              const SizedBox(height: denseSpacing),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: _FileListView(
                        files: _files,
                        selected: _selectedEntry,
                        loading: _listLoading,
                        error: _listError,
                        onSelect: _openFile,
                      ),
                    ),
                    const SizedBox(width: denseSpacing),
                    Expanded(
                      flex: 3,
                      child: _FileDetailView(
                        entry: _selectedEntry,
                        payload: _payload,
                        controller: _editorController,
                        dirty: _dirty,
                        loading: _fileLoading,
                        saving: _savingFile,
                        error: _fileError,
                        textTooLarge: _textTooLarge,
                        onReload: _reloadSelected,
                        onSave: _saveSelected,
                        onDelete: _deleteSelected,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _handleConnectionChange() {
    final connected = _isConnected;
    if (connected && !_wasConnected) {
      _wasConnected = true;
      _refreshFiles();
    }
    if (!connected && _wasConnected) {
      _wasConnected = false;
      _clearState();
    }
  }

  void _handleEditorChange() {
    if (_updatingEditor || _payload == null || !_payload!.isText) return;
    setState(() {
      _dirty = true;
    });
  }

  void _changeArea(final _StorageOption option) {
    setState(() {
      _selectedArea = option;
    });
    _refreshFiles();
  }

  void _changeRecursive(final bool value) {
    setState(() {
      _recursive = value;
    });
    _refreshFiles();
  }

  Future<void> _refreshFiles() async {
    if (!_isConnected) return;
    _startListLoading();
    try {
      final files = await _fetchFiles();
      _handleListSuccess(files);
    } catch (error, stackTrace) {
      _handleListError(error, stackTrace);
    } finally {
      _finishListLoading();
    }
  }

  void _startListLoading() {
    setState(() {
      _listLoading = true;
      _listError = null;
    });
  }

  Future<List<_FileEntry>> _fetchFiles() {
    return _api.listFiles(
      area: _selectedArea.area,
      profile: _profileText(),
      path: _pathText(),
      recursive: _recursive,
    );
  }

  void _handleListSuccess(final List<_FileEntry> files) {
    final previousPath = _selectedEntry?.path;
    final nextSelected =
        previousPath == null ? null : _findByPath(files, previousPath);
    setState(() {
      _files = files;
      _selectedEntry = nextSelected;
      if (_selectedEntry == null) {
        _payload = null;
        _editorController.clear();
        _dirty = false;
      }
    });
  }

  void _handleListError(final Object error, final StackTrace stackTrace) {
    debugPrint('Failed to load files: $error\n$stackTrace');
    setState(() {
      _listError = error.toString();
    });
  }

  void _finishListLoading() {
    setState(() {
      _listLoading = false;
    });
  }

  Future<void> _openFile(final _FileEntry entry) async {
    if (_shouldSkipOpen(entry)) return;
    _startFileLoading(entry);
    try {
      var payload = await _api.readFile(
        area: _selectedArea.area,
        profile: _profileText(),
        path: entry.path,
      );
      final tooLargeForText = entry.byteLength != null &&
          entry.byteLength! > _maxTextPreviewBytes &&
          payload.isTextFile;
      if (tooLargeForText) {
        payload = _FilePayload(
          base64: payload.base64,
          text: null,
          isTextFile: true,
        );
      }
      _applyPayload(payload, textTooLarge: tooLargeForText);
    } catch (error, stackTrace) {
      _handleFileError(error, stackTrace);
    } finally {
      _finishFileLoading();
    }
  }

  Future<void> _reloadSelected() async {
    final entry = _selectedEntry;
    if (entry == null) return;
    await _openFile(entry);
  }

  Future<void> _saveSelected() async {
    final entry = _selectedEntry;
    final payload = _payload;
    if (entry == null || payload == null || !payload.isText || !_dirty) return;
    _startSaving();
    try {
      await _api.saveFile(
        area: _selectedArea.area,
        profile: _profileText(),
        path: entry.path,
        text: _editorController.text,
        isText: true,
      );
      _markClean();
      await _refreshFiles();
      await _openFile(entry);
    } catch (error, stackTrace) {
      _handleSaveError(error, stackTrace);
    } finally {
      _finishSaving();
    }
  }

  Future<void> _deleteSelected() async {
    final entry = _selectedEntry;
    if (entry == null) return;
    _startSaving();
    try {
      await _api.deleteFile(
        area: _selectedArea.area,
        profile: _profileText(),
        path: entry.path,
      );
      _deleteFromList(entry);
      await _refreshFiles();
    } catch (error, stackTrace) {
      _handleSaveError(error, stackTrace);
    } finally {
      _finishSaving();
    }
  }

  void _deleteFromList(final _FileEntry entry) {
    setState(() {
      _files = _files.where((item) => item.path != entry.path).toList();
      if (_selectedEntry?.path == entry.path) {
        _selectedEntry = null;
        _payload = null;
        _editorController.clear();
        _dirty = false;
        _textTooLarge = false;
      }
    });
  }

  void _applyPayload(
    final _FilePayload payload, {
    final bool textTooLarge = false,
  }) {
    _updatingEditor = true;
    if (payload.isText) {
      _editorController.text = payload.text ?? '';
    } else {
      _editorController.clear();
    }
    setState(() {
      _payload = payload;
      _dirty = false;
      _fileError = null;
      _textTooLarge = textTooLarge;
    });
    _updatingEditor = false;
  }

  bool _shouldSkipOpen(final _FileEntry entry) {
    return _selectedEntry?.path == entry.path && _payload != null && !_dirty;
  }

  void _startFileLoading(final _FileEntry entry) {
    setState(() {
      _selectedEntry = entry;
      _fileLoading = true;
      _fileError = null;
      _dirty = false;
      _textTooLarge = false;
    });
  }

  void _handleFileError(final Object error, final StackTrace stackTrace) {
    debugPrint('Failed to load file: $error\n$stackTrace');
    setState(() {
      _fileError = error.toString();
      _payload = null;
      _editorController.clear();
      _dirty = false;
      _textTooLarge = false;
    });
  }

  void _finishFileLoading() {
    setState(() {
      _fileLoading = false;
    });
  }

  void _startSaving() {
    setState(() {
      _savingFile = true;
      _fileError = null;
    });
  }

  void _markClean() {
    setState(() {
      _dirty = false;
    });
  }

  void _handleSaveError(final Object error, final StackTrace stackTrace) {
    debugPrint('File operation failed: $error\n$stackTrace');
    setState(() {
      _fileError = error.toString();
    });
  }

  void _finishSaving() {
    setState(() {
      _savingFile = false;
    });
  }

  void _clearState() {
    setState(() {
      _files = const [];
      _selectedEntry = null;
      _payload = null;
      _listError = null;
      _fileError = null;
      _listLoading = false;
      _fileLoading = false;
      _savingFile = false;
      _dirty = false;
      _textTooLarge = false;
    });
    _editorController.clear();
  }

  String? _profileText() {
    final text = _profileController.text.trim();
    return text.isEmpty ? null : text;
  }

  String? _pathText() {
    final text = _pathController.text.trim();
    return text.isEmpty ? null : text;
  }

  _FileEntry? _findByPath(
    final List<_FileEntry> files,
    final String path,
  ) {
    for (final entry in files) {
      if (entry.path == path) return entry;
    }
    return null;
  }
}

class _DisconnectedNotice extends StatelessWidget {
  const _DisconnectedNotice({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(final BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off, size: defaultIconSize * 2),
          const SizedBox(height: denseSpacing),
          const Text('Connect an application to inspect its files.'),
          const SizedBox(height: denseSpacing),
          DevToolsButton(
            label: 'Retry',
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}

class _FileStorageToolbar extends StatelessWidget {
  const _FileStorageToolbar({
    required this.options,
    required this.selected,
    required this.profileController,
    required this.pathController,
    required this.recursive,
    required this.refreshing,
    required this.onAreaChanged,
    required this.onRecursiveChanged,
    required this.onRefresh,
  });

  final List<_StorageOption> options;
  final _StorageOption selected;
  final TextEditingController profileController;
  final TextEditingController pathController;
  final bool recursive;
  final bool refreshing;
  final ValueChanged<_StorageOption> onAreaChanged;
  final ValueChanged<bool> onRecursiveChanged;
  final VoidCallback onRefresh;

  @override
  Widget build(final BuildContext context) {
    return Wrap(
      spacing: denseSpacing,
      runSpacing: denseSpacing,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 180,
          child: DropdownButton<_StorageOption>(
            isExpanded: true,
            value: selected,
            onChanged: refreshing ? null : _notifyAreaChanged,
            items: [
              for (final option in options)
                DropdownMenuItem(
                  value: option,
                  child: Text(option.label),
                ),
            ],
          ),
        ),
        SizedBox(
          width: 160,
          child: TextField(
            controller: profileController,
            decoration: const InputDecoration(
              labelText: 'Profile',
            ),
          ),
        ),
        SizedBox(
          width: 200,
          child: TextField(
            controller: pathController,
            decoration: const InputDecoration(
              labelText: 'Path prefix',
            ),
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: recursive,
              onChanged: refreshing ? null : onRecursiveChanged,
            ),
            const Text('Recursive'),
          ],
        ),
        DevToolsButton(
          label: refreshing ? 'Loading…' : 'Refresh',
          icon: Icons.refresh,
          onPressed: refreshing ? null : onRefresh,
        ),
      ],
    );
  }

  void _notifyAreaChanged(final _StorageOption? option) {
    if (option != null) onAreaChanged(option);
  }
}

class _FileListView extends StatelessWidget {
  const _FileListView({
    required this.files,
    required this.selected,
    required this.loading,
    required this.error,
    required this.onSelect,
  });

  final List<_FileEntry> files;
  final _FileEntry? selected;
  final bool loading;
  final String? error;
  final ValueChanged<_FileEntry> onSelect;

  @override
  Widget build(final BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null) {
      return _ErrorState(message: error!);
    }
    if (files.isEmpty) {
      return const Center(child: Text('No files found.'));
    }
    return OutlineDecoration.onlyRight(
      child: ListView.separated(
        itemCount: files.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final entry = files[index];
          final isSelected = selected?.path == entry.path;
          return ListTile(
            selected: isSelected,
            title: Text(entry.path),
            subtitle: Text(entry.description),
            onTap: () => onSelect(entry),
          );
        },
      ),
    );
  }
}

class _FileDetailView extends StatelessWidget {
  const _FileDetailView({
    required this.entry,
    required this.payload,
    required this.controller,
    required this.dirty,
    required this.loading,
    required this.saving,
    required this.error,
    required this.onReload,
    required this.onSave,
    required this.onDelete,
    required this.textTooLarge,
  });

  final _FileEntry? entry;
  final _FilePayload? payload;
  final TextEditingController controller;
  final bool dirty;
  final bool loading;
  final bool saving;
  final String? error;
  final VoidCallback onReload;
  final VoidCallback? onSave;
  final VoidCallback onDelete;
  final bool textTooLarge;

  @override
  Widget build(final BuildContext context) {
    if (entry == null) {
      return const Center(child: Text('Select a file to inspect.'));
    }
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return OutlineDecoration.onlyLeft(
      child: Padding(
        padding: const EdgeInsets.all(defaultSpacing),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DetailsHeader(
              entry: entry!,
              dirty: dirty,
              saving: saving,
              onReload: onReload,
              onSave: payload?.isText == true ? onSave : null,
              onDelete: onDelete,
            ),
            const SizedBox(height: denseSpacing),
            if (error != null)
              _ErrorBanner(message: error!)
            else if (textTooLarge)
              const Expanded(child: _LargeTextNotice())
            else if (payload == null)
              const Text('No data available.')
            else if (payload!.isText)
              Expanded(
                child: _EditableTextField(controller: controller),
              )
            else
              Expanded(
                child: _BinaryPreview(payload: payload!),
              ),
          ],
        ),
      ),
    );
  }
}

class _DetailsHeader extends StatelessWidget {
  const _DetailsHeader({
    required this.entry,
    required this.dirty,
    required this.saving,
    required this.onReload,
    required this.onSave,
    required this.onDelete,
  });

  final _FileEntry entry;
  final bool dirty;
  final bool saving;
  final VoidCallback onReload;
  final VoidCallback? onSave;
  final VoidCallback onDelete;

  @override
  Widget build(final BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(entry.path, style: theme.textTheme.titleMedium),
        const SizedBox(height: denseSpacing),
        Row(
          children: [
            Wrap(
              spacing: denseSpacing,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(entry.description),
                if (dirty)
                  const Text('(edited)',
                      style: TextStyle(color: Colors.orange)),
              ],
            ),
            const Spacer(),
            DevToolsButton(
              label: 'Reload',
              icon: Icons.refresh,
              onPressed: saving ? null : onReload,
            ),
            const SizedBox(width: denseSpacing),
            DevToolsButton(
              label: 'Delete',
              icon: Icons.delete_outline,
              onPressed: saving ? null : onDelete,
            ),
            if (onSave != null) ...[
              const SizedBox(width: denseSpacing),
              DevToolsButton(
                label: saving ? 'Saving…' : 'Save',
                icon: Icons.save_outlined,
                onPressed: saving || !dirty ? null : onSave,
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _EditableTextField extends StatelessWidget {
  const _EditableTextField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(final BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: null,
      expands: true,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        alignLabelWithHint: true,
        labelText: 'Contents',
      ),
      style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
    );
  }
}

class _BinaryPreview extends StatelessWidget {
  const _BinaryPreview({required this.payload});

  final _FilePayload payload;

  @override
  Widget build(final BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Binary data (base64):'),
        const SizedBox(height: denseSpacing),
        Expanded(
          child: SelectableText(
            payload.base64,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          ),
        ),
      ],
    );
  }
}

class _LargeTextNotice extends StatelessWidget {
  const _LargeTextNotice();

  @override
  Widget build(final BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(defaultSpacing),
        child: Text(
          'Text files larger than 4 MB cannot be viewed or edited here.',
          style: Theme.of(context).textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});

  final String message;

  @override
  Widget build(final BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Colors.red),
          const SizedBox(height: denseSpacing),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(final BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(denseSpacing),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
      ),
    );
  }
}

class _StorageOption {
  const _StorageOption(this.label, this.area);

  final String label;
  final String area;
}

const _storageOptions = [
  _StorageOption('Files', 'files'),
  _StorageOption('Documents', 'documents'),
  _StorageOption('Cache', 'cache'),
];

class _FileEntry {
  _FileEntry({
    required this.path,
    this.byteLength,
    this.lastModified,
  });

  factory _FileEntry.fromJson(final Map<String, Object?> json) {
    final modified = json['lastModified'] as String?;
    return _FileEntry(
      path: json['path'] as String,
      byteLength: json['byteLength'] as int?,
      lastModified: modified == null ? null : DateTime.tryParse(modified),
    );
  }

  final String path;
  final int? byteLength;
  final DateTime? lastModified;

  String get description {
    final size = _formatFileSize(byteLength);
    final timestamp = lastModified == null
        ? 'unknown'
        : lastModified!.toLocal().toIso8601String();
    return 'Size: $size • Modified: $timestamp';
  }
}

class _FilePayload {
  const _FilePayload({
    required this.base64,
    this.text,
    this.isTextFile = false,
  });

  final String base64;
  final String? text;
  final bool isTextFile;

  bool get isText => isTextFile && text != null;
}

String _formatFileSize(final int? bytes) {
  if (bytes == null) return 'unknown';
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(kb >= 100 ? 0 : 1)} KB';
  final mb = kb / 1024;
  return '${mb.toStringAsFixed(mb >= 100 ? 0 : 1)} MB';
}

class _FileStorageApi {
  Future<List<_FileEntry>> listFiles({
    required final String area,
    final String? profile,
    final String? path,
    final bool recursive = true,
  }) async {
    final response = await serviceManager.callServiceExtensionOnMainIsolate(
      'ext.file_storage.listFiles',
      args: _buildArgs(
        area: area,
        profile: profile,
        path: path,
        recursive: recursive,
      ),
    );
    final data = response.json?['files'] as List<dynamic>? ?? const [];
    return data
        .whereType<Map<String, Object?>>()
        .map(_FileEntry.fromJson)
        .toList();
  }

  Future<_FilePayload> readFile({
    required final String area,
    final String? profile,
    required final String path,
  }) async {
    final response = await serviceManager.callServiceExtensionOnMainIsolate(
      'ext.file_storage.readFile',
      args: _buildArgs(
        area: area,
        profile: profile,
        path: path,
      ),
    );
    final data = response.json?['data'] as String?;
    final text = response.json?['text'] as String?;
    if (data == null) {
      throw StateError('File "$path" returned no data.');
    }
    return _FilePayload(
      base64: data,
      text: text,
      isTextFile: text != null,
    );
  }

  Future<void> saveFile({
    required final String area,
    final String? profile,
    required final String path,
    required final String text,
    required final bool isText,
  }) async {
    final args = _buildArgs(
      area: area,
      profile: profile,
      path: path,
    );
    if (isText) {
      args['encoding'] = 'text';
      args['payload'] = text;
    } else {
      args['encoding'] = 'base64';
      args['payload'] = text;
    }
    await serviceManager.callServiceExtensionOnMainIsolate(
      'ext.file_storage.saveFile',
      args: args,
    );
  }

  Future<void> deleteFile({
    required final String area,
    final String? profile,
    required final String path,
  }) async {
    await serviceManager.callServiceExtensionOnMainIsolate(
      'ext.file_storage.deleteFile',
      args: _buildArgs(
        area: area,
        profile: profile,
        path: path,
      ),
    );
  }

  Map<String, Object?> _buildArgs({
    required final String area,
    final String? profile,
    final String? path,
    final bool? recursive,
  }) {
    final args = <String, Object?>{
      'area': area,
    };
    if (profile != null) args['profile'] = profile;
    if (path != null) args['path'] = path;
    if (recursive != null) args['recursive'] = '$recursive';
    return args;
  }
}
