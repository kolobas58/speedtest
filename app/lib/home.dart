// Экран Speedtest — как в 1.x: заголовок, шкала, этап и сервер, пинг/джиттер, кнопка.
// Палитра тем открывается ПОД заголовком и сдвигает шкалу вниз (не перекрывает замер),
// закрывается кликом в любом месте, по Esc, при сворачивании и уходе из окна, после выбора темы.
import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'engine.dart';
import 'gauge.dart';
import 'store.dart';
import 'themes.dart';
import 'updater.dart';

class Home extends StatefulWidget {
  final Store store;
  final Updater updater;
  final bool desktop;
  final String? updatedNote; // «обновлено до X» — показываем после обновления
  const Home({super.key, required this.store, required this.updater, required this.desktop, this.updatedNote});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with WindowListener, WidgetsBindingObserver {
  late StTheme t = themeOf(widget.store.theme);
  final g = GaugeData();
  Engine? eng;
  bool running = false, stopping = false, paletteOpen = false;
  String phase = 'Нажмите «Старт»';
  String server = ' ';
  String ping = '—', jitter = '—';
  final res = <String, double>{};
  bool _firstRun = true;
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    if (widget.desktop) windowManager.addListener(this);
    WidgetsBinding.instance.addObserver(this);
    widget.updater.addListener(_upd);
    Timer(const Duration(milliseconds: 350), start); // замер стартует сразу при открытии
  }

  @override
  void dispose() {
    if (widget.desktop) windowManager.removeListener(this);
    WidgetsBinding.instance.removeObserver(this);
    widget.updater.removeListener(_upd);
    _focus.dispose();
    super.dispose();
  }

  void _upd() {
    if (mounted) setState(() {});
  }

  // --- палитра закрывается, если окно свернули или ушли из него
  @override
  void onWindowBlur() => _closePalette();
  @override
  void onWindowMinimize() => _closePalette();
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s != AppLifecycleState.resumed) _closePalette();
  }

  @override
  void onWindowClose() async {
    eng?.stop();
    await widget.updater.applyOnExit();
    await windowManager.destroy();
  }

  void _closePalette() {
    if (paletteOpen && mounted) setState(() => paletteOpen = false);
  }

  void _setTheme(StTheme nt) {
    setState(() {
      t = nt;
      paletteOpen = false;
    });
    widget.store.theme = nt.key;
  }

  // ---------------------------------------------------------------- замер
  Future<void> start() async {
    if (running) {
      setState(() {
        stopping = true;
        phase = 'Остановка…';
      });
      eng?.stop();
      return;
    }
    res.clear();
    setState(() {
      running = true;
      stopping = false;
      ping = '—';
      jitter = '—';
      server = ' ';
      g
        ..mode = GaugeMode.idle
        ..target = 0
        ..label = '';
    });
    var attempt = 0;
    while (true) {
      attempt++;
      final e = eng = Engine(widget.store,
          onPhase: _onPhase, onLive: (v) => g.target = max(0, v), onResult: _onResult, onServer: _onServer, onSearch: _onSearch);
      String? error;
      try {
        await e.run();
      } catch (x) {
        error = x.toString();
      }
      if (!mounted) return;
      // Первый замер после запуска иногда срывается (на некоторых Windows первое соединение долго проверяет
      // сертификаты) — повторяем сами один раз, без нажатия кнопки.
      if (error != null && !e.stopped && _firstRun && attempt == 1 && !res.containsKey('down')) {
        setState(() {
          phase = 'Не вышло с первого раза — повторяю…';
          g.mode = GaugeMode.idle;
          g.target = 0;
        });
        await Future.delayed(const Duration(milliseconds: 1500));
        if (!mounted || stopping) break;
        continue;
      }
      _finish(e, error);
      break;
    }
    _firstRun = false;
  }

  void _finish(Engine e, String? error) {
    setState(() {
      running = false;
      stopping = false;
      if (error != null && !e.stopped) {
        phase = 'Ошибка — $error';
        g.mode = GaugeMode.idle;
        g.target = 0;
      } else if (res.containsKey('down')) {
        g
          ..mode = GaugeMode.results
          ..down = res['down']!
          ..up = res['up'] ?? 0;
        phase = e.stopped ? 'Остановлено' : 'Готово';
      } else {
        g
          ..mode = GaugeMode.idle
          ..target = 0;
        phase = 'Остановлено';
      }
    });
    // после замера: свежий список серверов и проверка обновлений
    unawaited(refreshServerList(widget.store));
    unawaited(widget.updater.check());
  }

  void _onPhase(String p) => setState(() {
        switch (p) {
          case 'search':
            phase = 'Ищу ближайший сервер…';
            g
              ..mode = GaugeMode.search
              ..checked = 0
              ..total = 0;
          case 'search2':
            phase = 'Серверы молчат — ищу ещё раз, подольше…';
            g.mode = GaugeMode.search;
          case 'ping':
            phase = 'Пинг…';
            g
              ..mode = GaugeMode.idle
              ..target = 0
              ..label = '';
          case 'down':
            phase = 'Загрузка…';
            g
              ..mode = GaugeMode.live
              ..label = '↓ Загрузка'
              ..upload = false;
          case 'up':
            phase = 'Отдача…';
            g
              ..mode = GaugeMode.live
              ..target = 0
              ..label = '↑ Отдача'
              ..upload = true;
        }
      });

  void _onResult(String k, double v) {
    res[k] = v;
    setState(() {
      if (k == 'ping') ping = v.toStringAsFixed(0);
      if (k == 'jitter') jitter = v.toStringAsFixed(1);
      if (k == 'down' || k == 'up') g.target = v;
    });
  }

  void _onServer(String name, double rtt) => setState(() => server = 'Сервер: $name${rtt > 0 ? ' · ${rtt.toStringAsFixed(0)} мс' : ''}');

  void _onSearch(int checked, int total, String best, double rtt) => setState(() {
        if (g.mode == GaugeMode.search) {
          g.checked = checked;
          g.total = total;
        }
        if (best.isNotEmpty) server = 'лучший пока: $best · ${rtt.toStringAsFixed(0)} мс';
      });

  // ---------------------------------------------------------------- экран
  TextStyle _st(double size, Color c, {FontWeight w = FontWeight.w400, double ls = 0}) =>
      TextStyle(fontSize: size, color: c, fontWeight: w, letterSpacing: ls, fontFamily: 'Segoe UI', fontFamilyFallback: const ['Roboto', 'Noto Sans', 'DejaVu Sans']);

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle((t.light ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light)
        .copyWith(statusBarColor: Colors.transparent, systemNavigationBarColor: t.bg));
    final body = Padding(
      padding: EdgeInsets.fromLTRB(18, widget.desktop ? 8 : 12, 12, 26),
      child: Column(children: [
        _titleBar(),
        AnimatedSize(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          child: paletteOpen ? Padding(padding: const EdgeInsets.only(top: 8), child: _palette()) : const SizedBox(width: double.infinity),
        ),
        Expanded(child: Gauge(data: g, t: t)),
        Text(phase, textAlign: TextAlign.center, style: _st(13, t.dim)),
        const SizedBox(height: 2),
        Text(server, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: _st(11, t.trackTxt)),
        const SizedBox(height: 14),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [_stat('ПИНГ, мс', ping), const SizedBox(width: 40), _stat('ДЖИТТЕР, мс', jitter)]),
        const SizedBox(height: 22),
        _button(),
        if (Platform.isAndroid) _androidUpdate(),
      ]),
    );
    final wrapped = KeyboardListener(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: (e) {
        if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) _closePalette();
      },
      // клик в любом месте окна закрывает палитру (сам клик при этом проходит дальше)
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (ev) {
          if (paletteOpen && !_inPalette(ev.position)) _closePalette();
        },
        child: body,
      ),
    );
    return Scaffold(
      backgroundColor: t.bg,
      body: widget.desktop
          ? DecoratedBox(
              decoration: BoxDecoration(color: t.bg, border: Border.all(color: t.border)),
              child: GestureDetector(behavior: HitTestBehavior.translucent, onPanStart: (_) => windowManager.startDragging(), child: wrapped),
            )
          : SafeArea(child: wrapped),
    );
  }

  final _paletteKey = GlobalKey();
  final _themeBtnKey = GlobalKey();
  bool _inPalette(Offset p) {
    for (final k in [_paletteKey, _themeBtnKey]) {
      final box = k.currentContext?.findRenderObject() as RenderBox?;
      if (box != null && (box.localToGlobal(Offset.zero) & box.size).contains(p)) return true;
    }
    return false;
  }

  Widget _titleBar() {
    final u = widget.updater;
    String? note = widget.updatedNote;
    if (u.state == UpState.done && u.newVersion != null) note = Platform.isLinux ? '${u.newVersion} — при следующем запуске' : 'обновлено до ${u.newVersion}';
    if (u.state == UpState.ready && u.newVersion != null) note = '${u.newVersion} — установится при закрытии';
    return SizedBox(
      height: 34,
      child: Row(children: [
        Expanded(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: 'Speedtest ', style: _st(12, t.dim, ls: 1)),
              TextSpan(text: 'by kolobas58 · v$version', style: _st(12, t.trackTxt, ls: 1)),
              if (note != null) TextSpan(text: ' · $note', style: _st(12, const Color(0xFF3FB27F), ls: .5)),
            ]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        _TitleButton(key: _themeBtnKey, icon: Icons.contrast, tip: 'Тема оформления', t: t, onTap: () => setState(() => paletteOpen = !paletteOpen)),
        if (widget.desktop) ...[
          _TitleButton(icon: Icons.remove, tip: 'Свернуть', t: t, onTap: () => windowManager.minimize()),
          _TitleButton(icon: Icons.close, tip: 'Закрыть', t: t, danger: true, onTap: () => windowManager.close()),
        ],
      ]),
    );
  }

  Widget _palette() {
    return Container(
      key: _paletteKey,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: t.track, borderRadius: BorderRadius.circular(18), border: Border.all(color: t.border)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        for (final row in [darkThemes, lightThemes])
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [for (final th in row) _Swatch(th: th, current: t, onPick: _setTheme)]),
      ]),
    );
  }

  Widget _stat(String title, String v) => Column(children: [
        Text(title, style: _st(12, t.dim, ls: 1)),
        const SizedBox(height: 2),
        Text(v, style: _st(20, t.fg)),
      ]);

  Widget _button() {
    final label = running ? 'СТОП' : (res.isEmpty && phase == 'Нажмите «Старт»' ? 'СТАРТ' : 'ЕЩЁ РАЗ');
    final disabled = stopping;
    return _StartButton(label: label, t: t, disabled: disabled, onTap: start);
  }

  Widget _androidUpdate() {
    final u = widget.updater;
    if (u.newVersion == null || u.state == UpState.done) return const SizedBox.shrink();
    final dl = u.state == UpState.downloading;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: TextButton.icon(
        onPressed: dl ? null : u.installAndroid,
        icon: Icon(Icons.system_update_alt, size: 18, color: t.accent),
        label: Text(
            dl ? 'Скачиваю ${u.newVersion}… ${(u.progress * 100).round()}%' : (u.state == UpState.failed ? 'Не вышло — повторить ${u.newVersion}' : 'Обновить до ${u.newVersion}'),
            style: _st(13, t.accent, w: FontWeight.w600)),
      ),
    );
  }
}

class _TitleButton extends StatefulWidget {
  final IconData icon;
  final String tip;
  final StTheme t;
  final bool danger;
  final VoidCallback onTap;
  const _TitleButton({super.key, required this.icon, required this.tip, required this.t, required this.onTap, this.danger = false});
  @override
  State<_TitleButton> createState() => _TitleButtonState();
}

class _TitleButtonState extends State<_TitleButton> {
  bool hover = false;
  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return Tooltip(
      message: widget.tip,
      waitDuration: const Duration(milliseconds: 700),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => hover = true),
        onExit: (_) => setState(() => hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: Platform.isAndroid ? 40 : 30,
            height: Platform.isAndroid ? 36 : 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: hover ? (widget.danger ? const Color(0xFFD9434F) : t.track) : Colors.transparent, borderRadius: BorderRadius.circular(6)),
            child: Icon(widget.icon, size: Platform.isAndroid ? 20 : 15, color: hover ? (widget.danger ? Colors.white : t.fg) : t.dim),
          ),
        ),
      ),
    );
  }
}

class _Swatch extends StatefulWidget {
  final StTheme th, current;
  final void Function(StTheme) onPick;
  const _Swatch({required this.th, required this.current, required this.onPick});
  @override
  State<_Swatch> createState() => _SwatchState();
}

class _SwatchState extends State<_Swatch> {
  bool hover = false;
  @override
  Widget build(BuildContext context) {
    final s = Platform.isAndroid ? 38.0 : 30.0;
    return Tooltip(
      message: widget.th.name,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => hover = true),
        onExit: (_) => setState(() => hover = false),
        child: GestureDetector(
          onTap: () => widget.onPick(widget.th),
          child: Padding(
            padding: const EdgeInsets.all(1),
            child: CustomPaint(size: Size(s, s), painter: _SwatchPainter(widget.th, widget.current, hover)),
          ),
        ),
      ),
    );
  }
}

class _SwatchPainter extends CustomPainter {
  final StTheme th, cur;
  final bool hover;
  _SwatchPainter(this.th, this.cur, this.hover);
  @override
  void paint(Canvas c, Size sz) {
    final r = Rect.fromLTWH(4, 4, sz.width - 8, sz.height - 8);
    c.drawOval(r, Paint()..color = th.bg);
    c.drawOval(r, Paint()
      ..style = PaintingStyle.stroke
      ..color = th.border);
    final inner = r.deflate(4);
    if (th.gradient) {
      c.drawOval(inner, Paint()..shader = SweepGradient(colors: [...rainbow, rainbow.first], transform: const GradientRotation(-pi / 2)).createShader(inner));
    } else {
      c.drawArc(inner, pi / 2, pi, true, Paint()..color = th.accent);
      c.drawArc(inner, -pi / 2, pi, true, Paint()..color = th.accent2);
    }
    if (th.key == cur.key || hover) {
      c.drawOval(Rect.fromLTWH(1, 1, sz.width - 2, sz.height - 2), Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = th.key == cur.key ? cur.fg : cur.dim);
    }
  }

  @override
  bool shouldRepaint(covariant _SwatchPainter o) => o.th != th || o.cur != cur || o.hover != hover;
}

class _StartButton extends StatefulWidget {
  final String label;
  final StTheme t;
  final bool disabled;
  final VoidCallback onTap;
  const _StartButton({required this.label, required this.t, required this.disabled, required this.onTap});
  @override
  State<_StartButton> createState() => _StartButtonState();
}

class _StartButtonState extends State<_StartButton> {
  bool hover = false;
  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final bg = widget.disabled ? t.track : (hover ? t.accentHi : t.accent);
    return MouseRegion(
      cursor: widget.disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() => hover = false),
      child: GestureDetector(
        onTap: widget.disabled ? null : widget.onTap,
        child: Container(
          width: 160,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: t.gradient && !widget.disabled ? null : bg,
            gradient: t.gradient && !widget.disabled
                ? LinearGradient(colors: [for (final c in rainbow) hover ? mix(c, Colors.white, .18) : c])
                : null,
            borderRadius: BorderRadius.circular(23),
          ),
          child: Text(widget.label,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2,
                  color: widget.disabled ? t.dim : t.btnTxt,
                  fontFamily: 'Segoe UI',
                  fontFamilyFallback: const ['Roboto', 'Noto Sans', 'DejaVu Sans'])),
        ),
      ),
    );
  }
}
