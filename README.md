# FRIDA IAMC Post Processing

R code to process output files from FRIDA model to refactor and format in IAMC format for submission to the IAM community diagnostic assessment protocol in 2026.

## Resources

IAM community diagnostic assessment protocol
https://zenodo.org/records/19554965

Variable List
https://docs.google.com/spreadsheets/d/1WB_QZ2r5vusTELJ-DnpAbMNpIvoQk-cK85VCdgOuv_Y/edit?gid=211150776#gid=211150776

## Instructions

1. Create one folder for each scenario in the Data-Input folder
2. Place relevant Ensemble or Median RDS files in the the relevant policy scenario.

## Inputs

Scenario Inputs:
- policy_C0to400-lin
- policy_C80-gr5
- policy_C160-gr5
- policy_C400-lin
- policy_CP

## Output Format

The output format adheres to IAMC timeseries data format guidelines. That follows the following structure:

| Model | Scenario | Region | Variable | Unit | YYYY1 | YYYY2 | YYYY... |
|---|---|---|---|---|---|---|---|
| FRIDA V3.1_median | Policy Name | World | Variable Name | Units | XX.X | XX.X | ... |
| FRIDA V3.1_ensemble-1 | Policy Name | World | Variable Name | Units | XX.X | XX.X | ... |

## Process

## 1. Ingest

Loads all summary RDS files from `Data-Input/` and stacks into `All_Data`. One row per FRIDA variable, year, and scenario. Empty scenario folders are skipped. Saves to `Data-Output/1-All_Data.RDS`.

Set `Central_Series` in the Preamble to select the central value (`means`, `defaultRun`, or `ciBounds_q50`). Set `Ensemble_IDs` to pull specific ensemble members alongside the median — e.g. `c(1, 5, 100)`. Leave as `c()` for median only.

| Scenario | Variable | Run | Year | Value |
|---|---|---|---|---|
| policy_Scenario | frida_variable | median | YYYY | xx.xxx |
| policy_Scenario | frida_variable | ensemble-1 | YYYY | xxx.xx |

## 2. Calculate

Derives composite IAMC variables and applies unit conversions. Each IAMC variable that requires processing has its own section. Derived rows are appended to `All_Data` under `calc_` names. Pass-through variables (no calculation needed) skip this stage and map directly in `Variable-Mapping.csv`. Saves to `Data-Output/2-All_Data_Calc.RDS`.

## 3. Map

Joins `All_Data` with `Mapping/Variable-Mapping.csv` to replace FRIDA variable keys with IAMC variable names and units. Add a row to `Variable-Mapping.csv` for each new variable — pass-throughs and `calc_` intermediates are handled identically. Unmapped variables are dropped. Saves to `Data-Output/3-IAMC_Data.RDS`.

| IAMC Variable | IAMC Unit | IAMC Description | Variable |
|---|---|---|---|
| IAMC Variable Name | unit | Description | frida_variable |