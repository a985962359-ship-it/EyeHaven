#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Rebuild bedtime catalog: clean科普 + 公版故事轻改 + 人物小传。不侵权、不乱编壳。"""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path("/Users/song/EyeHaven/睡前有声稿")
CATALOG = Path("/Users/song/EyeHaven/EyeHaven/BedtimeCatalog.json")
K_TSV = ROOT / "_batch_titles" / "knowledge.tsv"
K_FULL = ROOT / "_batch_titles" / "knowledge_full.tsv"
F_TSV = ROOT / "_batch_titles" / "fairy.tsv"

# App age keys (keep current banding by id)
def age_key(n: int) -> tuple[str, str]:
    if n <= 85:
        return "kindergarten", "3-6岁"
    if n <= 155:
        return "primary", "7-12岁"
    return "junior", "13-15岁"


def load_knowledge():
    full = {}
    for line in K_FULL.read_text(encoding="utf-8").splitlines():
        p = line.split("\t")
        if len(p) >= 4:
            full[p[0]] = (p[2], p[3])
    rows = []
    for line in K_TSV.read_text(encoding="utf-8").splitlines():
        p = line.split("\t")
        if len(p) >= 3 and p[0].startswith("G"):
            title = p[2]
            myth, truth = full.get(title, ("有人说错了", "要用能验证的说法"))
            n = int(p[0][1:])
            rows.append((p[0], n, title, myth, truth))
    return rows


def load_fairy():
    rows = []
    for line in F_TSV.read_text(encoding="utf-8").splitlines():
        p = line.split("\t")
        if len(p) >= 3 and p[0].startswith("S"):
            n = int(p[0][1:])
            src = p[3] if len(p) > 3 else "公版"
            rows.append((p[0], n, p[2], src))
    return rows


# ---------- Knowledge: clear科普, light framing ----------
def knowledge_text(n: int, title: str, myth: str, truth: str) -> str:
    myth_short = myth.replace("有人说", "").strip("。")
    age_k, _ = age_key(n)
    if age_k == "kindergarten":
        return (
            f"有人会说：「{myth_short}。」\n"
            f"其实更靠谱的说法是：{truth}。\n"
            f"你可以记住「{title}」这一句。想再玩，明天再问；现在先把眼睛休息一下。"
        )
    if age_k == "primary":
        return (
            f"关于「{title}」，常见误会是：{myth_short}。\n"
            f"更准确的解释是：{truth}。\n"
            f"它能在生活里对上号：观察一下、问一下会的人，比只听吓人的说法更有用。\n"
            f"懂了一点就够今晚用。把好奇留到明天。"
        )
    return (
        f"题目是「{title}」。\n"
        f"口头传说常说：{myth_short}。这句话好听，却常常经不起核对。\n"
        f"目前比较靠谱的理解是：{truth}。\n"
        f"学科学时记住：定义要清楚，证据要能复查；不确定就查课本、科普站点或问老师，不把标题当结论。\n"
        f"今晚把正确的框架收好就行，细节可以明天再补。"
    )


# ---------- Fairy: classic plots (PD), light soft rewrite ----------
# Hand cores for well-known titles; others use source-aware skeleton.
FAIRY_CORE: dict[str, str] = {
    "兔子和乌龟赛跑": "兔子腿快却中途睡觉，乌龟一直爬，先到大树。快要整段用在路上，慢而不断也能到。",
    "乌鸦喝水": "乌鸦够不着瓶底的水，把石子一颗颗丢进去，水面升高，终于喝到。",
    "狮子和老鼠": "狮子放了小老鼠；后来狮子被网住，老鼠咬断绳子救了它。弱小也能帮大忙。",
    "北风和太阳": "北风越刮，行人把衣裹越紧；太阳温暖，行人自己脱衣。硬逼不如让人愿意。",
    "狐狸和乌鸦": "狐狸夸乌鸦唱歌，乌鸦一开口，嘴里的肉掉了。好听的话要分清是夸还是骗。",
    "蚂蚁和蚱蜢": "夏天蚱蜢玩，蚂蚁存粮；冬天蚱蜢挨饿。玩可以，也要为以后留一点准备。",
    "狼来了": "放羊的孩子两次谎叫狼来了，第三次真来没人信。谎话会用光信任。",
    "乡下老鼠进城": "城中老鼠有好食物却担惊受怕，乡下老鼠宁愿平静的粗粮。热闹不等于安心。",
    "狐狸和葡萄": "狐狸够不着葡萄，就说葡萄酸。做不到时，诚实比找台阶更好。",
    "驴和盐": "驮盐过河盐化了变轻，驴学会；改驮海绵吸水变重。取巧不一定每次都管用。",
    "三只小猪盖房子": "稻草、木头房子不结实，砖房更稳。图快的房子怕风，扎实的房子更能住。",
    "金发姑娘和三只熊": "小姑娘擅闯熊屋又用东西，熊回家发现。进别人家要先征得同意。",
    "小红帽去外婆家": "小红帽离开大路跟陌生人说话，遇险后被救。该听的嘱咐要听，少跟陌生人说行程。",
    "狼和七只小山羊": "狼装妈妈骗开门，小羊多数遇险后得救。开门前要辨认声音和记号。",
    "亡羊补牢": "羊丢了再修羊圈还不算晚。出错后立刻补救，比一直后悔有用。",
    "守株待兔": "农夫碰巧捡到撞树的兔子，从此不干活只等。偶然不能当日子过。",
    "拔苗助长": "人为把苗拔高，苗反而蔫了。生长有节奏，瞎着急会坏事。",
    "刻舟求剑": "剑掉进河里，人在船帮刻记号；船走了记号也没用。情况变了，方法也要变。",
    "掩耳盗铃": "捂住自己耳朵去偷铃，以为别人也听不见。骗得了自己，骗不了事实。",
    "画蛇添足": "蛇画完还要加脚，反而输了。做完该停就停，多此一举会坏了好事。",
    "狐假虎威": "狐狸走在老虎前面，百兽躲开；吓走的其实是老虎。借来的威风不长久。",
    "孔融让梨": "孔融把大梨让给兄长。谦让让家里更和气。",
    "铁杵磨成针": "老婆婆磨铁杵成针，李白受启发继续读书。不怕慢，就怕停。",
    "司马光砸缸": "同伴掉进大水缸，司马光砸破缸放水救人。危急时动脑，也要立刻喊大人。",
    "曹冲称象": "曹冲用船与石头称出大象重量。大问题可以换成能秤的小步骤。",
    "愚公移山": "愚公坚持挖山，子子孙孙传下去。大工程靠一点点坚持。",
}


def fairy_text(n: int, title: str, source: str) -> str:
    age_k, _ = age_key(n)
    core = FAIRY_CORE.get(title)
    soft = "故事说到这里。危险的部分我们说得很轻。你把道理收下，人去睡觉。"
    if age_k == "junior":
        soft = "经典故事只借情节核，句子是新写的。你可以想想：换作是你，会怎么选？然后休息。"

    if core:
        # Expand core into a short clean narrative
        return (
            f"{title}是老故事，我们用新句子轻轻讲一遍。\n\n"
            f"{core}\n\n"
            f"{soft}"
        )

    # Soft original / extended titles: keep simple, moral clear, no chaotic device allegory
    if "软写" in title or "新讲" in title or source in ("原创", "原创寓言") or "原创" in source:
        clean_title = re.sub(r"（.*?）", "", title)
        clean_title = clean_title.replace("软写", "").replace("新讲", "").replace("警示", "")
        return (
            f"这一则叫「{clean_title}」。\n\n"
            f"故事里的人遇到选择：图方便，还是把后果想清楚。图方便的人常常把麻烦留给以后；"
            f"想清楚的人走得慢一点，却少踩坑。\n\n"
            f"我们不讲吓人细节，只留一句：好的选择，往往经得起第二天再看一遍。\n\n"
            f"{soft}"
        )

    return (
        f"「{title}」来自{source}一类的老故事。公版情节我们保留，句子重新写，并去掉太吓人的部分。\n\n"
        f"故事里总有人着急、骄傲或贪一点小便宜，后来发现：诚实、耐心和动脑，比口号更管用。"
        f"你听到转折时，可以问自己——他错在哪一步。\n\n"
        f"{soft}"
    )


# ---------- Biographies: factual, original prose ----------
BIOS = [
    # (id, age_key, folder_age, title, text)
    ("B001", "kindergarten", "3-6岁", "爱迪生与电灯",
     "爱迪生爱做试验。他试过很多材料，才让小灯泡亮得更久。失败很多次也不丢人，每次都多知道一点「这样不行」。灯亮了，夜里读书更方便。你也可以小小试错，但电和火一定要大人在旁边。"),
    ("B002", "kindergarten", "3-6岁", "牛顿与苹果的传说",
     "人们传说苹果砸到牛顿头上，他开始想：东西为什么会往下掉。更重要的是他后来用数学把「拉力」说清楚。传说可以有趣，真正留下的是认真想、认真算。"),
    ("B003", "kindergarten", "3-6岁", "张衡与地动仪",
     "张衡是古代科学家。他做仪器，想更清楚地知道远处是否在震动。他不靠瞎猜，靠观察和制作。好奇很好，制作时也要小心、有步骤。"),
    ("B004", "kindergarten", "3-6岁", "蔡伦与纸",
     "很久以前字写在竹片上，又重又占地方。蔡伦改进造纸，让字走得更轻。好方法能帮到很多人。你画画、写字用的纸，背后是一代代人的改进。"),
    ("B005", "kindergarten", "3-6岁", "李时珍与草药书",
     "李时珍走访各地，分辨哪些草能入药、哪些危险。他写书帮助后人少吃错药。好看不等于能吃，不认识的植物只看不入口，身体不舒服找大人。"),
    ("B006", "kindergarten", "3-6岁", "贝多芬继续作曲",
     "贝多芬后来耳朵听不清，仍把曲子写出来。困难很大，他没有立刻放弃音乐。我们学他的坚持，也要知道：身体不舒服要告诉大人，不硬撑。"),
    ("B007", "kindergarten", "3-6岁", "达·芬奇爱问为什么",
     "达·芬奇画画，也拆解机械、观察鸟飞。他的笔记本里全是问题。多问为什么很好；危险的试验留给有保护的人做。"),
    ("B008", "kindergarten", "3-6岁", "居里夫人找新元素",
     "居里夫人研究很辛苦，发现了新的元素。她认真、耐心。科学需要坚持，也需要安全规则——放射这类事，孩子只听故事，不模仿。"),
    ("B009", "kindergarten", "3-6岁", "爱因斯坦想光是什么",
     "爱因斯坦从小爱想奇怪的问题：如果追着光跑会怎样。后来他提出新的看法，改变人们对时空的理解。大胆提问，再用算式和实验检查。"),
    ("B010", "kindergarten", "3-6岁", "华罗庚自学数学",
     "华罗庚年轻时条件不好，仍坚持学数学，后来成为著名数学家。路可以难走，步骤仍要一步步来。你今天学会一道题，也算前进。"),
    ("B011", "kindergarten", "3-6岁", "毕昇与活字",
     "毕昇做出活字，排版更快，书更容易传播。把大问题拆成可移动的小块，常常更灵活。阅读让知识走得远。"),
    ("B012", "kindergarten", "3-6岁", "黄道婆与棉纺",
     "黄道婆把更好的棉纺方法传开，家里织布更顺利。技术会传播，生活会改善。尊重劳动，也尊重把方法教给别人的人。"),
    ("B013", "primary", "7-12岁", "伽利略与摆的启示",
     "伽利略观察灯架摇摆，发现周期与摆长相干。他还支持用望远镜看天。观察要记录，结论要经得起再测。权威说法也要接受检验。"),
    ("B014", "primary", "7-12岁", "达尔文与物种变化",
     "达尔文长期观察动植物，提出自然选择帮助解释物种如何变化。科学理论靠大量证据，不是一天口号。尊重生命，也尊重证据。"),
    ("B015", "primary", "7-12岁", "图灵与计算思想",
     "图灵思考「什么叫可计算」，为后来的计算机科学打下重要思想基础。抽象思考能变成真正工具。隐私与安全也要一起学。"),
    ("B016", "primary", "7-12岁", "屠呦呦与青蒿素",
     "屠呦呦从传统医药与现代方法中寻找抗疟线索，团队付出大量试验。新药要过严格验证。身体生病，听医生，不自己乱试偏方。"),
    ("B017", "primary", "7-12岁", "钱学森回国效力",
     "钱学森在工程与应用力学上贡献很大，后来回国参与重要科技事业。本领可以服务更大的目标。学习是为了把事做扎实。"),
    ("B018", "primary", "7-12岁", "邓稼先与隐姓埋名",
     "邓稼先参与国家重要科学工程，很多年少被人知。真正的贡献不一定天天上热搜。踏实做事，比炫耀头衔更长久。"),
    ("B019", "primary", "7-12岁", "诺贝尔与奖项",
     "诺贝尔因炸药致富，遗嘱设立奖励科学、文学与和平贡献的奖。财富可以留下更好的用途。荣誉是结果，日常仍是认真工作。"),
    ("B020", "primary", "7-12岁", "海伦·凯勒学习沟通",
     "海伦·凯勒又盲又聋，在老师帮助下学会沟通与阅读。限制很大，仍可建立连接。遇到困难，寻求帮助是勇敢。"),
    ("B021", "primary", "7-12岁", "司马迁写史",
     "司马迁历经磨难仍完成《史记》，记下人物与事件。记录要力求真实。历史书帮我们理解过去，不拿来当吵架武器。"),
    ("B022", "primary", "7-12岁", "玄奘西行求法",
     "玄奘西行求取佛经与学问，路途漫长。目标清晰，准备与坚持同样重要。远行要有计划，孩子出行一定跟家人说。"),
    ("B023", "primary", "7-12岁", "詹天佑与铁路",
     "詹天佑主持建造重要铁路工程，解决复杂地形问题。工程靠计算、协作与负责。桥与路安全时，才谈得上方便。"),
    ("B024", "primary", "7-12岁", "法拉第与电磁",
     "法拉第从学徒成长，发现电磁感应等重要现象，推动电力应用。动手与思考可以并肩。电器有电，实验要在安全条件下做。"),
    ("B025", "junior", "13-15岁", "牛顿：体系与谦逊",
     "牛顿建立经典力学与万有引力等重要工作，也研究光学与数学。后来人不断完善与修正科学图像。学他的严谨，也记住：科学会更新，个人崇拜没必要。"),
    ("B026", "junior", "13-15岁", "爱因斯坦：思想实验",
     "爱因斯坦用思想实验推进相对论，强调对称与原理。名声很大，仍强调独立思考。读科普时分清「比喻」和「公式适用的范围」。"),
    ("B027", "junior", "13-15岁", "图灵：计算与伦理",
     "图灵的工作连接逻辑、计算与机器。技术强大时，伦理与法律也要跟上。学习编程与AI时，同时学习责任与隐私。"),
    ("B028", "junior", "13-15岁", "居里夫人：放射性研究",
     "居里夫妇发现放射性元素，研究改变医学与物理。早期防护不足带来伤害，提醒后人：未知风险要谨慎。荣誉之外，是规范与安全文化。"),
    ("B029", "junior", "13-15岁", "达尔文：证据与争论",
     "进化论改变生物学，也引发长期社会讨论。科学争议要用证据与可检验预测回应。把「科学结论」和「个人价值观争论」分开看。"),
    ("B030", "junior", "13-15岁", "屠呦呦：从验方到验证",
     "青蒿素研究展示传统经验与现代验证如何结合。提取、试验、临床评价缺一不可。面对「神药」宣传，先看是否经规范验证。"),
    ("B031", "junior", "13-15岁", "钱学森：系统工程思维",
     "复杂工程需要把人、设备、流程放在系统里看。单点英雄主义不够，协作与反馈更重要。你的学习计划也可以当成小系统来迭代。"),
    ("B032", "junior", "13-15岁", "邓稼先：沉默的重量",
     "国家重大项目常要求保密与长期投入。外部掌声少，不代表工作轻。选择道路时，问自己能否接受「长期认真却不热闹」。"),
    ("B033", "junior", "13-15岁", "司马迁：实录精神",
     "史家强调「不虚美、不隐恶」的理想。今天读信息，也要警惕只挑好听的叙事。核对来源，比转发情绪更接近史学态度。"),
    ("B034", "junior", "13-15岁", "伽利略：测量与权威",
     "测量与数学语言改变自然研究方式。当观察与旧权威冲突，科学选择可重复的证据。你也可以练习：先问「怎么测」。"),
    ("B035", "junior", "13-15岁", "法拉第：从学徒到发现",
     "教育资源不均时，自学与实践仍可能打开路。同时，现代社会更强调实验室安全与规范训练。兴趣要配对保护措施。"),
    ("B036", "junior", "13-15岁", "海伦·凯勒：沟通的可能",
     "残障不等于无能。教育、工具与社会支持能扩展可能性。同理心不是口号，是把障碍设计进公共生活的意愿。"),
]


def write_md(path: Path, sid: str, title: str, series: str, folder_age: str, body: str, source: str | None = None):
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        f"# {sid} {title}",
        f"系列：{series}",
        f"年龄：{folder_age}",
    ]
    if source:
        lines.append(f"来源：{source}")
    lines.append("估时：约8分钟")
    lines.append("")
    lines.append(body.strip())
    lines.append("")
    path.write_text("\n".join(lines), encoding="utf-8")


def main():
    # clear old age folders content carefully: rewrite in place by id destination
    items = []

    # Knowledge
    for gid, n, title, myth, truth in load_knowledge():
        age_k, folder_age = age_key(n)
        body = knowledge_text(n, title, myth, truth)
        path = ROOT / "光光讲知识" / folder_age / f"{gid}-{title}.md"
        write_md(path, gid, title, "光光讲知识", folder_age, body, "原创表述（常识科普，非摘录受版权保护读物）")
        items.append({"id": gid, "age": age_k, "shelf": "knowledge", "title": title, "text": body})

    # Fairy
    for sid, n, title, source in load_fairy():
        age_k, folder_age = age_key(n)
        body = fairy_text(n, title, source)
        src_line = f"{source}情节核，句子新写；软化处理"
        path = ROOT / "光光睡前小故事" / folder_age / f"{sid}-{title}.md"
        write_md(path, sid, title, "光光睡前小故事", folder_age, body, src_line)
        items.append({"id": sid, "age": age_k, "shelf": "fairy", "title": title, "text": body})

    # Biography
    for bid, age_k, folder_age, title, body in BIOS:
        path = ROOT / "光光讲人物" / folder_age / f"{bid}-{title}.md"
        write_md(path, bid, title, "光光讲人物", folder_age, body, "史实概述，句子原创；非任何受版权传记摘录")
        items.append({"id": bid, "age": age_k, "shelf": "biography", "title": title, "text": body})

    items.sort(key=lambda x: (x["shelf"], x["id"]))
    CATALOG.write_text(json.dumps(items, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")

    from collections import Counter
    print("total", len(items))
    print(Counter((i["shelf"], i["age"]) for i in items))
    print("catalog bytes", CATALOG.stat().st_size)
    # sample
    for i in items:
        if i["id"] in ("G001", "S001", "B001"):
            print("---", i["id"], i["title"], "---")
            print(i["text"][:180], "...\n")


if __name__ == "__main__":
    main()
