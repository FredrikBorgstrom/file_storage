# file_storage_devtools_extension

## Build Devtools Extension

Either run the vscode task "build devtools extension" or execute the following commands in the terminal:

1. cd extension/file_storage_devtools_extension
2. flutter pub get
3. dart run devtools_extensions build_and_copy --source=. --dest=../devtools
