import 'package:flutter/material.dart';

import 'data/app_db.dart';
import 'state/app_state.dart';
import 'ui/home_page.dart';
import 'ui/theme.dart';
import 'window_setup.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = AppDb(AppDb.openExecutor());
  await db.purgeExpired();
  WindowSizeController? windowController;
  if (isDesktopWindow) {
    windowController = WindowSizeController(db);
    await windowController.init();
  }
  runApp(OneNoteApp(db: db, windowController: windowController));
}

class OneNoteApp extends StatefulWidget {
  const OneNoteApp({super.key, required this.db, this.windowController});

  final AppDb db;
  final WindowSizeController? windowController;

  @override
  State<OneNoteApp> createState() => _OneNoteAppState();
}

class _OneNoteAppState extends State<OneNoteApp> {
  late final AppState state;

  @override
  void initState() {
    super.initState();
    state = AppState(widget.db);
    state.init();
  }

  @override
  void dispose() {
    widget.windowController?.dispose();
    state.dispose();
    widget.db.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'onenote',
      theme: buildInkTheme(Brightness.light),
      darkTheme: buildInkTheme(Brightness.dark),
      themeMode: ThemeMode.dark,
      home: HomePage(state: state),
    );
  }
}
