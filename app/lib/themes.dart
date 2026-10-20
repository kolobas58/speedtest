// 14 тем — 7 стихий (как в 1.x): тёмный и светлый вариант. Загрузка — цвет темы, отдача — соседний цвет радуги.
import 'package:flutter/painting.dart';

const rainbow = [Color(0xFFFF2E2E), Color(0xFFFF7A1A), Color(0xFFFFE619), Color(0xFF22C55E), Color(0xFF2F7BF6), Color(0xFF9D4EDD)];

class StTheme {
  final String key, name;
  final bool light, gradient;
  final Color bg, border, track, fg, dim, trackTxt, accent, accent2, btnTxt, txt1, txt2;
  const StTheme({
    required this.key,
    required this.name,
    required this.light,
    required this.gradient,
    required this.bg,
    required this.border,
    required this.track,
    required this.fg,
    required this.dim,
    required this.trackTxt,
    required this.accent,
    required this.accent2,
    required this.btnTxt,
    required this.txt1,
    required this.txt2,
  });

  Color get accentHi => mix(accent, const Color(0xFFFFFFFF), .18);
}

Color _c(String h) => Color(int.parse('FF${h.substring(1)}', radix: 16));

Color mix(Color a, Color b, double t) => Color.fromARGB(
      255,
      (a.red + (b.red - a.red) * t).round(),
      (a.green + (b.green - a.green) * t).round(),
      (a.blue + (b.blue - a.blue) * t).round(),
    );

Color _btnTxt(Color c) => (0.299 * c.red + 0.587 * c.green + 0.114 * c.blue) > 150 ? const Color(0xFF111114) : const Color(0xFFFFFFFF);

// ключ, название, раса, основной цвет, (тёмная: BG, BORDER, TRACK, FG, DIM, TRACK_TXT), (светлая: …)
const _palette = [
  ['fire', 'Огонь', 'Люди', '#FF2E2E', ['#140d0d', '#2a1a1a', '#2c1d1d', '#f2e8e8', '#9a8484', '#5e4a4a'], ['#fbf4f4', '#efd9d9', '#f2e1e1', '#2a1414', '#8a6c6c', '#bba0a0']],
  ['earth', 'Земля', 'Орки', '#FF7A1A', ['#14100c', '#2a2018', '#2d231b', '#f2ebe4', '#9a8a7c', '#5e5043'], ['#fbf6f1', '#eee0d2', '#f1e6db', '#2a1d12', '#8a7462', '#bba693']],
  ['light', 'Свет', 'Гномы', '#FFE619', ['#13120b', '#29271a', '#2b291c', '#f3f1e3', '#9a9680', '#5d5a45'], ['#fbfaf0', '#ece8cf', '#f0edd9', '#26230f', '#807b5c', '#b2ad8c']],
  ['wind', 'Ветер', 'Тёмные эльфы', '#22C55E', ['#0c1410', '#1a2720', '#1d2b24', '#e5f0ea', '#7b9086', '#485b51'], ['#f2f8f4', '#d6e7dd', '#deece4', '#12221a', '#5f7a6c', '#9ab0a4']],
  ['water', 'Вода', 'Светлые эльфы', '#2F7BF6', ['#0c0f16', '#1a2030', '#1d2435', '#e6ebf4', '#7c8599', '#49516a'], ['#f3f6fc', '#d9e1f0', '#e1e8f4', '#141c2c', '#64708a', '#a0aac0']],
  ['dark', 'Тьма', 'Камаэли', '#9D4EDD', ['#110d17', '#241c32', '#271e37', '#eee8f6', '#8d82a2', '#574c6c'], ['#f7f3fc', '#e3d9f0', '#e9e1f4', '#1f1530', '#776a90', '#ada2c2']],
  ['rainbow', 'Радуга', 'все расы', '', ['#0f0f12', '#222228', '#26262d', '#ececf0', '#85858f', '#50505a'], ['#f6f6f8', '#e0e0e6', '#e7e7ec', '#1b1b22', '#6c6c78', '#a5a5b0']],
];

StTheme _make(List p, bool light) {
  final key = p[0] as String, name = p[1] as String, race = p[2] as String, main = p[3] as String;
  final b = (light ? p[5] : p[4]) as List;
  final grad = main.isEmpty;
  Color a1, a2;
  if (!grad) {
    a1 = _c(main);
    a2 = rainbow[(rainbow.indexOf(a1) + 1) % rainbow.length];
  } else {
    a1 = const Color(0xFF2F7BF6);
    a2 = const Color(0xFF9D4EDD);
  }
  final dark = const Color(0xFF000000);
  return StTheme(
    key: light ? '${key}_light' : key,
    name: '$name — $race${light ? ' · светлая' : ''}',
    light: light,
    gradient: grad,
    bg: _c(b[0]),
    border: _c(b[1]),
    track: _c(b[2]),
    fg: _c(b[3]),
    dim: _c(b[4]),
    trackTxt: _c(b[5]),
    accent: a1,
    accent2: a2,
    btnTxt: grad ? const Color(0xFF111114) : _btnTxt(a1),
    txt1: light ? mix(a1, dark, .28) : a1,
    txt2: light ? mix(a2, dark, .28) : a2,
  );
}

final List<StTheme> darkThemes = [for (final p in _palette) _make(p, false)];
final List<StTheme> lightThemes = [for (final p in _palette) _make(p, true)];
final Map<String, StTheme> themes = {for (final t in [...darkThemes, ...lightThemes]) t.key: t};
const defaultTheme = 'wind'; // зелёная, как на сайте

StTheme themeOf(String? key) => themes[key] ?? themes[defaultTheme]!;
