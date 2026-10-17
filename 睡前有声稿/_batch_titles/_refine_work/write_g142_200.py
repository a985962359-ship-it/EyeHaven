# -*- coding: utf-8 -*-
"""Unique refined stories G142-G200 (9-16)."""
from pathlib import Path

ROOT = Path("/Users/song/EyeHaven/睡前有声稿/光光讲知识/9-16岁")
TSV = Path("/Users/song/EyeHaven/睡前有声稿/_batch_titles/knowledge.tsv")
FULL = Path("/Users/song/EyeHaven/睡前有声稿/_batch_titles/knowledge_full.tsv")

NAMES = [
    "阿哲", "林夏", "周屿", "宋宁", "韩川", "叶可", "方舟", "程未", "江澄", "陆行",
    "沈夜", "顾言", "唐予", "许安", "贺明", "罗野", "金桥", "魏然", "蔡知", "邓野",
    "彭城", "萧然", "冯渡", "丁一", "康宁", "尹夏", "毛豆", "贾森", "尤里", "白昼",
    "阿南", "阿北", "阿东", "阿西", "小满", "大成", "未央", "知秋", "立夏", "惊蛰",
    "谷雨", "白露", "霜降", "小雪", "大寒", "立春", "雨水", "春分", "清明", "芒种",
    "夏至", "小暑", "大暑", "立秋", "处暑", "秋分", "寒露", "冬至", "小寒",
]
PLACES = [
    "晚自习走廊", "体育馆更衣室", "图书馆三楼窗边", "校医室门口", "公交末班车",
    "家附近天桥", "实验室准备间", "宿舍熄灯后", "班主任办公室外", "球场边长椅",
    "厨房冰箱前", "阳台晾衣绳旁", "医院检验科走廊", "社区讲座现场", "网课摄像头前",
    "海边防波堤", "山顶信号塔下", "博物馆互动屏前", "电脑桌线槽旁", "便利店冷柜边",
    "游泳馆看台", "琴房隔音门外", "超市营养标签架", "药店柜台外", "公园塑胶跑道",
    "化学实验室水槽", "地理教室地球仪旁", "生物教室模型柜", "信息课机房", "心理咨询室外候座",
]


def wrap(gid, title, body):
    return (
        f"# {gid} {title}\n"
        f"系列：光光讲知识\n"
        f"年龄：9-16岁\n"
        f"来源：原创\n"
        f"估时：约10分钟\n\n"
        f"{body.strip()}\n"
    )


def build(gid, title, myth, truth, i):
    kid = NAMES[i % len(NAMES)]
    peer = NAMES[(i + 13) % len(NAMES)]
    if peer == kid:
        peer = NAMES[(i + 5) % len(NAMES)]
    place = PLACES[i % len(PLACES)]
    myth_short = myth.replace("有人说", "").strip("。")
    arc = i % 8

    if arc == 0:
        opener = (
            f"测验附加题写着：{title}。{peer}用吓人道具讲了一通，全班笑。"
            f"{kid}笑完却发愣——笑话不能当交卷答案。"
        )
        middle = (
            f"下课他们蹲在{place}核对。{kid}问：什么情况下出现？什么能改变？"
            f"什么必须找大人或医生？{peer}把段子收起来，一起写下能检验的句子。"
        )
        closer = f"走廊灯一排排灭。{kid}把真句默念一遍，像存档。存完，人关机。"
    elif arc == 1:
        opener = (
            f"{peer}转发短视频，标题是恐惑版「{title}」。"
            f"{kid}拇指悬在转发键上，光光在屏外轻轻一闪。"
        )
        middle = (
            f"他们暂停视频，去对课本与靠谱科普：样本多大？相关是否被说成因果？"
            f"恐惑散了，细节留下。{place}的风把两人头发吹乱，脑子却更清楚。"
        )
        closer = f"{kid}把视频标成「待查」而不是「已信」。枕头比转发键近。"
    elif arc == 2:
        opener = (
            f"家庭群争论{title}。有人甩出：「{myth}。」"
            f"大人点名：{kid}，你读书的你说！"
        )
        middle = (
            f"{kid}不装全懂：「我能确定的是——{truth}。」"
            f"争到激动，他提议证据留到明天，今晚先别互扣帽子。群里安静了几秒。"
        )
        closer = f"手机扣过去。{kid}觉得「我不知道的部分」也可以诚实说出来，然后睡。"
    elif arc == 3:
        opener = (
            f"实验课剩十分钟，{kid}想靠近{title}。器材不够，只好思想实验加查资料。"
        )
        middle = (
            f"在{place}，他们列：若「{myth_short}」成立会看到什么；若不成立会看到什么。"
            f"假说对不上。真句对得上：{truth}。"
        )
        closer = f"记录本合上。「对得上」三个字比满分解渴。去睡觉，让脑子巩固。"
    elif arc == 4:
        opener = (
            f"失眠夜里，{kid}越想{title}越醒，越醒越搜，越搜越怕。"
        )
        middle = (
            f"光光建议停搜：喝水、拉伸、把问题写成明天待办。"
            f"恐惧喜欢加班；身体喜欢班次。待办本写着：查清「{truth}」的来源。"
        )
        closer = f"问题还在，但不再按门铃。人先躺下。"
    elif arc == 5:
        opener = (
            f"社团辩论抽到{title}。正方要吓，反方要否认一切。{kid}当质询。"
        )
        middle = (
            f"他逼双方给定义、边界、反例。吓与否认都站不住。"
            f"中间那句可检验的话胜出：{truth}。场地就在{place}，灯很白，心却稳。"
        )
        closer = f"胜负其次。{kid}抄下胜出句，打开勿扰。"
    elif arc == 6:
        opener = (
            f"{place}有人把「{myth}」讲得像常识。{kid}想纠正，又怕尴尬。"
        )
        middle = (
            f"他问：「这个有来源吗？」对话从断言拉回证据。"
            f"有人查了，改口；有人仍嘴硬。{kid}至少把真句放进空气里：{truth}。"
        )
        closer = f"礼貌地要证据，也是力气。力气用完，去睡。"
    else:
        opener = (
            f"{kid}和{peer}在{place}抬杠：关于{title}。风有点硬，话更硬。"
        )
        middle = (
            f"第三回合他们改成合作：一人找支持「{myth_short}」的，一人找反对的。"
            f"假说溃得很快。留下的是：{truth}。"
        )
        closer = f"到家门口，抬杠变击掌。真的不必靠吼。门关上，夜安静。"

    body = f"""{opener}

有人坚持：「{myth}。」这话传得快，因为它简单、带情绪。{kid}把它放在一边，先找能指给人看的部分。

{middle}

他最后收下的句子是：「{truth}。」不是为了赢吵架，是为了少被吓、少被骗。光光只留一句口诀：标题党白天拆，夜里留真的。

{closer}
"""
    return wrap(gid, title, body)


def main():
    full = {}
    for line in FULL.read_text(encoding="utf-8").splitlines():
        p = line.split("\t")
        if len(p) >= 4:
            full[p[0]] = (p[2], p[3])
    items = []
    for line in TSV.read_text(encoding="utf-8").splitlines():
        p = line.split("\t")
        if len(p) >= 3 and p[0].startswith("G"):
            n = int(p[0][1:])
            if 142 <= n <= 200:
                myth, truth = full.get(p[2], ("有人说错了", "要找证据"))
                items.append((p[0], p[2], myth, truth))

    ROOT.mkdir(parents=True, exist_ok=True)
    for i, (gid, title, myth, truth) in enumerate(items):
        # keep polished antibiotic if somehow in range - G141 not in range
        text = build(gid, title, myth, truth, i)
        path = ROOT / f"{gid}-{title}.md"
        path.write_text(text, encoding="utf-8")
        print("wrote", path.name, len(text))
    print("total", len(items))


if __name__ == "__main__":
    main()
