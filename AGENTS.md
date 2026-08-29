# AGENTS.md - 抖音视频下载 (douyin-video-downloader)

> Stack: Python 3.12 (hard cap `<3.13`), FastAPI + uvicorn, httpx, aiosqlite, yt-dlp + yt-dlp-ejs (B站/YouTube), Flutter 3.47/Dart 3.13 (Windows desktop). Entrypoint `main.py` -> `src/application/TikTokDownloader.py`. Fork of DouK-Downloader / TikTokDownloader, rebranded 夜星视频下载器, version `5.9.0` (`src/custom/internal.py`).

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
- `gui/` - new GUI backend. `gui/backend.py` = headless `GuiAPIServer(APIServer)` on dynamic port; `gui/api_ext.py` = `/api/gui/*` (health/bootstrap/cookie 分平台 status/browsers/task/settings/thumbnail/update check+download + TaskManager). `gui/platforms_yt.py` = B站/YouTube engine on yt-dlp (detect_platform/extract_preview/run_ytdlp_download/save_platform_cookie/find_ffmpeg/find_qjs/platform_cookie_states). `gui/flutter_app/lib/*` = Flutter app. Empty placeholders: `src/tui_edition/`, `src/cli_edition/`, `src/gui_edition/` - ignore.
- `src/config/settings.py:164` - reads/writes `Volume/settings.json` (UTF-8-SIG on Windows), auto-creates with defaults, `__check` fills missing keys. `src/config/parameter.py:114` - runtime validator/normalizer.
- `src/interface/template.py:103` - base `API.run()` pagination loop; subclasses `Account/Mix/Detail/Live/Comment/Search/Hot` map 1:1 to endpoints. Callable via `Params` (`src/testers/params.py`) + `Volume/test_cookie.ini`.
- `src/custom/internal.py:3` - `PROJECT_ROOT = <repo>/Volume` (auto mkdir), version `5.9.0` (`VERSION_BETA` kept defined=False, imported elsewhere); `RELEASES_API` points at hoshino-sys/douyin-video-downloader for in-app update check, `DISCLAIMER_TEXT`.
- `src/downloader/download.py:150` / `src/extract/` / `src/encrypt/` / `src/storage/` - fetch -> extract -> download -> persist.
- `Volume/` - runtime, gitignored. `settings.json`, `DouK-Downloader.db` (tables `config_data`/`download_data`/`option_data`, key `Disclaimer`), `DouK-Downloader.log`, `cache/`. Don't commit. B站/YouTube cookies live in `Volume/cache/ytdlp_cookies_{bili,youtube}.txt` (Netscape format, written by `save_platform_cookie`, fed to yt-dlp via `cookiefile`).
- `build_release.py` - one-shot packager: precheck (only blocks processes running INSIDE repo release/dist dirs; the user's own installed copy elsewhere is fine) -> `bootstrap_release_dir` (copies newest old `夜星视频下载器_v5.*` dir when the v5.9 dir is missing, preserving user data) -> PyInstaller `backend.spec` -> `flutter build windows --release` -> assemble `release/夜星视频下载器_v5.9/` (syncs loose fallback sources `gui/*.py`, `src/`, `static/`, `locale/`; regenerates 启动.bat) -> `--zip` emits clean dist zip (excludes BOTH `Volume/` at app root AND `backend/_internal/Volume/`) + **extract-and-boot smoke test**. `说明.txt` edits need a `--zip` re-run to land in the dist zip.
- `release/夜星视频下载器_v5.9/` - shipped layout: Flutter exe + `data/` (flutter assets) at root, `backend/` = PyInstaller onedir with backend exe named `夜星视频下载器后端.exe` (`backend.spec`/`backend_of.spec` are gitignored local files; Flutter `_findBackendExe` accepts new + legacy `backend.exe`), ffmpeg.exe + qjs.exe inside `_internal`, 启动.bat at root. **The packaged app's live data dir is `<approot>/Volume/`** (migrated from the previous release dir on rebuild); `_internal/Volume` is a stale legacy copy - the zip excludes both.

## Conventions & Gotchas

- Python version is strict. `pyproject.toml:10` `requires-python = ">=3.12,<3.13"`; `.venv` launcher may point to missing interpreter - verify with `python --version` before use.
- `Volume/settings.json` missing keys are auto-patched via `Settings.__check:178`; corrupted JSON falls back to defaults without crash.
- `POST /settings` (upstream) only mutates in-memory `Parameter`, not file. GUI uses `POST /api/gui/settings` which does `Parameter.set_settings_data` + `Settings.update` for persistence.
- Windows cookie read via `rookiepy` needs admin + browser closed for Chromium; `src/tools/browser.py:152` adds Safari on darwin, drops OperaGX on linux.
- Event loop: `test_webui.py:7` and `gui/backend.py` set `WindowsSelectorEventLoopPolicy` on `win32` - keep for any headless server start, otherwise `ProactorEventLoop` breaks `aiosqlite`.
- `gui/backend.py` (frozen) sets `PROJECT_ROOT = DOUK_HOME` (Flutter passes app root) else exe dir, inserts it in `sys.path`, `os.chdir`s there. Frozen data dir is `backend\_internal\Volume` (`internal.py` derives `PROJECT_ROOT` from `__file__` -> `_internal`) - user settings/Cookies/db live there, NOT at app root; `build_release.py` preserves it when swapping builds.
- GUI backend picks random free port via `ServerSocket.bind(0)`; Flutter prefers `backend\backend.exe` (onedir, passes `DOUK_HOME`) and falls back to `python gui/backend.py`. Parent-death watcher (`backend.py`) `os.read`es the stdin pipe and `os._exit(0)` on EOF - verified working with the renamed `夜星视频下载器后端.exe`. In-app update: `GET /api/gui/update/check` hits GitHub releases/latest (graceful 404 until a release exists; publish with `gh release create v5.9.0 <zip>`), `POST /api/gui/update/download` streams the zip to ~/Downloads as an `update` task and opens Explorer on finish; URL must start with the repo's releases/download prefix.
- **Never enable `MigrateFolder` in the GUI backend**: `check_settings` calls it unless `TikTokDownloader.skip_folder_migration` (set True in `gui/backend.py`). Root `data/` is Flutter assets; the upstream migration would move it into `Volume/Data` and crash on fresh machines (release ships no `Volume/`).
- YouTube/B站: `yt-dlp-ejs` (JS challenge solver scripts) is a hard dep and needs a JS runtime (node/deno/bun) on the machine; `_base_opts` sets `js_runtimes` `{deno,node,bun,quickjs}` because yt-dlp defaults to deno only. On bot-check (`_is_bot_check`), both preview and download rotate `_FALLBACK_CLIENTS` unconditionally - never gate on cookie-file presence again (that was the "import cookie forever fails" bug). `_friendly_error` wording branches on whether the cookie file exists.
- `GET /api/gui/thumbnail` proxies images through urllib (NOT httpx - urllib picks up the Windows registry system proxy, which is how i.ytimg.com is reachable); blocks non-global IPs; frontend uses it only for `platform == 'youtube'`.
- ffmpeg lookup order: `DOUK_HOME` -> exe dir -> exe parent -> `_MEIPASS` (bundled via spec `binaries` from `vendor/ffmpeg/`) -> PATH.
- Zip packaging trap: never blanket-exclude `*.zip` when assembling the dist zip - `_internal/base_library.zip` is the Python stdlib; excluding it makes every fresh extraction die with `init_fs_encoding / No module named 'encodings'` while the dev machine's release dir works fine. `build_release.py --zip` ends with an extract-and-boot smoke test that catches this class; trust it over manual dev-dir testing.
- Test habit: simulate a fresh machine (copy release content WITHOUT `Volume/`, boot `backend\backend.exe`, poll `/api/gui/health`) - dev `Volume/` silently skips migration/compat code paths; backend cold start can exceed 12s.
- Task bug history: handler named `create_task` shadowed `asyncio.create_task` inside `setup_gui_routes` - must use alias `aio_create_task`.
- Flutter theme: `gui/flutter_app/lib/services/theme_controller.dart` persists `ThemeMode` (`system` default) via `shared_preferences_windows`; `lib/main.dart` wraps `MaterialApp` in `ListenableBuilder`.
- Lint before commit: `ruff` is sole formatter. No `mypy`/`pytest` config beyond `pyproject.toml`.
- Branch workflow: PRs target `develop`, not `master` (see README contribution guide); commit `<type>: <desc>`.

- `Dockerfile` - upstream CLI image (multi-stage, port `5555`), unrelated to the GUI release.
- `.github/workflows/` - 6 upstream workflows; `Manually_build_executable_programs.yml` builds the old CLI `main.py` exe, NOT the GUI release - use `build_release.py` instead.

## References

- Runtime docs: `README.md` (CN), `README_EN.md`, `docs/Cookie获取教程.md`
- API example: `README.md:104`
- Wiki: `https://github.com/JoeanAmier/TikTokDownloader/wiki/Documentation`
- Release layout & packaging rules: this file's Structure/Gotchas + `build_release.py` docstring
