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
| FRIDA V3.1 | Policy Name | World | Variable Name | Units | XX.X | XX.X | ... |

## Process

## 1. Ingest

Loads all summary RDS files from `Data-Input/` and stacks into `All_Data`. One row per FRIDA variable, year, and scenario. Empty scenario folders are skipped. Saves to `Data-Output/1-All_Data.RDS`.

Output Table from ingest follows the format:

| Scenario | Variable | Run | Year | Value |
|---|---|---|---|---|
| policy_C400-lin | emissions_total_co2_emissions | median | 1980 | 23501.05 |
| policy_C400-lin | ccs_captured_co2_to_store | median | 1980 | 0.14 |