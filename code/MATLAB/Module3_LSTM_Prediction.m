function Module3_LSTM_Prediction()
% 模块三：基于LSTM神经网络的长三角地级市碳达峰预测
% LSTM多变量时序预测 + 三情景分析 + 碳达峰时间判定

    clc; close all;
    fprintf('===== 模块三：LSTM碳达峰预测 =====\n');

    cfg = config();
    set(0, 'DefaultAxesFontName', 'SimHei');
    set(0, 'DefaultTextFontName', 'SimHei');

    %% 1. 调用Python LSTM训练与预测
    fprintf('\n--- 1. LSTM模型训练 ---\n');
    lstmCSV = fullfile(cfg.outputDir, 'lstm_predictions.csv');
    if ~isfile(lstmCSV)
        fprintf('运行Python LSTM脚本...\n');
        [status, cmdout] = system('py lstm_predict.py');
        if status ~= 0
            error('Python脚本执行失败:\n%s', cmdout);
        end
        fprintf('%s\n', cmdout);
    else
        fprintf('LSTM结果已存在，跳过训练\n');
    end

    %% 2. 读取结果
    fprintf('\n--- 2. 读取LSTM结果 ---\n');
    opts = detectImportOptions(fullfile(cfg.outputDir, 'lstm_loss.csv'));
    loss = readtable(fullfile(cfg.outputDir, 'lstm_loss.csv'));
    metrics = readtable(fullfile(cfg.outputDir, 'lstm_metrics.csv'), 'Encoding', 'UTF-8');
    valData = readtable(fullfile(cfg.outputDir, 'lstm_validation.csv'), 'Encoding', 'UTF-8');
    predData = readtable(fullfile(cfg.outputDir, 'lstm_predictions.csv'), 'Encoding', 'UTF-8');
    peakData = readtable(fullfile(cfg.outputDir, 'lstm_peak.csv'), 'Encoding', 'UTF-8');
    histData = readtable(fullfile(cfg.outputDir, 'lstm_hist_co2.csv'), 'Encoding', 'UTF-8');
    fprintf('数据读取完成\n');

    %% 3. Loss曲线
    fprintf('\n--- 3. 可视化 ---\n');
    plot_loss(loss, cfg);

    %% 4. 验证效果
    plot_validation(valData, histData, metrics, cfg);

    %% 5. 三情景预测
    plot_scenarios(predData, histData, cfg);

    %% 6. 碳达峰热力图
    plot_peak_heatmap(peakData, cfg);

    %% 7. 达峰年份分布
    plot_peak_dist(peakData, cfg);

    %% 8. MAPE分布
    plot_mape(metrics, cfg);

    fprintf('\n===== 模块三完成 =====\n');
end

%% ==================== Loss曲线 ====================
function plot_loss(loss, cfg)
    fig = figure('Position', [50 50 800 400], 'Color', 'w');
    plot(loss.epoch, loss.train_loss, 'b-', 'LineWidth', 1.5); hold on;
    plot(loss.epoch, loss.val_loss, 'r-', 'LineWidth', 1.5);
    xlabel('Epoch'); ylabel('MSE Loss');
    title('LSTM训练损失曲线');
    legend('训练集', '验证集', 'Location', 'northeast');
    grid on; set(gca, 'GridAlpha', 0.3);
    exportgraphics(fig, fullfile(cfg.outputDir, '图10_LSTM损失曲线.png'), 'Resolution', 300);
    fprintf('Loss曲线已保存\n');
end

%% ==================== 验证效果 ====================
function plot_validation(valData, histData, metrics, cfg)
    repCities = {'上海','南京','杭州','合肥','苏州','宁波'};
    fig = figure('Position', [50 50 1200 800], 'Color', 'w');
    for k = 1:length(repCities)
        cname = repCities{k};
        subplot(2, 3, k);
        hRows = histData(strcmp(histData.city, cname), :);
        vRows = valData(strcmp(valData.city, cname), :);
        if isempty(hRows) || isempty(vRows), continue; end
        plot(hRows.year, hRows.co2, 'ko-', 'LineWidth', 1.5, 'MarkerSize', 4); hold on;
        plot(vRows.year, vRows.predicted, 'rs-', 'LineWidth', 1.5, 'MarkerSize', 6);
        plot(vRows.year, vRows.actual, 'b^-', 'LineWidth', 1.5, 'MarkerSize', 6);
        hold off;
        mRow = metrics(strcmp(metrics.city, cname), :);
        if ~isempty(mRow)
            title(sprintf('%s (MAPE=%.1f%%)', cname, mRow.mape(1)));
        else
            title(cname);
        end
        xlabel('年份'); ylabel('碳排放');
        legend('历史值','LSTM预测','实际值', 'Location','best','FontSize',7);
        grid on; set(gca, 'GridAlpha', 0.3);
    end
    sgtitle('LSTM模型验证效果（2020-2022）', 'FontSize', 13, 'FontWeight', 'bold');
    exportgraphics(fig, fullfile(cfg.outputDir, '图11_LSTM验证效果.png'), 'Resolution', 300);
    fprintf('验证效果图已保存\n');
end

%% ==================== 三情景预测 ====================
function plot_scenarios(predData, histData, cfg)
    fig = figure('Position', [50 50 1000 500], 'Color', 'w');
    hold on;
    cities = unique(histData.city);
    years = unique(histData.year);
    histTotal = zeros(length(years), 1);
    for j = 1:length(years)
        yRows = histData(histData.year == years(j), :);
        histTotal(j) = sum(yRows.co2, 'omitnan');
    end
    plot(years, histTotal, 'k-o', 'LineWidth', 2, 'MarkerSize', 4);
    legendStr = {'历史值'};
    scNames = {'基准情景','低碳转型情景','强化减排情景'};
    colors = {[0.2 0.4 0.8],[0.2 0.7 0.3],[0.9 0.3 0.1]};
    predYears = unique(predData.year);
    for s = 1:3
        sRows = predData(strcmp(predData.scenario, scNames{s}), :);
        totalPred = zeros(length(predYears), 1);
        for j = 1:length(predYears)
            yRows = sRows(sRows.year == predYears(j), :);
            totalPred(j) = sum(yRows.co2, 'omitnan');
        end
        plot(predYears, totalPred, '-s', 'LineWidth', 2, 'MarkerSize', 4, 'Color', colors{s});
        legendStr{end+1} = scNames{s};
        allY = [years; predYears];
        allC = [histTotal; totalPred];
        [peakVal, peakIdx] = max(allC);
        peakYear = allY(peakIdx);
        plot(peakYear, peakVal, 'p', 'MarkerSize', 15, 'MarkerFaceColor', colors{s}, 'MarkerEdgeColor', 'k');
        fprintf('%s: 达峰年=%d, 峰值=%.2f\n', scNames{s}, peakYear, peakVal);
    end
    hold off;
    xline(2022.5, '--', '预测起点', 'Color', [0.5 0.5 0.5], 'LabelOrientation', 'horizontal');
    xlabel('年份'); ylabel('碳排放总量');
    title('长三角地区碳排放LSTM三情景预测');
    legend(legendStr, 'Location', 'best');
    grid on; set(gca, 'GridAlpha', 0.3);
    exportgraphics(fig, fullfile(cfg.outputDir, '图12_LSTM三情景预测对比.png'), 'Resolution', 300);
    fprintf('三情景预测图已保存\n');
end

%% ==================== 达峰热力图 ====================
function plot_peak_heatmap(peakData, cfg)
    scNames = {'基准情景','低碳转型情景','强化减排情景'};
    cities = cfg.cities;
    nC = length(cities);
    peakMat = NaN(nC, 3);
    for s = 1:3
        sRows = peakData(strcmp(peakData.scenario, scNames{s}), :);
        for i = 1:nC
            cRow = sRows(strcmp(sRows.city, cities{i}), :);
            if ~isempty(cRow)
                peakMat(i, s) = cRow.peak_year(1);
            end
        end
    end
    fig = figure('Position', [50 50 1200 600], 'Color', 'w');
    imagesc(peakMat);
    colormap(flipud(autumn(256)));
    cb = colorbar; cb.Label.String = '达峰年份';
    set(gca, 'YTick', 1:nC, 'YTickLabel', cities, 'FontSize', 7);
    set(gca, 'XTick', 1:3, 'XTickLabel', scNames);
    title('各城市碳达峰年份（LSTM三情景对比）');
    exportgraphics(fig, fullfile(cfg.outputDir, '图13_LSTM城市达峰热力图.png'), 'Resolution', 300);
    fprintf('达峰热力图已保存\n');
end

%% ==================== 达峰分布 ====================
function plot_peak_dist(peakData, cfg)
    scNames = {'基准情景','低碳转型情景','强化减排情景'};
    colors = {[0.2 0.4 0.8],[0.2 0.7 0.3],[0.9 0.3 0.1]};
    fig = figure('Position', [100 100 900 400], 'Color', 'w');
    for s = 1:3
        subplot(1, 3, s);
        sRows = peakData(strcmp(peakData.scenario, scNames{s}), :);
        histogram(sRows.peak_year, 2002:2:2042, 'FaceColor', colors{s}, 'FaceAlpha', 0.7);
        xlabel('达峰年份'); ylabel('城市数');
        title(scNames{s}); xlim([2000 2042]);
    end
    sgtitle('LSTM碳达峰年份分布', 'FontSize', 13, 'FontWeight', 'bold');
    exportgraphics(fig, fullfile(cfg.outputDir, '图14_LSTM达峰年份分布.png'), 'Resolution', 300);
    fprintf('达峰分布图已保存\n');
end

%% ==================== MAPE分布 ====================
function plot_mape(metrics, cfg)
    fig = figure('Position', [100 100 600 400], 'Color', 'w');
    histogram(metrics.mape, 0:2:max(metrics.mape)+2, 'FaceColor', [0.3 0.5 0.8], 'FaceAlpha', 0.7);
    xlabel('MAPE (%)'); ylabel('城市数');
    meanM = mean(metrics.mape);
    title(sprintf('LSTM预测精度分布 (均值MAPE=%.1f%%)', meanM));
    grid on; set(gca, 'GridAlpha', 0.3);
    exportgraphics(fig, fullfile(cfg.outputDir, '图15_LSTM精度分布.png'), 'Resolution', 300);
    fprintf('MAPE分布图已保存\n');
end
