import 'dart:io';

// ignore: implementation_imports
import 'package:desktop_drop/src/native_transport.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onenote/data/app_db.dart';
import 'package:onenote/state/app_state.dart';
import 'package:onenote/ui/note_view.dart';
import 'package:onenote/ui/theme.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('editor content font follows ui font switch', (tester) async {
    NativeTransport.debugOverride = NativeTransport.testing()
      ..invokeHandler = (call) async {
        if (call.method == 'initialize') {
          return {'view': (call.arguments as Map)['view']};
        }
        return null;
      };
    addTearDown(() => NativeTransport.debugOverride = null);
    final supportDir =
        Directory.systemTemp.createTempSync('onenote_editor_font');
    addTearDown(() => supportDir.deleteSync(recursive: true));
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => supportDir.path,
    );
    final db = AppDb(NativeDatabase.memory());
    final state = AppState(db);
    addTearDown(() async {
      state.dispose();
      await db.close();
    });

    late Note note;
    await tester.runAsync(() async {
      final notebook = await db.createNotebook('work');
      note = await db.createNote(notebook.id,
          title: 't', content: 'hello 中文');
      await state.init();
    });

    Widget app(String sans) => MaterialApp(
          theme: buildInkTheme(Brightness.dark, sans: sans),
          home: Scaffold(
            body: NoteView(
              state: state,
              noteId: note.id,
              showBack: false,
              onBack: () {},
            ),
          ),
        );

    TextStyle? contentStyle() => tester
        .widgetList<TextField>(find.byType(TextField))
        .firstWhere((f) => f.expands)
        .style;

    await tester.pumpWidget(app(miSansFamily));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    expect(contentStyle()?.fontFamily, miSansFamily);

    await tester.pumpWidget(app(interFamily));
    await tester.pumpAndSettle();
    expect(contentStyle()?.fontFamily, interFamily);
  });
}