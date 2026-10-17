#!/usr/bin/env python3
"""批量录制每篇开场：请听 + 标题（少年梓辛，与正文旁白一致）。"""

from __future__ import annotations

import argparse
import base64
import json
import os
import sys
import time
import uuid
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parent
CAST_PATH = ROOT / "_tts_cast.json"
CATALOG = REPO / "EyeHaven" / "BedtimeCatalog.json"
OUT_DIR = REPO / "EyeHaven" / "BedtimeAudio" / "Titles"
API_URL = "https://openspeech.bytedance.com/api/v3/tts/unidirectional/sse"


def synth(text: str, voice: dict, api_key: str, timeout: int = 120) -> bytes:
    payload = {
        "user": {"uid": "eyehaven_title"},
        "req_params": {
            "text": text,
            "speaker": voice["speaker"],
            "audio_params": {
                "format": "mp3",
                "sample_rate": 24000,
                "speech_rate": voice.get("speech_rate", 0),
                "loudness_rate": 0,
                "pitch_rate": voice.get("pitch_rate", 0),
            },
        },
    }
    headers = {
        "Content-Type": "application/json",
        "X-Api-Key": api_key,
        "X-Api-Resource-Id": voice["resource_id"],
        "X-Api-Request-Id": str(uuid.uuid4()),
        "X-Control-Require-Usage-Tokens-Return": "text_words",
    }
    data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    last: Exception | None = None
    for attempt in range(4):
        req = urllib.request.Request(
            API_URL,
            data=data,
            headers={**headers, "X-Api-Request-Id": str(uuid.uuid4())},
            method="POST",
        )
        chunks: list[bytes] = []
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                buf = b""
                while True:
                    piece = resp.read(4096)
                    if not piece:
                        break
                    buf += piece
                    while b"\n" in buf:
                        line, buf = buf.split(b"\n", 1)
                        line = line.strip()
                        if not line.startswith(b"data:"):
                            continue
                        obj = json.loads(line[5:].strip())
                        code = obj.get("code", 0)
                        if code == 20000000:
                            continue
                        if code != 0:
                            raise RuntimeError(f"TTS code={code}: {obj.get('message', '')}")
                        if obj.get("data"):
                            chunks.append(base64.b64decode(obj["data"]))
            if not chunks:
                raise RuntimeError("未收到音频")
            return b"".join(chunks)
        except Exception as e:
            last = e
            time.sleep(1.2 * (attempt + 1))
    raise RuntimeError(last)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--api-key", default=os.environ.get("DOUBAO_TTS_API_KEY", ""))
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--only", default="", help="逗号分隔 id，如 G001,S001")
    args = ap.parse_args()
    if not args.api_key:
        print("缺少 API Key", file=sys.stderr)
        return 1

    cast = json.loads(CAST_PATH.read_text(encoding="utf-8"))
    voice = cast["voices"]["narr"]
    items = json.loads(CATALOG.read_text(encoding="utf-8"))
    only = {x.strip() for x in args.only.split(",") if x.strip()}
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    todo = []
    for item in items:
        sid = item["id"]
        if only and sid not in only:
            continue
        out = OUT_DIR / f"{sid}.mp3"
        if out.exists() and not args.force and out.stat().st_size > 1000:
            continue
        todo.append((sid, item["title"], out))
    if args.limit > 0:
        todo = todo[: args.limit]

    print(f"待录 {len(todo)} 条标题（旁白：{voice['name']}）", flush=True)
    ok = 0
    fail = 0
    for i, (sid, title, out) in enumerate(todo, 1):
        text = f"请听，{title}"
        try:
            audio = synth(text, voice, args.api_key)
            out.write_bytes(audio)
            ok += 1
            print(f"[{i}/{len(todo)}] 完成 {sid} {title} ({len(audio)} bytes)", flush=True)
        except Exception as e:
            fail += 1
            print(f"[{i}/{len(todo)}] 失败 {sid}: {e}", file=sys.stderr, flush=True)
            time.sleep(2)
        time.sleep(0.15)
    print(f"成功 {ok}，失败 {fail}，跳过已有 {len(items) - len(todo) if not only else 'n/a'}")
    return 0 if fail == 0 else 2


if __name__ == "__main__":
    raise SystemExit(main())
