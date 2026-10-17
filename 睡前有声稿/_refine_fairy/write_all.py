# -*- coding: utf-8 -*-
"""覆盖写入 S001–S100 精修稿。不动 RestSession，不 commit。"""
from pathlib import Path
import importlib.util
import re

ROOT = Path("/Users/song/EyeHaven/睡前有声稿/光光睡前小故事")

def load_batch(name):
    path = Path(__file__).parent / name
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.STORIES

def main():
    stories = {}
    stories.update(load_batch("batch_01_30.py"))
    stories.update(load_batch("batch_31_60.py"))
    stories.update(load_batch("batch_61_100.py"))
    assert len(stories) == 100, len(stories)

    banned = [
        "麻烦的芯是",
        "情节沿着公版",
        "开场：光光",
        "第X幕",
        "【加长段】",
        "故事的核是",
        "有声名：",
    ]
    short, long, bad = [], [], []
    written = 0
    for sid, s in sorted(stories.items()):
        age = s["age"]
        title = s["title"]
        folder = ROOT / age
        folder.mkdir(parents=True, exist_ok=True)
        # 清理旧文件名可能不同：先按编号找
        for old in folder.glob(f"{sid}-*.md"):
            if old.name != f"{sid}-{title}.md":
                old.unlink()
        path = folder / f"{sid}-{title}.md"
        body = s["body"].strip()
        # 去掉样板里误留的英文 hop
        body = body.replace(" hop ", " 跳 ").replace("hop ", "跳 ")
        text = (
            f"# {title}\n"
            f"系列：光光睡前小故事（精修）\n"
            f"年龄：{age}\n"
            f"来源：{s['source']}\n"
            f"估时：约{s['mins']}分钟\n"
            f"\n"
            f"{body}\n"
        )
        path.write_text(text, encoding="utf-8")
        written += 1
        # 正文汉字大约计数（去掉空白）
        pure = re.sub(r"\s+", "", body)
        n = len(pure)
        if n < 450:
            short.append((sid, n, title))
        if n > 900:
            long.append((sid, n, title))
        for b in banned:
            if b in text:
                bad.append((sid, b))

    print(f"written={written}")
    print(f"short(<450)={len(short)} {short[:10]}")
    print(f"long(>900)={len(long)} {long[:10]}")
    print(f"banned_hits={bad}")
    # 抽查路径存在
    for sid in ("S001", "S033", "S050", "S071", "S100"):
        matches = list(ROOT.rglob(f"{sid}-*.md"))
        print(sid, matches[0] if matches else "MISSING")

if __name__ == "__main__":
    main()
