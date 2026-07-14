function Module2_PanelRegression()
% 模块二：长三角地级市碳排放影响因素分析
% 面板回归：固定效应、随机效应、Hausman检验、VIF、EKC验证、稳健性检验

    clc; close all;
    fprintf('===== 模块二：影响因素面板回归分析 =====\n');

    cfg = config();
    if isfile(fullfile(cfg.outputDir, 'panel_data.mat'))
        load(fullfile(cfg.outputDir, 'panel_data.mat'), 'data');
    else
        data = load_data();
    end

    set(0, 'DefaultAxesFontName', 'SimHei');
    set(0, 'DefaultTextFontName', 'SimHei');

    %% 1. 构建回归变量
    fprintf('\n--- 1. 构建回归变量 ---\n');
    [Y, X, varNames, validMask] = build_variables(data, cfg);

    %% 2. VIF多重共线性检验
    fprintf('\n--- 2. VIF检验 ---\n');
    vif = calc_vif(X);
    T_vif = table(varNames(:), vif(:), 'VariableNames', {'Variable','VIF'});
    disp(T_vif);
    writetable(T_vif, fullfile(cfg.outputDir, 'VIF检验.csv'));

    %% 3. 固定效应回归
    fprintf('\n--- 3. 固定效应回归 ---\n');
    [fe] = fixed_effects(Y, X, validMask, cfg.nCity, varNames);

    %% 4. 随机效应回归
    fprintf('\n--- 4. 随机效应回归 ---\n');
    [re] = random_effects(Y, X, validMask, cfg.nCity, varNames);

    %% 5. Hausman检验
    fprintf('\n--- 5. Hausman检验 ---\n');
    hausman_test(fe, re, varNames);

    %% 6. EKC验证
    fprintf('\n--- 6. EKC环境库兹涅茨曲线验证 ---\n');
    ekc_analysis(data, cfg, validMask);

    %% 7. 稳健性检验
    fprintf('\n--- 7. 稳健性检验 ---\n');
    robustness_check(Y, X, validMask, cfg, varNames);

    %% 8. 汇总回归结果
    export_results(fe, re, varNames, cfg);

    fprintf('\n===== 模块二完成 =====\n');
end

%% ==================== 构建回归变量 ====================
function [Y, X, varNames, validMask] = build_variables(data, cfg)
    nC = cfg.nCity;
    nY = cfg.nYear;
    N = nC * nY;

    % 展开为长面板 (N=nC*nY, 按城市堆叠)
    CO2_vec = reshape(data.CO2', [], 1);
    pgdp_vec = reshape(data.pgdp', [], 1);
    pop_vec = reshape(data.pop', [], 1);
    indus_vec = reshape(data.indus', [], 1);
    elec_vec = reshape(data.elec', [], 1);

    % 取对数（减少异方差）
    lnCO2 = log(CO2_vec);
    lnpgdp = log(pgdp_vec);
    lnpgdp2 = lnpgdp.^2;
    lnpop = log(pop_vec);
    lnelec = log(elec_vec);

    % 组装 Y 和 X (城市级变量: 人均GDP, GDP², 产业结构, 人口, 电力)
    Y = lnCO2;
    X = [lnpgdp, lnpgdp2, indus_vec, lnpop, lnelec];
    varNames = {'lnPGDP','lnPGDP²','产业结构','ln人口','ln电力'};

    % 有效观测（去除NaN和Inf）
    validMask = all(isfinite([Y, X]), 2);
    fprintf('有效观测: %d / %d (%.1f%%)\n', sum(validMask), N, 100*sum(validMask)/N);

    % 城市和时间索引
    cityIdx = repelem((1:nC)', nY, 1);
    yearIdx = repmat((1:nY)', nC, 1);

    assignin('caller', 'cityIdx', cityIdx);
    assignin('caller', 'yearIdx', yearIdx);
end

%% ==================== VIF计算 ====================
function vif = calc_vif(X)
    valid = all(isfinite(X), 2);
    Xv = X(valid, :);
    p = size(Xv, 2);
    vif = zeros(p, 1);
    for j = 1:p
        y_j = Xv(:, j);
        X_j = Xv(:, [1:j-1, j+1:p]);
        X_j = [ones(size(X_j,1),1), X_j];
        b = X_j \ y_j;
        yhat = X_j * b;
        SS_res = sum((y_j - yhat).^2);
        SS_tot = sum((y_j - mean(y_j)).^2);
        R2 = 1 - SS_res / SS_tot;
        vif(j) = 1 / (1 - R2);
    end
    fprintf('最大VIF: %.2f\n', max(vif));
    if max(vif) > 10
        fprintf('  警告：存在严重多重共线性(VIF>10)\n');
    end
end

%% ==================== 固定效应回归 ====================
function fe = fixed_effects(Y, X, validMask, nC, varNames)
    cfg = config();
    nY = cfg.nYear;
    cityIdx = repelem((1:nC)', nY, 1);

    Yv = Y(validMask);
    Xv = X(validMask, :);
    cIdx = cityIdx(validMask);
    [n, p] = size(Xv);

    % Within变换（组内去均值）
    Yd = Yv; Xd = Xv;
    uCities = unique(cIdx);
    for c = uCities'
        mask = (cIdx == c);
        Yd(mask) = Yv(mask) - mean(Yv(mask));
        Xd(mask,:) = Xv(mask,:) - mean(Xv(mask,:), 1);
    end

    % OLS on demeaned data
    b = Xd \ Yd;
    resid = Yd - Xd * b;
    df = n - length(uCities) - p;
    s2 = sum(resid.^2) / df;

    % 聚类稳健标准误（按城市聚类）
    XtX_inv = inv(Xd' * Xd);
    meat = zeros(p, p);
    for c = uCities'
        mask = (cIdx == c);
        Xi = Xd(mask, :);
        ei = resid(mask);
        meat = meat + (Xi' * ei) * (ei' * Xi);
    end
    G = length(uCities);
    correction = G / (G - 1) * (n - 1) / df;
    V_cluster = correction * XtX_inv * meat * XtX_inv;
    se = sqrt(diag(V_cluster));

    t_stat = b ./ se;
    p_val = 2 * (1 - tcdf(abs(t_stat), df));

    % R²
    SS_res = sum(resid.^2);
    SS_tot = sum((Yd - mean(Yd)).^2);
    R2_within = 1 - SS_res / SS_tot;

    % 输出
    fprintf('固定效应回归结果 (Within R² = %.4f)\n', R2_within);
    fprintf('%-12s %10s %10s %10s %10s\n', '变量', '系数', '稳健SE', 't值', 'p值');
    fprintf('%s\n', repmat('-', 1, 55));
    for k = 1:p
        sig = '';
        if p_val(k)<0.01, sig='***'; elseif p_val(k)<0.05, sig='**'; elseif p_val(k)<0.1, sig='*'; end
        fprintf('%-12s %10.4f %10.4f %10.2f %10.4f %s\n', varNames{k}, b(k), se(k), t_stat(k), p_val(k), sig);
    end
    fprintf('N=%d, 城市=%d, R²=%.4f\n', n, G, R2_within);

    fe.b = b; fe.se = se; fe.t = t_stat; fe.p = p_val;
    fe.R2 = R2_within; fe.s2 = s2; fe.resid = resid;
    fe.V = V_cluster; fe.df = df; fe.n = n;
end

%% ==================== 随机效应回归 ====================
function re = random_effects(Y, X, validMask, nC, varNames)
    cfg = config();
    nY = cfg.nYear;
    cityIdx = repelem((1:nC)', nY, 1);

    Yv = Y(validMask);
    Xv = [ones(sum(validMask),1), X(validMask,:)];
    cIdx = cityIdx(validMask);
    [n, p] = size(Xv);
    varNamesC = ['截距项', varNames];

    uCities = unique(cIdx);
    G = length(uCities);

    % 先做FE估计sigma_e²
    Yd = Yv; Xd = Xv;
    for c = uCities'
        mask = (cIdx == c);
        Yd(mask) = Yv(mask) - mean(Yv(mask));
        Xd(mask,:) = Xv(mask,:) - mean(Xv(mask,:),1);
    end
    b_fe = Xd \ Yd;
    e_fe = Yd - Xd * b_fe;
    sigma2_e = sum(e_fe.^2) / (n - G - p + 1);

    % Between估计sigma_u²
    Ybar = zeros(G,1); Xbar = zeros(G,p);
    Ti = zeros(G,1);
    for g = 1:G
        mask = (cIdx == uCities(g));
        Ti(g) = sum(mask);
        Ybar(g) = mean(Yv(mask));
        Xbar(g,:) = mean(Xv(mask,:),1);
    end
    b_be = Xbar \ Ybar;
    e_be = Ybar - Xbar * b_be;
    sigma2_b = max(sum(e_be.^2)/(G-p) - sigma2_e/mean(Ti), 0);

    % Quasi-demeaning
    theta = zeros(n,1);
    for g = 1:G
        mask = (cIdx == uCities(g));
        theta(mask) = 1 - sqrt(sigma2_e / (Ti(g)*sigma2_b + sigma2_e));
    end

    Yq = Yv - theta .* Ybar(arrayfun(@(c) find(uCities==c), cIdx));
    Xq = Xv - theta .* Xbar(arrayfun(@(c) find(uCities==c), cIdx), :);

    b = Xq \ Yq;
    resid = Yq - Xq * b;
    df = n - p;
    s2 = sum(resid.^2) / df;
    se = sqrt(diag(s2 * inv(Xq' * Xq)));
    t_stat = b ./ se;
    p_val = 2 * (1 - tcdf(abs(t_stat), df));

    R2 = 1 - sum(resid.^2) / sum((Yq - mean(Yq)).^2);

    fprintf('随机效应回归结果 (R² = %.4f)\n', R2);
    fprintf('%-12s %10s %10s %10s %10s\n', '变量', '系数', 'SE', 't值', 'p值');
    fprintf('%s\n', repmat('-', 1, 55));
    for k = 1:p
        sig = '';
        if p_val(k)<0.01, sig='***'; elseif p_val(k)<0.05, sig='**'; elseif p_val(k)<0.1, sig='*'; end
        fprintf('%-12s %10.4f %10.4f %10.2f %10.4f %s\n', varNamesC{k}, b(k), se(k), t_stat(k), p_val(k), sig);
    end

    re.b = b(2:end); re.se = se(2:end); re.t = t_stat(2:end); re.p = p_val(2:end);
    re.b0 = b(1); re.R2 = R2; re.V = inv(Xq'*Xq)*s2;
    re.V = re.V(2:end, 2:end);
end

%% ==================== Hausman检验 ====================
function hausman_test(fe, re, varNames)
    db = fe.b - re.b;
    dV = fe.V - re.V;
    % 确保dV正定
    [~, flag] = chol(dV);
    if flag > 0
        dV = dV + eye(size(dV)) * 1e-6;
    end
    H = db' * inv(dV) * db;
    K = length(db);
    p_val = 1 - chi2cdf(H, K);

    fprintf('Hausman检验: H=%.4f, df=%d, p=%.4f\n', H, K, p_val);
    if p_val < 0.05
        fprintf('  结论：拒绝H0，应使用固定效应模型\n');
    else
        fprintf('  结论：不拒绝H0，随机效应模型更有效\n');
    end
end

%% ==================== EKC验证 ====================
function ekc_analysis(data, cfg, validMask)
    nC = cfg.nCity; nY = cfg.nYear;
    cityIdx = repelem((1:nC)', nY, 1);

    CO2_vec = reshape(data.CO2', [], 1);
    pgdp_vec = reshape(data.pgdp', [], 1);

    lnCO2 = log(CO2_vec);
    lnpgdp = log(pgdp_vec);
    lnpgdp2 = lnpgdp.^2;
    lnpgdp3 = lnpgdp.^3;

    vm = validMask & isfinite(lnCO2) & isfinite(lnpgdp);
    Yv = lnCO2(vm);
    cIdx = cityIdx(vm);
    uC = unique(cIdx);

    % 固定效应下的EKC（二次项）
    X2 = [lnpgdp(vm), lnpgdp2(vm)];
    Yd = Yv; Xd = X2;
    for c = uC'
        m = (cIdx==c);
        Yd(m) = Yv(m) - mean(Yv(m));
        Xd(m,:) = X2(m,:) - mean(X2(m,:),1);
    end
    b2 = Xd \ Yd;
    e2 = Yd - Xd*b2;
    R2_2 = 1 - sum(e2.^2)/sum((Yd-mean(Yd)).^2);

    fprintf('EKC二次模型: lnCO2 = %.4f*lnPGDP + %.4f*lnPGDP²\n', b2(1), b2(2));
    fprintf('  R² = %.4f\n', R2_2);
    if b2(2) < 0 && b2(1) > 0
        tp = exp(-b2(1)/(2*b2(2)));
        fprintf('  倒U型成立，拐点人均GDP = %.0f\n', tp);
    else
        fprintf('  未呈现倒U型\n');
    end

    % 三次项检验（N型曲线）
    X3 = [lnpgdp(vm), lnpgdp2(vm), lnpgdp3(vm)];
    Xd3 = X3;
    for c = uC'
        m = (cIdx==c);
        Xd3(m,:) = X3(m,:) - mean(X3(m,:),1);
    end
    b3 = Xd3 \ Yd;
    e3 = Yd - Xd3*b3;
    R2_3 = 1 - sum(e3.^2)/sum((Yd-mean(Yd)).^2);
    fprintf('EKC三次模型: β1=%.4f, β2=%.4f, β3=%.4f, R²=%.4f\n', b3(1),b3(2),b3(3),R2_3);

    % EKC拟合曲线图
    fig = figure('Position', [100 100 700 500], 'Color', 'w');
    pgdp_range = linspace(min(lnpgdp(vm)), max(lnpgdp(vm)), 200);
    yfit2 = b2(1)*pgdp_range + b2(2)*pgdp_range.^2;
    yfit2 = yfit2 - mean(yfit2) + mean(Yd);

    scatter(lnpgdp(vm), Yv, 8, [0.6 0.6 0.6], 'filled', 'MarkerFaceAlpha', 0.3);
    hold on;
    plot(pgdp_range, yfit2, '-', 'LineWidth', 2.5, 'Color', [0.9 0.2 0.2]);
    hold off;
    xlabel('ln(人均GDP)'); ylabel('ln(碳排放)');
    title('环境库兹涅茨曲线(EKC)验证');
    legend('观测值', 'EKC拟合', 'Location', 'best');
    grid on; set(gca, 'GridAlpha', 0.3);
    exportgraphics(fig, fullfile(cfg.outputDir, '图8_EKC曲线.png'), 'Resolution', 300);
    fprintf('EKC分析完成\n');
end

%% ==================== 稳健性检验 ====================
function robustness_check(Y, X, validMask, cfg, varNames)
    nC = cfg.nCity; nY = cfg.nYear;
    cityIdx = repelem((1:nC)', nY, 1);

    Yv = Y(validMask);
    Xv = X(validMask,:);
    cIdx = cityIdx(validMask);
    uC = unique(cIdx);
    p = size(Xv, 2);

    fprintf('\n(1) 逐步回归稳健性检验\n');
    % 核心变量子集回归
    subsets = {1:3, 1:4, 1:p};
    subLabels = {'经济变量(3个)', '加人口(4个)', '全变量(5个)'};
    for s = 1:length(subsets)
        cols = subsets{s};
        Xs = Xv(:, cols);
        Yd = Yv; Xd = Xs;
        for c = uC'
            m = (cIdx==c);
            Yd(m) = Yv(m) - mean(Yv(m));
            Xd(m,:) = Xs(m,:) - mean(Xs(m,:),1);
        end
        b = Xd \ Yd;
        e = Yd - Xd*b;
        R2 = 1 - sum(e.^2)/sum((Yd-mean(Yd)).^2);
        fprintf('  %s: R²=%.4f, 系数=[', subLabels{s}, R2);
        fprintf('%.4f ', b);
        fprintf(']\n');
    end

    fprintf('\n(2) 分省份子样本回归\n');
    province = cfg.province;
    provIdx = repelem((1:nC)', nY, 1);
    provNames_all = repelem(province, nY, 1);
    provList = {'江苏','浙江','安徽'};
    for pi = 1:3
        pMask = validMask & strcmp(provNames_all, provList{pi});
        if sum(pMask) < p+2, continue; end
        Ys = Y(pMask); Xs = X(pMask,:);
        cIdxS = cityIdx(pMask);
        uCs = unique(cIdxS);
        Yd = Ys; Xd = Xs;
        for c = uCs'
            m = (cIdxS==c);
            Yd(m) = Ys(m) - mean(Ys(m));
            Xd(m,:) = Xs(m,:) - mean(Xs(m,:),1);
        end
        b = Xd \ Yd;
        e = Yd - Xd*b;
        R2 = 1 - sum(e.^2)/sum((Yd-mean(Yd)).^2);
        fprintf('  %s (N=%d): R²=%.4f\n', provList{pi}, sum(pMask), R2);
        fprintf('    系数: ');
        for k = 1:p
            fprintf('%s=%.3f ', varNames{k}, b(k));
        end
        fprintf('\n');
    end

    fprintf('\n(3) 缩尾处理稳健性检验（1%%/99%%）\n');
    Xw = Xv;
    for j = 1:p
        lo = prctile(Xv(:,j), 1);
        hi = prctile(Xv(:,j), 99);
        Xw(:,j) = max(min(Xv(:,j), hi), lo);
    end
    Yd = Yv; Xd = Xw;
    for c = uC'
        m = (cIdx==c);
        Yd(m) = Yv(m) - mean(Yv(m));
        Xd(m,:) = Xw(m,:) - mean(Xw(m,:),1);
    end
    b = Xd \ Yd;
    e = Yd - Xd*b;
    R2 = 1 - sum(e.^2)/sum((Yd-mean(Yd)).^2);
    fprintf('  缩尾后R²=%.4f\n', R2);
    fprintf('稳健性检验完成\n');
end

%% ==================== 导出回归结果 ====================
function export_results(fe, re, varNames, cfg)
    p = length(varNames);
    T = table();
    T.Variable = varNames(:);
    T.FE_coef = fe.b;
    T.FE_se = fe.se;
    T.FE_t = fe.t;
    T.FE_p = fe.p;
    T.RE_coef = re.b;
    T.RE_se = re.se;
    T.RE_t = re.t;
    T.RE_p = re.p;

    disp(T);
    writetable(T, fullfile(cfg.outputDir, '回归结果汇总.csv'));

    % 系数对比图
    fig = figure('Position', [100 100 900 500], 'Color', 'w');
    x = 1:p;
    bar(x, [fe.b, re.b], 'grouped');
    hold on;
    errorbar(x-0.15, fe.b, 1.96*fe.se, 'k.', 'LineWidth', 1);
    errorbar(x+0.15, re.b, 1.96*re.se, 'k.', 'LineWidth', 1);
    hold off;
    set(gca, 'XTick', x, 'XTickLabel', varNames, 'XTickLabelRotation', 30);
    ylabel('回归系数');
    title('固定效应 vs 随机效应回归系数对比');
    legend('固定效应', '随机效应', 'Location', 'best');
    grid on; set(gca, 'GridAlpha', 0.3);
    exportgraphics(fig, fullfile(cfg.outputDir, '图9_回归系数对比.png'), 'Resolution', 300);
    fprintf('回归结果已导出\n');
end
