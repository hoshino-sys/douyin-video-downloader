from asyncio import create_task as aio_create_task
from datetime import datetime
from functools import lru_cache
import os
import threading
import time
from typing import TYPE_CHECKING
from uuid import uuid4

from fastapi import Depends, HTTPException
from fastapi.responses import Response
from pydantic import BaseModel

from src.application.main_server import token_dependency
from src.custom import __VERSION__, PROJECT_ROOT
from src.models import Settings
from src.tools import Browser
from gui import platforms_yt
from gui.task_control import TaskControl, TaskInterrupted

if TYPE_CHECKING:
    from src.application.main_server import APIServer
    from src.application.TikTokDownloader import TikTokDownloader

__all__ = ["setup_gui_routes"]

GUI_TAG = "GUI"

# 图床 → Referer 映射（部分图床带 Referer 才返回图片）
_IMAGE_REFERERS = (
    ("hdslb.com", "https://www.bilibili.com/"),
    ("douyinpic.com", "https://www.douyin.com/"),
    ("ytimg.com", "https://www.youtube.com/"),
)


@lru_cache(maxsize=64)
def _fetch_image(url: str) -> tuple[bytes, str]:
    """同步抓取图片。urllib 默认走系统代理（Windows 读注册表），
    可覆盖前端直连不了的图床（如 YouTube i.ytimg.com）。"""
    import ipaddress
    import socket
    import urllib.request
    from urllib.parse import urlparse

    host = (urlparse(url).hostname or "").lower()
    if not host or host == "localhost" or host.endswith(".local"):
        raise ValueError("不允许的地址")
    try:  # 字面 IP 与域名解析结果都必须是公网地址，防内网访问
        for info in socket.getaddrinfo(host, None):
            if not ipaddress.ip_address(info[4][0]).is_global:
                raise ValueError("不允许内网地址")
    except socket.gaierror as e:
        raise ValueError("地址无法解析") from e

    headers = {
        "User-Agent": (
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
            "(KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36"
        )
    }
    for domain, referer in _IMAGE_REFERERS:
        if host == domain or host.endswith("." + domain):
            headers["Referer"] = referer
            break
    request = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(request, timeout=8) as resp:
        ctype = (resp.headers.get("Content-Type") or "").split(";")[0]
        ctype = ctype.strip().lower()
        data = resp.read(3 * 1024 * 1024 + 1)
    if not ctype.startswith("image/") or not data or len(data) > 3 * 1024 * 1024:
        raise ValueError("响应不是图片")
    return data, ctype


def _list_explorer_windows() -> set[int]:
    import ctypes
    from ctypes import wintypes

    user32 = ctypes.windll.user32
    hwnds: set[int] = set()

    @ctypes.WINFUNCTYPE(ctypes.c_bool, wintypes.HWND, wintypes.LPARAM)
    def callback(hwnd, _lparam):
        cls = ctypes.create_unicode_buffer(64)
        user32.GetClassNameW(hwnd, cls, 64)
        if cls.value == "CabinetWClass":
            hwnds.add(hwnd)
        return True

    user32.EnumWindows(callback, 0)
    return hwnds


def _foreground_explorer(folder_name: str, known: set[int]) -> None:
    import ctypes
    from ctypes import wintypes

    user32 = ctypes.windll.user32
    target = None
    deadline = time.time() + 3.0
    while time.time() < deadline and target is None:
        windows = []

        @ctypes.WINFUNCTYPE(ctypes.c_bool, wintypes.HWND, wintypes.LPARAM)
        def callback(hwnd, _lparam):
            cls = ctypes.create_unicode_buffer(64)
            user32.GetClassNameW(hwnd, cls, 64)
            if cls.value == "CabinetWClass":
                title = ctypes.create_unicode_buffer(256)
                user32.GetWindowTextW(hwnd, title, 256)
                windows.append((hwnd, title.value))
            return True

        user32.EnumWindows(callback, 0)
        for hwnd, title in windows:
            if hwnd not in known or (folder_name and folder_name in title):
                target = hwnd
                break
        if target is None:
            time.sleep(0.2)

    if target is None:
        return
    try:
        user32.keybd_event(0x12, 0, 0, 0)
        user32.keybd_event(0x12, 0, 2, 0)
        user32.ShowWindow(target, 9)
        user32.SetForegroundWindow(target)
    except Exception:
        pass


class BrowserRequest(BaseModel):
    browser: str
    target: str = "douyin"


class DetectRequest(BaseModel):
    url: str


class PasteRequest(BaseModel):
    text: str


class OpenFolderRequest(BaseModel):
    path: str


class GuiTaskRequest(BaseModel):
    type: str
    platform: str = "douyin"
    data: dict | None = None
    sec_user_id: str | None = None
    tab: str = "post"
    earliest: str = ""
    latest: str = ""
    label: str = ""
    url: str = ""
    format_id: str | None = None
    save_dir: str = ""


class UpdateDownloadRequest(BaseModel):
    url: str


def _check_update() -> dict:
    """查询 GitHub Releases 最新版本；任何失败都静默降级为无更新。"""
    import json
    import re
    import urllib.request

    from src.custom.internal import RELEASES, RELEASES_API, USERAGENT

    result = {
        "current": __VERSION__,
        "latest": "",
        "update_available": False,
        "notes": "",
        "page_url": RELEASES,
        "zip_url": "",
        "update_mode": "full",
        "zip_size": 0,
        "published_at": "",
        "error": "",
    }

    def nums(text: str) -> tuple:
        found = re.findall(r"\d+", text)
        return tuple(int(x) for x in found[:4]) if found else (0,)

    try:
        req = urllib.request.Request(
            RELEASES_API,
            headers={"User-Agent": USERAGENT, "Accept": "application/vnd.github+json"},
        )
        with urllib.request.urlopen(req, timeout=8) as resp:
            data = json.load(resp)
    except Exception as e:
        # GitHub API 有按 IP 的匿名速率限制，共享代理出口常被耗尽；
        # 回退抓 releases/latest 页面重定向（HTML 不占 API 限额），只有版本号、无说明
        tag = ""
        try:
            # RELEASES 常量即 releases/latest 页面，访问后由 GitHub 重定向到 /tag/vX.Y.Z
            req = urllib.request.Request(RELEASES, headers={"User-Agent": USERAGENT})
            with urllib.request.urlopen(req, timeout=8) as resp:
                m = re.search(r"/tag/v?([0-9][\d.]*)", resp.geturl() or "")
                if m:
                    tag = m.group(1).rstrip(".")
        except Exception:
            pass
        if not tag:
            result["error"] = f"无法连接更新服务器：{e}"[:160]
            return result
        result["latest"] = tag
        result["zip_url"] = (
            f"{_RELEASE_DOWNLOAD_PREFIX}v{tag}/yexing-video-downloader_v{tag}.zip"
        )
        result["update_available"] = nums(tag) > nums(__VERSION__)
        return result
    tag = str(data.get("tag_name") or "").lstrip("vV")
    result["latest"] = tag
    result["notes"] = str(data.get("body") or "")[:1200]
    result["published_at"] = str(data.get("published_at") or "")
    update_available = bool(tag) and nums(tag) > nums(__VERSION__)
    result["update_available"] = update_available

    # 资产名均为 ASCII（GitHub 会剔除中文名），全量包按命名规则识别
    full_url, full_size = "", 0
    patch_base, patch_url, patch_size = "", "", 0
    for a in data.get("assets") or []:
        name = str(a.get("name") or "").lower()
        url = str(a.get("browser_download_url") or "")
        size = int(a.get("size") or 0)
        if name == f"yexing-video-downloader_v{tag}.zip":
            full_url, full_size = url, size
            continue
        m = re.fullmatch(
            rf"yexing-video-downloader_v([\d.]+)_patch_v{re.escape(tag)}\.zip",
            name,
        )
        if m:
            patch_base, patch_url, patch_size = m.group(1), url, size
    if full_url == "":  # 兜底：任何 zip 资产（防命名规则变动后无包可选）
        for a in data.get("assets") or []:
            if str(a.get("name") or "").lower().endswith(".zip"):
                full_url = str(a.get("browser_download_url") or "")
                full_size = int(a.get("size") or 0)
                break

    # 增量补丁只在「当前版本 == 补丁基准版本」时使用，否则回退全量包；
    # zip_size 供前端展示「增量更新（约 xx MB）」
    if update_available and patch_url and nums(patch_base) == nums(__VERSION__):
        result["zip_url"] = patch_url
        result["update_mode"] = "patch"
        result["zip_size"] = patch_size
    else:
        result["zip_url"] = full_url
        result["update_mode"] = "full"
        result["zip_size"] = full_size
    return result


_RELEASE_DOWNLOAD_PREFIX = (
    "https://github.com/hoshino-sys/douyin-video-downloader/releases/download/"
)


class TaskManager:
    def __init__(self):
        self._tasks: dict[str, dict] = {}
        self._controls: dict[str, TaskControl] = {}

    def create(
        self,
        task_type: str,
        label: str,
        title: str = "",
        platform: str = "",
    ) -> dict:
        task_id = uuid4().hex[:12]
        task = {
            "id": task_id,
            "type": task_type,
            "label": label,
            "title": title,
            "platform": platform,
            "status": "running",
            "message": "",
            "created_at": datetime.now().isoformat(timespec="seconds"),
            "finished_at": "",
            "logs": [],
            "progress": {"current": 0, "total": 0, "percent": 0},
            "download_dir": "",
        }
        self._tasks[task_id] = task
        return task

    def bind(self, task_id: str, control: TaskControl) -> None:
        self._controls[task_id] = control

    def control(self, task_id: str) -> TaskControl | None:
        return self._controls.get(task_id)

    def append_log(self, task: dict, text: str) -> None:
        logs = task.get("logs")
        if logs is None:
            task["logs"] = logs = []
        logs.append(f"{datetime.now():%H:%M:%S} {text}")
        if len(logs) > 300:
            del logs[: len(logs) - 300]

    def broadcast(self, text: str) -> None:
        for t in self._tasks.values():
            if t.get("status") == "running":
                self.append_log(t, text)

    def set_meta(self, task: dict, **fields) -> None:
        for key, value in fields.items():
            if value:
                task[key] = value

    def set_progress(
        self,
        task: dict,
        current: int,
        total: int,
        message: str = "",
        speed: float | None = None,
        eta: float | None = None,
    ) -> None:
        progress = {
            "current": current,
            "total": total,
            "percent": int(current * 100 / total) if total else 0,
            "speed": speed,
            "eta": eta,
        }
        task["progress"] = progress
        if message:
            task["message"] = message

    def finish(self, task: dict, ok: bool, message: str = "") -> None:
        task["status"] = "success" if ok else "failed"
        task["message"] = message
        task["finished_at"] = datetime.now().isoformat(timespec="seconds")

    def set_status(self, task: dict, status: str, message: str = "") -> None:
        """状态流转：running/paused 视为未结束（不写 finished_at）。"""
        task["status"] = status
        if message:
            task["message"] = message
        if status not in ("running", "paused"):
            task["finished_at"] = datetime.now().isoformat(timespec="seconds")

    def get(self, task_id: str) -> dict | None:
        return self._tasks.get(task_id)

    def list(self) -> list[dict]:
        return sorted(
            self._tasks.values(),
            key=lambda item: item["created_at"],
            reverse=True,
        )


def setup_gui_routes(server: "APIServer", app: "TikTokDownloader") -> None:
    fast_app = server.server
    tasks = TaskManager()
    import asyncio

    _dir_lock = asyncio.Lock()

    def _resolve_save_dir(save_dir: str):
        from pathlib import Path

        text = (save_dir or "").strip()
        if not text:
            return None
        path = Path(text).expanduser()
        path.mkdir(parents=True, exist_ok=True)
        return path.resolve()

    def _swap_root_custom(custom_dir):
        """返回 contextmanager：临时替换 downloader.root（Downloader 在初始化时持有快照）。"""
        from contextlib import contextmanager

        @contextmanager
        def ctx():
            if custom_dir is None:
                yield
                return
            original = server.downloader.root
            server.downloader.root = custom_dir
            try:
                yield
            finally:
                server.downloader.root = original

        return ctx()

    _PLATFORM_DIR_NAMES = {
        "douyin": "抖音",
        "tiktok": "TikTok",
        "bili": "B站",
        "youtube": "YouTube",
    }

    def _with_platform_dir(base, platform: str):
        """平台分类开启时在下载根（或自定义目录）下套一层平台子目录，
        与 Downloader.platform_root 的落盘规则保持一致。"""
        from pathlib import Path

        base = Path(base)
        if not server.parameter.platform_folders:
            return base
        name = _PLATFORM_DIR_NAMES.get(platform, platform)
        return base / name

    def _on_interrupt(task: dict, ctl: TaskControl) -> None:
        """asyncio 任务被 cancel() 后按 request 标记暂停/取消。"""
        action = ctl.request or "cancel"
        ctl.request = None
        if action == "pause":
            tasks.set_status(task, "paused", "已暂停（进度保留，可继续）")
            tasks.append_log(task, "任务已暂停，继续时自动断点续传")
        else:
            tasks.set_status(task, "cancelled", "任务已取消")
            tasks.append_log(task, "任务已取消")

    def _spawn(task: dict, ctl: TaskControl, runner) -> None:
        """启动任务协程并注册控制句柄；runner 为可重复调用的协程函数（恢复用）。"""

        async def wrapped():
            try:
                await runner()
            except asyncio.CancelledError:
                _on_interrupt(task, ctl)
            except Exception as e:
                tasks.append_log(task, f"任务异常：{e}")
                tasks.finish(task, False, str(e))

        ctl.rerun = wrapped
        ctl.aio_task = aio_create_task(wrapped())
        tasks.bind(task["id"], ctl)

    logger = server.parameter.logger
    _orig_info = logger.info
    _orig_warning = logger.warning
    _orig_error = logger.error

    def _patched_info(text: str, output=True, **kw):
        try:
            _orig_info(text, output, **kw)
        except Exception:
            pass
        try:
            tasks.broadcast(str(text))
        except Exception:
            pass

    def _patched_warning(text: str, output=True, **kw):
        try:
            _orig_warning(text, output, **kw)
        except Exception:
            pass
        try:
            tasks.broadcast(f"[WARN] {text}")
        except Exception:
            pass

    def _patched_error(text: str, output=True, **kw):
        try:
            _orig_error(text, output, **kw)
        except Exception:
            pass
        try:
            tasks.broadcast(f"[ERR] {text}")
        except Exception:
            pass

    logger.info = _patched_info
    logger.warning = _patched_warning
    logger.error = _patched_error

    @fast_app.get("/api/gui/health", tags=[GUI_TAG], include_in_schema=False)
    async def health():
        # version 供打包脚本补丁验证与前端诊断使用
        return {"status": "ok", "version": __VERSION__}

    @fast_app.get("/api/gui/bootstrap", tags=[GUI_TAG])
    async def bootstrap(token: str = Depends(token_dependency)):
        parameter = server.parameter
        return {
            "version": __VERSION__,
            "disclaimer_accepted": bool(app.config.get("Disclaimer")),
            "cookie_configured": bool(parameter.cookie_dict or parameter.cookie_str),
            "cookie_logged_in": bool(parameter.cookie_state),
        }

    @fast_app.post("/api/gui/disclaimer/accept", tags=[GUI_TAG])
    async def accept_disclaimer(token: str = Depends(token_dependency)):
        await app.database.update_config_data("Disclaimer", 1)
        app.config["Disclaimer"] = 1
        return {"success": True}

    @fast_app.get("/api/gui/cookie/status", tags=[GUI_TAG])
    async def cookie_status():
        parameter = server.parameter
        platforms = platforms_yt.platform_cookie_states(parameter)
        return {
            "configured": any(v["imported"] for v in platforms.values()),
            "logged_in": bool(parameter.cookie_state),
            "platforms": platforms,
        }

    @fast_app.get("/api/gui/cookie/browsers", tags=[GUI_TAG])
    async def cookie_browsers():
        return {"browsers": list(Browser.SUPPORT_BROWSER.keys())}

    @fast_app.post("/api/gui/cookie/browser", tags=[GUI_TAG])
    async def cookie_from_browser(
        req: BrowserRequest, token: str = Depends(token_dependency)
    ):
        if req.target == "all":
            return _import_all_platform_cookies(req.browser)
        if req.target in ("bili", "youtube"):
            return platforms_yt.save_platform_cookie(
                req.target, req.browser, server.parameter, app.cookie
            )
        try:
            browser = Browser(server.parameter, app.cookie)
            cookie_dict = browser.get(req.browser, ["douyin.com"])
        except Exception as e:
            return {"success": False, "message": f"读取浏览器 Cookie 失败：{e}"}
        if not cookie_dict:
            return {
                "success": False,
                "message": "未读取到 Cookie 数据！请确认已在浏览器中登录抖音，关闭浏览器后重试，或改用手动粘贴方式",
            }
        app.cookie.save_cookie(cookie_dict, "cookie")
        server.parameter.set_cookie(cookie_dict, "")
        server.parameter.set_headers_cookie()
        return {"success": True, "logged_in": "sessionid_ss" in cookie_dict}

    def _read_browser_cookies(browser_name: str, domain: str) -> dict:
        try:
            browser = Browser(server.parameter, app.cookie)
            return browser.get(browser_name, [domain])
        except Exception:
            return {}

    def _import_all_platform_cookies(browser_name: str) -> dict:
        results: dict = {}
        douyin = _read_browser_cookies(browser_name, "douyin.com")
        tiktok = _read_browser_cookies(browser_name, "tiktok.com")
        if douyin:
            app.cookie.save_cookie(douyin, "cookie")
        if tiktok:
            app.cookie.save_cookie(tiktok, "cookie_tiktok")
        if douyin or tiktok:
            server.parameter.set_cookie(douyin or "", tiktok or "")
            server.parameter.set_headers_cookie()
        results["douyin"] = {
            "success": bool(douyin),
            "logged_in": "sessionid_ss" in douyin,
            "message": "" if douyin else "未读取到抖音 Cookie",
        }
        results["tiktok"] = {
            "success": bool(tiktok),
            "logged_in": "sessionid_ss" in tiktok,
            "message": "" if tiktok else "未读取到 TikTok Cookie",
        }
        for key, name in (("bili", "B站"), ("youtube", "YouTube")):
            r = platforms_yt.save_platform_cookie(
                key, browser_name, server.parameter, app.cookie
            )
            results[key] = {
                "success": bool(r.get("success")),
                "logged_in": bool(r.get("logged_in")),
                "message": str(r.get("message") or ""),
            }
        any_ok = any(v["success"] for v in results.values())
        return {"success": any_ok, "results": results}

    @fast_app.post("/api/gui/cookie/paste", tags=[GUI_TAG])
    async def cookie_paste(req: PasteRequest, token: str = Depends(token_dependency)):
        text = req.text.strip()
        if not app.cookie.validate_cookie_minimal(text):
            return {
                "success": False,
                "message": "内容不是有效的 Cookie 格式，请检查后重试",
            }
        cookie_dict = app.cookie.extract(text, key="cookie", platform="抖音")
        server.parameter.set_cookie(cookie_dict, "")
        server.parameter.set_headers_cookie()
        return {"success": True, "logged_in": "sessionid_ss" in cookie_dict}

    @fast_app.post("/api/gui/detect", tags=[GUI_TAG])
    async def detect_url(req: DetectRequest, token: str = Depends(token_dependency)):
        url = req.url.strip()
        detection = platforms_yt.detect_platform(url)
        if detection is None:
            return {"platform": "douyin"}
        platform, kind = detection
        try:
            preview = await platforms_yt.extract_preview(url, platform, kind)
        except Exception as e:
            return {
                "platform": platform,
                "kind": kind,
                "error": str(e)[:300],
            }
        preview["platform"] = platform
        return preview

    @fast_app.get(
        "/api/gui/thumbnail",
        tags=[GUI_TAG],
        include_in_schema=False,
    )
    async def thumbnail(url: str = "", token: str = Depends(token_dependency)):
        """图片代理：加载前端直连不了的图床（如 YouTube i.ytimg.com）。"""
        if not url.startswith(("http://", "https://")):
            raise HTTPException(status_code=400, detail="无效的图片地址")
        try:
            data, ctype = await asyncio.to_thread(_fetch_image, url)
        except Exception:
            raise HTTPException(status_code=404, detail="封面获取失败") from None
        return Response(
            content=data,
            media_type=ctype,
            headers={"Cache-Control": "max-age=86400"},
        )

    @fast_app.post("/api/gui/task", tags=[GUI_TAG])
    async def create_gui_task(
        req: GuiTaskRequest, token: str = Depends(token_dependency)
    ):
        is_tiktok = req.platform.lower() == "tiktok"

        if req.type == "detail":
            if not isinstance(req.data, dict) or not req.data:
                return {"status": "failed", "message": "缺少作品数据"}
            try:
                custom_dir = _resolve_save_dir(req.save_dir)
            except Exception as e:
                return {"status": "failed", "message": f"保存目录无效：{e}"}
            task = tasks.create(
                "detail",
                req.label or "单作品下载",
                title=str(req.data.get("desc") or "")[:100],
                platform="tiktok" if is_tiktok else "douyin",
            )
            task["download_dir"] = str(
                _with_platform_dir(
                    custom_dir or server.parameter.root.resolve(),
                    "tiktok" if is_tiktok else "douyin",
                )
            )
            tasks.append_log(
                task, f"开始下载单个作品，平台={'TikTok' if is_tiktok else '抖音'}"
            )
            desc = req.data.get("desc", "") or req.data.get("id", "")
            if desc:
                tasks.append_log(task, f"作品：{str(desc)[:80]}")
            tasks.append_log(task, f"保存目录：{task['download_dir']}")

            async def run_detail():
                tasks.append_log(task, "正在请求并下载文件…")
                if custom_dir is not None:
                    async with _dir_lock:
                        with _swap_root_custom(custom_dir):
                            await server.downloader.run(
                                [req.data], "detail", tiktok=is_tiktok
                            )
                else:
                    await server.downloader.run([req.data], "detail", tiktok=is_tiktok)
                tasks.append_log(task, "下载流程结束")
                tasks.finish(task, True, "下载完成")

            _spawn(task, TaskControl(asyncio_based=True), run_detail)
            return {"status": "success", "task": task}

        if req.type == "account":
            if not req.sec_user_id:
                return {"status": "failed", "message": "缺少账号 ID"}
            try:
                custom_dir = _resolve_save_dir(req.save_dir)
            except Exception as e:
                return {"status": "failed", "message": f"保存目录无效：{e}"}
            task = tasks.create(
                "account",
                req.label or "账号作品批量下载",
                platform="tiktok" if is_tiktok else "douyin",
            )
            task["download_dir"] = str(
                _with_platform_dir(
                    custom_dir or server.parameter.root.resolve(),
                    "tiktok" if is_tiktok else "douyin",
                )
            )
            tasks.append_log(
                task,
                f"开始批量下载，账号={req.sec_user_id} 平台={'TikTok' if is_tiktok else '抖音'} tab={req.tab}",
            )
            if req.earliest or req.latest:
                tasks.append_log(
                    task,
                    f"日期筛选：{req.earliest or '不限'} 至 {req.latest or '不限'}",
                )
            tasks.append_log(task, f"保存目录：{task['download_dir']}")
            tasks.append_log(task, "正在获取账号作品列表，这可能需要一些时间…")

            async def run_account():
                if custom_dir is not None:
                    async with _dir_lock:
                        with _swap_root_custom(custom_dir):
                            await server.deal_account_detail(
                                index=0,
                                sec_user_id=req.sec_user_id,
                                tab=req.tab,
                                earliest=req.earliest,
                                latest=req.latest,
                                tiktok=is_tiktok,
                                api=False,
                            )
                else:
                    await server.deal_account_detail(
                        index=0,
                        sec_user_id=req.sec_user_id,
                        tab=req.tab,
                        earliest=req.earliest,
                        latest=req.latest,
                        tiktok=is_tiktok,
                        api=False,
                    )
                tasks.append_log(task, "批量任务流程结束")
                tasks.finish(task, True, "任务完成，可在保存目录查看文件")

            _spawn(task, TaskControl(asyncio_based=True), run_account)
            return {"status": "success", "task": task}

        if req.type == "ytdlp":
            if not req.url.strip():
                return {"status": "failed", "message": "缺少视频链接"}
            try:
                custom_dir = _resolve_save_dir(req.save_dir)
            except Exception as e:
                return {"status": "failed", "message": f"保存目录无效：{e}"}
            ytdlp_platform = req.platform.lower()
            if ytdlp_platform not in ("bili", "youtube"):
                detected = platforms_yt.detect_platform(req.url.strip())
                ytdlp_platform = detected[0] if detected else ytdlp_platform
            task = tasks.create(
                "ytdlp",
                req.label or "B站/YouTube 下载",
                platform=ytdlp_platform,
            )
            root = _with_platform_dir(
                custom_dir or server.parameter.root.resolve(),
                ytdlp_platform,
            )
            root.mkdir(parents=True, exist_ok=True)
            task["download_dir"] = str(root)
            tasks.append_log(task, f"链接：{req.url.strip()[:120]}")

            async def run_ytdlp():
                # 暂停/取消在 run_ytdlp_download 内部处理（线程事件通道），
                # TaskInterrupted 不会抛到这里
                await platforms_yt.run_ytdlp_download(
                    task, tasks, req.url, root, req.format_id, control=ctl
                )

            ctl = TaskControl(asyncio_based=False)
            _spawn(task, ctl, run_ytdlp)
            return {"status": "success", "task": task}

        return {"status": "failed", "message": "不支持的任务类型"}

    @fast_app.post("/api/gui/settings", tags=[GUI_TAG])
    async def save_gui_settings(
        extract: Settings, token: str = Depends(token_dependency)
    ):
        data = extract.model_dump()
        await server.parameter.set_settings_data(dict(data))
        app.settings.update(data)
        return {"success": True}

    @fast_app.get("/api/gui/tasks", tags=[GUI_TAG])
    async def list_tasks(token: str = Depends(token_dependency)):
        return {"tasks": tasks.list()}

    @fast_app.get("/api/gui/task/{task_id}", tags=[GUI_TAG])
    async def get_task(task_id: str, token: str = Depends(token_dependency)):
        task = tasks.get(task_id)
        if not task:
            raise HTTPException(status_code=404, detail="任务不存在")
        return task

    @fast_app.post("/api/gui/task/{task_id}/pause", tags=[GUI_TAG])
    async def pause_task(task_id: str, token: str = Depends(token_dependency)):
        task = tasks.get(task_id)
        if not task:
            raise HTTPException(status_code=404, detail="任务不存在")
        if task["status"] != "running":
            return {"success": False, "message": "任务不在运行中"}
        ctl = tasks.control(task_id)
        if not ctl:
            return {"success": False, "message": "该任务不支持暂停"}
        if ctl.asyncio_based:
            ctl.request = "pause"
            if ctl.aio_task is not None:
                ctl.aio_task.cancel()
        else:
            ctl.pause_event.set()
        return {"success": True, "task": task}

    @fast_app.post("/api/gui/task/{task_id}/resume", tags=[GUI_TAG])
    async def resume_task(task_id: str, token: str = Depends(token_dependency)):
        task = tasks.get(task_id)
        if not task:
            raise HTTPException(status_code=404, detail="任务不存在")
        if task["status"] != "paused":
            return {"success": False, "message": "任务未处于暂停状态"}
        ctl = tasks.control(task_id)
        if not ctl or ctl.rerun is None:
            return {
                "success": False,
                "message": "缺少任务上下文，无法恢复，请重新创建任务",
            }
        ctl.request = None
        ctl.pause_event.clear()
        ctl.cancel_event.clear()
        tasks.set_status(task, "running", "已恢复")
        tasks.append_log(task, "继续任务…")
        aio_create_task(ctl.rerun())
        return {"success": True, "task": task}

    @fast_app.post("/api/gui/task/{task_id}/cancel", tags=[GUI_TAG])
    async def cancel_task(task_id: str, token: str = Depends(token_dependency)):
        from pathlib import Path

        task = tasks.get(task_id)
        if not task:
            raise HTTPException(status_code=404, detail="任务不存在")
        ctl = tasks.control(task_id)
        if task["status"] == "running":
            if not ctl:
                return {"success": False, "message": "该任务不支持取消"}
            if ctl.asyncio_based:
                ctl.request = "cancel"
                if ctl.aio_task is not None:
                    ctl.aio_task.cancel()
            else:
                ctl.cancel_event.set()
            return {"success": True, "task": task}
        if task["status"] == "paused":
            # 暂停中（执行体已退出）直接标记取消；更新包任务的半截文件
            # 与运行中取消保持一致：放弃即删除
            if ctl is not None:
                ctl.request = None
                ctl.cancel_event.set()
                if ctl.artifact is not None:
                    try:
                        Path(ctl.artifact).unlink(missing_ok=True)
                    except OSError:
                        pass
                    tasks.append_log(task, "已删除未完成的更新包")
            tasks.set_status(task, "cancelled", "任务已取消")
            tasks.append_log(task, "任务已取消")
            return {"success": True, "task": task}
        return {"success": False, "message": "任务已结束"}

    @fast_app.post("/api/gui/open_folder", tags=[GUI_TAG])
    async def open_folder(
        req: OpenFolderRequest, token: str = Depends(token_dependency)
    ):
        import subprocess
        import sys
        from pathlib import Path

        path = Path(req.path).expanduser().resolve()
        target = path if path.exists() else path.parent
        if not target.exists():
            return {"success": False, "message": f"路径不存在：{target}"}
        try:
            if sys.platform == "win32":
                known = _list_explorer_windows()
                subprocess.Popen(["explorer.exe", "/separate", str(target)])
                threading.Thread(
                    target=_foreground_explorer,
                    args=(target.name, known),
                    daemon=True,
                ).start()
            elif sys.platform == "darwin":
                subprocess.Popen(["open", str(target)])
            else:
                subprocess.Popen(["xdg-open", str(target)])
            return {"success": True}
        except Exception as e:
            return {"success": False, "message": str(e)}

    @fast_app.get("/api/gui/update/check", tags=[GUI_TAG])
    async def update_check(token: str = Depends(token_dependency)):
        return await asyncio.to_thread(_check_update)

    @fast_app.post("/api/gui/update/download", tags=[GUI_TAG])
    async def update_download(
        req: UpdateDownloadRequest, token: str = Depends(token_dependency)
    ):
        import subprocess
        import urllib.request
        from pathlib import Path

        from src.custom.internal import USERAGENT

        url = req.url.strip()
        if not url.startswith(_RELEASE_DOWNLOAD_PREFIX):
            return {"status": "failed", "message": "下载地址不受信任"}

        filename = url.rsplit("/", 1)[-1] or "update.zip"
        target_dir = Path.home() / "Downloads"
        if not target_dir.exists():
            # 命名避开顶层的 Downloads（下载媒体目录），防止大小写混淆
            target_dir = PROJECT_ROOT.joinpath("updates")
        target_dir.mkdir(parents=True, exist_ok=True)
        dest = target_dir / filename

        task = tasks.create("update", "更新包下载")
        task["download_dir"] = str(target_dir)
        tasks.append_log(task, f"开始下载更新包：{filename}")

        control = TaskControl(asyncio_based=False)
        control.artifact = dest  # 暂停态取消时由取消端点清理半截包
        resume_part = [0]  # 暂停后恢复的起始字节（GitHub 资产支持 Range）

        def work() -> None:
            part = resume_part[0]
            headers = {"User-Agent": USERAGENT}
            if part:
                headers["Range"] = f"bytes={part}-"
            request = urllib.request.Request(url, headers=headers)
            with urllib.request.urlopen(request, timeout=60) as resp:
                if part and resp.status != 206:
                    part = 0  # 服务器不支持续传，从头下载
                total = part + int(resp.headers.get("Content-Length") or 0)
                done = part
                with open(dest, "ab" if part else "wb") as fh:
                    start = time.time()
                    last_tick = 0.0
                    while True:
                        # 暂停/取消检查点：半截文件保留，恢复时 Range 续传
                        if control.cancel_event.is_set():
                            raise TaskInterrupted("cancel")
                        if control.pause_event.is_set():
                            raise TaskInterrupted("pause")
                        chunk = resp.read(262144)
                        if not chunk:
                            break
                        fh.write(chunk)
                        done += len(chunk)
                        now = time.time()
                        if now - last_tick >= 0.5:
                            elapsed = max(now - start, 0.001)
                            speed = (done - part) / elapsed
                            eta = (total - done) / speed if total and speed else None
                            tasks.set_progress(
                                task,
                                done,
                                total,
                                message=filename,
                                speed=speed,
                                eta=eta,
                            )
                            last_tick = now

        def finalize() -> None:
            tasks.set_progress(task, 1, 1, message="下载完成")
            tasks.append_log(task, f"已保存到：{dest}")
            tasks.append_log(task, "更新方法：退出本程序后，解压该压缩包覆盖原目录")
            try:
                if os.name == "nt":
                    subprocess.Popen(["explorer.exe", "/select", str(dest)])
            except Exception:
                pass
            tasks.finish(task, True, "更新包下载完成，退出应用后解压覆盖即可更新")

        async def run_update() -> None:
            try:
                await asyncio.to_thread(work)
                finalize()
            except TaskInterrupted as e:
                resume_part[0] = dest.stat().st_size if dest.exists() else 0
                if e.action == "pause":
                    tasks.set_status(task, "paused", "已暂停（进度保留，可继续）")
                    tasks.append_log(task, "更新包下载已暂停，继续时自动断点续传")
                else:
                    dest.unlink(missing_ok=True)  # 取消即放弃，清掉半截包
                    tasks.set_status(task, "cancelled", "任务已取消")
                    tasks.append_log(task, "更新包下载已取消")
            except Exception as e:
                message = f"更新包下载失败：{e}"[:200]
                tasks.append_log(task, message)
                tasks.finish(task, False, message)

        _spawn(task, control, run_update)
        return {"status": "success", "task": task}
