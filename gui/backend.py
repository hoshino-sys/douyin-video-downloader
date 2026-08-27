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
    def reader():
        try:
            # If stdin is already at EOF (e.g., launched without a pipe), don't exit immediately
            first = sys.stdin.buffer.read(1)
            if not first:
                return
            while sys.stdin.buffer.read(4096):
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
        await application.check_settings(False)
        server = GuiAPIServer(
            application.parameter,
            application.database,
            application,
        )
        print(f"[DouK GUI] backend ready: http://{host}:{port}", flush=True)
        await server.run_server(host, port)


def main():
    parser = argparse.ArgumentParser(description="DouK-Downloader GUI Backend")
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
