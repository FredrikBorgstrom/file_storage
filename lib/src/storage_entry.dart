/// The top-level storage areas supported by [FileStorage].
enum FileStorageArea {
  files,
  documents,
  cache;

  String get name {
    switch (this) {
      case FileStorageArea.files:
        return 'files';
      case FileStorageArea.documents:
        return 'documents';
      case FileStorageArea.cache:
        return 'cache';
    }
  }
}

/// Metadata describing a stored file.
class FileStorageEntry {
  const FileStorageEntry({
    required this.path,
    this.byteLength,
    this.lastModified,
  });

  /// Path relative to the queried storage root.
  final String path;

  /// File length in bytes when known.
  final int? byteLength;

  /// Last modification time in UTC when known.
  final DateTime? lastModified;

  Map<String, Object?> toJson() => <String, Object?>{
        'path': path,
        'byteLength': byteLength,
        'lastModified': lastModified?.toIso8601String(),
      };
}
