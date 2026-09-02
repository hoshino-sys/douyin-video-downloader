"""任务控制通道：暂停/取消信号与中断异常，供 api_ext 与 platforms_yt 共用。

两类任务的暂停机制不同：
- 抖音/TikTok（asyncio 协程）：pause/cancel 通过 Task.cancel() 触发
  CancelledError，由任务包装协程捕获后按 request 标记状态；
- B站/YouTube 与更新包下载（线程内分块循环）：循环/hook 检查 Event，
  触发 TaskInterrupted 中止（yt-dlp 的 .part 与更新包半截文件保留，
  恢复时自动断点续传）。
"""

import threading


class TaskInterrupted(Exception):
    """下载循环内抛出的暂停/取消信号。action: "pause" | "cancel" """

    def __init__(self, action: str):
        super().__init__(action)
        self.action = action


class TaskControl:
    """单个任务的执行控制句柄（内存态，随进程生命周期，不持久化）。"""

    def __init__(self, asyncio_based: bool = True):
        # asyncio_based=True：抖音/TikTok 任务，暂停/取消走 aio_task.cancel()
        # asyncio_based=False：ytdlp/更新包下载（线程内运行，cancel() 杀不掉
        # 线程），走分块循环轮询的 Event 信号
        self.asyncio_based = asyncio_based
        self.pause_event = threading.Event()
        self.cancel_event = threading.Event()
        # asyncio 类任务：暂停/取消端点先写入 request 再 cancel()，
        # 包装协程捕获 CancelledError 后按它区分标记 paused/cancelled
        self.request: str | None = None
        self.aio_task = None  # asyncio.Task 句柄
        self.rerun = None  # 恢复时重新执行的协程函数（无参，返回协程）
        # 取消即放弃的文件产物（仅更新包下载任务设置）：运行中取消由
        # TaskInterrupted 分支删除；暂停态取消时执行体已退出，由取消端点删除
        self.artifact = None
