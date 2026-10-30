# Speedtest by kolobas58

Минималистичный замер скорости интернета: открыл — и через пару секунд уже идёт замер. Пинг, скачивание, отдача — без рекламы и лишних сайтов.

**Windows · Linux · Android** — скачать в [Releases](../../releases/latest). Установка не нужна, все версии обновляются сами.

- **Windows** — [Speedtest-Windows-x64.exe](../../releases/latest/download/Speedtest-Windows-x64.exe): скачал → запустил;
- **Linux** — [Speedtest-Linux-x64.tar.gz](../../releases/latest/download/Speedtest-Linux-x64.tar.gz): распаковать, запустить `speedtest/speedtest`;
- **Android** — [Speedtest-Android.apk](../../releases/latest/download/Speedtest-Android.apk): Android 5+.

## Как это работает
- за ~0,7 с пингует ~40 серверов (LibreSpeed, Cloudflare, Vultr) и берёт ближайший живой; сервер отказал — на лету переходит на следующий, сорвался первый замер — повторяет сам;
- скачивание и отдача в 4 потока по 10 с, стрелка показывает среднюю скорость, без скачков;
- 14 тем — 7 стихий (Огонь, Земля, Свет, Ветер, Вода, Тьма, Радуга) в тёмном и светлом варианте, кнопка ◐ в заголовке; тема запоминается;
- на Windows и Linux — окно без системной рамки, своя полоска заголовка;
- обновления ставятся тихо и только подписанные ключом разработчика (Ed25519).

Сборка: GitHub Actions (`.github/workflows/build.yml`), Flutter 3.24 (`app/`). Платформенные папки генерирует `app/tool/prepare.sh`.
Выпуск — push в `main` с новой версией в `app/pubspec.yaml`. На Windows 7/8, где Flutter не работает, `Speedtest-Windows-x64.exe`
сам запускает прежнюю версию на Python/Qt5 (`src/speedtest.pyw`).

Секреты: `UPDATE_SIGNING_KEY` — ключ подписи обновлений, `ANDROID_KEYSTORE_B64` — ключ подписи APK. Хранить у себя: без них выпускать обновления нельзя.
