library(shiny)
library(ggplot2)
library(readxl)
library(jsonlite)

load_data <- function(file, builtin) {
  if (builtin != "None") {
    if (builtin == "iris")   return(iris)
    if (builtin == "mtcars") {
      d <- mtcars; d$car <- rownames(d); rownames(d) <- NULL; return(d)
    }
  }
  if (is.null(file)) return(NULL)
  ext  <- tools::file_ext(file$name)
  path <- file$datapath
  if (ext == "csv") read.csv(path, stringsAsFactors = FALSE)
  else if (ext %in% c("xlsx","xls")) as.data.frame(read_excel(path))
  else if (ext == "json") as.data.frame(fromJSON(path))
  else if (ext == "rds") readRDS(path)
  else NULL
}
# UI
ui <- navbarPage("App",

  # Loading Datasets
  tabPanel("Part 1: Load",
    sidebarLayout(
      sidebarPanel(
        fileInput("file", "Upload File (CSV / Excel / JSON / RDS):",
                  accept = c(".csv", ".xlsx", ".xls", ".json", ".rds")),
        selectInput("builtin", "Or select a built-in dataset:",
                    choices = c("None", "iris", "mtcars")),
        actionButton("load_builtin", "Load Built-in Dataset")
      ),
      mainPanel(
        tabsetPanel(
          tabPanel("Dataset", tableOutput("rawTable")),
          tabPanel("Summary", verbatimTextOutput("rawSummary"))
        )
      )
    )
  ),

  # Data Cleaning
  tabPanel("Part 2: Cleaning",
    sidebarLayout(
      sidebarPanel(
        checkboxInput("remove_duplicates", "Remove Duplicate Rows", value = FALSE),
        radioButtons("missing_strategy", "Handle Missing Values:",
                     choices = c("None", "Remove Rows", "Impute with Mean",
                                 "Impute with Median", "Impute with Mode")),
        checkboxInput("standardize_labels", "Standardize Text (trim & lowercase)",
                      value = FALSE),
        radioButtons("outlier_strategy", "Handle Outliers:",
                     choices = c("None", "Remove (IQR rule)", "Cap (Winsorize 5%)")),
        radioButtons("scaling", "Scale Numerical Features:",
                     choices = c("None", "Standardize (Z-score)", "Normalize (Min-Max)")),
        checkboxInput("encode_cat", "One-Hot Encode Categorical Features", value = FALSE),
        actionButton("apply_clean", "Apply Preprocessing")
      ),
      mainPanel(
        tabsetPanel(
          tabPanel("Cleaned Dataset", tableOutput("cleanTable")),
          tabPanel("Summary", verbatimTextOutput("cleanSummary"))
        )
      )
    )
  ),

  # Feature Engine
  tabPanel("Part 3: Feature Engineering",
    sidebarLayout(
      sidebarPanel(
        uiOutput("fe_var_select"),
        radioButtons("fe_transformation", "Choose Transformation:",
                     choices = c("Log(x+1)", "Square Root", "Square", "Binning (4 bins)")),
        actionButton("apply_fe", "Apply Transformation")
      ),
      mainPanel(
        tabsetPanel(
          tabPanel("Histogram", plotOutput("fe_histPlot")),
          tabPanel("Dataset",   tableOutput("fe_table"))
        )
      )
    )
  ),

  # EDA
  tabPanel("Part 4: EDA",
    sidebarLayout(
      sidebarPanel(
        uiOutput("eda_var_select"),
        radioButtons("plot_type", "Choose Plot Type:",
                     choices = c("Histogram", "Scatter", "Boxplot")),
        checkboxInput("add_lm", "Add Linear Regression Line", value = FALSE)
      ),
      mainPanel(
        tabsetPanel(
          tabPanel("Plot",        plotOutput("edaPlot")),
          tabPanel("Summary",     verbatimTextOutput("edaSummary")),
          tabPanel("Correlation", verbatimTextOutput("edaCorr"))
        )
      )
    )
  )
)

# Server
server <- function(input, output, session) {
  # Load
  dataset <- reactive({
    input$load_builtin
    load_data(input$file, isolate(input$builtin))
  })

  observeEvent(input$load_builtin, { dataset() })

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
    df       <- dataset()
    num_cols <- names(df)[sapply(df, is.numeric)]
    cat_cols <- names(df)[sapply(df, function(x) is.character(x) | is.factor(x))]
    if (input$remove_duplicates)
      df <- df[!duplicated(df), ]
    if (input$missing_strategy == "Remove Rows") {
      df <- na.omit(df)
    } else if (input$missing_strategy == "Impute with Mean") {
      for (col in num_cols) df[[col]][is.na(df[[col]])] <- mean(df[[col]], na.rm = TRUE)
    } else if (input$missing_strategy == "Impute with Median") {
      for (col in num_cols) df[[col]][is.na(df[[col]])] <- median(df[[col]], na.rm = TRUE)
    } else if (input$missing_strategy == "Impute with Mode") {
      mode_val <- function(x) { tbl <- table(x); names(tbl)[which.max(tbl)] }
      for (col in names(df)) df[[col]][is.na(df[[col]])] <- mode_val(df[[col]])
    }
    if (input$standardize_labels)
      for (col in cat_cols) df[[col]] <- trimws(tolower(as.character(df[[col]])))
    if (input$outlier_strategy == "Remove (IQR rule)") {
      for (col in num_cols) {
        Q1 <- quantile(df[[col]], 0.25, na.rm = TRUE)
        Q3 <- quantile(df[[col]], 0.75, na.rm = TRUE)
        df <- df[df[[col]] >= Q1 - 1.5*(Q3-Q1) & df[[col]] <= Q3 + 1.5*(Q3-Q1), ]
      }
    } else if (input$outlier_strategy == "Cap (Winsorize 5%)") {
      for (col in num_cols) {
        df[[col]] <- pmax(pmin(df[[col]], quantile(df[[col]], 0.95, na.rm = TRUE)),
                                          quantile(df[[col]], 0.05, na.rm = TRUE))
      }
    }
    if (input$scaling == "Standardize (Z-score)") {
      for (col in num_cols) df[[col]] <- as.numeric(scale(df[[col]]))
    } else if (input$scaling == "Normalize (Min-Max)") {
      for (col in num_cols) {
        rng <- range(df[[col]], na.rm = TRUE)
        if (diff(rng) > 0) df[[col]] <- (df[[col]] - rng[1]) / diff(rng)
      }
    }
    if (input$encode_cat && length(cat_cols) > 0)
      df <- as.data.frame(model.matrix(~ . - 1, data = df))
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

  # Feature Engine
  # Use cleaned data, otherwise raw
  active_data <- reactive({
    if (!is.null(tryCatch(cleaned_data(), error = function(e) NULL)))
      cleaned_data()
    else
      dataset()
  })
  output$fe_var_select <- renderUI({
    req(active_data())
    num_cols <- names(active_data())[sapply(active_data(), is.numeric)]
    selectInput("fe_variable", "Select Numeric Variable:", choices = num_cols)
  })
  fe_result <- eventReactive(input$apply_fe, {
    req(input$fe_variable, active_data())
    data <- active_data()[[input$fe_variable]]
    if (!is.numeric(data)) return(NULL)
    transformed <- data
    if (input$fe_transformation == "Log(x+1)") {
      transformed <- log(data + 1)
    } else if (input$fe_transformation == "Square Root") {
      transformed <- sqrt(abs(data))
    } else if (input$fe_transformation == "Square") {
      transformed <- data^2
    } else if (input$fe_transformation == "Binning (4 bins)") {
      transformed <- as.numeric(cut(data, breaks = 4, labels = FALSE))
    }
    new_col <- paste0(input$fe_variable, "_", gsub("[^a-zA-Z]", "", input$fe_transformation))
    df_new  <- active_data()
    df_new[[new_col]] <- transformed
    list(original = data, transformed = transformed, df = df_new)
  })
  output$fe_histPlot <- renderPlot({
    req(fe_result())
    par(mfrow = c(1, 2))
    hist(fe_result()$original,    main = "Original",    col = "blue", border = "white")
    hist(fe_result()$transformed, main = "Transformed", col = "red",  border = "white")
  })
  output$fe_table <- renderTable({
    req(fe_result())
    head(fe_result()$df, 20)
  })
  # EDA
  output$eda_var_select <- renderUI({
    req(active_data())
    cols     <- names(active_data())
    num_cols <- names(active_data())[sapply(active_data(), is.numeric)]
    tagList(
      selectInput("eda_x", "X Variable:", choices = cols),
      selectInput("eda_y", "Y Variable:", choices = num_cols)
    )
  })
  output$edaPlot <- renderPlot({
    req(input$eda_x, input$eda_y, active_data())
    df <- active_data()
    if (input$plot_type == "Histogram") {
      ggplot(df, aes_string(x = input$eda_x)) +
        geom_histogram(fill = "steelblue", color = "black", alpha = 0.7, bins = 30) +
        labs(title = paste("Histogram of", input$eda_x)) +
        theme_minimal()
    } else if (input$plot_type == "Scatter") {
      p <- ggplot(df, aes_string(x = input$eda_x, y = input$eda_y)) +
        geom_point(color = "blue", alpha = 0.6) +
        labs(title = paste("Scatter:", input$eda_x, "vs", input$eda_y)) +
        theme_minimal()
      if (input$add_lm) p <- p + geom_smooth(method = "lm", se = FALSE, color = "red")
      p
    } else if (input$plot_type == "Boxplot") {
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
    num_cols <- active_data()[, sapply(active_data(), is.numeric), drop = FALSE]
    if (ncol(num_cols) >= 2)
      round(cor(num_cols, use = "complete.obs"), 2)
    else
      cat("Not enough numerical columns to compute correlation.")
  })
}
# Run
shinyApp(ui = ui, server = server)
