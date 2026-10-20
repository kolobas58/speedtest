// Speedtest by kolobas58 — замер скорости интернета. Windows · Linux · Android.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'engine.dart' show version;
import 'home.dart';
import 'store.dart';
import 'updater.dart';

final desktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (desktop) {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        size: Size(400, 540),
        minimumSize: Size(340, 470),
        center: true,
        title: 'Speedtest by kolobas58',
        titleBarStyle: TitleBarStyle.hidden, // без системной рамки — своя полоска заголовка
        windowButtonVisibility: false,
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
    await windowManager.setPreventClose(true);
  }
  // хвост прошлого обновления (Windows): Speedtest.exe.old
  final exe = exePath(args);
  if (exe != null) {
    try {
      File('$exe.old').deleteSync();
    } catch (_) {}
  }
  final store = await Store.open();
  // «обновлено до X» — один раз после смены версии
  final last = store.p.getString('last_version');
  final note = (last != null && last != version) ? 'обновлено до $version' : null;
  await store.p.setString('last_version', version);
  runApp(SpeedtestApp(store: store, updater: Updater(args), note: note));
}

class SpeedtestApp extends StatelessWidget {
  final Store store;
  final Updater updater;
  final String? note;
  const SpeedtestApp({super.key, required this.store, required this.updater, this.note});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Speedtest by kolobas58',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, fontFamily: 'Segoe UI', fontFamilyFallback: const ['Roboto', 'Noto Sans', 'DejaVu Sans']),
      builder: (context, child) => Platform.isLinux ? DragToResizeArea(resizeEdgeSize: 6, child: child!) : child!,
      home: Home(store: store, updater: updater, desktop: desktop, updatedNote: note),
    );
  }
}
