# FRIDA IAMC Post Processing

R code to process output files from FRIDA model to refactor and format in IAMC format for submission to the IAM community diagnostic assessment protocol in 2026.

## Resources

IAM community diagnostic assessment protocol
https://zenodo.org/records/19554965

Variable List
https://docs.google.com/spreadsheets/d/1WB_QZ2r5vusTELJ-DnpAbMNpIvoQk-cK85VCdgOuv_Y/edit?gid=211150776#gid=211150776

## Instructions

1. Place each FRIDA uncertainty-analysis output folder in Data-Input. Each
   folder holds the per-variable parameter-space files under
   `<folder>/detectedParmSpace/PerVarFiles-RDS/<frida_variable>.RDS`.
2. List every input folder and its short scenario name in
   `Data-Config/FolderScenarioMap.csv`.
3. List the run ids to report, their sub-scenario labels (percentiles), and the
   Model name in `Data-Config/ScenarioInput.csv`.
4. Set the remaining run parameters in 0-Main.R.
5. Run the pipeline from 0-Main.R.

## Inputs

### Data-Config/FolderScenarioMap.csv

Maps each input folder (the full FRIDA output folder name) to the short scenario
name used in the output. Folders not listed here are ignored; the scenario name
is whatever short label you choose. One of these names is the reference scenario
set by `Baseline_Scenario` in 0-Main.R.

| folder | scenario |
|---|---|
| \<full FRIDA output folder name> | ScenarioA |
| \<full FRIDA output folder name> | ScenarioB |

### Data-Config/ScenarioInput.csv

One row per reported run. `id` is the run id to read from every per-variable
file; `subScenario` is the label appended to each scenario name in the output
(e.g. a percentile); `model` is the Model name to stamp.

| id | subScenario | model |
|---|---|---|
| \<run id> | p0 | Model Name |
| \<run id> | p50 | Model Name |
| \<run id> | p100 | Model Name |

## Output Format

The output format adheres to IAMC timeseries data format guidelines. Model comes
from ScenarioInput.csv; the scenario name is the scenario label with the
sub-scenario label appended (`Scenario_subScenario`):

| Model | Scenario | Region | Variable | Unit | YYYY1 | YYYY2 | YYYY... |
|---|---|---|---|---|---|---|---|
| Model Name | ScenarioA_p0 | World | Variable Name | Units | xx.x | xxx.x | ... |
| Model Name | ScenarioA_p50 | World | Variable Name | Units | xx.x | xxx.x | ... |

## Process

### 0. Main

0-Main.R holds every parameter that changes between runs and sources the four
stages in order: 

- Path_Input — Data-Input for real FRIDA output, Data-Input/Test-Data for placeholders
- Baseline_Scenario — reference scenario for loss-vs-baseline variables (default CP)
- Region_Name — output Region column
- Reported_Runs — subset of the ScenarioInput.csv sub-scenarios to report; unset = all
- Year_Start, Year_End — output year range; NA = full range in the data

The parameter sets to read and the Model name come from
Data-Input/ScenarioInput.csv rather than 0-Main.R. The stage scripts keep the
same parameters as defaults behind if (!exists(...)), so each can still be run
standalone in a fresh R session.


### 1. Ingest

- For each folder in FolderScenarioMap.csv, loads the per-variable files under
  `<folder>/detectedParmSpace/PerVarFiles-RDS/` and stacks them into All_Data.
- Only the FRIDA variables named in Mapping/Variable-Mapping.csv are read, so
  the large files that never reach the output are never loaded off disk. Folders
  still downloading (no per-var directory yet, or missing variables) are skipped
  with a note.
- Each per-var file is a data.frame of `id` (run id) + one column per year. Only
  the run ids in ScenarioInput.csv are kept; each id's `subScenario` label
  becomes the Run. One row per FRIDA variable, run, year, and scenario.
- Saves to Data-Output/1-All_Data.RDS.

| Scenario | Variable | Run | Year | Value |
|---|---|---|---|---|
| ScenarioA | frida_variable | p0 | YYYY | xx.xxx |
| ScenarioA | frida_variable | p50 | YYYY | xxx.xx |

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

