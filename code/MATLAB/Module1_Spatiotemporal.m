function Module1_Spatiotemporal()
% 模块一：长三角地级市碳排放时空演化特征分析
% 包含：趋势分析、空间可视化、Moran's I、描述性统计

    clc; close all;
    fprintf('===== 模块一：时空演化特征分析 =====\n');

    % 加载数据
    cfg = config();
    if isfile(fullfile(cfg.outputDir, 'panel_data.mat'))
        load(fullfile(cfg.outputDir, 'panel_data.mat'), 'data');
    else
        data = load_data();
    end

    set(0, 'DefaultAxesFontName', 'SimHei');
    set(0, 'DefaultTextFontName', 'SimHei');
    set(0, 'DefaultAxesFontSize', 11);

    %% 1. 描述性统计
    fprintf('\n--- 1. 描述性统计 ---\n');
    descriptive_stats(data, cfg);

    %% 2. 时序趋势分析
    fprintf('\n--- 2. 时序趋势分析 ---\n');
    trend_analysis(data, cfg);

    %% 3. 空间分布可视化
    fprintf('\n--- 3. 空间分布可视化 ---\n');
    spatial_distribution(data, cfg);

    %% 4. Moran's I 空间自相关
    fprintf('\n--- 4. 空间自相关分析 ---\n');
    spatial_autocorrelation(data, cfg);

    fprintf('\n===== 模块一完成，图表已保存至 results/ =====\n');
end

%% ==================== 描述性统计 ====================
function descriptive_stats(data, cfg)
    CO2 = data.CO2;
    years = data.years;
    cities = data.cities;
    nY = length(years);

    % 各年份截面统计
    avgVal = nanmean(CO2, 1)';
    stdVal = nanstd(CO2, 0, 1)';
    T = table(years(:), avgVal, stdVal, nanmin(CO2,[],1)', nanmax(CO2,[],1)', ...
        stdVal./avgVal, nansum(CO2,1)', ...
        'VariableNames', {'Year','Mean','Std','Min','Max','CV','Total'});
    disp(T);
    writetable(T, fullfile(cfg.outputDir, 'stats_yearly.csv'));

    % 各城市时序统计
    T2 = table(cities, nanmean(CO2,2), nanstd(CO2,0,2), nanmin(CO2,[],2), ...
        nanmax(CO2,[],2), (CO2(:,end)-CO2(:,1))./CO2(:,1)*100, ...
        'VariableNames', {'City','Mean','Std','Min','Max','GrowthRate'});
    writetable(T2, fullfile(cfg.outputDir, 'stats_city.csv'));
    fprintf('描述性统计表已保存\n');
end

%% ==================== 时序趋势分析 ====================
function trend_analysis(data, cfg)
    CO2 = data.CO2;
    years = data.years;
    cities = data.cities;
    province = cfg.province;

    % 图1：长三角总量与均值趋势
    fig1 = figure('Position', [100 100 900 400], 'Color', 'w');
    yyaxis left
    plot(years, nansum(CO2,1), '-o', 'LineWidth', 2, 'MarkerSize', 5, 'Color', [0.2 0.4 0.8]);
    ylabel('碳排放总量');
    yyaxis right
    plot(years, nanmean(CO2,1), '-s', 'LineWidth', 2, 'MarkerSize', 5, 'Color', [0.9 0.3 0.2]);
    ylabel('城市均值');
    xlabel('年份'); title('长三角地区碳排放总量与均值趋势（2003-2022）');
    legend('区域总量', '城市均值', 'Location', 'northwest');
    grid on; set(gca, 'GridAlpha', 0.3);
    exportgraphics(fig1, fullfile(cfg.outputDir, '图1_总量均值趋势.png'), 'Resolution', 300);

    % 图2：分省份趋势对比
    provList = {'上海','江苏','浙江','安徽'};
    colors = [0.9 0.2 0.2; 0.2 0.6 0.2; 0.2 0.4 0.9; 0.9 0.6 0.1];
    fig2 = figure('Position', [100 100 900 400], 'Color', 'w');
    hold on;
    for p = 1:4
        mask = strcmp(province, provList{p});
        provTotal = nansum(CO2(mask,:), 1);
        plot(years, provTotal, '-o', 'LineWidth', 2, 'MarkerSize', 4, 'Color', colors(p,:));
    end
    hold off;
    xlabel('年份'); ylabel('碳排放量');
    title('长三角各省份碳排放趋势对比');
    legend(provList, 'Location', 'northwest');
    grid on; set(gca, 'GridAlpha', 0.3);
    exportgraphics(fig2, fullfile(cfg.outputDir, '图2_分省趋势.png'), 'Resolution', 300);

    % 图3：Top10城市趋势
    avgCO2 = nanmean(CO2, 2);
    [~, sortIdx] = sort(avgCO2, 'descend');
    top10 = sortIdx(1:10);
    fig3 = figure('Position', [100 100 1000 500], 'Color', 'w');
    cmap = lines(10);
    hold on;
    for k = 1:10
        plot(years, CO2(top10(k),:), '-', 'LineWidth', 1.8, 'Color', cmap(k,:));
    end
    hold off;
    xlabel('年份'); ylabel('碳排放量');
    title('碳排放Top10城市趋势');
    legend(cities(top10), 'Location', 'eastoutside', 'FontSize', 9);
    grid on; set(gca, 'GridAlpha', 0.3);
    exportgraphics(fig3, fullfile(cfg.outputDir, '图3_Top10城市趋势.png'), 'Resolution', 300);

    fprintf('趋势分析图已保存\n');
end

%% ==================== 空间分布可视化 ====================
function spatial_distribution(data, cfg)
    CO2 = data.CO2;
    years = data.years;
    lon = cfg.lon; lat = cfg.lat;

    keyYears = [2003, 2010, 2015, 2022];
    fig4 = figure('Position', [50 50 1200 900], 'Color', 'w');

    for k = 1:4
        yr = keyYears(k);
        j = find(years == yr);
        if isempty(j), continue; end
        vals = CO2(:, j);

        subplot(2, 2, k);
        hold on;

        % 气泡大小映射
        maxVal = nanmax(vals);
        sz = max(vals / maxVal * 300, 10);
        sz(isnan(sz)) = 10;

        % 颜色映射
        cvals = vals;
        cvals(isnan(cvals)) = 0;

        scatter(lon, lat, sz, cvals, 'filled', 'MarkerEdgeColor', [0.3 0.3 0.3], ...
            'MarkerEdgeAlpha', 0.5, 'MarkerFaceAlpha', 0.75);
        colormap(gca, hot(256));
        cb = colorbar;
        cb.Label.String = '碳排放量';
        caxis([0 max(nanmax(CO2(:)), 1)]);

        % 标注Top5城市名
        [~, topIdx] = sort(vals, 'descend');
        topIdx = topIdx(1:min(5, length(topIdx)));
        for m = 1:length(topIdx)
            ci = topIdx(m);
            text(lon(ci)+0.15, lat(ci), cfg.cities{ci}, 'FontSize', 8);
        end

        xlabel('经度'); ylabel('纬度');
        title(sprintf('%d年碳排放空间分布', yr));
        grid on; set(gca, 'GridAlpha', 0.2);
        hold off;
    end
    sgtitle('长三角地级市碳排放空间分布演化', 'FontSize', 14, 'FontWeight', 'bold');
    exportgraphics(fig4, fullfile(cfg.outputDir, '图4_空间分布演化.png'), 'Resolution', 300);
    fprintf('空间分布图已保存\n');
end

%% ==================== Moran's I 空间自相关 ====================
function spatial_autocorrelation(data, cfg)
    CO2 = data.CO2;
    years = data.years;
    lon = cfg.lon; lat = cfg.lat;
    nC = cfg.nCity;

    % 构建空间权重矩阵（K近邻, K=5）
    K = 5;
    D = pdist2([lon lat], [lon lat]);
    W = zeros(nC);
    for i = 1:nC
        [~, idx] = sort(D(i,:));
        W(i, idx(2:K+1)) = 1;
    end
    % 行标准化
    W = W ./ sum(W, 2);

    % 全局Moran's I（逐年计算）
    nY = length(years);
    moranI = NaN(nY, 1);
    moranP = NaN(nY, 1);
    moranZ = NaN(nY, 1);
    nPerm = 999;

    for j = 1:nY
        x = CO2(:, j);
        if sum(~isnan(x)) < nC * 0.8, continue; end
        x(isnan(x)) = nanmean(x);
        [moranI(j), moranZ(j), moranP(j)] = global_moran(x, W, nPerm);
    end

    % 图5：全局Moran's I时序变化
    fig5 = figure('Position', [100 100 900 400], 'Color', 'w');
    yyaxis left
    plot(years, moranI, '-o', 'LineWidth', 2, 'MarkerSize', 6, 'Color', [0.2 0.4 0.8]);
    ylabel("Moran's I");
    yyaxis right
    plot(years, moranP, '--s', 'LineWidth', 1.5, 'MarkerSize', 5, 'Color', [0.8 0.2 0.2]);
    ylabel('P值');
    yline(0.05, ':', 'p=0.05', 'Color', [0.5 0.5 0.5]);
    xlabel('年份');
    title("全局Moran's I指数时序变化");
    legend("Moran's I", 'P值', 'Location', 'best');
    grid on; set(gca, 'GridAlpha', 0.3);
    exportgraphics(fig5, fullfile(cfg.outputDir, '图5_全局MoranI.png'), 'Resolution', 300);

    % 输出Moran's I结果表
    Tmoran = table(years(:), moranI, moranZ, moranP, ...
        'VariableNames', {'Year','MoranI','Z','P'});
    disp(Tmoran);
    writetable(Tmoran, fullfile(cfg.outputDir, 'MoranI_全局.csv'));

    % 局部Moran's I (LISA) —— 选取末期年份
    endYear = years(end);
    j = find(years == endYear);
    x = CO2(:, j);
    x(isnan(x)) = nanmean(x);
    [lisa, lisaCluster] = local_moran(x, W, nPerm);

    % 图6：LISA聚类图
    fig6 = figure('Position', [100 100 800 600], 'Color', 'w');
    hold on;
    clusterNames = {'不显著','HH(高-高)','LL(低-低)','HL(高-低)','LH(低-高)'};
    clusterColors = [0.8 0.8 0.8; 1 0 0; 0 0 1; 1 0.6 0.6; 0.6 0.6 1];
    for c = 0:4
        mask = (lisaCluster == c);
        if any(mask)
            scatter(lon(mask), lat(mask), 120, clusterColors(c+1,:), 'filled', ...
                'MarkerEdgeColor', 'k', 'LineWidth', 0.5);
        end
    end
    % 标注城市名
    for i = 1:nC
        if lisaCluster(i) > 0
            text(lon(i)+0.12, lat(i), cfg.cities{i}, 'FontSize', 8);
        end
    end
    hold off;
    legend(clusterNames(unique(lisaCluster)+1), 'Location', 'bestoutside');
    xlabel('经度'); ylabel('纬度');
    title(sprintf('%d年LISA聚类图', endYear));
    grid on; set(gca, 'GridAlpha', 0.2);
    exportgraphics(fig6, fullfile(cfg.outputDir, '图6_LISA聚类图.png'), 'Resolution', 300);

    % Moran散点图
    fig7 = figure('Position', [100 100 600 500], 'Color', 'w');
    xz = (x - mean(x)) / std(x);
    Wxz = W * xz;
    scatter(xz, Wxz, 60, 'filled', 'MarkerFaceAlpha', 0.6);
    hold on;
    lsline;
    xline(0, '--', 'Color', [0.5 0.5 0.5]);
    yline(0, '--', 'Color', [0.5 0.5 0.5]);
    hold off;
    xlabel('标准化碳排放'); ylabel('空间滞后');
    title(sprintf('%d年Moran散点图 (I=%.4f)', endYear, moranI(end)));
    text(0.05, 0.95, 'HH', 'Units', 'normalized', 'FontSize', 12, 'Color', 'r');
    text(0.05, 0.05, 'LH', 'Units', 'normalized', 'FontSize', 12, 'Color', [0.4 0.4 1]);
    text(0.85, 0.95, 'HL', 'Units', 'normalized', 'FontSize', 12, 'Color', [1 0.4 0.4]);
    text(0.85, 0.05, 'LL', 'Units', 'normalized', 'FontSize', 12, 'Color', 'b');
    exportgraphics(fig7, fullfile(cfg.outputDir, '图7_Moran散点图.png'), 'Resolution', 300);

    fprintf('空间自相关分析完成\n');
end

%% ==================== 全局Moran's I计算 ====================
function [I, Z, p] = global_moran(x, W, nPerm)
    n = length(x);
    xd = x - mean(x);
    S0 = sum(W(:));
    num = n * (xd' * W * xd);
    den = S0 * (xd' * xd);
    I = num / den;

    % 置换检验
    I_perm = zeros(nPerm, 1);
    for k = 1:nPerm
        xp = x(randperm(n));
        xpd = xp - mean(xp);
        I_perm(k) = n * (xpd' * W * xpd) / (S0 * (xpd' * xpd));
    end
    Z = (I - mean(I_perm)) / std(I_perm);
    p = sum(abs(I_perm) >= abs(I)) / nPerm;
    p = max(p, 1/nPerm);
end

%% ==================== 局部Moran's I (LISA) ====================
function [lisa, cluster] = local_moran(x, W, nPerm)
    n = length(x);
    xd = x - mean(x);
    s2 = sum(xd.^2) / n;
    zi = xd / sqrt(s2);
    Wz = W * zi;
    lisa = zi .* Wz;

    % 置换检验确定显著性
    lisa_p = ones(n, 1);
    for i = 1:n
        perm_vals = zeros(nPerm, 1);
        for k = 1:nPerm
            idx = randperm(n);
            idx(idx == i) = [];
            xp = x(idx(1:n-1));
            xpd = xp - mean(x);
            Wi = W(i, :);
            Wi(i) = 0;
            Wi_other = Wi; Wi_other(i) = [];
            % 简化：对整体置换
            xp_full = x(randperm(n));
            xpd_full = (xp_full - mean(x)) / sqrt(s2);
            perm_vals(k) = zi(i) * (W(i,:) * xpd_full);
        end
        lisa_p(i) = sum(abs(perm_vals) >= abs(lisa(i))) / nPerm;
    end

    % 聚类分类
    cluster = zeros(n, 1); % 0=不显著
    sig = lisa_p < 0.05;
    for i = 1:n
        if ~sig(i), continue; end
        if zi(i) > 0 && Wz(i) > 0
            cluster(i) = 1; % HH
        elseif zi(i) < 0 && Wz(i) < 0
            cluster(i) = 2; % LL
        elseif zi(i) > 0 && Wz(i) < 0
            cluster(i) = 3; % HL
        else
            cluster(i) = 4; % LH
        end
    end
end
