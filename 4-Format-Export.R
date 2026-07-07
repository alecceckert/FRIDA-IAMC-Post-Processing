# Description:
#   Stages 4 + 5. Sets the Model name and adds Region, appends the sub-scenario
#   (percentile) to the scenario name, pivots wide, validates, and exports.
#
#   Inputs:  Data-Output/3-IAMC_Data.RDS
#            Data-Config/ScenarioInput.csv  (subScenario -> model)
#   Outputs: Data-Output/Data-Output.csv
#            Columns: Model | Scenario | Region | Variable | Unit | <years>

library(tidyverse)
options(scipen = 999)


## * Preamble #################################################################

## ** Paths

if (!exists("Path_Config")) Path_Config <- "Data-Config"
Path_Output <- "Data-Output"
IAMC_Data   <- readRDS(file.path(Path_Output, "3-IAMC_Data.RDS"))

cat("Loaded IAMC_Data:", nrow(IAMC_Data), "rows\n\n")


## ** Constants

# Defaults apply only when not already set (e.g. by 0-Main.R).
if (!exists("Region_Name")) Region_Name <- "World"

# Model name and the runs to report both come from ScenarioInput.csv: each
# sub-scenario label (percentile) is a Run, carrying the Model name to stamp.
Scenario_Input <- read_csv(file.path(Path_Config, "ScenarioInput.csv"),
                           show_col_types = FALSE)
Run_Model <- distinct(Scenario_Input, Run = subScenario, Model = model)

# Run values to include in the output. Default: every sub-scenario in the file.
if (!exists("Reported_Runs")) Reported_Runs <- Scenario_Input$subScenario

# Year range for output. NA = use full range in the data.
if (!exists("Year_Start")) Year_Start <- NA
if (!exists("Year_End"))   Year_End   <- NA


## * Stage 4: Format ##########################################################

Horizon_Start <- if (is.na(Year_Start)) min(IAMC_Data$Year) else Year_Start
Horizon_End   <- if (is.na(Year_End))   max(IAMC_Data$Year) else Year_End

cat("Year horizon:", Horizon_Start, "—", Horizon_End, "\n\n")

IAMC_Wide <- IAMC_Data |>

  filter(Run %in% Reported_Runs,
         Year >= Horizon_Start,
         Year <= Horizon_End) |>

  left_join(Run_Model, by = "Run") |>       # Model name per sub-scenario

  mutate(
    Region   = Region_Name,
    # Append the sub-scenario (percentile): "C400-lin" + "p50" -> "C400-lin_p50".
    Scenario = paste0(Scenario, "_", Run)
  ) |>

  pivot_wider(
    id_cols     = c(Model, Scenario, Region, Variable, Unit),
    names_from  = Year,
    values_from = Value
  ) |>

  arrange(Scenario, Variable)

cat("IAMC_Wide:", nrow(IAMC_Wide), "rows x", ncol(IAMC_Wide), "columns\n")
cat("Scenarios:", paste(sort(unique(IAMC_Wide$Scenario)), collapse = ", "), "\n")
cat("Variables:", paste(sort(unique(IAMC_Wide$Variable)), collapse = ", "), "\n\n")


## ** Validation checks -------------------------------------------------------

Year_Column_Names <- setdiff(colnames(IAMC_Wide), c("Model", "Scenario", "Region", "Variable", "Unit"))
All_Scenarios     <- sort(unique(IAMC_Wide$Scenario))

if ("2060" %in% Year_Column_Names) {
  cat("CHECK PASS: year 2060 present\n")
} else {
  cat("CHECK FAIL: year 2060 missing\n")
}

Incomplete_Coverage <- IAMC_Wide |>
  count(Variable, name = "N_Scenarios") |>
  filter(N_Scenarios < length(All_Scenarios))

if (nrow(Incomplete_Coverage) == 0) {
  cat("CHECK PASS: all IAMC variables present in all", length(All_Scenarios), "scenarios\n")
} else {
  cat("CHECK WARN: variable(s) missing in one or more scenarios:\n")
  print(Incomplete_Coverage)
}

NA_Value_Count <- sum(is.na(select(IAMC_Wide, all_of(Year_Column_Names))))
if (NA_Value_Count == 0) {
  cat("CHECK PASS: no NA values in year columns\n")
} else {
  cat("CHECK WARN:", NA_Value_Count, "NA(s) in year columns\n")
}

## head(IAMC_Wide[, 1:10])
## filter(IAMC_Wide, Variable == "Emissions|CO2")


## * Stage 5: Export ##########################################################

Output_File <- file.path(Path_Output, "Data-Output.csv")
write.csv(IAMC_Wide, Output_File, na = "", row.names = FALSE)

cat("\nSaved:", Output_File, "\n")
cat("Final output:", nrow(IAMC_Wide), "rows,", ncol(IAMC_Wide), "columns\n")
cat("Year columns:", length(Year_Column_Names), "(", min(Year_Column_Names), "-", max(Year_Column_Names), ")\n")