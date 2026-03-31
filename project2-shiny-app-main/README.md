# TidyKit - Interactive Data Analysis Dashboard

A clean and interactive R Shiny dashboard for data loading, preprocessing, feature engineering, and exploratory data analysis. Built for Columbia University Applied Data Science STAT GR5243.

**Deployed App:** [TidyKit on shinyapps.io](https://kvd2112.shinyapps.io/tidykit/)

**GitHub Pages:** [Project Landing Page](https://github.com/Aurooora712/project2-shiny-app.git)

---

## Features

### 1. Data Loading
- Upload datasets in **CSV, Excel (.xlsx/.xls), JSON, and RDS** formats
- Two built-in sample datasets (**iris** and **mtcars**) for quick testing
- Instant dataset preview and summary statistics

### 2. Data Cleaning & Preprocessing
- **Remove duplicate rows**
- **Handle missing values**: remove rows, or impute with mean/median/mode
- **Standardize text labels**: trim whitespace and convert to lowercase
- **Outlier handling**: remove via IQR rule or cap via Winsorization (5%)
- **Feature scaling**: Z-score standardization or Min-Max normalization
- **One-hot encoding** for categorical variables
- Real-time feedback showing before/after cleaning statistics

### 3. Feature Engineering
- Apply transformations to numeric variables:
  - Log(x+1)
  - Square Root
  - Square
  - Binning (4 bins)
- Side-by-side comparison of original vs. transformed distributions
- Updated dataset preview after each transformation

### 4. Exploratory Data Analysis (EDA)
- **Histogram** for distribution analysis
- **Scatterplot** with optional linear regression line
- **Boxplot** for group comparisons
- Dynamic **summary statistics** and **correlation matrix**
- Interactive variable selection for X and Y axes

### 5. User Guide
- Built-in guided workflow as the first tab
- Step-by-step instructions for using each module
- Tips for optimal data analysis workflow

---

## Prerequisites

Install the following R packages before running the app:

```r
install.packages(c(
  "shiny",
  "ggplot2",
  "readxl",
  "jsonlite",
  "DT",
  "shinyWidgets",
  "fontawesome"
))
```

## How to Run

1. Clone this repository:
   ```bash
   git clone https://github.com/Aurooora712/project2-shiny-app.git
   cd project2-shiny-app
   ```

2. Open R or RStudio in the project directory.

3. Run the app:
   ```r
   shiny::runApp()
   ```

   This will launch TidyKit in your default web browser.

---

## Deploying to shinyapps.io

1. Install the `rsconnect` package:
   ```r
   install.packages("rsconnect")
   ```

2. Configure your shinyapps.io account:
   ```r
   rsconnect::setAccountInfo(
     name   = "YOUR_ACCOUNT_NAME",
     token  = "YOUR_TOKEN",
     secret = "YOUR_SECRET"
   )
   ```
   *(Find your token at: shinyapps.io > Account > Tokens)*

3. Deploy:
   ```r
   rsconnect::deployApp()
   ```

---

## Project Structure

```
project2-shiny-app/
├── app.R                        # Entry point (sources the final app)
├── 5243_Project2_Final.R        # Final integrated Shiny application
├── app_UI_design.R              # UI/UX design version
├── 5243_Proj2.R                 # Initial prototype
├── 1553768847-housing.csv       # Sample housing dataset
├── README.md                    # This file
├── .gitignore                   # R project ignores
├── docs/
│   └── index.html               # GitHub Pages landing page
└── report/
    └── Project2_Report.pdf      # Final project report (LaTeX)
```

---

## Team Contributions

| Member                      | Role                                                                          |
|-----------------------------|-------------------------------------------------------------------------------|
| Qixiang Fan (qf2188)       | Core analytical modules: data loading, cleaning, feature engineering, and EDA |
| Jingyang Zhang (jz3985)    | UI/UX design, layout, navigation, tooltips, and user guide                   |
| Pingyu Zhou (pz2341)       | App integration, reactivity, responsiveness, debugging, and testing           |
| Ketaki Dabade (kvd2112)    | Deployment, GitHub/README, code organization, and final report                |
