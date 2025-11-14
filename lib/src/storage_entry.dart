/// The top-level storage areas supported by [FileStorage].
enum FileStorageArea
{
  files,
  documents,
  cache;

  static FileStorageArea fromName(final String name)
  {
    final area = FileStorageArea.values.asNameMap()[name];
    if (area == null) {
      throw UnsupportedError('Unknown storage area: $name');
    }
    return area;
  }
}


/// Metadata describing a stored file.
class FileStorageEntry
{
  /// Path relative to the queried storage root.
  final String path;

  /// File length in bytes when known.
  final int? byteLength;

  /// Last modification time in UTC when known.
  /// 
  /// Always `null` under the web platform.
  final DateTime? lastModified;

  const FileStorageEntry({
    required this.path,
    this.byteLength,
    this.lastModified,
  });

  Map<String, dynamic> toJson() => {
    'path': path,
    'byteLength': byteLength,
    'lastModified': lastModified?.toIso8601String(),
  };
}
