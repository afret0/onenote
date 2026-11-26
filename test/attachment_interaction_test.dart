import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onenote/data/app_db.dart';
import 'package:onenote/state/app_state.dart';
import 'package:onenote/ui/home_page.dart';
import 'package:onenote/ui/markdown_view.dart';
import 'package:onenote/ui/theme.dart';

void main() {
  Future<Uint8List> pngBytes() async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(const Rect.fromLTWH(0, 0, 60, 40),
        ui.Paint()..color = const ui.Color(0xFF7719AA));
    final image = await recorder.endRecording().toImage(60, 40);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }

  Future<(AppDb, AppState, Note, String, String)> seed(
      WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('onenote_attach_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => dir.path,
    );
    var now = 1700000000000;
    final db = AppDb(NativeDatabase.memory(), clock: () => now);
    final state = AppState(db);
    addTearDown(() async {
      state.dispose();
      await db.close();
    });
    late Note note;
    late String imageId;
    late String pdfId;
    await tester.runAsync(() async {
      final bytes = await pngBytes();
      final work = await db.createNotebook('工作');
      now += 1000;
      await state.init();
      imageId = await state.attachments!.save(bytes, 'pic.png');
      pdfId = await state.attachments!
          .save(Uint8List.fromList(utf8.encode('%PDF-1.4 test')), 'doc.pdf');
      now += 1000;
      note = await db.createNote(work.id,
          title: '附件笔记',
          content: 'before\n\n'
              '![pic.png](onenote-asset://$imageId)\n\n'
              'middle\n\n'
              '![pic.png](onenote-asset://$imageId)\n\n'
              'after\n\n'
              '[doc.pdf](onenote-asset://$pdfId)');
      await state.refresh();
      await state.openNote(note.id);
      await tester.pumpWidget(MaterialApp(
        theme: buildInkTheme(Brightness.dark),
        home: HomePage(state: state),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    });
    return (db, state, note, imageId, pdfId);
  }

  Finder inlineImages() => find.descendant(
      of: find.byType(MarkdownView), matching: find.byType(Image));

  testWidgets('image right-click delete removes only the clicked occurrence',
      (WidgetTester tester) async {
    final (db, _, note, imageId, _) = await seed(tester);
    expect(inlineImages(), findsNWidgets(2));

    await tester.tap(inlineImages().first, buttons: kSecondaryButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('另存为'), findsOneWidget);
    expect(find.text('复制'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);

    await tester.tap(find.text('删除'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('删除附件'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.pump(const Duration(milliseconds: 900));
    late String saved;
    await tester.runAsync(() async {
      saved = (await db.findNote(note.id))!.content;
    });
    final ref = '![pic.png](onenote-asset://$imageId)';
    expect(saved.contains('before\n\nmiddle'), isTrue);
    expect(ref.allMatches(saved).length, 1);
    expect(saved.indexOf(ref) > saved.indexOf('middle'), isTrue);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('tap image opens zoom viewer, copy works, Esc closes',
      (WidgetTester tester) async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('pasteboard'),
            (call) async {
      calls.add(call);
      return null;
    });
    await seed(tester);

    await tester.runAsync(() async {
      await tester.tap(inlineImages().first);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    });
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.text('pic.png'), findsWidgets);

    await tester.runAsync(() async {
      await tester.tap(find.byType(InteractiveViewer),
          buttons: kSecondaryButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('复制'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    });
    expect(calls.map((c) => c.method), contains('writeImage'));
    expect(find.text('图片已复制'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(InteractiveViewer), findsNothing);
  });

  testWidgets('viewer delete closes viewer and removes the occurrence',
      (WidgetTester tester) async {
    final (db, _, note, imageId, _) = await seed(tester);
    await tester.runAsync(() async {
      await tester.tap(inlineImages().last);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    });
    expect(find.byType(InteractiveViewer), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.byType(InteractiveViewer),
          buttons: kSecondaryButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('删除'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    });
    expect(find.text('删除附件'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    });
    expect(find.byType(InteractiveViewer), findsNothing);

    late String saved;
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 900));
      saved = (await db.findNote(note.id))!.content;
    });
    final ref = '![pic.png](onenote-asset://$imageId)';
    expect(ref.allMatches(saved).length, 1);
    expect(saved.indexOf(ref) < saved.indexOf('middle'), isTrue);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('pdf link renders interactive and opens context menu',
      (WidgetTester tester) async {
    await seed(tester);
    final link = find.byWidgetPredicate((w) =>
        w is SelectableText &&
        w.textSpan != null &&
        w.textSpan!.toPlainText().contains('doc.pdf'));
    expect(link, findsOneWidget);

    await tester.tap(link, buttons: kSecondaryButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('另存为'), findsOneWidget);
    expect(find.text('复制'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);

    await tester.tapAt(const Offset(1200, 60));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.text('另存为'), findsNothing);
  });
}