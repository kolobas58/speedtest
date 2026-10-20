// Что Speedtest помнит между запусками: тема, лучший сервер прошлого замера, кэш списка LibreSpeed.
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class Store {
  final SharedPreferences p;
  Store(this.p);
  static Future<Store> open() async => Store(await SharedPreferences.getInstance());

  String? get theme => p.getString('theme');
  set theme(String? v) => v == null ? p.remove('theme') : p.setString('theme', v);

  String? get best => p.getString('best');
  set best(String? v) => v == null ? p.remove('best') : p.setString('best', v);

  List<Map<String, dynamic>> get librespeed {
    try {
      final s = p.getString('librespeed');
      if (s == null) return const [];
      return (jsonDecode(s) as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) {
      return const [];
    }
  }

  set librespeed(List<Map<String, dynamic>> v) => p.setString('librespeed', jsonEncode(v));
}
