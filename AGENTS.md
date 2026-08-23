# AGENTS.md - 抖音视频下载 (douyin-video-downloader)

> Stack: Python 3.12 (hard cap `<3.13`), FastAPI + uvicorn, httpx, aiosqlite, Flutter 3.47/Dart 3.13 (Windows desktop). Entrypoint `main.py` -> `src/application/TikTokDownloader.py`. Original: DouK-Downloader / TikTokDownloader.

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
```

## Structure

- `main.py` / `src/application/TikTokDownloader.py:49` - orchestrator, owns `Settings` + `Parameter` + `Database`. `run()` = `project_info -> check_config -> check_settings -> disclaimer -> main_menu`.
- `src/application/main_terminal.py:119` - `TikTok` class, all download flows (`deal_account_detail:538`, `deal_mix_detail:1653`, `downloader.run`).
- `src/application/main_server.py:66` - `APIServer(TikTok)`, FastAPI on `SERVER_HOST:SERVER_PORT` (`0.0.0.0:5555` in `src/custom/static.py:10`, GUI backend rebinds to `127.0.0.1`). Docs at `/docs` `/redoc`.
- `gui/` - new GUI backend. `gui/backend.py` = headless `GuiAPIServer(APIServer)` on dynamic port; `gui/api_ext.py` = `/api/gui/*` (health/bootstrap/cookie/browsers/task/settings + TaskManager). `gui/flutter_app/lib/*` = Flutter app. Empty placeholders: `src/tui_edition/`, `src/cli_edition/`, `src/gui_edition/` - ignore.
- `src/config/settings.py:164` - reads/writes `Volume/settings.json` (UTF-8-SIG on Windows), auto-creates with defaults, `__check` fills missing keys. `src/config/parameter.py:114` - runtime validator/normalizer.
- `src/interface/template.py:103` - base `API.run()` pagination loop; subclasses `Account/Mix/Detail/Live/Comment/Search/Hot` map 1:1 to endpoints. Callable via `Params` (`src/testers/params.py`) + `Volume/test_cookie.ini`.
- `src/custom/internal.py:3` - `PROJECT_ROOT = <repo>/Volume` (auto mkdir), version `5.8.beta`, `DISCLAIMER_TEXT`.
- `src/downloader/download.py:150` / `src/extract/` / `src/encrypt/` / `src/storage/` - fetch -> extract -> download -> persist.
- `Volume/` - runtime, gitignored. `settings.json`, `DouK-Downloader.db` (tables `config_data`/`download_data`/`option_data`, key `Disclaimer`), `DouK-Downloader.log`, `cache/`. Don't commit.
- `Dockerfile` - multi-stage `python:3.12-bullseye` builder -> `slim`, volume `/app/Volume`, port `5555`.
- `.github/workflows/` - 6 workflows; build exe via `Manually_build_executable_programs.yml` (`pyinstaller --collect-all emoji main.py`).

## Conventions & Gotchas

- Python version is strict. `pyproject.toml:10` `requires-python = ">=3.12,<3.13"`; `.venv` launcher may point to missing interpreter - verify with `python --version` before use.
- `Volume/settings.json` missing keys are auto-patched via `Settings.__check:178`; corrupted JSON falls back to defaults without crash.
- `POST /settings` (upstream) only mutates in-memory `Parameter`, not file. GUI uses `POST /api/gui/settings` which does `Parameter.set_settings_data` + `Settings.update` for persistence.
- Windows cookie read via `rookiepy` needs admin + browser closed for Chromium; `src/tools/browser.py:152` adds Safari on darwin, drops OperaGX on linux.
- Event loop: `test_webui.py:7` and `gui/backend.py` set `WindowsSelectorEventLoopPolicy` on `win32` - keep for any headless server start, otherwise `ProactorEventLoop` breaks `aiosqlite`.
- `gui/backend.py` must `os.chdir(PROJECT_ROOT.parent)` and fix `src/web_ui/static` mount guard (`Path("src/web_ui/static").exists()`), else `RuntimeError: Directory does not exist`.
- GUI backend picks random free port via `ServerSocket.bind(0)`, Flutter discovers via `BackendProcess._findBackendScript` walking up from exe to repo root for `gui/backend.py` and via `DOUK_BACKEND` env. Parent-death watcher reads `stdin` pipe -> `os._exit(0)`.
- Task bug history: handler named `create_task` shadowed `asyncio.create_task` inside `setup_gui_routes` - must use alias `aio_create_task`.
- Flutter theme: `gui/flutter_app/lib/services/theme_controller.dart` persists `ThemeMode` (`system` default) via `shared_preferences_windows`; `lib/main.dart` wraps `MaterialApp` in `ListenableBuilder`.
- Lint before commit: `ruff` is sole formatter. No `mypy`/`pytest` config beyond `pyproject.toml`.
- Branch workflow: PRs target `develop`, not `master` (see README contribution guide); commit `<type>: <desc>`.

## References

- Runtime docs: `README.md` (CN), `README_EN.md`, `docs/Cookie获取教程.md`
- API example: `README.md:104`
- Wiki: `https://github.com/JoeanAmier/TikTokDownloader/wiki/Documentation`
