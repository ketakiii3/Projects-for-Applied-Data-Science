
library(shiny)
library(ggplot2)
library(readxl)
library(jsonlite)
library(DT)
library(shinyWidgets)
library(fontawesome)


# Helper functions

load_data <- function(file, builtin) {
  if (!is.null(builtin) && builtin != "None") {
    if (builtin == "iris") return(iris)
    if (builtin == "mtcars") {
      d <- mtcars
      d$car <- rownames(d)
      rownames(d) <- NULL
      return(d)
    }
  }
  if (is.null(file)) return(NULL)
  ext  <- tolower(tools::file_ext(file$name))
  path <- file$datapath

  if (ext == "csv") {
    read.csv(path, stringsAsFactors = FALSE)
  } else if (ext %in% c("xlsx", "xls")) {
    as.data.frame(read_excel(path))
  } else if (ext == "json") {
    as.data.frame(fromJSON(path))
  } else if (ext == "rds") {
    readRDS(path)
  } else {
    NULL
  }
}

safe_mode <- function(x) {
  x2 <- x[!is.na(x)]
  if (length(x2) == 0) return(NA)
  tbl <- sort(table(x2), decreasing = TRUE)
  mode_raw <- names(tbl)[1]
  if (is.numeric(x)) return(as.numeric(mode_raw))
  if (is.logical(x)) return(as.logical(mode_raw))
  mode_raw
}

clip_outliers <- function(x) {
  if (!is.numeric(x)) return(x)
  lo <- quantile(x, 0.05, na.rm = TRUE, names = FALSE)
  hi <- quantile(x, 0.95, na.rm = TRUE, names = FALSE)
  pmax(pmin(x, hi), lo)
}

`%||%` <- function(x, y) if (is.null(x)) y else x

safe_num_summary <- function(x, fun, default = NA_real_) {
  x <- suppressWarnings(as.numeric(x))
  x <- x[is.finite(x)]
  if (length(x) == 0) return(default)
  fun(x)
}

safe_cor_value <- function(x, y) {
  x <- suppressWarnings(as.numeric(x))
  y <- suppressWarnings(as.numeric(y))
  ok <- is.finite(x) & is.finite(y)
  if (sum(ok) < 2) return(NA_real_)
  suppressWarnings(cor(x[ok], y[ok]))
}

safe_slider_bounds <- function(x) {
  x <- suppressWarnings(as.numeric(x))
  x <- x[is.finite(x)]
  if (length(x) == 0) return(c(0, 1))
  rng <- range(x)
  if (rng[1] == rng[2]) rng <- c(rng[1] - 1, rng[2] + 1)
  c(floor(rng[1]), ceiling(rng[2]))
}

is_discrete_numeric <- function(x, max_unique = 8) {
  is.numeric(x) && length(unique(x[!is.na(x)])) <= max_unique
}

cleaning_changes <- function(before_df, after_df, scaled_cols, encoded_cols, outlier_cols) {
  before_missing <- sum(is.na(before_df))
  after_missing  <- sum(is.na(after_df))
  before_dup <- sum(duplicated(before_df))
  after_dup  <- sum(duplicated(after_df))
  c(
    paste("Rows:", nrow(before_df), "→", nrow(after_df)),
    paste("Columns:", ncol(before_df), "→", ncol(after_df)),
    paste("Missing values:", before_missing, "→", after_missing),
    paste("Duplicate rows:", before_dup, "→", after_dup),
    paste("Scaled columns:", if (length(scaled_cols)) paste(scaled_cols, collapse = ", ") else "None"),
    paste("Encoded categorical columns:", if (length(encoded_cols)) paste(encoded_cols, collapse = ", ") else "None"),
    paste("Outlier-treated numeric columns:", if (length(outlier_cols)) paste(outlier_cols, collapse = ", ") else "None")
  )
}

svg_icon <- function(type, size = 64) {
  blue_main <- "#2E69A8"
  blue_light <- "#76AEE6"

  svg <- switch(
    type,
    "logo" = sprintf('
      <svg width="%d" height="%d" viewBox="0 0 64 64" fill="none" xmlns="http://www.w3.org/2000/svg">
        <path d="M14 48V18" stroke="white" stroke-width="3" stroke-linecap="round"/>
        <path d="M14 48H50" stroke="white" stroke-width="3" stroke-linecap="round"/>
        <rect x="20" y="34" width="6" height="14" rx="2" fill="white" opacity="0.95"/>
        <rect x="30" y="28" width="6" height="20" rx="2" fill="white" opacity="0.95"/>
        <rect x="40" y="22" width="6" height="26" rx="2" fill="white" opacity="0.95"/>
        <path d="M20 24L28 20L36 26L46 16" stroke="white" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/>
      </svg>', size, size),
    "loading" = sprintf('
      <svg width="%d" height="%d" viewBox="0 0 64 64" fill="none" xmlns="http://www.w3.org/2000/svg">
        <path d="M18 46H46" stroke="%s" stroke-width="5" stroke-linecap="round"/>
        <path d="M32 18V38" stroke="%s" stroke-width="5" stroke-linecap="round"/>
        <path d="M22 28L32 18L42 28" stroke="%s" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"/>
        <circle cx="18" cy="46" r="2.6" fill="%s"/>
        <circle cx="46" cy="46" r="2.6" fill="%s"/>
      </svg>', size, size, blue_main, blue_main, blue_main, blue_main, blue_main),
    "eda" = sprintf('
      <svg width="%d" height="%d" viewBox="0 0 64 64" fill="none" xmlns="http://www.w3.org/2000/svg">
        <path d="M14 48V18" stroke="%s" stroke-width="3" stroke-linecap="round"/>
        <path d="M14 48H50" stroke="%s" stroke-width="3" stroke-linecap="round"/>
        <rect x="20" y="34" width="6" height="14" rx="2" fill="%s"/>
        <rect x="30" y="28" width="6" height="20" rx="2" fill="%s"/>
        <rect x="40" y="22" width="6" height="26" rx="2" fill="%s"/>
        <path d="M20 24L28 20L36 26L46 16" stroke="%s" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/>
      </svg>', size, size, blue_main, blue_main, blue_light, "#86BDF2", blue_main, blue_light),
    "guide" = sprintf('
      <svg width="%d" height="%d" viewBox="0 0 64 64" fill="none" xmlns="http://www.w3.org/2000/svg">
        <rect x="16" y="12" width="32" height="40" rx="6" stroke="%s" stroke-width="3"/>
        <path d="M24 22H40" stroke="%s" stroke-width="3" stroke-linecap="round"/>
        <path d="M24 30H40" stroke="%s" stroke-width="3" stroke-linecap="round"/>
        <path d="M24 38H34" stroke="%s" stroke-width="3" stroke-linecap="round"/>
        <path d="M42 44C42 46.5 44 48.5 46 50" stroke="%s" stroke-width="3" stroke-linecap="round"/>
      </svg>', size, size, blue_main, blue_light, blue_light, blue_light, blue_light),
    ""
  )
  HTML(svg)
}



# UI

ui <- fluidPage(
  tags$head(
    tags$style(HTML("
      body {
        background: linear-gradient(180deg, #eef6ff 0%, #dcecff 100%);
        font-family: 'Arial', 'Helvetica', sans-serif;
        color: #12385f;
      }
      .container-fluid {
        padding-left: 18px;
        padding-right: 18px;
      }
      .top-banner {
        background: #1F4E82;
        color: white;
        padding: 30px 28px 36px 28px;
        border-radius: 0 0 28px 28px;
        box-shadow: 0 10px 28px rgba(31, 78, 130, 0.20);
        margin-bottom: 26px;
      }
      .app-title-wrap {
        display: flex;
        align-items: center;
        gap: 16px;
        margin-bottom: 10px;
      }
      .title-logo {
        width: 54px;
        height: 54px;
        display: flex;
        align-items: center;
        justify-content: center;
        background: rgba(255,255,255,0.14);
        border-radius: 16px;
        padding: 6px;
      }
      .app-title-text {
        font-size: 42px;
        font-weight: 800;
        color: white;
        line-height: 1.1;
      }
      .app-subtitle {
        font-size: 17px;
        line-height: 1.7;
        max-width: 900px;
        opacity: 0.97;
        color: white;
      }
      .hero-card {
        background: linear-gradient(135deg, #5fa7e8 0%, #7cbaf0 55%, #a8d2f7 100%);
        color: white;
        border-radius: 28px;
        padding: 38px 32px;
        box-shadow: 0 14px 30px rgba(83, 154, 220, 0.18);
        margin-bottom: 30px;
      }
      .hero-title {
        font-size: 44px;
        font-weight: 800;
        line-height: 1.18;
        margin-bottom: 14px;
      }
      .hero-text {
        font-size: 18px;
        line-height: 1.8;
        max-width: 900px;
        opacity: 0.98;
      }
      .section-title {
        font-size: 24px;
        font-weight: 800;
        color: #163e68;
        margin-top: 8px;
        margin-bottom: 16px;
      }
      .feature-card {
        background: linear-gradient(180deg, #ffffff 0%, #f5faff 100%);
        border-radius: 24px;
        padding: 24px 22px;
        box-shadow: 0 10px 24px rgba(23, 67, 114, 0.08);
        border: 1px solid #dbeeff;
        min-height: 280px;
        margin-bottom: 24px;
        transition: all 0.25s ease;
      }
      .feature-card:hover {
        transform: translateY(-4px);
        box-shadow: 0 16px 28px rgba(23, 67, 114, 0.13);
      }
      .feature-svg {
        width: 72px;
        height: 72px;
        margin-bottom: 16px;
        display: flex;
        align-items: center;
        justify-content: center;
        background: transparent;
        border-radius: 18px;
      }
      .feature-title {
        font-size: 20px;
        font-weight: 800;
        color: #163f69;
        margin-bottom: 10px;
      }
      .feature-text {
        font-size: 15px;
        line-height: 1.7;
        color: #4a6784;
      }
      .panel-card {
        background: #ffffff;
        border-radius: 24px;
        padding: 24px;
        box-shadow: 0 10px 26px rgba(22, 68, 116, 0.09);
        border: 1px solid #e0efff;
        margin-bottom: 24px;
      }
      .panel-title {
        font-size: 21px;
        font-weight: 800;
        color: #123c67;
        margin-bottom: 14px;
      }
      .help-note {
        background: linear-gradient(180deg, #eef8ff 0%, #e6f3ff 100%);
        border-left: 5px solid #4e96dd;
        padding: 14px 16px;
        border-radius: 12px;
        color: #355472;
        margin-top: 10px;
        line-height: 1.65;
      }
      .shiny-input-container {
        margin-bottom: 16px;
      }
      .btn, .btn-default, .btn-primary {
        background: linear-gradient(135deg, #1d5f9f 0%, #4a97df 100%) !important;
        color: white !important;
        border: none !important;
        border-radius: 12px !important;
        padding: 10px 18px !important;
        font-weight: 700 !important;
        box-shadow: 0 6px 14px rgba(34, 95, 155, 0.18);
      }
      .btn:hover, .btn:focus {
        opacity: 0.95 !important;
      }
      .nav-tabs {
        border-bottom: none;
        margin-bottom: 20px;
      }
      .nav-tabs > li > a {
        border: none !important;
        border-radius: 14px !important;
        background: #e9f4ff;
        color: #1e517f !important;
        margin-right: 8px;
        font-weight: 700;
        padding: 10px 18px;
      }
      .nav-tabs > li.active > a,
      .nav-tabs > li.active > a:hover,
      .nav-tabs > li.active > a:focus {
        background: linear-gradient(135deg, #1a568d 0%, #519be0 100%) !important;
        color: white !important;
      }
      .form-control, .selectize-input {
        border-radius: 12px !important;
        border: 1px solid #d2e6fb !important;
        box-shadow: none !important;
      }
      .well {
        background: #f7fbff !important;
        border: 1px solid #e1efff !important;
        border-radius: 18px !important;
      }
      table { background: white; }
      pre {
        background: #f8fbff;
        border: 1px solid #e4f0ff;
        border-radius: 14px;
        padding: 14px;
      }
      .control-row {
        display:flex;
        gap:10px;
        margin-top:8px;
        margin-bottom:10px;
        flex-wrap:wrap;
      }
      .small-note {
        font-size: 12px;
        color: #5b7692;
      }
    "))
  ),

  div(
    class = "top-banner",
    div(
      class = "app-title-wrap",
      div(class = "title-logo", svg_icon("logo", 48)),
      span(class = "app-title-text", "TidyKit")
    ),
    div(
      class = "app-subtitle",
      "A clean and interactive dashboard for data loading, preprocessing, feature engineering, and exploratory analysis."
    )
  ),

  div(
    class = "hero-card",
    div(class = "hero-title", "Welcome to TidyKit"),
    div(
      class = "hero-text",
      "Upload, clean, transform, and visualize your datasets in one place. TidyKit is designed to guide users step by step through an automated and intuitive data workflow."
    )
  ),

  div(class = "section-title", "Core Modules"),

  fluidRow(
    column(4, div(class = "feature-card",
                  div(class = "feature-svg", svg_icon("loading", 56)),
                  div(class = "feature-title", "Data Loading"),
                  div(class = "feature-text", "Import CSV, Excel, JSON, or RDS files, or choose a built-in dataset for quick testing."))),
    column(4, div(class = "feature-card",
                  div(class = "feature-svg", icon("broom", class = "fa-3x", style = "color:#2E69A8;")),
                  div(class = "feature-title", "Data Cleaning"),
                  div(class = "feature-text", "Handle duplicates, missing values, outliers, scaling, and categorical encoding through an intuitive interface."))),
    column(4, div(class = "feature-card",
                  div(class = "feature-svg", icon("wrench", class = "fa-3x", style = "color:#2E69A8;")),
                  div(class = "feature-title", "Feature Engineering"),
                  div(class = "feature-text", "Create transformed or combined variables with real-time visual feedback.")))
  ),

  fluidRow(
    column(6, div(class = "feature-card",
                  div(class = "feature-svg", svg_icon("eda", 56)),
                  div(class = "feature-title", "EDA"),
                  div(class = "feature-text", "Inspect distributions, variable relationships, dynamic insights, and filtered views with clean, accessible visualizations."))),
    column(6, div(class = "feature-card",
                  div(class = "feature-svg", svg_icon("guide", 56)),
                  div(class = "feature-title", "User Guide"),
                  div(class = "feature-text", "A guided workflow helps users understand where to start, what to do next, and how to interpret results.")))
  ),

  br(),

  tabsetPanel(
    tabPanel(
      "User Guide",
      div(
        class = "panel-card",
        div(class = "panel-title", "How to Use TidyKit"),
        tags$ol(
          tags$li("Go to Data Loading and upload a file or choose a built-in dataset."),
          tags$li("Preview the raw data and inspect the summary output."),
          tags$li("Use Data Cleaning to handle missing values, duplicates, outliers, scaling, and encoding."),
          tags$li("Use Feature Engineering to create transformed or combined variables."),
          tags$li("Use EDA to visualize distributions, relationships, filters, and insights.")
        ),
        div(class = "help-note", tags$b("Using Sample Data: "),
            "In the Data Loading tab, users can choose one of the two built-in sample datasets, iris or mtcars. The app updates automatically after selection."),
        div(class = "help-note", tags$b("Tip: "),
            "Use the reset buttons in EDA to quickly restore the default settings for a smooth demo flow.")
      )
    ),

    tabPanel(
      "Data Loading",
      fluidRow(
        column(
          4,
          div(class = "panel-card",
              div(class = "panel-title", "Upload Dataset"),
              fileInput("file", "Choose a file", accept = c(".csv", ".xlsx", ".xls", ".json", ".rds")),
              selectInput("builtin", "Or choose a built-in dataset", choices = c("None", "iris", "mtcars")),
              div(class = "help-note", "Supported formats: CSV, Excel, JSON, and RDS. The app updates automatically."))
        ),
        column(
          8,
          div(class = "panel-card",
              div(class = "panel-title", "Dataset Preview"),
              addSpinner(DTOutput("rawTable"), color = "#2E69A8")),
          div(class = "panel-card",
              div(class = "panel-title", "Summary Statistics"),
              addSpinner(verbatimTextOutput("rawSummary"), color = "#2E69A8"))
        )
      )
    ),

    tabPanel(
      "Data Cleaning",
      fluidRow(
        column(
          4,
          div(
            class = "panel-card",
            div(class = "panel-title", "Cleaning Controls"),
            checkboxInput("remove_duplicates", "Remove duplicate rows", FALSE),
            radioButtons("missing_strategy", "Missing value handling",
                         choices = c("None", "Remove Rows", "Impute with Mean", "Impute with Median", "Impute with Mode")),
            checkboxInput("standardize_labels", "Standardize text labels", FALSE),
            radioButtons("outlier_strategy", "Outlier handling",
                         choices = c("None", "Remove (IQR rule)", "Cap (Winsorize 5%)")),
            uiOutput("clean_outlier_cols_ui"),
            radioButtons("scaling", "Scale numeric features",
                         choices = c("None", "Standardize (Z-score)", "Normalize (Min-Max)")),
            uiOutput("clean_scale_cols_ui"),
            checkboxInput("encode_cat", "One-hot encode categorical features", FALSE),
            uiOutput("clean_encode_cols_ui"),
            div(class = "help-note", "Cleaning updates automatically and shows before/after feedback.")
          )
        ),
        column(
          8,
          fluidRow(
            column(4, wellPanel(strong("Rows"), textOutput("clean_rows"))),
            column(4, wellPanel(strong("Missing Values"), textOutput("clean_missing"))),
            column(4, wellPanel(strong("Duplicate Rows"), textOutput("clean_duplicates")))
          ),
          div(class = "panel-card",
              div(class = "panel-title", "Cleaned Dataset"),
              addSpinner(DTOutput("cleanTable"), color = "#2E69A8")),
          div(class = "panel-card",
              div(class = "panel-title", "Cleaned Data Summary"),
              addSpinner(verbatimTextOutput("cleanSummary"), color = "#2E69A8")),
          div(class = "panel-card",
              div(class = "panel-title", "Cleaning Log"),
              verbatimTextOutput("cleanLog"))
        )
      )
    ),

    tabPanel(
      "Feature Engineering",
      fluidRow(
        column(
          4,
          div(
            class = "panel-card",
            div(class = "panel-title", "Transformation Controls"),
            radioButtons("fe_mode", "Feature Engineering Mode:",
                         choices = c("Single-variable transformation", "Two-variable feature creation")),
            uiOutput("fe_var_select"),
            conditionalPanel(
              "input.fe_mode == 'Single-variable transformation'",
              radioButtons("fe_transformation", "Choose transformation",
                           choices = c("Log(x+1)", "Square Root", "Square", "Binning", "Z-score")),
              conditionalPanel("input.fe_transformation == 'Binning'",
                               sliderInput("fe_bins", "Number of bins:", min = 3, max = 10, value = 4))
            ),
            conditionalPanel(
              "input.fe_mode == 'Two-variable feature creation'",
              radioButtons("fe_pair_transformation", "Choose new feature",
                           choices = c("Interaction (X1 * X2)", "Ratio (X1 / X2)"))
            ),
            textInput("fe_new_name", "New feature name:", value = "engineered_feature"),
            div(class = "help-note", "Feature engineering updates automatically with explanation, statistics, and visual feedback.")
          )
        ),
        column(
          8,
          fluidRow(
            column(6, div(class = "panel-card",
                          div(class = "panel-title", "Transformation Explanation"),
                          verbatimTextOutput("fe_explanation"))),
            column(6, div(class = "panel-card",
                          div(class = "panel-title", "Before vs After Stats"),
                          tableOutput("fe_stats")))
          ),
          div(class = "panel-card",
              div(class = "panel-title", "Comparison Plot"),
              addSpinner(plotOutput("fe_histPlot"), color = "#2E69A8")),
          div(class = "panel-card",
              div(class = "panel-title", "Updated Dataset"),
              addSpinner(DTOutput("fe_table"), color = "#2E69A8"))
        )
      )
    ),

    tabPanel(
      "EDA",
      fluidRow(
        column(
          4,
          div(
            class = "panel-card",
            div(class = "panel-title", "EDA Controls"),
            uiOutput("eda_var_select"),
            radioButtons("plot_type", "Choose plot type",
                         choices = c("Histogram", "Scatter", "Boxplot", "Density", "Bar Chart")),
            conditionalPanel(
              "input.plot_type == 'Histogram'",
              sliderInput("eda_bins", "Histogram bins:", min = 5, max = 60, value = 30)
            ),
            conditionalPanel(
              "input.plot_type == 'Scatter'",
              sliderInput("eda_alpha", "Point transparency:", min = 0.1, max = 1, value = 0.6, step = 0.1),
              sliderInput("eda_size", "Point size:", min = 1, max = 5, value = 2, step = 0.5),
              checkboxInput("add_lm", "Add linear regression line", FALSE)
            ),
            conditionalPanel(
              "input.plot_type == 'Scatter' || input.plot_type == 'Boxplot'",
              uiOutput("eda_y_ui")
            ),
            selectInput("eda_color", "Color by (optional):", choices = c("None")),
            selectInput("eda_facet", "Facet by (optional):", choices = c("None")),
            div(class = "control-row",
                actionButton("reset_eda", "Reset EDA Controls"),
                actionButton("reset_filters", "Reset Filters")),
            div(class = "small-note", "Controls update dynamically based on your plot selection."),
            hr(),
            h4("Dataset Filters"),
            uiOutput("eda_filter_numeric_ui"),
            uiOutput("eda_filter_cat_ui")
          )
        ),
        column(
          8,
          div(
            class = "panel-card",
            div(
              style = "display:flex; gap:14px; margin-bottom:14px; flex-wrap:wrap;",
              div(style = "flex:1; min-width:180px; padding:12px 16px; border:1px solid #ddd; border-radius:10px; background:#fafafa;",
                  tags$div(style = "font-size:13px; color:#666; margin-bottom:6px;", "Filtered Rows"),
                  htmlOutput("eda_n")),
              div(style = "flex:1.2; min-width:220px; padding:12px 16px; border:1px solid #ddd; border-radius:10px; background:#fafafa;",
                  tags$div(style = "font-size:13px; color:#666; margin-bottom:6px;", "Recommended Plot"),
                  htmlOutput("edaRecommend")),
              div(style = "flex:1; min-width:220px; padding:12px 16px; border:1px solid #ddd; border-radius:10px; background:#fafafa;",
                  tags$div(style = "font-size:13px; color:#666; margin-bottom:6px;", "Dynamic Insight"),
                  htmlOutput("edaInsight")),
              div(style = "flex:1; min-width:220px; padding:12px 16px; border:1px solid #ddd; border-radius:10px; background:#fafafa;",
                  tags$div(style = "font-size:13px; color:#666; margin-bottom:6px;", "Current Variables"),
                  htmlOutput("edaVars"))
            )
          ),
          div(class = "panel-card",
              div(class = "panel-title", "Visualization"),
              addSpinner(plotOutput("edaPlot", height = "460px"), color = "#2E69A8")),
          div(class = "panel-card",
              div(class = "panel-title", "Summary"),
              addSpinner(verbatimTextOutput("edaSummary"), color = "#2E69A8")),
          div(class = "panel-card",
              div(class = "panel-title", "Correlation Matrix"),
              addSpinner(verbatimTextOutput("edaCorr"), color = "#2E69A8"))
        )
      )
    )
  )
)



# Server

server <- function(input, output, session) {
  dataset <- reactive({
    load_data(input$file, input$builtin)
  })

  output$rawTable <- renderDT({
    req(dataset())
    datatable(head(dataset(), 20), options = list(scrollX = TRUE, pageLength = 10))
  })

  output$rawSummary <- renderPrint({
    req(dataset())
    summary(dataset())
  })

  output$clean_scale_cols_ui <- renderUI({
    req(dataset())
    num_cols <- names(dataset())[sapply(dataset(), is.numeric)]
    checkboxGroupInput("scale_cols", "Columns to scale:", choices = num_cols, selected = num_cols)
  })

  output$clean_outlier_cols_ui <- renderUI({
    req(dataset())
    num_cols <- names(dataset())[sapply(dataset(), is.numeric)]
    checkboxGroupInput("outlier_cols", "Columns for outlier handling:", choices = num_cols, selected = num_cols)
  })

  output$clean_encode_cols_ui <- renderUI({
    req(dataset())
    cat_cols <- names(dataset())[sapply(dataset(), function(x) is.character(x) || is.factor(x))]
    checkboxGroupInput("encode_cols", "Categorical columns to encode:", choices = cat_cols, selected = cat_cols)
  })

  cleaning_result <- reactive({
    req(dataset())
    df_before <- dataset()
    df <- df_before
    num_cols <- names(df)[sapply(df, is.numeric)]
    cat_cols <- names(df)[sapply(df, function(x) is.character(x) || is.factor(x))]

    scale_cols <- intersect(input$scale_cols %||% character(0), num_cols)
    outlier_cols <- intersect(input$outlier_cols %||% character(0), num_cols)
    encode_cols <- intersect(input$encode_cols %||% character(0), cat_cols)

    log_lines <- c("Cleaning pipeline executed automatically:")

    if (isTRUE(input$remove_duplicates)) {
      removed_dup <- sum(duplicated(df))
      df <- df[!duplicated(df), , drop = FALSE]
      log_lines <- c(log_lines, paste("- Removed", removed_dup, "duplicate rows."))
    }

    if (input$missing_strategy == "Remove Rows") {
      before_n <- nrow(df)
      df <- na.omit(df)
      log_lines <- c(log_lines, paste("- Removed", before_n - nrow(df), "rows containing missing values."))
    } else if (input$missing_strategy == "Impute with Mean") {
      for (col in num_cols) {
        miss_n <- sum(is.na(df[[col]]))
        if (miss_n > 0) {
          df[[col]][is.na(df[[col]])] <- mean(df[[col]], na.rm = TRUE)
          log_lines <- c(log_lines, paste("- Imputed", miss_n, "missing values in", col, "with mean."))
        }
      }
    } else if (input$missing_strategy == "Impute with Median") {
      for (col in num_cols) {
        miss_n <- sum(is.na(df[[col]]))
        if (miss_n > 0) {
          df[[col]][is.na(df[[col]])] <- median(df[[col]], na.rm = TRUE)
          log_lines <- c(log_lines, paste("- Imputed", miss_n, "missing values in", col, "with median."))
        }
      }
    } else if (input$missing_strategy == "Impute with Mode") {
      for (col in names(df)) {
        miss_n <- sum(is.na(df[[col]]))
        if (miss_n > 0) {
          fill_value <- safe_mode(df[[col]])
          df[[col]][is.na(df[[col]])] <- fill_value
          log_lines <- c(log_lines, paste("- Imputed", miss_n, "missing values in", col, "with mode."))
        }
      }
    }

    if (isTRUE(input$standardize_labels) && length(cat_cols) > 0) {
      for (col in cat_cols) df[[col]] <- trimws(tolower(as.character(df[[col]])))
      log_lines <- c(log_lines, paste("- Standardized text in", length(cat_cols), "categorical columns."))
    }

    if (input$outlier_strategy == "Remove (IQR rule)" && length(outlier_cols) > 0) {
      keep <- rep(TRUE, nrow(df))
      for (col in outlier_cols) {
        q1 <- quantile(df[[col]], 0.25, na.rm = TRUE, names = FALSE)
        q3 <- quantile(df[[col]], 0.75, na.rm = TRUE, names = FALSE)
        iqr <- q3 - q1
        keep <- keep & (df[[col]] >= q1 - 1.5 * iqr & df[[col]] <= q3 + 1.5 * iqr | is.na(df[[col]]))
      }
      removed_n <- sum(!keep)
      df <- df[keep, , drop = FALSE]
      log_lines <- c(log_lines, paste("- Removed", removed_n, "rows using IQR outlier rule on selected numeric columns."))
    } else if (input$outlier_strategy == "Cap (Winsorize 5%)" && length(outlier_cols) > 0) {
      for (col in outlier_cols) df[[col]] <- clip_outliers(df[[col]])
      log_lines <- c(log_lines, paste("- Winsorized", length(outlier_cols), "numeric columns at the 5th/95th percentiles."))
    }

    if (input$scaling == "Standardize (Z-score)" && length(scale_cols) > 0) {
      for (col in scale_cols) {
        if (sd(df[[col]], na.rm = TRUE) > 0) df[[col]] <- as.numeric(scale(df[[col]]))
      }
      log_lines <- c(log_lines, paste("- Applied z-score scaling to", length(scale_cols), "numeric columns."))
    } else if (input$scaling == "Normalize (Min-Max)" && length(scale_cols) > 0) {
      for (col in scale_cols) {
        rng <- range(df[[col]], na.rm = TRUE)
        if (diff(rng) > 0) df[[col]] <- (df[[col]] - rng[1]) / diff(rng)
      }
      log_lines <- c(log_lines, paste("- Applied min-max scaling to", length(scale_cols), "numeric columns."))
    }

    if (isTRUE(input$encode_cat) && length(encode_cols) > 0) {
      other_cols <- setdiff(names(df), encode_cols)
      encoded_df <- as.data.frame(model.matrix(~ . - 1, data = df[, encode_cols, drop = FALSE]))
      df <- cbind(df[, other_cols, drop = FALSE], encoded_df)
      log_lines <- c(log_lines, paste("- One-hot encoded", length(encode_cols), "selected categorical columns."))
    }

    if (length(log_lines) == 1) log_lines <- c(log_lines, "- No cleaning transformations were applied.")

    list(
      data = df,
      log = log_lines,
      changes = cleaning_changes(df_before, df, scale_cols, encode_cols, outlier_cols)
    )
  })

  cleaned_data <- reactive(cleaning_result()$data)

  output$clean_rows <- renderText({
    req(dataset(), cleaned_data())
    paste(nrow(dataset()), "→", nrow(cleaned_data()))
  })
  output$clean_missing <- renderText({
    req(dataset(), cleaned_data())
    paste(sum(is.na(dataset())), "→", sum(is.na(cleaned_data())))
  })
  output$clean_duplicates <- renderText({
    req(dataset(), cleaned_data())
    paste(sum(duplicated(dataset())), "→", sum(duplicated(cleaned_data())))
  })

  output$cleanTable <- renderDT({
    req(cleaned_data())
    datatable(head(cleaned_data(), 20), options = list(scrollX = TRUE, pageLength = 10))
  })

  output$cleanSummary <- renderPrint({
    req(cleaned_data())
    summary(cleaned_data())
  })

  output$cleanLog <- renderPrint({
    req(cleaning_result())
    cat(paste(cleaning_result()$log, collapse = "\n"), "\n\n")
    cat(paste(cleaning_result()$changes, collapse = "\n"))
  })

  active_data <- reactive(cleaned_data())

  output$fe_var_select <- renderUI({
    req(active_data())
    num_cols <- names(active_data())[sapply(active_data(), is.numeric)]
    if (length(num_cols) == 0) return(helpText("No numeric columns available for feature engineering."))
    if (input$fe_mode == "Single-variable transformation") {
      selectInput("fe_variable", "Select Numeric Variable:", choices = num_cols)
    } else {
      tagList(
        selectInput("fe_variable_1", "Select First Numeric Variable:", choices = num_cols),
        selectInput("fe_variable_2", "Select Second Numeric Variable:", choices = num_cols,
                    selected = num_cols[min(2, length(num_cols))])
      )
    }
  })

  fe_result <- reactive({
    req(active_data())
    df_new <- active_data()

    if (input$fe_mode == "Single-variable transformation") {
      req(input$fe_variable)
      original <- suppressWarnings(as.numeric(df_new[[input$fe_variable]]))
      shiny::validate(shiny::need(!all(is.na(original)), "Selected variable must be numeric."))
      transformed <- original
      explanation <- ""

      if (input$fe_transformation == "Log(x+1)") {
        transformed <- log(pmax(original, 0) + 1)
        explanation <- "Log(x+1) compresses large values and reduces right-skewness."
      } else if (input$fe_transformation == "Square Root") {
        transformed <- sqrt(pmax(original, 0))
        explanation <- "Square root provides a milder compression than log and can stabilize variance."
      } else if (input$fe_transformation == "Square") {
        transformed <- original^2
        explanation <- "Square emphasizes larger values and can highlight nonlinear scale differences."
      } else if (input$fe_transformation == "Binning") {
        transformed <- as.numeric(cut(original, breaks = input$fe_bins, labels = FALSE, include.lowest = TRUE))
        explanation <- paste("Binning converts a continuous variable into", input$fe_bins, "ordered groups.")
      } else if (input$fe_transformation == "Z-score") {
        transformed <- as.numeric(scale(original))
        explanation <- "Z-score rescales the variable to mean 0 and standard deviation 1."
      }
    } else {
      req(input$fe_variable_1, input$fe_variable_2)
      x1 <- suppressWarnings(as.numeric(df_new[[input$fe_variable_1]]))
      x2 <- suppressWarnings(as.numeric(df_new[[input$fe_variable_2]]))
      shiny::validate(
        shiny::need(!all(is.na(x1)), "First selected variable must be numeric."),
        shiny::need(!all(is.na(x2)), "Second selected variable must be numeric.")
      )
      original <- x1
      if (input$fe_pair_transformation == "Interaction (X1 * X2)") {
        transformed <- x1 * x2
        explanation <- "Interaction features capture joint effects between two predictors."
      } else {
        transformed <- rep(NA_real_, length(x1))
        valid <- is.finite(x1) & is.finite(x2) & abs(x2) >= 1e-8
        transformed[valid] <- x1[valid] / x2[valid]
        explanation <- "Ratio features express relative magnitude and are useful when scale relationships matter."
      }
    }

    new_name <- trimws(input$fe_new_name)
    if (identical(new_name, "")) new_name <- "engineered_feature"
    df_new[[new_name]] <- transformed

    stats <- data.frame(
      Metric = c("Mean", "SD", "Min", "Median", "Max"),
      Original = c(
        safe_num_summary(original, mean),
        safe_num_summary(original, sd),
        safe_num_summary(original, min),
        safe_num_summary(original, median),
        safe_num_summary(original, max)
      ),
      Engineered = c(
        safe_num_summary(transformed, mean),
        safe_num_summary(transformed, sd),
        safe_num_summary(transformed, min),
        safe_num_summary(transformed, median),
        safe_num_summary(transformed, max)
      )
    )

    list(original = original, transformed = transformed, df = df_new,
         explanation = explanation, stats = stats, new_name = new_name)
  })

  output$fe_explanation <- renderPrint({
    req(fe_result())
    cat(fe_result()$explanation, "\n")
    cat("New feature created:", fe_result()$new_name)
  })

  output$fe_stats <- renderTable({
    req(fe_result())
    stats_df <- fe_result()$stats
    num_idx <- vapply(stats_df, is.numeric, logical(1))
    stats_df[num_idx] <- lapply(stats_df[num_idx], round, 4)
    stats_df
  })

  output$fe_histPlot <- renderPlot({
    req(fe_result())
    orig <- suppressWarnings(as.numeric(fe_result()$original))
    trans <- suppressWarnings(as.numeric(fe_result()$transformed))
    shiny::validate(shiny::need(sum(is.finite(c(orig, trans))) > 0, "No numeric values available to plot."))
    plot_df <- data.frame(value = c(orig, trans), type = rep(c("Original", "Engineered"), each = length(orig)))
    plot_df <- plot_df[is.finite(plot_df$value), , drop = FALSE]
    ggplot(plot_df, aes(x = value, fill = type)) +
      geom_histogram(alpha = 0.5, bins = 30, position = "identity") +
      facet_wrap(~type, scales = "free") +
      theme_minimal() +
      labs(title = "Before vs After Feature Distribution", x = "Value", y = "Count")
  })

  output$fe_table <- renderDT({
    req(fe_result())
    datatable(head(fe_result()$df, 20), options = list(scrollX = TRUE, pageLength = 10))
  })

  output$eda_var_select <- renderUI({
    req(active_data())
    cols <- names(active_data())
    selectInput("eda_x", "X Variable:", choices = cols)
  })

  output$eda_y_ui <- renderUI({
    req(active_data())
    num_cols <- names(active_data())[sapply(active_data(), is.numeric)]
    selectInput("eda_y", "Y Variable:", choices = c("None", num_cols), selected = "None")
  })

  observe({
    req(active_data())
    group_cols <- names(active_data())[sapply(active_data(), function(x) {
      is.character(x) || is.factor(x) || is_discrete_numeric(x)
    })]
    updateSelectInput(session, "eda_color", choices = c("None", group_cols), selected = "None")
    updateSelectInput(session, "eda_facet", choices = c("None", group_cols), selected = "None")
  })

  output$eda_filter_numeric_ui <- renderUI({
    req(active_data())
    num_cols <- names(active_data())[sapply(active_data(), is.numeric)]
    if (length(num_cols) == 0) return(NULL)
    selected <- if (!is.null(input$eda_filter_numeric)) input$eda_filter_numeric else num_cols[1]
    rng <- safe_slider_bounds(active_data()[[selected]])
    tagList(
      selectInput("eda_filter_numeric", "Numeric filter column:", choices = num_cols, selected = selected),
      sliderInput("eda_numeric_range", "Keep values in range:", min = rng[1], max = rng[2], value = rng)
    )
  })

  observeEvent(input$eda_filter_numeric, {
    req(active_data(), input$eda_filter_numeric)
    rng <- safe_slider_bounds(active_data()[[input$eda_filter_numeric]])
    updateSliderInput(session, "eda_numeric_range", min = rng[1], max = rng[2], value = rng)
  }, ignoreInit = TRUE)

  output$eda_filter_cat_ui <- renderUI({
    req(active_data())
    cat_cols <- names(active_data())[sapply(active_data(), function(x) {
      is.character(x) || is.factor(x) || is_discrete_numeric(x)
    })]
    if (length(cat_cols) == 0) return(NULL)
    selected_cat <- if (!is.null(input$eda_filter_cat_col)) input$eda_filter_cat_col else cat_cols[1]
    choices <- sort(unique(as.character(active_data()[[selected_cat]])))
    tagList(
      selectInput("eda_filter_cat_col", "Categorical filter column:", choices = cat_cols, selected = selected_cat),
      checkboxGroupInput("eda_filter_cat_vals", "Keep categories:", choices = choices, selected = choices)
    )
  })

  observeEvent(input$eda_filter_cat_col, {
    req(active_data(), input$eda_filter_cat_col)
    choices <- sort(unique(as.character(active_data()[[input$eda_filter_cat_col]])))
    updateCheckboxGroupInput(session, "eda_filter_cat_vals", choices = choices, selected = choices)
  }, ignoreInit = TRUE)

  eda_numeric_range_debounced <- debounce(reactive(input$eda_numeric_range), millis = 250)

  observeEvent(input$reset_eda, {
    updateRadioButtons(session, "plot_type", selected = "Histogram")
    updateSelectInput(session, "eda_color", selected = "None")
    updateSelectInput(session, "eda_facet", selected = "None")
    updateCheckboxInput(session, "add_lm", value = FALSE)
    updateSelectInput(session, "eda_y", selected = "None")
  })

  observeEvent(input$reset_filters, {
    req(active_data())
    num_cols <- names(active_data())[sapply(active_data(), is.numeric)]
    if (length(num_cols) > 0) {
      updateSelectInput(session, "eda_filter_numeric", selected = num_cols[1])
      rng <- safe_slider_bounds(active_data()[[num_cols[1]]])
      updateSliderInput(session, "eda_numeric_range", min = rng[1], max = rng[2], value = rng)
    }
    cat_cols <- names(active_data())[sapply(active_data(), function(x) {
      is.character(x) || is.factor(x) || is_discrete_numeric(x)
    })]
    if (length(cat_cols) > 0) {
      updateSelectInput(session, "eda_filter_cat_col", selected = cat_cols[1])
      choices <- sort(unique(as.character(active_data()[[cat_cols[1]]])))
      updateCheckboxGroupInput(session, "eda_filter_cat_vals", choices = choices, selected = choices)
    }
  })

  filtered_eda_data <- reactive({
    req(active_data())
    df <- active_data()
    if (!is.null(input$eda_filter_numeric) && !is.null(eda_numeric_range_debounced())) {
      col <- input$eda_filter_numeric
      rng <- eda_numeric_range_debounced()
      df <- df[df[[col]] >= rng[1] & df[[col]] <= rng[2], , drop = FALSE]
    }
    if (!is.null(input$eda_filter_cat_col) && !is.null(input$eda_filter_cat_vals) && length(input$eda_filter_cat_vals) > 0) {
      col2 <- input$eda_filter_cat_col
      df <- df[as.character(df[[col2]]) %in% input$eda_filter_cat_vals, , drop = FALSE]
    }
    df
  })

  eda_display_data <- reactive({
    req(filtered_eda_data())
    df <- filtered_eda_data()

    color_mapping <- if (!is.null(input$eda_color) && input$eda_color != "None") input$eda_color else NULL
    facet_mapping <- if (!is.null(input$eda_facet) && input$eda_facet != "None") input$eda_facet else NULL

    if (!is.null(color_mapping) && color_mapping %in% names(df)) df[[color_mapping]] <- as.factor(df[[color_mapping]])
    if (!is.null(facet_mapping) && facet_mapping %in% names(df)) df[[facet_mapping]] <- as.factor(df[[facet_mapping]])
    if (input$plot_type %in% c("Boxplot", "Bar Chart") &&
        input$eda_x %in% names(df) &&
        is_discrete_numeric(df[[input$eda_x]])) {
      df[[input$eda_x]] <- as.factor(df[[input$eda_x]])
    }

    list(df = df, color_mapping = color_mapping, facet_mapping = facet_mapping)
  })

  output$eda_n <- renderUI({
    req(filtered_eda_data())
    HTML(paste0("<div style='font-size:28px; font-weight:700; line-height:1;'>", nrow(filtered_eda_data()), "</div>"))
  })

  output$edaRecommend <- renderUI({
    req(filtered_eda_data(), input$eda_x)
    df <- filtered_eda_data()
    x <- df[[input$eda_x]]
    y <- if (!is.null(input$eda_y) && input$eda_y != "None") df[[input$eda_y]] else NULL

    x_is_num <- is.numeric(x) && !is_discrete_numeric(x)
    x_is_group <- is.character(x) || is.factor(x) || is_discrete_numeric(x)
    y_is_num <- !is.null(y) && is.numeric(y)

    rec <- "Histogram"
    why <- "default"
    status <- ""

    if (x_is_num && y_is_num) {
      rec <- "Scatter"
      why <- "numeric vs numeric"
      if (input$plot_type == "Scatter") status <- "✓ Good choice"
    } else if (x_is_group && y_is_num) {
      rec <- "Boxplot"
      why <- "group vs numeric"
      if (input$plot_type == "Boxplot") status <- "✓ Good choice"
    } else if (x_is_num && is.null(y)) {
      rec <- "Histogram / Density"
      why <- "distribution of X"
      if (input$plot_type %in% c("Histogram", "Density")) status <- "✓ Good choice"
    } else if (x_is_group && is.null(y)) {
      rec <- "Bar Chart"
      why <- "counts by group"
      if (input$plot_type == "Bar Chart") status <- "✓ Good choice"
    }

    HTML(paste0(
      "<div style='font-size:15px; line-height:1.5;'>",
      "<b>", rec, "</b><br/>",
      "<span style='color:#666;'>", why, "</span>",
      if (status != "") paste0("<br/><span style='color:#1a7f37; font-weight:600;'>", status, "</span>") else "",
      "</div>"
    ))
  })

  output$edaInsight <- renderUI({
    req(filtered_eda_data(), input$eda_x)
    df <- filtered_eda_data()

    if (nrow(df) == 0) {
      return(HTML("<div style='font-size:15px;'>No data</div>"))
    }

    y_name <- input$eda_y %||% "None"

    if (input$plot_type == "Scatter" &&
        y_name != "None" &&
        y_name %in% names(df) &&
        input$eda_x %in% names(df) &&
        is.numeric(df[[input$eda_x]]) &&
        is.numeric(df[[y_name]])) {

      corr_val <- safe_cor_value(df[[input$eda_x]], df[[y_name]])
      if (is.na(corr_val)) {
        return(HTML("<div style='font-size:15px;'>Correlation unavailable</div>"))
      }

      return(HTML(paste0(
        "<div style='font-size:15px; line-height:1.5;'>",
        "<b>Correlation</b><br/>", round(corr_val, 3),
        "</div>"
      )))
    }

    if (input$eda_x %in% names(df) && is.numeric(df[[input$eda_x]])) {
      return(HTML(paste0(
        "<div style='font-size:15px; line-height:1.5;'>",
        "<b>Mean</b>: ", round(safe_num_summary(df[[input$eda_x]], mean), 3), "<br/>",
        "<b>Median</b>: ", round(safe_num_summary(df[[input$eda_x]], median), 3),
        "</div>"
      )))
    }

    if (input$eda_x %in% names(df)) {
      top_level <- names(sort(table(df[[input$eda_x]]), decreasing = TRUE))[1]
      return(HTML(paste0(
        "<div style='font-size:15px; line-height:1.5;'>",
        "<b>Top category</b><br/>", top_level,
        "</div>"
      )))
    }

    HTML("<div style='font-size:15px;'>Insight unavailable</div>")
  })

  output$edaVars <- renderUI({
    req(input$eda_x, filtered_eda_data())
    HTML(paste0(
      "<div style='font-size:15px; line-height:1.6;'>",
      "<b>X</b>: ", input$eda_x, "<br/>",
      "<b>Y</b>: ", input$eda_y,
      "</div>"
    ))
  })

  output$edaPlot <- renderPlot({
    req(eda_display_data(), input$eda_x)
    dd <- eda_display_data()
    df <- dd$df
    color_mapping <- dd$color_mapping
    facet_mapping <- dd$facet_mapping

    shiny::validate(shiny::need(nrow(df) > 0, "No data available after filtering."))
    base_theme <- theme_minimal()
    y_name <- input$eda_y %||% "None"

    if (input$plot_type == "Histogram") {
      if (!is.numeric(df[[input$eda_x]]) || is_discrete_numeric(df[[input$eda_x]])) {
        if (!is.null(color_mapping)) {
          p <- ggplot(df, aes(x = .data[[input$eda_x]], fill = .data[[color_mapping]])) +
            geom_bar(alpha = 0.8, position = "stack")
        } else {
          p <- ggplot(df, aes(x = .data[[input$eda_x]])) +
            geom_bar(alpha = 0.8, fill = "steelblue")
        }
        p <- p + labs(title = paste("Bar Chart of", input$eda_x), y = "Count") + base_theme
      } else {
        if (!is.null(color_mapping)) {
          p <- ggplot(df, aes(x = .data[[input$eda_x]], fill = .data[[color_mapping]])) +
            geom_histogram(color = "black", alpha = 0.7, bins = input$eda_bins, position = "identity")
        } else {
          p <- ggplot(df, aes(x = .data[[input$eda_x]])) +
            geom_histogram(fill = "steelblue", color = "black", alpha = 0.7, bins = input$eda_bins)
        }
        p <- p + labs(title = paste("Histogram of", input$eda_x)) + base_theme
      }

    } else if (input$plot_type == "Scatter") {
      shiny::validate(
        shiny::need(y_name != "None", "Please choose a numeric Y variable for scatter plot."),
        shiny::need(y_name %in% names(df), "Y variable is not available yet."),
        shiny::need(input$eda_x %in% names(df), "X variable is not available."),
        shiny::need(is.numeric(df[[input$eda_x]]), "Scatter plot requires a numeric X variable."),
        shiny::need(is.numeric(df[[y_name]]), "Scatter plot requires a numeric Y variable.")
      )

      if (!is.null(color_mapping)) {
        p <- ggplot(df, aes(x = .data[[input$eda_x]], y = .data[[y_name]], color = .data[[color_mapping]])) +
          geom_point(alpha = input$eda_alpha, size = input$eda_size)
      } else {
        p <- ggplot(df, aes(x = .data[[input$eda_x]], y = .data[[y_name]])) +
          geom_point(alpha = input$eda_alpha, size = input$eda_size, color = "steelblue")
      }
      if (isTRUE(input$add_lm)) {
        p <- p + geom_smooth(
          data = df,
          mapping = aes(x = .data[[input$eda_x]], y = .data[[y_name]]),
          method = "lm", se = FALSE, inherit.aes = FALSE, color = "black"
        )
      }
      p <- p + labs(title = paste("Scatter:", input$eda_x, "vs", y_name)) + base_theme

    } else if (input$plot_type == "Boxplot") {
      shiny::validate(
        shiny::need(y_name != "None", "Please choose a numeric Y variable for boxplot."),
        shiny::need(y_name %in% names(df), "Y variable is not available yet."),
        shiny::need(is.numeric(df[[y_name]]), "Boxplot requires a numeric Y variable.")
      )
      if (is.numeric(df[[input$eda_x]]) && !is_discrete_numeric(df[[input$eda_x]])) {
        df[[input$eda_x]] <- cut(df[[input$eda_x]], breaks = 5, include.lowest = TRUE)
      }
      if (!is.null(color_mapping)) {
        p <- ggplot(df, aes(x = .data[[input$eda_x]], y = .data[[y_name]], fill = .data[[color_mapping]])) +
          geom_boxplot(alpha = 0.7)
      } else {
        p <- ggplot(df, aes(x = .data[[input$eda_x]], y = .data[[y_name]])) +
          geom_boxplot(alpha = 0.7, fill = "steelblue")
      }
      p <- p + labs(title = paste("Boxplot:", y_name, "by", input$eda_x)) + base_theme

    } else if (input$plot_type == "Density") {
      if (!is.numeric(df[[input$eda_x]]) || is_discrete_numeric(df[[input$eda_x]])) {
        if (!is.null(color_mapping)) {
          p <- ggplot(df, aes(x = .data[[input$eda_x]], fill = .data[[color_mapping]])) +
            geom_bar(alpha = 0.8, position = "stack")
        } else {
          p <- ggplot(df, aes(x = .data[[input$eda_x]])) +
            geom_bar(alpha = 0.8, fill = "steelblue")
        }
        p <- p + labs(title = paste("Bar Chart of", input$eda_x), y = "Count") + base_theme
      } else {
        if (!is.null(color_mapping)) {
          grp_count <- table(df[[color_mapping]])
          valid_groups <- names(grp_count[grp_count >= 2])
          df_den <- df[df[[color_mapping]] %in% valid_groups, , drop = FALSE]
          shiny::validate(shiny::need(length(valid_groups) > 0, "Density plot needs at least one group with 2 or more observations."))
          p <- ggplot(df_den, aes(x = .data[[input$eda_x]], color = .data[[color_mapping]], fill = .data[[color_mapping]])) +
            geom_density(alpha = 0.3)
        } else {
          p <- ggplot(df, aes(x = .data[[input$eda_x]])) +
            geom_density(fill = "steelblue", alpha = 0.3, color = "steelblue")
        }
        p <- p + labs(title = paste("Density Plot of", input$eda_x)) + base_theme
      }

    } else {
      if (is.numeric(df[[input$eda_x]]) && !is_discrete_numeric(df[[input$eda_x]])) {
        x_binned <- cut(df[[input$eda_x]], breaks = 10, include.lowest = TRUE)
        bar_df <- data.frame(x_binned = x_binned)
        if (!is.null(color_mapping)) bar_df[[color_mapping]] <- df[[color_mapping]]
        if (!is.null(facet_mapping)) bar_df[[facet_mapping]] <- df[[facet_mapping]]
        if (!is.null(color_mapping)) {
          p <- ggplot(bar_df, aes(x = x_binned, fill = .data[[color_mapping]])) +
            geom_bar(alpha = 0.8, position = "stack")
        } else {
          p <- ggplot(bar_df, aes(x = x_binned)) +
            geom_bar(alpha = 0.8, fill = "steelblue")
        }
        p <- p + labs(title = paste("Bar Chart of Binned", input$eda_x), x = paste(input$eda_x, "(binned)"), y = "Count") + base_theme
      } else {
        if (!is.null(color_mapping)) {
          p <- ggplot(df, aes(x = .data[[input$eda_x]], fill = .data[[color_mapping]])) +
            geom_bar(alpha = 0.8, position = "stack")
        } else {
          p <- ggplot(df, aes(x = .data[[input$eda_x]])) +
            geom_bar(alpha = 0.8, fill = "steelblue")
        }
        p <- p + labs(title = paste("Bar Chart of", input$eda_x), y = "Count") + base_theme
      }
    }

    if (!is.null(facet_mapping)) p <- p + facet_wrap(as.formula(paste("~", facet_mapping)))
    p
  })

  output$edaSummary <- renderPrint({
    req(filtered_eda_data())
    summary(filtered_eda_data())
  })

  output$edaCorr <- renderPrint({
    req(filtered_eda_data())
    num_df <- filtered_eda_data()[, sapply(filtered_eda_data(), is.numeric), drop = FALSE]

    if (ncol(num_df) < 2) {
      cat("Not enough numeric columns in the filtered dataset to compute correlation.")
      return()
    }

    corr_mat <- tryCatch(
      cor(num_df, use = "pairwise.complete.obs"),
      error = function(e) NULL
    )

    if (is.null(corr_mat) || all(is.na(corr_mat))) {
      cat("Correlation unavailable for the current filtered dataset.")
    } else {
      print(round(corr_mat, 2))
    }
  })
}

shinyApp(ui = ui, server = server)
