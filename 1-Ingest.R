# Description:
#   Stage 1. Loads all summary RDS files from Data-Input/ and stacks them
#   into All_Data. One row per FRIDA variable per year per scenario.
#
#   Inputs:  Data-Input/<scenario>/*-fit uncertainty-completeEqually-weighted.RDS
#   Outputs: Data-Output/1-All_Data.RDS
#            Columns: Scenario | Variable | Run | Year | Value

library(tidyverse)
options(scipen = 999)


## * Preamble #################################################################

## ** Paths

Path_Input  <- "Data-Input"
Path_Output <- "Data-Output"


## ** Constants

Central_Series <- "means"   # Which summary-list element is the central series.
                             #   "means"        = ensemble mean
                             #   "defaultRun"   = reference run
                             #   "ciBounds_q50" = true median (ciBounds[, "0.5"])


## ** Ingest helpers

# Summary list -> tidy rows. Variable = file stem (not varName.orig). Scenario filled by caller.
Ingest_Median <- function(file, Central_Series_Element = Central_Series) {

  Summary_List <- readRDS(file)

  Central_Values <- if (Central_Series_Element == "ciBounds_q50") {
    Summary_List$ciBounds[, "0.5"]
  } else {
    Summary_List[[Central_Series_Element]]
  }

  Variable_Key <- sub("-fit uncertainty-completeEqually-weighted\\.RDS$", "", basename(file))

  tibble(
    Scenario = NA_character_,
    Variable = Variable_Key,
    Run      = "median",
    Year     = as.integer(Summary_List$years),
    Value    = Central_Values
  )

}

# Ensemble df -> same shape as Ingest_Median. Run = id as character. Scenario filled by caller.
Ingest_Ensemble <- function(file, ids) {

  Ensemble_DF  <- readRDS(file)
  Variable_Key <- sub("\\.RDS$", "", basename(file))

  Ensemble_DF |>
    filter(id %in% ids) |>
    pivot_longer(cols = -id, names_to = "Year", values_to = "Value") |>
    mutate(
      Scenario = NA_character_,
      Variable = Variable_Key,
      Run      = as.character(id),
      Year     = as.integer(Year)
    ) |>
    select(Scenario, Variable, Run, Year, Value)

}


## * Stage 1: Ingest ##########################################################

# Skip folders with no summary files (e.g. policy_CP while data is still incoming).
All_Folders <- list.dirs(Path_Input, full.names = TRUE, recursive = FALSE)

Scenario_Folders <- All_Folders[
  sapply(All_Folders, function(Scenario_Dir) {
    length(list.files(Scenario_Dir, pattern = "-fit uncertainty-completeEqually-weighted\\.RDS$")) > 0
  })
]

cat("Scenario folders with data:", length(Scenario_Folders), "\n")
for (Folder in Scenario_Folders) cat(" ", basename(Folder), "\n")
cat("\n")

All_Data <- tibble()

for (Folder in Scenario_Folders) {

  Scenario_Name <- basename(Folder)

  Median_Files <- list.files(
    Folder,
    pattern    = "-fit uncertainty-completeEqually-weighted\\.RDS$",
    full.names = TRUE
  )

  # [To add ensemble members for a variable:
  #  bind_rows(Scenario_Data, Ingest_Ensemble(file, ids = c(1, 2, 3)))]
  Scenario_Data <- tibble()
  for (File in Median_Files) {
    Scenario_Data <- bind_rows(Scenario_Data, Ingest_Median(File))
  }
  Scenario_Data <- mutate(Scenario_Data, Scenario = Scenario_Name)

  cat(Scenario_Name, "—",
      length(Median_Files), "variable(s):",
      paste(unique(Scenario_Data$Variable), collapse = ", "),
      "—", nrow(Scenario_Data), "rows\n")

  All_Data <- bind_rows(All_Data, Scenario_Data)

}

cat("\nAll_Data:", nrow(All_Data), "rows\n")
cat("Year range:", min(All_Data$Year), "—", max(All_Data$Year), "\n")
cat("Run values:", paste(unique(All_Data$Run), collapse = ", "), "\n")

## head(All_Data)
## summary(All_Data)


## * Export Intermediate ######################################################

saveRDS(All_Data, file.path(Path_Output, "1-All_Data.RDS"))
cat("\nSaved: Data-Output/1-All_Data.RDS\n")
