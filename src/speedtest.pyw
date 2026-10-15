"""Speedtest by kolobas58 — минималистичный замер скорости сети (PyQt5/6, пул серверов LibreSpeed/Cloudflare/Vultr)."""
import hashlib
import http.client
import json
import math
import os
import random
import ssl
import statistics
import sys
import threading
import time
import urllib.request
from concurrent.futures import FIRST_COMPLETED, ThreadPoolExecutor, wait
from urllib.parse import urljoin, urlsplit

# Скрыть консоль, если запущено через python.exe/py.exe
if sys.platform == "win32":
    try:
        import ctypes
        _h = ctypes.windll.kernel32.GetConsoleWindow()
        if _h:
            ctypes.windll.user32.ShowWindow(_h, 0)
    except Exception:  # noqa: BLE001
        pass

    try:  # своя иконка на панели задач, а не pythonw
        ctypes.windll.shell32.SetCurrentProcessExplicitAppUserModelID("Speedtest.Mini")
    except Exception:  # noqa: BLE001
        pass

try:
    from PyQt6.QtCore import Qt, QThread, QRectF, QTimer, pyqtSignal
    from PyQt6.QtGui import (QBrush, QColor, QConicalGradient, QFont, QIcon, QPainter,
                             QPainterPath, QPen)
    from PyQt6.QtWidgets import (QApplication, QGridLayout, QHBoxLayout, QLabel, QPushButton,
                                 QVBoxLayout, QWidget)
    QT6 = True
except ImportError:  # Windows 7/8 — PyQt5
    from PyQt5.QtCore import Qt, QThread, QRectF, QTimer, pyqtSignal
    from PyQt5.QtGui import (QBrush, QColor, QConicalGradient, QFont, QIcon, QPainter,
                             QPainterPath, QPen)
    from PyQt5.QtWidgets import (QApplication, QGridLayout, QHBoxLayout, QLabel, QPushButton,
                                 QVBoxLayout, QWidget)
    QT6 = False

HERE = os.path.dirname(os.path.abspath(__file__))

# ---------- темы оформления ----------
# ACCENT — загрузка и кнопка, ACCENT2 — отдача, ACCENT_HI — кнопка под курсором
# Палитра стихий/рас: загрузка — цвет темы, отдача — соседний цвет радуги
RAINBOW = ["#FF2E2E", "#FF7A1A", "#FFE619", "#22C55E", "#2F7BF6", "#9D4EDD"]
#          ключ      название    раса              основной     фон тёмной (BG, BORDER, TRACK, FG, DIM, TRACK_TXT)                    фон светлой
_PALETTE = [
    ("fire",    "Огонь",   "Люди",           "#FF2E2E", ("#140d0d", "#2a1a1a", "#2c1d1d", "#f2e8e8", "#9a8484", "#5e4a4a"),
                                                        ("#fbf4f4", "#efd9d9", "#f2e1e1", "#2a1414", "#8a6c6c", "#bba0a0")),
    ("earth",   "Земля",   "Орки",           "#FF7A1A", ("#14100c", "#2a2018", "#2d231b", "#f2ebe4", "#9a8a7c", "#5e5043"),
                                                        ("#fbf6f1", "#eee0d2", "#f1e6db", "#2a1d12", "#8a7462", "#bba693")),
    ("light",   "Свет",    "Гномы",          "#FFE619", ("#13120b", "#29271a", "#2b291c", "#f3f1e3", "#9a9680", "#5d5a45"),
                                                        ("#fbfaf0", "#ece8cf", "#f0edd9", "#26230f", "#807b5c", "#b2ad8c")),
    ("wind",    "Ветер",   "Тёмные эльфы",   "#22C55E", ("#0c1410", "#1a2720", "#1d2b24", "#e5f0ea", "#7b9086", "#485b51"),
                                                        ("#f2f8f4", "#d6e7dd", "#deece4", "#12221a", "#5f7a6c", "#9ab0a4")),
    ("water",   "Вода",    "Светлые эльфы",  "#2F7BF6", ("#0c0f16", "#1a2030", "#1d2435", "#e6ebf4", "#7c8599", "#49516a"),
                                                        ("#f3f6fc", "#d9e1f0", "#e1e8f4", "#141c2c", "#64708a", "#a0aac0")),
    ("dark",    "Тьма",    "Камаэли",        "#9D4EDD", ("#110d17", "#241c32", "#271e37", "#eee8f6", "#8d82a2", "#574c6c"),
                                                        ("#f7f3fc", "#e3d9f0", "#e9e1f4", "#1f1530", "#776a90", "#ada2c2")),
    ("rainbow", "Радуга",  "все расы",       None,      ("#0f0f12", "#222228", "#26262d", "#ececf0", "#85858f", "#50505a"),
                                                        ("#f6f6f8", "#e0e0e6", "#e7e7ec", "#1b1b22", "#6c6c78", "#a5a5b0")),
]


def _rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def _hex(c):
    return "#%02x%02x%02x" % tuple(max(0, min(255, round(x))) for x in c)


def _mix(a, b, t):
    """a → b на долю t."""
    ra, rb = _rgb(a), _rgb(b)
    return _hex(ra[i] + (rb[i] - ra[i]) * t for i in range(3))


def _btn_txt(c):
    r, g, b = _rgb(c)
    return "#111114" if 0.299 * r + 0.587 * g + 0.114 * b > 150 else "#ffffff"


def _grad_css(lighten=0.0):
    stops = ", ".join(f"stop:{i / (len(RAINBOW) - 1):.2f} {_mix(c, '#ffffff', lighten)}" for i, c in enumerate(RAINBOW))
    return f"qlineargradient(x1:0, y1:0, x2:1, y2:0, {stops})"


def _make_theme(key, name, race, main, bg, light):
    keys = ("BG", "BORDER", "TRACK", "FG", "DIM", "TRACK_TXT")
    t = dict(zip(keys, bg))
    if main:
        a2 = RAINBOW[(RAINBOW.index(main) + 1) % len(RAINBOW)]
        t.update(ACCENT=main, ACCENT2=a2, ACCENT_HI=_mix(main, "#ffffff", 0.18), BTN_TXT=_btn_txt(main),
                 BTN_BG=main, BTN_HI=_mix(main, "#ffffff", 0.18))
    else:  # радуга: дуги — градиент по всей шкале, кнопка — градиент
        t.update(ACCENT="#2F7BF6", ACCENT2="#9D4EDD", ACCENT_HI="#5a96f8", BTN_TXT="#111114",
                 BTN_BG=_grad_css(), BTN_HI=_grad_css(0.18), GRADIENT=True)
    # цвет подписей ↓ЗАГРУЗКА / ↑ОТДАЧА: на светлом фоне яркие цвета (жёлтый) затемняем для читаемости
    t.update(TXT1=t["ACCENT"], TXT2=t["ACCENT2"])
    if light:
        t.update(TXT1=_mix(t["ACCENT"], "#000000", 0.28), TXT2=_mix(t["ACCENT2"], "#000000", 0.28))
    t["NAME"] = f"{name} — {race}" + (" · светлая" if light else "")
    return t


THEMES = {}
for _k, _n, _r, _m, _d, _l in _PALETTE:
    THEMES[_k] = _make_theme(_k, _n, _r, _m, _d, False)
for _k, _n, _r, _m, _d, _l in _PALETTE:
    THEMES[_k + "_light"] = _make_theme(_k, _n, _r, _m, _l, True)
DARK_KEYS = [p[0] for p in _PALETTE]
LIGHT_KEYS = [k + "_light" for k in DARK_KEYS]
DEFAULT_THEME = "wind"   # зелёная, как на сайте
THEME = DEFAULT_THEME


def apply_theme(key):
    """Делает тему текущей: цвета — глобальные константы, которые читает весь интерфейс."""
    global THEME
    THEME = key if key in THEMES else DEFAULT_THEME
    globals()["GRADIENT"] = False
    globals().update({k: v for k, v in THEMES[THEME].items() if k != "NAME"})


apply_theme(DEFAULT_THEME)
FONT = "Segoe UI"


VERSION = "1.3.0"
UPDATE_REPO = "kolobas58/speedtest"   # GitHub owner/repo с релизами
# Ed25519 публичный ключ: обновление ставится, только если latest.json подписан парным приватным ключом
UPDATE_PUBKEY = "0696ac4d041b14d1a288ae43fb9201ead6d69e77be48fd0d196c473f6bafbc4e"
UA = f"Mozilla/5.0 (Windows NT 10.0; Win64; x64) Speedtest-kolobas58/{VERSION}"
CTX = ssl.create_default_context()
STREAMS = 4            # параллельных потоков
DURATION = 10.0        # секунд на фазу (после последнего переключения сервера)
MAX_PHASE = 22.0       # жёсткий предел фазы, с
WARMUP = 1.5           # секунд разгона, не учитываются в итоге
UL_CHUNK = 4_000_000   # байт на один POST (под лимиты PHP/nginx у серверов)
PROBE_TIMEOUT = 2.5    # таймаут пинга кандидата при выборе сервера, с
SEARCH_MIN = 0.7       # не раньше, чем через столько секунд выбираем сервер (чтобы успели ближние)
SEARCH_FAV = 0.35      # ...а если отозвался сервер из прошлого замера — через столько
SEARCH_MAX = 3.0       # жёсткий предел поиска, с
MAX_FAILS = 3          # сетевых ошибок на сервере до переключения
GAUGE_MAX = 1000.0     # Мбит/с, верх шкалы (логарифмической)
LIBRESPEED_LIST = "https://librespeed.org/backend-servers/servers.php"

# --- Встроенный список серверов (живой список LibreSpeed подтягивается при запуске) ---
# (название, базовый URL, dl, ul, ping)
LIBRESPEED_BUILTIN = [
    ("Los Angeles, USA (Clouvider)", "https://la.speedtest.clouvider.net/backend", "garbage.php", "empty.php", "empty.php"),
    ("Los Angeles, USA (Sharktech)", "https://laxspeed.sharktech.net", "backend/garbage.php", "backend/empty.php", "backend/empty.php"),
    ("Las Vegas, USA (Sharktech)", "https://lasspeed.sharktech.net", "backend/garbage.php", "backend/empty.php", "backend/empty.php"),
    ("Denver, USA (Sharktech)", "https://denspeed.sharktech.net", "backend/garbage.php", "backend/empty.php", "backend/empty.php"),
    ("Chicago, USA (Sharktech)", "https://chispeed.sharktech.net", "backend/garbage.php", "backend/empty.php", "backend/empty.php"),
    ("Grand Rapids, USA (RackGenius)", "https://mispeed.rackgenius.com/", "backend/garbage.php", "backend/empty.php", "backend/empty.php"),
    ("Atlanta, USA (Clouvider)", "https://atl.speedtest.clouvider.net/backend", "garbage.php", "empty.php", "empty.php"),
    ("New York, USA (Clouvider)", "https://nyc.speedtest.clouvider.net/backend", "garbage.php", "empty.php", "empty.php"),
    ("London, UK (Clouvider)", "https://lon.speedtest.clouvider.net/backend", "garbage.php", "empty.php", "empty.php"),
    ("Amsterdam, NL (Clouvider)", "https://ams.speedtest.clouvider.net/backend", "garbage.php", "empty.php", "empty.php"),
    ("Amsterdam, NL (Sharktech)", "https://amsspeed.sharktech.net", "backend/garbage.php", "backend/empty.php", "backend/empty.php"),
    ("Frankfurt, DE (Clouvider)", "https://fra.speedtest.clouvider.net/backend", "garbage.php", "empty.php", "empty.php"),
    ("Frankfurt, DE (FS IT-Systeme)", "https://speed.fs-it.systems/", "backend/garbage.php", "backend/empty.php", "backend/empty.php"),
    ("Helsinki, FI (Hetzner)", "https://www.librespeed.fi/", "backend/garbage.php", "backend/empty.php", "backend/empty.php"),
    ("Prague, CZ (CESNET)", "https://speedtest.cesnet.cz", "backend/garbage.php", "backend/empty.php", "backend/empty.php"),
    ("Prague, CZ (Turris)", "https://librespeed.turris.cz", "backend/garbage.php", "backend/empty.php", "backend/empty.php"),
    ("Poznan, PL (INEA)", "https://speedtest.kamilszczepanski.com", "garbage.php", "empty.php", "empty.php"),
    ("Roma, IT (GARR)", "https://st-be-rm2.infra.garr.it", "garbage.php", "empty.php", "empty.php"),
    ("Belgrade, RS (SOX)", "https://speedtest1.sox.rs/librespeed/", "backend/garbage.php", "backend/empty.php", "backend/empty.php"),
    ("Novi Sad, RS (E-CAPS)", "https://speed1.e-caps.net", "backend/garbage.php", "backend/empty.php", "backend/empty.php"),
    ("Argalasti, GR (Cosmote)", "https://argalasti.skoultsos.eu/", "backend/garbage.php", "backend/empty.php", "backend/empty.php"),
    ("Tokyo, JP (A573)", "https://librespeed.a573.net/", "backend/garbage.php", "backend/empty.php", "backend/empty.php"),
]
# Запасные серверы только для загрузки (большие статичные файлы)
VULTR = [
    ("Los Angeles", "lax-ca-us-ping"), ("Silicon Valley", "sjo-ca-us-ping"), ("Seattle", "wa-us-ping"),
    ("Dallas", "tx-us-ping"), ("Chicago", "il-us-ping"), ("New Jersey", "nj-us-ping"),
    ("Atlanta", "ga-us-ping"), ("Miami", "fl-us-ping"), ("Frankfurt", "fra-de-ping"),
    ("Amsterdam", "ams-nl-ping"), ("London", "lon-gb-ping"), ("Paris", "par-fr-ping"),
    ("Tokyo", "hnd-jp-ping"), ("Singapore", "sgp-ping"), ("Sydney", "syd-au-ping"),
]


class Server:
    def __init__(self, name, base, dl, ul, ping, kind, tier):
        if not base.endswith("/"):
            base += "/"
        u = urlsplit(base)
        self.name, self.kind, self.tier = name, kind, tier
        self.https = u.scheme == "https"
        self.host = u.netloc
        root = u.path or "/"
        j = lambda p: None if p is None else (p if p.startswith("/") else urljoin(root, p))  # noqa: E731
        self.dl, self.ul, self.ping = j(dl), j(ul), j(ping)
        self.rtt = None
        self.key = (self.host + root).lower()

    def conn(self, timeout=15):
        if self.https:
            return http.client.HTTPSConnection(self.host, timeout=timeout, context=CTX)
        return http.client.HTTPConnection(self.host, timeout=timeout)

    def _q(self, path, extra=""):
        if self.kind != "librespeed":
            return path
        sep = "&" if "?" in path else "?"
        return f"{path}{sep}{extra}r={random.random()}"

    def dl_path(self):
        return self._q(self.dl, "ckSize=100&")

    def ul_path(self):
        return self._q(self.ul)

    def ping_path(self):
        return self._q(self.ping)


def state_dir():
    base = os.environ.get("LOCALAPPDATA") or os.path.join(os.path.expanduser("~"), ".cache")
    d = os.path.join(base, "Speedtest")
    os.makedirs(d, exist_ok=True)
    return d


def load_state():
    try:
        with open(os.path.join(state_dir(), "state.json"), encoding="utf-8") as f:
            return json.load(f)
    except Exception:  # noqa: BLE001
        return {}


def save_state(**kw):
    try:
        st = load_state()
        st.update(kw)
        path = os.path.join(state_dir(), "state.json")
        with open(path + ".tmp", "w", encoding="utf-8") as f:
            json.dump(st, f, ensure_ascii=False)
        os.replace(path + ".tmp", path)
    except Exception:  # noqa: BLE001
        pass


def refresh_server_list():
    """Фоном после замера: свежий список LibreSpeed в кэш — используется со следующего запуска."""
    try:
        u = urlsplit(LIBRESPEED_LIST)
        c = http.client.HTTPSConnection(u.netloc, timeout=8, context=CTX)
        c.request("GET", u.path, headers={"User-Agent": UA})
        r = c.getresponse()
        if r.status == 200:
            lst = [e for e in json.loads(r.read().decode("utf-8", "replace"))
                   if isinstance(e, dict) and e.get("server") and e.get("dlURL") and e.get("ulURL")]
            if lst:
                save_state(librespeed=lst)
        c.close()
    except Exception:  # noqa: BLE001
        pass


def load_servers():
    servers = {}

    def add(s):
        servers.setdefault(s.key, s)

    # 1) список LibreSpeed из кэша (обновляется фоном после замера), без сетевых запросов на старте
    for e in load_state().get("librespeed", []):
        try:
            add(Server(e.get("name", e["server"]), e["server"], e["dlURL"], e["ulURL"],
                       e.get("pingURL") or e["ulURL"], "librespeed", 0))
        except Exception:  # noqa: BLE001
            pass
    # 2) встроенный список
    for name, base, dl, ul, ping in LIBRESPEED_BUILTIN:
        add(Server(name, base, dl, ul, ping, "librespeed", 0))
    # 3) Cloudflare — запасной полноценный (часто режет частые замеры)
    add(Server("Cloudflare (ближайший узел)", "https://speed.cloudflare.com/",
               "__down?bytes=50000000", "__up", "__down?bytes=0", "cloudflare", 1))
    # 4) Vultr — запасные только для загрузки
    for city, h in VULTR:
        add(Server(f"{city} (Vultr)", f"https://{h}.vultr.com/", "vultr.com.1000MB.bin", None, "/", "static", 2))
    return list(servers.values())


def probe(srv, stop):
    """RTT до сервера, мс (лучший из 2 запросов после TLS-разогрева) или None."""
    try:
        c = srv.conn(PROBE_TIMEOUT)
        best = None
        for i in range(3):
            if stop.is_set():
                break
            t = time.perf_counter()
            c.request("GET", srv.ping_path(), headers={"User-Agent": UA})
            r = c.getresponse()
            r.read(65536)
            if r.status != 200:
                c.close()
                return None
            if i:  # первый запрос — TLS-рукопожатие, не считаем
                dt = (time.perf_counter() - t) * 1000
                best = dt if best is None else min(best, dt)
        c.close()
        return best
    except Exception:  # noqa: BLE001
        return None


class Worker(QThread):
    phase = pyqtSignal(str)
    live = pyqtSignal(float)          # средняя скорость с начала фазы, Мбит/с
    result = pyqtSignal(str, float)
    server = pyqtSignal(str, float)   # выбранный сервер, его пинг
    search = pyqtSignal(int, int, str, float)  # проверено, всего, лучший, его пинг
    failed = pyqtSignal(str)

    def __init__(self):
        super().__init__()
        self.stop = threading.Event()
        self.done = threading.Event()
        self.lock = threading.Lock()
        self.counter = 0
        self.errors = []
        self.pool = []
        self.idx = 0
        self.epoch = 0
        self.fails = {}

    # ---------- выбор сервера ----------
    def rank(self, servers):
        """Пингует все серверы параллельно и выходит рано: ближние отвечают за доли секунды,
        дальние ждать бессмысленно. Неопрошенные остаются в конце пула как запасные."""
        fav = load_state().get("best")
        total, checked, alive = len(servers), 0, []
        ex = ThreadPoolExecutor(max_workers=min(48, total))
        futs = {ex.submit(probe, s, self.stop): s for s in servers}
        pending = set(futs)
        t0 = time.perf_counter()
        self.search.emit(0, total, "", 0.0)
        while pending and not self.stop.is_set():
            done, pending = wait(pending, timeout=0.1, return_when=FIRST_COMPLETED)
            for f in done:
                checked += 1
                s = futs[f]
                s.rtt = f.result()
                if s.rtt is not None:
                    alive.append(s)
            full = [s for s in alive if s.ul and s.tier == 0]
            best = min(full, key=lambda s: s.rtt) if full else (min(alive, key=lambda s: (s.tier, s.rtt)) if alive else None)
            self.search.emit(checked, total, best.name if best else "", best.rtt if best else 0.0)
            el = time.perf_counter() - t0
            fav_ok = any(s.key == fav for s in full)
            if (fav_ok and el >= SEARCH_FAV) or (full and el >= SEARCH_MIN) or el >= SEARCH_MAX:
                break
        ex.shutdown(wait=False)
        alive.sort(key=lambda s: (s.tier, s.rtt))
        rest = sorted((s for s in servers if s.rtt is None and s not in alive), key=lambda s: s.tier)
        return alive, rest

    def _announce(self, srv):
        self.server.emit(srv.name, srv.rtt or 0.0)

    # ---------- фазы ----------
    def run(self):
        try:
            self.phase.emit("Поиск сервера")
            ranked, rest = self.rank(load_servers())
            if self.stop.is_set():
                return
            if not ranked:
                raise RuntimeError("нет доступных серверов — проверьте подключение")
            # основной порядок: полноценные серверы по пингу, затем запасные только-загрузка,
            # в самом конце — те, кто не успел ответить за время поиска
            full = [s for s in ranked if s.ul] + [s for s in rest if s.ul]
            dl_pool = [s for s in ranked if s.ul] + [s for s in ranked if not s.ul] + rest

            self.phase.emit("Пинг")
            ping = jitter = None
            for s in dl_pool[:5]:
                try:
                    ping, jitter = self.measure_ping(s)
                    dl_pool.remove(s)
                    dl_pool.insert(0, s)
                    break
                except Exception as e:  # noqa: BLE001
                    self.errors.append(f"{s.name}: {e}")
            if ping is None:
                raise RuntimeError("серверы не отвечают на пинг")
            self._announce(dl_pool[0])
            self.result.emit("ping", ping)
            self.result.emit("jitter", jitter)
            if self.stop.is_set():
                return

            self.phase.emit("Загрузка")
            self.result.emit("down", self.measure(dl_pool, upload=False))
            if self.stop.is_set():
                return

            if not full:
                raise RuntimeError("нет серверов для замера отдачи")
            used = self.pool[min(self.idx, len(self.pool) - 1)]
            ul_pool = ([used] if used.ul else []) + [s for s in full if s is not used]
            self.phase.emit("Отдача")
            self.result.emit("up", self.measure(ul_pool, upload=True))
            if used.ul and not self.stop.is_set():
                save_state(best=used.key)  # в следующий раз начнём с него
        except Exception as e:  # noqa: BLE001
            self.failed.emit(str(e) or e.__class__.__name__)

    def measure_ping(self, srv):
        c = srv.conn(8)
        hdr = {"User-Agent": UA}
        try:
            c.request("GET", srv.ping_path(), headers=hdr)  # прогрев TLS
            r = c.getresponse()
            r.read()
            if r.status != 200:
                raise RuntimeError(f"HTTP {r.status}")
            rtts = []
            for _ in range(12):
                if self.stop.is_set():
                    break
                t = time.perf_counter()
                c.request("GET", srv.ping_path(), headers=hdr)
                r = c.getresponse()
                r.read()
                rtts.append((time.perf_counter() - t) * 1000)
        finally:
            c.close()
        if not rtts:
            return srv.rtt or 0.0, 0.0
        jitter = statistics.mean(abs(a - b) for a, b in zip(rtts, rtts[1:])) if len(rtts) > 1 else 0.0
        return statistics.median(rtts), jitter

    def measure(self, pool, upload):
        self.pool, self.idx, self.epoch, self.fails = pool, 0, 0, {}
        self.counter = 0
        self.done.clear()
        self._announce(pool[0])
        loop = self.ul_loop if upload else self.dl_loop
        threads = [threading.Thread(target=self._safe, args=(loop,), daemon=True) for _ in range(STREAMS)]
        for t in threads:
            t.start()

        start = t0 = time.perf_counter()
        base, epoch = 0, 0
        warm_b = warm_t = None
        b, now = 0, t0
        while True:
            time.sleep(0.1)
            now = time.perf_counter()
            with self.lock:
                b = self.counter
                ep = self.epoch
            if ep != epoch:  # сменили сервер — считаем заново с этого момента
                epoch, base, t0, warm_b, warm_t = ep, b, now, None, None
            if warm_b is None and now - t0 >= WARMUP:
                warm_b, warm_t = b, now
            self.live.emit(self._avg(b - base, now, t0, None if warm_b is None else warm_b - base, warm_t))
            if (now - t0 >= DURATION or now - start >= MAX_PHASE or self.stop.is_set()
                    or not any(t.is_alive() for t in threads)):
                break
        self.done.set()
        for t in threads:
            t.join(2)

        got = b - base
        if got < 100_000 and not self.stop.is_set():
            raise RuntimeError(self.errors[-1] if self.errors else "сервер не отдал данные")
        return self._avg(got, now, t0, None if warm_b is None else warm_b - base, warm_t)

    @staticmethod
    def _avg(b, now, t0, warm_b, warm_t):
        # после разгона — среднее только по «прогретому» участку, до него — общее
        if warm_b is not None and now - warm_t >= 0.5:
            return (b - warm_b) * 8 / (now - warm_t) / 1e6
        return b * 8 / max(now - t0, 1e-6) / 1e6

    def _safe(self, loop):
        try:
            loop()
        except Exception as e:  # noqa: BLE001
            if not self.done.is_set():
                self.errors.append(str(e) or e.__class__.__name__)

    def _add(self, n):
        with self.lock:
            self.counter += n

    def _fail(self, idx, why, hard):
        """Ошибка на сервере idx. hard=True (отказ HTTP) — сразу следующий сервер."""
        switched = None
        with self.lock:
            self.errors.append(why)
            if self.idx != idx:
                return
            self.fails[idx] = self.fails.get(idx, 0) + 1
            if hard or self.fails[idx] >= MAX_FAILS:
                self.idx += 1
                self.epoch += 1
                if self.idx < len(self.pool):
                    switched = self.pool[self.idx]
        if switched:
            self._announce(switched)

    def _run_streams(self, once):
        while not self.done.is_set():
            idx = self.idx
            if idx >= len(self.pool):
                raise RuntimeError("все серверы недоступны")
            srv = self.pool[idx]
            c = srv.conn()
            try:
                while not self.done.is_set() and self.idx == idx:
                    err = once(c, srv)
                    if err:
                        self._fail(idx, f"{srv.name}: {err}", hard=True)
                        break
            except (OSError, http.client.HTTPException) as e:
                if self.done.is_set():
                    return
                self._fail(idx, f"{srv.name}: {e}", hard=False)
                time.sleep(0.3)
            finally:
                c.close()

    def _dl_once(self, c, srv):
        c.request("GET", srv.dl_path(), headers={"User-Agent": UA, "Accept-Encoding": "identity"})
        r = c.getresponse()
        if r.status != 200:
            r.read()
            return f"HTTP {r.status}"
        got = 0
        while not self.done.is_set():
            d = r.read(65536)
            if not d:
                break
            got += len(d)
            self._add(len(d))
        if got == 0 and not self.done.is_set():
            return "пустой ответ"
        return None

    def _ul_once(self, c, srv):
        c.putrequest("POST", srv.ul_path())
        c.putheader("User-Agent", UA)
        c.putheader("Content-Type", "application/octet-stream")
        c.putheader("Content-Length", str(UL_CHUNK))
        c.endheaders()
        sent = 0
        while sent < UL_CHUNK and not self.done.is_set():
            n = min(len(self.payload), UL_CHUNK - sent)
            c.send(self.payload[:n])
            sent += n
            self._add(n)
        if self.done.is_set():
            return None
        r = c.getresponse()
        r.read()
        if r.status not in (200, 204):
            return f"HTTP {r.status}"
        return None

    def dl_loop(self):
        self._run_streams(self._dl_once)

    def ul_loop(self):
        self.payload = getattr(self, "payload", None) or os.urandom(65536)
        self._run_streams(self._ul_once)


# ===================== автообновление =====================
# Обновление = новый Speedtest.exe из GitHub Releases. Ставится, только если
# latest.json подписан Ed25519-ключом разработчика (проверка ниже, чистый Python).

_P = 2 ** 255 - 19
_Q = 2 ** 252 + 27742317777372353535851937790883648493
_D = -121665 * pow(121666, _P - 2, _P) % _P
_I = pow(2, (_P - 1) // 4, _P)


def _xrecover(y):
    xx = (y * y - 1) * pow(_D * y * y + 1, _P - 2, _P) % _P
    x = pow(xx, (_P + 3) // 8, _P)
    if (x * x - xx) % _P:
        x = x * _I % _P
    if (x * x - xx) % _P:
        raise ValueError("not on curve")
    return x


_BY = 4 * pow(5, _P - 2, _P) % _P
_BX = _xrecover(_BY)
if _BX & 1:
    _BX = _P - _BX
_B = (_BX, _BY, 1, _BX * _BY % _P)


def _padd(a, b):
    x1, y1, z1, t1 = a
    x2, y2, z2, t2 = b
    aa = (y1 - x1) * (y2 - x2) % _P
    bb = (y1 + x1) * (y2 + x2) % _P
    cc = t1 * 2 * _D * t2 % _P
    dd = z1 * 2 * z2 % _P
    e, f, g, h = bb - aa, dd - cc, dd + cc, bb + aa
    return (e * f % _P, g * h % _P, f * g % _P, e * h % _P)


def _pmul(k, pt):
    q = (0, 1, 1, 0)
    while k:
        if k & 1:
            q = _padd(q, pt)
        pt = _padd(pt, pt)
        k >>= 1
    return q


def _penc(pt):
    x, y, z, _ = pt
    zi = pow(z, _P - 2, _P)
    x, y = x * zi % _P, y * zi % _P
    return (y | ((x & 1) << 255)).to_bytes(32, "little")


def _pdec(b):
    y = int.from_bytes(b, "little")
    sign, y = y >> 255, y & ((1 << 255) - 1)
    if y >= _P:
        raise ValueError("bad point")
    x = _xrecover(y)
    if x == 0 and sign:
        raise ValueError("bad point")
    if (x & 1) != sign:
        x = _P - x
    return (x, y, 1, x * y % _P)


def ed25519_verify(pub, msg, sig):
    try:
        if len(pub) != 32 or len(sig) != 64:
            return False
        r_pt, a_pt = _pdec(sig[:32]), _pdec(pub)
        s_int = int.from_bytes(sig[32:], "little")
        if s_int >= _Q:
            return False
        h = int.from_bytes(hashlib.sha512(sig[:32] + pub + msg).digest(), "little") % _Q
        return _penc(_pmul(s_int, _B)) == _penc(_padd(r_pt, _pmul(h, a_pt)))
    except Exception:  # noqa: BLE001
        return False


def _ver(v):
    try:
        return tuple(int(x) for x in str(v).lstrip("v").split("."))
    except ValueError:
        return (0,)


def exe_path():
    """Путь к Speedtest.exe, из которого запущено приложение (передаёт стартер)."""
    if "--exe" in sys.argv:
        i = sys.argv.index("--exe")
        if i + 1 < len(sys.argv):
            return sys.argv[i + 1]
    return None


def _http_get(url, timeout=10):
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "*/*"})
    return urllib.request.urlopen(req, timeout=timeout, context=CTX)


class Updater(QThread):
    updated = pyqtSignal(str)

    def __init__(self, base_url=None):
        super().__init__()
        # SPEEDTEST_UPDATE_BASE — только для тестов; подпись ключом проверяется всегда
        self.base = (base_url or os.environ.get("SPEEDTEST_UPDATE_BASE")
                     or f"https://github.com/{UPDATE_REPO}/releases/latest/download/")

    def run(self):
        try:
            self.check()
        except Exception:  # noqa: BLE001  (обновление — тихо, никогда не мешает замеру)
            pass

    def check(self):
        exe = exe_path()
        if not exe or not os.path.isfile(exe) or "@" in UPDATE_PUBKEY:
            return
        with _http_get(self.base + "latest.json") as r:
            man = json.loads(r.read(65536).decode("utf-8"))
        ver, name, digest = str(man["version"]), str(man["file"]), str(man["sha256"]).lower()
        size = int(man["size"])
        msg = f"{ver}|{name}|{digest}|{size}".encode()
        if not ed25519_verify(bytes.fromhex(UPDATE_PUBKEY), msg, bytes.fromhex(man["sig"])):
            return
        if _ver(ver) <= _ver(VERSION) or "/" in name or "\\" in name or size > 200_000_000:
            return
        tmp = exe + ".new"
        h = hashlib.sha256()
        got = 0
        try:
            with _http_get(self.base + name, timeout=30) as r, open(tmp, "wb") as f:
                while True:
                    chunk = r.read(262144)
                    if not chunk:
                        break
                    got += len(chunk)
                    if got > size:
                        raise ValueError("too big")
                    h.update(chunk)
                    f.write(chunk)
            if got != size or h.hexdigest() != digest:
                raise ValueError("checksum mismatch")
        except Exception:
            try:
                os.remove(tmp)
            except OSError:
                pass
            return
        # Стартер к этому моменту уже завершился, exe не занят — подменяем на месте.
        old = exe + ".old"
        try:
            if os.path.exists(old):
                os.remove(old)
        except OSError:
            pass
        try:
            os.replace(tmp, exe)
        except OSError:
            os.replace(exe, old)
            os.replace(tmp, exe)
        _bump_installed_version(exe, ver)
        self.updated.emit(ver)


def _bump_installed_version(exe, ver):
    """Если это установленная копия — обновить версию в «Программах и компонентах»."""
    if sys.platform != "win32":
        return
    try:
        import winreg
        key = r"Software\Microsoft\Windows\CurrentVersion\Uninstall\Speedtest"
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, key, 0, winreg.KEY_READ | winreg.KEY_SET_VALUE) as k:
            loc = winreg.QueryValueEx(k, "InstallLocation")[0]
            if os.path.normcase(os.path.abspath(loc)) == os.path.normcase(os.path.dirname(os.path.abspath(exe))):
                winreg.SetValueEx(k, "DisplayVersion", 0, winreg.REG_SZ, ver)
    except OSError:
        pass


def fmt(v):
    return f"{v:.0f}" if v >= 100 else f"{v:.1f}"


class Gauge(QWidget):
    """Дуга с плавной анимацией. Режимы: live (одна скорость) и results (итоги)."""

    def __init__(self):
        super().__init__()
        self.setMinimumSize(300, 300)
        self.target = 0.0
        self.shown = 0.0
        self.label = ""
        self.role = "ACCENT"  # какой цвет темы у дуги: ACCENT (загрузка) / ACCENT2 (отдача)
        self.results = None  # (down, up)
        self.searching = None  # (проверено, всего) во время поиска сервера
        self.spin = 0.0
        self.anim = QTimer(self)
        self.anim.setInterval(16)
        self.anim.timeout.connect(self._tick)
        self.anim.start()

    def set_search(self, checked, total):
        self.results = None
        self.searching = (checked, total)
        self.update()

    def set_live(self, label, role):
        self.results = None
        self.searching = None
        self.label = label
        self.role = role
        self.update()

    def set_target(self, v):
        self.target = max(0.0, v)

    def reset(self):
        self.target = self.shown = 0.0
        self.results = None
        self.searching = None
        self.label = ""
        self.update()

    def set_results(self, down, up):
        self.searching = None
        self.results = (down, up)
        self.update()

    def _tick(self):
        if self.searching:
            self.spin = (self.spin + 4.0) % 270
            self.update()
            return
        d = self.target - self.shown
        if abs(d) < 0.01:
            if self.shown != self.target:
                self.shown = self.target
                self.update()
            return
        self.shown += d * 0.08
        self.update()

    @staticmethod
    def _arc_pen(pen, rect, color):
        """Перо для дуги: обычный цвет или (тема «Радуга») градиент красный → фиолетовый по шкале."""
        if not GRADIENT:
            pen.setColor(QColor(color))
            return pen
        # QConicalGradient идёт против часовой от угла 315° (низ справа) — там фиолетовый,
        # к 225° (низ слева, начало шкалы) — красный
        g = QConicalGradient(rect.center(), 315)
        n = len(RAINBOW) - 1
        for i, c in enumerate(reversed(RAINBOW)):
            g.setColorAt(0.75 * i / n, QColor(c))
        g.setColorAt(0.87, QColor(RAINBOW[0]))
        g.setColorAt(1.0, QColor(RAINBOW[-1]))
        pen.setBrush(QBrush(g))
        return pen

    @staticmethod
    def _frac(v):
        return min(1.0, math.log10(1 + max(v, 0)) / math.log10(1 + GAUGE_MAX))

    def paintEvent(self, _):
        p = QPainter(self)
        p.setRenderHint(QPainter.RenderHint.Antialiasing)
        side = min(self.width(), self.height()) - 30
        rect = QRectF((self.width() - side) / 2, (self.height() - side) / 2, side, side)

        pen = QPen(QColor(TRACK), 14)
        pen.setCapStyle(Qt.PenCapStyle.RoundCap)
        p.setPen(pen)
        p.drawArc(rect, 225 * 16, -270 * 16)

        if self.results:
            self._paint_results(p, rect, pen)
            return
        if self.searching:
            self._paint_search(p, rect, pen)
            return

        frac = self._frac(self.shown)
        if frac > 0.002:
            self._arc_pen(pen, rect, globals()[self.role])
            p.setPen(pen)
            p.drawArc(rect, 225 * 16, int(-270 * 16 * frac))

        p.setPen(QColor(DIM))
        p.setFont(QFont(FONT, 11))
        p.drawText(rect.adjusted(0, -95, 0, -95), Qt.AlignmentFlag.AlignCenter, self.label.upper())
        p.setPen(QColor(FG))
        p.setFont(QFont(FONT, 44, QFont.Weight.Light))
        p.drawText(rect.adjusted(0, -10, 0, -10), Qt.AlignmentFlag.AlignCenter, fmt(self.shown))
        p.setPen(QColor(DIM))
        p.setFont(QFont(FONT, 12))
        p.drawText(rect.adjusted(0, 55, 0, 55), Qt.AlignmentFlag.AlignCenter, "Мбит/с")

    def _paint_search(self, p, rect, pen):
        # бегущий сегмент по дуге шкалы
        seg = 60
        start = 225 - min(self.spin, 270 - seg)
        self._arc_pen(pen, rect, ACCENT)
        p.setPen(pen)
        p.drawArc(rect, int(start * 16), int(-seg * 16))
        checked, total = self.searching
        p.setPen(QColor(DIM))
        p.setFont(QFont(FONT, 11))
        p.drawText(rect.adjusted(0, -95, 0, -95), Qt.AlignmentFlag.AlignCenter, "ПОИСК СЕРВЕРА")
        p.setPen(QColor(FG))
        p.setFont(QFont(FONT, 40, QFont.Weight.Light))
        p.drawText(rect.adjusted(0, -10, 0, -10), Qt.AlignmentFlag.AlignCenter, f"{checked} / {total}")
        p.setPen(QColor(DIM))
        p.setFont(QFont(FONT, 12))
        p.drawText(rect.adjusted(0, 55, 0, 55), Qt.AlignmentFlag.AlignCenter, "серверов проверено")

    def _paint_results(self, p, rect, pen):
        down, up = self.results
        # две дуги: внешняя — загрузка, внутренняя — отдача
        for v, col, inset in ((down, ACCENT, 0), (up, ACCENT2, 22)):
            r = rect.adjusted(inset, inset, -inset, -inset)
            if inset:
                pen.setColor(QColor(TRACK))
                pen.setWidth(8)
                p.setPen(pen)
                p.drawArc(r, 225 * 16, -270 * 16)
            frac = self._frac(v)
            if frac > 0.002:
                self._arc_pen(pen, r, col)
                pen.setWidth(14 if not inset else 8)
                p.setPen(pen)
                p.drawArc(r, 225 * 16, int(-270 * 16 * frac))

        cx = rect.center().x()
        cy = rect.center().y()
        colw = rect.width() * 0.32
        for i, (title, v, col) in enumerate((("ЗАГРУЗКА", down, TXT1), ("ОТДАЧА", up, TXT2))):
            x = cx - colw - 8 if i == 0 else cx + 8
            box = QRectF(x, cy - 50, colw, 22)
            p.setPen(QColor(col))
            p.setFont(QFont(FONT, 10, QFont.Weight.DemiBold))
            p.drawText(box, Qt.AlignmentFlag.AlignCenter, "↓ " + title if i == 0 else "↑ " + title)
            p.setPen(QColor(FG))
            p.setFont(QFont(FONT, 30, QFont.Weight.Light))
            p.drawText(QRectF(x, cy - 28, colw, 50), Qt.AlignmentFlag.AlignCenter, fmt(v))
        p.setPen(QColor(DIM))
        p.setFont(QFont(FONT, 12))
        p.drawText(QRectF(rect.left(), cy + 28, rect.width(), 24), Qt.AlignmentFlag.AlignCenter, "Мбит/с")


class Stat(QWidget):
    def __init__(self, title):
        super().__init__()
        lay = QVBoxLayout(self)
        lay.setContentsMargins(0, 0, 0, 0)
        lay.setSpacing(2)
        self.t = QLabel(title)
        self.t.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.v = QLabel("—")
        self.v.setAlignment(Qt.AlignmentFlag.AlignCenter)
        lay.addWidget(self.t)
        lay.addWidget(self.v)
        self.restyle()

    def restyle(self):
        self.t.setStyleSheet(f"color:{DIM}; font-size:12px; letter-spacing:1px;")
        self.v.setStyleSheet(f"color:{FG}; font-size:20px;")

    def set(self, text):
        self.v.setText(text)


class TitleButton(QPushButton):
    def __init__(self, text, hover=None):
        super().__init__(text)
        self.hover = hover  # None — цвет дорожки текущей темы
        self.setFixedSize(30, 26)
        self.setFocusPolicy(Qt.FocusPolicy.NoFocus)
        self.setCursor(Qt.CursorShape.PointingHandCursor)
        self.restyle()

    def restyle(self):
        hv = self.hover or TRACK
        fg = "white" if self.hover else FG
        self.setStyleSheet(
            f"QPushButton{{background:transparent; color:{DIM}; border:none; border-radius:6px; font-size:14px;}}"
            f"QPushButton:hover{{background:{hv}; color:{fg};}}")


class Swatch(QWidget):
    """Кружок темы: фон темы + две половинки акцентов; выбранный — с кольцом."""
    S = 30

    def __init__(self, key, on_pick):
        super().__init__()
        self.key, self.on_pick = key, on_pick
        self.setFixedSize(self.S, self.S)
        self.setCursor(Qt.CursorShape.PointingHandCursor)
        self.setToolTip(THEMES[key]["NAME"])
        self.hover = False

    def enterEvent(self, e):
        self.hover = True
        self.update()

    def leaveEvent(self, e):
        self.hover = False
        self.update()

    def mousePressEvent(self, e):
        if e.button() == Qt.MouseButton.LeftButton:
            self.on_pick(self.key)

    def paintEvent(self, _):
        t = THEMES[self.key]
        p = QPainter(self)
        p.setRenderHint(QPainter.RenderHint.Antialiasing)
        r = QRectF(4, 4, self.S - 8, self.S - 8)
        p.setPen(QPen(QColor(t["BORDER"]), 1))
        p.setBrush(QColor(t["BG"]))
        p.drawEllipse(r)
        inner = r.adjusted(4, 4, -4, -4)
        p.setPen(Qt.PenStyle.NoPen)
        if t.get("GRADIENT"):
            g = QConicalGradient(inner.center(), 90)
            for i, c in enumerate(RAINBOW + RAINBOW[:1]):
                g.setColorAt(i / len(RAINBOW), QColor(c))
            p.setBrush(QBrush(g))
            p.drawEllipse(inner)
        else:
            p.setBrush(QColor(t["ACCENT"]))
            p.drawPie(inner, 90 * 16, 180 * 16)
            p.setBrush(QColor(t["ACCENT2"]))
            p.drawPie(inner, 270 * 16, 180 * 16)
        if self.key == THEME or self.hover:
            p.setBrush(Qt.BrushStyle.NoBrush)
            p.setPen(QPen(QColor(FG if self.key == THEME else DIM), 1.6))
            p.drawEllipse(QRectF(1, 1, self.S - 2, self.S - 2))


class ThemeBar(QWidget):
    """Всплывающая панель выбора темы под заголовком."""

    def __init__(self, parent, on_pick):
        super().__init__(parent)
        lay = QGridLayout(self)
        lay.setContentsMargins(10, 8, 10, 8)
        lay.setHorizontalSpacing(2)
        lay.setVerticalSpacing(2)
        self.sw = []
        for row, keys in enumerate((DARK_KEYS, LIGHT_KEYS)):  # сверху тёмные, снизу светлые
            for col, k in enumerate(keys):
                w = Swatch(k, on_pick)
                lay.addWidget(w, row, col)
                self.sw.append(w)
        self.adjustSize()
        self.hide()

    def paintEvent(self, _):
        p = QPainter(self)
        p.setRenderHint(QPainter.RenderHint.Antialiasing)
        path = QPainterPath()
        path.addRoundedRect(QRectF(self.rect()).adjusted(0.5, 0.5, -0.5, -0.5), 18, 18)
        p.fillPath(path, QColor(TRACK))
        p.setPen(QPen(QColor(BORDER), 1))
        p.drawPath(path)


class App(QWidget):
    RADIUS = 18

    def __init__(self):
        super().__init__()
        self.setWindowTitle("Speedtest by kolobas58")
        self.setWindowFlags(Qt.WindowType.FramelessWindowHint | Qt.WindowType.Window)
        self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground)
        self.setStyleSheet(f"font-family:'{FONT}';")
        self.resize(400, 540)
        self.worker = None
        self.updater = None
        self.res = {}

        # --- заголовок (перетаскивание + кнопки) ---
        self.title = title = QLabel(self._title_html())
        title.setTextFormat(Qt.TextFormat.RichText)
        self.b_theme = TitleButton("◐")
        self.b_theme.setToolTip("Тема оформления")
        self.b_theme.clicked.connect(self.toggle_themes)
        self.b_min = TitleButton("—")
        self.b_min.clicked.connect(self.showMinimized)
        self.b_close = TitleButton("✕", "#d9434f")
        self.b_close.clicked.connect(self.close)
        bar = QHBoxLayout()
        bar.addWidget(title)
        bar.addStretch(1)
        bar.addWidget(self.b_theme)
        bar.addWidget(self.b_min)
        bar.addWidget(self.b_close)

        self.gauge = Gauge()
        self.phase = QLabel("Нажмите «Старт»")
        self.phase.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.srv = QLabel(" ")
        self.srv.setAlignment(Qt.AlignmentFlag.AlignCenter)

        self.s_ping, self.s_jit = Stat("ПИНГ, мс"), Stat("ДЖИТТЕР, мс")
        row = QHBoxLayout()
        row.addStretch(1)
        row.addWidget(self.s_ping)
        row.addSpacing(40)
        row.addWidget(self.s_jit)
        row.addStretch(1)

        self.btn = QPushButton("СТАРТ")
        self.btn.setCursor(Qt.CursorShape.PointingHandCursor)
        self.btn.setFixedSize(160, 46)
        self.btn.setFocusPolicy(Qt.FocusPolicy.NoFocus)
        self.btn.clicked.connect(self.toggle)

        lay = QVBoxLayout(self)
        lay.setContentsMargins(18, 12, 12, 26)
        lay.addLayout(bar)
        lay.addWidget(self.gauge, 1)
        lay.addWidget(self.phase)
        lay.addWidget(self.srv)
        lay.addSpacing(14)
        lay.addLayout(row)
        lay.addSpacing(22)
        lay.addWidget(self.btn, alignment=Qt.AlignmentFlag.AlignCenter)

        self.themes = ThemeBar(self, self.set_theme)
        self.restyle()

    # --- темы ---
    def restyle(self):
        self.title.setStyleSheet(f"color:{DIM}; font-size:12px; letter-spacing:1px;")
        self.title.setText(self._title_html(getattr(self, "_note", "")))
        self.phase.setStyleSheet(f"color:{DIM}; font-size:13px;")
        self.srv.setStyleSheet(f"color:{TRACK_TXT}; font-size:11px;")
        self.btn.setStyleSheet(
            f"QPushButton{{background:{BTN_BG}; color:{BTN_TXT}; border:none; border-radius:23px;"
            f" font-size:14px; font-weight:600; letter-spacing:2px;}}"
            f"QPushButton:hover{{background:{BTN_HI};}}"
            f"QPushButton:disabled{{background:{TRACK}; color:{DIM};}}")
        for w in (self.s_ping, self.s_jit, self.b_theme, self.b_min, self.b_close):
            w.restyle()
        self.themes.update()
        self.gauge.update()
        self.update()

    def set_theme(self, key):
        apply_theme(key)
        save_state(theme=THEME)  # запоминаем — следующий запуск откроется в этой теме
        self.restyle()

    def toggle_themes(self):
        if self.themes.isVisible():
            self.themes.hide()
            return
        self.themes.adjustSize()
        x = self.width() - self.themes.width() - 12
        y = self.b_theme.geometry().bottom() + 8
        self.themes.move(x, y)
        self.themes.raise_()
        self.themes.show()

    @staticmethod
    def _title_html(note=""):
        html = f"Speedtest <span style='color:{TRACK_TXT}'>by kolobas58 · v{VERSION}</span>"
        if note:
            html += f" <span style='color:#3fb27f'>· {note}</span>"
        return html

    def on_updated(self, ver):
        self._note = f"обновлено до {ver}"
        self.title.setText(self._title_html(self._note))

    # --- рамка/фон ---
    def paintEvent(self, _):
        p = QPainter(self)
        p.setRenderHint(QPainter.RenderHint.Antialiasing)
        path = QPainterPath()
        path.addRoundedRect(QRectF(self.rect()).adjusted(0.5, 0.5, -0.5, -0.5), self.RADIUS, self.RADIUS)
        p.fillPath(path, QColor(BG))
        p.setPen(QPen(QColor(BORDER), 1))
        p.drawPath(path)

    def mousePressEvent(self, e):
        if self.themes.isVisible():  # клик мимо панели — закрыть её
            self.themes.hide()
        if e.button() == Qt.MouseButton.LeftButton and self.windowHandle():
            self.windowHandle().startSystemMove()

    # --- логика ---
    def toggle(self):
        if self.worker and self.worker.isRunning():
            self.worker.stop.set()
            self.btn.setEnabled(False)
            self.phase.setText("Остановка…")
            return
        self.res = {}
        self.s_ping.set("—")
        self.s_jit.set("—")
        self.srv.setText(" ")
        self.gauge.reset()
        self.worker = Worker()
        self.worker.phase.connect(self.on_phase)
        self.worker.live.connect(self.gauge.set_target)
        self.worker.result.connect(self.on_result)
        self.worker.server.connect(self.on_server)
        self.worker.search.connect(self.on_search)
        self.worker.failed.connect(self.on_fail)
        self.worker.finished.connect(self.on_finished)
        self.btn.setText("СТОП")
        self.worker.start()

    def on_phase(self, name):
        self.phase.setText("Ищу ближайший сервер…" if name == "Поиск сервера" else name + "…")
        if name == "Поиск сервера":
            self.gauge.set_search(0, 0)
        elif name == "Пинг":
            self.gauge.reset()
        elif name == "Загрузка":
            self.gauge.set_live("↓ Загрузка", "ACCENT")
        elif name == "Отдача":
            self.gauge.set_target(0)
            self.gauge.set_live("↑ Отдача", "ACCENT2")

    def on_result(self, key, v):
        self.res[key] = v
        if key == "ping":
            self.s_ping.set(f"{v:.0f}")
        elif key == "jitter":
            self.s_jit.set(f"{v:.1f}")
        else:
            self.gauge.set_target(v)

    def on_search(self, checked, total, best, rtt):
        if self.gauge.searching is not None:
            self.gauge.set_search(checked, total)
        if best:
            self.srv.setText(f"лучший пока: {best} · {rtt:.0f} мс")

    def on_server(self, name, rtt):
        self.srv.setText(f"Сервер: {name}" + (f" · {rtt:.0f} мс" if rtt else ""))

    def on_fail(self, msg):
        self.res["error"] = msg

    def on_finished(self):
        self.btn.setText("ЕЩЁ РАЗ")
        self.btn.setEnabled(True)
        if self.updater is None:  # после первого замера, чтобы не мешать ему трафиком
            threading.Thread(target=refresh_server_list, daemon=True).start()
            self.updater = Updater()
            self.updater.updated.connect(self.on_updated)
            self.updater.start()
        if "error" in self.res:
            self.phase.setText(f"Ошибка: {self.res['error']}")
            return
        stopped = self.worker.stop.is_set()
        if "down" in self.res:
            self.gauge.set_results(self.res["down"], self.res.get("up", 0.0))
            self.phase.setText("Остановлено" if stopped else "Готово")
        else:
            self.gauge.reset()
            self.phase.setText("Остановлено")

    def closeEvent(self, e):
        if self.worker and self.worker.isRunning():
            self.worker.stop.set()
            self.worker.wait(4000)
        if self.updater and self.updater.isRunning():
            self.hide()
            self.updater.wait(15000)  # дать докачать и подменить exe
        super().closeEvent(e)


if __name__ == "__main__":
    if not QT6:
        QApplication.setAttribute(Qt.ApplicationAttribute.AA_EnableHighDpiScaling, True)
        QApplication.setAttribute(Qt.ApplicationAttribute.AA_UseHighDpiPixmaps, True)
        try:
            QApplication.setHighDpiScaleFactorRoundingPolicy(
                Qt.HighDpiScaleFactorRoundingPolicy.PassThrough)
        except AttributeError:
            pass
    app = QApplication(sys.argv)
    if exe_path():  # хвост прошлого обновления
        try:
            os.remove(exe_path() + ".old")
        except OSError:
            pass
    ico = os.path.join(HERE, "speedtest.ico")
    if os.path.exists(ico):
        app.setWindowIcon(QIcon(ico))
    apply_theme(load_state().get("theme", DEFAULT_THEME))
    w = App()
    w.show()
    QTimer.singleShot(350, w.toggle)  # замер стартует сразу при открытии
    sys.exit(app.exec() if hasattr(app, "exec") else app.exec_())
