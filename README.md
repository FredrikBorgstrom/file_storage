This is a simple cross-platform package to operate files in available on a certain platform destinations. Uses idb_shim under the web platform.

## Features

- Provides with destinations of
    - Application's files,
    - Documents,
    - Cache files.
- Recursive creation of folders inside supported destinations.
- Checking existence of a certain file by its path.
- Loading and saving of
    - binary data (`List<int>`),
    - text (utf8-encoded),
    - json objects and arrays.
- Saving stream of data (`List<int>`).

## Usage

```dart
final fileStorage = FileStorage();
final documentsPath = await fileStorage.getDocumentsPath();
final filePath = '$documentsPath/my_folder/my_file.txt';
await fileStorage.ensurePathExists(fileName);
await fileStorage.saveText(fileName, 'My text');
final savedText = await fileStorage.loadText(fileName);
print('Saved text is: $savedText');
final bytes1 = Uint8List.fromList([ 1, 2, 3 ]);
final bytes2 = Uint8List.fromList([ 4, 5, 6 ]);
await fileStorage.saveStream(fileName, Stream.fromIterable([
  bytes1, bytes2
]));
```

## DevTools extension

The package ships with a Flutter DevTools extension that lets you explore,
edit, and delete stored files while debugging. Register the service
extensions during development to enable the bridge between your app and the
DevTools UI:

```dart
import 'package:file_storage/file_storage.dart';

void main() {
  assert(() {
    registerFileStorageDevTools();
    return true;
  }());
  runApp(const MyApp());
}
```

Make sure your pubspec.yaml contains this:

```yaml
devtools:
   extensions:
      - file_storage
```

If the devtools extension doesn't show up, make sure that there's a `devtools_options.yaml` file in the root of your project with this content:

```yaml
extensions:
  - file_storage: true
```

Whenever you change the extension UI, rebuild the static assets before
publishing the package:

```
dart run devtools_extensions build_and_copy \
    --source=extension/file_storage_devtools_extension \
    --dest=extension/devtools
```
