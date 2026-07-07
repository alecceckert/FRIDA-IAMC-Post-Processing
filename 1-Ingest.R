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

# Defaults apply only when not already set (e.g. by 0-Main.R).
if (!exists("Path_Input")) Path_Input <- "Data-Input"
Path_Output <- "Data-Output"

## ** Constants

# Run types to ingest. c() = all.
#   Summary series: "means", "defaultRun", "ciBounds_q50"
#   Ensemble members: "ensemble-1", "ensemble-50", etc.

if (!exists("Selected_Runs")) Selected_Runs <- c(
  "means",
  "defaultRun",
  "ciBounds_q50",
  "ensemble-1",
  "ensemble-50"
  #"ensemble-100"
  )

## ** Derived from Selected_Runs

All_Summary_Runs <- c("means", "defaultRun", "ciBounds_q50")
Summary_Runs     <- if (length(Selected_Runs) == 0) All_Summary_Runs else intersect(Selected_Runs, All_Summary_Runs)

Ensemble_Entries <- grep("^ensemble-", Selected_Runs, value = TRUE)
Ensemble_IDs     <- if (length(Selected_Runs) == 0) NULL else as.integer(sub("^ensemble-", "", Ensemble_Entries))
# NULL = all ensemble members in file; integer(0) = none


## ** Ingest helpers

# Summary list -> tidy rows for all three central series. Variable = file stem. Scenario filled by caller.
Ingest_Median <- function(file) {

  Summary_List <- readRDS(file)
  Variable_Key <- sub("-fit uncertainty-completeEqually-weighted\\.RDS$", "", basename(file))
  Years        <- as.integer(Summary_List$years)

  bind_rows(
    tibble(Scenario = NA_character_, Variable = Variable_Key, Run = "means",
           Year = Years, Value = Summary_List$means),
    tibble(Scenario = NA_character_, Variable = Variable_Key, Run = "defaultRun",
           Year = Years, Value = Summary_List$defaultRun),
    tibble(Scenario = NA_character_, Variable = Variable_Key, Run = "ciBounds_q50",
           Year = Years, Value = Summary_List$ciBounds[, "0.5"])
  )

}

# Ensemble df -> same shape as Ingest_Median. ids = NULL loads all members. Scenario filled by caller.
Ingest_Ensemble <- function(file, ids = NULL) {

  Ensemble_DF  <- readRDS(file)
  Variable_Key <- sub("\\.RDS$", "", basename(file))

  if (!is.null(ids)) Ensemble_DF <- filter(Ensemble_DF, id %in% ids)

  Ensemble_DF |>
    pivot_longer(cols = -id, names_to = "Year", values_to = "Value") |>
    mutate(
      Scenario = NA_character_,
      Variable = Variable_Key,
      Run      = paste0("ensemble-", id),
      Year     = as.integer(Year)
    ) |>
    select(Scenario, Variable, Run, Year, Value)

}


## * Stage 1: Ingest ##########################################################

# Skip folders with no RDS files at all (e.g. policy_CP while data is still incoming).
All_Folders <- list.dirs(Path_Input, full.names = TRUE, recursive = FALSE)

Scenario_Folders <- All_Folders[
  sapply(All_Folders, function(Scenario_Dir) {
    length(list.files(Scenario_Dir, pattern = "\\.RDS$")) > 0
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

  Scenario_Data <- tibble()
  for (File in Median_Files) {
    Scenario_Data <- bind_rows(Scenario_Data, filter(Ingest_Median(File), Run %in% Summary_Runs))
  }

  Load_Ensemble <- is.null(Ensemble_IDs) || length(Ensemble_IDs) > 0
  if (Load_Ensemble) {
    Ensemble_Files <- list.files(Folder, pattern = "\\.RDS$", full.names = TRUE)
    Ensemble_Files <- Ensemble_Files[
      !grepl("-fit uncertainty-completeEqually-weighted\\.RDS$", Ensemble_Files)
    ]
    for (File in Ensemble_Files) {
      Scenario_Data <- bind_rows(Scenario_Data, Ingest_Ensemble(File, Ensemble_IDs))
    }
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
Run_Values <- unique(All_Data$Run)
if (length(Run_Values) > 10) {
  cat("Run values:", length(Run_Values), "distinct runs (", paste(head(Run_Values, 5), collapse = ", "), "... )\n")
} else {
  cat("Run values:", paste(Run_Values, collapse = ", "), "\n")
}

## head(All_Data)
## summary(All_Data)


## * Export Intermediate ######################################################

saveRDS(All_Data, file.path(Path_Output, "1-All_Data.RDS"))
cat("\nSaved: Data-Output/1-All_Data.RDS\n")