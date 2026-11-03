#!/usr/bin/env python3
# 第九把尺：种子数据体检（tools/audit_seed.py）。
#
# 前八把尺管"画得对不对"，这把管"喂给 AI 的数据本身对不对"——种子是产品定位
# 「AI 是分析引擎，不是数据源」的根基，而 DataSeeder 对坏数据是静默降级的：
# 坐标缺失回退区中心、片区不落点、枚举外标签直接丢行内值。静默不等于没有，
# 这把尺把降级显性化，并对真正不可接受的问题硬失败。
#
# 用法：python3 tools/audit_seed.py
# 退出码：0 = 硬查全过（警告不算失败）；1 = 有硬失败。
#
# 硬查（任何一条命中即退出码 1）：
#   1. JSON 坏行、缺 id/name（seeder 会静默跳过该行 → 库里少数据没人知道）
#   2. id 重复（同城或跨城；upsert 按 id REPLACE，重复 id = 后行吃掉前行）
#   3. 枚举白名单外的值（spot.t / area.tier / area.g；seeder 静默丢值或回默认档）
#   4. la/lo 在城界外——seeder 的 geoOf 只挡中国界（18-54/73-135），
#      编错城的点（如北京的坐标落到上海）会原样进库上屏
#   5. 同城不同 id 坐标相距 <50m——geocode 撞点嫌疑，两张卡一个是错的位置
#   6. 无坐标的景点且所在区不在 DistrictCoords 表——会落到深圳兜底点（2000km 外）
# 警告（不失败，报告里摆数字）：
#   - 无 la/lo 的行（景点回退区中心 / 片区不落点，provenance 已标低可信度）
#   - 同城同名、字段完整度、阶段5 验收线（每城 30-50 景点 / 35-50 区域）

import json
import math
import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SEED_DIR = os.path.join(REPO, 'entry/src/main/resources/rawfile/seed')

CITIES = ['beijing', 'shanghai', 'guangzhou', 'shenzhen']
CITY_CN = {'beijing': '北京', 'shanghai': '上海', 'guangzhou': '广州', 'shenzhen': '深圳'}

# GCJ02 城界（宽松框，含全部市辖县区；只抓"编错城"级别的错误）
CITY_BBOX = {
    '北京': (39.2, 41.3, 115.2, 117.6),
    '上海': (30.4, 32.1, 120.6, 122.3),
    '广州': (22.2, 24.1, 112.8, 114.6),
    '深圳': (22.3, 23.0, 113.6, 114.9),
}

SPOT_TAGS = ['must_see', 'classic', 'niche', 'family']
AREA_TIERS = ['economy', 'comfort', 'luxury']
AREA_GROUPS = ['core', 'commercial', 'metro']

# 与 DataSeeder.DistrictCoords 的键值保持一致：区中心坐标（GCJ02，度）。
# 第七查用：景点坐标离所属区中心 >30km 即报——它抓的是「bbox 内但错区」的 geocode
# 事故（撞点/出城检查的空档：广州 gz-025 曾因参数双交换落进 bbox 内的错值，bbox 抓不到它）
KNOWN_DISTRICTS = {
    '北京': {'东城区': (39.928, 116.414), '西城区': (39.912, 116.366), '朝阳区': (39.921, 116.443),
           '海淀区': (39.959, 116.298), '丰台区': (39.858, 116.287), '石景山区': (39.906, 116.223),
           '通州区': (39.902, 116.657), '昌平区': (40.221, 116.231), '怀柔区': (40.316, 116.637),
           '延庆区': (40.457, 115.975), '门头沟区': (39.941, 116.102), '房山区': (39.742, 116.143),
           '顺义区': (40.129, 116.654), '大兴区': (39.726, 116.341),
           '密云区': (40.376, 116.843)},
    '上海': {'黄浦区': (31.232, 121.484), '徐汇区': (31.188, 121.437), '长宁区': (31.220, 121.425),
           '静安区': (31.229, 121.458), '普陀区': (31.250, 121.396), '虹口区': (31.265, 121.487),
           '杨浦区': (31.260, 121.526), '浦东新区': (31.221, 121.544), '闵行区': (31.112, 121.381),
           '宝山区': (31.405, 121.489), '嘉定区': (31.375, 121.266), '松江区': (31.032, 121.227),
           '青浦区': (31.151, 121.112), '奉贤区': (30.918, 121.474), '崇明区': (31.624, 121.397)},
    '广州': {'越秀区': (23.129, 113.267), '荔湾区': (23.126, 113.243), '海珠区': (23.102, 113.317),
           '天河区': (23.124, 113.363), '白云区': (23.269, 113.267), '黄埔区': (23.181, 113.487),
           '番禺区': (22.938, 113.384), '花都区': (23.404, 113.220), '南沙区': (22.802, 113.525),
           '增城区': (23.292, 113.811), '从化区': (23.548, 113.586)},
    '深圳': {'罗湖区': (22.548, 114.127), '福田区': (22.541, 114.055), '南山区': (22.531, 113.930),
           '宝安区': (22.560, 113.883), '龙岗区': (22.720, 114.247), '龙华区': (22.610, 114.030),
           '盐田区': (22.556, 114.235), '光明区': (22.762, 113.935), '坪山区': (22.691, 114.346),
           '大鹏新区': (22.590, 114.480)},
}

fails = []
warns = []

# 「离区过远」白名单（带理由，同值不同义原则）：这些是行政大区/地理事实，不是 geocode 错误
WHITELIST_FAR = {
    'sh-026': '崇明东滩在岛东端，区中心（城桥镇）在岛西端——横穿全岛约 50km 属地理事实',
    'sh-027': '上海海昌海洋公园在浦东临港滴水湖板块，离区中心远属地理事实',
    'sh-032': '上海天文馆在浦东临港滴水湖板块，离区中心远属地理事实',
    'bj-026': '古北水镇在密云区北端古北口，区境南北跨度大',
}


def fail(city, kind, detail):
    fails.append(f'[{city}][{kind}] {detail}')


def warn(city, kind, detail):
    warns.append(f'[{city}][{kind}] {detail}')


def load(fname):
    path = os.path.join(SEED_DIR, fname)
    rows = []
    bad = []
    with open(path, encoding='utf-8') as f:
        for i, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                rows.append((i, json.loads(line)))
            except json.JSONDecodeError as e:
                bad.append((i, str(e)))
    return rows, bad


def havings(o):
    la = o.get('la')
    lo = o.get('lo')
    if isinstance(la, (int, float)) and isinstance(lo, (int, float)):
        return (float(la), float(lo))
    return None


def dist_m(a, b):
    # 球面近似（haversine），50m 阈值下足够
    rlat = math.pi / 180
    x = math.sin((b[0] - a[0]) * rlat / 2) ** 2
    y = math.sin((b[1] - a[1]) * rlat / 2) ** 2
    h = x + math.cos(a[0] * rlat) * math.cos(b[0] * rlat) * y
    return 2 * 6371000 * math.asin(math.sqrt(h))


spots = {}   # city -> rows
areas = {}
stats_lines = []

for city_key in CITIES:
    city = CITY_CN[city_key]
    bbox = CITY_BBOX[city]

    # ---- 景点 ----
    rows, bad = load(f'spots_{city_key}.jsonl')
    spots[city] = rows
    for i, e in bad:
        fail(city, 'JSON坏行', f'spots 第{i}行: {e}')
    seen_ids = {}
    seen_names = {}
    coords = []
    no_geo = 0
    for i, o in rows:
        sid = o.get('id')
        name = o.get('n')
        if not isinstance(sid, str) or not sid or not isinstance(name, str) or not name:
            fail(city, '缺id/name', f'spots 第{i}行')
            continue
        if sid in seen_ids:
            fail(city, 'id重复', f'{sid}（{name}）与第{seen_ids[sid]}行重复')
        else:
            seen_ids[sid] = i
        if name in seen_names:
            warn(city, '同名', f'{name} 第{i}行 ≈ 第{seen_names[name]}行')
        else:
            seen_names[name] = i
        tags = o.get('t')
        if isinstance(tags, list):
            for t in tags:
                if t not in SPOT_TAGS:
                    fail(city, '标签外值', f'{sid} {name}: {t}')
        else:
            fail(city, '标签缺失', f'{sid} {name}: t 不是数组')
        g = havings(o)
        if g is None:
            no_geo += 1
            district = o.get('d')
            if not (isinstance(district, str) and district in KNOWN_DISTRICTS[city]):
                fail(city, '回退点出城', f'{sid} {name} 无坐标且区「{district}」不在区中心表，将落到深圳兜底点')
            warn(city, '景点无坐标', f'{sid} {name}（将回退区中心）')
        else:
            la, lo = g
            if not (bbox[0] <= la <= bbox[1] and bbox[2] <= lo <= bbox[3]):
                fail(city, '坐标出城', f'{sid} {name}: ({la}, {lo}) 在 {city} 城界外')
            district = o.get('d')
            if isinstance(district, str) and district in KNOWN_DISTRICTS[city]:
                d = dist_m((la, lo), KNOWN_DISTRICTS[city][district])
                if d > 30000 and sid not in WHITELIST_FAR:
                    fail(city, '离区过远', f'{sid} {name}: 距{district}中心 {d/1000:.1f}km，geocode 错区嫌疑')
            coords.append((sid, name, (la, lo)))
    # 同城撞点
    for a in range(len(coords)):
        for b in range(a + 1, len(coords)):
            d = dist_m(coords[a][2], coords[b][2])
            if d < 50:
                fail(city, '坐标撞点', f'{coords[a][1]}({coords[a][0]}) ≈ {coords[b][1]}({coords[b][0]}) 相距 {d:.0f}m')
    if not (30 <= len(rows) <= 50):
        fail(city, '验收线', f'景点 {len(rows)} 个，阶段5 验收线 30-50')

    # ---- 区域 ----
    rows_a, bad_a = load(f'areas_{city_key}.jsonl')
    areas[city] = rows_a
    for i, e in bad_a:
        fail(city, 'JSON坏行', f'areas 第{i}行: {e}')
    seen_area_ids = set()
    area_no_geo = 0
    tier_count = {}
    group_count = {}
    for i, o in rows_a:
        aid = o.get('id')
        name = o.get('n')
        if not isinstance(aid, str) or not aid or not isinstance(name, str) or not name:
            fail(city, '缺id/name', f'areas 第{i}行')
            continue
        if aid in seen_area_ids:
            fail(city, 'id重复', f'areas {aid}（{name}）重复')
        seen_area_ids.add(aid)
        if o.get('tier') not in AREA_TIERS:
            fail(city, '档位外值', f'{aid} {name}: tier={o.get("tier")!r}')
        if o.get('g') not in AREA_GROUPS:
            fail(city, '分组外值', f'{aid} {name}: g={o.get("g")!r}')
        tier_count[o.get('tier')] = tier_count.get(o.get('tier'), 0) + 1
        group_count[o.get('g')] = group_count.get(o.get('g'), 0) + 1
        if havings(o) is None:
            area_no_geo += 1
            warn(city, '片区无坐标', f'{aid} {name}（地图不落点）')
    if not (35 <= len(rows_a) <= 50):
        fail(city, '验收线', f'区域 {len(rows_a)} 个，阶段5 验收线 35-50')

    stats_lines.append(
        f'{city}: 景点 {len(rows)}（有坐标 {len(rows) - no_geo}）· 区域 {len(rows_a)}（有坐标 {len(rows_a) - area_no_geo}）'
        f' · 档位 {tier_count} · 分组 {group_count}')

# ---- 跨城 id 撞车 ----
all_ids = {}
for city_key in CITIES:
    city = CITY_CN[city_key]
    for i, o in spots[city] + areas[city]:
        sid = o.get('id')
        if isinstance(sid, str) and sid:
            if sid in all_ids and all_ids[sid][1] != city:
                fail('跨城', 'id重复', f'{sid} 同时在 {all_ids[sid][1]} 与 {city}')
            all_ids[sid] = (i, city)

# ---- 完整度普查（§3.2 字段组；结构性缺口单列，不与坏数据混淆）----
print('== 每城概览 ==')
for s in stats_lines:
    print(s)

print('\n== 结构性缺口（种子未采集，非坏数据；与 INIT_REPORT §四-3 / §4d 登记一致）==')
bk_m = bk_adv = bk_rel = bk_closed = bk_diff = req = 0
total_spots = sum(len(v) for v in spots.values())
for city_key in CITIES:
    for i, o in spots[CITY_CN[city_key]]:
        bk = o.get('bk') if isinstance(o.get('bk'), dict) else {}
        if bk.get('req') is True:
            req += 1
            if isinstance(bk.get('m'), str) and bk['m']:
                bk_m += 1
            if isinstance(bk.get('adv'), (int, float)) and bk['adv'] > 0:
                bk_adv += 1
            if isinstance(bk.get('rel'), str) and bk['rel']:
                bk_rel += 1
            if isinstance(bk.get('closed'), str) and bk['closed']:
                bk_closed += 1
            if isinstance(bk.get('diff'), str) and bk['diff']:
                bk_diff += 1
print(f'预约组填充率（{req}/{total_spots} 城点需预约）：'
      f'方式 {bk_m}/{req} · 提前天数 {bk_adv}/{req} · 放票时间 {bk_rel}/{req} · 闭馆日 {bk_closed}/{req} · 难度 {bk_diff}/{req}')
print('种子键里不存在的 §3.2 字段（代码侧已留空、UI 不展示）：'
      '景点 brief / entranceTip / nearestMetro / nearbySpotIds，区域 description / commerceTags / priceRange')

print(f'\n== 结果 ==')
for w in warns:
    print(f'WARN  {w}')
for f_ in fails:
    print(f'FAIL  {f_}')
print(f'\n硬失败 {len(fails)} 项 · 警告 {len(warns)} 项 · 退出码 {1 if fails else 0}')
sys.exit(1 if fails else 0)
