function data = load_data()
% 读取所有数据并构建面板数据集
% CEADS为城市级碳排放；城市级社会经济数据来自年鉴提取的panel_city_data.csv

    cfg = config();
    nC = cfg.nCity;
    nY = cfg.nYear;
    years = cfg.yearRange;
    cities = cfg.cities;

    fprintf('========== 数据加载开始 ==========\n');

    %% 1. CEADS碳排放 (emission matrix, 城市级)
    fprintf('读取CEADS碳排放数据 (emission matrix)...\n');
    CO2 = NaN(nC, nY);
    try
        T = readtable(cfg.files.ceads, 'Sheet', 'emission matrix', ...
            'VariableNamingRule', 'preserve');
        varNames = T.Properties.VariableNames;
        ceadsCities = T{:, 1};
        if iscell(ceadsCities), ceadsCities = string(ceadsCities); end

        yrMap = containers.Map('KeyType','int32','ValueType','int32');
        for v = 2:length(varNames)
            yr = str2double(varNames{v});
            if ~isnan(yr) && yr >= years(1) && yr <= years(end)
                yrMap(int32(yr)) = int32(v);
            end
        end
        fprintf('  CEADS可用年份列: %d 个\n', yrMap.Count);

        for i = 1:nC
            matched = false;
            for r = 1:length(ceadsCities)
                cname = ceadsCities(r);
                if endsWith(cname, cities{i}) || strcmp(cname, cities{i})
                    for yr = years
                        if yr > 2019, continue; end
                        j = yr - years(1) + 1;
                        if yrMap.isKey(int32(yr))
                            val = T{r, yrMap(int32(yr))};
                            if iscell(val), val = str2double(val{1}); end
                            if isnumeric(val) && ~isnan(val)
                                CO2(i, j) = val;
                            end
                        end
                    end
                    matched = true;
                    break;
                end
            end
            if ~matched
                fprintf('  未匹配: %s\n', cities{i});
            end
        end
    catch ME
        fprintf('  CEADS读取失败: %s\n', ME.message);
    end
    fprintf('  CEADS匹配城市数: %d/%d\n', sum(any(~isnan(CO2),2)), nC);

    %% 2. EDGAR补充2020-2022（国家级增长率外推）
    fprintf('读取EDGAR数据，外推2020-2022...\n');
    try
        T_edgar = readtable(cfg.files.edgar, 'Sheet', 'TOTALS BY COUNTRY', ...
            'VariableNamingRule', 'preserve', 'Range', 'A10');
        eVars = T_edgar.Properties.VariableNames;
        codeCol = T_edgar{:, 3};
        if iscell(codeCol), codeCol = string(codeCol); end
        chinaRow = find(strcmp(codeCol, 'CHN'), 1);

        if ~isempty(chinaRow)
            edgarYrs = [2019 2020 2021 2022];
            edgarVals = NaN(1, 4);
            for k = 1:4
                colName = sprintf('Y_%d', edgarYrs(k));
                colIdx = find(strcmp(eVars, colName), 1);
                if ~isempty(colIdx)
                    val = T_edgar{chinaRow, colIdx};
                    if iscell(val), val = str2double(val{1}); end
                    edgarVals(k) = val;
                end
            end
            fprintf('  EDGAR中国总排放: 2019=%.1f, 2020=%.1f, 2021=%.1f, 2022=%.1f\n', edgarVals);

            for yr = 2020:min(2022, years(end))
                j = yr - years(1) + 1;
                j2019 = 2019 - years(1) + 1;
                if j > nY || j2019 < 1, continue; end
                growthRate = edgarVals(yr-2018) / edgarVals(1);
                CO2(:, j) = CO2(:, j2019) * growthRate;
            end
            fprintf('  已用EDGAR增长率外推2020-2022\n');
        end
    catch ME
        fprintf('  EDGAR读取失败: %s\n', ME.message);
    end

    %% 3. 读取城市级面板数据 (来自年鉴提取)
    fprintf('读取城市级面板数据 (panel_city_data.csv)...\n');
    csvPath = fullfile(cfg.dataDir, 'panel_city_data.csv');
    if ~isfile(csvPath)
        error('panel_city_data.csv 不存在，请先运行 py build_panel.py');
    end

    T_panel = readtable(csvPath, 'VariableNamingRule', 'preserve', ...
        'TextType', 'string');

    GDP    = NaN(nC, nY);
    pgdp   = NaN(nC, nY);
    indus  = NaN(nC, nY);
    pop_d  = NaN(nC, nY);
    elec   = NaN(nC, nY);
    rd     = NaN(nC, nY);

    for i = 1:nC
        for j = 1:nY
            yr = years(j);
            mask = strcmp(T_panel.city, cities{i}) & (T_panel.year == yr);
            if ~any(mask), continue; end
            row = find(mask, 1);

            v = T_panel.gdp(row);
            if ~isnan(v) && v > 0, GDP(i,j) = v; end

            v = T_panel.pgdp(row);
            if ~isnan(v) && v > 0, pgdp(i,j) = v; end

            v = T_panel.pop(row);
            if ~isnan(v) && v > 0, pop_d(i,j) = v; end

            v = T_panel.indus(row);
            if ~isnan(v) && v > 0, indus(i,j) = v; end

            v = T_panel.elec(row);
            if ~isnan(v) && v > 0, elec(i,j) = v; end

            v = T_panel.rd(row);
            if ~isnan(v) && v > 0, rd(i,j) = v; end
        end
    end
    fprintf('  城市级数据读取完成\n');

    %% 4. 组装输出
    data.CO2    = CO2;
    data.GDP    = GDP;
    data.pgdp   = pgdp;
    data.indus  = indus;
    data.pop    = pop_d;
    data.elec   = elec;
    data.rd     = rd;
    data.cities = cities;
    data.years  = years;
    data.cfg    = cfg;

    % 缺失值统计
    fields = {'CO2','GDP','pgdp','indus','pop','elec','rd'};
    fprintf('\n========== 缺失值统计 ==========\n');
    for k = 1:length(fields)
        mat = data.(fields{k});
        miss = sum(isnan(mat(:)));
        total = numel(mat);
        fprintf('  %-10s: %d/%d (%.1f%% 缺失)\n', fields{k}, miss, total, 100*miss/total);
    end

    if ~exist(cfg.outputDir, 'dir'), mkdir(cfg.outputDir); end
    save(fullfile(cfg.outputDir, 'panel_data.mat'), 'data');
    fprintf('\n面板数据已保存至 results/panel_data.mat\n');
end
