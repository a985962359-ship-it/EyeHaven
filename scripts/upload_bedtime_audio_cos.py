#!/usr/bin/env python3
"""把 EyeHaven/BedtimeAudio 上传到腾讯云 COS，供 App 云端播放。

用法（先在腾讯云开好存储桶，并装好 coscmd 或填环境变量）：

  export COS_SECRET_ID=xxx
  export COS_SECRET_KEY=xxx
  export COS_BUCKET=你的桶名-数字ID
  export COS_REGION=ap-guangzhou
  python3 scripts/upload_bedtime_audio_cos.py

上传后把打印出的 BaseURL 填进 Xcode：
  INFOPLIST_KEY_BedtimeAudioBaseURL
"""
from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
AUDIO = ROOT / "EyeHaven" / "BedtimeAudio"


def main() -> int:
    if not AUDIO.is_dir():
        print("找不到", AUDIO, file=sys.stderr)
        return 1
    secret_id = os.environ.get("COS_SECRET_ID", "").strip()
    secret_key = os.environ.get("COS_SECRET_KEY", "").strip()
    bucket = os.environ.get("COS_BUCKET", "").strip()
    region = os.environ.get("COS_REGION", "ap-guangzhou").strip()
    prefix = os.environ.get("COS_PREFIX", "bedtime-audio").strip().strip("/")

    if not all([secret_id, secret_key, bucket]):
        print(
            "请先设置环境变量 COS_SECRET_ID / COS_SECRET_KEY / COS_BUCKET\n"
            "可在腾讯云 → 访问管理 → API密钥 创建。\n"
            "存储桶：对象存储 COS → 创建桶（公有读私有写，或用 CDN）。",
            file=sys.stderr,
        )
        return 2

    # 优先 coscmd
    conf = Path.home() / ".cos.conf"
    conf.write_text(
        f"""[common]
secret_id = {secret_id}
secret_key = {secret_key}
bucket = {bucket}
region = {region}
max_thread = 5
scheme = https
""",
        encoding="utf-8",
    )
    print("已写", conf)

    # 上传正文
    cmd = [
        "coscmd",
        "upload",
        "-rs",
        str(AUDIO),
        f"{prefix}/",
        "--ignore",
        "Distance/*",
    ]
    print("运行:", " ".join(cmd))
    try:
        subprocess.check_call(cmd)
    except FileNotFoundError:
        print("未安装 coscmd。请先执行: pip3 install coscmd", file=sys.stderr)
        return 3
    except subprocess.CalledProcessError as e:
        return e.returncode

    # 桶名形如 name-1250000000
    base = f"https://{bucket}.cos.{region}.myqcloud.com/{prefix}/"
    print("\n上传完成。请把下面这一行填进 Xcode（Debug/Release 两处 INFOPLIST_KEY_BedtimeAudioBaseURL）：")
    print(base)
    print("\n然后重新编译装机。听过的故事会缓存在手机里，下次可离线。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
