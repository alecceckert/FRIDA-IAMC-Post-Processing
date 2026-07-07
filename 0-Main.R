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

# "Data-Input" = real FRIDA output (git-ignored); "Data-Config" holds the small
# tracked config files (FolderScenarioMap.csv, ScenarioInput.csv).
Path_Input  <- "Data-Input"
Path_Config <- "Data-Config"

# The run ids to ingest, their sub-scenario labels (percentiles), and the Model
# name are all listed in <Path_Config>/ScenarioInput.csv
# (columns: id | subScenario | model). Each run id becomes one Run; the label is
# appended to the scenario name in the output (Scenario_subScenario).

## ** Calculation (2-Calculate.R)

# Reference scenario for baseline-relative variables (Policy Cost|Consumption
# Loss, Policy Cost|Additional Total Energy System Cost). Must match a scenario
# name in Data-Input/FolderScenarioMap.csv (the CP / current-policy baseline).
Baseline_Scenario <- "CP"

## ** Output format (4-Format-Export.R)

Region_Name <- "World"

# Runs (sub-scenarios) to report. NA/unset = every sub-scenario in
# ScenarioInput.csv. Set to a subset of the labels (e.g. c("p50")) to restrict.
# Reported_Runs <- c("p0", "p50", "p100")

# Year range for the output file. NA = full range present in the data.
Year_Start <- NA
Year_End   <- NA


## * Run Pipeline #############################################################

source("1-Ingest.R")
source("2-Calculate.R")
source("3-Map.R")
source("4-Format-Export.R")
