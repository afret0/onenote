import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onenote/data/app_db.dart';
import 'package:onenote/main.dart';

void main() {
  testWidgets('empty state shows brand and create entry',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final db = AppDb(NativeDatabase.memory());
    await tester.pumpWidget(OneNoteApp(db: db));
    await tester.pumpAndSettle();

    expect(find.text('onenote'), findsOneWidget);
    expect(find.text('还没有笔记，写下第一条吧'), findsOneWidget);
    expect(find.text('全部笔记'), findsWidgets);
    expect(find.text('回收站'), findsOneWidget);
  });
}