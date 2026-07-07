# Description:
#   Main control script. Defines every parameter that may change between runs
#   and sources the four pipeline stages in order. Edit the Parameters section,
#   then source this file to run the full pipeline.
#
#   The stage scripts define the same parameters with `if (!exists(...))`
#   fallbacks, so each can still be run standalone (fresh R session) for
#   line-by-line inspection. Note: parameters persist in the session after a
#   run — restart R or rm() them before relying on a stage script's defaults.
#
#   Inputs:  parameters below
#   Outputs: Data-Output/Data-Output.csv (plus stage intermediates)

## * Parameters ###############################################################

## ** Input data (1-Ingest.R)

# "Data-Input" = real FRIDA output; "Data-Input/Test-Data" = placeholder data.
Path_Input <- "Data-Input"

# Run types to ingest. c() = all (all three summary series + all ~100,000
# ensemble members — works, but slow).
#   Summary series:   "means", "defaultRun", "ciBounds_q50"
#   Ensemble members: "ensemble-1", "ensemble-50", etc.
Selected_Runs <- c(
  "defaultRun"
)

## ** Calculation (2-Calculate.R)

# Reference scenario for loss-vs-baseline variables (Policy Cost|Consumption
# Loss). Must match a scenario folder name in Path_Input.
Baseline_Scenario <- "policy_CP"

## ** Output format (4-Format-Export.R)

Model_Name  <- "FRIDA V3.1"  # confirm exact registered name for IIASA database
Region_Name <- "World"

# Runs to report. Each becomes its own Model value: "<Model_Name>_<Run>".
# Must be a subset of what Selected_Runs ingested.
Reported_Runs <- c(
  "means",
  "defaultRun",
  "ciBounds_q50",
  "ensemble-1"
)

# Year range for the output file. NA = full range present in the data.
Year_Start <- NA
Year_End   <- NA


## * Run Pipeline #############################################################

source("1-Ingest.R")
source("2-Calculate.R")
source("3-Map.R")
source("4-Format-Export.R")
