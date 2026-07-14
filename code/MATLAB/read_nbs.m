function vals = read_nbs(filepath, years, keywords)
% 读取NBS全国级数据文件
% filepath: xlsx文件路径
% years: 目标年份向量 (如 2003:2022)
% keywords: cell数组，指标名关键词（模糊匹配，任一命中即可）
% 返回: 1 x length(years) 向量

    nY = length(years);
    vals = NaN(1, nY);

    if ~isfile(filepath)
        fprintf('    文件不存在: %s\n', filepath);
        return;
    end

    try
        % 跳过前2行元数据，第3行作为表头
        T = readtable(filepath, 'Sheet', 1, 'VariableNamingRule', 'preserve', ...
            'Range', 'A3');
    catch
        try
            T = readtable(filepath, 'VariableNamingRule', 'preserve', 'Range', 'A3');
        catch ME
            fprintf('    读取失败: %s\n', ME.message);
            return;
        end
    end

    if isempty(T) || width(T) < 2
        fprintf('    表格为空或列数不足\n');
        return;
    end

    varNames = T.Properties.VariableNames;

    % 第一列为指标名
    indicators = T{:, 1};
    if isnumeric(indicators)
        fprintf('    第一列非文本，跳过\n');
        return;
    end
    if iscell(indicators), indicators = string(indicators); end

    % 模糊匹配指标行
    targetRow = 0;
    for k = 1:length(keywords)
        for r = 1:length(indicators)
            if contains(indicators(r), keywords{k})
                targetRow = r;
                break;
            end
        end
        if targetRow > 0, break; end
    end

    if targetRow == 0
        fprintf('    未找到指标: ');
        fprintf('%s ', keywords{:});
        fprintf('\n');
        return;
    end
    fprintf('    匹配指标: %s\n', indicators(targetRow));

    % 提取年份列的值
    for v = 2:length(varNames)
        vn = varNames{v};
        % 年份格式: "2023年" 或 "2023"
        nums = regexp(vn, '(\d{4})', 'tokens');
        if isempty(nums), continue; end
        yr = str2double(nums{1}{1});
        j = find(years == yr);
        if isempty(j), continue; end

        val = T{targetRow, v};
        if iscell(val)
            val = strrep(val{1}, ',', '');
            val = str2double(val);
        elseif isstring(val)
            val = strrep(val, ',', '');
            val = str2double(val);
        end
        if isnumeric(val) && ~isnan(val)
            vals(j) = val;
        end
    end

    matched = sum(~isnan(vals));
    fprintf('    有效年份: %d/%d\n', matched, nY);
end
