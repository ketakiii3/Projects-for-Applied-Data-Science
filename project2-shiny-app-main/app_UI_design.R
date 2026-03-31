library(shiny)
library(ggplot2)
library(readxl)
library(jsonlite)
library(shinyWidgets)
library(fontawesome)

# -----------------------------
# Helper: load uploaded/built-in data
# -----------------------------
load_data <- function(file, builtin) {
  if (!is.null(builtin) && builtin != "None") {
    if (builtin == "iris") {
      return(iris)
    }
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

# -----------------------------
# Helper: mode function
# -----------------------------
get_mode <- function(x) {
  x2 <- x[!is.na(x)]
  if (length(x2) == 0) return(NA)
  tbl <- table(x2)
  names(tbl)[which.max(tbl)]
}

svg_icon <- function(type, size = 64) {
  blue_dark <- "#1F4E82"
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

# -----------------------------
# UI
# -----------------------------
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

      table {
        background: white;
      }

      pre {
        background: #f8fbff;
        border: 1px solid #e4f0ff;
        border-radius: 14px;
        padding: 14px;
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
    column(
      4,
      div(
        class = "feature-card",
        div(class = "feature-svg", svg_icon("loading", 56)),
        div(class = "feature-title", "Data Loading"),
        div(
          class = "feature-text",
          "Import CSV, Excel, JSON, or RDS files, or choose a built-in dataset for quick testing."
        )
      )
    ),
    column(
      4,
      div(
        class = "feature-card",
        div(class = "feature-svg", icon("broom", class = "fa-3x", style = "color:#2E69A8;")),
        div(class = "feature-title", "Data Cleaning"),
        div(
          class = "feature-text",
          "Handle duplicates, missing values, outliers, scaling, and categorical encoding through an intuitive interface."
        )
      )
    ),
    column(
      4,
      div(
        class = "feature-card",
        div(class = "feature-svg", icon("wrench", class = "fa-3x", style = "color:#2E69A8;")),
        div(class = "feature-title", "Feature Engineering"),
        div(
          class = "feature-text",
          "Create transformed variables such as log, square root, square, and binned features for downstream analysis."
        )
      )
    )
  ),
  
  fluidRow(
    column(
      6,
      div(
        class = "feature-card",
        div(class = "feature-svg", svg_icon("eda", 56)),
        div(class = "feature-title", "EDA"),
        div(
          class = "feature-text",
          "Inspect distributions, variable relationships, and summary statistics with clean, accessible visualizations."
        )
      )
    ),
    column(
      6,
      div(
        class = "feature-card",
        div(class = "feature-svg", svg_icon("guide", 56)),
        div(class = "feature-title", "User Guide"),
        div(
          class = "feature-text",
          "A guided workflow helps users understand where to start, what to do next, and how to interpret results."
        )
      )
    )
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
          tags$li("Use Feature Engineering to create transformed variables."),
          tags$li("Use EDA to visualize distributions and relationships between variables.")
        ),
        div(
          class = "help-note",
          tags$b("Using Sample Data: "),
          "In the Data Loading tab, users can choose one of the two built-in sample datasets, iris or mtcars, and click 'Load Dataset'. This is a convenient way to explore the app workflow and test its functions before uploading an external file."
        ),
        div(
          class = "help-note",
          tags$b("Tip: "),
          "Apply cleaning before feature engineering when your dataset contains missing values or extreme observations."
        )
      )
    ),
    
    tabPanel(
      "Data Loading",
      fluidRow(
        column(
          4,
          div(
            class = "panel-card",
            div(class = "panel-title", "Upload Dataset"),
            fileInput("file", "Choose a file", accept = c(".csv", ".xlsx", ".xls", ".json", ".rds")),
            selectInput("builtin", "Or choose a built-in dataset", choices = c("None", "iris", "mtcars")),
            actionButton("load_builtin", "Load Dataset"),
            div(class = "help-note", "Supported formats: CSV, Excel, JSON, and RDS.")
          )
        ),
        column(
          8,
          div(
            class = "panel-card",
            div(class = "panel-title", "Dataset Preview"),
            tableOutput("rawTable")
          ),
          div(
            class = "panel-card",
            div(class = "panel-title", "Summary Statistics"),
            verbatimTextOutput("rawSummary")
          )
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
            radioButtons(
              "missing_strategy",
              "Missing value handling",
              choices = c("None", "Remove Rows", "Impute with Mean", "Impute with Median", "Impute with Mode")
            ),
            checkboxInput("standardize_labels", "Standardize text labels", FALSE),
            radioButtons(
              "outlier_strategy",
              "Outlier handling",
              choices = c("None", "Remove (IQR rule)", "Cap (Winsorize 5%)")
            ),
            radioButtons(
              "scaling",
              "Scale numeric features",
              choices = c("None", "Standardize (Z-score)", "Normalize (Min-Max)")
            ),
            checkboxInput("encode_cat", "One-hot encode categorical features", FALSE),
            actionButton("apply_clean", "Apply Cleaning")
          )
        ),
        column(
          8,
          div(
            class = "panel-card",
            div(class = "panel-title", "Cleaned Dataset"),
            tableOutput("cleanTable")
          ),
          div(
            class = "panel-card",
            div(class = "panel-title", "Cleaned Data Summary"),
            verbatimTextOutput("cleanSummary")
          )
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
            uiOutput("fe_var_select"),
            radioButtons(
              "fe_transformation",
              "Choose transformation",
              choices = c("Log(x+1)", "Square Root", "Square", "Binning (4 bins)")
            ),
            actionButton("apply_fe", "Apply Transformation"),
            div(class = "help-note", "Only numeric variables can be transformed.")
          )
        ),
        column(
          8,
          div(
            class = "panel-card",
            div(class = "panel-title", "Transformed Variable Plot"),
            plotOutput("fe_histPlot")
          ),
          div(
            class = "panel-card",
            div(class = "panel-title", "Updated Dataset"),
            tableOutput("fe_table")
          )
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
            radioButtons(
              "plot_type",
              "Choose plot type",
              choices = c("Histogram", "Scatter", "Boxplot")
            ),
            checkboxInput("add_lm", "Add linear regression line", FALSE)
          )
        ),
        column(
          8,
          div(
            class = "panel-card",
            div(class = "panel-title", "Visualization"),
            plotOutput("edaPlot")
          ),
          div(
            class = "panel-card",
            div(class = "panel-title", "Summary"),
            verbatimTextOutput("edaSummary")
          ),
          div(
            class = "panel-card",
            div(class = "panel-title", "Correlation Matrix"),
            verbatimTextOutput("edaCorr")
          )
        )
      )
    )
  )
)

# -----------------------------
# Server
# -----------------------------
server <- function(input, output, session) {
  
  # Load dataset
  dataset <- eventReactive(input$load_builtin, {
    load_data(input$file, input$builtin)
  }, ignoreNULL = FALSE)
  
  output$rawTable <- renderTable({
    req(dataset())
    head(dataset(), 20)
  })
  
  output$rawSummary <- renderPrint({
    req(dataset())
    summary(dataset())
  })
  
  # Cleaning
  cleaned_data <- eventReactive(input$apply_clean, {
    req(dataset())
    df <- dataset()
    
    num_cols <- names(df)[sapply(df, is.numeric)]
    cat_cols <- names(df)[sapply(df, function(x) is.character(x) || is.factor(x))]
    
    # Remove duplicates
    if (input$remove_duplicates) {
      df <- df[!duplicated(df), , drop = FALSE]
    }
    
    # Handle missing values
    if (input$missing_strategy == "Remove Rows") {
      df <- na.omit(df)
    } else if (input$missing_strategy == "Impute with Mean") {
      for (col in num_cols) {
        df[[col]][is.na(df[[col]])] <- mean(df[[col]], na.rm = TRUE)
      }
    } else if (input$missing_strategy == "Impute with Median") {
      for (col in num_cols) {
        df[[col]][is.na(df[[col]])] <- median(df[[col]], na.rm = TRUE)
      }
    } else if (input$missing_strategy == "Impute with Mode") {
      for (col in names(df)) {
        mode_val <- get_mode(df[[col]])
        df[[col]][is.na(df[[col]])] <- mode_val
      }
    }
    
    # Standardize text
    if (input$standardize_labels) {
      for (col in cat_cols) {
        df[[col]] <- trimws(tolower(as.character(df[[col]])))
      }
    }
    
    # Handle outliers
    if (input$outlier_strategy == "Remove (IQR rule)") {
      for (col in num_cols) {
        Q1 <- quantile(df[[col]], 0.25, na.rm = TRUE)
        Q3 <- quantile(df[[col]], 0.75, na.rm = TRUE)
        IQR_val <- Q3 - Q1
        lower <- Q1 - 1.5 * IQR_val
        upper <- Q3 + 1.5 * IQR_val
        df <- df[df[[col]] >= lower & df[[col]] <= upper, , drop = FALSE]
      }
    } else if (input$outlier_strategy == "Cap (Winsorize 5%)") {
      for (col in num_cols) {
        lower <- quantile(df[[col]], 0.05, na.rm = TRUE)
        upper <- quantile(df[[col]], 0.95, na.rm = TRUE)
        df[[col]] <- pmax(pmin(df[[col]], upper), lower)
      }
    }
    
    # Scale numeric variables
    if (input$scaling == "Standardize (Z-score)") {
      for (col in num_cols) {
        df[[col]] <- as.numeric(scale(df[[col]]))
      }
    } else if (input$scaling == "Normalize (Min-Max)") {
      for (col in num_cols) {
        rng <- range(df[[col]], na.rm = TRUE)
        if (diff(rng) > 0) {
          df[[col]] <- (df[[col]] - rng[1]) / diff(rng)
        }
      }
    }
    
    # One-hot encode categorical variables
    if (input$encode_cat && length(cat_cols) > 0) {
      df <- as.data.frame(model.matrix(~ . - 1, data = df))
    }
    
    df
  })
  
  output$cleanTable <- renderTable({
    req(cleaned_data())
    head(cleaned_data(), 20)
  })
  
  output$cleanSummary <- renderPrint({
    req(cleaned_data())
    summary(cleaned_data())
  })
  
  # Use cleaned data if available; otherwise raw data
  active_data <- reactive({
    cd <- tryCatch(cleaned_data(), error = function(e) NULL)
    if (!is.null(cd)) cd else dataset()
  })
  
  # Feature engineering UI
  output$fe_var_select <- renderUI({
    req(active_data())
    num_cols <- names(active_data())[sapply(active_data(), is.numeric)]
    selectInput("fe_variable", "Select numeric variable", choices = num_cols)
  })
  
  # Feature engineering logic
  fe_result <- eventReactive(input$apply_fe, {
    req(active_data(), input$fe_variable)
    
    df <- active_data()
    x <- df[[input$fe_variable]]
    new_name <- paste0(input$fe_variable, "_", gsub("[^A-Za-z0-9]", "", input$fe_transformation))
    
    if (input$fe_transformation == "Log(x+1)") {
      df[[new_name]] <- ifelse(x > -1, log(x + 1), NA)
    } else if (input$fe_transformation == "Square Root") {
      df[[new_name]] <- ifelse(x >= 0, sqrt(x), NA)
    } else if (input$fe_transformation == "Square") {
      df[[new_name]] <- x^2
    } else if (input$fe_transformation == "Binning (4 bins)") {
      df[[new_name]] <- cut(x, breaks = 4, include.lowest = TRUE)
    }
    
    list(data = df, new_var = new_name)
  })
  
  output$fe_histPlot <- renderPlot({
    req(fe_result())
    
    df <- fe_result()$data
    new_var <- fe_result()$new_var
    
    if (is.numeric(df[[new_var]])) {
      ggplot(df, aes_string(x = new_var)) +
        geom_histogram(bins = 30, fill = "steelblue", color = "black", alpha = 0.7) +
        labs(title = paste("Histogram of", new_var), x = new_var, y = "Count") +
        theme_minimal()
    } else {
      ggplot(df, aes_string(x = new_var)) +
        geom_bar(fill = "steelblue", color = "black", alpha = 0.7) +
        labs(title = paste("Bar Chart of", new_var), x = new_var, y = "Count") +
        theme_minimal()
    }
  })
  
  output$fe_table <- renderTable({
    req(fe_result())
    head(fe_result()$data, 20)
  })
  
  # EDA UI
  output$eda_var_select <- renderUI({
    req(active_data())
    cols <- names(active_data())
    
    tagList(
      selectInput("eda_x", "Select X variable", choices = cols),
      selectInput("eda_y", "Select Y variable", choices = cols)
    )
  })
  
  # EDA plot
  output$edaPlot <- renderPlot({
    req(active_data(), input$eda_x)
    
    df <- active_data()
    
    if (input$plot_type == "Histogram") {
      validate(
        need(is.numeric(df[[input$eda_x]]), "Histogram requires a numeric X variable.")
      )
      
      ggplot(df, aes_string(x = input$eda_x)) +
        geom_histogram(fill = "steelblue", color = "black", alpha = 0.7, bins = 30) +
        labs(title = paste("Histogram of", input$eda_x)) +
        theme_minimal()
      
    } else if (input$plot_type == "Scatter") {
      validate(
        need(!is.null(input$eda_y), "Please select a Y variable."),
        need(is.numeric(df[[input$eda_x]]) && is.numeric(df[[input$eda_y]]),
             "Scatterplot requires both X and Y to be numeric.")
      )
      
      p <- ggplot(df, aes_string(x = input$eda_x, y = input$eda_y)) +
        geom_point(alpha = 0.6, color = "blue") +
        labs(title = paste("Scatterplot:", input$eda_x, "vs", input$eda_y)) +
        theme_minimal()
      
      if (input$add_lm) {
        p <- p + geom_smooth(method = "lm", se = FALSE, color = "red")
      }
      p
      
    } else if (input$plot_type == "Boxplot") {
      validate(
        need(!is.null(input$eda_y), "Please select a Y variable."),
        need(is.numeric(df[[input$eda_y]]), "Boxplot requires a numeric Y variable.")
      )
      
      ggplot(df, aes_string(x = input$eda_x, y = input$eda_y)) +
        geom_boxplot(fill = "lightblue", color = "black", alpha = 0.7) +
        labs(title = paste("Boxplot:", input$eda_y, "by", input$eda_x)) +
        theme_minimal()
    }
  })
  
  output$edaSummary <- renderPrint({
    req(active_data())
    summary(active_data())
  })
  
  output$edaCorr <- renderPrint({
    req(active_data())
    num_df <- active_data()[, sapply(active_data(), is.numeric), drop = FALSE]
    
    if (ncol(num_df) >= 2) {
      round(cor(num_df, use = "complete.obs"), 2)
    } else {
      cat("Not enough numeric columns to compute a correlation matrix.")
    }
  })
}

shinyApp(ui = ui, server = server)

