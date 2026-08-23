from asyncio import create_task as aio_create_task
from datetime import datetime
from typing import TYPE_CHECKING
from uuid import uuid4

from fastapi import Depends, HTTPException
from pydantic import BaseModel

from src.application.main_server import token_dependency
from src.custom import __VERSION__
from src.models import Settings
from src.tools import Browser

if TYPE_CHECKING:
    from src.application.main_server import APIServer
    from src.application.TikTokDownloader import TikTokDownloader

__all__ = ["setup_gui_routes"]

GUI_TAG = "GUI"


class BrowserRequest(BaseModel):
    browser: str


class PasteRequest(BaseModel):
    text: str


class GuiTaskRequest(BaseModel):
    type: str
    platform: str = "douyin"
    data: dict | None = None
    sec_user_id: str | None = None
    tab: str = "post"
    earliest: str = ""
    latest: str = ""
    label: str = ""


class TaskManager:
    def __init__(self):
        self._tasks: dict[str, dict] = {}

    def create(self, task_type: str, label: str) -> dict:
        task_id = uuid4().hex[:12]
        task = {
            "id": task_id,
            "type": task_type,
            "label": label,
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

    def set_progress(self, task: dict, current: int, total: int, message: str = "") -> None:
        task["progress"] = {
            "current": current,
            "total": total,
            "percent": int(current * 100 / total) if total else 0,
        }
        if message:
            task["message"] = message

    def finish(self, task: dict, ok: bool, message: str = "") -> None:
        task["status"] = "success" if ok else "failed"
        task["message"] = message
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
        return {"status": "ok"}

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
        return {
            "configured": bool(parameter.cookie_dict or parameter.cookie_str),
            "logged_in": bool(parameter.cookie_state),
        }

    @fast_app.get("/api/gui/cookie/browsers", tags=[GUI_TAG])
    async def cookie_browsers():
        return {"browsers": list(Browser.SUPPORT_BROWSER.keys())}

    @fast_app.post("/api/gui/cookie/browser", tags=[GUI_TAG])
    async def cookie_from_browser(
        req: BrowserRequest, token: str = Depends(token_dependency)
    ):
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

    @fast_app.post("/api/gui/cookie/paste", tags=[GUI_TAG])
    async def cookie_paste(req: PasteRequest, token: str = Depends(token_dependency)):
        text = req.text.strip()
        if not app.cookie.validate_cookie_minimal(text):
            return {"success": False, "message": "内容不是有效的 Cookie 格式，请检查后重试"}
        cookie_dict = app.cookie.extract(text, key="cookie", platform="抖音")
        server.parameter.set_cookie(cookie_dict, "")
        server.parameter.set_headers_cookie()
        return {"success": True, "logged_in": "sessionid_ss" in cookie_dict}

    @fast_app.post("/api/gui/task", tags=[GUI_TAG])
    async def create_gui_task(req: GuiTaskRequest, token: str = Depends(token_dependency)):
        is_tiktok = req.platform.lower() == "tiktok"

        if req.type == "detail":
            if not isinstance(req.data, dict) or not req.data:
                return {"status": "failed", "message": "缺少作品数据"}
            task = tasks.create("detail", req.label or "单作品下载")
            task["download_dir"] = str(server.parameter.root.resolve())
            tasks.append_log(task, f"开始下载单个作品，平台={'TikTok' if is_tiktok else '抖音'}")
            desc = req.data.get("desc", "") or req.data.get("id", "")
            if desc:
                tasks.append_log(task, f"作品：{str(desc)[:80]}")
            tasks.append_log(task, f"保存目录：{task['download_dir']}")

            async def run_detail():
                try:
                    tasks.append_log(task, "正在请求并下载文件…")
                    await server.downloader.run([req.data], "detail", tiktok=is_tiktok)
                    tasks.append_log(task, "下载流程结束")
                    tasks.finish(task, True, "下载完成")
                except Exception as e:
                    tasks.append_log(task, f"任务异常：{e}")
                    tasks.finish(task, False, str(e))

            aio_create_task(run_detail())
            return {"status": "success", "task": task}

        if req.type == "account":
            if not req.sec_user_id:
                return {"status": "failed", "message": "缺少账号 ID"}
            task = tasks.create("account", req.label or "账号作品批量下载")
            task["download_dir"] = str(server.parameter.root.resolve())
            tasks.append_log(task, f"开始批量下载，账号={req.sec_user_id} 平台={'TikTok' if is_tiktok else '抖音'} tab={req.tab}")
            if req.earliest or req.latest:
                tasks.append_log(task, f"日期筛选：{req.earliest or '不限'} 至 {req.latest or '不限'}")
            tasks.append_log(task, f"保存目录：{task['download_dir']}")
            tasks.append_log(task, "正在获取账号作品列表，这可能需要一些时间…")

            async def run_account():
                try:
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
                except Exception as e:
                    tasks.append_log(task, f"任务异常：{e}")
                    tasks.finish(task, False, str(e))

            aio_create_task(run_account())
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
