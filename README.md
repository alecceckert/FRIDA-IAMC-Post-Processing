# FRIDA IAMC Post Processing

R code to process output files from FRIDA model to refactor and format in IAMC format for submission to the IAM community diagnostic assessment protocol in 2026.

## Resources

IAM community diagnostic assessment protocol
https://zenodo.org/records/19554965

Variable List
https://docs.google.com/spreadsheets/d/1WB_QZ2r5vusTELJ-DnpAbMNpIvoQk-cK85VCdgOuv_Y/edit?gid=211150776#gid=211150776

## Instructions

1. Create one folder for each scenario in the Data-Input folder using
   scenario name as the folder name
2. Place relevant Ensemble or Median RDS files in the the relevant policy
   scenario. 
3. Set the run parameters in 0-Main.R.
4. Run pipeline from 0-Main.R

## Inputs

Scenario Inputs:
- policy_C0to400-lin
- policy_C80-gr5
- policy_C160-gr5
- policy_C400-lin
- policy_CP

## Output Format

The output format adheres to IAMC timeseries data format guidelines. Each
reported run becomes its own Model value. That follows the following structure:

| Model | Scenario | Region | Variable | Unit | YYYY1 | YYYY2 | YYYY... |
|---|---|---|---|---|---|---|---|
| FRIDA VX.X_means | Policy Name | World | Variable Name | Units | xx.s | xxx.x | ... |
| FRIDA VX.X_ensemble-X | Policy Name | World | Variable Name | Units | xx.x | xxx.x | ... |

## Process

### 0. Main

0-Main.R holds every parameter that changes between runs and sources the four
stages in order: 

- Path_Input — Data-Input for real FRIDA output, Data-Input/Test-Data for placeholders
- Selected_Runs — runs to ingest: any of means, defaultRun, ciBounds_q50, ensemble-<id>; c() = everything
- Baseline_Scenario — reference scenario for loss-vs-baseline variables (default policy_CP)
- Model_Name, Region_Name — output identity columns
- Reported_Runs — subset of ingested runs that reach the output file
- Year_Start, Year_End — output year range; NA = full range in the data

The stage scripts keep the same parameters as defaults behind if
(!exists(...)), so each can still be run standalone in a fresh R session.


### 1. Ingest

- Loads all summary RDS files from Data-Input/ and stacks into All_Data.
- One row per FRIDA variable, run, year, and scenario. Empty scenario folders
  are skipped.
- Summary files contribute the three central series (means, defaultRun,
  ciBounds_q50); ensemble files contribute one run per member id.
- Selected_Runs filters both at ingest. Saves to Data-Output/1-All_Data.RDS.

| Scenario | Variable | Run | Year | Value |
|---|---|---|---|---|
| policy_Scenario | frida_variable | means | YYYY | xx.xxx |
| policy_Scenario | frida_variable | ensemble-X | YYYY | xxx.xx |

### 2. Calculate

- Derives composite IAMC variables and applies unit conversions.
- Each IAMC variable that requires processing has its own section. Calculations.
  are appended to All_Data under calc_ names.

### 3. Map

- Joins All_Data with Mapping/Variable-Mapping.csv to replace FRIDA variable
  keys with IAMC variable names and units.
- Add a row to Variable-Mapping.csv for each new variable.
- Unmapped variables are dropped. The last three columns document the FRIDA
  source, its units, and the transformation applied.
- Saves to Data-Output/3-IAMC_Data.RDS.

| IAMC Variable | IAMC Unit | IAMC Description | Variable | FRIDA Variable | FRIDA Unit | Transformation |
|---|---|---|---|---|---|---|
| IAMC Variable Name | unit | Description | frida_variable | Module.Variable name | unit | operation and constant |

## 4. Format and Export

- Filters to Reported_Runs and the Year_Start–Year_End horizon.
- Appends the run name to the Model name, adds the Region and Scenario, pivots
  to the wide IAMC layout.  
- Writes Data-Output/Data-Output.csv

