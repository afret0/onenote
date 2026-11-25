import 'dart:io';

// ignore: implementation_imports
import 'package:desktop_drop/src/native_transport.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onenote/data/app_db.dart';
import 'package:onenote/state/app_state.dart';
import 'package:onenote/synthetic_paste.dart';
import 'package:onenote/ui/note_view.dart';
import 'package:onenote/ui/theme.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> deliverSyntheticPaste() async {
    await binding.defaultBinaryMessenger.handlePlatformMessage(
      'onenote/synthetic_paste',
      const StandardMethodCodec().encodeMethodCall(const MethodCall('paste')),
      (_) {},
    );
  }

  void mockClipboard(String text) {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.getData') {
          return {'text': text};
        }
        return null;
      },
    );
    addTearDown(() => binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
  }

  testWidgets('synthetic paste inserts clipboard text into focused field',
      (tester) async {
    SyntheticPaste.install();
    mockClipboard('from raycast');
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TextField(controller: controller, autofocus: true),
      ),
    ));
    await tester.pumpAndSettle();

    await deliverSyntheticPaste();
    await tester.pumpAndSettle();

    expect(controller.text, 'from raycast');
  });

  testWidgets('ancestor PasteTextIntent override wins over standard paste',
      (tester) async {
    SyntheticPaste.install();
    mockClipboard('from raycast');
    var overridden = false;
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Actions(
          actions: {
            PasteTextIntent: CallbackAction<PasteTextIntent>(
              onInvoke: (_) {
                overridden = true;
                return null;
              },
            ),
          },
          child: TextField(controller: controller, autofocus: true),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await deliverSyntheticPaste();
    await tester.pumpAndSettle();

    expect(overridden, isTrue);
    expect(controller.text, isEmpty);
  });

  testWidgets('note editor pastes synthetic clipboard through paste handler',
      (tester) async {
    NativeTransport.debugOverride = NativeTransport.testing()
      ..invokeHandler = (call) async {
        if (call.method == 'initialize') {
          return {'view': (call.arguments as Map)['view']};
        }
        return null;
      };
    addTearDown(() => NativeTransport.debugOverride = null);
    final supportDir =
        Directory.systemTemp.createTempSync('onenote_synthetic_paste');
    addTearDown(() => supportDir.deleteSync(recursive: true));
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => supportDir.path,
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('pasteboard'),
      (call) async => null,
    );
    addTearDown(() => binding.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('pasteboard'), null));
    SyntheticPaste.install();
    mockClipboard('raycast 剪贴板');

    final db = AppDb(NativeDatabase.memory());
    final state = AppState(db);
    addTearDown(() async {
      state.dispose();
      await db.close();
    });

    late Note note;
    await tester.runAsync(() async {
      final notebook = await db.createNotebook('work');
      note = await db.createNote(notebook.id, title: 't', content: 'hello');
      await state.init();
    });

    await tester.pumpWidget(MaterialApp(
      theme: buildInkTheme(Brightness.dark, sans: miSansFamily),
      home: Scaffold(
        body: NoteView(
          state: state,
          noteId: note.id,
          showBack: false,
          onBack: () {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();

    await deliverSyntheticPaste();
    await tester.pumpAndSettle();

    final contentField = tester
        .widgetList<TextField>(find.byType(TextField))
        .firstWhere((f) => f.expands);
    expect(contentField.controller!.text, 'raycast 剪贴板hello');
  });
}
