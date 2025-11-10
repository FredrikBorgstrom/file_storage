// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:devtools_extensions/devtools_extensions.dart';

import 'package:file_storage_devtools_extension/main.dart';

void main() {
  testWidgets('wraps the extension in DevToolsExtension', (tester) async {
    await tester.pumpWidget(const FileStorageDevToolsApp());
    expect(find.byType(DevToolsExtension), findsOneWidget);
  });
}
