#!/usr/bin/env python3
"""按角色音色表批量录音（语音合成）。支持断点续录。"""

from __future__ import annotations

import argparse
import base64
import json
import os
import re
import sys
import time
import traceback
import uuid
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent
CAST_PATH = ROOT / "_tts_cast.json"
API_URL = "https://openspeech.bytedance.com/api/v3/tts/unidirectional/sse"
OUT_ROOT = ROOT / "_音频"
LOG_PATH = OUT_ROOT / "_batch_cast.jsonl"

MOM_KEYS = ("妈妈", "母亲", "奶奶", "外婆", "姥姥", "阿姨")
DAD_KEYS = ("爸爸", "父亲", "爷爷", "外公", "姥爷", "叔叔", "舅舅")
GUANG_KEYS = ("光光",)


def load_cast() -> dict:
    return json.loads(CAST_PATH.read_text(encoding="utf-8"))


def body_from_md(path: Path) -> str:
    lines = path.read_text(encoding="utf-8").splitlines()
    i = 0
    while i < len(lines):
        line = lines[i].strip()
        if not line:
            i += 1
            continue
        if line.startswith("#") or line.startswith(("系列：", "年龄：", "来源：", "估时：")):
            i += 1
            continue
        break
    return re.sub(r"\n{3,}", "\n\n", "\n".join(lines[i:]).strip())


def age_folder(path: Path) -> str:
    return path.parent.name  # 3-6岁 / 7-12岁 / 13-15岁


def kid_role_for(cast: dict, path: Path) -> str:
    return cast.get("age_kid_role", {}).get(age_folder(path), "kid")


def guess_quote_role(before: str, kid_role: str) -> str:
    window = before[-40:]
    # 近距离说话人优先
    for key in GUANG_KEYS:
        if key in window and re.search(rf"{key}.{{0,6}}(说|问|答|笑|喊|道|讲)", window):
            return "narr"
    for key in MOM_KEYS:
        if key in window and re.search(rf"{key}.{{0,8}}(说|问|答|笑|喊|道|补充|解释|继续)", window):
            return "mom"
        if key in window and window.rstrip().endswith(("：", ":", "，", ",")):
            return "mom"
    for key in DAD_KEYS:
        if key in window and re.search(rf"{key}.{{0,8}}(说|问|答|笑|喊|道|补充|又说)", window):
            return "dad"
        if key in window and window.rstrip().endswith(("：", ":", "，", ",")):
            return "dad"
    # 「某某问/说」——非光光/爸妈 → 小孩
    if re.search(r"[\u4e00-\u9fff]{1,4}(问|说|喊|笑|嘀咕|小声说)[：:]?\s*$", window):
        name = re.search(r"([\u4e00-\u9fff]{1,4})(问|说|喊|笑|嘀咕|小声说)", window)
        if name:
            who = name.group(1)
            if who in GUANG_KEYS:
                return "narr"
            if who in MOM_KEYS:
                return "mom"
            if who in DAD_KEYS:
                return "dad"
            return kid_role
    # 光光台词常见：在引号前有光光
    if "光光" in window:
        return "narr"
    if any(k in window for k in MOM_KEYS):
        return "mom"
    if any(k in window for k in DAD_KEYS):
        return "dad"
    # 默认提问/孩子对话
    return kid_role


def split_roles(text: str, kid_role: str) -> list[tuple[str, str]]:
    """拆成 (role, text)。旁白与光光都用 narr 音色。"""
    parts: list[tuple[str, str]] = []
    pos = 0
    for m in re.finditer(r"「[^」]*」", text):
        before = text[pos : m.start()]
        if before.strip():
            parts.append(("narr", before.strip()))
        quote = m.group(0)
        role = guess_quote_role(text[: m.start()], kid_role)
        # 引号前极短引导语并入旁白已处理；引号本体按角色
        # 若引导是「朵朵问：」已在 before 里
        parts.append((role, quote))
        pos = m.end()
    tail = text[pos:]
    if tail.strip():
        parts.append(("narr", tail.strip()))
    # 合并相邻同角色
    merged: list[tuple[str, str]] = []
    for role, seg in parts:
        if merged and merged[-1][0] == role:
            merged[-1] = (role, merged[-1][1] + seg)
        else:
            merged.append((role, seg))
    return merged or [("narr", text)]


def has_speakable(text: str) -> bool:
    """接口拒绝纯标点；至少要有汉字/字母/数字才送去合成。"""
    return any(
        ("\u4e00" <= c <= "\u9fff") or c.isalnum()
        for c in text
    )


def synth_chunk(text: str, voice: dict, api_key: str, timeout: int = 180) -> bytes:
    payload = {
        "user": {"uid": "eyehaven_batch"},
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
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                buf = b""
                chunks: list[bytes] = []
                while True:
                    piece = resp.read(8192)
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
                            raise RuntimeError(f"code={code} {obj.get('message')}")
                        if obj.get("data"):
                            chunks.append(base64.b64decode(obj["data"]))
            if not chunks:
                raise RuntimeError("无音频")
            return b"".join(chunks)
        except Exception as e:
            last = e
            time.sleep(1.5 * (attempt + 1))
    raise RuntimeError(str(last))


def record_story(md: Path, cast: dict, api_key: str) -> dict:
    text = body_from_md(md)
    kid_role = kid_role_for(cast, md)
    voices = cast["voices"]
    segments = split_roles(text, kid_role)
    # 过长旁白再切，避免超时（按句）
    flat: list[tuple[str, str]] = []
    for role, seg in segments:
        if role == "narr" and len(seg) > 280:
            bits = re.split(r"(?<=[。！？])", seg)
            cur = ""
            for b in bits:
                if not b:
                    continue
                if cur and len(cur) + len(b) > 260:
                    flat.append((role, cur))
                    cur = b
                else:
                    cur += b
            if cur.strip():
                flat.append((role, cur.strip()))
        else:
            flat.append((role, seg))

    audios: list[bytes] = []
    for role, seg in flat:
        if not seg.strip() or not has_speakable(seg):
            continue
        voice = voices.get(role) or voices["narr"]
        # 单段仍太长则对半
        if len(seg) > 400:
            mid = len(seg) // 2
            cut = seg.rfind("。", 0, mid + 30)
            if cut < 20:
                cut = mid
            else:
                cut += 1
            for sub in (seg[:cut], seg[cut:]):
                if sub.strip():
                    audios.append(synth_chunk(sub.strip(), voice, api_key))
                    time.sleep(0.25)
        else:
            audios.append(synth_chunk(seg.strip(), voice, api_key))
            time.sleep(0.25)

    out = OUT_ROOT / md.relative_to(ROOT).with_suffix(".mp3")
    out.parent.mkdir(parents=True, exist_ok=True)
    tmp = out.with_suffix(".mp3.part")
    tmp.write_bytes(b"".join(audios))
    tmp.replace(out)
    return {
        "status": "ok",
        "md": str(md.relative_to(ROOT)),
        "mp3": str(out.relative_to(ROOT)),
        "segments": len(flat),
        "size": out.stat().st_size,
        "roles": sorted({r for r, _ in flat}),
    }


def log_event(obj: dict) -> None:
    LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
    with LOG_PATH.open("a", encoding="utf-8") as f:
        f.write(json.dumps(obj, ensure_ascii=False) + "\n")


def list_targets(series: str, age: str, limit: int, start_id: str) -> list[Path]:
    d = ROOT / series / age
    paths = sorted(d.glob("*.md"))
    if start_id:
        paths = [p for p in paths if p.stem.split("-")[0] >= start_id]
    if limit:
        paths = paths[:limit]
    return paths


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--api-key", default=os.environ.get("DOUBAO_TTS_API_KEY", ""))
    ap.add_argument("--series", default="光光讲知识")
    ap.add_argument("--age", default="3-6岁")
    ap.add_argument("--limit", type=int, default=20)
    ap.add_argument("--start", default="G001", help="从该编号起，如 G001")
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args()
    if not args.api_key:
        print("缺少 API Key", file=sys.stderr)
        return 1

    cast = load_cast()
    paths = list_targets(args.series, args.age, args.limit, args.start)
    print(f"计划 {len(paths)} 篇：{args.series}/{args.age} from {args.start}", flush=True)
    ok = skip = fail = 0
    t0 = time.time()
    for i, md in enumerate(paths, 1):
        out = OUT_ROOT / md.relative_to(ROOT).with_suffix(".mp3")
        if out.exists() and out.stat().st_size > 8000 and not args.force:
            skip += 1
            print(f"[{i}/{len(paths)}] skip {md.name}", flush=True)
            log_event({"status": "skip", "md": str(md.relative_to(ROOT))})
            continue
        print(f"[{i}/{len(paths)}] 录 {md.name} …", flush=True)
        try:
            info = record_story(md, cast, args.api_key)
            ok += 1
            print(
                f"  OK {info['size']}B roles={info['roles']} segs={info['segments']}",
                flush=True,
            )
            log_event(info)
        except Exception as e:
            fail += 1
            err = {"status": "fail", "md": str(md.relative_to(ROOT)), "error": str(e)}
            print(f"  FAIL {e}", flush=True)
            log_event({**err, "trace": traceback.format_exc()[-400:]})
    summary = {
        "status": "summary",
        "ok": ok,
        "skip": skip,
        "fail": fail,
        "elapsed": round(time.time() - t0, 1),
        "series": args.series,
        "age": args.age,
    }
    log_event(summary)
    print(json.dumps(summary, ensure_ascii=False), flush=True)
    return 0 if fail == 0 else 2


if __name__ == "__main__":
    raise SystemExit(main())
