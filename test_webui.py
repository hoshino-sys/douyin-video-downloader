from src.application.TikTokDownloader import TikTokDownloader
import asyncio
import sys

# 解决 Windows 下 ProactorEventLoop 问题（如果有）
if sys.platform == 'win32':
    asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())

async def run():
    print("Starting WebUI test...")
    async with TikTokDownloader() as app:
        print("TikTokDownloader initialized.")
        # Initialize necessary components
        app.check_config()
        await app.check_settings(False)
        # 直接调用 server 方法
        await app.server()

if __name__ == "__main__":
    try:
        asyncio.run(run())
    except KeyboardInterrupt:
        pass
