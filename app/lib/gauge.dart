// Шкала как в 1.x: дуга 270° (снизу слева → снизу справа), логарифмическая до 1000 Мбит/с, плавная стрелка.
// Режимы: поиск сервера (бегущий сегмент), идёт замер (одна дуга), итоги (две дуги: снаружи загрузка, внутри отдача).
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'engine.dart';
import 'themes.dart';

enum GaugeMode { idle, search, live, results }

class GaugeData {
  GaugeMode mode = GaugeMode.idle;
  String label = '';
  bool upload = false; // цвет дуги: загрузка — accent, отдача — accent2
  int checked = 0, total = 0;
  double target = 0, down = 0, up = 0;
}

class Gauge extends StatefulWidget {
  final GaugeData data;
  final StTheme t;
  const Gauge({super.key, required this.data, required this.t});
  @override
  State<Gauge> createState() => _GaugeState();
}

class _GaugeState extends State<Gauge> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double shown = 0, spin = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      final d = widget.data;
      if (d.mode == GaugeMode.search) {
        setState(() => spin = (spin + 4) % 270);
        return;
      }
      if (d.mode == GaugeMode.idle && shown == 0 && d.target == 0) return;
      final diff = d.target - shown;
      if (diff.abs() < 0.01) {
        if (shown != d.target) setState(() => shown = d.target);
        return;
      }
      setState(() => shown += diff * 0.08);
    })
      ..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.data.mode == GaugeMode.idle && widget.data.target == 0) shown = 0;
    return CustomPaint(painter: _Painter(widget.data, widget.t, shown, spin), size: Size.infinite);
  }
}

double _frac(double v) => min(1.0, log(1 + max(v, 0)) / log(1 + gaugeMax));

class _Painter extends CustomPainter {
  final GaugeData d;
  final StTheme t;
  final double shown, spin;
  _Painter(this.d, this.t, this.shown, this.spin);

  static const _start = 3 * pi / 4; // 135° — снизу слева
  static const _full = 3 * pi / 2; // 270°

  Paint _pen(double w, Color c, Rect r) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..color = c;
    if (t.gradient && c != t.track) {
      // тема «Радуга»: красный в начале шкалы → фиолетовый в конце
      p.shader = SweepGradient(
        startAngle: 0,
        endAngle: _full,
        colors: rainbow,
        transform: const GradientRotation(_start),
      ).createShader(r);
    }
    return p;
  }

  void _text(Canvas c, String s, Offset center, double size, Color color, {FontWeight w = FontWeight.w400, double ls = 0}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(fontSize: size, color: color, fontWeight: w, letterSpacing: ls, fontFamily: 'Segoe UI', fontFamilyFallback: const ['Roboto', 'Noto Sans', 'DejaVu Sans'])),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();
    tp.paint(c, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final side = min(size.width, size.height) - 30;
    if (side <= 40) return;
    final k = side / 330; // размеры шрифтов — от размера шкалы (в 1.x шкала ~330 px)
    final rect = Rect.fromCenter(center: size.center(Offset.zero), width: side, height: side);
    final cx = rect.center.dx, cy = rect.center.dy;
    canvas.drawArc(rect, _start, _full, false, _pen(14 * k.clamp(.7, 1.4), t.track, rect));
    final w = 14 * k.clamp(.7, 1.4);

    switch (d.mode) {
      case GaugeMode.results:
        for (final (v, col, inset) in [(d.down, t.accent, 0.0), (d.up, t.accent2, 22.0 * k)]) {
          final r = rect.deflate(inset);
          final ww = inset > 0 ? w * 8 / 14 : w;
          if (inset > 0) canvas.drawArc(r, _start, _full, false, _pen(ww, t.track, r));
          final f = _frac(v);
          if (f > 0.002) canvas.drawArc(r, _start, _full * f, false, _pen(ww, col, r));
        }
        final colw = side * .32;
        for (var i = 0; i < 2; i++) {
          final x = i == 0 ? cx - colw / 2 - 8 : cx + colw / 2 + 8;
          _text(canvas, i == 0 ? '↓ ЗАГРУЗКА' : '↑ ОТДАЧА', Offset(x, cy - 39 * k), 13 * k, i == 0 ? t.txt1 : t.txt2, w: FontWeight.w600);
          _text(canvas, fmtSpeed(i == 0 ? d.down : d.up), Offset(x, cy - 3 * k), 40 * k, t.fg, w: FontWeight.w300);
        }
        _text(canvas, 'Мбит/с', Offset(cx, cy + 40 * k), 16 * k, t.dim);
        return;
      case GaugeMode.search:
        const seg = 60.0;
        final st = _start + min(spin, 270 - seg) * pi / 180;
        canvas.drawArc(rect, st, seg * pi / 180, false, _pen(w, t.accent, rect));
        _text(canvas, 'ПОИСК СЕРВЕРА', Offset(cx, cy - 95 * k), 14.5 * k, t.dim, ls: 1);
        _text(canvas, '${d.checked} / ${d.total}', Offset(cx, cy - 10 * k), 53 * k, t.fg, w: FontWeight.w300);
        _text(canvas, 'серверов проверено', Offset(cx, cy + 55 * k), 16 * k, t.dim);
        return;
      case GaugeMode.idle:
      case GaugeMode.live:
        final f = _frac(shown);
        if (f > 0.002) canvas.drawArc(rect, _start, _full * f, false, _pen(w, d.upload ? t.accent2 : t.accent, rect));
        _text(canvas, d.label.toUpperCase(), Offset(cx, cy - 95 * k), 14.5 * k, t.dim, ls: 1);
        _text(canvas, fmtSpeed(shown), Offset(cx, cy - 10 * k), 58 * k, t.fg, w: FontWeight.w300);
        _text(canvas, 'Мбит/с', Offset(cx, cy + 55 * k), 16 * k, t.dim);
    }
  }

  @override
  bool shouldRepaint(covariant _Painter o) => true;
}
