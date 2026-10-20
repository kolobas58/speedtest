#!/usr/bin/env bash
# Speedtest 2.x для Windows: Speedtest-Portable.exe и Speedtest-Setup.exe.
# Внутри два рантайма: Flutter-версия (Windows 10/11) и прежняя версия на Python/Qt5 (Windows 7/8 — Flutter там не работает).
# Стартер сам выбирает, что запустить. Обе версии обновляются одним и тем же подписанным latest.json.
# Запуск: build/package.sh <папка flutter build windows (Release)>   Нужны: python3+pip, nsis, unzip.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FL="$(cd "$1" && pwd)"
VER="$(sed -n 's/^version: *\([0-9.]*\).*/\1/p' "$ROOT/app/pubspec.yaml")"
[ -n "$VER" ] || { echo "version не найден в app/pubspec.yaml"; exit 1; }
[ -f "$FL/speedtest.exe" ] || { echo "нет $FL/speedtest.exe"; exit 1; }
W="$ROOT/.work"; OUT="$ROOT/dist"
rm -rf "$W"; mkdir -p "$W/dl" "$OUT"
echo ">> Speedtest $VER"

# --- прежняя версия для Windows 7/8: зависимости с закреплёнными хэшами ---
cat > "$W/req.txt" <<REQ
pyqt5==5.15.10 --hash=sha256:501355f327e9a2c38db0428e1a236d25ebcb99304cd6e668c05d1188d514adec
pyqt5-qt5==5.15.2 --hash=sha256:750b78e4dba6bdf1607febedc08738e318ea09e9b10aea9ff0d73073f11f6962
pyqt5-sip==12.15.0 --hash=sha256:f600ae6f03e4bff91153c0dc7ebe52f90bd2b6afda58fd580e6990b3b951adc0
REQ
python3 -m pip download -q --no-deps --require-hashes -r "$W/req.txt" -d "$W/dl" \
  --platform win_amd64 --python-version 38 --implementation cp --abi cp38 --abi abi3 --abi none --only-binary=:all:
python3 -m pip download -q --no-deps --no-build-isolation python-embed==3.8.0 --no-binary :all: -d "$W/dl"
echo "56e4b6dba01983735bbecc644ebad599dd70607e9c0dc51171c0664fffa55a08  $W/dl/python_embed-3.8.0.tar.gz" | sha256sum -c --quiet -

P="$W/payload"; L="$P/legacy"; mkdir -p "$L/lib" "$W/pe"
tar xzf "$W/dl/python_embed-3.8.0.tar.gz" -C "$W/pe"
unzip -q "$(find "$W/pe" -name data.zip)" -d "$W/pe/x"
cp -r "$(dirname "$(find "$W/pe/x" -name python38.dll)")" "$L/python"
rm -f "$L/python/"{_msi.pyd,_sqlite3.pyd,sqlite3.dll,winsound.pyd}
printf 'python38.zip\r\n.\r\n..\\lib\r\n' > "$L/python/python38._pth"
for w in "$W/dl/"*.whl; do unzip -q -o "$w" -d "$L/lib"; done
Q="$L/lib/PyQt5"
rm -rf "$L/lib/"PyQt5_* "$L/lib/"PyQt5-* "$Q/bindings" "$Q/uic" "$Q/Qt5/qml" "$Q/Qt5/qsci" "$Q/Qt5/translations"
find "$Q" -maxdepth 1 -type f ! -name '__init__.py' ! -name 'QtCore.pyd' ! -name 'QtGui.pyd' ! -name 'QtWidgets.pyd' ! -name 'sip*.pyd' -delete
find "$Q/Qt5/bin" -type f ! -regex '.*/\(Qt5Core\|Qt5Gui\|Qt5Widgets\|msvcp140\|msvcp140_1\|msvcp140_2\|vcruntime140\|vcruntime140_1\)\.dll' -delete
find "$Q/Qt5/plugins" -mindepth 1 -maxdepth 1 ! -name platforms ! -name styles ! -name imageformats -exec rm -rf {} +
find "$Q/Qt5/plugins/platforms" -type f ! -name qwindows.dll -delete
find "$Q/Qt5/plugins/imageformats" -type f ! -name qico.dll -delete
# прежняя версия считает себя текущей (иначе качала бы обновление при каждом запуске)
sed "s/^VERSION = \".*\"/VERSION = \"$VER\"/" "$ROOT/src/speedtest.pyw" > "$L/speedtest.pyw"
cp "$ROOT/src/speedtest.ico" "$L/"

# --- Flutter-версия ---
cp -r "$FL" "$P/app"

makensis -V2 -DVER="$VER" -DPAYLOAD="$P" -DOUT="$OUT/Speedtest-Portable.exe" -DICON="$ROOT/src/speedtest.ico" "$ROOT/build/portable.nsi"
echo ">> $OUT/Speedtest-Portable.exe ($(du -h "$OUT/Speedtest-Portable.exe" | cut -f1))"
makensis -V2 -DVER="$VER" -DEXE="$OUT/Speedtest-Portable.exe" -DOUT="$OUT/Speedtest-Setup.exe" -DICON="$ROOT/src/speedtest.ico" "$ROOT/build/installer.nsi"
echo ">> $OUT/Speedtest-Setup.exe ($(du -h "$OUT/Speedtest-Setup.exe" | cut -f1))"
