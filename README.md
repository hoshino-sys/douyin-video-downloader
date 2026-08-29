<div align="center">

# 夜星视频下载器

**抖音 / TikTok / Bilibili / YouTube 视频与图集采集下载工具**

`yexing-video-downloader` · Windows 桌面应用（无需命令行）

</div>

---

## 📝 简介

夜星视频下载器是一款完全开源的免费视频下载工具，提供开箱即用的 Windows 桌面图形界面：

- **抖音**：无水印视频、图集、直播拉流、账号作品批量下载、评论/搜索/热榜数据采集
- **TikTok**：视频、图集、账号发布/喜欢作品批量下载、直播拉流
- **Bilibili**：视频（含番剧/合集）下载，多清晰度可选
- **YouTube**：视频下载，多清晰度/格式可选，自动求解 JS 签名挑战（无需额外安装 Node.js/Deno）
- **图形界面**：粘贴链接即可下载，实时下载进度（速度/剩余时间）、任务管理、按平台区分的 Cookie 状态提示
- **应用内更新**：一键检查并下载新版本

## 📥 下载安装

前往 [Releases](https://github.com/hoshino-sys/douyin-video-downloader/releases/latest) 下载最新的
`yexing-video-downloader_v*.zip`，解压后运行 `夜星视频下载器.exe`（或 `启动.bat`）即可。

已安装旧版本时，可在软件内「设置 → 关于 → 检查更新」直接在应用内下载新版本。

> 内置 ffmpeg 与 quickjs 运行时，无需额外安装任何依赖；首次使用请按界面提示导入各平台 Cookie。

## 🔑 Cookie 获取

详细的 Cookie 获取步骤见 [docs/Cookie获取教程.md](docs/Cookie获取教程.md)。

软件内也可通过「Cookie 管理」向导按平台导入（支持浏览器自动读取与手动粘贴）。

## 🛠 从源码构建

环境要求：Python 3.12（严格 `<3.13`）、Flutter 3.47+（Windows 桌面支持）、Git。

```bash
git clone https://github.com/hoshino-sys/douyin-video-downloader.git
cd douyin-video-downloader
pip install -r requirements.txt

# 一键打包（PyInstaller 后端 + Flutter 前端 + 组装发布目录 + 分发包冒烟测试）
# 需要 vendor/ffmpeg/ffmpeg.exe、ffprobe.exe 与 vendor/qjs/qjs.exe
D:/Python 3.12/python.exe build_release.py --zip
```

开发调试：

```bash
python main.py          # 终端交互模式
python test_webui.py    # WebAPI 模式（文档见 /docs）
cd gui/flutter_app && flutter run -d windows   # GUI（自动拉起 Python 后端）
```

## 📄 免责声明

本工具仅供学习交流与个人使用，请勿用于任何商业用途或非法用途；下载内容版权归原作者所有；
使用本工具产生的任何问题由使用者自行承担。详见软件内《服务条款》。

## 🙏 致谢

- 上游项目 [JoeanAmier/TikTokDownloader](https://github.com/JoeanAmier/TikTokDownloader)（DouK-Downloader），
  本项目在其基础上二次开发而成，感谢原作者的开源贡献。
- [yt-dlp](https://github.com/yt-dlp/yt-dlp) 与 [yt-dlp-ejs](https://github.com/yt-dlp/yt-dlp-ejs) 提供 B站/YouTube 下载能力。

## 📃 许可证

[GPL-3.0](LICENSE)
