function Module4_Policy()
% 模块四：碳达峰优化对策建议
% 基于模块二影响因素分析和模块三预测结果，生成差异化政策建议

    clc; close all;
    fprintf('===== 模块四：碳达峰优化对策建议 =====\n');

    cfg = config();
    set(0, 'DefaultAxesFontName', 'SimHei');
    set(0, 'DefaultTextFontName', 'SimHei');

    %% 1. 调用Python生成对策分析
    fprintf('\n--- 1. 生成对策建议 ---\n');
    policyCSV = fullfile(cfg.outputDir, '对策建议表.csv');
    if ~isfile(policyCSV)
        fprintf('运行Python对策分析脚本...\n');
        [status, cmdout] = system('py Module4_Policy.py');
        if status ~= 0
            error('Python脚本执行失败:\n%s', cmdout);
        end
        fprintf('%s\n', cmdout);
    else
        fprintf('对策建议已存在，跳过生成\n');
    end

    %% 2. 读取结果
    fprintf('\n--- 2. 读取对策分析结果 ---\n');
    drivers = readtable(fullfile(cfg.outputDir, '核心驱动因素.csv'), 'Encoding', 'UTF-8', 'VariableNamingRule', 'preserve');
    cityClass = readtable(fullfile(cfg.outputDir, '城市分类.csv'), 'Encoding', 'UTF-8', 'VariableNamingRule', 'preserve');
    policies = readtable(fullfile(cfg.outputDir, '对策建议表.csv'), 'Encoding', 'UTF-8', 'VariableNamingRule', 'preserve');
    policyAlign = readtable(fullfile(cfg.outputDir, '政策对接表.csv'), 'Encoding', 'UTF-8', 'VariableNamingRule', 'preserve');

    fprintf('核心驱动因素: %d个\n', height(drivers));
    fprintf('城市分类: %d个城市\n', height(cityClass));
    fprintf('对策建议: %d条\n', height(policies));
    fprintf('政策对接: %d项\n', height(policyAlign));

    %% 3. 生成对策优先级矩阵图
    fprintf('\n--- 3. 可视化对策体系 ---\n');
    plot_policy_matrix(policies, cfg);

    %% 4. 生成分省对策建议
    plot_province_policy(cityClass, cfg);

    %% 5. 生成减排路径图
    plot_reduction_path(cfg);

    fprintf('\n===== 模块四完成 =====\n');
    fprintf('\n核心建议:\n');
    fprintf('1. 产业结构优化是首要对策（第二产业占比是核心驱动）\n');
    fprintf('2. 能源结构调整是关键路径（2030年清洁能源占比达40%%）\n');
    fprintf('3. 差异化施策：已达峰城市巩固成果，远期达峰城市加速转型\n');
    fprintf('4. 建立长三角统一碳市场，推动区域协同减排\n');
end

%% ==================== 对策优先级矩阵 ====================
function plot_policy_matrix(policies, cfg)
    categories = unique(policies.("对策类别"));
    priorities = {'高','中','低'};

    matrix = zeros(length(categories), length(priorities));
    for i = 1:length(categories)
        for j = 1:length(priorities)
            count = sum(strcmp(policies.("对策类别"), categories{i}) & ...
                       strcmp(policies.("优先级"), priorities{j}));
            matrix(i, j) = count;
        end
    end

    fig = figure('Position', [50 50 900 600], 'Color', 'w');
    b = bar(matrix, 'grouped');
    b(1).FaceColor = [0.9 0.3 0.1]; % 高
    b(2).FaceColor = [0.95 0.6 0.1]; % 中
    b(3).FaceColor = [0.6 0.6 0.6]; % 低

    set(gca, 'XTickLabel', categories, 'XTickLabelRotation', 15);
    ylabel('措施数量');
    title('碳达峰对策优先级矩阵', 'FontSize', 13, 'FontWeight', 'bold');
    legend(priorities, 'Location', 'northeast');
    grid on; set(gca, 'GridAlpha', 0.3);

    exportgraphics(fig, fullfile(cfg.outputDir, '图18_对策优先级矩阵.png'), 'Resolution', 300);
    fprintf('对策优先级矩阵已保存\n');
end

%% ==================== 分省对策建议 ====================
function plot_province_policy(cityClass, cfg)
    provinces = {'上海','江苏','浙江','安徽'};
    types = {'已达峰','近期达峰(2023-2030)','远期达峰(2031-2040)'};

    provData = zeros(length(provinces), length(types));
    for i = 1:length(provinces)
        for j = 1:length(types)
            count = sum(strcmp(cityClass.province, provinces{i}) & ...
                       strcmp(cityClass.("类型"), types{j}));
            provData(i, j) = count;
        end
    end

    fig = figure('Position', [50 50 800 500], 'Color', 'w');
    b = bar(provData, 'stacked');
    b(1).FaceColor = [0.15 0.68 0.38]; % 已达峰
    b(2).FaceColor = [0.95 0.6 0.1];   % 近期
    b(3).FaceColor = [0.9 0.3 0.1];    % 远期

    set(gca, 'XTickLabel', provinces);
    ylabel('城市数量');
    title('长三角分省碳达峰进度（强化减排情景）', 'FontSize', 13, 'FontWeight', 'bold');
    legend(types, 'Location', 'northwest');
    grid on; set(gca, 'GridAlpha', 0.3);

    % 添加对策建议文本
    text(1, provData(1,1)+provData(1,2)+provData(1,3)+1, '巩固减排成果', ...
        'HorizontalAlignment', 'center', 'FontSize', 9, 'Color', [0.2 0.2 0.2]);
    text(4, provData(4,1)+provData(4,2)+provData(4,3)+1, '加速产业转型', ...
        'HorizontalAlignment', 'center', 'FontSize', 9, 'Color', [0.2 0.2 0.2]);

    exportgraphics(fig, fullfile(cfg.outputDir, '图19_分省对策建议.png'), 'Resolution', 300);
    fprintf('分省对策建议图已保存\n');
end

%% ==================== 减排路径图 ====================
function plot_reduction_path(cfg)
    % 读取LSTM预测结果
    pred = readtable(fullfile(cfg.outputDir, 'lstm_predictions.csv'), 'Encoding', 'UTF-8');
    hist = readtable(fullfile(cfg.outputDir, 'lstm_hist_co2.csv'), 'Encoding', 'UTF-8');

    % 计算历史总量
    histYears = unique(hist.year);
    histTotal = zeros(length(histYears), 1);
    for i = 1:length(histYears)
        histTotal(i) = sum(hist.co2(hist.year == histYears(i)), 'omitnan');
    end

    % 计算三情景预测总量
    scenarios = unique(pred.scenario);
    predYears = unique(pred.year);

    fig = figure('Position', [50 50 1000 600], 'Color', 'w');
    hold on;

    % 历史数据
    plot(histYears, histTotal, 'k-o', 'LineWidth', 2.5, 'MarkerSize', 5, 'DisplayName', '历史排放');

    % 三情景预测
    colors = {[0.2 0.4 0.8], [0.2 0.7 0.3], [0.9 0.3 0.1]};
    for s = 1:length(scenarios)
        sRows = pred(strcmp(pred.scenario, scenarios{s}), :);
        predTotal = zeros(length(predYears), 1);
        for i = 1:length(predYears)
            predTotal(i) = sum(sRows.co2(sRows.year == predYears(i)), 'omitnan');
        end
        plot(predYears, predTotal, '-s', 'LineWidth', 2, 'MarkerSize', 5, ...
            'Color', colors{s}, 'DisplayName', scenarios{s});
    end

    % 添加关键节点标注
    xline(2022, '--', '历史/预测分界', 'Color', [0.5 0.5 0.5], 'LineWidth', 1.5, ...
        'LabelOrientation', 'horizontal', 'FontSize', 10);
    xline(2030, '--', '2030目标年', 'Color', [0.8 0.3 0.1], 'LineWidth', 1.5, ...
        'LabelOrientation', 'horizontal', 'FontSize', 10);

    hold off;
    xlabel('年份', 'FontSize', 12);
    ylabel('碳排放总量（万吨CO_2）', 'FontSize', 12);
    title('长三角碳达峰减排路径（2003-2040）', 'FontSize', 14, 'FontWeight', 'bold');
    legend('Location', 'northeast', 'FontSize', 10);
    grid on; set(gca, 'GridAlpha', 0.3);
    xlim([2003 2040]);

    exportgraphics(fig, fullfile(cfg.outputDir, '图20_减排路径.png'), 'Resolution', 300);
    fprintf('减排路径图已保存\n');
end
