# Description:
#   Stages 4 + 5. Appends run identity to Model name, adds Region, renames
#   scenarios to protocol names, pivots wide, validates, and exports.
#
#   Inputs:  Data-Output/3-IAMC_Data.RDS
#   Outputs: Data-Output/Data-Output.csv
#            Columns: Model | Scenario | Region | Variable | Unit | <years>

library(tidyverse)
options(scipen = 999)


## * Preamble #################################################################

## ** Paths

Path_Output <- "Data-Output"
IAMC_Data   <- readRDS(file.path(Path_Output, "3-IAMC_Data.RDS"))

cat("Loaded IAMC_Data:", nrow(IAMC_Data), "rows\n\n")


## ** Constants

Model_Name    <- "FRIDA V3.1"  # confirm exact registered name for IIASA database
Region_Name   <- "World"

# Run values to include in the output. Use c(...) for multiple.
#   Summary series: "means", "defaultRun", "ciBounds_q50"
#   Ensemble members: "ensemble-1", "ensemble-5", etc.

Reported_Runs <- c(
  "means",
  "defaultRun",
  "ciBounds_q50",
  "ensemble-1"
  #"ensemble-2",
  )

# Year range for output. NA = use full range in the data.
Year_Start <- NA
Year_End   <- NA


## * Stage 4: Format ##########################################################

Horizon_Start <- if (is.na(Year_Start)) min(IAMC_Data$Year) else Year_Start
Horizon_End   <- if (is.na(Year_End))   max(IAMC_Data$Year) else Year_End

cat("Year horizon:", Horizon_Start, "—", Horizon_End, "\n\n")

IAMC_Wide <- IAMC_Data |>

  filter(Run %in% Reported_Runs,
         Year >= Horizon_Start,
         Year <= Horizon_End) |>

  mutate(
    Model    = paste0(Model_Name, "_", Run),   # e.g. "FRIDA V3.1_median", "FRIDA V3.1_ensemble-1"
    Region   = Region_Name,
    # Strip "policy_" prefix: "policy_C400-lin" -> "C400-lin" etc.
    Scenario = sub("^policy_", "", Scenario)
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