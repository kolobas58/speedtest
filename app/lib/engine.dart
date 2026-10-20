// Замер — как в 1.x: параллельно пингуем ~40 серверов (LibreSpeed, Cloudflare, Vultr), берём ближайший живой,
// пинг/джиттер по 12 запросам, загрузка и отдача в 4 потока по 10 с (первые 1,5 с — разгон, в итог не идут).
// При сбое сервера на лету переключаемся на следующий.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'store.dart';

const version = '2.0.2';
const ua = 'Mozilla/5.0 Speedtest-kolobas58/$version';
const streams = 4;
const duration = 10.0; // с на фазу (после последнего переключения сервера)
const maxPhase = 22.0; // жёсткий предел фазы, с
const warmup = 1.5;
const ulChunk = 4000000; // байт на один POST (под лимиты PHP/nginx у серверов)
const searchMin = 0.7, searchFav = 0.35, searchMax = 3.0;
const maxFails = 3;
const gaugeMax = 1000.0;
const librespeedList = 'https://librespeed.org/backend-servers/servers.php';

// (название, база, dl, ul, ping)
const _builtin = [
  ['Los Angeles, USA (Clouvider)', 'https://la.speedtest.clouvider.net/backend', 'garbage.php', 'empty.php', 'empty.php'],
  ['Los Angeles, USA (Sharktech)', 'https://laxspeed.sharktech.net', 'backend/garbage.php', 'backend/empty.php', 'backend/empty.php'],
  ['Las Vegas, USA (Sharktech)', 'https://lasspeed.sharktech.net', 'backend/garbage.php', 'backend/empty.php', 'backend/empty.php'],
  ['Denver, USA (Sharktech)', 'https://denspeed.sharktech.net', 'backend/garbage.php', 'backend/empty.php', 'backend/empty.php'],
  ['Chicago, USA (Sharktech)', 'https://chispeed.sharktech.net', 'backend/garbage.php', 'backend/empty.php', 'backend/empty.php'],
  ['Grand Rapids, USA (RackGenius)', 'https://mispeed.rackgenius.com/', 'backend/garbage.php', 'backend/empty.php', 'backend/empty.php'],
  ['Atlanta, USA (Clouvider)', 'https://atl.speedtest.clouvider.net/backend', 'garbage.php', 'empty.php', 'empty.php'],
  ['New York, USA (Clouvider)', 'https://nyc.speedtest.clouvider.net/backend', 'garbage.php', 'empty.php', 'empty.php'],
  ['London, UK (Clouvider)', 'https://lon.speedtest.clouvider.net/backend', 'garbage.php', 'empty.php', 'empty.php'],
  ['Amsterdam, NL (Clouvider)', 'https://ams.speedtest.clouvider.net/backend', 'garbage.php', 'empty.php', 'empty.php'],
  ['Amsterdam, NL (Sharktech)', 'https://amsspeed.sharktech.net', 'backend/garbage.php', 'backend/empty.php', 'backend/empty.php'],
  ['Frankfurt, DE (Clouvider)', 'https://fra.speedtest.clouvider.net/backend', 'garbage.php', 'empty.php', 'empty.php'],
  ['Frankfurt, DE (FS IT-Systeme)', 'https://speed.fs-it.systems/', 'backend/garbage.php', 'backend/empty.php', 'backend/empty.php'],
  ['Helsinki, FI (Hetzner)', 'https://www.librespeed.fi/', 'backend/garbage.php', 'backend/empty.php', 'backend/empty.php'],
  ['Prague, CZ (CESNET)', 'https://speedtest.cesnet.cz', 'backend/garbage.php', 'backend/empty.php', 'backend/empty.php'],
  ['Prague, CZ (Turris)', 'https://librespeed.turris.cz', 'backend/garbage.php', 'backend/empty.php', 'backend/empty.php'],
  ['Poznan, PL (INEA)', 'https://speedtest.kamilszczepanski.com', 'garbage.php', 'empty.php', 'empty.php'],
  ['Roma, IT (GARR)', 'https://st-be-rm2.infra.garr.it', 'garbage.php', 'empty.php', 'empty.php'],
  ['Belgrade, RS (SOX)', 'https://speedtest1.sox.rs/librespeed/', 'backend/garbage.php', 'backend/empty.php', 'backend/empty.php'],
  ['Novi Sad, RS (E-CAPS)', 'https://speed1.e-caps.net', 'backend/garbage.php', 'backend/empty.php', 'backend/empty.php'],
  ['Argalasti, GR (Cosmote)', 'https://argalasti.skoultsos.eu/', 'backend/garbage.php', 'backend/empty.php', 'backend/empty.php'],
  ['Tokyo, JP (A573)', 'https://librespeed.a573.net/', 'backend/garbage.php', 'backend/empty.php', 'backend/empty.php'],
];
const _vultr = [
  ['Los Angeles', 'lax-ca-us-ping'], ['Silicon Valley', 'sjo-ca-us-ping'], ['Seattle', 'wa-us-ping'], ['Dallas', 'tx-us-ping'],
  ['Chicago', 'il-us-ping'], ['New Jersey', 'nj-us-ping'], ['Atlanta', 'ga-us-ping'], ['Miami', 'fl-us-ping'],
  ['Frankfurt', 'fra-de-ping'], ['Amsterdam', 'ams-nl-ping'], ['London', 'lon-gb-ping'], ['Paris', 'par-fr-ping'],
  ['Tokyo', 'hnd-jp-ping'], ['Singapore', 'sgp-ping'], ['Sydney', 'syd-au-ping'],
];

final _rnd = Random();

class Server {
  final String name, kind;
  final int tier; // 0 — полноценный (загрузка + отдача), 1 — Cloudflare, 2 — только загрузка
  final Uri base;
  final String? dl, ul, ping;
  double? rtt;
  Server(this.name, String baseUrl, this.dl, this.ul, this.ping, this.kind, this.tier)
      : base = Uri.parse(baseUrl.endsWith('/') ? baseUrl : '$baseUrl/');

  String get key => '${base.host}${base.path}'.toLowerCase();

  Uri _u(String p, [String extra = '']) {
    final u = base.resolve(p);
    if (kind != 'librespeed') return u;
    return u.replace(query: '${u.hasQuery ? '${u.query}&' : ''}${extra}r=${_rnd.nextDouble()}');
  }

  Uri get dlUri => _u(dl!, 'ckSize=100&');
  Uri get ulUri => _u(ul!);
  Uri get pingUri => _u(ping!);
}

List<Server> loadServers(Store st) {
  final out = <String, Server>{};
  void add(Server s) => out.putIfAbsent(s.key, () => s);
  for (final e in st.librespeed) {
    try {
      add(Server((e['name'] ?? e['server']).toString(), e['server'].toString(), e['dlURL'].toString(), e['ulURL'].toString(),
          (e['pingURL'] ?? e['ulURL']).toString(), 'librespeed', 0));
    } catch (_) {}
  }
  for (final b in _builtin) {
    add(Server(b[0], b[1], b[2], b[3], b[4], 'librespeed', 0));
  }
  add(Server('Cloudflare (ближайший узел)', 'https://speed.cloudflare.com/', '__down?bytes=50000000', '__up', '__down?bytes=0', 'cloudflare', 1));
  for (final v in _vultr) {
    add(Server('${v[0]} (Vultr)', 'https://${v[1]}.vultr.com/', 'vultr.com.1000MB.bin', null, '/', 'static', 2));
  }
  return out.values.toList();
}

/// Свежий список LibreSpeed — фоном после замера, пригодится со следующего запуска.
Future<void> refreshServerList(Store st) async {
  final c = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final rq = await c.getUrl(Uri.parse(librespeedList));
    rq.headers.set('User-Agent', ua);
    final rs = await rq.close().timeout(const Duration(seconds: 10));
    if (rs.statusCode != 200) return;
    final j = jsonDecode(await rs.transform(utf8.decoder).join());
    if (j is List) {
      final lst = j.whereType<Map>().where((e) => e['server'] != null && e['dlURL'] != null && e['ulURL'] != null).map((e) => Map<String, dynamic>.from(e)).toList();
      if (lst.isNotEmpty) st.librespeed = lst;
    }
  } catch (_) {
  } finally {
    c.close(force: true);
  }
}

class StepError implements Exception {
  final String step, message;
  StepError(this.step, this.message);
  @override
  String toString() => '$step: $message';
}

/// RTT до сервера, мс (лучший из 2 запросов после TLS-разогрева) или null.
Future<double?> probe(Server s, Duration timeout, bool Function() stopped) async {
  final c = HttpClient()
    ..connectionTimeout = timeout
    ..idleTimeout = const Duration(seconds: 5);
  try {
    double? best;
    for (var i = 0; i < 3; i++) {
      if (stopped()) break;
      final sw = Stopwatch()..start();
      final rq = await c.getUrl(s.pingUri).timeout(timeout);
      rq.headers.set('User-Agent', ua);
      final rs = await rq.close().timeout(timeout);
      await rs.drain<void>().timeout(timeout);
      if (rs.statusCode != 200) return null;
      if (i > 0) {
        final dt = sw.elapsedMicroseconds / 1000;
        best = best == null ? dt : min(best, dt);
      }
    }
    return best;
  } catch (_) {
    return null;
  } finally {
    c.close(force: true);
  }
}

typedef SearchCb = void Function(int checked, int total, String best, double rtt);

class Engine {
  final Store st;
  final void Function(String phase) onPhase;
  final void Function(double mbps) onLive;
  final void Function(String key, double v) onResult;
  final void Function(String name, double rtt) onServer;
  final SearchCb onSearch;
  Engine(this.st, {required this.onPhase, required this.onLive, required this.onResult, required this.onServer, required this.onSearch});

  bool _stop = false;
  bool get stopped => _stop;
  final _clients = <HttpClient>{};
  final errors = <String>[];

  void stop() {
    _stop = true;
    for (final c in _clients.toList()) {
      c.close(force: true);
    }
  }

  // ---------------------------------------------------------------- выбор сервера
  /// Пингует все серверы параллельно и выходит рано: ближние отвечают за доли секунды.
  /// Если не ответил никто (так бывает при первом запуске на некоторых Windows — первое TLS-соединение
  /// долго проверяет сертификаты), ищем второй раз с бо́льшим запасом времени.
  Future<(List<Server>, List<Server>)> rank(List<Server> servers, {required Duration timeout, required double limit}) async {
    final fav = st.best;
    final total = servers.length;
    var checked = 0;
    final alive = <Server>[];
    final sw = Stopwatch()..start();
    onSearch(0, total, '', 0);
    final done = Completer<void>();
    for (final s in servers) {
      s.rtt = null;
      probe(s, timeout, () => _stop).then((r) {
        checked++;
        s.rtt = r;
        if (r != null) alive.add(s);
        if (checked == total && !done.isCompleted) done.complete();
      });
    }
    while (!_stop && !done.isCompleted) {
      await Future.any([done.future, Future.delayed(const Duration(milliseconds: 100))]);
      final full = alive.where((s) => s.ul != null && s.tier == 0).toList();
      Server? best;
      if (full.isNotEmpty) {
        best = full.reduce((a, b) => a.rtt! <= b.rtt! ? a : b);
      } else if (alive.isNotEmpty) {
        best = (List.of(alive)..sort((a, b) => a.tier != b.tier ? a.tier - b.tier : a.rtt!.compareTo(b.rtt!))).first;
      }
      onSearch(checked, total, best?.name ?? '', best?.rtt ?? 0);
      final el = sw.elapsedMilliseconds / 1000;
      final favOk = full.any((s) => s.key == fav);
      if ((favOk && el >= searchFav) || (full.isNotEmpty && el >= searchMin) || el >= limit) break;
    }
    final ranked = List.of(alive)..sort((a, b) => a.tier != b.tier ? a.tier - b.tier : a.rtt!.compareTo(b.rtt!));
    final rest = servers.where((s) => s.rtt == null && !alive.contains(s)).toList()..sort((a, b) => a.tier - b.tier);
    return (ranked, rest);
  }

  // ---------------------------------------------------------------- фазы
  Future<void> run() async {
    onPhase('search');
    var (ranked, rest) = await rank(loadServers(st), timeout: const Duration(milliseconds: 2500), limit: searchMax);
    if (_stop) return;
    if (ranked.isEmpty) {
      onPhase('search2');
      (ranked, rest) = await rank(loadServers(st), timeout: const Duration(seconds: 7), limit: 9);
      if (_stop) return;
    }
    if (ranked.isEmpty) throw StepError('Поиск сервера', 'ни один сервер не ответил — проверьте подключение или брандмауэр');
    final full = [...ranked.where((s) => s.ul != null), ...rest.where((s) => s.ul != null)];
    final dlPool = [...ranked.where((s) => s.ul != null), ...ranked.where((s) => s.ul == null), ...rest];

    onPhase('ping');
    (double, double)? pj;
    for (final s in dlPool.take(5).toList()) {
      try {
        pj = await _measurePing(s);
        dlPool
          ..remove(s)
          ..insert(0, s);
        break;
      } catch (e) {
        errors.add('${s.name}: $e');
      }
      if (_stop) return;
    }
    if (pj == null) throw StepError('Пинг', 'серверы не отвечают');
    onServer(dlPool.first.name, dlPool.first.rtt ?? 0);
    onResult('ping', pj.$1);
    onResult('jitter', pj.$2);
    if (_stop) return;

    onPhase('down');
    final down = await _measure(dlPool, upload: false, step: 'Загрузка');
    onResult('down', down);
    if (_stop) return;

    if (full.isEmpty) throw StepError('Отдача', 'нет серверов для замера отдачи');
    final used = _pool[min(_idx, _pool.length - 1)];
    final ulPool = [if (used.ul != null) used, ...full.where((s) => s != used)];
    onPhase('up');
    final up = await _measure(ulPool, upload: true, step: 'Отдача');
    onResult('up', up);
    if (used.ul != null && !_stop) st.best = used.key; // в следующий раз начнём с него
  }

  Future<(double, double)> _measurePing(Server s) async {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    _clients.add(c);
    try {
      Future<void> one() async {
        final rq = await c.getUrl(s.pingUri).timeout(const Duration(seconds: 8));
        rq.headers.set('User-Agent', ua);
        final rs = await rq.close().timeout(const Duration(seconds: 8));
        await rs.drain<void>();
        if (rs.statusCode != 200) throw Exception('HTTP ${rs.statusCode}');
      }

      await one(); // прогрев TLS
      final rtts = <double>[];
      for (var i = 0; i < 12 && !_stop; i++) {
        final sw = Stopwatch()..start();
        await one();
        rtts.add(sw.elapsedMicroseconds / 1000);
      }
      if (rtts.isEmpty) return (s.rtt ?? 0.0, 0.0);
      var jit = 0.0;
      for (var i = 1; i < rtts.length; i++) {
        jit += (rtts[i] - rtts[i - 1]).abs();
      }
      if (rtts.length > 1) jit /= rtts.length - 1;
      final sorted = List.of(rtts)..sort();
      final med = sorted.length.isOdd ? sorted[sorted.length ~/ 2] : (sorted[sorted.length ~/ 2 - 1] + sorted[sorted.length ~/ 2]) / 2;
      return (med, jit);
    } finally {
      c.close(force: true);
      _clients.remove(c);
    }
  }

  // ---------------------------------------------------------------- загрузка / отдача
  List<Server> _pool = [];
  int _idx = 0, _epoch = 0, _counter = 0;
  Map<int, int> _fails = {};
  bool _done = false;
  static final Uint8List _payload = Uint8List.fromList(List.generate(65536, (_) => _rnd.nextInt(256)));

  Future<double> _measure(List<Server> pool, {required bool upload, required String step}) async {
    _pool = pool;
    _idx = 0;
    _epoch = 0;
    _fails = {};
    _counter = 0;
    _done = false;
    onServer(pool.first.name, pool.first.rtt ?? 0);
    final workers = [for (var i = 0; i < streams; i++) _streamLoop(upload)];
    var alive = streams;
    for (final w in workers) {
      w.whenComplete(() => alive--);
    }

    final start = DateTime.now();
    var t0 = start;
    var base = 0, epoch = 0;
    int? warmB;
    DateTime? warmT;
    var b = 0;
    var now = start;
    double secs(DateTime a, DateTime b) => b.difference(a).inMicroseconds / 1e6;
    double avg(int got, int? wb) {
      if (wb != null && warmT != null && secs(warmT!, now) >= 0.5) return (got - wb) * 8 / secs(warmT!, now) / 1e6;
      return got * 8 / max(secs(t0, now), 1e-6) / 1e6;
    }

    while (true) {
      await Future.delayed(const Duration(milliseconds: 100));
      now = DateTime.now();
      b = _counter;
      if (_epoch != epoch) {
        // сменили сервер — считаем заново с этого момента
        epoch = _epoch;
        base = b;
        t0 = now;
        warmB = null;
        warmT = null;
      }
      if (warmB == null && secs(t0, now) >= warmup) {
        warmB = b;
        warmT = now;
      }
      onLive(avg(b - base, warmB == null ? null : warmB! - base));
      if (secs(t0, now) >= duration || secs(start, now) >= maxPhase || _stop || alive == 0) break;
    }
    _done = true;
    for (final c in _clients.toList()) {
      c.close(force: true);
    }
    await Future.wait(workers.map((w) => w.catchError((_) {}))).timeout(const Duration(seconds: 3), onTimeout: () => []);
    final got = b - base;
    if (got < 100000 && !_stop) {
      throw StepError(step, errors.isNotEmpty ? errors.last : 'сервер не отдал данные');
    }
    return avg(got, warmB == null ? null : warmB! - base);
  }

  void _fail(int idx, String why, {required bool hard}) {
    errors.add(why);
    if (_idx != idx) return;
    _fails[idx] = (_fails[idx] ?? 0) + 1;
    if (hard || _fails[idx]! >= maxFails) {
      _idx++;
      _epoch++;
      if (_idx < _pool.length) onServer(_pool[_idx].name, _pool[_idx].rtt ?? 0);
    }
  }

  Future<void> _streamLoop(bool upload) async {
    while (!_done && !_stop) {
      final idx = _idx;
      if (idx >= _pool.length) {
        errors.add('все серверы недоступны');
        return;
      }
      final s = _pool[idx];
      final c = HttpClient()
        ..connectionTimeout = const Duration(seconds: 15)
        ..autoUncompress = false;
      _clients.add(c);
      try {
        while (!_done && !_stop && _idx == idx) {
          final err = upload ? await _ulOnce(c, s) : await _dlOnce(c, s);
          if (err != null) {
            _fail(idx, '${s.name}: $err', hard: true);
            break;
          }
        }
      } catch (e) {
        if (_done || _stop) return;
        _fail(idx, '${s.name}: ${e is SocketException ? e.message : e}', hard: false);
        await Future.delayed(const Duration(milliseconds: 300));
      } finally {
        c.close(force: true);
        _clients.remove(c);
      }
    }
  }

  Future<String?> _dlOnce(HttpClient c, Server s) async {
    final rq = await c.getUrl(s.dlUri).timeout(const Duration(seconds: 15));
    rq.headers
      ..set('User-Agent', ua)
      ..set('Accept-Encoding', 'identity');
    final rs = await rq.close().timeout(const Duration(seconds: 15));
    if (rs.statusCode != 200) {
      await rs.drain<void>().catchError((_) {});
      return 'HTTP ${rs.statusCode}';
    }
    var got = 0;
    await for (final chunk in rs) {
      if (_done || _stop) break;
      got += chunk.length;
      _counter += chunk.length;
    }
    if (got == 0 && !_done && !_stop) return 'пустой ответ';
    return null;
  }

  Future<String?> _ulOnce(HttpClient c, Server s) async {
    final rq = await c.postUrl(s.ulUri).timeout(const Duration(seconds: 15));
    rq.headers
      ..set('User-Agent', ua)
      ..set('Content-Type', 'application/octet-stream');
    rq.contentLength = ulChunk;
    Stream<List<int>> body() async* {
      var sent = 0;
      while (sent < ulChunk) {
        if (_done || _stop) return;
        final n = min(_payload.length, ulChunk - sent);
        yield n == _payload.length ? _payload : Uint8List.sublistView(_payload, 0, n);
        sent += n;
        _counter += n;
      }
    }

    await rq.addStream(body());
    if (_done || _stop) return null;
    final rs = await rq.close().timeout(const Duration(seconds: 20));
    await rs.drain<void>().catchError((_) {});
    if (rs.statusCode != 200 && rs.statusCode != 204) return 'HTTP ${rs.statusCode}';
    return null;
  }
}

String fmtSpeed(double v) => v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
