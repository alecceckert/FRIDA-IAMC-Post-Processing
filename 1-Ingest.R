# Description:
#   Stage 1. For every scenario folder, loads the per-variable parameter-space
#   RDS files, keeps only the sub-sampled parameter runs listed in
#   ScenarioInput.csv, and stacks them into All_Data. One row per FRIDA variable
#   per year per sub-sample run.
#
#   Each scenario folder holds one RDS per FRIDA variable under
#     <scenario>/detectedParmSpace/PerVarFiles-RDS/<frida_variable>.RDS
#   Each file is a data.frame: column `id` (run id) plus one column per year.
#   ScenarioInput.csv maps a chosen run id to a sub-scenario label (a percentile,
#   p0..p100); only those ids are read and the label becomes the Run. Stage 4
#   appends the label to the scenario name (Scenario_subScenario).
#
#   Only the FRIDA variables named in Mapping/Variable-Mapping.csv are loaded,
#   so the large per-var files that never reach the output are never read.
#
#   Inputs:  Data-Input/<folder>/detectedParmSpace/PerVarFiles-RDS/*.RDS
#            Data-Config/FolderScenarioMap.csv (folder -> scenario name)
#            Data-Config/ScenarioInput.csv     (id | subScenario | model)
#            Mapping/Variable-Mapping.csv       (FRIDA Variable column)
#   Outputs: Data-Output/1-All_Data.RDS
#            Columns: Scenario | Variable | Run | Year | Value

library(tidyverse)
options(scipen = 999)


## * Preamble #################################################################

## ** Paths

# Defaults apply only when not already set (e.g. by 0-Main.R).
if (!exists("Path_Input"))  Path_Input  <- "Data-Input"
if (!exists("Path_Config")) Path_Config <- "Data-Config"
Path_Output    <- "Data-Output"
Path_Mapping   <- file.path("Mapping", "Variable-Mapping.csv")
Path_Scenarios <- file.path(Path_Config, "ScenarioInput.csv")
Path_FolderMap <- file.path(Path_Config, "FolderScenarioMap.csv")

# Per-var files live under this sub-path inside each scenario folder.
PerVar_Subdir <- file.path("detectedParmSpace", "PerVarFiles-RDS")


## ** Folder -> scenario name

# Maps each input folder to the short scenario name used downstream, e.g.
# "IAMC-Scenario-...-policy_C0to400-lin-ClimateFeedback_On-..." -> "C0to400-lin"
# and the "UA-v3-1-..." baseline folder -> "CP".
Folder_Map <- read_csv(Path_FolderMap, show_col_types = FALSE)


## ** Sub-sample runs to ingest

# run id -> sub-scenario label (percentile). Each listed run id becomes one Run,
# selected identically from every scenario folder.
Scenario_Input <- read_csv(Path_Scenarios, show_col_types = FALSE)

cat("Sub-sample runs:", nrow(Scenario_Input), "—",
    paste(Scenario_Input$subScenario, collapse = ", "), "\n")


## ** FRIDA variables to load (driven by the mapping)

# A per-var file is named after its FRIDA variable, normalised to snake_case
# (lower-case, non-alphanumerics collapsed to "_"). Rebuild those stems from the
# mapping's `FRIDA Variable` column so only variables that can reach the output
# are read off disk. Parenthetical notes are dropped and compound "A + B"
# sources are split, matching the calc_ inputs used in 2-Calculate.R.
Mapping <- read_csv(Path_Mapping, show_col_types = FALSE)

Normalize_FRIDA_Key <- function(x) {
  x |>
    str_remove_all("\\([^)]*\\)") |>       # drop "(scenario and baseline)" notes
    str_split("\\+") |> unlist() |>         # compound "A + B" -> separate sources
    str_to_lower() |>
    str_replace_all("[^a-z0-9]+", "_") |>
    str_replace_all("^_+|_+$", "")
}

Needed_Variables <- Normalize_FRIDA_Key(Mapping$`FRIDA Variable`)
Needed_Variables <- unique(Needed_Variables[nzchar(Needed_Variables)])

cat("FRIDA variables needed by the mapping:", length(Needed_Variables), "\n\n")


## ** Ingest helper

# Per-var data.frame -> tidy rows for the sub-sampled ids only. The sub-scenario
# label becomes the Run; Scenario is filled by the caller.
Ingest_PerVar <- function(file, sub_runs) {

  Variable_Key <- sub("\\.RDS$", "", basename(file))

  readRDS(file) |>
    filter(id %in% sub_runs$id) |>
    pivot_longer(cols = -id, names_to = "Year", values_to = "Value") |>
    inner_join(sub_runs, by = "id") |>
    transmute(
      Scenario = NA_character_,
      Variable = Variable_Key,
      Run      = subScenario,
      Year     = as.integer(Year),
      Value
    )
}


## * Stage 1: Ingest ##########################################################

# Only mapped folders that already have the per-var directory (data may still
# be downloading for others; unmapped folders are ignored).
Scenario_Folders <- file.path(Path_Input, Folder_Map$folder)
Have_Data        <- dir.exists(file.path(Scenario_Folders, PerVar_Subdir))

if (any(!Have_Data)) {
  cat("Mapped folders without per-var data yet:",
      paste(Folder_Map$folder[!Have_Data], collapse = ", "), "\n")
}

Scenario_Folders <- Scenario_Folders[Have_Data]

cat("Scenario folders with per-var data:", length(Scenario_Folders), "\n")
for (Folder in Scenario_Folders) cat(" ", basename(Folder), "\n")
cat("\n")

All_Data <- tibble()

for (Folder in Scenario_Folders) {

  # Scenario name from the folder map, e.g. "C0to400-lin", "CP".
  Scenario_Name <- Folder_Map$scenario[Folder_Map$folder == basename(Folder)]

  PerVar_Dir      <- file.path(Folder, PerVar_Subdir)
  Available_Stems <- sub("\\.RDS$", "", list.files(PerVar_Dir, pattern = "\\.RDS$"))
  To_Load         <- intersect(Needed_Variables, Available_Stems)

  Not_Yet <- setdiff(Needed_Variables, Available_Stems)
  if (length(Not_Yet) > 0) {
    cat("  ", Scenario_Name, "— mapping variables not yet present:",
        paste(Not_Yet, collapse = ", "), "\n")
  }

  Scenario_Data <- tibble()
  for (Stem in To_Load) {
    File <- file.path(PerVar_Dir, paste0(Stem, ".RDS"))
    Scenario_Data <- bind_rows(Scenario_Data, Ingest_PerVar(File, Scenario_Input))
  }

  if (nrow(Scenario_Data) == 0) next
  Scenario_Data <- mutate(Scenario_Data, Scenario = Scenario_Name)

  cat(Scenario_Name, "—",
      length(To_Load), "variable(s):",
      paste(To_Load, collapse = ", "),
      "—", nrow(Scenario_Data), "rows\n")

  All_Data <- bind_rows(All_Data, Scenario_Data)

}

cat("\nAll_Data:", nrow(All_Data), "rows\n")
if (nrow(All_Data) > 0) {
  cat("Year range:", min(All_Data$Year), "—", max(All_Data$Year), "\n")
  cat("Run values:", paste(sort(unique(All_Data$Run)), collapse = ", "), "\n")
}

## head(All_Data)
## summary(All_Data)


## * Export Intermediate ######################################################

saveRDS(All_Data, file.path(Path_Output, "1-All_Data.RDS"))
cat("\nSaved: Data-Output/1-All_Data.RDS\n")
