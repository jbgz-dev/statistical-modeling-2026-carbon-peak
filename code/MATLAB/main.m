%% 长三角地级市碳排放时空演化特征、影响因素分析及碳达峰预测
%  主入口脚本 —— 依次运行三个模块
%  运行前请确保：
%    1. 所有Excel数据文件在当前目录下
%    2. 已安装 Deep Learning Toolbox（模块三LSTM需要）
%    3. MATLAB版本 >= R2019b

clear; clc; close all;
fprintf('============================================\n');
fprintf(' 长三角地级市碳排放研究 - 全流程运行\n');
fprintf(' 时间: %s\n', datestr(now));
fprintf('============================================\n\n');

%% Step 0: 数据加载与预处理
fprintf('>>> Step 0: 数据加载\n');
data = load_data();

%% Step 1: 模块一 - 时空演化特征分析
fprintf('\n>>> Step 1: 模块一\n');
Module1_Spatiotemporal();

%% Step 2: 模块二 - 影响因素面板回归
fprintf('\n>>> Step 2: 模块二\n');
Module2_PanelRegression();

%% Step 3: 模块三 - LSTM碳达峰预测
fprintf('\n>>> Step 3: 模块三\n');
Module3_LSTM_Prediction();

fprintf('\n============================================\n');
fprintf(' 全部模块运行完成！\n');
fprintf(' 结果保存在: %s\n', fullfile(pwd, 'results'));
fprintf('============================================\n');
