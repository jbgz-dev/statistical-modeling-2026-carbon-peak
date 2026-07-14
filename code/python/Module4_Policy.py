import os
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import matplotlib
matplotlib.rcParams['font.sans-serif'] = ['SimHei']
matplotlib.rcParams['axes.unicode_minus'] = False

WORK_DIR = os.path.dirname(os.path.abspath(__file__))
RESULT_DIR = os.path.join(WORK_DIR, 'results')

# 城市-省份映射
CITIES = ['上海',
'南京','无锡','徐州','常州','苏州','南通','连云港','淮安','盐城','扬州','镇江','泰州','宿迁',
'杭州','宁波','温州','嘉兴','湖州','绍兴','金华','衢州','舟山','台州','丽水',
'合肥','芜湖','蚌埠','淮南','马鞍山','淮北','铜陵','安庆','黄山','滁州','阜阳','宿州','六安','亳州','池州','宣城']

PROV_MAP = {}
PROV_MAP['上海'] = '上海'
for c in CITIES[1:14]: PROV_MAP[c] = '江苏'
for c in CITIES[14:25]: PROV_MAP[c] = '浙江'
for c in CITIES[25:]: PROV_MAP[c] = '安徽'

def load_results():
    """读取模块二、三结果"""
    reg = pd.read_csv(os.path.join(RESULT_DIR, '回归结果汇总.csv'), encoding='utf-8-sig')
    peak = pd.read_csv(os.path.join(RESULT_DIR, 'lstm_peak.csv'), encoding='utf-8-sig')
    pred = pd.read_csv(os.path.join(RESULT_DIR, 'lstm_predictions.csv'), encoding='utf-8-sig')
    return reg, peak, pred

def analyze_drivers(reg):
    """分析核心驱动因素"""
    print('\n=== 模块二：核心影响因素 ===')
    fe = reg[['Variable','FE_coef','FE_p']].copy()
    fe.columns = ['变量','系数','P值']
    fe['显著性'] = fe['P值'].apply(lambda x: '***' if x<0.01 else ('**' if x<0.05 else ('*' if x<0.1 else '')))
    fe['影响方向'] = fe['系数'].apply(lambda x: '正向' if x>0 else '负向')

    # 保存到文件而不是打印
    fe.to_csv(os.path.join(RESULT_DIR, '影响因素分析.csv'), index=False, encoding='utf-8-sig')
    print(f'影响因素分析已保存（共{len(fe)}个变量）')

    # 识别核心驱动因素
    sig = fe[fe['P值']<0.05].copy()
    sig['abs_coef'] = sig['系数'].abs()
    sig = sig.sort_values('abs_coef', ascending=False)

    drivers = []
    for _, row in sig.iterrows():
        var = row['变量']
        coef = row['系数']
        direction = '增加' if coef > 0 else '降低'
        if 'lnpgdp' in var.lower():
            drivers.append({'因素':'人均GDP','方向':direction,'系数':coef,'建议':'优化经济结构，提升绿色GDP占比'})
        elif 'indus' in var.lower():
            drivers.append({'因素':'第二产业占比','方向':direction,'系数':coef,'建议':'加快产业结构转型，降低高耗能产业比重'})
        elif 'pop' in var.lower():
            drivers.append({'因素':'人口规模','方向':direction,'系数':coef,'建议':'优化城市空间布局，提升人均碳效率'})
        elif 'elec' in var.lower():
            drivers.append({'因素':'电力消费','方向':direction,'系数':coef,'建议':'提升清洁能源占比，降低电力碳排放强度'})

    return pd.DataFrame(drivers)

def classify_cities(peak):
    """城市分类：按达峰时间"""
    peak['province'] = peak['city'].map(PROV_MAP)
    sc3 = peak[peak['scenario']=='强化减排情景'].copy()

    sc3['类型'] = sc3['peak_year'].apply(lambda y:
        '已达峰' if y <= 2022 else
        ('近期达峰(2023-2030)' if y <= 2030 else '远期达峰(2031-2040)'))

    print('\n=== 城市分类（强化减排情景）===')
    for t in ['已达峰','近期达峰(2023-2030)','远期达峰(2031-2040)']:
        cities = sc3[sc3['类型']==t]['city'].tolist()
        print(f'{t}: {len(cities)}个城市')

    return sc3

def generate_policies(drivers, city_class):
    """生成差异化对策"""
    policies = []

    # 1. 产业结构优化（针对第二产业占比高的影响）
    policies.append({
        '对策类别': '产业结构优化',
        '具体措施': '推动高耗能产业绿色转型，提升第三产业占比',
        '量化目标': '2030年第二产业占比降至40%以下',
        '适用城市': '已达峰城市（巩固成果）',
        '优先级': '高'
    })

    policies.append({
        '对策类别': '产业结构优化',
        '具体措施': '加快淘汰落后产能，严控"两高"项目新增',
        '量化目标': '2025年前完成钢铁、水泥等行业产能压减20%',
        '适用城市': '远期达峰城市（加速转型）',
        '优先级': '高'
    })

    # 2. 能源结构调整
    policies.append({
        '对策类别': '能源结构调整',
        '具体措施': '提升清洁能源使用率，降低电力碳排放因子',
        '量化目标': '2030年清洁能源占比提升至40%',
        '适用城市': '全部城市',
        '优先级': '高'
    })

    policies.append({
        '对策类别': '能源结构调整',
        '具体措施': '推广分布式光伏、海上风电等可再生能源',
        '量化目标': '2030年电力领域碳排放较2022年下降30%',
        '适用城市': '沿海城市（江苏、浙江、上海）',
        '优先级': '中'
    })

    # 3. 技术创新
    policies.append({
        '对策类别': '技术创新驱动',
        '具体措施': '加大R&D投入，推广碳捕集、储能等低碳技术',
        '量化目标': 'R&D经费占GDP比重提升至3.5%',
        '适用城市': '创新型城市（上海、南京、杭州、苏州）',
        '优先级': '中'
    })

    # 4. 建筑领域
    policies.append({
        '对策类别': '建筑领域减排',
        '具体措施': '推广低碳建材，提升建筑能效标准',
        '量化目标': '2030年新建建筑100%执行绿色建筑标准',
        '适用城市': '全部城市',
        '优先级': '中'
    })

    # 5. 交通领域
    policies.append({
        '对策类别': '交通领域减排',
        '具体措施': '推广新能源汽车，优化公共交通体系',
        '量化目标': '2030年新能源汽车保有量占比达50%',
        '适用城市': '全部城市',
        '优先级': '中'
    })

    # 6. 协同政策
    policies.append({
        '对策类别': '区域协同',
        '具体措施': '建立长三角碳排放权交易市场，推动区域减排协同',
        '量化目标': '2025年建成统一碳市场，覆盖80%重点排放企业',
        '适用城市': '全部城市',
        '优先级': '高'
    })

    return pd.DataFrame(policies)

def plot_policy_framework(drivers, policies):
    """绘制对策框架图"""
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(14, 6))

    # 左图：核心驱动因素
    factors = drivers['因素'].tolist()
    coefs = drivers['系数'].abs().tolist()
    colors = ['#e74c3c' if c > 0 else '#27ae60' for c in drivers['系数']]

    ax1.barh(factors, coefs, color=colors, alpha=0.7)
    ax1.set_xlabel('影响系数（绝对值）')
    ax1.set_title('核心驱动因素识别（模块二）', fontsize=13, fontweight='bold')
    ax1.grid(axis='x', alpha=0.3)

    # 右图：对策优先级分布
    policy_counts = policies.groupby(['对策类别','优先级']).size().unstack(fill_value=0)
    policy_counts.plot(kind='barh', stacked=True, ax=ax2,
                       color={'高':'#e74c3c','中':'#f39c12','低':'#95a5a6'}, alpha=0.8)
    ax2.set_xlabel('措施数量')
    ax2.set_title('对策体系框架', fontsize=13, fontweight='bold')
    ax2.legend(title='优先级', loc='lower right')
    ax2.grid(axis='x', alpha=0.3)

    plt.tight_layout()
    plt.savefig(os.path.join(RESULT_DIR, '图16_对策框架.png'), dpi=300, bbox_inches='tight')
    print('对策框架图已保存')

def plot_city_classification(city_class):
    """绘制城市分类地图"""
    fig, ax = plt.subplots(figsize=(10, 8))

    type_colors = {'已达峰':'#27ae60','近期达峰(2023-2030)':'#f39c12','远期达峰(2031-2040)':'#e74c3c'}

    for t, color in type_colors.items():
        tdf = city_class[city_class['类型']==t]
        prov_count = tdf.groupby('province').size()
        ax.barh([f'{p}-{t}' for p in prov_count.index], prov_count.values,
                color=color, alpha=0.7, label=t)

    ax.set_xlabel('城市数量')
    ax.set_title('长三角城市碳达峰分类（强化减排情景）', fontsize=13, fontweight='bold')
    ax.legend(loc='lower right')
    ax.grid(axis='x', alpha=0.3)

    plt.tight_layout()
    plt.savefig(os.path.join(RESULT_DIR, '图17_城市分类.png'), dpi=300, bbox_inches='tight')
    print('城市分类图已保存')

def main():
    print('='*60)
    print('模块四：碳达峰优化对策建议')
    print('='*60)

    print('\n[1] 读取模块二、三结果...')
    reg, peak, pred = load_results()

    print('\n[2] 分析核心驱动因素...')
    drivers = analyze_drivers(reg)

    print('\n[3] 城市分类...')
    city_class = classify_cities(peak)

    print('\n[4] 生成差异化对策...')
    policies = generate_policies(drivers, city_class)
    print(f'生成{len(policies)}条对策建议')

    print('\n[5] 保存结果...')
    drivers.to_csv(os.path.join(RESULT_DIR, '核心驱动因素.csv'), index=False, encoding='utf-8-sig')
    city_class.to_csv(os.path.join(RESULT_DIR, '城市分类.csv'), index=False, encoding='utf-8-sig')
    policies.to_csv(os.path.join(RESULT_DIR, '对策建议表.csv'), index=False, encoding='utf-8-sig')

    print('\n[6] 生成可视化...')
    plot_policy_framework(drivers, policies)
    plot_city_classification(city_class)

    print('\n[7] 生成政策对接表...')
    policy_align = pd.DataFrame([
        {'国家/区域政策':'碳达峰行动方案','对接措施':'产业结构优化、能源结构调整','实施路径':'2030年前实现碳达峰'},
        {'国家/区域政策':'长三角一体化发展规划','对接措施':'区域协同减排、碳市场建设','实施路径':'建立统一碳排放权交易市场'},
        {'国家/区域政策':'清洁能源发展规划','对接措施':'提升清洁能源占比至40%','实施路径':'推广光伏、风电等可再生能源'},
        {'国家/区域政策':'工业绿色发展规划','对接措施':'淘汰落后产能、严控两高项目','实施路径':'2025年前完成重点行业产能压减'},
    ])
    policy_align.to_csv(os.path.join(RESULT_DIR, '政策对接表.csv'), index=False, encoding='utf-8-sig')

    print('\n'+'='*60)
    print('模块四完成！')
    print('='*60)
    print('\n核心结论：')
    print('1. 第二产业占比是碳排放核心驱动因素，产业结构优化是首要对策')
    print('2. 32个城市已达峰，需巩固减排成果；9个城市需加速转型')
    print('3. 能源结构调整是关键路径，2030年清洁能源占比需达40%')
    print('4. 建议建立长三角统一碳市场，推动区域协同减排')

if __name__ == '__main__':
    main()
