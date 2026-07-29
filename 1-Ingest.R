# Description:
#   Stage 1. For every scenario folder, loads the per-variable parameter-space
#   RDS files, keeps only the sub-sampled parameter runs listed in
#   ScenarioInput.csv, and stacks them into All_Data. One row per FRIDA variable
#   per year per sub-sample run.
#
#   Each scenario folder holds one RDS per FRIDA variable under
#     <scenario>/detectedParmSpace/PerVarFiles-RDS/<frida_variable>.RDS
#   Each file is a data.frame: column `id` (run id) plus one column per year.
#   ScenarioInput.csv maps a chosen id to a sub-scenario label (e.g. STAp0..
#   STAp100) that becomes the Run; Stage 4 appends it to the scenario name
#   (Scenario_subScenario). An id is one of three kinds:
#     - a numeric run id  -> that run is read from the per-var RDS above.
#     - a statistic name  -> read from the fit-uncertainty plotData CSV instead
#       (mean, median, defaultRun, or any Quantile* column; median = Quantile0.5).
#       plotData holds one CSV per variable with a year column plus one column
#       per statistic, under figures/CI-plots/completeEquallyWeighted/plotData/.
#     - "csvFiles"         -> read a single-run trajectory from the top-level
#       Data-Input/<scenario>.csv (Year column + one column per FRIDA variable,
#       native names with [1] subscripts), independent of the scenario folder.
#
#   Only the FRIDA variables named in Mapping/Variable-Mapping.csv are loaded,
#   so the large per-var files that never reach the output are never read.
#
#   Inputs:  Data-Input/<folder>/detectedParmSpace/PerVarFiles-RDS/*.RDS
#            Data-Input/<folder>/figures/CI-plots/completeEquallyWeighted/plotData/*.csv
#            Data-Input/<scenario>.csv          (csvFiles: wide single-run table)
#            Data-Config/FolderScenarioMap.csv (folder -> scenario name)
#            Data-Config/ScenarioInput.csv     (id | subScenario | model)
#            Mapping/Variable-Mapping-<set>.csv (FRIDA Variable column;
#            set by Path_Mapping from Variable_Set in 0-Main.R)
#   Outputs: Data-Output/1-All_Data-<set>.RDS
#            Columns: Scenario | Variable | Run | Year | Value

library(tidyverse)
options(scipen = 999)


## * Preamble #################################################################

## ** Paths

# Defaults apply only when not already set (e.g. by 0-Main.R).
if (!exists("Path_Input"))   Path_Input   <- "Data-Input"
if (!exists("Path_Config"))  Path_Config  <- "Data-Config"
if (!exists("Path_Mapping")) Path_Mapping <- file.path("Mapping", "Variable-Mapping-Diagnostic.csv")
if (!exists("File_Suffix"))  File_Suffix  <- "-Diagnostic"
Path_Output    <- "Data-Output"
Path_Scenarios <- file.path(Path_Config, "ScenarioInput.csv")
Path_FolderMap <- file.path(Path_Config, "FolderScenarioMap.csv")

# Per-var files live under this sub-path inside each scenario folder.
PerVar_Subdir <- file.path("detectedParmSpace", "PerVarFiles-RDS")

# Statistic runs (mean/median/defaultRun/Quantile*) are not in the per-var
# parameter-space files; they come from the fit-uncertainty plotData CSVs, one
# per FRIDA variable (a year column plus one column per statistic), named
# "<stem><PlotData_Suffix>".
PlotData_Subdir <- file.path("figures", "CI-plots", "completeEquallyWeighted", "plotData")
PlotData_Suffix <- "-fit uncertainty-completeEqually-weighted.csv"


## ** Folder -> scenario name

# Maps each input folder to the short scenario name used downstream, e.g.
# "IAMC-Scenario-...-policy_C0to400-lin-ClimateFeedback_On-..." -> "C0to400-lin"
# and the "UA-v3-1-..." baseline folder -> "Current-Policies".
Folder_Map <- read_csv(Path_FolderMap, show_col_types = FALSE)


## ** Sub-sample runs to ingest

# id -> sub-scenario label. Each listed id becomes one Run, selected identically
# from every scenario folder. id is read as text so numeric run ids and
# statistic ids (mean, median, defaultRun, Quantile0.5, ...) can share the column.
Scenario_Input <- read_csv(Path_Scenarios, show_col_types = FALSE,
                           col_types = cols(id = col_character()))

# A statistic id names a plotData column directly (median is the 0.5 quantile);
# "csvFiles" reads a wide per-scenario CSV from Data-Input; every other id is a
# parameter-space run id read from the per-var RDS.
Is_Stat_Id  <- function(id) id %in% c("mean", "median", "defaultRun") |
                            str_starts(id, "Quantile")
Is_Csv_Id   <- function(id) id == "csvFiles"
Stat_Column <- function(id) if_else(id == "median", "Quantile0.5", id)

Run_Input  <- Scenario_Input |>
  filter(!Is_Stat_Id(id), !Is_Csv_Id(id)) |> mutate(id = as.numeric(id))
Stat_Input <- Scenario_Input |> filter(Is_Stat_Id(id))
Csv_Input  <- Scenario_Input |> filter(Is_Csv_Id(id))
Need_Runs  <- nrow(Run_Input)  > 0
Need_Stats <- nrow(Stat_Input) > 0
Need_Csv   <- nrow(Csv_Input)  > 0

cat("Sub-sample runs:", nrow(Scenario_Input), "—",
    paste(Scenario_Input$subScenario, collapse = ", "), "\n")
if (Need_Stats)
  cat("  statistic runs (from plotData):",
      paste(Stat_Input$id, "->", Stat_Input$subScenario, collapse = ", "), "\n")
if (Need_Csv)
  cat("  csvFiles runs (from Data-Input/<scenario>.csv):", nrow(Csv_Input), "\n")


## ** FRIDA variables to load (driven by the mapping)

# A per-var file is named after its FRIDA variable, normalised to snake_case
# (lower-case, non-alphanumerics collapsed to "_"). Rebuild those stems from the
# mapping's `FRIDA Variable` column so only variables that can reach the output
# are read off disk. Parenthetical notes and [1]/[*] element subscripts are
# dropped; compound "A + B" (sums) and "A over B" (ratios, e.g. the Compass
# food-per-capita rows) sources are split, matching the calc_ inputs used in
# the 2-Calculate-<set>.R scripts.
Mapping <- read_csv(Path_Mapping, show_col_types = FALSE)

Normalize_FRIDA_Key <- function(x) {
  x |>
    str_remove_all("\\([^)]*\\)") |>       # drop "(scenario and baseline)" notes
    str_remove_all("\\[[^]]*\\]") |>       # drop [1]/[*] element subscripts
    str_split("\\+|\\s+over\\s+") |> unlist() |>  # "A + B" / "A over B" -> separate sources
    str_to_lower() |>
    str_replace_all("[^a-z0-9]+", "_") |>
    str_replace_all("^_+|_+$", "")
}

# csvFiles headers are FRIDA-native names with array subscripts, e.g.
# "CCS.Captured CO2 to store[1]". Strip the [..] subscript, then normalise the
# same way so the columns line up with Needed_Variables. Element-wise (no "+"
# split) so column positions are preserved.
Normalize_CSV_Header <- function(x) {
  x |>
    str_remove_all("\\[[^]]*\\]") |>       # drop [1]/[*] element subscripts
    str_remove_all("\\([^)]*\\)") |>       # drop parenthetical notes
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

# plotData CSV -> tidy rows for the statistic runs only. Each stat id selects one
# column (Stat_Column maps median -> Quantile0.5); its subScenario becomes the Run.
Ingest_PerVar_Stat <- function(file, stem, stat_runs) {

  Wide <- read_csv(file, show_col_types = FALSE)

  Rows <- map(seq_len(nrow(stat_runs)), function(i) {
    Column <- Stat_Column(stat_runs$id[i])
    if (!Column %in% names(Wide)) {
      cat("    ", stem, "— plotData has no column", Column, "— skipped\n")
      return(NULL)
    }
    tibble(
      Scenario = NA_character_,
      Variable = stem,
      Run      = stat_runs$subScenario[i],
      Year     = as.integer(Wide$year),
      Value    = Wide[[Column]]
    )
  })

  bind_rows(Rows)
}

# Wide scenario CSV (Data-Input/<scenario>.csv) -> tidy rows for the mapped
# variables only. Header FRIDA names are normalised to snake_case keys; each
# csvFiles row's subScenario becomes the Run.
Ingest_ScenarioCsv <- function(file, csv_runs) {

  Wide <- read_csv(file, show_col_types = FALSE)
  names(Wide) <- Normalize_CSV_Header(names(Wide))    # native headers -> snake keys

  Long <- Wide |>
    pivot_longer(cols = -year, names_to = "Variable", values_to = "Value") |>
    filter(Variable %in% Needed_Variables)

  map_dfr(seq_len(nrow(csv_runs)), function(i) {
    transmute(Long,
      Scenario = NA_character_,
      Variable,
      Run      = csv_runs$subScenario[i],
      Year     = as.integer(year),
      Value
    )
  })
}


## * Stage 1: Ingest ##########################################################

All_Data <- tibble()


## ** Folder sources: run ids (per-var RDS) + statistic ids (plotData) --------

# Only mapped folders that already have every requested folder source (data may
# still be downloading for others; unmapped folders are ignored).
if (Need_Runs || Need_Stats) {

  Scenario_Folders <- file.path(Path_Input, Folder_Map$folder)
  Have_PerVar      <- dir.exists(file.path(Scenario_Folders, PerVar_Subdir))
  Have_PlotData    <- dir.exists(file.path(Scenario_Folders, PlotData_Subdir))

  # Ingest a folder only once every requested source is present: per-var RDS for
  # run ids, plotData for statistic ids.
  Have_Data <- (!Need_Runs | Have_PerVar) & (!Need_Stats | Have_PlotData)

  if (any(!Have_Data)) {
    cat("Mapped folders without all requested data yet:",
        paste(Folder_Map$folder[!Have_Data], collapse = ", "), "\n")
  }

  Scenario_Folders <- Scenario_Folders[Have_Data]

  cat("Scenario folders with per-var data:", length(Scenario_Folders), "\n")
  for (Folder in Scenario_Folders) cat(" ", basename(Folder), "\n")
  cat("\n")

  for (Folder in Scenario_Folders) {

    # Scenario name from the folder map, e.g. "C0to400-lin", "Current-Policies".
    Scenario_Name <- Folder_Map$scenario[Folder_Map$folder == basename(Folder)]

    PerVar_Dir   <- file.path(Folder, PerVar_Subdir)
    PlotData_Dir <- file.path(Folder, PlotData_Subdir)

    # Stems available from each source; their union drives what can be loaded.
    PerVar_Stems    <- sub("\\.RDS$", "", list.files(PerVar_Dir, pattern = "\\.RDS$"))
    PlotData_Stems  <- sub(PlotData_Suffix, "",
                           list.files(PlotData_Dir, pattern = "\\.csv$"), fixed = TRUE)
    Available_Stems <- union(PerVar_Stems, PlotData_Stems)
    To_Load         <- intersect(Needed_Variables, Available_Stems)

    Not_Yet <- setdiff(Needed_Variables, Available_Stems)
    if (length(Not_Yet) > 0) {
      cat("  ", Scenario_Name, "— mapping variables not yet present:",
          paste(Not_Yet, collapse = ", "), "\n")
    }

    Scenario_Data <- tibble()
    for (Stem in To_Load) {

      # Parameter-space run ids from the per-var RDS.
      if (Need_Runs) {
        RDS_File <- file.path(PerVar_Dir, paste0(Stem, ".RDS"))
        if (file.exists(RDS_File))
          Scenario_Data <- bind_rows(Scenario_Data, Ingest_PerVar(RDS_File, Run_Input))
      }

      # Statistic ids from the plotData CSV.
      if (Need_Stats) {
        CSV_File <- file.path(PlotData_Dir, paste0(Stem, PlotData_Suffix))
        if (file.exists(CSV_File))
          Scenario_Data <- bind_rows(Scenario_Data,
                                     Ingest_PerVar_Stat(CSV_File, Stem, Stat_Input))
      }
    }

    if (nrow(Scenario_Data) == 0) next
    Scenario_Data <- mutate(Scenario_Data, Scenario = Scenario_Name)

    cat(Scenario_Name, "—",
        length(To_Load), "variable(s):",
        paste(To_Load, collapse = ", "),
        "—", nrow(Scenario_Data), "rows\n")

    All_Data <- bind_rows(All_Data, Scenario_Data)

  }

}


## ** csvFiles source: one wide Data-Input/<scenario>.csv per scenario --------

# Reads a single-run trajectory straight from Data-Input/<scenario>.csv, keyed by
# the scenario name (not the folder). Scenarios whose CSV is not present yet are
# skipped with a note.
if (Need_Csv) {

  for (Row in seq_len(nrow(Folder_Map))) {

    Scenario_Name <- Folder_Map$scenario[Row]
    Csv_File      <- file.path(Path_Input, paste0(Scenario_Name, ".csv"))

    if (!file.exists(Csv_File)) {
      cat("  ", Scenario_Name, "— csvFiles: no", basename(Csv_File), "yet\n")
      next
    }

    Csv_Data <- Ingest_ScenarioCsv(Csv_File, Csv_Input) |>
      mutate(Scenario = Scenario_Name)

    cat(Scenario_Name, "— csvFiles:",
        length(unique(Csv_Data$Variable)), "variable(s) —", nrow(Csv_Data), "rows\n")

    All_Data <- bind_rows(All_Data, Csv_Data)

  }

}

cat("\nAll_Data:", nrow(All_Data), "rows\n")
if (nrow(All_Data) > 0) {
  cat("Year range:", min(All_Data$Year), "—", max(All_Data$Year), "\n")
  cat("Run values:", paste(sort(unique(All_Data$Run)), collapse = ", "), "\n")
}

## head(All_Data)
## summary(All_Data)


## * Export Intermediate ######################################################

saveRDS(All_Data, file.path(Path_Output, paste0("1-All_Data", File_Suffix, ".RDS")))
cat("\nSaved: Data-Output/1-All_Data", File_Suffix, ".RDS\n", sep = "")
