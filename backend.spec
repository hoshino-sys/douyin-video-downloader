# -*- mode: python ; coding: utf-8 -*-
import os

from PyInstaller.utils.hooks import collect_all

datas = [('static', 'static'), ('locale', 'locale')]
binaries = []
hiddenimports = []
tmp_ret = collect_all('emoji')
datas += tmp_ret[0]; binaries += tmp_ret[1]; hiddenimports += tmp_ret[2]
tmp_ret = collect_all('yt_dlp_ejs')
datas += tmp_ret[0]; binaries += tmp_ret[1]; hiddenimports += tmp_ret[2]

# ffmpeg 随后端分发（_internal 根目录），无 PATH 环境也可合并音视频
_ffmpeg_dir = os.path.join(SPECPATH, 'vendor', 'ffmpeg')
if os.path.exists(os.path.join(_ffmpeg_dir, 'ffmpeg.exe')):
    for _name in ('ffmpeg.exe', 'ffprobe.exe'):
        binaries.append((os.path.join(_ffmpeg_dir, _name), '.'))
else:
    print(f'WARNING: vendor/ffmpeg 缺少 ffmpeg.exe，后端将不含内置 ffmpeg')

# 内置 quickjs(qjs.exe) 作为 JS 运行时兜底：yt-dlp 解 YouTube JS 挑战必需，
# 新机器上无 node/deno 时靠 platforms_yt.find_qjs 的显式 path 使用
_qjs_exe = os.path.join(SPECPATH, 'vendor', 'qjs', 'qjs.exe')
if os.path.exists(_qjs_exe):
    binaries.append((_qjs_exe, '.'))
else:
    print('WARNING: vendor/qjs 缺少 qjs.exe，无 JS 运行时的电脑将无法解析 YouTube')


a = Analysis(
    ['gui\\backend.py'],
    pathex=[],
    binaries=binaries,
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
    optimize=0,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name='夜星视频下载器后端',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=True,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)
coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name='夜星视频下载器后端',
)
