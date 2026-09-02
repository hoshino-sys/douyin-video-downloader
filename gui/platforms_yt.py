"""Bilibili / YouTube 下载引擎（基于 yt-dlp）。

抖音/TikTok 链接不经过本模块，仍走原有流程。
"""

from __future__ import annotations

import asyncio
import os
import re
import shutil
import sys
import time
from pathlib import Path
from typing import Any, Callable

from src.custom.internal import PROJECT_ROOT
from gui.task_control import TaskInterrupted

__all__ = [
    "detect_platform",
    "extract_preview",
    "find_ffmpeg",
    "platform_cookie_states",
    "run_ytdlp_download",
    "save_platform_cookie",
]

# 与 parameter.py 的下载临时缓存同一目录：Windows 不区分大小写，
# Cache/cache 两个名字会混用同一个文件夹，这里必须用同一个拼写
_CACHE_DIR = PROJECT_ROOT.joinpath("Cache")

_BILI_VIDEO = (
    r"^https?://(?:www\.|m\.)?bilibili\.com/video/(?:BV[\w]+|av\d+)",
    r"^https?://b23\.tv/",
    r"^https?://(?:www\.)?bilibili\.com/(?:festival|list)/",
)
_BILI_BATCH = (
    r"^https?://space\.bilibili\.com/\d+",
    r"^https?://(?:www\.)?bilibili\.com/lists/",
    r"^https?://(?:www\.)?bilibili\.com/channel/collectiondetail",
)
_YOUTUBE_VIDEO = (
    r"^https?://(?:www\.|m\.|music\.)?youtube\.com/(?:watch|shorts|live)",
    r"^https?://youtu\.be/[\w\-]+",
)
_YOUTUBE_BATCH = (
    r"^https?://(?:www\.)?youtube\.com/(?:channel|c)/",
    r"^https?://(?:www\.)?youtube\.com/@",
    r"^https?://(?:www\.)?youtube\.com/playlist\?",
)

_COOKIE_DOMAINS = {"bili": ".bilibili.com", "youtube": ".youtube.com"}
_COOKIE_LOGIN_KEYS = {
    "bili": ("SESSDATA",),
    "youtube": ("SID", "__Secure-1PSID", "SAPISID"),
}

_COOKIE_FILES: dict[str, Path] = {}


def detect_platform(url: str) -> tuple[str, str] | None:
    """返回 (平台, 类型)，类型为 video/batch；非目标平台返回 None。"""
    u = url.strip()
    for pattern in _BILI_BATCH:
        if re.match(pattern, u):
            return "bili", "batch"
    for pattern in _YOUTUBE_BATCH:
        if re.match(pattern, u):
            return "youtube", "batch"
    for pattern in _BILI_VIDEO:
        if re.match(pattern, u):
            return "bili", "video"
    for pattern in _YOUTUBE_VIDEO:
        if re.match(pattern, u):
            return "youtube", "video"
    return None


def _ffmpeg_search_dirs() -> list[Path]:
    candidates: list[Path] = []
    home = os.environ.get("DOUK_HOME")
    if home:
        candidates.append(Path(home))
    if getattr(sys, "frozen", False):
        exe_dir = Path(sys.executable).resolve().parent
        candidates.extend([exe_dir, exe_dir.parent])
    else:
        # 开发模式：源码树的 vendor/ffmpeg（发布根不再带 ffmpeg，
        # 打包版经 _MEIPASS 兜底，源码运行则靠这里）
        candidates.append(Path(__file__).resolve().parents[1] / "vendor" / "ffmpeg")
    bundle = getattr(sys, "_MEIPASS", "")
    if bundle:
        candidates.append(Path(bundle))
    found = shutil.which("ffmpeg")
    if found:
        candidates.append(Path(found).parent)
    return candidates


def find_ffmpeg() -> str | None:
    """按 应用根目录(DOUK_HOME) → exe 目录 → exe 上级 → vendor(开发模式) → 打包目录(_internal) → PATH 顺序查找 ffmpeg。"""
    for c in _ffmpeg_search_dirs():
        if (c / "ffmpeg.exe").exists() or (c / "ffmpeg").exists():
            return str(c)
    return None


def find_qjs() -> str | None:
    """查找内置/系统的 quickjs(qjs) 可执行文件，供 yt-dlp 求解 YouTube JS 挑战。

    yt-dlp 的 _find_exe 冻结时只搜 exe 同级目录和 PATH，不搜 _internal，
    因此必须把显式 path 传进 js_runtimes 选项。
    """
    for c in _ffmpeg_search_dirs():
        for name in ("qjs.exe", "qjs"):
            if (c / name).exists():
                return str(c / name)
    found = shutil.which("qjs")
    return found


# 最近一次 yt-dlp 运行是否报告过"缺少 JS 运行时"（用于区分风控原因）
_RUNTIME_MISSING = False


def platform_cookie_states(parameter: Any) -> dict:
    """返回四个平台的 Cookie 导入/登录态，供 GUI 状态展示。

    douyin/tiktok 分别取 parameter 中各自的 Cookie 与登录态；bili/youtube 看
    UserData/Cache 下的 Netscape Cookie 文件是否存在及其中的登录态键。
    """
    states = {
        "douyin": {
            "imported": bool(
                getattr(parameter, "cookie_dict", None)
                or getattr(parameter, "cookie_str", None)
            ),
            "logged_in": bool(getattr(parameter, "cookie_state", None)),
        },
        "tiktok": {
            "imported": bool(
                getattr(parameter, "cookie_dict_tiktok", None)
                or getattr(parameter, "cookie_str_tiktok", None)
            ),
            "logged_in": bool(getattr(parameter, "cookie_tiktok_state", None)),
        },
    }
    for target in ("bili", "youtube"):
        path = _cookie_path(target)
        target_logged = False
        if path is not None:
            try:
                lines = path.read_text(encoding="utf-8").splitlines()
            except OSError:
                lines = []
            keys = _COOKIE_LOGIN_KEYS[target]
            for line in lines:
                if not line or line.startswith("#"):
                    continue
                parts = line.split("\t")
                if len(parts) >= 7 and parts[5] in keys:
                    target_logged = True
                    break
        states[target] = {"imported": path is not None, "logged_in": target_logged}
    return states


def save_platform_cookie(
    target: str,
    browser_name: str,
    parameter: Any,
    cookie_manager: Any,
) -> dict:
    """从浏览器读取指定平台 Cookie 并写入 Netscape 文件供 yt-dlp 使用。"""
    if target not in _COOKIE_DOMAINS:
        return {"success": False, "message": f"不支持的平台：{target}"}
    try:
        from src.tools import Browser

        browser = Browser(parameter, cookie_manager)
        cookie_dict = browser.get(browser_name, [_COOKIE_DOMAINS[target].lstrip(".")])
    except Exception as e:
        return {"success": False, "message": f"读取浏览器 Cookie 失败：{e}"}
    if not cookie_dict:
        platform_name = "B站" if target == "bili" else "YouTube"
        return {
            "success": False,
            "message": f"未读取到 {platform_name} Cookie，请确认已在浏览器登录并关闭浏览器后重试",
        }
    _write_cookie_file(target, cookie_dict)
    logged_in = any(k in cookie_dict for k in _COOKIE_LOGIN_KEYS[target])
    return {"success": True, "count": len(cookie_dict), "logged_in": logged_in}


def _write_cookie_file(target: str, cookie_dict: dict[str, str]) -> Path:
    _CACHE_DIR.mkdir(parents=True, exist_ok=True)
    path = _cookie_path(target) or _CACHE_DIR.joinpath(f"ytdlp_cookies_{target}.txt")
    expiry = int(time.time()) + 365 * 24 * 3600
    lines = ["# Netscape HTTP Cookie File", "# Generated by 夜星视频下载器"]
    for name, value in cookie_dict.items():
        lines.append(
            f"{_COOKIE_DOMAINS[target]}\tTRUE\t/\tTRUE\t{expiry}\t{name}\t{value}"
        )
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    _COOKIE_FILES[target] = path
    return path


def _cookie_path(target: str) -> Path | None:
    """Cookie 文件解析：优先会话内路径，其次磁盘持久化文件（重启后仍有效）。"""
    path = _COOKIE_FILES.get(target) or _CACHE_DIR.joinpath(
        f"ytdlp_cookies_{target}.txt"
    )
    return path if path.exists() else None


def _is_bot_check(text: str) -> bool:
    markers = (
        "Sign in to confirm",
        "not a bot",
        "The page needs to be reloaded",
        "This content isn't available",
    )
    return any(m in text for m in markers)


_FALLBACK_CLIENTS = ("android_vr", "tv_simply", "web_embedded", "mweb", "tv")


def _client_opts(client: str | None) -> dict:
    if not client:
        return {}
    return {"extractor_args": {"youtube": {"player_client": [client]}}}


def _base_opts(logger_cb: Callable[[str], None]) -> dict:
    global _RUNTIME_MISSING
    _RUNTIME_MISSING = False
    # yt-dlp 默认只启用 deno；显式开启全部运行时探测，
    # 否则机器上只有 node/bun 时无法解 YouTube 的 JS 挑战
    # quickjs 传内置 qjs 的显式路径：新机器上没有任何系统运行时时作为兜底
    # （yt-dlp 固定优先级 deno > node > quickjs > bun，装有 node/deno 的机器不受影响）
    runtimes: dict[str, dict] = {"deno": {}, "node": {}, "bun": {}}
    qjs = find_qjs()
    runtimes["quickjs"] = {"path": qjs} if qjs else {}
    opts = {
        "quiet": True,
        "no_warnings": True,
        "noprogress": True,
        "socket_timeout": 30,
        "retries": 5,
        "logger": _YtdlpLogger(logger_cb),
        "js_runtimes": runtimes,
    }
    return opts


class _YtdlpLogger:
    def __init__(self, cb: Callable[[str], None]):
        self._cb = cb

    def debug(self, msg: str) -> None:
        pass

    def info(self, msg: str) -> None:
        self._cb(str(msg))

    def warning(self, msg: str) -> None:
        global _RUNTIME_MISSING
        text = str(msg)
        if (
            "No supported JavaScript runtime could be found" in text
            or "challenge solving failed" in text
            or "Signature solving failed" in text
        ):
            _RUNTIME_MISSING = True
        self._cb(f"[警告] {text}")

    def error(self, msg: str) -> None:
        self._cb(f"[错误] {msg}")


def _extract_sync(clean: str, flat: bool, platform: str, extra: dict) -> dict:
    from yt_dlp import YoutubeDL

    opts = _base_opts(lambda _: None)
    opts.update(
        {
            "skip_download": True,
            "noplaylist": not flat,
            "extract_flat": "in_playlist" if flat else False,
            # 预览阶段快速失败，避免网络不通时长时间等待
            "socket_timeout": 15,
            "retries": 1,
        }
    )
    cookie_file = _cookie_path(platform)
    if cookie_file:
        opts["cookiefile"] = str(cookie_file)
    opts.update(extra)
    with YoutubeDL(opts) as ydl:
        info = ydl.extract_info(clean, download=False)
    if info is None:
        raise RuntimeError("未能获取视频信息")
    return ydl.sanitize_info(info)


async def extract_preview(url: str, platform: str, kind: str) -> dict:
    """提取预览信息。单视频返回标题/UP主/封面/时长/清晰度列表；
    批量返回条目数与前若干个标题。"""
    clean = url.strip()
    flat = kind == "batch"
    try:
        info = await asyncio.to_thread(_extract_sync, clean, flat, platform, {})
    except Exception as e:
        message = str(e)
        if platform == "youtube" and _is_bot_check(message):
            last = e
            for client in _FALLBACK_CLIENTS:
                try:
                    info = await asyncio.to_thread(
                        _extract_sync,
                        clean,
                        flat,
                        platform,
                        _client_opts(client),
                    )
                    break
                except Exception as e2:
                    last = e2
            else:
                raise RuntimeError(_friendly_error(last)) from last
        else:
            raise RuntimeError(_friendly_error(message)) from e

    result: dict = {"kind": kind}
    if flat:
        entries = list(info.get("entries") or [])
        result.update(
            {
                "title": info.get("title") or "",
                "uploader": info.get("uploader") or info.get("uploader_id") or "",
                "item_count": info.get("playlist_count") or len(entries) or None,
                "sample_titles": [
                    str(e.get("title") or e.get("id"))
                    for e in entries[:20]
                    if isinstance(e, dict)
                ],
            }
        )
        return result
    result.update(
        {
            "title": info.get("title") or "",
            "uploader": info.get("uploader") or "",
            "thumbnail": info.get("thumbnail") or "",
            "duration": info.get("duration"),
            "webpage_url": info.get("webpage_url") or clean,
            "formats": _norm_formats(info),
        }
    )
    return result


def _norm_formats(info: dict) -> list[dict]:
    best: dict[int, dict] = {}
    for f in info.get("formats") or []:
        if not isinstance(f, dict):
            continue
        height = f.get("height")
        if not height or f.get("vcodec") in (None, "none"):
            continue
        score = f.get("tbr") or 0
        kept = best.get(height)
        if kept is None or score > (kept.get("_score") or 0):
            best[height] = {
                "_score": score,
                "format_id": str(f.get("format_id") or ""),
                "label": f"{height}P" + ("60帧" if (f.get("fps") or 0) >= 50 else ""),
                "ext": f.get("ext") or "",
                "filesize": f.get("filesize") or f.get("filesize_approx"),
                "height": height,
                "_note": f.get("format_note") or "",
            }
    formats = sorted(best.values(), key=lambda x: x["height"], reverse=True)
    for f in formats:
        f.pop("_score", None)
    return formats


def _format_selector(fmt: str | None) -> tuple[str, str]:
    """返回 (yt-dlp format 选择器, 日志描述)。纯数字按高度上限处理。"""
    if not fmt:
        return "bestvideo*+bestaudio/best", "最高画质（自动合并最佳视频+音频）"
    if fmt.isdigit():
        h = int(fmt)
        return (
            f"bestvideo*[height<={h}]+bestaudio/best[height<={h}]/best",
            f"画质：不超过 {h}P",
        )
    return fmt, f"格式选择器：{fmt}"


async def run_ytdlp_download(
    task: dict,
    tasks_mgr: Any,
    url: str,
    root: Path,
    format_id: str | None = None,
    control: Any = None,
) -> None:
    """执行下载任务，通过 tasks_mgr 记录日志与进度。

    control 为 TaskControl 时支持暂停/取消：progress hook 里轮询信号并抛
    TaskInterrupted 中止 yt-dlp（.part 分块文件保留，恢复时自动续传）。
    """
    from yt_dlp import YoutubeDL

    clean = url.strip()
    detection = detect_platform(clean)
    if detection is None:
        tasks_mgr.finish(task, False, "链接不是受支持的B站/YouTube格式")
        return
    platform, kind = detection
    platform_name = "B站" if platform == "bili" else "YouTube"

    def log(text: str) -> None:
        tasks_mgr.append_log(task, text)

    ffmpeg = find_ffmpeg()
    if not ffmpeg:
        searched = "、".join(str(c) for c in _ffmpeg_search_dirs())
        message = (
            f"未找到 ffmpeg（合并音视频必需）。已查找：{searched}。"
            "请把 ffmpeg.exe 放到以上任一目录后重试；"
            "若目录中确有 ffmpeg.exe 却仍报错，"
            "多半是被杀毒软件（360/Defender）隔离了，请恢复该文件或重新解压程序"
        )
        log(f"任务异常：{message}")
        tasks_mgr.finish(task, False, message)
        return

    def hook(d: dict) -> None:
        if control is not None:
            # 暂停/取消检查点：hook 在 yt-dlp 下载循环内同步触发
            if control.cancel_event.is_set():
                raise TaskInterrupted("cancel")
            if control.pause_event.is_set():
                raise TaskInterrupted("pause")
        status = d.get("status")
        if status == "downloading":
            total = d.get("total_bytes") or d.get("total_bytes_estimate") or 0
            done = d.get("downloaded_bytes") or 0
            name = Path(d.get("filename") or "").name[:60]
            tasks_mgr.set_progress(
                task,
                done,
                total,
                message=name,
                speed=d.get("speed"),
                eta=d.get("eta"),
            )
        elif status == "finished":
            tasks_mgr.set_progress(task, 0, 0, message="正在合并音视频…")
            log("文件下载完成，正在合并音视频…")

    def attempt(client: str | None) -> dict:
        selector, _ = _format_selector(format_id)
        opts = _base_opts(log)
        opts.update(
            {
                "format": selector,
                "outtmpl": str(root.joinpath("%(title).100s [%(id)s].%(ext)s")),
                "noplaylist": kind == "video",
                "ffmpeg_location": ffmpeg,
                "progress_hooks": [hook],
                "concurrent_fragment_downloads": 5,
            }
        )
        cookie_file = _cookie_path(platform)
        if cookie_file:
            opts["cookiefile"] = str(cookie_file)
            log(f"使用已导入的 {platform_name} Cookie")
        if client:
            log(f"尝试备用客户端 {client} 绕过风控…")
            opts.update(_client_opts(client))
        with YoutubeDL(opts) as ydl:
            info = ydl.extract_info(clean, download=True)
            if info is None:
                raise RuntimeError("下载失败：未返回结果信息")
        return info

    def work() -> None:
        try:
            info = attempt(None)
        except TaskInterrupted:
            raise  # 暂停/取消不能触发备用客户端重试
        except Exception as e:
            if platform == "youtube" and _is_bot_check(str(e)):
                last = e
                for client in _FALLBACK_CLIENTS:
                    try:
                        info = attempt(client)
                        break
                    except TaskInterrupted:
                        raise
                    except Exception as e2:
                        last = e2
                else:
                    raise last
            else:
                raise
        if kind == "batch":
            entries = info.get("entries")
            count = len(entries) if entries is not None else "?"
            log(f"批量处理完成，共 {count} 个条目")
        tasks_mgr.set_meta(task, title=info.get("title"))

    log(f"开始下载{platform_name}{'单视频' if kind == 'video' else '列表'}内容")
    log(f"保存目录：{root}")
    _, selector_note = _format_selector(format_id)
    log(f"画质策略：{selector_note}")
    try:
        await asyncio.to_thread(work)
        tasks_mgr.finish(task, True, "下载完成，可在保存目录查看文件")
    except TaskInterrupted as e:
        if e.action == "pause":
            tasks_mgr.set_status(task, "paused", "已暂停（进度保留，可继续）")
            log("任务已暂停，继续时自动断点续传")
        else:
            tasks_mgr.set_status(task, "cancelled", "任务已取消")
            log("任务已取消")
    except Exception as e:
        message = _friendly_error(e)
        log(f"任务异常：{message}")
        tasks_mgr.finish(task, False, message)


def _friendly_error(e: Exception | str) -> str:
    text = str(e)
    if "ffmpeg" in text.lower():
        return text.split("ERROR:")[0].strip() or text
    if "Unsupported URL" in text:
        return "暂不支持该链接（yt-dlp 无法解析此地址）"
    if "Private video" in text or "members-only" in text:
        return "该内容为私有或会员专享，需要对应权限的 Cookie"
    login_wall = any(
        m in text
        for m in (
            "Sign in to confirm",
            "not a bot",
            "The page needs to be reloaded",
        )
    )
    if not login_wall and "This content isn't available" in text:
        return (
            "视频不可用或访问受限：可能已被删除、设为私享或存在地区限制，"
            "也可能是当前网络被 YouTube 风控，可更换网络后重试"
        )
    if login_wall or ("age" in text.lower() and "restrict" in text.lower()):
        if _RUNTIME_MISSING:
            return (
                "本机缺少可用的 JavaScript 运行时（内置 qjs 未找到或不可用），"
                "无法完成 YouTube 解析。安装包可能不完整，"
                "请重新解压安装包后重试"
            )
        if _cookie_path("youtube") is not None:
            return (
                "已导入 Cookie 但仍触发 YouTube 风控验证，"
                "通常是当前网络/代理 IP 被 YouTube 风控"
                "（Cookie 本身可能有效）。建议更换网络环境或代理节点后重试；"
                "Cookie 导入已久的话也可尝试重新导入"
            )
        return (
            "YouTube 风控验证：需要登录态。请点击右上角钥匙图标 →"
            "「一键导入全部 Cookie」或「导入YouTube Cookie」"
            "（导入前先完全关闭浏览器）后重试"
        )
    return text[:300]
