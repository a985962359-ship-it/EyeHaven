#!/usr/bin/env python3
"""火山 Seed-Audio：把睡前文稿录成 mp3（/api/v3/tts/create）。支持全库断点续录。"""

from __future__ import annotations

import argparse
import base64
import json
import os
import re
import sys
import time
import traceback
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

ROOT = Path(__file__).resolve().parent
API_URL = "https://openspeech.bytedance.com/api/v3/tts/create"
MODEL = "seed-audio-1.0"
CHUNK_CHARS = 260
OUT_ROOT = ROOT / "_音频"
LOG_PATH = ROOT / "_音频" / "_progress.jsonl"
SERIES_DIRS = ("光光讲知识", "光光睡前小故事", "光光讲人物")

PROMPTS = {
    "光光讲知识": (
        "用温柔、稍慢的睡前讲故事语气，把下面这段科普小故事读给孩子听。"
        "旁白是「光光」：圆脑袋白机器人，声音软软清楚、老实、不吓人。"
        "不要背景音乐，不要音效，只要人声朗读。\n\n"
    ),
    "光光睡前小故事": (
        "用温柔、稍慢的睡前讲故事语气，把下面这段小故事读给孩子听。"
        "旁白是「光光」：圆脑袋白机器人，声音软软清楚、老实、不吓人。"
        "不要背景音乐，不要音效，只要人声朗读。\n\n"
    ),
    "光光讲人物": (
        "用温柔、稍慢的睡前讲故事语气，把下面这段人物小传读给孩子听。"
        "旁白是「光光」：圆脑袋白机器人，声音软软清楚、老实、不吓人。"
        "不要背景音乐，不要音效，只要人声朗读。\n\n"
    ),
}
CONTINUE_PROMPT = "继续用同一位「光光」的温柔睡前语气朗读，不要背景音乐，不要音效。\n\n"


def body_from_md(path: Path) -> str:
    raw = path.read_text(encoding="utf-8")
    lines = raw.splitlines()
    i = 0
    while i < len(lines):
        line = lines[i].strip()
        if not line:
            i += 1
            continue
        if (
            line.startswith("#")
            or line.startswith("系列：")
            or line.startswith("年龄：")
            or line.startswith("来源：")
            or line.startswith("估时：")
        ):
            i += 1
            continue
        break
    text = "\n".join(lines[i:]).strip()
    return re.sub(r"\n{3,}", "\n\n", text)


def split_chunks(text: str, limit: int = CHUNK_CHARS) -> list[str]:
    parts = re.split(r"(?<=[。！？」』])\s*", text)
    parts = [p for p in parts if p.strip()]
    chunks: list[str] = []
    cur = ""
    for p in parts:
        if cur and len(cur) + len(p) > limit:
            chunks.append(cur)
            cur = p
        else:
            cur = cur + p if cur else p
    if cur:
        chunks.append(cur)
    return chunks or [text]


def _call_once(
    text_prompt: str,
    api_key: str,
    *,
    speech_rate: int,
    sample_rate: int,
    timeout: int,
    retries: int = 3,
) -> tuple[bytes, dict]:
    payload = {
        "model": MODEL,
        "text_prompt": text_prompt,
        "audio_config": {
            "format": "mp3",
            "sample_rate": sample_rate,
            "pitch_rate": 0,
            "speech_rate": speech_rate,
            "loudness_rate": 0,
        },
        "watermark": {},
    }
    headers = {
        "Content-Type": "application/json",
        "X-Api-Key": api_key,
    }
    data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    last_err: Exception | None = None
    for attempt in range(1, retries + 1):
        req = urllib.request.Request(API_URL, data=data, headers=headers, method="POST")
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                raw = resp.read()
            break
        except urllib.error.HTTPError as e:
            body = e.read().decode("utf-8", errors="replace")
            last_err = RuntimeError(f"HTTP {e.code}: {body[:400]}")
            # 402 额度/时长类、401 密钥问题：少重试
            if e.code in (401, 403):
                raise last_err
            if e.code == 402 and "DurationOutOfRange" in body:
                raise last_err
            time.sleep(2 * attempt)
        except Exception as e:
            last_err = e
            time.sleep(2 * attempt)
    else:
        raise RuntimeError(str(last_err))

    if raw[:1] != b"{":
        return raw, {}

    obj = json.loads(raw.decode("utf-8"))
    if "audio" not in obj and "url" not in obj:
        raise RuntimeError(f"业务错误: {obj}")
    if obj.get("audio"):
        audio = base64.b64decode(obj["audio"])
    else:
        with urllib.request.urlopen(obj["url"], timeout=60) as r:
            audio = r.read()
    meta = {
        "duration": obj.get("duration"),
        "original_duration": obj.get("original_duration"),
    }
    return audio, meta


def series_of(md_path: Path) -> str:
    for name in SERIES_DIRS:
        if name in md_path.parts:
            return name
    return "光光讲知识"


def out_path_for(md_path: Path) -> Path:
    rel = md_path.relative_to(ROOT)
    return OUT_ROOT / rel.with_suffix(".mp3")


def synthesize(
    text: str,
    output_path: Path,
    api_key: str,
    *,
    series: str,
    speech_rate: int = 0,
    sample_rate: int = 24000,
    timeout: int = 300,
) -> dict:
    wrap = PROMPTS.get(series, PROMPTS["光光讲知识"])
    chunks = split_chunks(text)
    audios: list[bytes] = []
    total_dur = 0.0
    for idx, chunk in enumerate(chunks, 1):
        prompt = (wrap if idx == 1 else CONTINUE_PROMPT) + chunk
        # 若仍超时长，再切一半
        try:
            audio, meta = _call_once(
                prompt,
                api_key,
                speech_rate=speech_rate,
                sample_rate=sample_rate,
                timeout=timeout,
            )
        except RuntimeError as e:
            if "DurationOutOfRange" in str(e) and len(chunk) > 120:
                half = len(chunk) // 2
                # 在句号附近切开
                cut = chunk.rfind("。", 0, half + 40)
                if cut < 40:
                    cut = half
                else:
                    cut += 1
                parts = [chunk[:cut], chunk[cut:]]
                for j, sub in enumerate(parts):
                    if not sub.strip():
                        continue
                    sub_prompt = (wrap if idx == 1 and j == 0 else CONTINUE_PROMPT) + sub
                    audio, meta = _call_once(
                        sub_prompt,
                        api_key,
                        speech_rate=speech_rate,
                        sample_rate=sample_rate,
                        timeout=timeout,
                    )
                    audios.append(audio)
                    d = meta.get("duration")
                    if isinstance(d, (int, float)):
                        total_dur += float(d)
                    time.sleep(0.3)
                continue
            raise
        if len(audio) < 500:
            raise RuntimeError(f"第 {idx} 段音频过短")
        audios.append(audio)
        d = meta.get("duration")
        if isinstance(d, (int, float)):
            total_dur += float(d)
        if idx < len(chunks):
            time.sleep(0.3)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    tmp = output_path.with_suffix(".mp3.part")
    tmp.write_bytes(b"".join(audios))
    tmp.replace(output_path)
    return {
        "output": str(output_path),
        "size_bytes": output_path.stat().st_size,
        "chars": len(text),
        "chunks": len(chunks),
        "duration": total_dur or None,
    }


def list_manuscripts() -> list[Path]:
    paths: list[Path] = []
    for series in SERIES_DIRS:
        d = ROOT / series
        if not d.is_dir():
            continue
        paths.extend(sorted(d.rglob("*.md")))
    return paths


def log_event(obj: dict) -> None:
    LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
    with LOG_PATH.open("a", encoding="utf-8") as f:
        f.write(json.dumps(obj, ensure_ascii=False) + "\n")


def process_one(md: Path, api_key: str, speech_rate: int, force: bool) -> dict:
    out = out_path_for(md)
    rel = str(md.relative_to(ROOT))
    if out.exists() and out.stat().st_size > 8000 and not force:
        return {"status": "skip", "md": rel, "mp3": str(out.relative_to(ROOT))}
    text = body_from_md(md)
    if len(text) < 20:
        return {"status": "empty", "md": rel}
    series = series_of(md)
    t0 = time.time()
    info = synthesize(text, out, api_key, series=series, speech_rate=speech_rate)
    info.update(
        {
            "status": "ok",
            "md": rel,
            "seconds": round(time.time() - t0, 1),
        }
    )
    return info


def import_trial() -> None:
    trial = ROOT / "_试听"
    mapping = {
        "G001-天为什么是蓝的.mp3": ROOT / "光光讲知识/3-6岁/G001-天为什么是蓝的.md",
        "G100-近视是怎么形成的.mp3": ROOT / "光光讲知识/7-12岁/G100-近视是怎么形成的.md",
        "G196-眼睛20-20-20.mp3": ROOT / "光光讲知识/13-15岁/G196-眼睛20-20-20.md",
    }
    for name, md in mapping.items():
        src = trial / name
        if not src.exists() or not md.exists():
            continue
        dst = out_path_for(md)
        if dst.exists() and dst.stat().st_size > 8000:
            continue
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_bytes(src.read_bytes())
        print(f"导入试听 → {dst.relative_to(ROOT)}", flush=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--api-key", default=os.environ.get("DOUBAO_TTS_API_KEY", ""))
    parser.add_argument("--speech-rate", type=int, default=0)
    parser.add_argument("--workers", type=int, default=2)
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--all", action="store_true", help="录全库")
    parser.add_argument("--limit", type=int, default=0, help="最多录 N 篇（调试用）")
    parser.add_argument("paths", nargs="*", help="指定文稿；与 --all 二选一")
    args = parser.parse_args()
    if not args.api_key:
        print("缺少 API Key", file=sys.stderr)
        return 1

    import_trial()

    if args.all:
        mds = list_manuscripts()
    else:
        mds = []
        for raw in args.paths:
            p = Path(raw)
            if not p.is_absolute():
                p = ROOT / p
            mds.append(p)
    if not mds:
        print("没有要录的文稿", file=sys.stderr)
        return 1
    if args.limit:
        mds = mds[: args.limit]

    total = len(mds)
    print(f"计划 {total} 篇，workers={args.workers}", flush=True)
    ok = skip = fail = 0
    t0 = time.time()

    def run(md: Path) -> dict:
        try:
            return process_one(md, args.api_key, args.speech_rate, args.force)
        except Exception as e:
            return {
                "status": "fail",
                "md": str(md.relative_to(ROOT)),
                "error": str(e),
                "trace": traceback.format_exc()[-500:],
            }

    with ThreadPoolExecutor(max_workers=max(1, args.workers)) as ex:
        futs = {ex.submit(run, md): md for md in mds}
        done = 0
        for fut in as_completed(futs):
            done += 1
            info = fut.result()
            log_event({**info, "done": done, "total": total, "ts": time.time()})
            st = info.get("status")
            if st == "ok":
                ok += 1
                print(
                    f"[{done}/{total}] OK {info['md']} "
                    f"({info.get('size_bytes')}B, {info.get('seconds')}s)",
                    flush=True,
                )
            elif st == "skip":
                skip += 1
                if done % 20 == 0 or done == total:
                    print(f"[{done}/{total}] skip… ok={ok} skip={skip} fail={fail}", flush=True)
            else:
                fail += 1
                print(f"[{done}/{total}] FAIL {info.get('md')}: {info.get('error')}", flush=True)

    elapsed = time.time() - t0
    summary = {
        "status": "summary",
        "ok": ok,
        "skip": skip,
        "fail": fail,
        "total": total,
        "elapsed_sec": round(elapsed, 1),
    }
    log_event(summary)
    print(json.dumps(summary, ensure_ascii=False), flush=True)
    return 0 if fail == 0 else 2


if __name__ == "__main__":
    raise SystemExit(main())
