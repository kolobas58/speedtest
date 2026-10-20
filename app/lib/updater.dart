// Автообновление, как в 1.x: манифест в GitHub Releases подписан ключом разработчика (Ed25519) —
// без верной подписи и совпадения SHA-256 ничего не ставится.
//   Windows — latest.json → Speedtest-Portable.exe: подменяем свой Speedtest.exe (стартер к этому моменту уже вышел),
//             новая версия — со следующего запуска (так же обновляются и копии 1.x).
//   Linux   — latest-linux.json → архив: распаковываем рядом, подменяем файлы после закрытия окна.
//   Android — latest-android.json → APK: проверяем и открываем системный установщик (молча Android ставить не даёт).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart' as c;
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:ota_update/ota_update.dart';
import 'package:path_provider/path_provider.dart';

import 'engine.dart' show version, ua;

const updateRepo = 'kolobas58/speedtest';
const updatePubkey = '0696ac4d041b14d1a288ae43fb9201ead6d69e77be48fd0d196c473f6bafbc4e';
// для проверки в CI: SPEEDTEST_TEST_VERSION=1.0.0 — программа считает себя старой; SPEEDTEST_UPDATE_BASE — другой адрес релиза
final _current = Platform.environment['SPEEDTEST_TEST_VERSION'] ?? version;
final _base = Platform.environment['SPEEDTEST_UPDATE_BASE'] ?? 'https://github.com/$updateRepo/releases/latest/download/';

void _log(String m) {
  try {
    File('${Directory.systemTemp.path}${Platform.pathSeparator}speedtest_update.log')
        .writeAsStringSync('${DateTime.now().toIso8601String()} $m\n', mode: FileMode.append);
  } catch (_) {}
  if (Platform.environment.containsKey('SPEEDTEST_TEST_VERSION')) stderr.writeln('[update] $m');
}

bool newer(String a, String b) {
  List<int> p(String s) => [...s.replaceFirst('v', '').split('.').map((x) => int.tryParse(x) ?? 0), 0, 0, 0];
  final x = p(a), y = p(b);
  for (var i = 0; i < 3; i++) {
    if (x[i] != y[i]) return x[i] > y[i];
  }
  return false;
}

List<int> _hex(String h) => [for (var i = 0; i + 1 < h.length; i += 2) int.parse(h.substring(i, i + 2), radix: 16)];

/// Путь к Speedtest.exe, из которого запущено приложение (передаёт стартер: --exe "<путь>").
String? exePath(List<String> args) {
  final i = args.indexOf('--exe');
  return (i >= 0 && i + 1 < args.length) ? args[i + 1] : null;
}

enum UpState { idle, downloading, ready, done, failed }

class Updater extends ChangeNotifier {
  final List<String> args;
  Updater(this.args);

  UpState state = UpState.idle;
  String? newVersion;
  String? _url, _sha;
  int _size = 0;
  Directory? _staged; // Linux: распакованная новая версия
  double progress = 0;
  bool _started = false;

  static String get _manifest => Platform.isWindows ? 'latest.json' : Platform.isLinux ? 'latest-linux.json' : 'latest-android.json';

  /// Проверяем после первого замера, чтобы не мешать ему трафиком.
  Future<void> check() async {
    if (_started) return;
    _started = true;
    try {
      if (Platform.isWindows && exePath(args) == null) {
        _log('check: нет --exe (запуск не через Speedtest.exe) — пропускаю');
        return;
      }
      final r = await http.get(Uri.parse('$_base$_manifest'), headers: {'User-Agent': ua}).timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) {
        _log('check: HTTP ${r.statusCode}');
        return;
      }
      final m = jsonDecode(r.body) as Map<String, dynamic>;
      final ver = '${m['version']}', name = '${m['file']}', sha = '${m['sha256']}'.toLowerCase();
      final size = (m['size'] as num).toInt();
      final ok = await Ed25519().verify(
        utf8.encode('$ver|$name|$sha|$size'),
        signature: Signature(_hex('${m['sig']}'), publicKey: SimplePublicKey(_hex(updatePubkey), type: KeyPairType.ed25519)),
      );
      _log('check: $ver (current $_current), подпись ${ok ? 'верна' : 'НЕВЕРНА'}');
      if (!ok || !newer(ver, _current) || name.contains('/') || name.contains('\\') || size > 200000000) return;
      newVersion = ver;
      _url = '$_base$name';
      _sha = sha;
      _size = size;
      notifyListeners();
      if (!Platform.isAndroid) await _download();
    } catch (e) {
      _log('check: $e');
    }
  }

  Future<File> _fetch(String path) async {
    state = UpState.downloading;
    notifyListeners();
    final f = File(path);
    final rq = await http.Client().send(http.Request('GET', Uri.parse(_url!))..headers['User-Agent'] = ua);
    final sink = f.openWrite();
    var got = 0;
    await for (final chunk in rq.stream) {
      got += chunk.length;
      if (got > _size) throw Exception('файл больше заявленного');
      sink.add(chunk);
    }
    await sink.close();
    if (got != _size || c.sha256.convert(f.readAsBytesSync()).toString() != _sha) {
      f.deleteSync();
      throw Exception('контрольная сумма не совпала');
    }
    return f;
  }

  Future<void> _download() async {
    try {
      if (Platform.isWindows) {
        final exe = exePath(args)!;
        final tmp = await _fetch('$exe.new');
        final old = File('$exe.old');
        try {
          if (old.existsSync()) old.deleteSync();
        } catch (_) {}
        try {
          tmp.renameSync(exe);
        } catch (_) {
          File(exe).renameSync(old.path);
          tmp.renameSync(exe);
        }
        state = UpState.done; // со следующего запуска
        _log('download: Speedtest.exe обновлён до $newVersion');
      } else {
        final dir = File(Platform.resolvedExecutable).parent;
        try {
          File('${dir.path}/.w')
            ..writeAsStringSync('1')
            ..deleteSync();
        } catch (_) {
          _log('download: папка программы только для чтения — ${dir.path}');
          state = UpState.idle;
          return;
        }
        final tmp = Directory('${(await getTemporaryDirectory()).path}/speedtest_update_$newVersion');
        if (tmp.existsSync()) tmp.deleteSync(recursive: true);
        tmp.createSync(recursive: true);
        final f = await _fetch('${tmp.path}/pkg.tar.gz');
        final arc = TarDecoder().decodeBytes(GZipDecoder().decodeBytes(f.readAsBytesSync()));
        final out = Directory('${tmp.path}/x')..createSync();
        for (final e in arc.files) {
          if (e.name.contains('..')) continue;
          final p = '${out.path}/${e.name}';
          if (e.isFile) {
            File(p)
              ..parent.createSync(recursive: true)
              ..writeAsBytesSync(e.content as List<int>);
          } else {
            Directory(p).createSync(recursive: true);
          }
        }
        File? exe;
        for (final e in out.listSync(recursive: true)) {
          if (e is File && e.uri.pathSegments.last == 'speedtest') {
            exe = e;
            break;
          }
        }
        if (exe == null) throw Exception('в архиве нет программы');
        await Process.run('chmod', ['+x', exe.path]);
        _staged = exe.parent;
        state = UpState.ready;
        _log('download: готово ${_staged!.path}');
      }
    } catch (e) {
      _log('download: $e');
      state = UpState.failed;
    }
    notifyListeners();
  }

  /// Linux: подменить файлы после выхода (вызывается при закрытии окна).
  Future<void> applyOnExit({bool restart = false}) async {
    if (!Platform.isLinux || state != UpState.ready || _staged == null) return;
    final dst = File(Platform.resolvedExecutable).parent.path;
    final sh = File('${_staged!.parent.parent.path}/apply.sh')
      ..writeAsStringSync('while kill -0 $pid 2>/dev/null; do sleep 0.2; done\n'
          'cp -rf "${_staged!.path}/." "$dst/" && chmod +x "$dst/speedtest"\n'
          '${restart ? '(cd "$dst" && nohup ./speedtest >/dev/null 2>&1 &)\n' : ''}');
    await Process.start('sh', [sh.path], mode: ProcessStartMode.detached);
    _log('apply: restart=$restart');
    state = UpState.done;
  }

  /// Android: скачать проверенный APK и открыть установщик.
  void installAndroid() {
    if (_url == null || state == UpState.downloading) return;
    state = UpState.downloading;
    progress = 0;
    notifyListeners();
    try {
      OtaUpdate().execute(_url!, destinationFilename: 'Speedtest-$newVersion.apk', sha256checksum: _sha).listen((e) {
        final s = e.status.toString();
        if (s.contains('ERROR')) {
          state = UpState.failed;
        } else if (s.contains('DOWNLOADING')) {
          progress = (double.tryParse(e.value ?? '') ?? 0) / 100;
        } else {
          state = UpState.idle;
        }
        notifyListeners();
      }, onError: (_) {
        state = UpState.failed;
        notifyListeners();
      });
    } catch (_) {
      state = UpState.failed;
      notifyListeners();
    }
  }
}
