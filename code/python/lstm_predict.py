import os, sys
import numpy as np
import pandas as pd
import torch
import torch.nn as nn
from torch.utils.data import DataLoader, TensorDataset
import scipy.io as sio

WORK_DIR = os.path.dirname(os.path.abspath(__file__))
RESULT_DIR = os.path.join(WORK_DIR, 'results')
WINDOW = 4
HIDDEN = 32
LAYERS = 1
EPOCHS = 500
BATCH = 32
LR = 0.005
FEAT_NAMES = ['co2','pgdp','indus','pop','elec']
N_FEAT = len(FEAT_NAMES)

class CarbonLSTM(nn.Module):
    def __init__(self, n_feat, hidden, n_layers):
        super().__init__()
        self.lstm = nn.LSTM(n_feat, hidden, n_layers, batch_first=True)
        self.fc = nn.Linear(hidden, 1)
    def forward(self, x):
        out, _ = self.lstm(x)
        return self.fc(out[:, -1, :]).squeeze(-1)

def load_data():
    mat = sio.loadmat(os.path.join(RESULT_DIR, 'panel_data.mat'))
    d = mat['data'][0, 0]
    co2 = d['CO2'].astype(np.float64)
    pgdp = d['pgdp'].astype(np.float64)
    indus = d['indus'].astype(np.float64)
    pop = d['pop'].astype(np.float64)
    elec = d['elec'].astype(np.float64)
    years = d['years'].flatten().astype(int)
    cities = [str(c[0]) for c in d['cities'].flatten()]
    features = np.stack([co2, pgdp, indus, pop, elec], axis=-1)
    return features, years, cities

def fill_nan(features):
    nC, nY, nF = features.shape
    filled = features.copy()
    for i in range(nC):
        for f in range(nF):
            s = pd.Series(filled[i, :, f])
            s = s.interpolate(method='linear', limit_direction='both')
            filled[i, :, f] = s.values
    for f in range(nF):
        col = filled[:, :, f]
        gm = np.nanmean(col)
        col[np.isnan(col)] = gm
        filled[:, :, f] = col
    return filled

def normalize(features_filled, years):
    nC, nY, nF = features_filled.shape
    train_mask = years <= 2019
    train_data = features_filled[:, train_mask, :].reshape(-1, nF)
    fmin = train_data.min(axis=0)
    fmax = train_data.max(axis=0)
    frange = fmax - fmin
    frange[frange == 0] = 1.0
    features_norm = (features_filled - fmin) / frange
    return features_norm, fmin, frange

def create_windows(features_norm, years):
    nC, nY, nF = features_norm.shape
    Xtr, ytr, Xv, yv, vinfo = [], [], [], [], []
    for i in range(nC):
        for t in range(WINDOW, nY):
            x_seq = features_norm[i, t-WINDOW:t, :]
            y_co2 = features_norm[i, t, 0]
            if np.any(np.isnan(x_seq)) or np.isnan(y_co2):
                continue
            if years[t] <= 2019:
                Xtr.append(x_seq); ytr.append(y_co2)
            else:
                Xv.append(x_seq); yv.append(y_co2)
                vinfo.append((i, int(years[t])))
    return (np.array(Xtr, dtype=np.float32), np.array(ytr, dtype=np.float32),
            np.array(Xv, dtype=np.float32), np.array(yv, dtype=np.float32), vinfo)

def train_model(X_train, y_train, X_val, y_val):
    model = CarbonLSTM(N_FEAT, HIDDEN, LAYERS)
    optimizer = torch.optim.Adam(model.parameters(), lr=LR, weight_decay=1e-4)
    criterion = nn.MSELoss()
    train_ds = TensorDataset(torch.tensor(X_train), torch.tensor(y_train))
    loader = DataLoader(train_ds, batch_size=BATCH, shuffle=True)
    Xv_t = torch.tensor(X_val)
    yv_t = torch.tensor(y_val)
    loss_hist = []
    best_vl = float('inf')
    best_st = None
    wait = 0
    for ep in range(EPOCHS):
        model.train()
        ep_loss, nb = 0, 0
        for xb, yb in loader:
            pred = model(xb)
            loss = criterion(pred, yb)
            optimizer.zero_grad(); loss.backward(); optimizer.step()
            ep_loss += loss.item(); nb += 1
        tl = ep_loss / max(nb, 1)
        model.eval()
        with torch.no_grad():
            vl = criterion(model(Xv_t), yv_t).item()
        loss_hist.append((ep+1, tl, vl))
        if vl < best_vl:
            best_vl = vl
            best_st = {k: v.clone() for k, v in model.state_dict().items()}
            wait = 0
        else:
            wait += 1
            if wait >= 30:
                print(f'  Early stop at epoch {ep+1}')
                break
        if (ep+1) % 50 == 0:
            print(f'  Epoch {ep+1}: train={tl:.6f} val={vl:.6f}')
    model.load_state_dict(best_st)
    return model, loss_hist

def validate(model, X_val, y_val, vinfo, fmin, frange, cities):
    model.eval()
    with torch.no_grad():
        pn = model(torch.tensor(X_val)).numpy()
    actual = y_val * frange[0] + fmin[0]
    predicted = pn * frange[0] + fmin[0]
    # Global R²
    g_ss_r = np.sum((actual - predicted)**2)
    g_ss_t = np.sum((actual - np.mean(actual))**2)
    global_r2 = 1 - g_ss_r / max(g_ss_t, 1e-10)
    global_mape = np.mean(np.abs((actual - predicted) / np.maximum(np.abs(actual), 1e-6))) * 100
    global_rmse = np.sqrt(np.mean((actual - predicted)**2))
    # Per-city metrics
    city_data = {}
    for idx, ((ci, yr), a, p) in enumerate(zip(vinfo, actual, predicted)):
        if ci not in city_data:
            city_data[ci] = {'a': [], 'p': []}
        city_data[ci]['a'].append(a); city_data[ci]['p'].append(p)
    metrics = []
    for ci, v in city_data.items():
        a, p = np.array(v['a']), np.array(v['p'])
        mape = np.mean(np.abs((a - p) / np.maximum(np.abs(a), 1e-6))) * 100
        rmse = np.sqrt(np.mean((a - p)**2))
        metrics.append({'city_idx': ci, 'city': cities[ci], 'mape': mape, 'rmse': rmse, 'r2': global_r2})
    detail = [{'city_idx': ci, 'city': cities[ci], 'year': yr, 'actual': float(a), 'predicted': float(p)}
              for (ci, yr), a, p in zip(vinfo, actual, predicted)]
    return metrics, detail, global_mape, global_r2, global_rmse

def predict_scenarios(model, feat_norm, feat_filled, years, cities, fmin, frange):
    nC, nY, nF = feat_filled.shape
    scenarios = [
        ('基准情景',     {'pgdp_g': 0.05, 'indus_c': -0.3, 'pop_g': 0.002, 'elec_g': 0.03}),
        ('低碳转型情景', {'pgdp_g': 0.04, 'indus_c': -0.6, 'pop_g': 0.001, 'elec_g': 0.015}),
        ('强化减排情景', {'pgdp_g': 0.03, 'indus_c': -1.0, 'pop_g': 0.0,   'elec_g': 0.005}),
    ]
    pred_years = list(range(2023, 2041))
    all_preds = []
    model.eval()
    for sc_name, sp in scenarios:
        for i in range(nC):
            win_raw = feat_filled[i, -WINDOW:, :].copy()
            city_preds = []
            for yr in pred_years:
                win_norm = ((win_raw - fmin) / frange).astype(np.float32)
                with torch.no_grad():
                    co2_n = model(torch.tensor(win_norm).unsqueeze(0)).item()
                co2_val = max(co2_n * frange[0] + fmin[0], 0)
                city_preds.append(co2_val)
                last = win_raw[-1].copy()
                nf = np.array([co2_val,
                               last[1]*(1+sp['pgdp_g']),
                               last[2]+sp['indus_c'],
                               last[3]*(1+sp['pop_g']),
                               last[4]*(1+sp['elec_g'])])
                win_raw = np.vstack([win_raw[1:], nf.reshape(1,-1)])
            for yr, co2 in zip(pred_years, city_preds):
                all_preds.append({'city_idx': i, 'city': cities[i],
                                  'year': yr, 'scenario': sc_name, 'co2': co2})
    return all_preds, pred_years

def analyze_peaks(all_preds, feat_filled, years, cities, pred_years):
    nC = len(cities)
    hist_co2 = feat_filled[:, :, 0]
    pdf = pd.DataFrame(all_preds)
    peaks = []
    for sc in pdf['scenario'].unique():
        sdf = pdf[pdf['scenario'] == sc]
        for i in range(nC):
            h = hist_co2[i, :]
            vm = ~np.isnan(h)
            p = sdf[sdf['city_idx'] == i]['co2'].values
            ac = np.concatenate([h[vm], p])
            ay = np.concatenate([years[vm], np.array(pred_years)])
            if len(ac) == 0: continue
            pi = np.argmax(ac)
            peaks.append({'city_idx': i, 'city': cities[i], 'scenario': sc,
                          'peak_year': int(ay[pi]), 'peak_value': float(ac[pi])})
    return peaks

def main():
    print('='*50)
    print('LSTM Carbon Emission Prediction')
    print('='*50)
    print('\n[1] Loading data...')
    features, years, cities = load_data()
    print(f'    {len(cities)} cities, {len(years)} years')
    print('[2] Filling NaN...')
    feat_filled = fill_nan(features)
    print('[3] Normalizing...')
    feat_norm, fmin, frange = normalize(feat_filled, years)
    print('[4] Creating windows...')
    Xtr, ytr, Xv, yv, vinfo = create_windows(feat_norm, years)
    print(f'    Train: {len(Xtr)}, Val: {len(Xv)}')
    print('[5] Training LSTM...')
    model, loss_hist = train_model(Xtr, ytr, Xv, yv)
    print('[6] Validating...')
    metrics, val_detail, g_mape, g_r2, g_rmse = validate(model, Xv, yv, vinfo, fmin, frange, cities)
    print(f'    Global MAPE: {g_mape:.2f}%, R2: {g_r2:.4f}, RMSE: {g_rmse:.4f}')
    print('[7] Scenario prediction (2023-2040)...')
    preds, pyears = predict_scenarios(model, feat_norm, feat_filled, years, cities, fmin, frange)
    print('[8] Peak analysis...')
    peaks = analyze_peaks(preds, feat_filled, years, cities, pyears)
    print('[9] Saving results...')
    pd.DataFrame(loss_hist, columns=['epoch','train_loss','val_loss']).to_csv(
        os.path.join(RESULT_DIR,'lstm_loss.csv'), index=False)
    pd.DataFrame(metrics).to_csv(os.path.join(RESULT_DIR,'lstm_metrics.csv'), index=False, encoding='utf-8-sig')
    pd.DataFrame(val_detail).to_csv(os.path.join(RESULT_DIR,'lstm_validation.csv'), index=False, encoding='utf-8-sig')
    pd.DataFrame(preds).to_csv(os.path.join(RESULT_DIR,'lstm_predictions.csv'), index=False, encoding='utf-8-sig')
    pd.DataFrame(peaks).to_csv(os.path.join(RESULT_DIR,'lstm_peak.csv'), index=False, encoding='utf-8-sig')
    hist_rows = [{'city_idx': i, 'city': cities[i], 'year': int(years[j]), 'co2': float(feat_filled[i,j,0])}
                 for i in range(len(cities)) for j in range(len(years))]
    pd.DataFrame(hist_rows).to_csv(os.path.join(RESULT_DIR,'lstm_hist_co2.csv'), index=False, encoding='utf-8-sig')
    print(f'\nDone! MAPE={g_mape:.2f}%, R2={g_r2:.4f}')

if __name__ == '__main__':
    main()
