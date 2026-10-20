import 'package:flutter_test/flutter_test.dart';
import 'package:speedtest/engine.dart';
import 'package:speedtest/themes.dart';
import 'package:speedtest/updater.dart';

void main() {
  test('формат скорости как в 1.x', () {
    expect(fmtSpeed(30.14), '30.1');
    expect(fmtSpeed(512.6), '513');
  });
  test('версии', () {
    expect(newer('2.0.1', '2.0.0'), isTrue);
    expect(newer('v1.3.0', '2.0.0'), isFalse);
  });
  test('14 тем', () {
    expect(themes.length, 14);
    expect(themeOf('nope').key, 'wind');
    expect(themeOf('fire').accent2, rainbow[1]);
  });
}
