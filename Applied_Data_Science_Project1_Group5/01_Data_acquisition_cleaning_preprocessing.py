# -*- coding: utf-8 -*-
"""
NYC 311 Analysis Pipeline (Jan–Jun 2024)
=========================================
Parts 1.1–1.4 : Data Collection  (311, Weather, Events, Census, Airbnb)
Part 2         : Build Daily × Borough Panel
Part 3         : Data Quality, Outliers, Imputation

Final output   : Daily Borough Events Panel.csv
"""

import os, time, datetime as _dt
from dataclasses import dataclass
from typing import Dict, List

import numpy as np
import pandas as pd
import requests
import matplotlib.pyplot as plt
from bs4 import BeautifulSoup

# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║  GLOBAL CONFIGURATION                                                    ║
# ╚═══════════════════════════════════════════════════════════════════════════╝

START_DATE = "2024-01-01"
END_DATE   = "2024-06-30"

# Auto-detect environment: Colab uses /content, local uses script directory
if os.path.isdir("/content"):
    BASE_DIR = "/content"
else:
    BASE_DIR = os.path.dirname(os.path.abspath(__file__))

RAW_DIR       = os.path.join(BASE_DIR, "data", "raw")
PROCESSED_DIR = os.path.join(BASE_DIR, "data", "processed")
os.makedirs(RAW_DIR, exist_ok=True)
os.makedirs(PROCESSED_DIR, exist_ok=True)

# Paths — raw inputs
RAW_311_PATH     = os.path.join(RAW_DIR, "nyc_311_raw.csv")
RAW_WEATHER_PATH = os.path.join(RAW_DIR, "weather_raw.csv")
CENSUS_PATH      = os.path.join(RAW_DIR, "census_demographics_raw.csv")
AIRBNB_PATH      = os.path.join(BASE_DIR, "new_york_listings_2024.csv")   # Kaggle upload
EVENTS_PATH      = os.path.join(BASE_DIR, "web_scraped_nyc_jan_jun_2024_expanded.csv")

# Path — final output
FINAL_OUTPUT = os.path.join(PROCESSED_DIR, "Daily Borough Events Panel.csv")

NYC_BOROUGHS = ["MANHATTAN", "BROOKLYN", "QUEENS", "BRONX", "STATEN ISLAND"]

# Census API key
CENSUS_API_KEY = os.getenv("CENSUS_API_KEY", "")

# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║  UTILITY                                                                 ║
# ╚═══════════════════════════════════════════════════════════════════════════╝

def load_csv(path: str) -> pd.DataFrame:
    """Universal CSV loader: read + lowercase column names."""
    df = pd.read_csv(path, low_memory=False)
    df.columns = df.columns.str.lower().str.strip()
    return df


@dataclass
class SoqlWindow:
    """Time window for Socrata SOQL queries."""
    start_date: str   # YYYY-MM-DD
    end_date: str      # YYYY-MM-DD (inclusive)

    def to_where_clause(self) -> str:
        end_plus_1 = (_dt.datetime.strptime(self.end_date, "%Y-%m-%d").date()
                      + _dt.timedelta(days=1))
        return (f"created_date >= '{self.start_date}T00:00:00.000' "
                f"AND created_date < '{end_plus_1.isoformat()}T00:00:00.000'")


# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║  PART 1.1 — 311 + Weather Data Collection                               ║
# ╚═══════════════════════════════════════════════════════════════════════════╝

def download_311(start_date: str, end_date: str, limit: int = 1_500_000) -> pd.DataFrame:
    """Download NYC 311 complaints via Socrata API with pagination."""
    base_url = "https://data.cityofnewyork.us/resource/erm2-nwe9.json"
    window = SoqlWindow(start_date, end_date)

    select_cols = [
        "unique_key", "created_date", "closed_date", "agency", "agency_name",
        "complaint_type", "descriptor", "location_type", "incident_zip",
        "incident_address", "street_name", "cross_street_1", "cross_street_2",
        "intersection_street_1", "intersection_street_2", "borough", "city",
        "status", "resolution_description", "latitude", "longitude", "location",
    ]

    rows: List[Dict] = []
    offset = 0
    page_size = 50_000

    print(f"\n📞 Downloading NYC 311 Data (target: {limit:,} records)")
    while offset < limit:
        batch = min(page_size, limit - offset)
        params = {
            "$select": ",".join(select_cols),
            "$where":  window.to_where_clause(),
            "$order":  "created_date ASC",
            "$limit":  batch,
            "$offset": offset,
        }
        try:
            r = requests.get(base_url, params=params, timeout=60)
            r.raise_for_status()
            data = r.json()
            if not data:
                break
            rows.extend(data)
            offset += len(data)
            print(f"  Downloaded: {len(rows):,} ({len(rows)/limit*100:.1f}%)")
            time.sleep(0.2)
            if len(data) < batch:
                break
        except Exception as e:
            print(f"  ⚠️ Error: {e} — stopping at {len(rows):,} records")
            break

    df = pd.DataFrame(rows)
    df.to_csv(RAW_311_PATH, index=False)
    print(f"  ✅ Saved {len(df):,} rows → {RAW_311_PATH}")
    return df


def download_weather(start_date: str, end_date: str) -> pd.DataFrame:
    """Fetch hourly weather from Open-Meteo Archive API."""
    params = {
        "latitude": 40.7128, "longitude": -74.0060,
        "start_date": start_date, "end_date": end_date,
        "hourly": "temperature_2m,relative_humidity_2m,precipitation,rain,"
                  "snowfall,wind_speed_10m,wind_gusts_10m,cloud_cover",
        "timezone": "America/New_York",
    }
    print("\n🌤️  Downloading Weather Data")
    r = requests.get("https://archive-api.open-meteo.com/v1/archive",
                     params=params, timeout=60)
    r.raise_for_status()
    payload = r.json()

    df = pd.DataFrame(payload.get("hourly", {}))
    df.rename(columns={"time": "timestamp_local"}, inplace=True)
    df["latitude"]  = payload.get("latitude")
    df["longitude"] = payload.get("longitude")
    df["timezone"]  = payload.get("timezone")

    df.to_csv(RAW_WEATHER_PATH, index=False)
    print(f"  ✅ Saved {len(df):,} rows → {RAW_WEATHER_PATH}")
    return df


# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║  PART 1.2 — Web Scraping NYC Events                                     ║
# ╚═══════════════════════════════════════════════════════════════════════════╝

def scrape_events() -> pd.DataFrame:
    """
    Collect NYC events from three sources:
      1. Web scraping nyctourism.com annual events page (BeautifulSoup)
      2. NYC Open Data permitted events API
      3. Manually curated holidays & parades
    """
    import re

    all_events = []

    # --- Source 1: Web scraping nyctourism.com with BeautifulSoup ---
    print("\n🕷️  [Source 1] Web scraping nyctourism.com/annual-events ...")

    # Known annual events with approximate 2024 dates, scraped from page structure
    # We fetch the page, parse event names per month, then match to 2024 dates
    ANNUAL_EVENTS_URL = "https://www.nyctourism.com/annual-events/"
    try:
        headers = {"User-Agent": "Mozilla/5.0 (research project; NYC 311 analysis)"}
        resp = requests.get(ANNUAL_EVENTS_URL, headers=headers, timeout=20)
        resp.raise_for_status()
        soup = BeautifulSoup(resp.text, "html.parser")

        # The page organises events under month headings (h4 tags)
        # Each event is a bold link (<a> inside <strong> or <b>) following its month
        month_sections = soup.find_all("h4")

        # Map month names to numbers for filtering Jan-Jun 2024
        month_map = {
            "january": 1, "february": 2, "march": 3,
            "april": 4, "may": 5, "june": 6,
            "july": 7, "august": 8, "september": 9,
            "october": 10, "november": 11, "december": 12,
        }

        scraped_count = 0
        for heading in month_sections:
            month_text = heading.get_text(strip=True).lower()
            month_num = None
            for name, num in month_map.items():
                if name in month_text:
                    month_num = num
                    break

            if month_num is None or month_num > 6:
                continue  # Only Jan–Jun 2024

            # Walk through siblings until next h4 to find event links
            sibling = heading.find_next_sibling()
            while sibling and sibling.name != "h4":
                # Look for bold event title links
                links = sibling.find_all("a") if sibling.name else []
                for link in links:
                    title = link.get_text(strip=True)
                    # Filter: skip very short or navigation-like text
                    if len(title) > 5 and not title.startswith("http"):
                        # Clean up trademark symbols
                        title = re.sub(r"[℠®™]", "", title).strip()
                        if title:
                            all_events.append({
                                "title": title,
                                "date": f"2024-{month_num:02d}-15",  # mid-month approx
                                "borough": "MANHATTAN",  # most major NYC events
                                "type": "cultural",
                                "source": "nyctourism_scrape",
                                "method": "beautifulsoup",
                                "location": "NYC",
                            })
                            scraped_count += 1
                sibling = sibling.find_next_sibling() if sibling else None

        print(f"  ✅ Scraped {scraped_count} events from nyctourism.com")

    except Exception as e:
        print(f"  ⚠️ Web scraping failed: {e}")

    # --- Source 2: NYC Open Data permitted events API ---
    print("\n  [Source 2] NYC Open Data permitted events API ...")
    url = "https://data.cityofnewyork.us/resource/tvpp-9vvx.json"
    for offset in [0, 100, 200]:
        try:
            resp = requests.get(url, params={"$limit": 100, "$offset": offset}, timeout=15)
            resp.raise_for_status()
            for item in resp.json():
                raw_date = item.get("event_date", "")
                if not raw_date:
                    continue
                try:
                    dt = _dt.datetime.fromisoformat(raw_date.replace("T", " ").split(".")[0])
                    if dt.year == 2024 and dt.month <= 6:
                        all_events.append({
                            "title": item.get("event_name", ""),
                            "date": dt.strftime("%Y-%m-%d"),
                            "borough": item.get("event_borough", "UNKNOWN"),
                            "type": item.get("event_type", "permitted"),
                            "source": "nyc_opendata",
                            "method": "api",
                            "location": item.get("event_location", ""),
                        })
                except Exception:
                    continue
            time.sleep(1)
        except Exception as e:
            print(f"  ⚠️ Batch offset={offset} failed: {str(e)[:60]}")

    # --- Source 3: Manually curated holidays & parades (verified dates) ---
    print("\n  [Source 3] Curated major holidays & parades ...")
    manual = [
        ("New Year Day",           "2024-01-01", "ALL",       "holiday",  "Citywide"),
        ("MLK Day",                "2024-01-15", "ALL",       "holiday",  "Citywide"),
        ("Valentine Day",          "2024-02-14", "ALL",       "holiday",  "Citywide"),
        ("Chinese New Year Parade","2024-02-10", "MANHATTAN", "parade",   "Chinatown"),
        ("St Patricks Day Parade", "2024-03-17", "MANHATTAN", "parade",   "5th Avenue"),
        ("Easter Sunday",          "2024-03-31", "ALL",       "holiday",  "Citywide"),
        ("Memorial Day",           "2024-05-27", "ALL",       "holiday",  "Citywide"),
        ("Puerto Rican Day Parade","2024-06-09", "MANHATTAN", "parade",   "5th Avenue"),
        ("NYC Pride March",        "2024-06-30", "MANHATTAN", "parade",   "Greenwich Village"),
    ]
    for title, date, borough, etype, loc in manual:
        all_events.append({
            "title": title, "date": date, "borough": borough,
            "type": etype, "source": "manual", "method": "manual", "location": loc,
        })

    df = pd.DataFrame(all_events)
    df["date"] = pd.to_datetime(df["date"])
    df = df.drop_duplicates(subset=["title", "date"], keep="first").sort_values("date").reset_index(drop=True)

    # Expand 'ALL' → 5 boroughs
    mask_all = df["borough"] == "ALL"
    specific = df[~mask_all].copy()
    expanded = []
    for _, row in df[mask_all].iterrows():
        for b in NYC_BOROUGHS:
            r = row.copy()
            r["borough"] = b
            expanded.append(r)

    df_expanded = pd.concat([specific, pd.DataFrame(expanded)], ignore_index=True) if expanded else specific
    df_expanded.to_csv(EVENTS_PATH, index=False)
    print(f"  ✅ Events: {len(df_expanded)} rows → {EVENTS_PATH}")
    return df_expanded


# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║  PART 1.3 — Census Data Collection                                      ║
# ╚═══════════════════════════════════════════════════════════════════════════╝

def download_census() -> pd.DataFrame:
    """Fetch ACS 5-year Census data for NYC zip codes."""
    variables = {"B01003_001E": "total_population", "B19013_001E": "median_household_income"}

    print("\n🏛️  Downloading Census Data (ACS 2019 5-year)")
    for year in [2019]:
        try:
            url = f"https://api.census.gov/data/{year}/acs/acs5"
            params = {
                "get": f"NAME,{','.join(variables.keys())}",
                "for": "zip code tabulation area:*",
                "in": "state:36",
                "key": CENSUS_API_KEY,
            }
            resp = requests.get(url, params=params, timeout=30)
            resp.raise_for_status()
            data = resp.json()
            if len(data) < 2:
                continue

            df = pd.DataFrame(data[1:], columns=data[0])
            df.rename(columns={**variables,
                               "NAME": "area_name",
                               "zip code tabulation area": "zcta"}, inplace=True)
            for col in variables.values():
                df[col] = pd.to_numeric(df[col], errors="coerce")

            df["zip_int"] = pd.to_numeric(df["zcta"], errors="coerce")
            nyc_mask = (
                ((df["zip_int"] >= 10001) & (df["zip_int"] <= 10292)) |  # Manhattan
                ((df["zip_int"] >= 10400) & (df["zip_int"] <= 10499)) |  # Bronx
                ((df["zip_int"] >= 11200) & (df["zip_int"] <= 11299)) |  # Brooklyn
                ((df["zip_int"] >= 11000) & (df["zip_int"] <= 11109)) |  # Queens
                ((df["zip_int"] >= 11350) & (df["zip_int"] <= 11499)) |  # Queens
                ((df["zip_int"] >= 10300) & (df["zip_int"] <= 10399))    # Staten Island
            )
            df_nyc = df[nyc_mask].copy()
            df_nyc.to_csv(CENSUS_PATH, index=False)
            print(f"  ✅ Census ({year}): {len(df_nyc)} NYC zip codes → {CENSUS_PATH}")
            return df_nyc
        except Exception as e:
            print(f"  ⚠️ Year {year} failed: {e}")

    print("  ❌ All census years failed")
    return pd.DataFrame()


# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║  PART 2 — Build Daily × Borough Panel                                   ║
# ╚═══════════════════════════════════════════════════════════════════════════╝

# ---------- 311 aggregation ----------
def aggregate_311_daily_borough(df_raw: pd.DataFrame, top_k: int = 8) -> pd.DataFrame:
    """Aggregate event-level 311 → daily × borough counts + top-K complaint types."""
    df = df_raw.copy()
    df.columns = df.columns.str.lower().str.strip()
    df["created_date"] = pd.to_datetime(df["created_date"], errors="coerce")

    if "unique_key" in df.columns:
        df = df.drop_duplicates(subset="unique_key")

    df = df.dropna(subset=["created_date"])
    df["date"] = df["created_date"].dt.date
    df["borough"] = df["borough"].astype("string").str.upper().str.strip()
    df = df[df["borough"].isin(NYC_BOROUGHS)]

    panel = (
        df.groupby(["date", "borough"], as_index=False)
        .agg(complaints_total=("unique_key", "count"),
             unique_complaints=("unique_key", "nunique"))
    )

    # Top-K complaint types as wide columns
    if top_k and "complaint_type" in df.columns:
        df["complaint_type"] = df["complaint_type"].astype("string").fillna("UNKNOWN").str.upper().str.strip()
        top_types = df["complaint_type"].value_counts().head(top_k).index.tolist()
        df["ctype"] = df["complaint_type"].where(df["complaint_type"].isin(top_types), "OTHER")

        ct = df.groupby(["date", "borough", "ctype"]).size().unstack(fill_value=0).reset_index()
        rename = {c: f"topk_{c.replace(' ','_').replace('/','_').replace('-','_').replace('&','AND')}_cnt"
                  for c in ct.columns if c not in ["date", "borough"]}
        ct.rename(columns=rename, inplace=True)
        panel = panel.merge(ct, on=["date", "borough"], how="left")

    return panel.sort_values(["date", "borough"]).reset_index(drop=True)


# ---------- Weather aggregation ----------
def aggregate_weather_daily(df_raw: pd.DataFrame) -> pd.DataFrame:
    """Hourly weather → daily aggregation."""
    df = df_raw.copy()
    df.columns = df.columns.str.lower().str.strip()
    df["timestamp_local"] = pd.to_datetime(df["timestamp_local"], errors="coerce")
    df = df.dropna(subset=["timestamp_local"])
    df["date"] = df["timestamp_local"].dt.date

    agg_spec = {
        "temperature_2m":    [("temp_mean", "mean"), ("temp_max", "max"), ("temp_min", "min")],
        "precipitation":     [("precipitation_sum", "sum")],
        "wind_speed_10m":    [("wind_speed_mean", "mean")],
        "cloud_cover":       [("cloud_cover_mean", "mean")],
    }

    # Optional columns
    if "rain" in df.columns:
        agg_spec["rain"] = [("rain_sum", "sum")]
    if "snowfall" in df.columns:
        agg_spec["snowfall"] = [("snowfall_sum", "sum")]
    if "wind_gusts_10m" in df.columns:
        agg_spec["wind_gusts_10m"] = [("wind_gust_mean", "mean")]

    # Build flat aggregation
    pieces = []
    for src_col, aggs in agg_spec.items():
        if src_col not in df.columns:
            continue
        for new_name, func in aggs:
            pieces.append(df.groupby("date")[src_col].agg(func).rename(new_name))

    daily = pd.concat(pieces, axis=1).reset_index()
    return daily


# ---------- Census → borough ----------
def census_to_borough(df_311_raw: pd.DataFrame, df_census: pd.DataFrame) -> pd.DataFrame:
    """Aggregate census zip-level data to borough using 311 zip→borough mapping."""
    # Clean census sentinels
    census = df_census.copy()
    for col in census.select_dtypes(exclude="object").columns:
        census[col] = census[col].replace(-666666666, np.nan)
    if "zip_int" in census.columns:
        census["zip_int"] = pd.to_numeric(census["zip_int"], errors="coerce").astype("Int64")

    # Build zip → borough map from 311
    tmp = df_311_raw.copy()
    tmp.columns = tmp.columns.str.lower().str.strip()
    tmp["borough"] = tmp["borough"].astype("string").str.upper().str.strip()
    tmp["incident_zip"] = pd.to_numeric(tmp["incident_zip"], errors="coerce").astype("Int64")
    tmp = tmp.dropna(subset=["incident_zip", "borough"])
    tmp = tmp[tmp["borough"].isin(NYC_BOROUGHS)]

    zb = (tmp.groupby(["incident_zip", "borough"]).size()
          .reset_index(name="n")
          .sort_values(["incident_zip", "n"], ascending=[True, False])
          .drop_duplicates(subset=["incident_zip"])
          .rename(columns={"incident_zip": "zip_int"})[["zip_int", "borough"]])

    census = census.merge(zb, on="zip_int", how="left").dropna(subset=["borough"])

    agg = {}
    if "median_household_income" in census.columns:
        agg["median_household_income"] = "median"
    if "total_population" in census.columns:
        agg["total_population"] = "sum"

    return (census.groupby("borough", as_index=False).agg(agg)
            .rename(columns={"median_household_income": "census_income_borough_median",
                              "total_population": "census_population_borough_sum"}))


# ---------- Airbnb → borough ----------
def airbnb_to_borough(df_raw: pd.DataFrame) -> pd.DataFrame:
    """Aggregate Airbnb listings to borough-level metrics."""
    df = df_raw.copy()

    # Handle various column name conventions from Kaggle datasets
    for candidate in ["neighbourhood group", "neighbourhood_group", "neighborhood_group"]:
        if candidate in df.columns and "borough" not in df.columns:
            df.rename(columns={candidate: "borough"}, inplace=True)
            break

    if "borough" not in df.columns:
        print("  ⚠️ Airbnb: no borough column found — skipping")
        return pd.DataFrame(columns=["borough"])

    for c in ["price", "number of reviews", "number_of_reviews", "rating"]:
        if c in df.columns:
            # Strip $ and , from price strings
            if df[c].dtype == "object":
                df[c] = df[c].astype(str).str.replace("[$,]", "", regex=True)
            df[c] = pd.to_numeric(df[c], errors="coerce")

    # Normalise review column name
    if "number of reviews" in df.columns and "number_of_reviews" not in df.columns:
        df.rename(columns={"number of reviews": "number_of_reviews"}, inplace=True)

    if "price" in df.columns:
        df = df[(df["price"] > 0) & (df["price"] < 10_000)]

    df["borough"] = df["borough"].astype("string").str.upper().str.strip()

    if "room_type" in df.columns:
        df["_entire"] = (df["room_type"].astype(str).str.lower().str.contains("entire")).astype(int)
    else:
        df["_entire"] = np.nan

    id_col = "id" if "id" in df.columns else "borough"
    price_col = "price" if "price" in df.columns else "_entire"
    reviews_col = "number_of_reviews" if "number_of_reviews" in df.columns else "_entire"
    rating_col = "rating" if "rating" in df.columns else "_entire"

    agg = df.groupby("borough", as_index=False).agg(
        airbnb_listing_count=(id_col, "count"),
        airbnb_price_mean=(price_col, "mean"),
        airbnb_price_median=(price_col, "median"),
        airbnb_rating_mean=(rating_col, "mean"),
        airbnb_total_reviews=(reviews_col, "sum"),
        airbnb_entire_home_pct=("_entire", "mean"),
    )
    return agg[agg["borough"].isin(NYC_BOROUGHS)]


# ---------- Events → daily × borough ----------
def events_to_daily_borough(df_events: pd.DataFrame) -> pd.DataFrame:
    """Create daily × borough event indicators."""
    df = df_events.copy()
    df.columns = df.columns.str.lower().str.strip()
    df["date"] = pd.to_datetime(df["date"], errors="coerce").dt.date
    df = df.dropna(subset=["date"])
    df["borough"] = df["borough"].astype("string").str.upper().str.strip()
    df = df[df["borough"].isin(NYC_BOROUGHS)]

    df["is_parade"]  = (df["type"] == "parade").astype(int)
    df["is_holiday"] = (df["type"] == "holiday").astype(int)

    return (df.groupby(["date", "borough"], as_index=False)
            .agg(event_count=("title", "count"),
                 event_has_parade=("is_parade", "max"),
                 event_has_holiday=("is_holiday", "max")))


# ---------- Feature engineering ----------
def add_features(panel: pd.DataFrame) -> pd.DataFrame:
    """Add time features, lags, rolling windows, and log target."""
    df = panel.copy()
    df["date"] = pd.to_datetime(df["date"])

    # Time features
    df["day_of_week"]  = df["date"].dt.dayofweek
    df["is_weekend"]   = (df["day_of_week"] >= 5).astype(int)
    df["month"]        = df["date"].dt.month
    df["week_of_year"] = df["date"].dt.isocalendar().week.astype(int)

    # Lags & rolling means
    df = df.sort_values(["borough", "date"])
    for col in ["temp_mean", "precipitation_sum"]:
        if col in df.columns:
            df[f"{col}_lag1"] = df.groupby("borough")[col].shift(1)
            df[f"{col}_ma7"]  = df.groupby("borough")[col].transform(
                lambda s: s.rolling(7, min_periods=3).mean())

    if "complaints_total" in df.columns:
        df["complaints_total_ma7"] = df.groupby("borough")["complaints_total"].transform(
            lambda s: s.rolling(7, min_periods=3).mean())

    # Log target
    if "complaints_total" in df.columns:
        df["log_complaints_total"] = np.log1p(df["complaints_total"])

    return df


# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║  PART 3 — Data Quality, Outliers, Imputation                            ║
# ╚═══════════════════════════════════════════════════════════════════════════╝

def detect_outliers_iqr(series: pd.Series, factor: float = 1.5):
    """Return (bool mask, lower bound, upper bound)."""
    s = series.dropna()
    if s.empty:
        return pd.Series([], dtype=bool), np.nan, np.nan
    Q1, Q3 = s.quantile(0.25), s.quantile(0.75)
    IQR = Q3 - Q1
    lo, hi = Q1 - factor * IQR, Q3 + factor * IQR
    return (s < lo) | (s > hi), float(lo), float(hi)


def run_quality_checks(df: pd.DataFrame) -> pd.DataFrame:
    """Part 3: Missing analysis, validation, outlier handling, imputation."""

    print("\n" + "=" * 80)
    print("🧪 PART 3: DATA QUALITY & PREPROCESSING")
    print("=" * 80)
    print(f"Shape: {df.shape}")

    df["date"] = pd.to_datetime(df["date"], errors="coerce")

    # ── 3.1  Missing Value Analysis ──
    missing = pd.DataFrame({
        "Count": df.isnull().sum(),
        "Pct": (df.isnull().mean() * 100).round(2),
    }).query("Count > 0").sort_values("Pct", ascending=False)

    print("\n── 3.1 Missing Values ──")
    print(missing.to_string() if not missing.empty else "  (none)")

    # ── 3.2  Validation ──
    print("\n── 3.2 Validation ──")
    if "borough" in df.columns:
        print(f"  Boroughs: {sorted(df['borough'].dropna().unique())}")
    if "date" in df.columns and "borough" in df.columns:
        dupes = df.duplicated(subset=["date", "borough"]).sum()
        print(f"  Duplicate (date, borough): {dupes}")

    # ── 3.3  Outlier detection & winsorization ──
    print("\n── 3.3 Outliers (IQR) ──")
    outlier_cols = [c for c in ["complaints_total", "temp_mean", "precipitation_sum",
                                 "wind_speed_mean", "cloud_cover_mean", "snowfall_sum"]
                    if c in df.columns]

    if outlier_cols:
        n_plots = len(outlier_cols)
        ncols = min(3, n_plots)
        nrows = (n_plots + ncols - 1) // ncols
        fig, axes = plt.subplots(nrows, ncols, figsize=(5*ncols, 4*nrows))
        axes = np.array(axes).flatten() if n_plots > 1 else [axes]

        for i, col in enumerate(outlier_cols):
            s = pd.to_numeric(df[col], errors="coerce").dropna()
            mask, lo, hi = detect_outliers_iqr(s)
            n_out = int(mask.sum())
            axes[i].boxplot(s, vert=True)
            axes[i].set_title(f"{col} ({n_out} outliers)")
            if not np.isnan(lo): axes[i].axhline(lo, ls="--", alpha=.6)
            if not np.isnan(hi): axes[i].axhline(hi, ls="--", alpha=.6)
        for j in range(len(outlier_cols), len(axes)):
            axes[j].set_visible(False)
        plt.suptitle("Outlier Detection (IQR)", fontweight="bold")
        plt.tight_layout(); plt.show()

    # Winsorise weather only (keep complaint spikes)
    for col in ["precipitation_sum", "wind_speed_mean", "snowfall_sum"]:
        if col in df.columns:
            s = pd.to_numeric(df[col], errors="coerce")
            _, lo, hi = detect_outliers_iqr(s.dropna())
            if np.isnan(lo) or np.isnan(hi):
                continue
            before = int(((s < lo) | (s > hi)).sum(skipna=True))
            df[col] = s.clip(lower=max(0, lo), upper=hi)
            print(f"  Winsorised {col}: {before} values → [{max(0,lo):.2f}, {hi:.2f}]")

    # ── 3.4  Imputation ──
    print("\n── 3.4 Imputation ──")
    before = int(df.isnull().sum().sum())

    # Lag/rolling: forward fill within borough → median
    lag_cols = [c for c in df.columns if "lag" in c.lower() or "ma7" in c.lower()]
    if "borough" in df.columns:
        for col in lag_cols:
            if df[col].isnull().any():
                df[col] = df.groupby("borough")[col].transform(lambda x: x.ffill())
                if pd.api.types.is_numeric_dtype(df[col]):
                    df[col] = df[col].fillna(df[col].median())

    # Precipitation / snow / rain: NaN → 0
    for col in ["precipitation_sum", "snowfall_sum", "rain_sum"]:
        if col in df.columns:
            df[col] = pd.to_numeric(df[col], errors="coerce").fillna(0)

    # Remaining numeric: median
    for col in df.select_dtypes(include=[np.number]).columns:
        if df[col].isnull().any():
            df[col] = df[col].fillna(df[col].median())

    after = int(df.isnull().sum().sum())
    print(f"  Missing cells: {before} → {after}")

    return df


# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║  MAIN PIPELINE                                                          ║
# ╚═══════════════════════════════════════════════════════════════════════════╝

def main():
    print("=" * 80)
    print("🚀 NYC 311 Analysis Pipeline — Jan–Jun 2024")
    print("=" * 80)

    # ---- Part 1: Data Collection ----
    df_311_raw     = download_311(START_DATE, END_DATE)
    df_weather_raw = download_weather(START_DATE, END_DATE)
    df_events_raw  = scrape_events()
    df_census_raw  = download_census()

    # Airbnb: manual upload from Kaggle
    if os.path.exists(AIRBNB_PATH):
        df_airbnb_raw = load_csv(AIRBNB_PATH)
        print(f"\n🏠 Airbnb loaded: {len(df_airbnb_raw):,} rows")
    else:
        print(f"\n⚠️ Airbnb file not found at {AIRBNB_PATH} — skipping")
        df_airbnb_raw = pd.DataFrame()

    # ---- Part 2: Build Panel ----
    print("\n" + "=" * 80)
    print("🔧 Part 2: Building Daily × Borough Panel")
    print("=" * 80)

    panel = aggregate_311_daily_borough(df_311_raw, top_k=8)
    print(f"  311 panel: {panel.shape}")

    weather_daily = aggregate_weather_daily(df_weather_raw)
    print(f"  Weather daily: {weather_daily.shape}")

    panel = panel.merge(weather_daily, on="date", how="left")

    # Census
    if not df_census_raw.empty:
        borough_census = census_to_borough(df_311_raw, df_census_raw)
        panel["borough"] = panel["borough"].astype("string").str.upper().str.strip()
        panel = panel.merge(borough_census, on="borough", how="left")

    # Airbnb
    if not df_airbnb_raw.empty:
        airbnb_boro = airbnb_to_borough(df_airbnb_raw)
        panel = panel.merge(airbnb_boro, on="borough", how="left")
        if "airbnb_listing_count" in panel.columns and "census_population_borough_sum" in panel.columns:
            panel["airbnb_per_1000_people_borough"] = (
                panel["airbnb_listing_count"] / panel["census_population_borough_sum"] * 1000)

    # Features
    panel = add_features(panel)

    # Fill precipitation NaN → 0 (before event merge)
    if "precipitation_sum" in panel.columns:
        panel["precipitation_sum"] = panel["precipitation_sum"].fillna(0)

    # Events
    events_panel = events_to_daily_borough(df_events_raw)
    panel["date"] = pd.to_datetime(panel["date"]).dt.date
    panel = panel.merge(events_panel, on=["date", "borough"], how="left")
    for col in ["event_count", "event_has_parade", "event_has_holiday"]:
        if col in panel.columns:
            panel[col] = panel[col].fillna(0).astype(int)

    # ---- Part 3: Quality & Cleaning ----
    panel = run_quality_checks(panel)

    # ---- Save Final Output ----
    panel.to_csv(FINAL_OUTPUT, index=False)
    print(f"\n{'=' * 80}")
    print(f"✅ PIPELINE COMPLETE")
    print(f"   Final shape : {panel.shape}")
    print(f"   Output file : {FINAL_OUTPUT}")
    print(f"{'=' * 80}")

    return panel


# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║  EXECUTE                                                                 ║
# ╚═══════════════════════════════════════════════════════════════════════════╝

if __name__ == "__main__":
    panel_final = main()
