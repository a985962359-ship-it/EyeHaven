#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Rebuild BedtimeCatalog.json from current md files (3 shelves)."""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path("/Users/song/EyeHaven/睡前有声稿")
CATALOG = Path("/Users/song/EyeHaven/EyeHaven/BedtimeCatalog.json")

AGE_MAP = {"3-6岁": "kindergarten", "7-12岁": "primary", "13-15岁": "junior"}
META_PREFIXES = ("系列：", "年龄：", "来源：", "估时：", "类型：", "有声名：", "来源说明：")


def parse_md(path: Path, shelf: str):
    raw = path.read_text(encoding="utf-8")
    lines = raw.splitlines()
    m = re.match(r"^(G|S|B)(\d{3})-(.+)$", path.stem)
    sid = f"{m.group(1)}{m.group(2)}" if m else path.stem
    title = m.group(3) if m else path.stem
    age = AGE_MAP.get(path.parent.name)
    if not age:
        raise ValueError(f"unknown age folder {path.parent}")
    body = []
    started = False
    for ln in lines:
        if ln.startswith("#"):
            h = re.sub(r"^[GSB]\d{3}\s+", "", ln.lstrip("#").strip())
            if h:
                title = h
            continue
        if any(ln.startswith(p) for p in META_PREFIXES):
            continue
        if not started:
            if not ln.strip():
                continue
            started = True
        body.append(ln)
    text = re.sub(r"\n{3,}", "\n\n", "\n".join(body).strip())
    return {"id": sid, "age": age, "shelf": shelf, "title": title, "text": text}


def main():
    items = []
    for p in sorted((ROOT / "光光讲知识").rglob("G*.md")):
        items.append(parse_md(p, "knowledge"))
    for p in sorted((ROOT / "光光睡前小故事").rglob("S*.md")):
        items.append(parse_md(p, "fairy"))
    for p in sorted((ROOT / "光光讲人物").rglob("B*.md")):
        items.append(parse_md(p, "biography"))
    items.sort(key=lambda x: (x["shelf"], x["id"]))
    CATALOG.write_text(json.dumps(items, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    from collections import Counter

    print("total", len(items))
    print(Counter((i["shelf"], i["age"]) for i in items))
    print("bytes", CATALOG.stat().st_size)
    # length stats
    lens = [len(re.sub(r"\s+", "", i["text"])) for i in items]
    print("len min/avg/max", min(lens), sum(lens) // len(lens), max(lens))
    # too short
    short = [i["id"] for i, n in zip(items, lens) if n < 200]
    print("short<200", len(short), short[:10])


if __name__ == "__main__":
    main()
