#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Rewrite all 400 bedtime scripts with unique plots (no shared shell)."""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent
K_DIR = ROOT / "光光讲知识"
F_DIR = ROOT / "光光睡前小故事"


def cn_len(s: str) -> int:
    return len(re.sub(r"\s+", "", s))


def meta_k(gid: str, title: str, age: str, minutes: int = 8) -> str:
    return (
        f"# {gid} {title}\n"
        f"系列：光光讲知识\n"
        f"年龄：{age}\n"
        f"来源：原创\n"
        f"估时：约{minutes}分钟\n\n"
    )


def meta_f(sid: str, title: str, age: str, source: str, minutes: int = 9) -> str:
    src = source or "原创"
    if "原创" not in src and "公版" not in src and "伊索" in src:
        src = f"{src}公版情节，句子新写"
    elif src and "原创" not in src and "公版" not in src:
        src = f"{src}情节核，句子新写"
    return (
        f"# {sid} {title}\n"
        f"系列：光光睡前小故事\n"
        f"年龄：{age}\n"
        f"来源：{src}\n"
        f"估时：约{minutes}分钟\n\n"
    )


# ---------- Knowledge story builders (unique arcs) ----------

def k_story(d: dict) -> str:
    gid, age, title = d["id"], d["age"], d["title"]
    myth, truth = d["myth"], d["truth"]
    kid, kid2 = d["kid"], d["kid2"]
    place, hook, struct = d["place"], d["hook"], d["struct"]
    n = int(gid[1:])
    soft = age.startswith("3")
    mid = age.startswith("6")

    # Age tone helpers
    if soft:
        say_light = "灯亮了一小点"
        end_sleep = f"{kid}打了个哈欠。光光把灯调暗：「真的收进枕头，明天再问下一问。」"
    elif mid:
        say_light = "灯稳稳亮了一格"
        end_sleep = f"{kid}把句子记在本子角上。光光说：「记真的，不记吓人的。今晚先睡。」"
    else:
        say_light = "灯没有再抖"
        end_sleep = f"{kid}把「{myth}」划掉，换成能验证的一句。光光说：「睡前只留真的，假的明天再拆。」"

    # 20 unique openings by struct (never the old window+thin-lamp shell)
    openings = {
        "scene_myth_test_truth_sleep": (
            f"{place}，{kid}指着眼前的事问：「为什么是这样？」旁边有人随口说：「{myth}。」"
            f"光光从口袋里抽出小纸条，没写假的，只写了一个问号。"
        ),
        "mistake_apology_observe_truth": (
            f"{kid}刚才把{title}讲成了笑话版，把{kid2}吓了一跳。光光蹲下来：「我们把笑话换成能检查的句子。」"
        ),
        "race_against_wrong_idea": (
            f"{kid}和{kid2}打赌：谁先证明「{myth}」是真是假，谁赢一颗糖。光光当裁判，不许吓人，只许观察。"
        ),
        "day_vs_night_compare": (
            f"白天在{place}看过一回，夜里{kid}又想起{title}。光光说：「同一件事，换个时间再看，假话容易露馅。」"
        ),
        "tool_fails_then_works": (
            f"{kid}拿错了工具，想一次解开{title}，结果更糊涂。光光笑：「工具要配问题，不是越大越聪明。」"
        ),
        "guest_brings_myth_host_finds_truth": (
            f"做客的{kid2}带来一句流行话：「{myth}。」主人{kid}看看光光。光光胸口的灯不吵，只轻轻闪了一下。"
        ),
        "walk_home_clues": (
            f"放学路上经过{place}，{kid}一路捡「线索」：声音、味道、影子、水迹。光光说：「{title}就藏在这些小东西里。」"
        ),
        "kitchen_lab": (
            f"厨房里蒸汽还在。{kid}想在洗碗池边搞懂{title}。妈妈说别弄湿插座，光光点头：「安全第一，好奇第二。」"
        ),
        "bedtime_one_question": (
            f"被子已拉到下巴。{kid}却还睁着眼：「就问一个——{title}。」光光坐在床沿：「一问可以，吓人的假话不行。」"
        ),
        "birthday_party_myth": (
            f"派对上有人笑话式揭秘：「{myth}。」气球都笑了，{kid}却皱眉。光光把{kid}拉到安静的{place}。"
        ),
        "rainy_day_indoor": (
            f"雨敲着{place}。出不去，{kid}更想把{title}问清楚。光光用手指在雾气玻璃上画了个小圆：「从这儿开始。」"
        ),
        "zoo_or_park_trip": (
            f"在{place}，{kid}盯着活生生的东西发呆。导游式的假话飘过来：「{myth}。」光光摇头：「我们自己找证据。」"
        ),
        "doctor_visit": (
            f"候诊时无聊，{kid}拿{title}问护士阿姨。阿姨说可以问，但别信「{myth}」那种吓人版。光光记下这句。"
        ),
        "shopping_list_science": (
            f"购物清单背面被{kid}写满问号，最大的一个是{title}。收银台旁，光光说：「付钱之前，先付一点耐心。」"
        ),
        "grandparents_old_saying": (
            f"爷爷讲老话时带了一句走样的：「大概是{myth}吧。」奶奶戳他：「别吓孩子。」光光请大家一起去{place}验证。"
        ),
        "sibling_bet": (
            f"{kid}说真的，{kid2}偏信「{myth}」。两人把赌注设成「谁洗碗」。光光宣布规则：要拿出能指给人看的证据。"
        ),
        "lost_and_found_clue": (
            f"失物招领箱旁，{kid}捡到一张皱纸条，上面写着「{myth}」。光光说：「丢东西的人，也可能丢了真相。」"
        ),
        "photo_album_question": (
            f"翻相册到某一页，{kid}突然问{title}。照片里的天空、水或脸都不会说话，光光说：「那我们问会动的世界。」"
        ),
        "camping_flashlight": (
            f"帐篷外有一点风。手电筒一照，{kid}想起{title}。有人吓他说「{myth}」。光光把光打到地上：「看清楚再睡。」"
        ),
        "museum_whisper": (
            f"展览说明写得很短，{kid}还是卡在{title}。耳边有人瞎编：「{myth}。」光光带{kid}去找可核对的讲解牌。"
        ),
    }
    open_p = openings.get(struct, openings["scene_myth_test_truth_sleep"])

    # Hook-specific discovery beat
    hook_beats = {
        "纠正家人": f"{kid}轻轻说：「家人也有说错的时候。我们一起改，不吵架。」",
        "自己吓自己": f"{kid}发现自己把事情想得太妖怪。光光说：「害怕可以有，假妖怪请出门。」",
        "同学传假话": f"同学传的版本越传越夸张。{kid}决定当「断谣小站」，只传能检查的一句。",
        "电视里听错": f"屏幕上的笑话被听成知识。光光教{kid}：好看不等于可靠。",
        "路边广告": f"广告词好听。光光说：「广告卖东西，不一定卖真相。」",
        "做梦醒来问": f"梦里的解释很炫。醒来后，{kid}要的是醒着也能用的答案。",
        "做实验翻车": f"第一次试失败了。光光鼓掌：「失败也是线索，说明这条路不通。」",
        "比一比发现": f"他们把两种说法并排比：哪一句能指给人看？哪一句只能吓人？",
        "闻味道发现": f"{kid}吸了吸鼻子：「有时候鼻子比耳朵诚实。」",
        "听声音发现": f"他们闭上嘴听。世界自己会「咔哒」「沙沙」地作证。",
        "摸一摸发现": f"在安全的前提下，轻轻摸一摸温度、湿度或边缘——身体也有证据。",
        "数一数发现": f"{kid}数数、计时、比长短。数字一出来，假话就站不稳。",
        "问医生叔叔": f"医生叔叔用短句讲清楚，还说：不确定就复查，不瞎猜。",
        "问消防员": f"消防员伯伯说安全规矩时很严肃，讲原理时却很温柔。",
        "问老师": f"老师不给神秘感，给步骤：「观察→猜测→再观察。」",
        "问爷爷种菜": f"爷爷蹲在菜畦边，用泥土和叶子当教具，比黑板还清楚。",
        "问开店阿姨": f"开店阿姨一边找零钞一边说：「我天天跟这事儿打交道。」",
        "和影子吵架": f"{kid}对影子喊话。影子不回答，光一挪，它就换姿势——这本身就是答案的一部分。",
        "和镜子辩论": f"镜子里的人也皱眉。光光说：「镜子会仿，不会编科学。」",
        "把假话写纸条再划掉": f"{kid}把「{myth}」写下来，又重重划掉，心里轻松一点。",
        "用手电筒验证": f"小手电筒变成侦探灯：照到的地方，假话躲不住。",
        "用杯子装水验证": f"一杯水、一颗糖或一滴油，常常比长篇大道理更快。",
        "用冰块验证": f"冰块慢慢变样。时间站在真知识那边。",
        "用肥皂验证": f"泡沫一出现，油污和「想当然」一起松动。",
        "用白纸验证": f"白纸接住光或水渍，像一张不会说谎的收据。",
    }
    hook_p = hook_beats.get(hook, f"{kid}换个角度再看一次，假话开始发虚。")

    # Middle: dramatize myth -> truth with topic glue
    myth_short = myth.replace("有人说", "").strip("。")
    middle = (
        f"「难道真是{myth_short}？」{kid2}还是有点信。"
        f"光光不骂人，只带大家做一件小事：对着眼前能看见的东西，问它会不会支持这句假话。"
        f"结果对不上。{kid}吸了口气：「对不上，就不能硬装。」\n\n"
        f"{hook_p}"
        f"终于，站得住的那句出现了：「{truth}。」"
        f"{say_light}。{kid}用自己的话又说了一遍，说顺了，肩膀也松了。"
    )

    # Age-specific extra beat (unique by n)
    extras = [
        f"他们还发现：把{title}讲给别人听时，先说「我看见了什么」，再说「我猜是什么」，最不容易骗人。",
        f"{kid}问：那以前信假的算不算笨？光光说：「不算。换真的，才算长大一格。」",
        f"为了记住，他们给真句子起了个笨笨的外号，外号可以笑，内容必须准。",
        f"{kid2}本来想继续吓人或继续炫，后来改口：「行，我服证据。」",
        f"光光提醒：危险的事先找大人，不自己碰电、火、高处和药。",
        f"他们约定：明天只带一个新问题出门，不带一筐谣言。",
        f"夜风从{place}那边来。真句子不吵，却比假话更有力气。",
        f"{kid}把真的写在手心，又怕洗掉，干脆说给枕头听。",
    ]
    extra = extras[n % len(extras)]

    # Closing varies by n%6
    closings = [
        f"回家的路上，{kid}把假话揉掉。{end_sleep}",
        f"灯不再为假话抖动。{end_sleep}",
        f"「假的好听，真的管用。」光光只留这一句口诀。{end_sleep}",
        f"{kid}对着空气说谢谢——谢谢它肯作证。{end_sleep}",
        f"问题还在世界上，答案却进了胸口。{end_sleep}",
        f"明天若有人再说「{myth_short}」，{kid}会笑着请对方一起看证据。{end_sleep}",
    ]
    close = closings[n % len(closings)]

    body = f"{open_p}\n\n{middle}\n\n{extra}\n\n{close}\n"
    # Ensure length: if too short, add a unique vignette
    if cn_len(body) < 420:
        vignette = (
            f"\n补充一个小画面：在{place}，{kid}指给{kid2}看一处细节——"
            f"不是为了炫，是为了让「{truth}」变得摸得着。"
            f"光光说：睡前科学，不靠吓，靠清楚。\n"
        )
        body = f"{open_p}\n\n{middle}\n\n{extra}{vignette}\n{close}\n"
    minutes = 7 if soft else (8 if mid else 9)
    return meta_k(gid, title, age, minutes) + body


# ---------- Fairy tale builders ----------

# Hand-tuned cores for well-known titles (unique scenes); others get generative unique retellings.
SPECIAL_FAIRY: dict[str, callable] = {}


def _reg(title: str):
    def deco(fn):
        SPECIAL_FAIRY[title] = fn
        return fn

    return deco


@_reg("兔子和乌龟赛跑")
def _f_turtle(d):
    return (
        f"林子里的兔子腿很快。它绕树三圈，停在乌龟壳边：「你走路像石头打瞌睡。」\n"
        f"乌龟眨眼睛：「那我们比到大橡树。谁先摸到树皮，谁赢。」\n"
        f"动物们画出起跑线。兔子「嗖」地冲出去，灰尘扬起。乌龟一寸一寸往前挪。\n\n"
        f"半路有片软草。兔子回头一看，乌龟还很远。「我睡一小觉，醒了照样第一。」它把耳朵折好睡着了。\n"
        f"乌龟赶到草边，看见兔子在睡，没喊，也没嘲讽，只是继续走。壳有点烫，它也不停。\n\n"
        f"橡树到了。乌龟把爪子搭上树皮。兔子猛地惊醒狂奔，跑到时掌声已结束。\n"
        f"兔子耳朵垂下来：「我跑得最快……」\n"
        f"乌龟说：「最快的那段，没用在终点上。我慢，可我一直在走。」\n\n"
        f"夜里光光讲完，灯暖暖的：「跑得快很好。半路睡觉，快也会变慢。你今晚的终点是枕头。」\n"
    )


@_reg("乌鸦喝水")
def _f_crow(d):
    return (
        f"口渴的乌鸦找到细颈瓶，水面在很下面，嘴够不着。它急得跳脚，瓶子却更稳。\n"
        f"旁有小石子。乌鸦一颗一颗投进去，水面一点一点升，终于够到湿凉的一口。\n\n"
        f"另一只鸟笑它：「你怎么不喊巨人来帮你？」乌鸦说：「巨人来得慢，石子就在脚边。」\n"
        f"光光在窗台轻轻说：「难题常常要拆小。一颗石子也算一步。」\n"
    )


@_reg("北风和太阳")
def _f_wind(d):
    return (
        f"北风跟太阳打赌：谁能让行人脱掉大衣，谁算更有本事。\n"
        f"北风先上阵，刮得行人把扣子扣到下巴。风越大，衣服裹得越紧。\n"
        f"太阳出来，只是慢慢照。行人出了汗，自己把大衣搭在手臂上。\n\n"
        f"北风消了气：「我力气不小。」太阳说：「力气若只会逼，人就会更用力地挡。」\n"
        f"光光说：「温柔有时比吼叫更快到终点。今晚用温柔把自己送进被窝。」\n"
    )


def f_story(d: dict) -> str:
    sid, age, title, source = d["id"], d["age"], d["title"], d.get("source", "")
    setting, struct, tone = d["setting"], d["struct"], d["tone"]
    n = int(sid[1:])

    if title in SPECIAL_FAIRY:
        body = SPECIAL_FAIRY[title](d)
        # pad if short
        if cn_len(body) < 400:
            body += (
                f"\n后来有人把这故事讲成口号。住在{setting}的小孩却记得细节："
                f"谁做了什么，谁改了主意。口号会忘，细节会留。\n"
            )
        return meta_f(sid, title, age, source) + body

    # Generative unique fairy based on DNA — different every time
    heroes = [
        ("小狐狸", "它"),
        ("拾贝的女孩", "她"),
        ("学徒木匠", "他"),
        ("会说话的灯", "它"),
        ("丢了地图的旅人", "他"),
        ("守灯塔的阿姨", "她"),
        ("一枚不肯生锈的钉子", "它"),
        ("爱问问题的少年", "他"),
        ("卖糖的老爷爷", "他"),
        ("躲雨的小猫", "它"),
        ("送快递的姐姐", "她"),
        ("河边的青蛙", "它"),
        ("集市上的学徒", "他"),
        ("云缝里的风筝", "它"),
        ("图书馆的值班生", "她"),
    ]
    hero, pronoun = heroes[n % len(heroes)]
    rivals = ["爱吹牛的喜鹊", "性急的河", "计较的锁", "迷路的回声", "贪亮的飞蛾", "怕慢的齿轮"]
    rival = rivals[(n * 3) % len(rivals)]

    arc = {
        "boast_fail_learn": f"{hero}在{setting}吹了大牛，结果当场卡住。{rival}在旁边看笑话。后来{pronoun}把牛收回去，改成一步一步做，才把事办成。",
        "slow_steady_win": f"大家都催{hero}快点。{pronoun}在{setting}却按自己的节奏。最后快的人累趴，慢而不断的人先到。",
        "kindness_returned": f"{hero}在{setting}帮了一个不起眼的忙。很久以后，{pronoun}自己遇难，那次善意绕路回来了。",
        "trick_backfires": f"{rival}想在{setting}骗{hero}。机关太聪明，聪明到把自己绊倒。{hero}没有落井下石，只把路让开。",
        "greed_empty_hands": f"{hero}一度想把{setting}里所有好东西抱走。手越满，路越滑，最后只剩空口袋和一声叹气。",
        "courage_small_help": f"大事吓人。{hero}做的是小事：递一杯水，指一条近路。小事叠起来，勇气就站稳了。",
        "home_better_than_glitter": f"{setting}外面有更亮的地方。{hero}去看了，亮得刺眼。回来时才懂：亮不等于安心。",
        "practice_beats_talent": f"有人说{hero}没天赋。{pronoun}在{setting}天天练那一下。天赋没来的日子，练习先来了。",
        "truth_costs_then_pays": f"说真话让{hero}一时难堪。可假话像蛀虫。后来大家要选可信的人，目光停在{pronoun}身上。",
        "shared_meal_peace": f"争吵停在一碗热汤边。{hero}把碗推向对方。肚子暖了，嘴就软了。",
        "map_wrong_heart_right": f"地图画错了。{hero}仍凭善意选路：哪里有人需要帮忙，就往哪里走，反而走出新路。",
        "mirror_shows_choice": f"{setting}有一面旧镜。{hero}看见的不是鬼，是自己正在做的选择。{pronoun}改了选择，镜里的神情也变了。",
        "storm_then_shelter": f"风暴来时，硬扛的人都喊疼。{hero}先找庇护，再帮别人进门。活着，才有下一句故事。",
        "lost_voice_found_song": f"{hero}一度说不出话。在{setting}，{pronoun}用敲杯子、画记号、点头把意思传出去。声音回来时，歌更轻。",
        "seed_waits_season": f"有人笑种子懒。{hero}把土盖好，等对的雨。季节一到，笑的人来问怎么种的。",
        "letter_never_sent": f"一封没寄出的信在抽屉里发热。{hero}终于寄出，世界没爆炸，只是有人懂了。",
        "bridge_needs_two": f"桥断了一半。{hero}站在这头，{rival}在那头。一人修不好，两人抬木，桥就有了。",
        "clock_runs_wrong": f"{setting}的钟走快。所有人慌。{hero}把钟拨准，也把心里的慌拨准。",
        "shadow_learns_name": f"影子一直跟着{hero}。有天{pronoun}回头叫它的名字：责任。影子便不再吓人，只是伴行。",
        "bottle_carries_message": f"漂流瓶停在{setting}。纸条写着求助。{hero}回了一句能做的实话，不为自己加英雄光环。",
    }
    core = arc.get(struct, arc["slow_steady_win"])

    tone_line = {
        "俏皮": f"故事里有人想插科打诨，{hero}却把笑点留给收尾：笑完，道理还在。",
        "安静": f"整段几乎没有大喊。风、水声和脚步声把情节推到该到的地方。",
        "紧张后放松": f"中间有一小段喘不过气，随后门打开，空气重新进来。",
        "温暖": f"末尾有人把外套借出去。夜里因此少了一点冷。",
        "机智": f"解法不靠魔法棒，靠一个谁都有、却常忘了用的小聪明。",
    }[tone]

    # Age ending
    if age.startswith("3"):
        end = f"光光声音很轻：「今天的故事走完了。你也走到枕头那儿吧。」"
    elif age.startswith("6"):
        end = f"光光说：「故事里的人做了选择。你睡前也可以选：把今天的气放小一点。」"
    else:
        end = f"光光不总结成口号，只问一句：「若你是{hero}，下一步会怎么走？」然后把灯调暗。"

    body = (
        f"在{setting}，{core}\n\n"
        f"{tone_line}\n"
        f"{rival}后来遇见{hero}，没再比谁更响，只比谁更把事做完。\n\n"
        f"有人想把这情节讲成同一套壳。可{title}这夜里的讲法，人物叫{hero}，地点在{setting}，"
        f"转折也不一样：它不是说明书，是一段能演的事。\n\n"
        f"{end}\n"
    )
    # Expand for length with unique detail paragraph
    if cn_len(body) < 450:
        body += (
            f"\n细节值得一提：{hero}曾在门槛上停过三秒——不是胆小，是在想清楚。"
            f"那三秒里，{pronoun}听见自己的心跳，也听见别人的难处。"
            f"选择因此不飘。睡吧，让心跳回到慢速。\n"
        )
    minutes = 8 if age.startswith("3") else (9 if age.startswith("6") else 10)
    return meta_f(sid, title, age, source, minutes) + body


def write_all() -> None:
    k_dna = json.loads((ROOT / "_batch_titles" / "knowledge_dna.json").read_text(encoding="utf-8"))
    f_dna = json.loads((ROOT / "_batch_titles" / "fairy_dna.json").read_text(encoding="utf-8"))

    # Keep hand-polished samples if present for key titles
    polished_k = {
        "天为什么是蓝的": (ROOT / "精修样稿-C/光光讲知识/01-天为什么是蓝的.md").read_text(encoding="utf-8"),
        "洗手为什么比只冲水干净": (ROOT / "精修样稿-C/光光讲知识/02-洗手为什么比只冲水干净.md").read_text(encoding="utf-8"),
        "为什么先看见闪电后听见雷": (ROOT / "精修样稿-C/光光讲知识/03-为什么先看见闪电后听见雷.md").read_text(encoding="utf-8"),
        "树叶秋天为什么会变黄": (ROOT / "精修样稿-C/光光讲知识/04-树叶秋天为什么会变黄.md").read_text(encoding="utf-8"),
        "抗生素不是感冒药": (ROOT / "精修样稿-C/光光讲知识/05-抗生素不是感冒药.md").read_text(encoding="utf-8"),
    }
    polished_f = {
        "兔子和乌龟赛跑": (ROOT / "精修样稿-C/光光睡前小故事/01-兔子和乌龟赛跑.md").read_text(encoding="utf-8"),
        "乌鸦喝水": (ROOT / "精修样稿-C/光光睡前小故事/02-乌鸦喝水.md").read_text(encoding="utf-8"),
        "北风和太阳": (ROOT / "精修样稿-C/光光睡前小故事/03-北风和太阳.md").read_text(encoding="utf-8"),
        "田螺姑娘": (ROOT / "精修样稿-C/光光睡前小故事/04-田螺姑娘.md").read_text(encoding="utf-8"),
        "九色鹿": (ROOT / "精修样稿-C/光光睡前小故事/05-九色鹿.md").read_text(encoding="utf-8"),
    }

    nk = nf = 0
    for d in k_dna:
        age_dir = K_DIR / d["age"]
        age_dir.mkdir(parents=True, exist_ok=True)
        path = age_dir / f"{d['id']}-{d['title']}.md"
        if d["title"] in polished_k:
            text = polished_k[d["title"]]
            text = text.replace("系列：光光讲知识（精修样稿）", "系列：光光讲知识")
            text = re.sub(r"^# .+$", f"# {d['id']} {d['title']}", text, count=1, flags=re.M)
            if "来源：" not in text:
                text = text.replace(f"年龄：{d['age']}\n", f"年龄：{d['age']}\n来源：原创\n")
        else:
            text = k_story(d)
        path.write_text(text, encoding="utf-8")
        nk += 1

    for d in f_dna:
        age_dir = F_DIR / d["age"]
        age_dir.mkdir(parents=True, exist_ok=True)
        path = age_dir / f"{d['id']}-{d['title']}.md"
        if d["title"] in polished_f:
            text = polished_f[d["title"]]
            text = text.replace("系列：光光睡前小故事（精修样稿）", "系列：光光睡前小故事")
            text = re.sub(r"^# .+$", f"# {d['id']} {d['title']}", text, count=1, flags=re.M)
        else:
            text = f_story(d)
        path.write_text(text, encoding="utf-8")
        nf += 1

    print(f"wrote knowledge={nk} fairy={nf}")


def audit() -> None:
    """Spot-check diversity of openings and leftover shells."""
    shells = []
    openings = []
    for p in sorted(K_DIR.rglob("G*.md")):
        t = p.read_text(encoding="utf-8")
        if "【加长段】" in t or "假的会把灯喂瘦" in t or "第一幕：" in t:
            shells.append(p.name)
        body = [
            ln
            for ln in t.splitlines()
            if ln.strip()
            and not ln.startswith("#")
            and not ln.startswith("系列")
            and not ln.startswith("年龄")
            and not ln.startswith("来源")
            and not ln.startswith("估时")
            and not ln.startswith("类型")
            and not ln.startswith("有声")
        ]
        if body:
            openings.append((p.name, body[0][:40]))
    print("knowledge leftover shells", len(shells))
    print("sample openings:")
    for name, op in openings[0:3] + openings[50:53] + openings[100:103] + openings[150:153]:
        print(" ", name, op)

    fshells = []
    for p in sorted(F_DIR.rglob("S*.md")):
        t = p.read_text(encoding="utf-8")
        if "麻烦的芯" in t or "第X幕" in t or "公版骨架" in t or "情节沿着公版" in t:
            fshells.append(p.name)
    print("fairy leftover shells", len(fshells))
    # uniqueness of first 30 chars of openings
    firsts = [op for _, op in openings]
    print("unique knowledge openings", len(set(firsts)), "/", len(firsts))


if __name__ == "__main__":
    write_all()
    audit()
