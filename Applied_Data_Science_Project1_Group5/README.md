# NYC 311 Complaint Analysis

**Course:** GU4243/GR5243 Applied Data Science  
**Project 1 — Team 5**  
Ketaki Dabade (kvd2112) · Junye Chen (jc6636) · Rui Lin (rl3445) · Xiao Xiao (xx2492)

---

## Project Description

This project fulfills the requirements of **Project 1: Data Acquisition, Cleaning, Preprocessing and Feature Engineering for Exploratory Analysis**. The objective is to acquire data from multiple sources, perform data cleaning and EDA, engineer meaningful features, and produce a well-documented report summarizing findings and methodology.

New York City's 311 system is the primary channel through which residents report non-emergency issues such as noise complaints, illegal parking, heating failures, and unsanitary conditions. We analyze 311 complaints from January through June 2024 by integrating five heterogeneous data sources into a unified **daily × borough** panel dataset (~840 rows, 40+ variables), investigating how weather, public events, demographics, and housing markets drive complaint volumes across the five boroughs.

## Project Requirements Mapping

| Requirement | Where Addressed |
|-------------|-----------------|
| **1. Data Acquisition** — multiple sources, APIs, web scraping, public repos | `data_acquisition_cleaning_preprocessing.py` — Socrata API, Open-Meteo API, Census API, BeautifulSoup scraping, Kaggle dataset |
| **2. Data Cleaning** — inconsistencies, formatting, duplicates, outliers, missing values | `data_acquisition_cleaning_preprocessing.py` Part 3 + notebook Section 3 |
| **3. EDA** — summary stats, visualizations, patterns, correlations, anomalies | Notebook Sections 3–4 (20+ figures, anomaly detection, correlation/VIF/PCA) |
| **4. Feature Engineering** — normalization, encoding, new features, justification | Notebook Section 5 (cyclical encodings, lags, interactions, 4 scaling variants) |
| **5. Report** — structured PDF with all sections and team contributions | `STAT5243_Project1_Team5.pdf` via Overleaf |

## Repository Structure

```
├── data_acquisition_cleaning_preprocessing.py   ← Data collection & panel building
├── Project1_Section3_Section4_Final.ipynb        ← EDA & feature engineering
├── new_york_listings_2024.csv                    ← Airbnb data (you provide)
├── data/                                         ← Raw & processed data
├── outputs_task3_task4/                           ← Figures, tables & model matrices
└── README.md
```

## Data Sources

| Source | Method | Scale |
|--------|--------|-------|
| NYC 311 Requests | Socrata API (paginated, 50K/request) | ~1.5M complaint records |
| Weather | Open-Meteo Archive API | ~4,300 hourly observations |
| NYC Events | BeautifulSoup scraping + NYC Open Data API + manual curation | ~300 borough-days flagged |
| U.S. Census ACS 2019 | Census Bureau API | ~200 NYC ZCTAs |
| Airbnb Listings | Kaggle CSV (manual upload) | ~100K listings |

## Prerequisites

**Python 3.8+** with the following packages:

```bash
pip install pandas numpy requests matplotlib seaborn beautifulsoup4 scikit-learn statsmodels
```

## Setup

1. Download the Airbnb dataset from [Kaggle](https://www.kaggle.com/datasets/arianazmoudeh/airbnbopendata)
2. Rename the file to `new_york_listings_2024.csv` and place it in the project root directory
3. All other datasets are fetched automatically via APIs — no additional setup needed

## How to Run

### Step 1: Data Acquisition, Cleaning & Preprocessing

```bash
python data_acquisition_cleaning_preprocessing.py
```

Estimated runtime: **30–40 minutes** (dominated by 311 API pagination).

This script executes the full data pipeline:

- **Part 1 — Data Collection**
  - Downloads ~1.5M 311 complaints via Socrata API with controlled pagination and rate limiting
  - Fetches hourly weather data from Open-Meteo and aggregates to daily summaries
  - Scrapes NYC Tourism website with BeautifulSoup, queries NYC Open Data permitted events API, and supplements with manually curated holidays and parades
  - Retrieves 2019 ACS 5-year census estimates (population, income) for NYC ZIP codes
  - Reads Airbnb listings and aggregates to borough-level market indicators

- **Part 2 — Panel Construction**
  - Aggregates 311 records to daily × borough complaint counts with top-8 complaint type breakdowns
  - Merges all five sources by date, borough, or both
  - Engineers calendar features (day-of-week, weekend, month), lag/rolling features (1-day lag, 7-day moving average), and a log-transformed target variable
  - Computes derived metrics such as Airbnb density per 1,000 residents

- **Part 3 — Data Quality**
  - Missing value analysis with column-level counts and percentages
  - Validation of borough encoding, date completeness, numeric ranges, and duplicate checks
  - IQR-based outlier detection with winsorization of weather variables (preserving complaint spikes)
  - Context-aware imputation: forward-fill for lag features, zero-fill for precipitation, median for remaining numerics

**Output:** `data/processed/Daily Borough Events Panel.csv`

### Step 2: EDA & Feature Engineering

```bash
jupyter notebook Project1_Section3_Section4_Final.ipynb
```

The notebook reads the panel CSV and performs two major phases:

- **Sections 3–4 — Exploratory Data Analysis**
  - Descriptive statistics and auto-generated data dictionary
  - Citywide anomaly detection using robust Z-scores (median + MAD)
  - Spatial patterns: complaint distributions and composition by borough (box/violin plots, stacked bars, heatmaps)
  - Temporal dynamics: daily time series, 7-day rolling trends, monthly aggregation, day-of-week and weekend effects
  - Event and weather effects: event-day vs. non-event comparison, temperature/precipitation scatter plots
  - Correlation diagnostics: heatmap, VIF multicollinearity check, influence diagnostics (Cook's distance, DFFITS, leverage), PCA visualization

- **Section 5 — Feature Engineering**
  - Cyclical sin/cos encodings for day-of-week and month
  - Lagged complaint history and rolling weather context
  - Weather regime indicators (hot/cold/rainy), precipitation transforms, temperature bins
  - Complaint composition features: lagged top-type shares, Herfindahl concentration index
  - Interaction terms: weekend × weather, event × precipitation, borough × temperature
  - Two imputation strategies: EDA-friendly (bidirectional fill) and time-safe (forward-only, no future leakage)
  - Model matrix construction with one-hot encoding, zero-variance filtering, and four scaling variants (raw, standardized, min-max, Yeo–Johnson power)

**Outputs:** Processed datasets, model-ready matrices, and all figures/tables saved to `outputs_task3_task4/`

## Research Questions

1. **Weather Effects** — Do temperature extremes, precipitation, or wind speed significantly increase daily complaints?
2. **Temporal Patterns** — How do complaints vary by day of week, month, and season?
3. **Borough Differences** — Are complaint rate differences driven by population, income, or housing density?
4. **Event Effects** — Are event days associated with significant changes in complaint volumes?
5. **Predictive Features** — Which engineered features best predict daily complaint counts?
