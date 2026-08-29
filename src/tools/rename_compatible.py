from ..custom import PROJECT_ROOT
from shutil import copy2


class RenameCompatible:
    # 历史库名按启用时间排序：yexing-video-downloader 为当前库名，
    # 首次启动时按顺序认领旧库并复制为新名（旧库保留不删）
    LEGACY_DB_FILES = (
        "TikTokDownloader.db",
        "DouK-Downloader.db",
    )
    DB_FILE = "yexing-video-downloader.db"

    @classmethod
    def migration_file(
        cls,
    ):
        new = PROJECT_ROOT.joinpath(cls.DB_FILE)
        if new.exists():
            return
        for name in cls.LEGACY_DB_FILES:
            # 打包版历史版本可能把库放在应用根目录而非 Volume 内
            for old in (PROJECT_ROOT.joinpath(name), PROJECT_ROOT.parent.joinpath(name)):
                if old.exists():
                    copy2(old.resolve(), new.resolve())
                    return
