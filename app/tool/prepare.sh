#!/usr/bin/env bash
# Платформенная часть проекта (в репозитории её нет — генерирует Flutter) + название, размер окна, значки, разрешения.
# Запуск из папки app/: bash tool/prepare.sh android|linux|windows
set -euo pipefail
P="$1"
flutter create --org club.kolobas58 --project-name speedtest --platforms="$P" .
rm -f test/widget_test.dart   # шаблонный тест счётчика из flutter create
case "$P" in
  android)
    M=android/app/src/main/AndroidManifest.xml
    sed -i 's/android:label="speedtest"/android:label="Speedtest"/' "$M"
    grep -q 'android.permission.INTERNET' "$M" || sed -i '0,/<application/s//<uses-permission android:name="android.permission.INTERNET"\/>\n    <application/' "$M"
    # автообновление (ota_update): разрешение ставить APK и FileProvider для скачанного файла
    grep -q 'REQUEST_INSTALL_PACKAGES' "$M" || sed -i '0,/<application/s//<uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES"\/>\n    <application/' "$M"
    grep -q 'ota_update_provider' "$M" || sed -i 's#</application>#    <provider android:name="sk.fourq.otaupdate.OtaUpdateFileProvider" android:authorities="${applicationId}.ota_update_provider" android:exported="false" android:grantUriPermissions="true">\n            <meta-data android:name="android.support.FILE_PROVIDER_PATHS" android:resource="@xml/filepaths"/>\n        </provider>\n    </application>#' "$M"
    mkdir -p android/app/src/main/res/xml
    cat > android/app/src/main/res/xml/filepaths.xml <<'X'
<?xml version="1.0" encoding="utf-8"?>
<paths>
    <external-path name="external" path="."/>
    <external-files-path name="external_files" path="."/>
    <files-path name="files" path="."/>
    <cache-path name="cache" path="."/>
</paths>
X
    # старые плагины (ota_update) собираются с compileSdk 28 → «android:attr/lStar not found»; поднимаем всем библиотекам
    G=android/build.gradle
    if [ -f "$G" ] && ! grep -q 'compileSdkVersion 34 // libs' "$G"; then
      printf 'subprojects {\n    afterEvaluate { p ->\n        if (p.plugins.hasPlugin("com.android.library")) { p.android { compileSdkVersion 34 // libs\n } }\n    }\n}\n' | cat - "$G" > "$G.tmp" && mv "$G.tmp" "$G"
    fi
    ;;
  linux)
    F=linux/runner/my_application.cc
    [ -f "$F" ] || F=linux/my_application.cc
    sed -i 's/"speedtest")/"Speedtest by kolobas58")/g; s/gtk_window_set_default_size(window, 1280, 720)/gtk_window_set_default_size(window, 400, 540)/' "$F"
    ;;
  windows)
    F=windows/runner/main.cpp
    sed -i 's/L"speedtest"/L"Speedtest by kolobas58"/; s/Win32Window::Size size(1280, 720)/Win32Window::Size size(400, 540)/' "$F"
    R=windows/runner/Runner.rc
    sed -i 's/"FileDescription", "speedtest"/"FileDescription", "Speedtest by kolobas58"/; s/"ProductName", "speedtest"/"ProductName", "Speedtest by kolobas58"/; s/"CompanyName", "club.kolobas58"/"CompanyName", "kolobas58"/' "$R"
    ;;
esac
flutter pub get
if [ "$P" = android ]; then
  cat > .icons.yaml <<'Y'
flutter_launcher_icons:
  image_path: "assets/icon.png"
  android: true
  ios: false
  min_sdk_android: 21
  adaptive_icon_background: "#101115"
  adaptive_icon_foreground: "assets/icon_fg.png"
Y
  dart run flutter_launcher_icons -f .icons.yaml
elif [ "$P" = windows ]; then
  cat > .icons.yaml <<'Y'
flutter_launcher_icons:
  android: false
  ios: false
  windows:
    generate: true
    image_path: "assets/icon.png"
    icon_size: 256
Y
  dart run flutter_launcher_icons -f .icons.yaml
fi
echo "prepared $P"
