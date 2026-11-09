# =====================================================================
# RECENT PRACTICE RUNS: what the forecast said a few weeks ahead, for the weeks that already happened.
# Run after call_forecast_26weeks.py:   py make_recent_backtest.py
# It pretends to run the forecast every other Monday from May 2026, looking 8 weeks ahead, and saves
#   test_recent_forecasts.csv   (one row per week and language: what we said ~1 month ahead, and what really happened)
# make_forecast_charts.py reads it to draw the "what we said back then" line on chart 2.
# =====================================================================
import os, runpy
from pathlib import Path
import numpy as np
import pandas as pd

FOLDER = Path(__file__).resolve().parent
os.environ["RUN_TEST"] = "0"
g = runpy.run_path(str(FOLDER / "call_forecast_26weeks.py"))
daily, LAGS, LAST = g["daily"], g["LAGS"], g["LAST"]
build_frame, forecast_days, week_label, FEATS = g["build_frame"], g["forecast_days"], g["week_label"], g["FEATS_WITHOUT"]

FIRST_ORIGIN = pd.Timestamp("2026-05-04")
HORIZON_DAYS = 56
origins = [o for o in pd.date_range(FIRST_ORIGIN, LAST, freq="14D") if o + pd.Timedelta(days=22) <= LAST]
print(f"{len(origins)} practice Mondays: {origins[0].date()} to {origins[-1].date()}")
FR = {}
for lang in ["English", "Spanish"]:
    S = daily[lang].copy()
    fr = build_frame(S, LAGS)
    fr.attrs["S"] = S
    FR[lang] = fr
rows = []
for o in origins:
    for lang in ["English", "Spanish"]:
        f = forecast_days(FR[lang], o, HORIZON_DAYS, FEATS)
        for d in f.index:
            a = daily[lang].get(d, np.nan)
            if not np.isnan(a):
                rows.append((o, lang, d, (d - o).days + 1, f[d], a))
T = pd.DataFrame(rows, columns=["origin", "Language", "Day", "h", "f", "a"])
T["week"] = week_label(T["Day"])
W = T.groupby(["origin", "Language", "week"]).agg(f=("f", "sum"), a=("a", "sum"), n=("Day", "count"), h=("h", "min")).reset_index()
W = W[W["n"] >= 5]
W = W[(W["h"] >= 15) & (W["h"] <= 28)]            # the forecast made about a month before that week
W = W.sort_values("origin").groupby(["week", "Language"]).tail(1)
W["Accuracy %"] = (100 - (W["f"] - W["a"]).abs() / W["a"] * 100).round(1)
W = W.rename(columns={"week": "Week starting (Sat)", "f": "Forecast a month ahead", "a": "Real calls"})
W[["Week starting (Sat)", "Language", "Forecast a month ahead", "Real calls", "Accuracy %", "origin"]].to_csv(FOLDER / "test_recent_forecasts.csv", index=False)
print(W.groupby("Language")["Accuracy %"].mean().round(1))
tot = W.groupby("Week starting (Sat)")[["Forecast a month ahead", "Real calls"]].sum()
print("Both languages together:", round((100 - (tot.iloc[:, 0] - tot.iloc[:, 1]).abs() / tot.iloc[:, 1] * 100).mean(), 1),
      " average lean:", round(((tot.iloc[:, 0] / tot.iloc[:, 1]) - 1).mean() * 100, 1), "%")
print("Saved test_recent_forecasts.csv")
