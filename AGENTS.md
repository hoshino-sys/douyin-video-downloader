# AGENTS.md - 夜星视频下载器 (douyin-video-downloader)

> Stack: Python 3.12 (hard cap `<3.13`), FastAPI + uvicorn, httpx, aiosqlite, yt-dlp + yt-dlp-ejs (B站/YouTube), Flutter 3.47/Dart 3.13 (Windows desktop). Entrypoint `main.py` -> `src/application/TikTokDownloader.py`. Fork of DouK-Downloader / TikTokDownloader, rebranded 夜星视频下载器, version `5.9.1` (`src/custom/internal.py`).

## Commands

```bash
# Python env (must be 3.12, see .python-version)
python -m venv .venv && .venv\Scripts\activate   # or uv venv
pip install -r requirements.txt                    # generated via `uv pip compile pyproject.toml -o requirements.txt`
# or: uv pip install -r requirements.txt

# Run app
python main.py                                     # interactive menu (disclaimer -> main_menu)
python test_webui.py                               # headless WebAPI without menu (sets WindowsSelectorEventLoopPolicy on win32)

# Lint/format (ruff, line-length 88, target py312, select E4,E7,E9,F)
ruff check src
ruff format src

# Tests (dev group)
pytest                                             # generic; real interface tests are per-file __main__ needing Volume/test_cookie.ini
python -m src.interface.detail                     # example: any file in src/interface/*.py has test() guard

# Flutter GUI (Windows)
flutter config --enable-windows-desktop
cd gui/flutter_app
flutter pub get
flutter analyze
flutter test
flutter build windows --debug                      # -> build/windows/x64/runner/Debug/douk_gui.exe
flutter run -d windows                             # spawns Python backend automatically

# Package release (MANDATORY after every change - user only runs the packaged build)
D:/Python 3.12/python.exe build_release.py --zip   # pyinstaller + flutter build + assemble release/ + smoke-tested zip
```

Build env note: system `D:/Python 3.12/python.exe` has all deps (PyInstaller 6.20, ruff, yt-dlp-ejs); `.venv` is broken. Packaging needs `vendor/ffmpeg/ffmpeg.exe`+`ffprobe.exe` (source binaries, copied into backend via spec).

## Structure

- `main.py` / `src/application/TikTokDownloader.py:49` - orchestrator, owns `Settings` + `Parameter` + `Database`. `run()` = `project_info -> check_config -> check_settings -> disclaimer -> main_menu`.
- `src/application/main_terminal.py:119` - `TikTok` class, all download flows (`deal_account_detail:538`, `deal_mix_detail:1653`, `downloader.run`).
- `src/application/main_server.py:66` - `APIServer(TikTok)`, FastAPI on `SERVER_HOST:SERVER_PORT` (`0.0.0.0:5555` in `src/custom/static.py:10`, GUI backend rebinds to `127.0.0.1`). Docs at `/docs` `/redoc`.
- `gui/` - new GUI backend. `gui/backend.py` = headless `GuiAPIServer(APIServer)` on dynamic port; `gui/api_ext.py` = `/api/gui/*` (health/bootstrap/cookie 分平台 status/browsers/task/settings/thumbnail/update check+download + TaskManager). `gui/platforms_yt.py` = B站/YouTube engine on yt-dlp (detect_platform/extract_preview/run_ytdlp_download/save_platform_cookie/find_ffmpeg/find_qjs/platform_cookie_states). `gui/flutter_app/lib/*` = Flutter app. Upstream empty placeholders `src/tui_edition|cli_edition|gui_edition` were deleted 2026-08 - do not recreate.
- `src/config/settings.py:164` - reads/writes `Volume/settings.json` (UTF-8-SIG on Windows), auto-creates with defaults, `__check` fills missing keys. `src/config/parameter.py:114` - runtime validator/normalizer.
- `src/interface/template.py:103` - base `API.run()` pagination loop; subclasses `Account/Mix/Detail/Live/Comment/Search/Hot` map 1:1 to endpoints. Callable via `Params` (`src/testers/params.py`) + `Volume/test_cookie.ini`.
- `src/custom/internal.py:3` - `PROJECT_ROOT = <repo>/Volume` (auto mkdir), version `5.9.1` (`VERSION_BETA` kept defined=False, imported elsewhere); `RELEASES_API` points at hoshino-sys/douyin-video-downloader for in-app update check, `DISCLAIMER_TEXT`.
- `src/downloader/download.py:150` / `src/extract/` / `src/encrypt/` / `src/storage/` - fetch -> extract -> download -> persist.
- `Volume/` - runtime, gitignored. `settings.json`, `yexing-video-downloader.db` (tables `config_data`/`download_data`/`option_data`, key `Disclaimer`; renamed from `DouK-Downloader.db` in 5.9.1 - `src/tools/rename_compatible.py` auto-copies legacy `DouK-Downloader.db`/`TikTokDownloader.db` (also from approot) on first boot, legacy file kept), `Log/<timestamp>.log` (logger names files by datetime, not by project name), `cache/`. Don't commit. B站/YouTube cookies live in `Volume/cache/ytdlp_cookies_{bili,youtube}.txt` (Netscape format, written by `save_platform_cookie`, fed to yt-dlp via `cookiefile`).
- `build_release.py` - one-shot packager: precheck (only blocks processes running INSIDE repo release/dist dirs; the user's own installed copy elsewhere is fine) -> `bootstrap_release_dir` (copies newest old `夜星视频下载器_v5.*` dir when the new version dir is missing, preserving user data) -> PyInstaller `backend.spec` (git-tracked) -> `flutter build windows --release` -> assemble `release/夜星视频下载器_v5.9.1/` (syncs loose fallback sources `gui/*.py`, `src/`, `static/`, `locale/`; regenerates 启动.bat; copies 说明.txt from repo root - single source of truth) -> `--zip` emits clean dist zip (excludes BOTH `Volume/` at app root AND `backend/_internal/Volume/`) + **extract-and-boot smoke test**.
- `release/夜星视频下载器_v5.9.1/` - shipped layout: Flutter exe + `data/` (flutter assets) at root, `backend/` = PyInstaller onedir with backend exe named `夜星视频下载器后端.exe` (`backend.spec` is git-tracked; Flutter `_findBackendExe` accepts new + legacy `backend.exe`), ffmpeg.exe + qjs.exe inside `_internal`, 启动.bat + 说明.txt at root. **The packaged app's live data dir is `<approot>/Volume/`** (migrated from the previous release dir on rebuild); `_internal/Volume` is a stale legacy copy - the zip excludes both.

## Conventions & Gotchas

- Python version is strict. `pyproject.toml:10` `requires-python = ">=3.12,<3.13"`; `.venv` launcher may point to missing interpreter - verify with `python --version` before use.
- `Volume/settings.json` missing keys are auto-patched via `Settings.__check:178`; corrupted JSON falls back to defaults without crash.
- `POST /settings` (upstream) only mutates in-memory `Parameter`, not file. GUI uses `POST /api/gui/settings` which does `Parameter.set_settings_data` + `Settings.update` for persistence.
- Windows cookie read via `rookiepy` needs admin + browser closed for Chromium; `src/tools/browser.py:152` adds Safari on darwin, drops OperaGX on linux.
- Event loop: `test_webui.py:7` and `gui/backend.py` set `WindowsSelectorEventLoopPolicy` on `win32` - keep for any headless server start, otherwise `ProactorEventLoop` breaks `aiosqlite`.
- `gui/backend.py` (frozen) sets `PROJECT_ROOT = DOUK_HOME` (Flutter passes app root) else exe dir, inserts it in `sys.path`, `os.chdir`s there. **The packaged app's live data dir is `<approot>/Volume/`** (settings.json, `yexing-video-downloader.db`, cookies, downloads) — `backend\_internal\Volume` is a stale legacy copy, do not trust it for state checks; both are excluded from the dist zip and the release dir is migrated forward by `build_release.py`.
- GUI backend picks random free port via `ServerSocket.bind(0)`; Flutter `_findBackendExe` prefers `backend\夜星视频下载器后端.exe` (accepts legacy `backend.exe`), falls back to `python gui/backend.py`. Parent-death watcher (`backend.py`) `os.read`es the stdin pipe and `os._exit(0)` on EOF.
- In-app update (v5.9): `GET /api/gui/update/check` tries the GitHub API `releases/latest`, and on ANY failure (the anonymous API is rate-limited per IP — shared proxy exits hit 403 constantly) falls back to fetching `RELEASES` (= the `releases/latest` page) and parsing the tag from the redirect URL; zip URL is constructed from the fixed asset-name rule `yexing-video-downloader_v{tag}.zip` (GitHub strips non-ASCII from asset names, so Chinese asset names are impossible). `POST /api/gui/update/download` accepts only URLs under the repo's `releases/download/` prefix, streams the zip to ~/Downloads as an `update` task and opens Explorer on finish. Repo is **public**; publish a new version: `build_release.py --zip` -> upload the zip via REST API (`gh` CLI unusable - the stored token lacks `read:org`; use `git credential fill` for the token + proxy `-x http://127.0.0.1:7890`) -> verify the constructed download URL with an anonymous HEAD.
- **Never enable `MigrateFolder` in the GUI backend**: `check_settings` calls it unless `TikTokDownloader.skip_folder_migration` (set True in `gui/backend.py`). Root `data/` is Flutter assets; the upstream migration would move it into `Volume/Data` and crash on fresh machines (release ships no `Volume/`).
- YouTube/B站: `yt-dlp-ejs` (JS challenge solver scripts) is a hard dep and needs a JS runtime to solve challenges; since 5.8.2 quickjs-ng `qjs.exe` is bundled into `_internal` (source: git-tracked `vendor/qjs/qjs.exe`) and `find_qjs()` passes an explicit `{"path": ...}` into `js_runtimes["quickjs"]` because yt-dlp's `_find_exe` never searches `_MEIPASS`. Priority deno>node>quickjs>bun, so machines with Node are unaffected. On bot-check (`_is_bot_check`), both preview and download rotate `_FALLBACK_CLIENTS` unconditionally - never gate on cookie-file presence again (that was the "import cookie forever fails" bug). `_friendly_error` first checks the `_RUNTIME_MISSING` flag (set by `_YtdlpLogger` when yt-dlp warns about a missing runtime) and only then branches on cookie-file presence - a runtime-missing failure must NOT be reported as IP 风控. Testing note: without a valid cookie the current proxy IPs are bot-checked regardless of runtime; refresh `Volume/cache/ytdlp_cookies_youtube.txt` via rookiepy from Edge before comparing runtimes.
- `GET /api/gui/thumbnail` proxies images through urllib (NOT httpx - urllib picks up the Windows registry system proxy, which is how i.ytimg.com is reachable); blocks non-global IPs; frontend uses it only for `platform == 'youtube'`.
- ffmpeg lookup order: `DOUK_HOME` -> exe dir -> exe parent -> `_MEIPASS` (bundled via spec `binaries` from `vendor/ffmpeg/`) -> PATH.
- Zip packaging trap: never blanket-exclude `*.zip` when assembling the dist zip - `_internal/base_library.zip` is the Python stdlib; excluding it makes every fresh extraction die with `init_fs_encoding / No module named 'encodings'` while the dev machine's release dir works fine. `build_release.py --zip` ends with an extract-and-boot smoke test that catches this class; trust it over manual dev-dir testing.
- Test habit: simulate a fresh machine (copy release content WITHOUT `Volume/`, boot `backend\backend.exe`, poll `/api/gui/health`) - dev `Volume/` silently skips migration/compat code paths; backend cold start can exceed 12s.
- Task bug history: handler named `create_task` shadowed `asyncio.create_task` inside `setup_gui_routes` - must use alias `aio_create_task`.
- Flutter UI conventions (v5.9): task cards (`lib/pages/tasks_page.dart`) show `TaskInfo.title` (video title, fallback message/label) as the headline with a `PlatformBadge` (`lib/widgets/platform_badge.dart` - platform colors/icons map, TikTok switches to cyan in dark mode) plus a determinate progress bar with percent/speed/ETA when `progress.total > 0`. The cookie banner (`home_shell.dart`) renders four per-platform chips from `/api/gui/cookie/status`'s `platforms` field and hides only when all four are imported. Backend feeds titles/platform via `TaskManager.create(..., title=, platform=)` + `set_meta`; download progress via `set_progress(..., speed=, eta=)`.
- Flutter theme: `gui/flutter_app/lib/services/theme_controller.dart` persists `ThemeMode` (`system` default) via `shared_preferences_windows`; `lib/main.dart` wraps `MaterialApp` in `ListenableBuilder`.
- Lint before commit: `ruff` is sole formatter. No `mypy`/`pytest` config beyond `pyproject.toml`.
- Branch workflow: this fork pushes directly to `main`; commit `<type>: <desc>`.
- Repo layout was reorganized in 5.9.1 (2026-08): deleted `Dockerfile`, `README_EN.md`, upstream `backend_of.spec`, empty edition placeholders, upstream docs/ads/QR codes in `docs/` (kept `Cookie获取教程.md` + its screenshots), 5 of 6 GitHub workflows (only `Close_Stale_Issues_and_PRs.yaml` remains), `license` renamed to `LICENSE`, `release_body.md` tracked as release-notes template, `说明.txt` now lives at repo root and is copied into the release dir by `build_release.py`. `backend.spec` is git-tracked (previously gitignored) so a clean clone can package.
- `.github/workflows/` - only `Close_Stale_Issues_and_PRs.yaml` (manages stale issues/PRs on the public repo). The five upstream build/docker workflows were deleted - they either never ran on this fork (upstream-guarded) or built the old CLI `main.py` exe; releases are built locally via `build_release.py` only.

## References

- Runtime docs: `README.md` (rewritten for this fork), `docs/Cookie获取教程.md`
- Public repo & releases (in-app update source): `https://github.com/hoshino-sys/douyin-video-downloader` / `.../releases/latest`
- Release layout & packaging rules: this file's Structure/Gotchas + `build_release.py` docstring
