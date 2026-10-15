#!/usr/bin/env bash
# Сборка портативного Speedtest.exe (Windows 7 SP1 – 11, x64) на Linux.
# Нужны: python3 + pip, nsis (makensis), unzip.   Ubuntu: sudo apt install nsis unzip
# Результат: dist/Speedtest.exe   (+ dist/latest.json, если задан UPDATE_SIGNING_KEY)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VER="$(sed -n 's/^VERSION = "\(.*\)"/\1/p' "$ROOT/src/speedtest.pyw")"
[ -n "$VER" ] || { echo "VERSION не найден в src/speedtest.pyw"; exit 1; }
W="$ROOT/.work"; OUT="$ROOT/dist"
rm -rf "$W"; mkdir -p "$W/dl" "$OUT"
echo ">> Speedtest $VER"

# --- зависимости с закреплёнными хэшами (защита от подмены на PyPI) ---
cat > "$W/req.txt" <<REQ
pyqt5==5.15.10 --hash=sha256:501355f327e9a2c38db0428e1a236d25ebcb99304cd6e668c05d1188d514adec
pyqt5-qt5==5.15.2 --hash=sha256:750b78e4dba6bdf1607febedc08738e318ea09e9b10aea9ff0d73073f11f6962
pyqt5-sip==12.15.0 --hash=sha256:f600ae6f03e4bff91153c0dc7ebe52f90bd2b6afda58fd580e6990b3b951adc0
REQ
python3 -m pip download -q --no-deps --require-hashes -r "$W/req.txt" -d "$W/dl" \
  --platform win_amd64 --python-version 38 --implementation cp --abi cp38 --abi abi3 --abi none --only-binary=:all:
# официальный embeddable Python 3.8.10 (подписан PSF) — упакован на PyPI как python-embed
python3 -m pip download -q --no-deps --no-build-isolation python-embed==3.8.0 --no-binary :all: -d "$W/dl"
echo "56e4b6dba01983735bbecc644ebad599dd70607e9c0dc51171c0664fffa55a08  $W/dl/python_embed-3.8.0.tar.gz" | sha256sum -c --quiet -

# --- сборка рантайма ---
P="$W/payload"; mkdir -p "$P/lib" "$W/pe"
tar xzf "$W/dl/python_embed-3.8.0.tar.gz" -C "$W/pe"
unzip -q "$(find "$W/pe" -name data.zip)" -d "$W/pe/x"
cp -r "$(dirname "$(find "$W/pe/x" -name python38.dll)")" "$P/python"
rm -f "$P/python/"{_msi.pyd,_sqlite3.pyd,sqlite3.dll,winsound.pyd}
printf 'python38.zip\r\n.\r\n..\\lib\r\n' > "$P/python/python38._pth"
for w in "$W/dl/"*.whl; do unzip -q -o "$w" -d "$P/lib"; done

# --- вырезаем из Qt всё, кроме Core/Gui/Widgets (149 МБ -> ~31 МБ) ---
Q="$P/lib/PyQt5"
rm -rf "$P/lib/"PyQt5_* "$P/lib/"PyQt5-* "$Q/bindings" "$Q/uic" "$Q/Qt5/qml" "$Q/Qt5/qsci" "$Q/Qt5/translations"
find "$Q" -maxdepth 1 -type f ! -name '__init__.py' ! -name 'QtCore.pyd' ! -name 'QtGui.pyd' ! -name 'QtWidgets.pyd' ! -name 'sip*.pyd' -delete
find "$Q/Qt5/bin" -type f ! -regex '.*/\(Qt5Core\|Qt5Gui\|Qt5Widgets\|msvcp140\|msvcp140_1\|msvcp140_2\|vcruntime140\|vcruntime140_1\)\.dll' -delete
find "$Q/Qt5/plugins" -mindepth 1 -maxdepth 1 ! -name platforms ! -name styles ! -name imageformats -exec rm -rf {} +
find "$Q/Qt5/plugins/platforms" -type f ! -name qwindows.dll -delete
find "$Q/Qt5/plugins/imageformats" -type f ! -name qico.dll -delete

cp "$ROOT/src/speedtest.pyw" "$ROOT/src/speedtest.ico" "$P/"

# --- портативный exe ---
makensis -V2 -DVER="$VER" -DPAYLOAD="$P" -DOUT="$OUT/Speedtest.exe" -DICON="$ROOT/src/speedtest.ico" "$ROOT/build/portable.nsi"
echo ">> $OUT/Speedtest.exe ($(du -h "$OUT/Speedtest.exe" | cut -f1))"

# --- манифест обновления (только при наличии ключа) ---
if [ -n "${UPDATE_SIGNING_KEY:-}" ]; then
  python3 "$ROOT/tools/sign_release.py" "$OUT/Speedtest.exe" "$VER" > "$OUT/latest.json"
  echo ">> $OUT/latest.json подписан"
fi
