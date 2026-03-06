

import os
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt

from IPython.display import display

# =============================================================================
from pathlib import Path
import matplotlib.pyplot as plt
import seaborn as sns

# --- Global style choices (requested: darker blues) ---
DARK_BLUE = "#003366"
LIGHT_GRAY = "#B0B0B0"

sns.set_theme(style="whitegrid", context="talk")
plt.rcParams["figure.dpi"] = 120
plt.rcParams["savefig.dpi"] = 300
plt.rcParams["axes.titleweight"] = "bold"
plt.rcParams["axes.titlesize"] = 14
plt.rcParams["axes.labelsize"] = 12

OUTPUT_ROOT = Path("outputs_task3_task4")
FIG_DIR = OUTPUT_ROOT / "figures"
TABLE_DIR = OUTPUT_ROOT / "tables"
FIG_DIR.mkdir(parents=True, exist_ok=True)
TABLE_DIR.mkdir(parents=True, exist_ok=True)

def save_fig(name: str, fig=None, formats=("png", "pdf")):
    """Save the current matplotlib figure into outputs_task3_task4/figures as PNG + PDF."""
    if fig is None:
        fig = plt.gcf()
    for fmt in formats:
        fig.savefig(FIG_DIR / f"{name}.{fmt}", bbox_inches="tight")

def save_table(df_in: pd.DataFrame, name: str, max_rows: int = 35, max_cols: int = 12, fontsize: int = 9):
    """
    Save a dataframe as:
      - CSV (full table)
      - LaTeX (full table, for Overleaf \input{})
      - PNG snapshot (head, readable) for quick inclusion as an image
    """
 # Full exports
    df_in.to_csv(TABLE_DIR / f"{name}.csv", index=True)
    try:
        df_in.to_latex(TABLE_DIR / f"{name}.tex", index=True)
    except Exception as e:
        print(f"[save_table] LaTeX export failed for {name}: {e}")

 # PNG snapshot (head + limited columns)
    df_show = df_in.copy()
    if df_show.shape[0] > max_rows:
        df_show = df_show.head(max_rows)
    if df_show.shape[1] > max_cols:
        df_show = df_show.iloc[:, :max_cols]

 # Format numeric columns for readability
    df_show_fmt = df_show.copy()
    for c in df_show_fmt.columns:
        if pd.api.types.is_numeric_dtype(df_show_fmt[c]):
            df_show_fmt[c] = df_show_fmt[c].map(lambda x: "" if pd.isna(x) else f"{x:.3f}")

    df_show_fmt = df_show_fmt.reset_index()

    fig, ax = plt.subplots(figsize=(max(8, 0.8 * df_show_fmt.shape[1]), max(2.5, 0.35 * df_show_fmt.shape[0])))
    ax.axis("off")

    tbl = ax.table(
        cellText=df_show_fmt.values,
        colLabels=df_show_fmt.columns,
        loc="center",
        cellLoc="center"
    )
    tbl.auto_set_font_size(False)
    tbl.set_fontsize(fontsize)
    tbl.scale(1, 1.2)

 # Style header row + zebra stripes
    for (row, col), cell in tbl.get_celld().items():
        if row == 0:
            cell.set_facecolor(DARK_BLUE)
            cell.set_text_props(color="white", weight="bold")
        else:
            cell.set_facecolor("#F7F7F7" if row % 2 == 0 else "white")

    fig.tight_layout()
    fig.savefig(TABLE_DIR / f"{name}.png", bbox_inches="tight")
    plt.close(fig)

def make_outputs_zip(zip_name: str = "outputs_task3_task4"):
    """Zip the entire outputs_task3_task4 folder (figures + tables + CSVs)."""
    import shutil
    zip_path = shutil.make_archive(zip_name, "zip", OUTPUT_ROOT)
    print("Created zip:", zip_path)
    return zip_path

#Load Data
pd.set_option("display.max_columns", 200)
pd.set_option("display.width", 120)

np.random.seed(42)

DATA_PATH = "Daily Borough Events Panel.csv"

df_raw = pd.read_csv(DATA_PATH)

print("Cleaned Panel Data File:", DATA_PATH)
print("Shape:", df_raw.shape)
display(df_raw.head())


#EDA - Dataset Overview & Panel Structure Checks

# 1) Dataset overview + quick structure checks
df = df_raw.copy()

# Parse date
df["date"] = pd.to_datetime(df["date"], errors="coerce")

# Standardize borough as category
df["borough"] = df["borough"].astype("string").str.upper().str.strip()
df["borough"] = df["borough"].astype("category")

# Basic panel completeness check
n_days = df["date"].nunique()
n_borough = df["borough"].nunique()
expected = n_days * n_borough
print(f"Unique days: {n_days} | Unique boroughs: {n_borough} | Expected rows: {expected} | Actual rows: {len(df)}")
print("Balanced panel:", expected == len(df))

# Duplicate check at panel key level
dup = df.duplicated(subset=["date","borough"]).sum()
print("Duplicate (date, borough) rows:", dup)

# Date range
print("Date range:", df["date"].min().date(), "→", df["date"].max().date())


#EDA - Auto Data Dictionary

# 2) Data dictionary (auto-generated)
def make_data_dictionary(data: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for c in data.columns:
        s = data[c]
        row = {
            "column": c,
            "dtype": str(s.dtype),
            "missing_n": int(s.isna().sum()),
            "missing_%": float(s.isna().mean()*100),
            "unique_n": int(s.nunique(dropna=True)),
        }
        if pd.api.types.is_numeric_dtype(s):
            row.update({
                "mean": float(np.nanmean(s)),
                "std": float(np.nanstd(s)),
                "min": float(np.nanmin(s)),
                "p25": float(np.nanpercentile(s.dropna(), 25)) if s.notna().any() else np.nan,
                "median": float(np.nanmedian(s)),
                "p75": float(np.nanpercentile(s.dropna(), 75)) if s.notna().any() else np.nan,
                "max": float(np.nanmax(s)),
            })
        else:
            examples = s.dropna().astype(str).unique()[:5]
            row["examples"] = ", ".join(examples)
        rows.append(row)
    out = pd.DataFrame(rows).sort_values(["missing_%","unique_n"], ascending=[False, False])
    return out

dd = make_data_dictionary(df)
display(dd.head(15))
print("\nColumns with any missingness:")
display(dd[dd["missing_n"]>0][["column","dtype","missing_n","missing_%"]])


#EDA - Column Grouping & Sanity Checks

# 3) Column groups
id_cols = ["date", "borough"]

target_cols = ["complaints_total", "log_complaints_total"]

topk_cols = [c for c in df.columns if c.startswith("topk_") and c.endswith("_cnt")]

weather_cols = [
    "temp_mean", "temp_max", "temp_min",
    "precipitation_sum", "rain_sum", "snowfall_sum",
    "wind_speed_mean", "wind_gust_mean", "cloud_cover_mean"
]

structural_cols = [
    "census_income_borough_median", "census_population_borough_sum",
    "airbnb_listing_count", "airbnb_price_mean", "airbnb_price_median",
    "airbnb_rating_mean", "airbnb_total_reviews", "airbnb_entire_home_pct",
    "airbnb_per_1000_people_borough"
]

time_cols = ["day_of_week", "is_weekend", "month", "event_day"]

lag_cols = [c for c in df.columns if c.endswith("_lag1") or c.endswith("_ma7")]

other_cols = [c for c in df.columns if c not in (id_cols + topk_cols + weather_cols + structural_cols + time_cols + lag_cols + ["unique_complaints"])]

print("Top-K complaint bucket columns:", len(topk_cols))
print("Lag/Rolling columns:", len(lag_cols))
print("Other columns:", other_cols)

#Consistency checks (useful EDA sanity checks)

# 1) topk buckets should partition complaints_total (since there's a topk_OTHER_cnt)
topk_sum = df[topk_cols].sum(axis=1)
share_ok = (topk_sum == df["complaints_total"]).mean()
print("Share check: topk_sum == complaints_total in % of rows:", round(share_ok*100, 2), "%")

# 2) unique_complaints duplicates complaints_total in this panel (it is redundant here)
same_unique = (df["unique_complaints"] == df["complaints_total"]).mean()
print("Check: unique_complaints == complaints_total in % of rows:", round(same_unique*100, 2), "%")


#EDA - Summary Statistics

# 4) EDA — summary statistics

# Overall summary of key numeric variables
key_numeric = ["complaints_total","log_complaints_total"] + weather_cols
display(df[key_numeric].describe().T)

# By-borough complaint summary (mean/median/min/max)
borough_summary = (
    df.groupby("borough")["complaints_total"]
      .agg(["count","mean","median","min","max","sum"])
      .sort_values("mean", ascending=False)
)
display(borough_summary)


#EDA - Missingness Patterns

# 5) EDA — missingness patterns
miss = df.isna().mean().sort_values(ascending=False)
miss_tbl = miss[miss > 0].to_frame("missing_rate")
display(miss_tbl)

if len(miss_tbl) > 0:
    save_table(miss_tbl, "Table_missingness_rates")

# Missingness heatmap
# In this dataset, missingness is mainly structural from lag/rolling features at the start of each borough series.
mask = df.isna().to_numpy().astype(int)

plt.figure(figsize=(12, 4))
plt.imshow(mask, aspect="auto", interpolation="nearest", cmap="Blues")
plt.title("Missingness heatmap (1 = missing)")
plt.xlabel("Columns (in df order)")
plt.ylabel("Rows")
plt.colorbar()
plt.tight_layout()
save_fig("Fig00_missingness_heatmap")
plt.show()


#EDA - Citywide Anomaly Detection (Robust Z-score)

# Citywide total complaints per day
daily_city = df.groupby("date")["complaints_total"].sum().sort_index()

median = daily_city.median()
mad = np.median(np.abs(daily_city - median))
robust_z = 0.6745 * (daily_city - median) / (mad if mad != 0 else 1)

quality_by_date = (
    pd.DataFrame({
        "date": daily_city.index,
        "citywide_complaints_total": daily_city.values,
        "citywide_robust_z": robust_z.values,
    })
    .sort_values("date")
    .reset_index(drop=True)
)

# Robust outlier flags (|robust_z| > 3.5 is a common MAD-based rule of thumb)
quality_by_date["is_outlier_citywide"] = (quality_by_date["citywide_robust_z"].abs() > 3.5).astype(int)
quality_by_date["is_outlier_low_citywide"] = (quality_by_date["citywide_robust_z"] < -3.5).astype(int)
quality_by_date["is_outlier_high_citywide"] = (quality_by_date["citywide_robust_z"] > 3.5).astype(int)

outlier_df = quality_by_date[quality_by_date["is_outlier_citywide"] == 1].copy()

print("Outlier dates (robust z-score):")
display(outlier_df)

# Save the outlier table (CSV + LaTeX + PNG snapshot)
if len(outlier_df) > 0:
    save_table(outlier_df.set_index("date"), "Table_citywide_outliers_robust_z")

plt.figure(figsize=(12, 4))
plt.plot(
    quality_by_date["date"],
    quality_by_date["citywide_complaints_total"],
    color=DARK_BLUE,
    linewidth=2,
    label="Citywide total"
)

if len(outlier_df) > 0:
    plt.scatter(
        outlier_df["date"],
        outlier_df["citywide_complaints_total"],
        color="orange",
        edgecolor="white",
        s=80,
        label="Robust outlier"
    )

plt.title("Citywide daily complaints_total (robust outliers highlighted)")
plt.xlabel("Date")
plt.ylabel("Citywide complaints_total")
plt.legend()
plt.grid(alpha=0.25)
plt.tight_layout()
save_fig("Fig01_citywide_anomaly_robust_z")
plt.show()


#EDA - Distributions & Potential Outliers

# 7) EDA — distributions & potential outliers

# Histogram: raw complaints_total
plt.figure(figsize=(10, 4))
plt.hist(df["complaints_total"], bins=30, color=DARK_BLUE, edgecolor="white")
plt.title("Distribution of complaints_total (all borough-days)")
plt.xlabel("complaints_total")
plt.ylabel("Frequency")
plt.grid(alpha=0.25)
plt.tight_layout()
save_fig("Fig02_hist_complaints_total")
plt.show()

# Histogram: log1p-transformed target
plt.figure(figsize=(10, 4))
plt.hist(df["log_complaints_total"], bins=30, color=DARK_BLUE, edgecolor="white")
plt.title("Distribution of log_complaints_total (log1p transform)")
plt.xlabel("log_complaints_total")
plt.ylabel("Frequency")
plt.grid(alpha=0.25)
plt.tight_layout()
save_fig("Fig03_hist_log_complaints_total")
plt.show()


# Boxplot by borough (visualize heterogeneity + outliers)
# plt.figure(figsize=(10, 4))
# sns.boxplot(data=df, x="borough", y="complaints_total", color=DARK_BLUE)
# plt.title("complaints_total by borough")
# plt.xlabel("borough")
# plt.ylabel("complaints_total")
# plt.grid(alpha=0.25)
# plt.tight_layout()
# save_fig("Fig04_boxplot_complaints_by_borough")
# plt.show()
# ============================================================
# Boxplot + Violin Plot by Borough
# ============================================================

fig, axes = plt.subplots(1, 2, figsize=(16, 5))

# Order boroughs by median complaint level (descending)
order = (
    df.groupby('borough')['complaints_total']
      .median()
      .sort_values(ascending=False)
      .index
)

# -------------------------
# Boxplot
# -------------------------
sns.boxplot(
    data=df,
    x='borough',
    y='complaints_total',
    order=order,
    palette='Set2',
    ax=axes[0]
)

axes[0].set_title('Distribution of Daily Complaints by Borough',
                  fontsize=13, fontweight='bold')
axes[0].set_xlabel('Borough')
axes[0].set_ylabel('Daily Complaints')
axes[0].tick_params(axis='x', rotation=20)
axes[0].grid(alpha=0.25)

# -------------------------
# Violin Plot
# -------------------------
sns.violinplot(
    data=df,
    x='borough',
    y='complaints_total',
    order=order,
    palette='Set2',
    inner='quartile',
    ax=axes[1]
)

axes[1].set_title('Complaint Density by Borough (Violin Plot)',
                  fontsize=13, fontweight='bold')
axes[1].set_xlabel('Borough')
axes[1].set_ylabel('Daily Complaints')
axes[1].tick_params(axis='x', rotation=20)
axes[1].grid(alpha=0.25)

plt.tight_layout()

# Save figure (consistent naming style)
save_fig("Fig04_boxplot_violin_complaints_by_borough")

plt.show()


#EDA - Complaint Composition (Top-K Buckets)

# 10) EDA — complaint composition (topk_* buckets)

# Compute shares (composition)
shares = df[topk_cols].div(df["complaints_total"], axis=0)

# Overall average share per bucket
mean_shares = shares.mean().sort_values(ascending=False)
display(mean_shares.to_frame("mean_share"))

save_table(mean_shares.to_frame("mean_share"), "Table_mean_share_overall")

# Borough-level average shares
shares_borough = pd.concat([df[["borough"]], shares], axis=1).groupby("borough").mean()

# Heatmap (borough × bucket) — prettier than raw imshow (and easier to read)
plt.figure(figsize=(12, 4))
sns.heatmap(
    shares_borough,
    cmap="Blues",
    cbar_kws={"shrink": 0.8},
    linewidths=0.25
)
plt.title("Average complaint share by borough × complaint bucket")
plt.xlabel("Complaint bucket")
plt.ylabel("Borough")
plt.tight_layout()
save_fig("Fig05_composition_heatmap")
plt.show()

# Save the borough × share table too
save_table(shares_borough, "Table_shares_by_borough")

display(shares_borough)


#EDA - Time Trends (Borough + Citywide)

# 6) EDA — trends over time

# Borough time series
ts = df.pivot_table(index="date", columns="borough", values="complaints_total", aggfunc="mean").sort_index()

plt.figure(figsize=(12, 5))
for b in ts.columns:
    plt.plot(ts.index, ts[b], label=str(b), linewidth=1.6, alpha=0.85)
plt.title("Daily NYC 311 complaints_total by borough")
plt.xlabel("Date")
plt.ylabel("complaints_total")
plt.legend(ncol=3, fontsize=9)
plt.grid(alpha=0.25)
plt.tight_layout()
save_fig("Fig06_timeseries_by_borough")
plt.show()

# Citywide total (sum across boroughs per day)
daily_city = df.groupby("date", as_index=False).agg(
    complaints_total_city=("complaints_total", "sum"),
    temp_mean=("temp_mean", "mean"),
    precipitation_sum=("precipitation_sum", "sum"),
    event_day=("event_day", "max"),
    is_weekend=("is_weekend", "max"),
)

plt.figure(figsize=(12, 4))
plt.plot(
    daily_city["date"],
    daily_city["complaints_total_city"],
    color=DARK_BLUE,
    linewidth=2.2
)
plt.title("Citywide daily 311 complaints (sum across boroughs)")
plt.xlabel("Date")
plt.ylabel("complaints_total_city")
plt.grid(alpha=0.25)
plt.tight_layout()
save_fig("Fig07_citywide_total_complaints")
plt.show()


# =============================================================================
# Figure: Citywide Trend with 7-Day Moving Average
# =============================================================================
# We aggregate across boroughs to get a single citywide daily series, then smooth it with a 7-day MA.
city = df.groupby("date", as_index=False)["complaints_total"].sum()
city["ma7"] = city["complaints_total"].rolling(7, min_periods=1).mean()

plt.figure(figsize=(12, 5))
plt.plot(city["date"], city["complaints_total"], alpha=0.35, label="Daily total", color=LIGHT_GRAY)
plt.plot(city["date"], city["ma7"], linewidth=2.8, label="7-day moving average", color=DARK_BLUE)
plt.title("Citywide Daily Complaints with 7-Day Moving Average", fontsize=14, fontweight="bold")
plt.xlabel("Date", fontsize=12)
plt.ylabel("Total Complaints", fontsize=12)
plt.legend(fontsize=10)
plt.grid(alpha=0.25)
plt.tight_layout()
save_fig("Fig08_citywide_ma7")
plt.show()


# =============================================================================
# Figure: Autocorrelation Function (ACF)
# =============================================================================
print("Generating autocorrelation function (ACF)...")

def acf(x, lags=30):
    """
    Calculate autocorrelation function manually.

    Args:
        x: Time series array
        lags: Number of lags to calculate

    Returns:
        List of autocorrelation coefficients
    """
    x = x - np.mean(x)
    result = [1.0]  # ACF at lag 0 is always 1
    for lag in range(1, lags + 1):
        if len(x) <= lag:
            break
        corr = np.corrcoef(x[:-lag], x[lag:])[0, 1]
        result.append(corr)
    return result

acf_vals = acf(city["complaints_total"].values, 30)

plt.figure(figsize=(10, 5))
markerline, stemlines, baseline = plt.stem(range(len(acf_vals)), acf_vals)
# Style (requested: darker blue)
markerline.set_color(DARK_BLUE)
try:
    stemlines.set_color(DARK_BLUE)
except Exception:
    pass
baseline.set_color("gray")

plt.axhline(0, color="black", linewidth=0.8)
plt.axhline(1.96/np.sqrt(len(city)), color="red", linestyle="--", linewidth=1, label="95% CI")
plt.axhline(-1.96/np.sqrt(len(city)), color="red", linestyle="--", linewidth=1)
plt.title("Autocorrelation Function (ACF) of Citywide Daily Complaints", fontsize=14, fontweight="bold")
plt.xlabel("Lag (days)", fontsize=12)
plt.ylabel("Autocorrelation", fontsize=12)
plt.legend()
plt.grid(alpha=0.25)
plt.tight_layout()
save_fig("Fig09_acf_citywide")
plt.show()


#EDA - Day-of-Week & Weekend Effects

# 8) EDA — day-of-week / weekend patterns

# Average by day-of-week (0=Mon ... 6=Sun)
dow_mean = df.groupby("day_of_week")["complaints_total"].mean()

plt.figure(figsize=(8, 4))
plt.bar(dow_mean.index.astype(int), dow_mean.values, color=DARK_BLUE)
plt.title("Average complaints_total by day_of_week (0=Mon ... 6=Sun)")
plt.xlabel("day_of_week")
plt.ylabel("mean complaints_total")
plt.grid(alpha=0.25, axis="y")
plt.tight_layout()
save_fig("Fig10_day_of_week_pattern")
plt.show()

# Weekend vs weekday (citywide)
wk_mean = df.groupby("is_weekend")["complaints_total"].mean()

plt.figure(figsize=(6, 4))
plt.bar(["Weekday (0)", "Weekend (1)"], wk_mean.values, color=[DARK_BLUE, "orange"])
plt.title("Average complaints_total: weekend vs weekday")
plt.ylabel("mean complaints_total")
plt.grid(alpha=0.25, axis="y")
plt.tight_layout()
save_fig("Fig11_weekend_vs_weekday")
plt.show()

# By-borough weekend effect (mean difference)
wk_b = df.pivot_table(index="borough", columns="is_weekend", values="complaints_total", aggfunc="mean")
wk_b["weekend_minus_weekday"] = wk_b.get(1) - wk_b.get(0)

display(wk_b)

save_table(wk_b, "Table_weekend_effect_by_borough")


#EDA - Event-Day Comparison

# 9) EDA — event_day effect (simple comparison)

event_counts = df["event_day"].value_counts().rename_axis("event_day").to_frame("n_rows")
display(event_counts)
save_table(event_counts, "Table_event_day_row_counts")

event_mean = df.groupby("event_day")["complaints_total"].agg(["count", "mean", "median"])
display(event_mean)
save_table(event_mean, "Table_event_day_summary_stats")

event_b = df.pivot_table(index="borough", columns="event_day", values="complaints_total", aggfunc="mean")
event_b["event_minus_non"] = event_b.get(1) - event_b.get(0)
display(event_b)
save_table(event_b, "Table_event_effect_by_borough")

# Plot (boxplot)
df_plot = df.copy()
df_plot["event_day_label"] = df_plot["event_day"].map({0: "Non-event (0)", 1: "Event (1)"})

plt.figure(figsize=(7, 4))
sns.boxplot(
    data=df_plot,
    x="event_day_label",
    y="complaints_total",
    palette=[DARK_BLUE, "orange"]
)
plt.title("complaints_total: event day vs non-event day")
plt.xlabel("")
plt.ylabel("complaints_total")
plt.grid(alpha=0.25, axis="y")
plt.tight_layout()
save_fig("Fig12_event_day_boxplot")
plt.show()


#### 4.4.2 Weather effects (weather relationships)

# =====================
# 11) EDA — weather relationships (Task 3)
# =====================

import numpy as np
from scipy import stats
import matplotlib.pyplot as plt

# Citywide daily aggregates (avoid borough scale differences dominating correlations)
daily = df.groupby("date", as_index=False).agg(
    complaints_total_city=("complaints_total", "sum"),
    temp_mean=("temp_mean", "mean"),
    precipitation_sum=("precipitation_sum", "sum"),
    wind_speed_mean=("wind_speed_mean", "mean"),
    event_day=("event_day", "max") if "event_day" in df.columns else ("event_count", "max"),
    is_weekend=("is_weekend", "max"),
)

# Small correlation table (optional)
corr_small = daily[["complaints_total_city", "temp_mean", "precipitation_sum", "wind_speed_mean", "event_day", "is_weekend"]].corr()
display(corr_small)
save_table(corr_small, "Table_citywide_weather_corr_small")

# ---------- Helper: scatter + optional regression line ----------
def scatter_with_stats(ax, x, y, xlabel, ylabel, title_prefix, add_fit=True):
 # drop NaNs pairwise
    mask = x.notna() & y.notna()
    x_clean = x[mask].astype(float)
    y_clean = y[mask].astype(float)

 # scatter
    ax.scatter(x_clean, y_clean, alpha=0.25, s=12)

 # Pearson correlation
    r, pval = stats.pearsonr(x_clean, y_clean)

 # linear fit line
    if add_fit:
        z = np.polyfit(x_clean, y_clean, 1)
        p_line = np.poly1d(z)
        x_range = np.linspace(x_clean.min(), x_clean.max(), 100)
        ax.plot(x_range, p_line(x_range), linewidth=2)

    ax.set_title(f"{title_prefix}\n(r={r:.3f}, p={pval:.2e})", fontsize=11)
    ax.set_xlabel(xlabel)
    ax.set_ylabel(ylabel)
    ax.grid(alpha=0.25)

    return r, pval

# ---------- 1×3 figure ----------
fig, axes = plt.subplots(1, 3, figsize=(18, 5))

r1, p1 = scatter_with_stats(
    axes[0],
    daily["temp_mean"],
    daily["complaints_total_city"],
    xlabel="Mean Temperature (C)",
    ylabel="Citywide Daily Complaints",
    title_prefix="Temperature vs Complaints",
    add_fit=True
)

r2, p2 = scatter_with_stats(
    axes[1],
    daily["precipitation_sum"],
    daily["complaints_total_city"],
    xlabel="Precipitation (mm)",
    ylabel="Citywide Daily Complaints",
    title_prefix="Precipitation vs Complaints",
    add_fit=True
)

r3, p3 = scatter_with_stats(
    axes[2],
    daily["wind_speed_mean"],
    daily["complaints_total_city"],
    xlabel="Wind Speed (km/h)",
    ylabel="Citywide Daily Complaints",
    title_prefix="Wind Speed vs Complaints",
    add_fit=True
)

plt.suptitle("Weather Variables vs 311 Complaints (Citywide Daily Aggregates)", fontsize=14, fontweight="bold")
plt.tight_layout()

save_fig("Fig13_citywide_weather_vs_complaints_3panels")
plt.show()




#EDA - Correlation Heatmap & Multicollinearity (VIF)

# 12) EDA — correlation structure + multicollinearity diagnostics

from statsmodels.stats.outliers_influence import variance_inflation_factor
import statsmodels.api as sm

# A) Correlation matrix (all numeric columns)
num_cols_all = df.select_dtypes(include=[np.number]).columns.tolist()

# Drop all-NA / constant columns (correlation undefined)
num_cols_all = [
    c for c in num_cols_all
    if df[c].notna().any() and df[c].nunique(dropna=True) > 1
]

corr_all = df[num_cols_all].corr(numeric_only=True)

# Save correlation matrix values (full) for reference
corr_all.to_csv(TABLE_DIR / "corr_full_numeric.csv")

# Prettier diverging colormap (requested: make it look nicer than default coolwarm)
cmap_corr = sns.diverging_palette(240, 10, as_cmap=True)

plt.figure(figsize=(max(12, 0.35 * len(num_cols_all)), max(10, 0.35 * len(num_cols_all))))
sns.heatmap(
    corr_all,
    cmap=cmap_corr,
    center=0,
    vmin=-1,
    vmax=1,
    cbar_kws={"shrink": 0.6},
    linewidths=0.15
)
plt.title("Full correlation matrix (all numeric columns)")
plt.tight_layout()
save_fig("Fig16_corr_full_numeric")
plt.show()

# B) VIF (Variance Inflation Factor) for a curated feature subset
vif_features = [
    "temp_mean",
    "precipitation_sum",
    "wind_speed_mean",
    "cloud_cover_mean",
    "census_income_borough_median",
    "airbnb_listing_count",
    "event_day",
    "is_weekend",
]
vif_features = [c for c in vif_features if c in df.columns]

X_vif = df[vif_features].copy().dropna()
X_vif = sm.add_constant(X_vif)

vif_table = []
for i, col in enumerate(X_vif.columns):
    if col == "const":
        continue
    vif_table.append({"feature": col, "VIF": variance_inflation_factor(X_vif.values, i)})

vif_table = pd.DataFrame(vif_table).sort_values("VIF", ascending=False)
display(vif_table)

# Save VIF table (CSV + LaTeX + PNG snapshot)
save_table(vif_table.set_index("feature"), "Table_vif_curated_features")


#EDA - Outliers & Influential Points Diagnostics

# 13) EDA — outliers & influential points
import statsmodels.formula.api as smf

# Simple baseline regression (for diagnostics only)
df_reg = df.copy()
df_reg = df_reg.dropna(subset=["log_complaints_total", "temp_mean", "precipitation_sum", "month", "is_weekend", "event_day", "borough"])

model = smf.ols("log_complaints_total ~ C(borough) + temp_mean + precipitation_sum + is_weekend + event_day + month", data=df_reg).fit()
print(model.summary().tables[0])
print(model.summary().tables[1])

influence = model.get_influence()
sf = influence.summary_frame()

# Add identifiers back for interpretation
sf = sf.reset_index(drop=True)
sf = pd.concat(
    [df_reg[["date", "borough", "complaints_total", "temp_mean", "precipitation_sum", "event_day"]].reset_index(drop=True), sf],
    axis=1
)

# Rules of thumb (style)
n = model.nobs
p = int(model.df_model) + 1  # includes intercept
cook_thr = 4 / n
leverage_thr = 2 * p / n

print(f"n={int(n)}, p={p} | Cook's threshold ~ 4/n = {cook_thr:.4f} | leverage threshold ~ 2p/n = {leverage_thr:.4f}")

# Top influential points by Cook's distance
top_cook = sf.sort_values("cooks_d", ascending=False).head(10)
display(top_cook[["date", "borough", "complaints_total", "temp_mean", "precipitation_sum", "event_day", "cooks_d", "hat_diag", "student_resid"]])

# Save influential-points table
save_table(
    top_cook[["date", "borough", "complaints_total", "temp_mean", "precipitation_sum", "event_day", "cooks_d", "hat_diag", "student_resid"]].set_index(["date", "borough"]),
    "Table_top10_influential_points_cooksd"
)

# Visual: Cook's distance (requested: darker blue + save)
plt.figure(figsize=(10, 4))
try:
    markerline, stemlines, baseline = plt.stem(sf["cooks_d"].values)
except TypeError:
 # Some matplotlib versions return different objects, but the basic call still works
    markerline, stemlines, baseline = plt.stem(sf["cooks_d"].values)

# Style stem
try:
    markerline.set_color(DARK_BLUE)
    stemlines.set_color(DARK_BLUE)
    baseline.set_color("gray")
except Exception:
    pass

plt.axhline(cook_thr, linestyle="--", color="red", linewidth=1.5, label="4/n threshold")
plt.title("Cook's distance across observations (baseline OLS)")
plt.xlabel("Observation index")
plt.ylabel("Cook's D")
plt.legend()
plt.grid(alpha=0.25)
plt.tight_layout()
save_fig("Fig17_cooks_distance")
plt.show()

# Visual: leverage vs studentized residuals (classic influence diagnostic)
plt.figure(figsize=(6, 5))
plt.scatter(sf["hat_diag"], sf["student_resid"], alpha=0.55, color=DARK_BLUE, edgecolor="white", linewidth=0.4)
plt.axvline(leverage_thr, linestyle="--", color="red", linewidth=1.5, label="2p/n threshold")
plt.axhline(0, linestyle="--", color="gray", linewidth=1.0)
plt.title("Leverage (hat) vs studentized residuals")
plt.xlabel("hat_diag (leverage)")
plt.ylabel("student_resid")
plt.legend()
plt.grid(alpha=0.25)
plt.tight_layout()
save_fig("Fig18_leverage_vs_studentized_residuals")
plt.show()


#EDA - PCA

# 14) PCA view of borough-days
from sklearn.preprocessing import StandardScaler
from sklearn.decomposition import PCA

# Use complaint composition shares (excluding OTHER) + weather
share_cols = [c.replace("_cnt", "_share") for c in topk_cols]
df_pca = df.copy()

for c_cnt in topk_cols:
    df_pca[c_cnt.replace("_cnt", "_share")] = df_pca[c_cnt] / df_pca["complaints_total"]

# Exclude the "OTHER" share to avoid perfect dependence (shares sum to 1)
share_cols_no_other = [c for c in share_cols if "OTHER" not in c]

pca_features = share_cols_no_other + [
    "temp_mean",
    "precipitation_sum",
    "wind_speed_mean",
    "cloud_cover_mean",
    "event_day",
    "is_weekend",
    "month",
]
X = df_pca[pca_features].copy()
X = X.dropna()
borough_for_plot = df_pca.loc[X.index, "borough"].astype(str)

scaler = StandardScaler()
X_scaled = scaler.fit_transform(X)

pca = PCA(n_components=2, random_state=42)
Z = pca.fit_transform(X_scaled)

print("Explained variance ratio:", pca.explained_variance_ratio_)

plt.figure(figsize=(7, 5))
for b in sorted(borough_for_plot.unique()):
    idx = (borough_for_plot == b).values
    plt.scatter(Z[idx, 0], Z[idx, 1], alpha=0.45, label=b)

plt.title("PCA of borough-days (complaint shares + weather + calendar)")
plt.xlabel("PC1")
plt.ylabel("PC2")
plt.legend(fontsize=8)
plt.grid(alpha=0.25)
plt.tight_layout()
save_fig("Fig19_pca_scatter")
plt.show()


#Feature Engineering (Time, Weather, Shares, Lags, Interactions)

# 16) Feature engineering
df_fe = df.copy()

# ---- 16.1 Time index (trend feature)
min_date = df_fe["date"].min()
df_fe["day_index"] = (df_fe["date"] - min_date).dt.days

# ---- 16.2 Cyclical encodings (weekly + yearly seasonality proxies)
df_fe["dow_sin"] = np.sin(2*np.pi*df_fe["day_of_week"]/7)
df_fe["dow_cos"] = np.cos(2*np.pi*df_fe["day_of_week"]/7)

df_fe["month_sin"] = np.sin(2*np.pi*(df_fe["month"]-1)/12)
df_fe["month_cos"] = np.cos(2*np.pi*(df_fe["month"]-1)/12)

# ---- 16.3 Weather-derived features
df_fe["temp_range"] = df_fe["temp_max"] - df_fe["temp_min"]
df_fe["is_freezing"] = (df_fe["temp_min"] <= 0).astype(int)
df_fe["is_precip"] = (df_fe["precipitation_sum"] > 0).astype(int)
df_fe["is_snow"] = (df_fe["snowfall_sum"] > 0).astype(int)

# ---- 16.4 Per-capita complaint rate (per 1,000 people)
df_fe["complaints_per_1000_people"] = (
    df_fe["complaints_total"] / df_fe["census_population_borough_sum"] * 1000
)

# ---- 16.5 Complaint composition shares (drop one share later to avoid sum-to-1 dependence)
for c_cnt in topk_cols:
    df_fe[c_cnt.replace("_cnt","_share")] = df_fe[c_cnt] / df_fe["complaints_total"]

share_cols = [c.replace("_cnt","_share") for c in topk_cols]
share_cols_no_other = [c for c in share_cols if "OTHER" not in c]

# Composition diversity metrics (creative but interpretable)
P = df_fe[share_cols].clip(lower=1e-12)  # avoid log(0)
df_fe["complaint_entropy"] = -(P * np.log(P)).sum(axis=1)      # Shannon entropy
df_fe["complaint_hhi"] = (df_fe[share_cols]**2).sum(axis=1)    # concentration (Herfindahl)
df_fe["complaint_top_share"] = df_fe[share_cols].max(axis=1)

# A domain-motivated share
df_fe["heat_hot_water_share"] = df_fe["topk_HEAT_HOT_WATER_cnt"] / df_fe["complaints_total"]

# ---- 16.6 Lag-safe features (avoid leakage by using *previous-day* information)
df_fe = df_fe.sort_values(["borough","date"]).reset_index(drop=True)

df_fe["complaints_total_lag1"] = df_fe.groupby("borough")["complaints_total"].shift(1)
df_fe["complaints_total_lag7"] = df_fe.groupby("borough")["complaints_total"].shift(7)

df_fe["complaints_total_ma7_prev"] = df_fe.groupby("borough")["complaints_total"].transform(
    lambda s: s.shift(1).rolling(7, min_periods=3).mean()
)

df_fe["temp_mean_ma7_prev"] = df_fe.groupby("borough")["temp_mean"].transform(
    lambda s: s.shift(1).rolling(7, min_periods=3).mean()
)

# Changes / growth


# ---- 16.6B Additional lag structure (time-safe) for change features
df_fe["complaints_total_lag2"] = df_fe.groupby("borough")["complaints_total"].shift(2)

# Past-only change features (avoid using same-day target)
df_fe["complaints_total_diff_lag1"] = df_fe["complaints_total_lag1"] - df_fe["complaints_total_lag2"]
df_fe["complaints_total_pct_change_lag1"] = (
    (df_fe["complaints_total_lag1"] - df_fe["complaints_total_lag2"]) / df_fe["complaints_total_lag2"]
).replace([np.inf, -np.inf], np.nan)

# ---- 16.6C Lagged complaint composition (safe for predicting today's volume)
# We keep same-day shares for EDA, but use *lagged* shares for modeling.
for c in share_cols_no_other + ["complaint_entropy", "complaint_hhi", "complaint_top_share", "heat_hot_water_share"]:
    if c in df_fe.columns:
        df_fe[f"{c}_lag1"] = df_fe.groupby("borough")[c].shift(1)
# ---- 16.7 Interaction terms (interaction examples)
df_fe["weekend_x_precip"] = df_fe["is_weekend"] * df_fe["precipitation_sum"]
df_fe["event_x_weekend"] = df_fe["event_day"] * df_fe["is_weekend"]
df_fe["event_x_temp"] = df_fe["event_day"] * df_fe["temp_mean"]
df_fe["freezing_x_heat_share"] = df_fe["is_freezing"] * df_fe["heat_hot_water_share"]

# ---- 16.8 Simple binning (example: bin continuous vars)
df_fe["temp_bin"] = pd.cut(
    df_fe["temp_mean"],
    bins=[-np.inf, 0, 10, 20, 30, np.inf],
    labels=["<=0C","0-10C","10-20C","20-30C",">30C"]
)

# ---- 16.X Data quality flags by date (from the anomaly detection step)
# These flags are for *filtering / reporting* only; do NOT use them as predictors for same-day complaint models (leakage risk).
if "quality_by_date" in globals():
    df_fe = df_fe.merge(
        quality_by_date[["date","is_outlier_citywide","is_outlier_low_citywide","is_outlier_high_citywide"]],
        on="date",
        how="left",
    )
else:
    df_fe["is_outlier_citywide"] = 0
    df_fe["is_outlier_low_citywide"] = 0
    df_fe["is_outlier_high_citywide"] = 0

print("Feature engineering done. New shape:", df_fe.shape)
display(df_fe.head())


#Preprocessing - Missing Value Handling (EDA-friendly vs Time-safe)

# 17) Handle missing values
miss2 = df_fe.isna().mean().sort_values(ascending=False)
display(miss2[miss2>0].to_frame("missing_rate_after_FE"))

cols_with_missing = miss2[miss2>0].index.tolist()
print("Columns with missing values:", cols_with_missing)

# -------------------------------------------------------------------
# Two "processed" views:
# 1) df_imp -> EDA-friendly (panel-aware imputation that may use bfill)
# 2) df_time -> time-safe (NO backward fill; keep structural lag NAs and drop those rows later)
# -------------------------------------------------------------------

# ---- 17.1 EDA-friendly imputed dataset (ok for plots/correlations)
df_imp = df_fe.copy()

# Missingness indicators (often useful for modeling)
for c in cols_with_missing:
    df_imp[f"{c}_missing"] = df_imp[c].isna().astype(int)

for c in cols_with_missing:
    if pd.api.types.is_numeric_dtype(df_imp[c]):
 # Panel-aware fill: for EDA convenience we allow bfill+ffill within borough
        df_imp[c] = df_imp.groupby("borough")[c].transform(lambda s: s.bfill().ffill())
        df_imp[c] = df_imp[c].fillna(df_imp[c].median())
    else:
        mode_val = df_imp[c].mode(dropna=True)
        df_imp[c] = df_imp[c].fillna(mode_val.iloc[0] if len(mode_val)>0 else "UNKNOWN")

print("EDA-friendly missingness after imputation (should be ~0):")
display(df_imp.isna().mean().sort_values(ascending=False).head(10).to_frame("missing_rate"))

# ---- 17.2 Time-safe dataset for model matrices (avoid future-looking imputation)
df_time = df_fe.copy()

for c in cols_with_missing:
    df_time[f"{c}_missing"] = df_time[c].isna().astype(int)

for c in cols_with_missing:
    if pd.api.types.is_numeric_dtype(df_time[c]):
 # IMPORTANT: forward fill only (past -> present). No backward fill.
        df_time[c] = df_time.groupby("borough")[c].transform(lambda s: s.ffill())
 # If anything remains missing (e.g., first day lag), keep as NaN for now.
    else:
        mode_val = df_time[c].mode(dropna=True)
        df_time[c] = df_time[c].fillna(mode_val.iloc[0] if len(mode_val)>0 else "UNKNOWN")

print("Time-safe missingness snapshot (expected: lags/rollings still missing at start of each borough):")
display(df_time.isna().mean().sort_values(ascending=False).head(10).to_frame("missing_rate_time_safe"))


#Preprocessing - OPTIONAL KNN Imputation

# 17B) OPTIONAL: KNN imputation

from sklearn.impute import KNNImputer

# Apply KNN to numeric columns (KNN uses distance; scaling can matter!)
num_cols = df_fe.select_dtypes(include=[np.number]).columns

knn = KNNImputer(n_neighbors=5, weights="distance")
df_knn_num = pd.DataFrame(knn.fit_transform(df_fe[num_cols]), columns=num_cols, index=df_fe.index)

# Compare missing columns before vs after (should be filled)
print("Missing rate BEFORE (numeric):")
display(df_fe[num_cols].isna().mean().sort_values(ascending=False).head(8).to_frame("missing_rate_before"))

print("Missing rate AFTER KNN (numeric):")
display(df_knn_num.isna().mean().sort_values(ascending=False).head(8).to_frame("missing_rate_after_knn"))

# We'll keep df_imp (panel-aware imputation) as our main imputed dataset.


#Preprocessing - Outliers & Skewness Transforms

# 18) Outliers & skewness: winsorization + log/power transforms (+ )
from scipy.stats.mstats import winsorize
from scipy.stats import boxcox

def add_outlier_and_skew_transforms(df_in: pd.DataFrame) -> pd.DataFrame:
    df_out = df_in.copy()

 # 18.1 Winsorize a few heavily-skewed *predictors* (NOT the target)
    wins_cols = ["precipitation_sum", "rain_sum", "snowfall_sum", "wind_gust_mean"]
    for c in wins_cols:
        if c in df_out.columns:
 # winsorize ignores NaNs by design if we convert with np.array; keep NaNs as-is
            x = df_out[c].to_numpy(dtype=float)
            df_out[c + "_wins"] = np.array(winsorize(x, limits=[0.01, 0.01]), dtype=float)

 # 18.2 Log1p transforms (useful for heavy tails / count-like predictors)
    log_cols = ["precipitation_sum", "rain_sum", "snowfall_sum", "airbnb_total_reviews", "airbnb_listing_count"]
    for c in log_cols:
        if c in df_out.columns:
            df_out["log1p_" + c] = np.log1p(df_out[c])

 # 18.3 Box-Cox example (requires strictly positive input)
 # We demonstrate on precipitation_sum by adding a small constant so zeros become positive.
 # NOTE: Box-Cox is optional; Yeo-Johnson (used later) works with zeros/negatives.
    if "precipitation_sum" in df_out.columns:
        x = df_out["precipitation_sum"].fillna(0).astype(float) + 1e-3
        bc, lam = boxcox(x)
        df_out["boxcox_precipitation_sum"] = bc
        df_out["_boxcox_lambda_precipitation_sum"] = lam  # constant; stored for transparency

    return df_out

df_proc_eda = add_outlier_and_skew_transforms(df_imp)
df_proc_time = add_outlier_and_skew_transforms(df_time)

# Quick skewness check (before vs after for precipitation_sum) using the EDA-friendly copy
sk_before = df_proc_eda["precipitation_sum"].skew()
sk_after_wins = df_proc_eda["precipitation_sum_wins"].skew() if "precipitation_sum_wins" in df_proc_eda.columns else np.nan
sk_after_log = df_proc_eda["log1p_precipitation_sum"].skew() if "log1p_precipitation_sum" in df_proc_eda.columns else np.nan

print("Skewness precipitation_sum:", round(sk_before,3))
print("Skewness precipitation_sum_wins:", round(sk_after_wins,3))
print("Skewness log1p_precipitation_sum:", round(sk_after_log,3))

display(df_proc_eda[["precipitation_sum","precipitation_sum_wins","log1p_precipitation_sum","boxcox_precipitation_sum"]].head())


#Preprocessing - Model Matrix Construction (Encoding, Variance Filter, Scaling)

# 19) Build model-ready matrices (encoding + variance filter + scaling)

from sklearn.feature_selection import VarianceThreshold
from sklearn.preprocessing import StandardScaler, MinMaxScaler, PowerTransformer

# -----------------------
# 19.1 Choose target
# -----------------------
TARGET = "log_complaints_total"

# -----------------------
# 19.2 Choose predictors (avoid perfect collinearity / leakage)
# -----------------------
# Drop redundant columns and unsafe rolling means that include current day
drop_cols = [
    "is_outlier_citywide", "is_outlier_low_citywide", "is_outlier_high_citywide",
    "unique_complaints",
    "complaints_total_ma7",      # includes current day -> leakage if target is same-day complaints
    "temp_mean_ma7",             # includes current day
    "precipitation_sum_ma7",     # includes current day
]

# Predictor set for a *future* modeling step:
# - Use time, weather, events, borough, structural
# - Use lagged complaint-based features (past information), not same-day shares or same-day derived rates.
predictor_cols = []

# Time & seasonality
predictor_cols += ["day_index", "dow_sin", "dow_cos", "month_sin", "month_cos", "is_weekend", "event_day"]

# Weather (raw + derived + transformed versions)
predictor_cols += ["temp_mean", "temp_range", "wind_speed_mean", "cloud_cover_mean"]
predictor_cols += ["precipitation_sum_wins", "log1p_precipitation_sum", "boxcox_precipitation_sum"]
predictor_cols += ["is_freezing", "is_precip", "is_snow"]

# Structural borough-level variables (OPTION B uses these instead of borough dummies)
predictor_cols_structural = structural_cols.copy()

# Lag-safe time-series features (past only)
predictor_cols += ["complaints_total_lag1", "complaints_total_lag2", "complaints_total_lag7", "complaints_total_ma7_prev"]
predictor_cols += ["temp_mean_ma7_prev"]

# Past-only change features
predictor_cols += ["complaints_total_diff_lag1", "complaints_total_pct_change_lag1"]

# Lagged complaint composition (yesterday’s composition)
lagged_comp = [c + "_lag1" for c in (share_cols_no_other + ["complaint_entropy", "complaint_hhi", "complaint_top_share", "heat_hot_water_share"])]
predictor_cols += [c for c in lagged_comp if c in df_proc_time.columns]

# Interactions (weather/time/event based; no same-day complaint leakage)
predictor_cols += ["weekend_x_precip", "event_x_weekend", "event_x_temp"]

# Categorical engineered bin + borough
cat_cols = ["borough", "temp_bin"]

# -----------------------
# 19.3 Construct base modeling frame (time-safe)
# -----------------------
df_mm = df_proc_time.copy()

# OPTIONAL: drop suspected partial-day observations (data quality flag)
if "is_outlier_low_citywide" in df_mm.columns:
    before = len(df_mm)
    df_mm = df_mm[df_mm["is_outlier_low_citywide"]==0].copy()
    print(f"Dropped suspected partial-day rows (low outlier days): {before - len(df_mm)}")


# Ensure required columns exist (defensive)
all_needed = [TARGET] + predictor_cols + predictor_cols_structural + cat_cols
missing_needed = [c for c in all_needed if c not in df_mm.columns]
if missing_needed:
    print("WARNING: missing expected columns:", missing_needed)

# Option A: include borough dummies, EXCLUDE structural variables (avoid perfect dependence in linear models)
df_A = df_mm[[TARGET] + predictor_cols + cat_cols].drop(columns=[c for c in drop_cols if c in df_mm.columns], errors="ignore")
# Drop rows with missing in target or any selected predictors (time-safe handling of structural lag NAs)
df_A = df_A.dropna(subset=[TARGET] + predictor_cols).copy()

# Dummy encoding (drop_first=True to avoid dummy trap)
X_A = pd.get_dummies(df_A.drop(columns=[TARGET]), columns=cat_cols, drop_first=True)
y_A = df_A[TARGET].copy()

print("Model Matrix A shape (time-safe, no leakage predictors):", X_A.shape)

# Option B: EXCLUDE borough, INCLUDE structural variables (lets continuous borough-level vars capture differences)
df_B = df_mm[[TARGET] + predictor_cols + predictor_cols_structural + ["temp_bin"]].drop(columns=[c for c in drop_cols if c in df_mm.columns], errors="ignore")
df_B = df_B.dropna(subset=[TARGET] + predictor_cols).copy()
X_B = pd.get_dummies(df_B.drop(columns=[TARGET]), columns=["temp_bin"], drop_first=True)
y_B = df_B[TARGET].copy()

print("Model Matrix B shape (time-safe, includes structural vars):", X_B.shape)

# -----------------------
# 19.4 Near-zero / zero-variance filter ()
# -----------------------
vt = VarianceThreshold(threshold=0.0)
X_A_vt = pd.DataFrame(vt.fit_transform(X_A), columns=X_A.columns[vt.get_support()], index=X_A.index)
dropped_vt = [c for c in X_A.columns if c not in X_A_vt.columns]
print("Dropped zero-variance columns (A):", dropped_vt)

# -----------------------
# 19.5 Scaling versions (standardization vs normalization)
# We'll scale ONLY continuous features; keep binary/dummies unchanged.
# -----------------------
def split_binary_continuous(X: pd.DataFrame):
    binary_cols = []
    cont_cols = []
    for c in X.columns:
        vals = X[c].dropna().unique()
 # treat {0,1} (or very close) as binary
        if len(vals) <= 2 and set(np.round(vals,6)).issubset({0,1}):
            binary_cols.append(c)
        else:
            cont_cols.append(c)
    return binary_cols, cont_cols

bin_A, cont_A = split_binary_continuous(X_A_vt)

scaler_std = StandardScaler()
scaler_mm = MinMaxScaler()

X_A_std = X_A_vt.copy()
X_A_std[cont_A] = scaler_std.fit_transform(X_A_vt[cont_A])

X_A_minmax = X_A_vt.copy()
X_A_minmax[cont_A] = scaler_mm.fit_transform(X_A_vt[cont_A])

# Power transform (Yeo-Johnson) + standardize (often useful for skewed predictors)
pt = PowerTransformer(method="yeo-johnson", standardize=True)
X_A_power = X_A_vt.copy()
X_A_power[cont_A] = pt.fit_transform(X_A_vt[cont_A])

print("Scaled matrices built:")
print(" - X_A_vt:", X_A_vt.shape)
print(" - X_A_std:", X_A_std.shape)
print(" - X_A_minmax:", X_A_minmax.shape)
print(" - X_A_power:", X_A_power.shape)


#Output - Save Processed Data & Model Matrices

# 20) Save outputs
def safe_to_csv(df_obj: pd.DataFrame, path: str) -> str:
    """Write CSV; if overwrite is not permitted, write to a versioned filename."""
    try:
        df_obj.to_csv(path, index=False)
        return path
    except PermissionError:
        base, ext = os.path.splitext(path)
        alt = base + "_v2" + ext
        df_obj.to_csv(alt, index=False)
        print(f"PermissionError writing {path}. Saved to {alt} instead.")
        return alt

out_dir = "outputs_task3_task4"
os.makedirs(out_dir, exist_ok=True)
# Outputs are written to a local folder next to this notebook (portable across environments).

# Processed datasets
out_processed = os.path.join(out_dir, "Daily_Borough_Events_Panel_processed.csv")                 # EDA-friendly (imputed)
out_processed_time = os.path.join(out_dir, "Daily_Borough_Events_Panel_processed_time_safe.csv") # time-safe (no backward fill)

# Model matrices (time-safe)
out_mm_A = os.path.join(out_dir, "Daily_Borough_Events_Panel_model_matrix_A.csv")
out_mm_A_std = os.path.join(out_dir, "Daily_Borough_Events_Panel_model_matrix_A_standard.csv")
out_mm_A_minmax = os.path.join(out_dir, "Daily_Borough_Events_Panel_model_matrix_A_minmax.csv")
out_mm_A_power = os.path.join(out_dir, "Daily_Borough_Events_Panel_model_matrix_A_power.csv")

saved_paths = []
saved_paths.append(safe_to_csv(df_proc_eda, out_processed))
saved_paths.append(safe_to_csv(df_proc_time, out_processed_time))

saved_paths.append(safe_to_csv(X_A_vt.assign(**{TARGET: y_A}), out_mm_A))
saved_paths.append(safe_to_csv(X_A_std.assign(**{TARGET: y_A}), out_mm_A_std))
saved_paths.append(safe_to_csv(X_A_minmax.assign(**{TARGET: y_A}), out_mm_A_minmax))
saved_paths.append(safe_to_csv(X_A_power.assign(**{TARGET: y_A}), out_mm_A_power))

print("Saved files:")
for p in saved_paths:
    print(" -", p)

# =============================================================================
# =============================================================================
zip_path = make_outputs_zip("outputs_task3_task4")
print("Overleaf-ready outputs zip created:", zip_path)



