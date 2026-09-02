"""夜星视频下载器 一键打包脚本。

用法（在仓库根目录）:
    D:/Python 3.12/python.exe build_release.py [--zip]

流程: 前置检查 → PyInstaller 后端 → Flutter 前端 → 组装 release 目录
（保留 backend/_internal/{UserData,Volume} 用户数据）→ 同步回退源码
→ 可选生成干净分发包 → 清理旧版本产物。

分发包自动排除: 根 Volume/（旧版数据目录）、UserData/、Downloads/（本机
下载与设置）、backend/_internal/{UserData,Volume}/、__pycache__、旧 zip，
避免把个人数据发给别人。
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
RELEASE_DIR_NAME = "夜星视频下载器_v5.9.3"
REL = ROOT / "release" / RELEASE_DIR_NAME
DIST_BACKEND = ROOT / "dist" / "夜星视频下载器后端"
FLUTTER_RELEASE = (
    ROOT / "gui" / "flutter_app" / "build" / "windows" / "x64" / "runner" / "Release"
)
VENDOR_FFMPEG = ROOT / "vendor" / "ffmpeg"
VENDOR_QJS = ROOT / "vendor" / "qjs" / "qjs.exe"
APP_EXE = "夜星视频下载器.exe"
BACKEND_EXE = "夜星视频下载器后端.exe"
LEGACY_BACKEND_EXES = ("backend.exe",)  # 旧版本包内的后端进程名，防漏杀

# 前端文件改名映射（douk_gui.exe → 夜星视频下载器.exe）
FRONTEND_RENAME = {"douk_gui.exe": APP_EXE}

# 回退源码同步（发布包内散装 Python 源码，无 backend.exe 时走系统 Python）
SOURCE_SYNC_DIRS = ("src", "static", "locale")


def log(text: str) -> None:
    print(text, flush=True)


def fail(text: str) -> None:
    log(f"[错误] {text}")
    sys.exit(1)


def check_no_running() -> None:
    """仅拦截运行在本仓库 release/dist 目录里的实例；用户自己另装副本不受影响。"""
    try:
        result = subprocess.run(
            [
                "powershell",
                "-NoProfile",
                "-Command",
                "Get-Process | Where-Object { $_.Path } "
                "| ForEach-Object { $_.Path.ToLower() }",
            ],
            capture_output=True,
            timeout=30,
        )
        paths = result.stdout.decode("utf-8", errors="ignore").splitlines()
    except Exception:
        paths = []
    prefixes = tuple(
        str(ROOT / name).lower().rstrip("\\") + os.sep
        for name in ("release", "dist", os.path.join("gui", "flutter_app", "build"))
    )
    locked = sorted({p for p in paths if p.startswith(prefixes)})
    if locked:
        fail("以下进程正在使用构建目录，请先退出应用再打包：\n  " + "\n  ".join(locked))


def _release_version_key(p: Path) -> tuple[int, ...]:
    m = re.search(r"v(\d+(?:\.\d+)*)", p.name)
    return tuple(int(x) for x in m.group(1).split(".")) if m else (0,)


def bootstrap_release_dir() -> None:
    """发布目录尚不存在时，从旧版本目录整体迁移（保留用户数据）。

    版本号按数字比较取最新：字符串排序在 v5.10 会排在 v5.9 之前。"""
    if REL.exists():
        return
    candidates = sorted(
        (p for p in REL.parent.glob("夜星视频下载器_v5.*") if p.is_dir()),
        key=_release_version_key,
    )
    if not candidates:
        fail(f"未找到发布目录 {REL}，也没有可迁移的旧版发布目录")
    src = candidates[-1]
    log(f"从旧版发布目录迁移：{src.name} → {RELEASE_DIR_NAME}")
    shutil.copytree(src, REL)


def ensure_vendor_ffmpeg() -> None:
    if (VENDOR_FFMPEG / "ffmpeg.exe").exists():
        return
    # 救援源按优先级：旧版发布根（v5.9.2 前布局）、发布包 backend/_internal
    # （v5.9.3 起发布包只保留 _internal 一份，发布根不再复制）
    for legacy in (REL / "ffmpeg.exe", REL / "backend" / "_internal" / "ffmpeg.exe"):
        if not legacy.exists():
            continue
        VENDOR_FFMPEG.mkdir(parents=True, exist_ok=True)
        for name in ("ffmpeg.exe", "ffprobe.exe"):
            src = legacy.parent / name
            if src.exists():
                shutil.copy2(src, VENDOR_FFMPEG / name)
        log(f"已从 {legacy.parent} 复制 ffmpeg 到 vendor/ffmpeg/")
        return
    fail("缺少 vendor/ffmpeg/ffmpeg.exe（音视频合并必需），请先放置该文件")


def ensure_vendor_qjs() -> None:
    if VENDOR_QJS.exists():
        return
    fail(
        "缺少 vendor/qjs/qjs.exe（内置 JS 运行时，新电脑解析 YouTube 必需）。"
        "请从 https://github.com/quickjs-ng/quickjs/releases 下载"
        " qjs-windows-x86_64.exe 并改名为 qjs.exe 放入 vendor/qjs/"
    )


def build_backend() -> None:
    log("== [1/4] PyInstaller 构建后端…")
    result = subprocess.run(
        [sys.executable, "-m", "PyInstaller", "backend.spec", "--noconfirm"],
        cwd=ROOT,
    )
    if result.returncode != 0 or not (DIST_BACKEND / BACKEND_EXE).exists():
        fail("后端构建失败")
    internal = DIST_BACKEND / "_internal"
    if not (internal / "yt_dlp_ejs").exists():
        fail("后端产物缺少 yt_dlp_ejs（JS 挑战求解脚本），请检查 backend.spec")
    if not (internal / "qjs.exe").exists():
        fail(
            "后端产物缺少 qjs.exe（内置 JS 运行时），"
            "无 node/deno 的电脑将无法解析 YouTube，请检查 backend.spec"
        )
    if not (internal / "ffmpeg.exe").exists():
        log(
            "[警告] 后端产物未内置 ffmpeg.exe（_MEIPASS 兜底不可用，将无法自动合并音视频）"
        )


def build_frontend() -> None:
    log("== [2/4] Flutter 构建前端…")
    flutter = shutil.which("flutter")
    if not flutter:
        fail("未找到 flutter 命令，请确认 Flutter 已安装并在 PATH 中")
    result = subprocess.run(
        [flutter, "build", "windows", "--release"],
        cwd=ROOT / "gui" / "flutter_app",
    )
    if result.returncode != 0 or not (FLUTTER_RELEASE / "douk_gui.exe").exists():
        fail("前端构建失败")


def assemble_backend() -> None:
    log("== [3/4] 组装发布包…")
    backend_dir = REL / "backend"
    backend_dir.mkdir(parents=True, exist_ok=True)
    # 保留用户数据（设置/Cookie/数据库）；UserData 为现名，Volume 为旧版遗留
    saved = []
    for name in ("UserData", "Volume"):
        volume = backend_dir / "_internal" / name
        if volume.exists():
            bak = backend_dir / f"{name}_bak"
            shutil.move(str(volume), str(bak))
            saved.append((volume, bak))
    try:
        shutil.rmtree(backend_dir / "_internal", ignore_errors=True)
        shutil.copytree(DIST_BACKEND / "_internal", backend_dir / "_internal")
    finally:
        for volume, bak in saved:
            if volume.exists():
                shutil.rmtree(bak, ignore_errors=True)
            else:
                shutil.move(str(bak), str(volume))
    shutil.copy2(DIST_BACKEND / BACKEND_EXE, backend_dir / BACKEND_EXE)
    # 清理旧版后端进程文件，避免包内残留两份后端
    for legacy in ("backend.exe", "backend"):
        legacy_path = backend_dir / legacy
        if legacy_path.exists():
            legacy_path.unlink()


def write_launch_bat() -> None:
    bat = REL / "启动.bat"
    content = "\r\n".join(
        [
            "@echo off",
            "chcp 65001 >nul",
            "echo 正在启动 夜星视频下载器...",
            f'if not exist "backend\\{BACKEND_EXE}" (',
            "  echo 未找到内置后端，尝试使用 Python 后端...",
            "  python --version >nul 2>&1",
            "  if errorlevel 1 (",
            "    echo [错误] 未找到内置后端与 Python 3.12，请先安装 Python 3.12 并添加到 PATH",
            "    echo 下载地址: https://www.python.org/downloads/",
            "    pause",
            "    exit /b",
            "  )",
            ")",
            f'start "" "{APP_EXE}"',
            "",
        ]
    )
    bat.write_text(content, encoding="utf-8-sig", newline="\r\n")


def write_readme_txt() -> None:
    # 说明.txt 单一来源在仓库根，组装时转 utf-8-sig/CRLF 复制进发布目录
    src = ROOT / "说明.txt"
    if not src.exists():
        log("警告: 仓库根缺少 说明.txt，发布目录将沿用旧文件")
        return
    text = src.read_text(encoding="utf-8-sig")
    (REL / "说明.txt").write_text(text, encoding="utf-8-sig", newline="\r\n")


def assemble_frontend() -> None:
    for item in FLUTTER_RELEASE.iterdir():
        if item.is_dir():
            if item.name == "data":
                dest = REL / "data"
                shutil.rmtree(dest, ignore_errors=True)
                shutil.copytree(item, dest)
            continue
        dest_name = FRONTEND_RENAME.get(item.name, item.name)
        shutil.copy2(item, REL / dest_name)


def sync_fallback_sources() -> None:
    gui_dest = REL / "gui"
    gui_dest.mkdir(exist_ok=True)
    shutil.rmtree(gui_dest / "__pycache__", ignore_errors=True)
    for py in (ROOT / "gui").glob("*.py"):
        shutil.copy2(py, gui_dest / py.name)
    for name in SOURCE_SYNC_DIRS:
        src = ROOT / name
        if src.exists():
            shutil.copytree(src, REL / name, dirs_exist_ok=True)


def make_zip() -> None:
    log("== [5/6] 生成全量分发包…")
    # 注意不能用 with_suffix：目录名含点（_v5.8）会被截断成 _v5.zip
    zip_path = REL.parent / (REL.name + ".zip")
    if zip_path.exists():
        zip_path.unlink()
    # 排除本机个人数据与构建残留：UserData/Downloads 为现数据目录，
    # Volume 为旧版数据目录（bootstrap 迁移前仍在），三者都必须排除
    exclude_prefixes = (
        REL / "UserData",
        REL / "Downloads",
        REL / "Volume",
        REL / "backend" / "_internal" / "UserData",
        REL / "backend" / "_internal" / "Volume",
    )
    exclude_names = {"__pycache__", ".DS_Store", "Thumbs.db"}

    def skip(path: Path) -> bool:
        if any(path == p or p in path.parents for p in exclude_prefixes):
            return True
        return path.name in exclude_names

    count = 0
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
        for path in sorted(REL.rglob("*")):
            # 仅排除发布根目录的杂散 zip（分发 zip 自身在 REL 外）。
            # 不能一刀切排除 *.zip：backend/_internal/base_library.zip 是
            # Python 标准库，缺了它解压出来必然 init_fs_encoding 崩溃
            if skip(path) or (path.parent == REL and path.suffix == ".zip"):
                continue
            if path.is_file():
                zf.write(path, path.relative_to(REL.parent))
                count += 1
    size_mb = zip_path.stat().st_size / 1024 / 1024
    with zipfile.ZipFile(zip_path) as zf:  # 完整性校验，防止生成损坏的分发包
        if zf.testzip() is not None:
            zip_path.unlink(missing_ok=True)
            fail("分发包 CRC 校验失败，已删除，请重新运行 --zip")
    log(
        f"分发包: {zip_path}（{count} 个文件, {size_mb:.0f} MB, 已排除本机 Cookie/设置/下载，CRC 校验通过）"
    )


def verify_zip(zip_path: Path) -> None:
    """冒烟测试：解压到临时目录（模拟用户新机器首次启动），确认后端可就绪。"""
    import tempfile
    import time
    import urllib.request

    log("== [6/6] 全量包冒烟测试（解压并启动后端）…")
    with tempfile.TemporaryDirectory(
        prefix="douk_zip_smoke_", ignore_cleanup_errors=True
    ) as tmp:
        with zipfile.ZipFile(zip_path) as zf:
            zf.extractall(tmp)
        backend_exe = Path(tmp) / RELEASE_DIR_NAME / "backend" / BACKEND_EXE
        if not backend_exe.exists():
            fail(f"冒烟测试失败：解压后缺少 backend/{BACKEND_EXE}")
        if not (backend_exe.parent / "_internal" / "base_library.zip").exists():
            fail("冒烟测试失败：解压后缺少 base_library.zip（Python 标准库）")
        env = {**os.environ, "DOUK_HOME": str(backend_exe.parent.parent)}
        for key in ("HTTP_PROXY", "HTTPS_PROXY", "http_proxy", "https_proxy"):
            env.pop(key, None)  # 模拟无代理的纯净环境
        proc = subprocess.Popen(
            [str(backend_exe), "--host", "127.0.0.1", "--port", "5595"],
            cwd=backend_exe.parent,
            env=env,
            stdin=subprocess.PIPE,  # 保持管道打开，等效 Flutter 启动方式
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        try:
            deadline = time.time() + 90
            healthy = False
            while time.time() < deadline:
                if proc.poll() is not None:
                    fail(f"冒烟测试失败：后端启动即退出（代码 {proc.returncode}）")
                try:
                    with urllib.request.urlopen(
                        "http://127.0.0.1:5595/api/gui/health", timeout=2
                    ) as resp:
                        if resp.status == 200:
                            healthy = True
                            break
                except Exception:
                    time.sleep(1)
            if not healthy:
                fail("冒烟测试失败：后端 90 秒内未就绪")
            log("冒烟测试通过：分发包解压后后端可正常启动")
        finally:
            proc.kill()
            try:
                proc.wait(timeout=10)
            except Exception:
                pass


def cleanup_old_releases(keep_patch: Path | None = None) -> None:
    """发布成功后清理旧版本产物（保留当前版本目录、zip 与本次增量补丁）。

    注意：清理后 find_previous_release() 将找不到基准，因此增量补丁
    （make_patch_zip/verify_patch）必须在本次调用之前完成。"""
    keep_zip = REL.parent / (REL.name + ".zip")
    removed = []
    for p in REL.parent.iterdir():
        if p == REL or p == keep_zip or p == keep_patch:
            continue
        if p.name.startswith("夜星视频下载器_patch_") or p.name.startswith(
            "夜星视频下载器_v5."
        ):
            pass
        else:
            continue
        try:
            if p.is_dir():
                shutil.rmtree(p, ignore_errors=True)
            else:
                p.unlink()
            removed.append(p.name)
        except OSError:
            pass
    if removed:
        log("已清理旧版本产物：" + "、".join(removed))


def _release_version_text(p: Path) -> str:
    m = re.search(r"_v(\d+(?:\.\d+)*)", p.name)
    return m.group(1) if m else ""


def find_previous_release() -> Path | None:
    """增量补丁基准：当前版本之外最新的旧版本发布目录（数字比较）。"""
    candidates = sorted(
        (p for p in REL.parent.glob("夜星视频下载器_v5.*") if p.is_dir() and p != REL),
        key=_release_version_key,
    )
    return candidates[-1] if candidates else None


_PATCH_EXCLUDE_TOP = ("UserData", "Downloads", "Volume")
_PATCH_EXCLUDE_NAMES = {"__pycache__", ".DS_Store", "Thumbs.db"}


def _patch_skip(path: Path, base: Path) -> bool:
    """补丁 diff 范围排除：本机数据目录（新旧布局）与杂散 zip。"""
    rel = path.relative_to(base)
    if rel.parts and rel.parts[0] in _PATCH_EXCLUDE_TOP:
        return True
    if (
        len(rel.parts) >= 3
        and rel.parts[:2] == ("backend", "_internal")
        and rel.parts[2] in ("UserData", "Volume")
    ):
        return True
    if path.name in _PATCH_EXCLUDE_NAMES:
        return True
    if path.parent == base and path.suffix == ".zip":
        return True
    return False


def make_patch_zip() -> Path | None:
    """与上一版本发布目录逐文件 diff，生成只含变更文件的增量补丁包。

    补丁 zip 内不带顶层文件夹（解压即覆盖安装目录），附 补丁说明.txt、
    removed.txt 与可选的 清理已移除文件.bat。"""
    import hashlib

    log("== [4/6] 生成增量补丁包（与上一版 diff）…")
    prev = find_previous_release()
    if prev is None:
        log("[提示] 未找到上一版本发布目录，本次仅发布全量包")
        return None
    prev_version = _release_version_text(prev)
    new_version = _release_version_text(REL)
    if not prev_version or prev_version == new_version:
        log("[提示] 补丁基准版本无效，跳过增量补丁")
        return None

    def digest(path: Path) -> str:
        h = hashlib.sha256()
        with path.open("rb") as f:
            for block in iter(lambda: f.read(1024 * 1024), b""):
                h.update(block)
        return h.hexdigest()

    old_files = {
        p.relative_to(prev).as_posix(): p
        for p in prev.rglob("*")
        if p.is_file() and not _patch_skip(p, prev)
    }
    changed = []
    new_rels = set()
    for path in sorted(REL.rglob("*")):
        if not path.is_file() or _patch_skip(path, REL):
            continue
        rel = path.relative_to(REL).as_posix()
        new_rels.add(rel)
        old = old_files.get(rel)
        if old is None:
            changed.append(path)
        elif old.stat().st_size != path.stat().st_size or digest(old) != digest(path):
            changed.append(path)
    removed = sorted(set(old_files) - new_rels)
    if not changed and not removed:
        log("[提示] 与上一版无文件差异，跳过增量补丁")
        return None

    patch_path = REL.parent / f"夜星视频下载器_patch_v{prev_version}_v{new_version}.zip"
    if patch_path.exists():
        patch_path.unlink()
    with zipfile.ZipFile(patch_path, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        for path in changed:
            zf.write(path, path.relative_to(REL))
        if removed:
            zf.writestr("removed.txt", "\n".join(removed) + "\n")
            zf.writestr("清理已移除文件.bat", _PATCH_CLEANUP_BAT)
        zf.writestr(
            "补丁说明.txt",
            _patch_note_text(prev_version, new_version, len(changed), removed),
        )
    size_mb = patch_path.stat().st_size / 1024 / 1024
    log(
        f"增量补丁包: {patch_path.name}"
        f"（变更 {len(changed)} 个文件, 移除 {len(removed)} 个, {size_mb:.1f} MB）"
    )
    return patch_path


_PATCH_CLEANUP_BAT = "\r\n".join(
    [
        "@echo off",
        "chcp 65001 >nul",
        "echo 按补丁清单清理新版本已移除的旧文件…",
        "powershell -NoProfile -ExecutionPolicy Bypass -Command "
        "\"Get-Content -LiteralPath 'removed.txt' -Encoding UTF8 | "
        "ForEach-Object { $p = $_.Trim(); if ($p -and "
        "(Test-Path -LiteralPath $p)) { Remove-Item -LiteralPath $p -Force; "
        "Write-Host ('已删除 ' + $p) } }\"",
        "echo 清理完成。",
        "pause",
        "",
    ]
)


def _patch_note_text(
    prev_version: str, new_version: str, changed: int, removed: list[str]
) -> str:
    lines = [
        f"夜星视频下载器 增量更新补丁 v{prev_version} → v{new_version}",
        "=" * 46,
        "",
        f"本补丁只包含与 v{prev_version} 有差异的文件（共 {changed} 个），"
        "远小于完整安装包。",
        "",
        "使用方法：",
        "1. 退出正在运行的 夜星视频下载器",
        "2. 将本压缩包中的全部文件解压到软件安装目录，选择「替换目标中的文件」",
    ]
    if removed:
        lines.append(
            "3. 双击运行「清理已移除文件.bat」，删除本版本不再需要的旧文件"
            f"（共 {len(removed)} 个）"
        )
        lines.append("4. 重新启动 夜星视频下载器.exe，在 设置-关于 中确认版本已更新")
    else:
        lines.append("3. 重新启动 夜星视频下载器.exe，在 设置-关于 中确认版本已更新")
    lines += [
        "",
        f"注意：本补丁仅适用于从 v{prev_version} 升级；更旧的版本请下载完整安装包。",
        "UserData 与 Downloads 数据目录不受影响。",
        "",
    ]
    return "\n".join(lines)


def verify_patch(patch_path: Path) -> None:
    """补丁端到端验证：上一版完整安装副本 + 补丁 → 启动 → 确认版本升级。

    基准优先用上一版分发 zip（等同用户手里的安装包，含发布根 ffmpeg 的
    旧布局），没有 zip 时复制上一版目录（排除数据目录）。"""
    import json
    import tempfile
    import time
    import urllib.request

    prev = find_previous_release()
    if prev is None:
        log("[提示] 无上一版目录，跳过补丁端到端验证")
        return
    new_version = _release_version_text(REL)
    log(f"== 补丁端到端验证（{prev.name} + 补丁 → 应升级为 v{new_version}）…")
    with tempfile.TemporaryDirectory(
        prefix="douk_patch_smoke_", ignore_cleanup_errors=True
    ) as tmp:
        prev_zip = REL.parent / (prev.name + ".zip")
        if prev_zip.exists():
            with zipfile.ZipFile(prev_zip) as zf:
                zf.extractall(tmp)
            base = Path(tmp) / prev.name
        else:
            base = Path(tmp) / prev.name
            shutil.copytree(
                prev,
                base,
                ignore=shutil.ignore_patterns(
                    "UserData", "Downloads", "Volume", "__pycache__"
                ),
            )
        with zipfile.ZipFile(patch_path) as zf:
            zf.extractall(base)
        backend_exe = base / "backend" / BACKEND_EXE
        if not backend_exe.exists():
            fail("补丁验证失败：应用补丁后缺少后端文件")
        env = {**os.environ, "DOUK_HOME": str(base)}
        for key in ("HTTP_PROXY", "HTTPS_PROXY", "http_proxy", "https_proxy"):
            env.pop(key, None)
        proc = subprocess.Popen(
            [str(backend_exe), "--host", "127.0.0.1", "--port", "5596"],
            cwd=backend_exe.parent,
            env=env,
            stdin=subprocess.PIPE,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        try:
            deadline = time.time() + 90
            version = ""
            while time.time() < deadline:
                if proc.poll() is not None:
                    fail(f"补丁验证失败：后端启动即退出（代码 {proc.returncode}）")
                try:
                    with urllib.request.urlopen(
                        "http://127.0.0.1:5596/api/gui/health", timeout=2
                    ) as resp:
                        data = json.loads(resp.read() or b"{}")
                        version = str(data.get("version") or "")
                        if resp.status == 200 and version:
                            break
                except Exception:
                    pass
                time.sleep(1)
            if version != new_version:
                fail(
                    f"补丁验证失败：健康检查版本为 {version or '无'}，"
                    f"应为 {new_version}"
                )
            log(f"补丁验证通过：上一版副本应用补丁后运行版本 v{version}")
        finally:
            proc.kill()
            try:
                proc.wait(timeout=10)
            except Exception:
                pass


def main() -> None:
    parser = argparse.ArgumentParser(description="夜星视频下载器 打包脚本")
    parser.add_argument(
        "--zip", action="store_true", help="生成干净分发包（排除个人数据）"
    )
    args = parser.parse_args()

    if os.name == "nt":
        try:
            sys.stdout.reconfigure(encoding="utf-8")
        except Exception:
            pass

    if not REL.exists() and not any(REL.parent.glob("夜星视频下载器_v5.*")):
        fail(f"未找到发布目录 {REL}")
    check_no_running()
    bootstrap_release_dir()
    ensure_vendor_ffmpeg()
    ensure_vendor_qjs()
    build_backend()
    build_frontend()
    assemble_backend()
    assemble_frontend()
    sync_fallback_sources()
    write_launch_bat()
    write_readme_txt()
    log(f"打包完成: {REL}")
    if args.zip:
        patch = make_patch_zip()
        make_zip()
        verify_zip(REL.parent / (REL.name + ".zip"))
        if patch is not None:
            verify_patch(patch)
        cleanup_old_releases(keep_patch=patch)


if __name__ == "__main__":
    main()
