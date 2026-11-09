# =====================================================================
# CALL FORECAST - next 26 weeks (weekly + monthly) and next 90 days (every 15 minutes)
# English and Spanish separately.
#
# What this does, in plain words:
#   PART 1  Loads the call data and the customer counts.
#   PART 2  TEST: pretends to be 30 past Mondays, forecasts 26 weeks ahead each time,
#           and scores the result against what really happened. It does this twice -
#           with and without customer counts - so you can see if the counts help.
#   PART 3  FORECAST: forecasts from today, writes the files Lou's team / the report need.
#
# Weeks run Saturday to Friday (same as Lou's team). Sundays are closed.
# Accuracy = 100 - (miss / real calls) x 100, same as before.
#
# Run it on Mondays, after you refresh the call data:   py call_forecast_26weeks.py
# Files needed in this folder:
#     eng_spa_15min_2year_combined.csv      (the call data, refreshed)
#     F27_210_MM_Counts.xlsx                (customer counts, monthly, with their forecast)
# =====================================================================
from pathlib import Path
import json
import os
import numpy as np
import pandas as pd
from pandas.tseries.holiday import USFederalHolidayCalendar
from sklearn.ensemble import HistGradientBoostingRegressor

# ---------------------------------------------------------------------
# SETTINGS - the only part you normally touch
# ---------------------------------------------------------------------
FOLDER = Path(__file__).resolve().parent
CALLS_FILE = FOLDER / "eng_spa_15min_2year_combined.csv"
COUNTS_FILE = FOLDER / "F27_210_MM_Counts.xlsx"

COUNT_JURISDICTION = "Texas"       # which customers the calls come from
COUNT_TYPE = "Residential"         # Residential or Commercial
COUNT_UNIT = "Customer Count"      # Customer Count, RCE or Contract Counts  (ask Lou which one he plans from)

WEEKS_AHEAD = 26                   # weekly forecast length
INTERVAL_DAYS = 90                 # 15-minute forecast length
USE_CUSTOMER_COUNTS = False        # the test showed the counts did not improve the forecast (see PART 2); set True to use them
RUN_TEST = os.environ.get("RUN_TEST", "1") == "1"   # False = skip the few-minute test and reuse the saved ranges (the weekly runner does this)
N_TEST_MONDAYS = 30                # how many pretend-Mondays in the test
TEST_EVERY_N_WEEKS = 2             # spacing of pretend-Mondays (2 = every other Monday)
SHAPE_WEEKS = 8                    # weeks of history used for the shape of the day

# Days the call centre is closed. Thanksgiving, Christmas Day and New Year's Day were always
# closed in your data. 24 Dec was closed in 2025 and the day after Thanksgiving in 2025.
# Confirm with Lou and edit this list if needed (format YYYY-MM-DD).
EXTRA_CLOSED = ["2026-12-24", "2026-11-27"]
LAGS = [1, 15, 30, 60, 90, 120, 150, 182]
TRAIN_START = pd.Timestamp("2022-09-01")

# ---------------------------------------------------------------------
# PART 1: LOAD
# ---------------------------------------------------------------------
raw = pd.read_csv(CALLS_FILE, parse_dates=["CallDay", "Interval15Min"])
raw["Slot"] = raw["Interval15Min"].dt.hour * 60 + raw["Interval15Min"].dt.minute
SLOTS = sorted(raw.groupby("Slot")["CallCount"].sum().loc[lambda s: s > s.sum() * 0.00005].index)
raw = raw[raw["Slot"].isin(SLOTS)]
LAST = raw["CallDay"].max()
FIRST = raw["CallDay"].min()
ORIGIN = LAST + pd.Timedelta(days=1)                       # first day we forecast
print(f"Call data: {FIRST.date()} to {LAST.date()}")

# the Saturday on which the first FULL forecast week starts
next_sat = ORIGIN + pd.Timedelta(days=(5 - ORIGIN.dayofweek) % 7)
if next_sat == ORIGIN and ORIGIN.dayofweek == 5:
    pass
CURRENT_WEEK_START = next_sat - pd.Timedelta(days=7)
FORECAST_END = next_sat + pd.Timedelta(weeks=WEEKS_AHEAD) - pd.Timedelta(days=1)   # a Friday
HORIZON = (FORECAST_END - ORIGIN).days + 1

cal_idx = pd.date_range(FIRST - pd.Timedelta(days=400), FORECAST_END + pd.Timedelta(days=5))
daily = raw.groupby(["Language", "CallDay"])["CallCount"].sum().unstack(0).reindex(cal_idx)

# customer counts (monthly) -> one number per day
cnt = pd.read_excel(COUNTS_FILE, header=2)
cnt = cnt[(cnt["Jurisdiction"] == COUNT_JURISDICTION) & (cnt["R/C"] == COUNT_TYPE)
          & (cnt["Indicator"] == "EOP") & (cnt["unit"] == COUNT_UNIT)]
cnt = cnt.drop_duplicates(subset=["Entity", "R/C", "Retail Book"]).drop_duplicates(subset=["Entity", "R/C"])   # the file lists the RCE rows twice
months = [c for c in cnt.columns if hasattr(c, "year") and not isinstance(c, str)]
cust_m = cnt[months].sum()
cust_m.index = pd.to_datetime(cust_m.index)
cust_m = cust_m[cust_m > 0]
CUST = cust_m.reindex(cal_idx.union(cust_m.index)).interpolate(limit_area="inside").reindex(cal_idx).ffill().bfill()
print(f"Customer counts ({COUNT_JURISDICTION} {COUNT_TYPE} {COUNT_UNIT}): "
      f"{cust_m.index.min().date()} to {cust_m.index.max().date()}; latest month {cust_m.loc[:LAST].iloc[-1]:,.0f}")

cal = USFederalHolidayCalendar()
HOL = set(cal.holidays("2019-01-01", "2031-12-31")) | {
    pd.Timestamp(y, m, d) for y in range(2019, 2032) for m, d in [(1, 1), (6, 19), (7, 4), (11, 11), (12, 25)]}
CLOSED = set(pd.to_datetime(EXTRA_CLOSED))
for y in range(2026, 2031):
    CLOSED |= {pd.Timestamp(y, 12, 25), pd.Timestamp(y, 1, 1)}
    thx = pd.Timestamp(y, 11, 1) + pd.Timedelta(days=(3 - pd.Timestamp(y, 11, 1).dayofweek) % 7 + 21)
    CLOSED.add(thx)


def cal_features(idx):
    d = pd.DatetimeIndex(idx)
    f = pd.DataFrame(index=d)
    f["dow"] = d.dayofweek
    f["month"] = d.month
    f["dom"] = d.day
    f["woy"] = d.isocalendar().week.values.astype(int)
    f["hol"] = [x in HOL for x in d]
    f["after_hol"] = [((x - pd.Timedelta(days=1)) in HOL) or (x.dayofweek == 0 and (x - pd.Timedelta(days=3)) in HOL) for x in d]
    f["before_hol"] = [(x + pd.Timedelta(days=1)) in HOL for x in d]
    return f.astype(float)


CAL = cal_features(cal_idx)


def build_frame(S, lags):
    """one row per (day, how-far-ahead). Every feature only uses what was known on the 'origin' day."""
    LV = S.rolling(28, min_periods=7).mean().shift(1)         # recent level, known on the morning of day d
    LY = pd.concat([S.shift(371), S.shift(364), S.shift(357)], axis=1).mean(axis=1)
    out = []
    for L in lags:
        X = CAL.copy()
        X["lag"] = L
        lvl = LV.shift(L)                                      # level on the origin day
        X["ly_ratio"] = LY / np.maximum(LV.shift(364 + L), 1)
        X["cust_growth"] = CUST / CUST.shift(L)
        m_ = (L - 1) // 7 + 1                                  # same weekday, recent weeks: is this weekday running high or low lately?
        dl = pd.concat([S.shift(7 * (m_ + j)) for j in range(5)], axis=1).mean(axis=1)
        X["dow_ratio"] = dl / np.maximum(lvl, 1)
        X["level"] = lvl
        X["y"] = S / np.maximum(lvl, 1)
        X["actual"] = S
        X["day"] = X.index
        out.append(X)
    return pd.concat(out)


FEATS_WITH = ["dow", "month", "dom", "woy", "hol", "after_hol", "before_hol", "lag", "ly_ratio", "dow_ratio", "cust_growth"]
FEATS_WITHOUT = [f for f in FEATS_WITH if f != "cust_growth"]


def fit(train, feats):
    m = HistGradientBoostingRegressor(max_iter=250, learning_rate=0.05, max_depth=4, min_samples_leaf=30, random_state=1)
    m.fit(train[feats], train["y"])
    return m


def forecast_days(frames, origin, horizon, feats):
    """frames = the frame built for one language. Returns forecast calls per open day."""
    F = frames
    train = F[(F["day"] >= TRAIN_START) & (F["day"] < origin) & F["y"].notna()
              & ((F["day"] - pd.to_timedelta(F["lag"], unit="D")) < origin)]
    m = fit(train, feats)
    days = pd.date_range(origin, periods=horizon)
    days = days[(days.dayofweek != 6) & (~days.isin(list(CLOSED)))]
    lag_rows = []
    for d in days:
        L = (d - origin).days + 1
        lag_rows.append(L)
    # build the rows for these days directly, with lag = distance from origin
    S = frames.attrs["S"]
    LV = S.rolling(28, min_periods=7).mean().shift(1)
    LY = pd.concat([S.shift(371), S.shift(364), S.shift(357)], axis=1).mean(axis=1)
    X = CAL.loc[days].copy()
    L = np.array(lag_rows)
    X["lag"] = L
    X["ly_ratio"] = [LY[d] / max(LV.get(d - pd.Timedelta(days=364 + int(l)), np.nan), 1)
                     if not np.isnan(LV.get(d - pd.Timedelta(days=364 + int(l)), np.nan)) else np.nan
                     for d, l in zip(days, L)]
    X["cust_growth"] = [CUST[d] / CUST[d - pd.Timedelta(days=int(l))] for d, l in zip(days, L)]
    level = LV[origin]
    dl = [np.nanmean([S.get(d - pd.Timedelta(days=7 * (((int(l) - 1) // 7 + 1) + j)), np.nan) for j in range(5)]) for d, l in zip(days, L)]
    X["dow_ratio"] = np.array(dl) / max(level, 1)
    pred = np.maximum(m.predict(X[feats]), 0) * level
    return pd.Series(pred, index=days)


def week_label(days):
    """Saturday-to-Friday week, named by its Saturday"""
    d = pd.DatetimeIndex(days)
    return (d - pd.to_timedelta((d.dayofweek - 5) % 7, unit="D")).normalize()


# per-language frames (built once; every feature only uses data known on the origin day)
FRAMES = {}
for lang in ["English", "Spanish"]:
    S = daily[lang].copy()
    fr = build_frame(S, LAGS)
    fr.attrs["S"] = S
    FRAMES[lang] = fr

# ---------------------------------------------------------------------
# PART 2: TEST (pretend-Mondays)
# ---------------------------------------------------------------------
band = {}                # range of error by language and how far ahead, from the test
if RUN_TEST:
    last_ok = LAST - pd.Timedelta(days=WEEKS_AHEAD * 7 + 6)
    mons = [d for d in pd.date_range(TRAIN_START + pd.Timedelta(days=500), last_ok, freq="W-MON")]
    origins = mons[::-1][::TEST_EVERY_N_WEEKS][:N_TEST_MONDAYS][::-1]
    print(f"\nTEST: {len(origins)} pretend-Mondays, {origins[0].date()} to {origins[-1].date()}, "
          f"each forecasting {WEEKS_AHEAD} weeks ahead (this takes a few minutes)")
    rows = []
    for o in origins:
        for lang in ["English", "Spanish"]:
            S = daily[lang]
            fr = FRAMES[lang]
            f_with = forecast_days(fr, o, WEEKS_AHEAD * 7, FEATS_WITH)
            f_wo = forecast_days(fr, o, WEEKS_AHEAD * 7, FEATS_WITHOUT)
            # simple yardstick: average weekly total of the last 4 full weeks, repeated
            prev = S.loc[o - pd.Timedelta(days=28): o - pd.Timedelta(days=1)]
            last4 = prev.sum() / 4.0
            for d in f_with.index:
                a = S.get(d, np.nan)
                if np.isnan(a):
                    continue
                rows.append((o, lang, d, (d - o).days + 1, f_with[d], f_wo[d], a))
    T = pd.DataFrame(rows, columns=["origin", "Language", "Day", "h", "With counts", "Without counts", "actual"])
    T["week"] = week_label(T["Day"])
    W = T.groupby(["origin", "Language", "week"]).agg(
        w=("With counts", "sum"), wo=("Without counts", "sum"), a=("actual", "sum"),
        n=("Day", "count"), h=("h", "min")).reset_index()
    W = W[W["n"] >= 5]
    W["weeks_ahead"] = ((W["week"] - (W["origin"] + pd.to_timedelta((5 - W["origin"].dt.dayofweek) % 7, unit="D"))).dt.days // 7 + 1)
    W = W[W["weeks_ahead"] >= 1]
    # yardstick: the last 4 full weeks before the origin, repeated
    ys = []
    for _, r in W.iterrows():
        prev = daily[r["Language"]].loc[r["origin"] - pd.Timedelta(days=28): r["origin"] - pd.Timedelta(days=1)]
        ys.append(prev.sum() / 4.0)
    W["last4"] = ys
    for c in ["w", "wo", "last4"]:
        W[c + "_acc"] = 100 - (W[c] - W["a"]).abs() / W["a"] * 100
    W["when"] = pd.cut(W["weeks_ahead"], [0, 4, 13, 26], labels=["Weeks 1-4", "Weeks 5-13", "Weeks 14-26"])
    summ = W.groupby(["Language", "when"], observed=True)[["w_acc", "wo_acc", "last4_acc"]].mean().round(1)
    summ.columns = ["With customer counts", "Without customer counts", "Repeat last 4 weeks"]
    print("\nWEEKLY ACCURACY (average of weeks, higher is better)\n", summ.to_string())
    allsumm = W.groupby("when", observed=True)[["w_acc", "wo_acc", "last4_acc"]].mean().round(1)
    allsumm.columns = summ.columns
    print("\nBOTH LANGUAGES\n", allsumm.to_string())
    summ.reset_index().to_csv(FOLDER / "test_weekly_accuracy_26weeks.csv", index=False)
    # --- too high or too low? (positive = our forecast was above the real number) ---
    use_w, use_d = ("w", "With counts") if USE_CUSTOMER_COUNTS else ("wo", "Without counts")
    W["bias"] = W[use_w] / W["a"] - 1
    bias = W.groupby("when", observed=True)["bias"].agg(lambda x: round(x.mean() * 100, 1))
    over = W.groupby("when", observed=True)["bias"].agg(lambda x: round((x > 0).mean() * 100))
    print("\nTOO HIGH OR TOO LOW?  (average miss in %, plus the share of weeks we were too high)")
    print(pd.DataFrame({"Average miss (%)": bias, "Weeks too high (%)": over}).to_string())
    # --- by day of the week ---
    T["acc_day"] = 100 - (T[use_d] - T["actual"]).abs() / T["actual"] * 100
    T["bias_day"] = T[use_d] / T["actual"] - 1
    T["dow"] = T["Day"].dt.day_name()
    T["when_d"] = np.where(T["h"] <= 28, "Next 4 weeks", "After that")
    order_d = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    wd = T.groupby(["dow", "when_d"])["acc_day"].mean().unstack().reindex(order_d).round(1)
    wd["Too high by (%)"] = (T.groupby("dow")["bias_day"].mean().reindex(order_d) * 100).round(1)
    print("\nACCURACY BY DAY OF THE WEEK (average of daily scores)\n", wd.to_string())
    wd.reset_index().to_csv(FOLDER / "test_accuracy_by_weekday.csv", index=False)
    T.to_csv(FOLDER / "test_26weeks_daily_detail.csv", index=False)
    # the range: how far off the weekly forecast typically was, by language and distance
    W["err"] = (W["w"] if USE_CUSTOMER_COUNTS else W["wo"]) / W["a"] - 1
    for (lang, wh), g in W.groupby(["Language", "when"], observed=True):
        band[(lang, wh)] = (g["err"].quantile(0.10), g["err"].quantile(0.90))
    print("\n(The low-high range in the forecast file covers the middle 80% of past misses.)")
    (FOLDER / "forecast_error_ranges.json").write_text(json.dumps({f"{k[0]}|{k[1]}": v for k, v in band.items()}))
elif (FOLDER / "forecast_error_ranges.json").exists():
    band = {tuple(k.split("|")): tuple(v) for k, v in json.loads((FOLDER / "forecast_error_ranges.json").read_text()).items()}
    print("Test skipped: using the saved low-high ranges from the last full test.")

# ---------------------------------------------------------------------
# PART 3: FORECAST FROM TODAY
# ---------------------------------------------------------------------
print(f"\nFORECAST from {ORIGIN.date()} to {FORECAST_END.date()}  ({WEEKS_AHEAD} full weeks start Saturday {next_sat.date()})")
fc = {}
for lang in ["English", "Spanish"]:
    fc[lang] = forecast_days(FRAMES[lang], ORIGIN, HORIZON, FEATS_WITH if USE_CUSTOMER_COUNTS else FEATS_WITHOUT)
daily_out = pd.DataFrame({"English": fc["English"], "Spanish": fc["Spanish"]}).fillna(0)
daily_out.index.name = "Date"
daily_out["Total"] = daily_out.sum(axis=1)
daily_out.round(0).to_csv(FOLDER / "forecast_daily.csv")

# add the real calls for days of this week that have already happened
actual_now = daily.loc[CURRENT_WEEK_START:LAST, ["English", "Spanish"]].dropna(how="all")
combined = pd.concat([actual_now.assign(Source="Actual"), daily_out[["English", "Spanish"]].assign(Source="Forecast")])
combined["Week starting (Sat)"] = week_label(combined.index)
wk = combined.groupby("Week starting (Sat)")[["English", "Spanish"]].sum()
wk["Total"] = wk.sum(axis=1)
wk["Weeks ahead"] = ((wk.index - next_sat).days // 7 + 1)
wk["Note"] = np.where(wk["Weeks ahead"] == 0, "This week: real calls so far + forecast for the rest", "")


def rng(lang, wa, which):
    if not band:
        return np.nan
    key = "Weeks 1-4" if wa <= 4 else ("Weeks 5-13" if wa <= 13 else "Weeks 14-26")
    lo, hi = band[(lang, key)]
    return lo if which == "lo" else hi


for lang in ["English", "Spanish"]:
    # low/high: past misses were forecast/actual - 1; so actual ranges between f/(1+hi) and f/(1+lo)
    wk[f"{lang} low"] = [v / (1 + rng(lang, a, "hi")) if a > 0 and band else np.nan for v, a in zip(wk[lang], wk["Weeks ahead"])]
    wk[f"{lang} high"] = [v / (1 + rng(lang, a, "lo")) if a > 0 and band else np.nan for v, a in zip(wk[lang], wk["Weeks ahead"])]
wk = wk[["Weeks ahead", "English", "English low", "English high", "Spanish", "Spanish low", "Spanish high", "Total", "Note"]]
wk.round(0).to_csv(FOLDER / "forecast_weekly_26weeks.csv")

# monthly: add up the days (complete months only)
actual_month = daily.loc[LAST.replace(day=1):LAST, ["English", "Spanish"]].dropna(how="all")
mon = pd.concat([actual_month, daily_out[["English", "Spanish"]]])
mon["Month"] = mon.index.to_period("M").astype(str)
m = mon.groupby("Month")[["English", "Spanish"]].sum()
m["Total"] = m.sum(axis=1)
last_full = (FORECAST_END + pd.Timedelta(days=1)).to_period("M") - 1
m = m[m.index <= str(last_full)]
m["Note"] = ""
first_m = str(LAST.to_period("M"))
if first_m in m.index and LAST.day < LAST.days_in_month:
    m.loc[first_m, "Note"] = "Real calls to date + forecast"
m.round(0).to_csv(FOLDER / "forecast_monthly_6months.csv")

# 15 minutes for the next 90 days
shape = {}
for lang in ["English", "Spanish"]:
    s0 = ORIGIN - pd.Timedelta(weeks=SHAPE_WEEKS)
    r = raw[(raw.Language == lang) & (raw.CallDay >= s0) & (~raw.CallDay.isin(list(HOL)))]
    t = r.assign(dow=r.CallDay.dt.dayofweek).groupby(["dow", "Slot"])["CallCount"].sum().unstack(1).reindex(columns=SLOTS).fillna(0)
    shape[lang] = t.div(t.sum(axis=1), axis=0)
int_rows = []
end90 = ORIGIN + pd.Timedelta(days=INTERVAL_DAYS - 1)
for lang in ["English", "Spanish"]:
    for d, v in fc[lang].items():
        if d > end90:
            continue
        sh = shape[lang].loc[d.dayofweek].values
        for s, p in zip(SLOTS, v * sh):
            int_rows.append((lang, d.date(), (d + pd.Timedelta(minutes=int(s))).strftime("%Y-%m-%d %H:%M"), round(p, 1)))
pd.DataFrame(int_rows, columns=["Language", "CallDay", "Interval15Min", "ForecastCalls"]).to_csv(
    FOLDER / "forecast_15min_90days.csv", index=False)

print("\nWEEKLY FORECAST (first 8 weeks)\n", wk.head(8).round(0).to_string())
print("\nMONTHLY FORECAST\n", m.round(0).to_string())
print("\nSaved: forecast_weekly_26weeks.csv, forecast_monthly_6months.csv, forecast_15min_90days.csv, forecast_daily.csv"
      + (", test_weekly_accuracy_26weeks.csv" if RUN_TEST else ""))
