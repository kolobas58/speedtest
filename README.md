# Speedtest by kolobas58

Минималистичный замер скорости интернета — **Windows · Linux · Android**. Все версии обновляются сами.

- **[Speedtest-Portable.exe](../../releases/latest/download/Speedtest-Portable.exe)** — Windows без установки: скачал → запустил.
- **[Speedtest-Setup.exe](../../releases/latest/download/Speedtest-Setup.exe)** — Windows, тихая установка без прав администратора (ярлыки, «Программы и компоненты»).
- **[Speedtest-Linux-x64.tar.gz](../../releases/latest/download/Speedtest-Linux-x64.tar.gz)** — распаковать, запустить `speedtest/speedtest`.
- **[Speedtest-Android.apk](../../releases/latest/download/Speedtest-Android.apk)** — Android 5+.

## Как это работает
- 14 тем — 7 стихий (Огонь, Земля, Свет, Ветер, Вода, Тьма, Радуга) в тёмном и светлом варианте; кнопка ◐ в заголовке.
- Параллельно пингует ~40 серверов (LibreSpeed, Cloudflare, Vultr) и за ~0.7 с выбирает ближайший живой;
  при сбое сервера на лету переключается на следующий. Если первый замер сорвался — повторяет сам.
- Скачивание и отдача в 4 потока по 10 с, показывается средняя скорость (без скачков).
- После замера тихо проверяет обновления. Ставится только то, что подписано ключом разработчика (Ed25519):
  `latest.json` (Windows), `latest-linux.json`, `latest-android.json`.

## Устройство
- `app/` — Flutter 3.24 (Windows 10/11, Linux, Android). Платформенные папки генерирует `app/tool/prepare.sh`.
- `src/speedtest.pyw` — прежняя версия на Python/Qt5: её кладём внутрь Windows-сборки для Windows 7/8, где Flutter не работает.
  Стартер `build/portable.nsi` сам выбирает, что запустить.
- `.github/workflows/build.yml` — сборка, снимки экрана и проверка обновления на каждый push; выпуск — push в `main`
  с новой версией в `app/pubspec.yaml`.

Секреты: `UPDATE_SIGNING_KEY` — приватный ключ подписи обновлений (hex), `ANDROID_KEYSTORE_B64` — ключ подписи APK.
Хранить у себя: без них выпускать обновления нельзя.
