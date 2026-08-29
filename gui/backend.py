import argparse
import asyncio
import os
import sys
import threading
from pathlib import Path

if getattr(sys, "frozen", False):
    env_root = os.environ.get("DOUK_HOME")
    PROJECT_ROOT = (
        Path(env_root).resolve()
        if env_root
        else Path(sys.executable).resolve().parent
    )
    # In frozen mode, src modules are bundled, but ensure _MEIPASS is in path for data files
    meipass = getattr(sys, "_MEIPASS", None)
    if meipass and meipass not in sys.path:
        sys.path.insert(0, meipass)
else:
    PROJECT_ROOT = Path(__file__).resolve().parent.parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))
os.chdir(PROJECT_ROOT)

from src.application.TikTokDownloader import TikTokDownloader
from src.application.main_server import APIServer

from gui.api_ext import setup_gui_routes


def watch_parent_process():
    """Flutter 以管道持有本进程 stdin 且从不写入；读到 EOF 即父进程已退出。
    isatty 守卫保证双击/控制台直启（非管道）不会武装本监视器。
    用 os.read 读原始描述符，避免解释器关闭时 io 缓冲区锁导致的
    Fatal Python error: _enter_buffered_busy。"""

    def reader():
        try:
            fd = sys.stdin.fileno()
            while os.read(fd, 4096):
                pass
        except Exception:
            pass
        os._exit(0)

    threading.Thread(target=reader, daemon=True).start()


class GuiAPIServer(APIServer):
    def __init__(self, parameter, database, application):
        super().__init__(parameter, database)
        self.application = application

    def setup_routes(self):
        super().setup_routes()
        setup_gui_routes(self, self.application)


async def start(port: int, host: str = "127.0.0.1"):
    async with TikTokDownloader() as application:
        application.check_config()
        # 程序根目录的 data 是 Flutter 资源目录，不是旧版数据目录，
        # 旧版目录迁移会误搬它并因文件被 GUI 占用而崩溃，必须跳过
        application.skip_folder_migration = True
        await application.check_settings(False)
        server = GuiAPIServer(
            application.parameter,
            application.database,
            application,
        )
        print(f"[夜星视频下载器] backend ready: http://{host}:{port}", flush=True)
        await server.run_server(host, port)


def main():
    parser = argparse.ArgumentParser(description="夜星视频下载器 后端服务")
    parser.add_argument("--host", type=str, default="127.0.0.1")
    parser.add_argument("--port", type=int, default=5555)
    args = parser.parse_args()
    if sys.stdin is not None and not sys.stdin.isatty():
        watch_parent_process()
    try:
        asyncio.run(start(args.port, args.host))
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
