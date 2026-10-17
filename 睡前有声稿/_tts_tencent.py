#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""腾讯云长文本语音：把 S201 起的少年故事录成 mp3。

密钥只从环境变量读，不写进文件：
  TENCENTCLOUD_SECRET_ID / TENCENTCLOUD_SECRET_KEY
"""
from __future__ import annotations

import base64
import os
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent
OUT = Path("/Users/song/EyeHaven/EyeHaven/BedtimeAudio")


def body_of(path: Path) -> str:
    body = []
    started = False
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("#") or line.startswith(("系列：", "年龄：", "来源：", "估时：")):
            continue
        if not started:
            if not line.strip():
                continue
            started = True
        body.append(line)
    return "\n".join(body).strip()


def chunks(text: str, limit: int = 140) -> list[str]:
    parts: list[str] = []
    buf = ""
    for ch in text:
        buf += ch
        if len(buf) >= limit and ch in "。！？；\n":
            parts.append(buf.strip())
            buf = ""
        elif len(buf) >= limit:
            cut = max(buf.rfind("。"), buf.rfind("，"), buf.rfind("、"))
            if cut < 40:
                cut = limit
            parts.append(buf[: cut + 1].strip())
            buf = buf[cut + 1 :]
    if buf.strip():
        parts.append(buf.strip())
    safe: list[str] = []
    for part in parts:
        part = part.strip()
        while len(part) > 140:
            safe.append(part[:140])
            part = part[140:].strip()
        if part:
            safe.append(part)
    return safe


def main() -> None:
    sid = os.environ.get("TENCENTCLOUD_SECRET_ID", "")
    sk = os.environ.get("TENCENTCLOUD_SECRET_KEY", "")
    if not sid or not sk:
        print("还没有腾讯云语音密钥，没法录音。")
        sys.exit(2)
    from tencentcloud.common import credential
    from tencentcloud.common.profile.client_profile import ClientProfile
    from tencentcloud.common.profile.http_profile import HttpProfile
    from tencentcloud.tts.v20190823 import tts_client, models

    voice = int(os.environ.get("TENCENT_TTS_VOICE", "101001"))
    force = os.environ.get("TENCENT_TTS_FORCE", "") == "1"
    cred = credential.Credential(sid, sk)
    http = HttpProfile(endpoint="tts.tencentcloudapi.com")
    client = tts_client.TtsClient(cred, "ap-guangzhou", ClientProfile(httpProfile=http))
    OUT.mkdir(parents=True, exist_ok=True)
    files = sorted((ROOT / "光光睡前小故事" / "13-15岁").glob("S2*.md"))
    files = [p for p in files if "S201" <= p.stem[:4] <= "S248"]
    tmp = OUT / "_tts_tmp"
    titles = OUT / "Titles"
    tmp.mkdir(parents=True, exist_ok=True)
    titles.mkdir(parents=True, exist_ok=True)

    def speak(text: str, key: str) -> bytes:
        req = models.TextToVoiceRequest()
        req.Text = text
        req.SessionId = f"{key}-{int(time.time() * 1000)}"
        req.ModelType = 1
        req.VoiceType = voice
        req.Codec = "mp3"
        req.SampleRate = 16000
        req.Volume = 5
        req.Speed = 0
        last_err: Exception | None = None
        for _ in range(3):
            try:
                resp = client.TextToVoice(req)
                time.sleep(0.12)
                return base64.b64decode(resp.Audio)
            except Exception as err:  # noqa: BLE001
                last_err = err
                time.sleep(1)
        raise RuntimeError(key) from last_err

    for path in files:
        story_id = path.stem.split("-")[0]
        title = path.stem.split("-", 1)[1]
        dest = OUT / f"{story_id}.mp3"
        title_dest = titles / f"{story_id}.mp3"
        if force or not (dest.exists() and dest.stat().st_size > 8000):
            parts = []
            for i, piece in enumerate(chunks(body_of(path))):
                parts.append(speak(piece, f"{story_id}-{i}"))
            dest.write_bytes(b"".join(parts))
            print("正文", dest.name, dest.stat().st_size, flush=True)
        else:
            print("正文已有", dest.name)
        if force or not (title_dest.exists() and title_dest.stat().st_size > 500):
            title_dest.write_bytes(speak(f"请听，{title}", f"{story_id}-title"))
            print("篇名", title_dest.name, title_dest.stat().st_size, flush=True)
        else:
            print("篇名已有", title_dest.name)
    print("全部结束")


if __name__ == "__main__":
    main()
