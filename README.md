# =====================================================================
# MAKE THE THREE CHARTS FOR THE PRESENTATION
#
#   chart_1_accuracy.png    How accurate the forecast is, near and far, against the targets
#   chart_2_forecast.png    The next 26 weeks by language, with the low-high range
#   chart_3_15min.png       Why a flat spread misses, and how the 15-minute methods score
#
# Run:  py make_forecast_charts.py      (needs:  py -m pip install matplotlib   the first time)
# It reads the files the forecast already saved in this same folder:
#     test_weekly_accuracy_26weeks.csv, forecast_weekly_26weeks.csv,
#     test_15min_accuracy_summary.csv, eng_spa_15min_2year_combined.csv
# and writes the PNG pictures into a folder called charts.
# =====================================================================
from pathlib import Path
import numpy as np
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.ticker import FuncFormatter

FOLDER = Path(__file__).resolve().parent
OUT = FOLDER / "charts"
OUT.mkdir(exist_ok=True)

# targets from Jonathon (about 93% in the short term, about 84% in the long term)
TARGET_SHORT, TARGET_LONG = 93, 84

# ---- look: one blue for what the chart is about, grey for everything else ----
BLUE = "#1f5fbf"
BLUE_LIGHT = "#bcd0ee"
GREY = "#a3a8b0"
GREY_DARK = "#5b616b"
INK = "#1d2330"
plt.rcParams.update({
    "font.family": "DejaVu Sans", "font.size": 11, "text.color": INK,
    "axes.edgecolor": "#c9ccd1", "axes.labelcolor": GREY_DARK, "xtick.color": GREY_DARK, "ytick.color": GREY_DARK,
    "axes.spines.top": False, "axes.spines.right": False, "figure.dpi": 100, "savefig.dpi": 200,
})

# =====================================================================
# CHART 1: accuracy near and far
# =====================================================================
acc = pd.read_csv(FOLDER / "test_weekly_accuracy_26weeks.csv")
order = ["Weeks 1-4", "Weeks 5-13", "Weeks 14-26"]
both = acc.groupby("when")[["Without customer counts", "Repeat last 4 weeks"]].mean().reindex(order)
ours = both["Without customer counts"].values
base = both["Repeat last 4 weeks"].values

# ---- optional: the operational forecast (drop operational_forecast_weekly.csv in this folder to add its bar) ----
# columns: Week starting (Sat), Language (English / Spanish / Both), Weeks ahead (how many weeks before that week the forecast was made), Forecast
op = None
OPF = FOLDER / "operational_forecast_weekly.csv"
if OPF.exists():
    _o = pd.read_csv(OPF, parse_dates=["Week starting (Sat)"])
    _raw = pd.read_csv(FOLDER / "eng_spa_15min_2year_combined.csv", parse_dates=["CallDay"])
    _d = _raw.groupby(["Language", "CallDay"])["CallCount"].sum().unstack(0)
    _w = _d.groupby(_d.index - pd.to_timedelta((_d.index.dayofweek - 5) % 7, unit="D")).sum()
    _w["Both"] = _w.sum(axis=1)
    _rows = []
    for _, r in _o.iterrows():
        wk = r["Week starting (Sat)"]
        if wk in _w.index and wk + pd.Timedelta(days=6) <= _d.index.max():
            a = _w.loc[wk, r["Language"]]
            _rows.append((int(r["Weeks ahead"]), 100 - abs(r["Forecast"] - a) / a * 100))
    if _rows:
        _t = pd.DataFrame(_rows, columns=["wa", "acc"])
        _t["when"] = pd.cut(_t["wa"], [0, 4, 13, 26], labels=order)
        op = _t.groupby("when", observed=False)["acc"].mean().reindex(order).values

fig, ax = plt.subplots(figsize=(9.5, 5.6))
x = np.arange(3)
nb = 3 if op is not None else 2
w = 0.26 if nb == 3 else 0.34
offs = [-w - 0.01, 0, w + 0.01] if nb == 3 else [-w / 2 - 0.01, w / 2 + 0.01]
b1 = ax.bar(x + offs[0], base, w, color=GREY, label="Repeat the last 4 weeks (simple comparison)")
bars_all = [b1]
if op is not None:
    b_op = ax.bar(x + offs[1], op, w, color=GREY_DARK, label="Operational forecast")
    bars_all.append(b_op)
b2 = ax.bar(x + offs[-1], ours, w, color=BLUE, label="Our forecast")
bars_all.append(b2)
for bars in bars_all:
    for r in bars:
        top = r.get_height()
        if bars is b2 and abs(top - TARGET_SHORT) < 3:      # keep the number clear of the dashed target line
            top = TARGET_SHORT + 0.8
        ax.text(r.get_x() + r.get_width() / 2, top + 0.8, f"{r.get_height():.0f}%", ha="center", va="bottom",
                fontsize=12, fontweight="bold" if bars is b2 else "normal", color=INK if bars is b2 else GREY_DARK)
# target marks (only where Jonathon gave one)
for xi, t, lab in [(0, TARGET_SHORT, "Target about 93%"), (2, TARGET_LONG, "Target about 84%")]:
    ax.plot([xi - 0.42, xi + 0.42], [t, t], color=INK, lw=1.6, ls=(0, (4, 3)))
    ax.text(xi + 0.44, t, lab, va="center", ha="left", fontsize=10, color=INK)
ax.set_xticks(x)
ax.set_xticklabels(["Next 1 to 4 weeks", "5 to 13 weeks ahead", "14 to 26 weeks ahead"])
ax.set_ylim(50, 102)
ax.yaxis.set_major_formatter(FuncFormatter(lambda v, p: f"{v:.0f}%"))
ax.set_ylabel("How close the forecast was (100% = exact)")
ax.grid(axis="y", color="#e6e8eb", lw=0.8)
ax.set_axisbelow(True)
ax.set_title(f"About {ours[0]:.0f}% accurate for the next month,\nand still about {ours[2]:.0f}% at six months", loc="left", fontsize=14,
             fontweight="bold", pad=14)
ax.legend(frameon=False, loc="lower left", ncol=3 if op is not None else 2, bbox_to_anchor=(0, -0.2), fontsize=9.5)
fig.text(0.01, 0.01, "Test: 30 practice runs from Mar 2025 to Apr 2026, English and Spanish together. Weekly totals, Saturday to Friday.",
         fontsize=8.5, color=GREY_DARK)
fig.tight_layout(rect=(0, 0.03, 0.97, 1))
fig.savefig(OUT / "chart_1_accuracy.png")
plt.close(fig)

# =====================================================================
# CHART 2: the next 26 weeks by language
# =====================================================================
raw = pd.read_csv(FOLDER / "eng_spa_15min_2year_combined.csv", parse_dates=["CallDay"])
dayly = raw.groupby(["Language", "CallDay"])["CallCount"].sum().unstack(0)
wk_start = lambda d: d - pd.to_timedelta((d.dayofweek - 5) % 7, unit="D")
fc = pd.read_csv(FOLDER / "forecast_weekly_26weeks.csv", parse_dates=["Week starting (Sat)"])
first_fc = fc["Week starting (Sat)"].min()
hist = dayly[dayly.index < first_fc]
hist_w = hist.groupby(wk_start(hist.index)).sum()
hist_w = hist_w[hist_w.index >= first_fc - pd.Timedelta(weeks=26)]

# ---- what the forecast said back then (from the practice runs), to compare with the real calls ----
past_far, past_near, far_date = None, None, ""
BT = FOLDER / "test_26weeks_daily_detail.csv"
if BT.exists():
    bt = pd.read_csv(BT, parse_dates=["Day", "origin", "week"])
    bt["f"] = bt["Without counts"]
    wk_ = bt.groupby(["origin", "Language", "week"]).agg(f=("f", "sum"), n=("Day", "count")).reset_index()
    wk_ = wk_[wk_["n"] >= 5]
    last_o = wk_["origin"].max()
    far = wk_[wk_["origin"] == last_o]                                   # one forecast, made about six months before these weeks
    past_far = far.pivot(index="week", columns="Language", values="f")
    past_far = past_far[past_far.index >= hist_w.index.min()]
    far_date = f"{last_o.day} {last_o.strftime('%B')}"
RT = FOLDER / "test_recent_forecasts.csv"
if RT.exists():
    rt = pd.read_csv(RT, parse_dates=["Week starting (Sat)"])
    past_near = rt.pivot(index="Week starting (Sat)", columns="Language", values="Forecast a month ahead")
    past_near = past_near[past_near.index >= hist_w.index.min()]

fig, axes = plt.subplots(2, 1, figsize=(10.5, 7.2), sharex=True)
for ax, lang in zip(axes, ["English", "Spanish"]):
    ax.plot(hist_w.index, hist_w[lang], color=GREY, lw=2, label="Real calls")
    if past_far is not None and lang in past_far:
        ax.plot(past_far.index, past_far[lang], color=BLUE, lw=1.6, ls=(0, (4, 3)), alpha=0.9,
                label=f"What we forecast on {far_date} for these weeks")
    if past_near is not None and lang in past_near:
        ax.plot(past_near.index, past_near[lang], color=BLUE, lw=1.6, alpha=0.9, label="What we forecast about a month before each week")
    ax.plot(fc["Week starting (Sat)"], fc[lang], color=BLUE, lw=2.4, label="Forecast")
    rng = fc.dropna(subset=[f"{lang} low"])
    ax.fill_between(rng["Week starting (Sat)"], rng[f"{lang} low"], rng[f"{lang} high"], color=BLUE_LIGHT, alpha=0.55, lw=0,
                    label="Likely range (8 times in 10)")
    top = max(float(hist_w[lang].max()), float(fc[lang].max())) * 1.12
    ax.set_ylim(0, top)
    ax.axvline(first_fc, color=GREY_DARK, lw=1, ls=(0, (3, 3)))
    ax.text(first_fc, top, "  today", va="top", ha="left", fontsize=9, color=GREY_DARK)
    ax.set_ylabel(f"{lang} calls per week")
    ax.yaxis.set_major_formatter(FuncFormatter(lambda v, p: f"{v:,.0f}"))
    ax.grid(axis="y", color="#e6e8eb", lw=0.8)
    ax.set_axisbelow(True)
    # label the holiday dips and the last real week
    for lbl, wdate in [("Thanksgiving", pd.Timestamp("2026-11-21")), ("Christmas", pd.Timestamp("2026-12-19"))]:
        row = fc[fc["Week starting (Sat)"] == wdate]
        if len(row):
            v = float(row[lang].iloc[0])
            left = lbl == "Thanksgiving"          # one label goes left, one goes right, so they never touch
            ax.annotate(lbl, (wdate, v), xytext=(-12 if left else 12, -34), textcoords="offset points",
                        ha="right" if left else "left", fontsize=9.5, color=GREY_DARK,
                        arrowprops=dict(arrowstyle="-", color=GREY, lw=0.9, shrinkA=2, shrinkB=3))
axes[1].legend(*axes[0].get_legend_handles_labels(), frameon=False, loc="upper center", bbox_to_anchor=(0.5, -0.12), ncol=2, fontsize=9)
axes[0].set_title("Calls are coming down from the autumn peak\nand should hold steady through winter",
                  loc="left", fontsize=14, fontweight="bold", pad=14)
axes[1].xaxis.set_major_formatter(matplotlib.dates.DateFormatter("%b %Y"))
axes[1].xaxis.set_major_locator(matplotlib.dates.MonthLocator(interval=2))
fig.text(0.01, 0.005, "Each point is one week (Saturday to Friday). Grey = real calls, blue = forecast.\nThin blue lines on the grey history = what the forecast said back then (solid: a month before each week, dashed: six months before).",
         fontsize=8.5, color=GREY_DARK)
fig.tight_layout(rect=(0, 0.04, 1, 1))
fig.savefig(OUT / "chart_2_forecast.png")
plt.close(fig)

# =====================================================================
# CHART 3: the 15-minute view
# =====================================================================
raw["Interval15Min"] = pd.to_datetime(raw["Interval15Min"])
raw["Minute"] = raw["Interval15Min"].dt.hour * 60 + raw["Interval15Min"].dt.minute
last_day = raw["CallDay"].max()
recent = raw[(raw["CallDay"] > last_day - pd.Timedelta(weeks=8)) & (raw["CallDay"].dt.dayofweek == 0)]
# a normal Monday = the average of the last 8 weeks of Mondays, English and Spanish together
n_mon = recent["CallDay"].nunique()
shape = recent.groupby("Minute")["CallCount"].sum().reindex(range(7 * 60, 19 * 60 + 1, 15)).fillna(0) / n_mon
flat = np.full(len(shape), shape.sum() / len(shape))

s15 = pd.read_csv(FOLDER / "test_15min_accuracy_summary.csv")
row = s15[(s15["Language"] == "Both") & (s15["Horizon"] == "All 90 days")].iloc[0]
methods = ["Weekly number\nspread evenly", "Weekly number spread\nby the usual week shape", "Our forecast"]
vals = [row["Spread evenly"], row["Spread by usual week shape"], row["Ours"]]

fig, (a1, a2) = plt.subplots(1, 2, figsize=(12.5, 5.4), gridspec_kw={"width_ratios": [1.35, 1]})
hours = shape.index / 60
a1.fill_between(hours, shape.values, color=BLUE_LIGHT, lw=0)
a1.plot(hours, shape.values, color=BLUE, lw=2.4, label="What really happens on a normal Monday")
a1.plot(hours, flat, color=GREY_DARK, lw=2, ls=(0, (4, 3)), label="Weekly number spread evenly")
a1.set_xticks(range(7, 20, 2))
a1.set_xticklabels([f"{h if h <= 12 else h - 12}{'am' if h < 12 else 'pm'}" for h in range(7, 20, 2)])
a1.set_ylabel("Calls in each 15-minute slot")
a1.grid(axis="y", color="#e6e8eb", lw=0.8)
a1.set_axisbelow(True)
a1.legend(frameon=False, loc="upper center", bbox_to_anchor=(0.5, -0.1), ncol=2, fontsize=9.5)
a1.set_title("Spreading the week evenly misses\nwhen calls really come in", loc="left", fontsize=12.5, fontweight="bold")
cols = [GREY, GREY, BLUE]
bars = a2.bar(range(3), vals, color=cols, width=0.62)
for r in bars:
    a2.text(r.get_x() + r.get_width() / 2, r.get_height() + 1, f"{r.get_height():.0f}%", ha="center", va="bottom", fontsize=12,
            fontweight="bold" if r is bars[-1] else "normal")
a2.set_xticks(range(3))
a2.set_xticklabels(methods, fontsize=9.5)
a2.set_ylim(0, 100)
a2.yaxis.set_major_formatter(FuncFormatter(lambda v, p: f"{v:.0f}%"))
a2.set_ylabel("15-minute accuracy over 90 days")
a2.grid(axis="y", color="#e6e8eb", lw=0.8)
a2.set_axisbelow(True)
a2.set_title("Ours beats an even spread by 17 points,\nand a smarter one by 2", loc="left", fontsize=12.5,
             fontweight="bold")
fig.text(0.01, 0.012, "Left: average of the last 8 Mondays, English and Spanish together. Right: 30 practice runs, each forecasting 90 days.\n"
         "The two 'spread' methods are our guess at how Workforce does it; they got the same weekly total as ours.", fontsize=8.5, color=GREY_DARK)
fig.tight_layout(rect=(0, 0.07, 1, 1))
fig.savefig(OUT / "chart_3_15min.png")
plt.close(fig)
print("Saved chart_1_accuracy.png, chart_2_forecast.png and chart_3_15min.png in the charts folder")
