import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onenote/data/attachment_store.dart';
import 'package:onenote/ui/markdown_view.dart';
import 'package:onenote/ui/theme.dart';

void main() {
  const href = 'https://blog.afreto.top/2020/08/07/v2ray/';
  final openKey = Platform.isMacOS
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;
  final otherKey = Platform.isMacOS
      ? LogicalKeyboardKey.controlLeft
      : LogicalKeyboardKey.metaLeft;

  Future<List<String>> pumpLink(
    WidgetTester tester, {
    String data = '[v2ray 搭建记录]($href)',
    void Function(String id)? onAttachmentLink,
  }) async {
    final opened = <String>[];
    await tester.pumpWidget(MaterialApp(
      theme: buildInkTheme(Brightness.dark),
      home: Scaffold(
        body: MarkdownView(
          content: data,
          onAttachmentLink: onAttachmentLink,
          browserLauncherOverride: (url) async => opened.add(url),
        ),
      ),
    ));
    return opened;
  }

  testWidgets('plain click selects text without opening or snack',
      (tester) async {
    final opened = await pumpLink(tester);
    await tester.tap(find.text('v2ray 搭建记录'),
        kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(opened, isEmpty);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('open modifier click launches the default browser',
      (tester) async {
    final opened = await pumpLink(tester);
    await tester.sendKeyDownEvent(openKey);
    await tester.tap(find.text('v2ray 搭建记录'),
        kind: PointerDeviceKind.mouse);
    await tester.pump();
    await tester.sendKeyUpEvent(openKey);
    expect(opened, [href]);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('non-matching modifier click does not launch', (tester) async {
    final opened = await pumpLink(tester);
    await tester.sendKeyDownEvent(otherKey);
    await tester.tap(find.text('v2ray 搭建记录'),
        kind: PointerDeviceKind.mouse);
    await tester.pump();
    await tester.sendKeyUpEvent(otherKey);
    expect(opened, isEmpty);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('non-http links stay on the snack bar path', (tester) async {
    final opened =
        await pumpLink(tester, data: '[mail](mailto:a@example.com)');
    await tester.sendKeyDownEvent(openKey);
    await tester.tap(find.text('mail'), kind: PointerDeviceKind.mouse);
    await tester.pump();
    await tester.sendKeyUpEvent(openKey);
    expect(opened, isEmpty);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('attachment links keep their own handler under the modifier',
      (tester) async {
    final id = 'a' * 64;
    final attached = <String>[];
    final opened = await pumpLink(
      tester,
      data: '[file](${AttachmentStore.scheme}://$id)',
      onAttachmentLink: attached.add,
    );
    await tester.sendKeyDownEvent(openKey);
    await tester.tap(find.text('file'), kind: PointerDeviceKind.mouse);
    await tester.pump();
    await tester.sendKeyUpEvent(openKey);
    expect(attached, [id]);
    expect(opened, isEmpty);
    expect(find.byType(SnackBar), findsNothing);
  });
}