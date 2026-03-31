# Projects for Applied Data Science

This repository contains four major data science projects completed for the **GU4243/GR5243 Applied Data Science** course at Columbia University. Each project focuses on building end-to-end pipelines, from automated data acquisition to feature engineering and exploratory analysis.

## Repository Structure

The curriculum consists of four projects in total:

### 1. NYC 311 Complaint Analysis (Jan–Jun 2024)
A multi-source integration project investigating the drivers of urban service requests in New York City.

* **Goal**: Analyze the impact of weather, public events, and socio-economic factors on 311 volumes.
* **Data Sources**: Socrata API (311 records), Open-Meteo API (weather), BeautifulSoup scraping (NYC events), and US Census data.
* **Key Features**: Includes cyclical temporal encodings, lagged complaint history, and robust anomaly detection.

### 2. TidyKit — Interactive Data Analysis Dashboard
An R Shiny dashboard for data loading, preprocessing, feature engineering, and exploratory data analysis.

* **Goal**: Provide a clean, guided interface for end-to-end tabular data exploration — from upload through cleaning, transformation, and visualization.
* **Tech Stack**: R, Shiny, ggplot2, readxl, jsonlite, DT, shinyWidgets.
* **Key Features**: Supports CSV/Excel/JSON/RDS uploads, missing value imputation (mean/median/mode), outlier handling (IQR removal, Winsorization), feature scaling (Z-score, Min-Max), one-hot encoding, log/sqrt/binning transformations, and interactive EDA (histograms, scatterplots, boxplots, correlation matrices).
* **Deployed App**: [TidyKit on shinyapps.io](LINK_HERE)

### 3. Project 3
*Details coming soon.*

### 4. Project 4
*Details coming soon.*

## Core Environment

* **Language**: Python 3.8+ (Projects 1, 3, 4), R (Project 2)
* **Libraries**: `pandas`, `numpy`, `scikit-learn`, `matplotlib`, `seaborn`, `beautifulsoup4`, `statsmodels` (Python); `shiny`, `ggplot2`, `readxl`, `jsonlite`, `DT` (R)
