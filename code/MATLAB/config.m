function cfg = config()
% 长三角地级市碳排放研究 - 全局配置

    cfg.dataDir = fileparts(mfilename('fullpath'));
    cfg.outputDir = fullfile(cfg.dataDir, 'results');
    if ~exist(cfg.outputDir, 'dir'), mkdir(cfg.outputDir); end

    cfg.yearRange = 2003:2022;
    cfg.predRange = 2023:2040;
    cfg.elecEF = 0.5306; % 电力排放因子 kgCO2/kWh

    % 41个长三角地级市
    cfg.cities = { ...
        '上海'; ...
        '南京';'无锡';'徐州';'常州';'苏州';'南通';'连云港';'淮安';'盐城';'扬州';'镇江';'泰州';'宿迁'; ...
        '杭州';'宁波';'温州';'嘉兴';'湖州';'绍兴';'金华';'衢州';'舟山';'台州';'丽水'; ...
        '合肥';'芜湖';'蚌埠';'淮南';'马鞍山';'淮北';'铜陵';'安庆';'黄山';'滁州';'阜阳';'宿州';'六安';'亳州';'池州';'宣城'};

    cfg.province = [repmat({'上海'},1,1); repmat({'江苏'},13,1); ...
        repmat({'浙江'},11,1); repmat({'安徽'},16,1)];

    cfg.nCity = length(cfg.cities);
    cfg.nYear = length(cfg.yearRange);

    % 城市经纬度（用于空间分析）
    cfg.lon = [121.47; ...
        118.80;120.30;117.28;119.97;120.62;120.87;119.22;119.03;120.16;119.41;119.43;119.92;118.28; ...
        120.15;121.55;120.70;120.76;120.09;120.58;119.65;118.87;122.11;121.42;119.92; ...
        117.28;118.38;117.39;116.98;118.51;116.79;117.81;117.05;118.34;118.32;115.81;116.96;116.52;115.78;117.49;118.76];

    cfg.lat = [31.23; ...
        32.06;31.49;34.26;31.81;31.30;31.98;34.60;33.61;33.38;32.39;32.20;32.46;33.96; ...
        30.27;29.87;28.00;30.75;30.87;30.00;29.08;28.94;30.00;28.66;28.47; ...
        31.86;31.33;32.92;32.63;31.67;33.97;30.95;30.53;29.71;32.30;32.89;33.64;31.74;33.84;30.66;30.95];

    % 数据文件路径
    cfg.files.ceads    = fullfile(cfg.dataDir, '模块一_CEADS_1997-2019年290个中国城市碳排放清单.xlsx');
    cfg.files.edgar    = fullfile(cfg.dataDir, '模块一_EDGAR_IEA_EDGAR_CO2_1970_2023.xlsx');
    cfg.files.elec     = fullfile(cfg.dataDir, '模块一二_电力消费量.xlsx');
    cfg.files.gdp      = fullfile(cfg.dataDir, '模块二三_GDP年度数据.xlsx');
    cfg.files.industry = fullfile(cfg.dataDir, '模块二三_三次产业构成年度数据.xlsx');
    cfg.files.energy   = fullfile(cfg.dataDir, '模块二_能源消费总量.xlsx');
    cfg.files.pop      = fullfile(cfg.dataDir, '模块二_总人口_城镇人口.xlsx');
    cfg.files.coal     = fullfile(cfg.dataDir, '模块二_煤炭消费占比.xlsx');
    cfg.files.rd       = fullfile(cfg.dataDir, '模块二_R&D.xlsx');
    cfg.files.account  = fullfile(cfg.dataDir, '模块二三_国民经济国民经济核算指标.xls');
end
