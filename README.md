# FRIDA IAMC Post Processing

R code to process output files from FRIDA model to refactor and format in IAMC
format. One pipeline serves two submissions, selected by `Variable_Set` in
0-Main.R:

- **Diagnostic** — the IAM community diagnostic assessment protocol (core
  variables), deadline 1 Sep 2026.
- **Compass** — the Scenario Compass variable set (74 variables), deadline
  29 Sep 2026. Merged 2026-07-28 from the now-superseded
  FRIDA-Scenario-Compass-Post-Processing repository.

Each set has its own mapping CSV (`Mapping/Variable-Mapping-<set>.csv`) and
calculate script (`2-Calculate-<set>.R`, sharing `2-Constants.R`); stages
1/3/4 are generic. Intermediates and outputs are suffixed with the set name,
so both sets can be ingested side by side.

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
3. List the runs to report in `Data-Config/ScenarioInput.csv`. Each row's `id`
   is a parameter-space run id, a statistic name
   (`mean`/`median`/`defaultRun`/`Quantile*`), or `csvFiles` (read from
   `Data-Input/<scenario>.csv`), paired with a sub-scenario label and the Model
   name. See the ScenarioInput.csv section below for all options.
4. Choose the variable set (`Variable_Set <- "Diagnostic"` or `"Compass"`) and
   set the remaining run parameters in 0-Main.R.
5. Run the pipeline from 0-Main.R. Rerun with the other `Variable_Set` for the
   other submission — outputs do not overwrite each other.

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

One row per reported run. Each row picks a data series with `id`, labels it with
`subScenario`, and stamps a Model name with `model`. Run ids and statistic ids
can be mixed in the same file.

**`id`** — which series to read, one of two kinds:

- **A run id** (a number, e.g. `37996`) — reads that single parameter-space run
  from the per-variable files under
  `<folder>/detectedParmSpace/PerVarFiles-RDS/`.
- **A statistic name** — reads a precomputed statistic from the fit-uncertainty
  plotData CSVs under
  `<folder>/figures/CI-plots/completeEquallyWeighted/plotData/` instead. Allowed
  values:
  - `mean` — mean across the parameter space
  - `median` — the 50th percentile (alias for `Quantile0.5`)
  - `defaultRun` — the model's default (calibrated) run
  - `Quantile<q>` — any quantile column present in the plotData files, where
    `<q>` is the fraction: `Quantile0.025`, `Quantile0.165`, `Quantile0.5`,
    `Quantile0.835`, `Quantile0.975`
- **`csvFiles`** — reads a single-run trajectory straight from the top-level
  `Data-Input/<scenario>.csv` (a `Year` column plus one column per FRIDA
  variable, native names with `[1]` subscripts), keyed by the scenario name
  rather than the scenario folder. Unlike the other ids it does not look inside
  the scenario folder at all.

**`subScenario`** — the label appended to the scenario name in the output
(`Scenario_subScenario`). Leave it **blank** to keep the scenario name unchanged
(no suffix) — useful for a headline run such as `defaultRun`.

**`model`** — the Model name to stamp in the output.

| id | subScenario | model |
|---|---|---|
| csvFiles | | Model Name |
| defaultRun | | Model Name |
| Quantile0.025 | STAquantile2.5 | Model Name |
| Quantile0.5 | STAquantile50 | Model Name |
| Quantile0.975 | STAquantile97.5 | Model Name |
| \<run id> | STAp50 | Model Name |

Statistic ids require the plotData CSVs; run ids require the per-variable RDS
files; `csvFiles` requires the top-level `Data-Input/<scenario>.csv`. If a
variable is missing the requested statistic column, or a source a row needs is
not present, that piece is skipped with a note.

## Output Format

The output format adheres to IAMC timeseries data format guidelines. Model comes
from ScenarioInput.csv; the scenario name is the scenario label with the
sub-scenario label appended (`Scenario_subScenario`), or the scenario label alone
when the sub-scenario label is blank:

| Model | Scenario | Region | Variable | Unit | YYYY1 | YYYY2 | YYYY... |
|---|---|---|---|---|---|---|---|
| Model Name | ScenarioA | World | Variable Name | Units | xx.x | xxx.x | ... |
| Model Name | ScenarioA_STAquantile50 | World | Variable Name | Units | xx.x | xxx.x | ... |

## Process

### 0. Main

0-Main.R holds every parameter that changes between runs and sources the four
stages in order: 

- Variable_Set — "Diagnostic" or "Compass"; selects the mapping CSV
  (Path_Mapping), the calculate script, and the file suffix (File_Suffix) used
  on all intermediates and outputs
- Path_Input — Data-Input holds the FRIDA output folders
- Baseline_Scenario — reference scenario for loss-vs-baseline variables (default Current-Policies)
- Region_Name — output Region column
- Reported_Runs — subset of the ScenarioInput.csv sub-scenarios to report; unset = all
- Year_Start, Year_End — output year range; NA = full range in the data

The parameter sets to read and the Model name come from
Data-Config/ScenarioInput.csv rather than 0-Main.R. The stage scripts keep the
same parameters as defaults behind if (!exists(...)), so each can still be run
standalone in a fresh R session (defaulting to the Diagnostic set).


### 1. Ingest

- For each folder in FolderScenarioMap.csv, loads the series named in
  ScenarioInput.csv and stacks them into All_Data. Run ids come from the
  per-variable files under `<folder>/detectedParmSpace/PerVarFiles-RDS/`;
  statistic ids (mean/median/defaultRun/Quantile*) come from the fit-uncertainty
  plotData CSVs under `<folder>/figures/CI-plots/completeEquallyWeighted/plotData/`;
  `csvFiles` reads the wide single-run table `Data-Input/<scenario>.csv` directly
  (keyed by scenario name, not folder).
- Only the FRIDA variables named in the selected
  Mapping/Variable-Mapping-\<set>.csv are read, so the large files that never
  reach the output are never loaded off disk. Folders still downloading (a
  needed source not present yet, or missing variables) are skipped with a note.
- Each id's `subScenario` label becomes the Run (a blank label leaves the
  scenario name unsuffixed). One row per FRIDA variable, run, year, and scenario.
- Saves to Data-Output/1-All_Data-\<set>.RDS.

| Scenario | Variable | Run | Year | Value |
|---|---|---|---|---|
| ScenarioA | frida_variable | | YYYY | xx.xxx |
| ScenarioA | frida_variable | STAquantile50 | YYYY | xxx.xx |

### 2. Calculate

- One script per variable set: 2-Calculate-Diagnostic.R or
  2-Calculate-Compass.R (0-Main.R sources the one matching Variable_Set).
  Conversion constants shared by both live in 2-Constants.R; set-specific
  constants stay in the owning script's Preamble.
- Derives composite IAMC variables and applies unit conversions.
- Each IAMC variable that requires processing has its own section. Calculations
  are appended to All_Data under calc_ names.
- Saves to Data-Output/2-All_Data_Calc-\<set>.RDS.

### 3. Map

- Joins All_Data with the selected Mapping/Variable-Mapping-\<set>.csv to
  replace FRIDA variable keys with IAMC variable names and units.
- Add a row to the set's mapping CSV for each new variable.
- Unmapped variables are dropped. The last three columns document the FRIDA
  source, its units, and the transformation applied. One FRIDA/calc key may
  feed several IAMC variables (e.g. Compass Consumption also maps to
  Expenditure|Households).
- Saves to Data-Output/3-IAMC_Data-\<set>.RDS.

| IAMC Variable | IAMC Unit | IAMC Description | Variable | FRIDA Variable | FRIDA Unit | Transformation |
|---|---|---|---|---|---|---|
| IAMC Variable Name | unit | Description | frida_variable | Module.Variable name | unit | operation and constant |

## 4. Format and Export

- Filters to Reported_Runs and the Year_Start–Year_End horizon.
- Stamps the Model name from ScenarioInput.csv, adds the Region, appends the
  sub-scenario label to the Scenario name, pivots to the wide IAMC layout.
- Writes Data-Output/Data-Output-\<set>.csv and .xlsx (requires the writexl
  package).

