function mat = read_panel(filepath, cities, years, label)
% 通用面板数据读取：从Excel中提取 城市×年份 矩阵
% 自动识别城市列和年份列

    nC = length(cities);
    nY = length(years);
    mat = NaN(nC, nY);

    if ~isfile(filepath)
        fprintf('  [%s] 文件不存在: %s\n', label, filepath);
        return;
    end

    try
        T = readtable(filepath, 'Sheet', 1, 'VariableNamingRule', 'preserve');
    catch
        try
            T = readtable(filepath, 'VariableNamingRule', 'preserve');
        catch ME
            fprintf('  [%s] 读取失败: %s\n', label, ME.message);
            return;
        end
    end

    varNames = T.Properties.VariableNames;
    fprintf('  [%s] 列名: ', label);
    fprintf('%s ', varNames{1:min(6,end)});
    if length(varNames)>6, fprintf('...'); end
    fprintf('\n');

    % 识别城市列（第一个含中文文本的列）
    cityColIdx = 1;
    cityCol = T{:, cityColIdx};
    if isnumeric(cityCol)
        for cc = 1:min(5, width(T))
            tmp = T{:, cc};
            if iscell(tmp) || isstring(tmp)
                cityColIdx = cc;
                cityCol = tmp;
                break;
            end
        end
    end
    if iscell(cityCol), cityCol = string(cityCol); end

    % 识别年份列
    yrColMap = containers.Map('KeyType','int32','ValueType','int32');
    for v = 1:length(varNames)
        vn = varNames{v};
        nums = regexp(vn, '(\d{4})', 'tokens');
        if ~isempty(nums)
            yr = str2double(nums{1}{1});
            if yr >= years(1) && yr <= years(end)
                yrColMap(int32(yr)) = int32(v);
            end
        end
    end

    % 如果列名中没有年份，尝试转置格式（年份在行中）
    if yrColMap.Count == 0
        fprintf('  [%s] 列名无年份，尝试行匹配...\n', label);
        % 可能第一行是城市名，第一列是年份
        for v = 2:length(varNames)
            vn = varNames{v};
            vn = regexprep(vn, '[^0-9一-鿿]', '');
            for ci = 1:nC
                if contains(vn, cities{ci})
                    % 找到城市在列中，年份应在第一列
                    for r = 1:height(T)
                        yrVal = T{r, 1};
                        if iscell(yrVal), yrVal = yrVal{1}; end
                        if ischar(yrVal)||isstring(yrVal), yrVal = str2double(yrVal); end
                        if ~isnan(yrVal) && yrVal >= years(1) && yrVal <= years(end)
                            j = find(years == yrVal);
                            val = T{r, v};
                            if iscell(val), val = str2double(val{1}); end
                            if isnumeric(val), mat(ci, j) = val; end
                        end
                    end
                end
            end
        end
        matched = sum(any(~isnan(mat), 2));
        fprintf('  [%s] 转置匹配城市数: %d/%d\n', label, matched, nC);
        return;
    end

    % 标准格式：城市在行，年份在列
    for i = 1:nC
        idx = find(contains(cityCol, cities{i}), 1);
        if isempty(idx), continue; end
        for yr = years
            if yrColMap.isKey(int32(yr))
                j = yr - years(1) + 1;
                colIdx = yrColMap(int32(yr));
                val = T{idx, colIdx};
                if iscell(val), val = str2double(val{1}); end
                if isnumeric(val) && ~isnan(val)
                    mat(i, j) = val;
                end
            end
        end
    end

    matched = sum(any(~isnan(mat), 2));
    fprintf('  [%s] 匹配城市数: %d/%d\n', label, matched, nC);
end
