# -*- coding: utf-8 -*-
"""
从年鉴CSV文件中提取41个长三角城市的面板数据
输出: panel_city_data.csv (城市×年份 面板)
"""
import os, csv, re, math

BASE = os.path.dirname(os.path.abspath(__file__))
CSV_DIR = os.path.join(BASE, 'csv_data')

CITIES = [
    '上海',
    '南京','无锡','徐州','常州','苏州','南通','连云港','淮安','盐城','扬州','镇江','泰州','宿迁',
    '杭州','宁波','温州','嘉兴','湖州','绍兴','金华','衢州','舟山','台州','丽水',
    '合肥','芜湖','蚌埠','淮南','马鞍山','淮北','铜陵','安庆','黄山','滁州','阜阳','宿州','六安','亳州','池州','宣城'
]
YEARS = list(range(2003, 2023))

def read_csv_file(path):
    rows = []
    try:
        with open(path, 'r', encoding='utf-8-sig') as f:
            reader = csv.reader(f)
            for row in reader:
                rows.append(row)
    except:
        pass
    return rows

def parse_num(s):
    if s is None:
        return None
    s = str(s).strip().replace(',', '').replace(' ', '')
    if s in ('', 'None', 'none', '-', '…', '...'):
        return None
    try:
        v = float(s)
        return v if math.isfinite(v) else None
    except:
        return None

def match_city(cell, target):
    """检查单元格是否匹配目标城市"""
    cell = str(cell).strip().replace(' ', '').replace('　', '')
    target = target.strip()
    # 精确匹配（去掉市字）
    cell_clean = cell.rstrip('市')
    if cell_clean == target:
        return True
    # 上海特殊处理
    if target == '上海' and cell_clean in ('上海', '上海市'):
        return True
    return False

def has_english_col(rows):
    """检测是否有英文城市名列(col B)"""
    eng_markers = ['Beijing', 'Tianjin', 'Shanghai', 'City', 'Nanjing', 'Hebei']
    for row in rows[:30]:
        if len(row) > 1:
            for m in eng_markers:
                if m in str(row[1]):
                    return True
    return False

def find_year_folder(yr):
    """找到年份对应的csv_data子目录"""
    for d in os.listdir(CSV_DIR):
        if d.startswith(str(yr)) and os.path.isdir(os.path.join(CSV_DIR, d)):
            return os.path.join(CSV_DIR, d)
    return None

def find_file(folder, include_kw, exclude_kw=None):
    """在文件夹中找匹配关键词的CSV文件"""
    if not folder or not os.path.isdir(folder):
        return None
    candidates = []
    for f in os.listdir(folder):
        if not f.endswith('.csv'):
            continue
        name = f
        if all(kw in name for kw in include_kw):
            if exclude_kw and any(ek in name for ek in exclude_kw):
                continue
            candidates.append(os.path.join(folder, f))
    # 优先选不含"市辖区"的
    non_district = [c for c in candidates if '市辖区' not in os.path.basename(c)]
    if non_district:
        return non_district[0]
    return candidates[0] if candidates else None

def extract_data(csv_path, cities, col_offset):
    """
    从CSV提取城市数据
    col_offset: 从数据起始列算起的偏移量(0=第一个数据列, 2=第二对的全市列, ...)
    """
    if not csv_path or not os.path.isfile(csv_path):
        return {}
    rows = read_csv_file(csv_path)
    if not rows:
        return {}

    has_eng = has_english_col(rows)
    data_start = 2 if has_eng else 1
    target_col = data_start + col_offset

    results = {}
    for row in rows:
        if len(row) <= target_col:
            continue
        cell = str(row[0])
        for city in cities:
            if city not in results and match_city(cell, city):
                val = parse_num(row[target_col])
                if val is not None and val > 0:
                    results[city] = val
                break
    return results

def extract_elec_old(csv_path, cities):
    """
    从供水供电文件提取用电量 (2003-2010格式)
    用电量列通过扫描表头中的'用电'关键词定位
    """
    if not csv_path or not os.path.isfile(csv_path):
        return {}
    rows = read_csv_file(csv_path)
    if not rows:
        return {}

    # 扫描前15行找'用电'列（跳过col 0/1的标题行）
    elec_col = None
    for r in range(min(15, len(rows))):
        for c in range(2, len(rows[r])):  # 从col 2开始，跳过城市名和英文名列
            txt = str(rows[r][c])
            if '用电量' in txt or '用电' in txt:
                elec_col = c
                break
        if elec_col is not None:
            break

    if elec_col is None:
        # fallback: 尝试固定位置
        has_eng = has_english_col(rows)
        elec_col = 5 if has_eng else 4

    results = {}
    for row in rows:
        if len(row) <= elec_col:
            continue
        cell = str(row[0])
        for city in cities:
            if city not in results and match_city(cell, city):
                val = parse_num(row[elec_col])
                if val is not None and val > 0:
                    results[city] = val
                break
    return results

def extract_rd(csv_path, cities):
    """从科技创新文件提取R&D经费支出(万元)"""
    if not csv_path or not os.path.isfile(csv_path):
        return {}
    rows = read_csv_file(csv_path)
    if not rows:
        return {}

    # R&D经费支出通常在第4列(有英文列)或第3列
    rd_col = None
    for r in range(min(10, len(rows))):
        for c in range(len(rows[r])):
            txt = str(rows[r][c])
            if 'R&D' in txt and ('经费' in txt or '支出' in txt or 'Outlay' in txt or 'Internal' in txt):
                rd_col = c
                break
        if rd_col is not None:
            break

    if rd_col is None:
        has_eng = has_english_col(rows)
        rd_col = 3 if has_eng else 2

    results = {}
    for row in rows:
        if len(row) <= rd_col:
            continue
        cell = str(row[0])
        for city in cities:
            if city not in results and match_city(cell, city):
                val = parse_num(row[rd_col])
                if val is not None and val > 0:
                    results[city] = val
                break
    return results

# ============================================================
# 主提取逻辑
# ============================================================

JIANGSU = ['南京','无锡','徐州','常州','苏州','南通','连云港','淮安','盐城','扬州','镇江','泰州','宿迁']
ZHEJIANG = ['杭州','宁波','温州','嘉兴','湖州','绍兴','金华','衢州','舟山','台州','丽水']
ANHUI = ['合肥','芜湖','蚌埠','淮南','马鞍山','淮北','铜陵','安庆','黄山','滁州','阜阳','宿州','六安','亳州','池州','宣城']

def load_jiangsu_elec():
    """读取江苏2020-2022城市用电量(亿千瓦时→万千瓦时)"""
    path = os.path.join(CSV_DIR, '用电量2020-2022', '江苏.csv')
    rows = read_csv_file(path)
    if not rows:
        return {}
    # 找表头行(含年份)
    header_row = None
    for i, row in enumerate(rows):
        if any('2020' in str(c) for c in row):
            header_row = i
            break
    if header_row is None:
        return {}
    headers = rows[header_row]
    # 找2020/2021/2022列索引
    yr_cols = {}
    for c, h in enumerate(headers):
        for yr in [2020, 2021, 2022]:
            if str(yr) in str(h):
                yr_cols[yr] = c
                break
    result = {}
    for row in rows[header_row+1:]:
        if len(row) < 2:
            continue
        cell = str(row[0]).strip().replace(' ', '').replace('　', '')
        for city in JIANGSU:
            if city in cell or cell.rstrip('市') == city:
                for yr, c in yr_cols.items():
                    if c < len(row):
                        val = parse_num(row[c])
                        if val is not None and val > 0:
                            result.setdefault(city, {})[yr] = val * 10000  # 亿→万千瓦时
                break
    return result

def load_zhejiang_growth():
    """读取浙江省级用电增长率(相对2019)"""
    path = os.path.join(CSV_DIR, '用电量2020-2022', '浙江.csv')
    rows = read_csv_file(path)
    if not rows:
        print('  浙江文件读取失败')
        return {}
    # 找表头行(年份在不同列中，而非标题行中)
    header_row = None
    for i, row in enumerate(rows):
        yr_count = 0
        for c in range(1, len(row)):
            h_str = str(row[c]).strip().replace('.0', '')
            if h_str in ('2019', '2020', '2021', '2022'):
                yr_count += 1
        if yr_count >= 3:
            header_row = i
            break
    if header_row is None:
        print('  浙江: 未找到含年份列的表头行')
        return {}
    headers = rows[header_row]
    yr_cols = {}
    for c, h in enumerate(headers):
        h_str = str(h).replace('.0', '')
        for yr in [2019, 2020, 2021, 2022]:
            if str(yr) == h_str or str(yr) in h_str:
                yr_cols[yr] = c
                break
    print(f'  浙江年份列: {yr_cols}')
    # 找全社会用电总计行
    for row in rows[header_row+1:]:
        txt = str(row[0]).strip()
        if '全社会用电' in txt or '用电总计' in txt:
            base = parse_num(row[yr_cols.get(2019, -1)]) if 2019 in yr_cols else None
            print(f'  浙江2019基准: {base}')
            if base and base > 0:
                rates = {}
                for yr in [2020, 2021, 2022]:
                    if yr in yr_cols:
                        val = parse_num(row[yr_cols[yr]])
                        if val and val > 0:
                            rates[yr] = val / base
                print(f'  浙江增长率: {rates}')
                return rates
    print('  浙江: 未找到全社会用电行')
    return {}

def build_panel():
    # 初始化数据结构: panel[city][year] = {gdp, pgdp, pop, indus, elec, rd}
    panel = {c: {y: {} for y in YEARS} for c in CITIES}

    for yr in YEARS:
        folder = find_year_folder(yr)
        if not folder:
            print(f'  {yr}: 文件夹未找到')
            continue
        print(f'处理 {yr}...')

        # --- GDP(亿元) ---
        gdp_file = find_file(folder, ['地区生产总值'], ['构成'])
        if not gdp_file:
            gdp_file = find_file(folder, ['综合经济'], ['二', '（二）', '(二)'])
        gdp_data = extract_data(gdp_file, CITIES, col_offset=0)
        pgdp_data = extract_data(gdp_file, CITIES, col_offset=2)
        for c in CITIES:
            if c in gdp_data:
                panel[c][yr]['gdp'] = gdp_data[c]
            if c in pgdp_data:
                panel[c][yr]['pgdp'] = pgdp_data[c]

        # --- 人口(万人) ---
        pop_file = find_file(folder, ['人口'], ['户数'])
        if not pop_file:
            pop_file = find_file(folder, ['人口'])
        pop_data = extract_data(pop_file, CITIES, col_offset=0)
        for c in CITIES:
            if c in pop_data:
                panel[c][yr]['pop'] = pop_data[c]

        # --- 产业结构(第二产业占比%) ---
        indus_file = find_file(folder, ['构成'])
        if not indus_file:
            indus_file = find_file(folder, ['综合经济', '二'])
            if not indus_file:
                indus_file = find_file(folder, ['综合经济'], ['一', '（一）', '(一)'])
        indus_data = extract_data(indus_file, CITIES, col_offset=2)
        for c in CITIES:
            if c in indus_data:
                panel[c][yr]['indus'] = indus_data[c]

        # --- 用电量(万千瓦时) ---
        # 纯用电文件(2019): 用col_offset=0
        # 供水/售水+用电混合文件(2003-2018): 用header扫描找用电列
        elec_file = find_file(folder, ['用电情况'], ['供水', '售水', '排水'])
        if elec_file:
            elec_data = extract_data(elec_file, CITIES, col_offset=0)
        else:
            elec_file = find_file(folder, ['用电'])
            if not elec_file:
                elec_file = find_file(folder, ['供电'])
                if not elec_file:
                    elec_file = find_file(folder, ['供水'])
            elec_data = extract_elec_old(elec_file, CITIES)
        for c in CITIES:
            if c in elec_data:
                panel[c][yr]['elec'] = elec_data[c]

        # --- R&D(万元) ---
        rd_file = find_file(folder, ['科技创新'])
        if rd_file:
            rd_data = extract_rd(rd_file, CITIES)
            for c in CITIES:
                if c in rd_data:
                    panel[c][yr]['rd'] = rd_data[c]

    # ============================================================
    # GDP单位归一化: 2003-2018年鉴GDP为万元，2019+为亿元
    # ============================================================
    print('\nGDP单位归一化...')
    for city in CITIES:
        for yr in YEARS:
            gdp = panel[city][yr].get('gdp')
            if gdp is not None and gdp > 100000:
                panel[city][yr]['gdp'] = gdp / 10000  # 万元→亿元

    # ============================================================
    # 补充2020-2022用电量
    # ============================================================
    print('\n补充2020-2022用电量...')

    # 江苏: 实际城市数据
    js_elec = load_jiangsu_elec()
    for city in JIANGSU:
        if city in js_elec:
            for yr in [2020, 2021, 2022]:
                if yr in js_elec[city]:
                    panel[city][yr]['elec'] = js_elec[city][yr]
                    print(f'  {city} {yr}: {js_elec[city][yr]:.0f} (江苏实际)')

    # 浙江: 省级增长率 × 2019城市值
    zj_rates = load_zhejiang_growth()
    for city in ZHEJIANG:
        base = panel[city].get(2019, {}).get('elec')
        if base and zj_rates:
            for yr in [2020, 2021, 2022]:
                if yr in zj_rates and 'elec' not in panel[city].get(yr, {}):
                    panel[city][yr]['elec'] = base * zj_rates[yr]
                    print(f'  {city} {yr}: {base * zj_rates[yr]:.0f} (浙江增长率)')

    # 上海和安徽: 用2017-2019线性外推
    for city in ['上海'] + ANHUI:
        vals = []
        for yr in [2017, 2018, 2019]:
            v = panel[city].get(yr, {}).get('elec')
            if v:
                vals.append((yr, v))
        if len(vals) >= 2:
            # 线性回归
            n = len(vals)
            sx = sum(v[0] for v in vals)
            sy = sum(v[1] for v in vals)
            sxx = sum(v[0]**2 for v in vals)
            sxy = sum(v[0]*v[1] for v in vals)
            denom = n*sxx - sx*sx
            if abs(denom) > 0:
                slope = (n*sxy - sx*sy) / denom
                intercept = (sy - slope*sx) / n
                for yr in [2020, 2021, 2022]:
                    if 'elec' not in panel[city].get(yr, {}):
                        est = max(intercept + slope * yr, 0)
                        panel[city][yr]['elec'] = est
                        print(f'  {city} {yr}: {est:.0f} (线性外推)')

    # ============================================================
    # 异常值清理: 邻域插值修复跳变
    # ============================================================
    print('\n异常值清理...')
    vars_to_clean = ['gdp', 'pop', 'indus', 'elec']
    fixed_count = 0
    for city in CITIES:
        for var in vars_to_clean:
            vals = [(yr, panel[city][yr].get(var)) for yr in YEARS]
            for i in range(1, len(vals)-1):
                yr, v = vals[i]
                prev_v = vals[i-1][1]
                next_v = vals[i+1][1]
                if v is None or prev_v is None or next_v is None:
                    continue
                expected = (prev_v + next_v) / 2
                if expected > 0 and abs(v - expected) / expected > 0.35:
                    panel[city][yr][var] = expected
                    fixed_count += 1
                    print(f'  {city} {yr} {var}: {v:.1f} -> {expected:.1f}')
    print(f'  共修复 {fixed_count} 个异常值')

    # ============================================================
    # 输出CSV
    # ============================================================
    out_path = os.path.join(BASE, 'panel_city_data.csv')
    fields = ['city', 'year', 'gdp', 'pgdp', 'pop', 'indus', 'elec', 'rd']
    with open(out_path, 'w', newline='', encoding='utf-8-sig') as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        for city in CITIES:
            for yr in YEARS:
                row = {'city': city, 'year': yr}
                for k in ['gdp', 'pgdp', 'pop', 'indus', 'elec', 'rd']:
                    row[k] = panel[city][yr].get(k, '')
                writer.writerow(row)

    # 统计
    print(f'\n输出: {out_path}')
    print(f'城市: {len(CITIES)}, 年份: {len(YEARS)}, 总行数: {len(CITIES)*len(YEARS)}')
    for var in ['gdp', 'pgdp', 'pop', 'indus', 'elec', 'rd']:
        count = sum(1 for c in CITIES for y in YEARS if panel[c][y].get(var) is not None)
        total = len(CITIES) * len(YEARS)
        print(f'  {var}: {count}/{total} ({100*count/total:.1f}%)')

if __name__ == '__main__':
    build_panel()
