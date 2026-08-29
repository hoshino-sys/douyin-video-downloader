"""夜星视频下载器 一键打包脚本。

用法（在仓库根目录）:
    D:/Python 3.12/python.exe build_release.py [--zip]

流程: 前置检查 → PyInstaller 后端 → Flutter 前端 → 组装 release 目录
（保留 backend/_internal/Volume 用户数据）→ 同步回退源码 → 可选生成干净分发包。

分发包自动排除: 根 Volume/（本机下载与设置）、backend/_internal/Volume/
（本机 Cookie）、__pycache__、旧 zip，避免把个人数据发给别人。
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
RELEASE_DIR_NAME = "夜星视频下载器_v5.8"
REL = ROOT / "release" / RELEASE_DIR_NAME
DIST_BACKEND = ROOT / "dist" / "backend"
FLUTTER_RELEASE = ROOT / "gui" / "flutter_app" / "build" / "windows" / "x64" / "runner" / "Release"
VENDOR_FFMPEG = ROOT / "vendor" / "ffmpeg"
APP_EXE = "夜星视频下载器.exe"

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
    result = subprocess.run(
        ["tasklist", "/FO", "CSV"], capture_output=True
    )
    text = result.stdout.decode("gbk", errors="ignore")
    running = []
    if "backend.exe" in text.lower():
        running.append("backend.exe")
    if APP_EXE in text:
        running.append(APP_EXE)
    if running:
        fail(f"以下进程正在运行，请先退出应用再打包：{'、'.join(running)}")


def ensure_vendor_ffmpeg() -> None:
    if (VENDOR_FFMPEG / "ffmpeg.exe").exists():
        return
    legacy = REL / "ffmpeg.exe"
    if legacy.exists():
        VENDOR_FFMPEG.mkdir(parents=True, exist_ok=True)
        for name in ("ffmpeg.exe", "ffprobe.exe"):
            src = REL / name
            if src.exists():
                shutil.copy2(src, VENDOR_FFMPEG / name)
        log("已从现有发布包复制 ffmpeg 到 vendor/ffmpeg/")
        return
    fail("缺少 vendor/ffmpeg/ffmpeg.exe（音视频合并必需），请先放置该文件")


def build_backend() -> None:
    log("== [1/4] PyInstaller 构建后端…")
    result = subprocess.run(
        [sys.executable, "-m", "PyInstaller", "backend.spec", "--noconfirm"],
        cwd=ROOT,
    )
    if result.returncode != 0 or not (DIST_BACKEND / "backend.exe").exists():
        fail("后端构建失败")
    internal = DIST_BACKEND / "_internal"
    if not (internal / "yt_dlp_ejs").exists():
        fail("后端产物缺少 yt_dlp_ejs（JS 挑战求解脚本），请检查 backend.spec")
    if not (internal / "ffmpeg.exe").exists():
        log("[警告] 后端产物未内置 ffmpeg.exe（不影响根目录 ffmpeg 的查找）")


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
    volume = backend_dir / "_internal" / "Volume"
    volume_bak = backend_dir / "Volume_bak"
    if volume.exists():  # 保留用户数据（设置/Cookie/数据库）
        shutil.move(volume, volume_bak)
    try:
        shutil.rmtree(backend_dir / "_internal", ignore_errors=True)
        shutil.copytree(DIST_BACKEND / "_internal", backend_dir / "_internal")
    finally:
        if volume_bak.exists():
            if volume.exists():
                shutil.rmtree(volume_bak, ignore_errors=True)
            else:
                shutil.move(volume_bak, volume)
    shutil.copy2(DIST_BACKEND / "backend.exe", backend_dir / "backend.exe")


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


def copy_ffmpeg() -> None:
    for name in ("ffmpeg.exe", "ffprobe.exe"):
        shutil.copy2(VENDOR_FFMPEG / name, REL / name)


def make_zip() -> None:
    log("== [4/4] 生成干净分发包…")
    # 注意不能用 with_suffix：目录名含点（_v5.8）会被截断成 _v5.zip
    zip_path = REL.parent / (REL.name + ".zip")
    if zip_path.exists():
        zip_path.unlink()
    # 排除本机个人数据与构建残留
    exclude_prefixes = (
        REL / "Volume",
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
    log(f"分发包: {zip_path}（{count} 个文件, {size_mb:.0f} MB, 已排除本机 Cookie/设置/下载，CRC 校验通过）")


def verify_zip(zip_path: Path) -> None:
    """冒烟测试：解压到临时目录（模拟用户新机器首次启动），确认后端可就绪。"""
    import tempfile
    import time
    import urllib.request

    log("== [5/5] 分发包冒烟测试（解压并启动后端）…")
    with tempfile.TemporaryDirectory(
        prefix="douk_zip_smoke_", ignore_cleanup_errors=True
    ) as tmp:
        with zipfile.ZipFile(zip_path) as zf:
            zf.extractall(tmp)
        backend_exe = Path(tmp) / RELEASE_DIR_NAME / "backend" / "backend.exe"
        if not backend_exe.exists():
            fail("冒烟测试失败：解压后缺少 backend/backend.exe")
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


def main() -> None:
    parser = argparse.ArgumentParser(description="夜星视频下载器 打包脚本")
    parser.add_argument("--zip", action="store_true", help="生成干净分发包（排除个人数据）")
    args = parser.parse_args()

    if os.name == "nt":
        try:
            sys.stdout.reconfigure(encoding="utf-8")
        except Exception:
            pass

    if not REL.exists():
        fail(f"未找到发布目录 {REL}")
    check_no_running()
    ensure_vendor_ffmpeg()
    build_backend()
    build_frontend()
    assemble_backend()
    assemble_frontend()
    sync_fallback_sources()
    copy_ffmpeg()
    log(f"打包完成: {REL}")
    if args.zip:
        make_zip()
        verify_zip(REL.parent / (REL.name + ".zip"))


if __name__ == "__main__":
    main()
