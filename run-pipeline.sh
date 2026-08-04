#!/usr/bin/env bash
#
# Description:
#   End-to-end runner for the FRIDA IAMC post-processing pipeline. Asks which
#   variable set to build — Compass or Diagnostic — shows exactly how the output
#   will be produced (which folder feeds which scenario, which series each one
#   contributes, what lands in the Scenario column), asks for confirmation, then
#   runs 0-Main.R (stages 1-4) via Rscript. Every other parameter still comes
#   from 0-Main.R and Data-Config/.
#
#   Usage: ./run-pipeline.sh [compass|diagnostic|both] [options]
#
#     -y, --yes             skip the confirmation prompt
#     --no-subscenarios     report only the unlabelled headline run, so no
#                           Scenario:subScenario names appear (Diagnostic runs)
#     --no-install          report missing R packages instead of installing them
#
#   With no set argument it prompts for the choice, so a batch job (SLURM, no
#   terminal) must name the set and is never prompted:
#
#     module load r
#     ./run-pipeline.sh diagnostic --no-subscenarios
#
#   Inputs:  Data-Input/ (FRIDA output folders), Data-Config/*.csv
#   Outputs: Data-Output/Data-Output-<set>.csv and .xlsx (plus stage
#            intermediates, all suffixed with the set name)

set -euo pipefail

Script_Dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$Script_Dir"

Install_Missing=1
Assume_Yes=0
No_SubScenarios=0

Folder_Map="Data-Config/FolderScenarioMap.csv"
Scenario_Input="Data-Config/ScenarioInput.csv"

# Subdirectories 1-Ingest.R reads inside a scenario folder.
PerVar_Subdir="detectedParmSpace/PerVarFiles-RDS"
PlotData_Subdir="figures/CI-plots/completeEquallyWeighted/plotData"


## * Helpers ##################################################################

Usage() {
  cat <<'EOF'
Usage: ./run-pipeline.sh [compass|diagnostic|both] [options]

  compass             Scenario Compass variable set
  diagnostic          IAM community diagnostic assessment protocol
  both                run each set in turn (outputs do not overwrite each other)

  -y, --yes           skip the confirmation prompt
  --no-subscenarios   report only the unlabelled headline run, so every output
                      Scenario is a plain name with no ":subScenario" suffix
  --no-install        do not install missing R packages, just report them

With no set argument the script prompts for the choice; a batch job with no
terminal must name the set, e.g.  ./run-pipeline.sh compass --yes
EOF
}

# R reads these UTF-8 source files in the locale encoding, so a C/POSIX locale
# (the default in many batch jobs) can fail on the non-ASCII characters in the
# scripts. Settle on a UTF-8 locale when the environment has not set one.
Ensure_Utf8_Locale() {
  case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
    *UTF-8*|*utf-8*|*UTF8*|*utf8*) return 0 ;;
  esac

  # Matched in-shell rather than through a pipe: under pipefail, grep -q exiting
  # early makes the producer take SIGPIPE and the whole pipeline read as failure.
  local Available Candidate
  Available=$'\n'"$(locale -a 2>/dev/null || true)"$'\n'

  for Candidate in C.UTF-8 C.utf8 en_US.UTF-8 en_US.utf8; do
    if [[ $Available == *$'\n'"$Candidate"$'\n'* ]]; then
      export LC_ALL="$Candidate" LANG="$Candidate"
      return 0
    fi
  done

  echo "WARNING: no UTF-8 locale available; R may fail on non-ASCII characters" >&2
  echo "         in the pipeline scripts. Set LANG to a UTF-8 locale if it does." >&2
  echo >&2
}

# Maps a case-insensitive answer or menu number onto the canonical set name
# used in the file names (Compass / Diagnostic / Both).
Canonical_Set() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    1|c|compass)    echo "Compass" ;;
    2|d|diagnostic) echo "Diagnostic" ;;
    3|b|both)       echo "Both" ;;
    *)              return 1 ;;
  esac
}

# Value of a scalar parameter assigned in 0-Main.R, quotes stripped. Only used
# for the plan display, so an unreadable value simply prints as given.
R_Param() {
  sed -n "s/^[[:space:]]*$1[[:space:]]*<-[[:space:]]*\(.*\)\$/\1/p" 0-Main.R |
    tail -1 | sed 's/[[:space:]]*#.*$//; s/^"//; s/"$//'
}


## * R packages ###############################################################

# Every package the pipeline library()s. These are the tidyverse components the
# stages actually use rather than the tidyverse meta-package, which additionally
# requires dbplyr and ragg — ragg needs system font libraries (fontconfig,
# harfbuzz) that a cluster module does not provide, so it cannot be built there.
R_Packages=(dplyr tidyr readr stringr purrr tibble writexl)

# Prints the subset of its arguments R cannot load, one per line.
Missing_Packages() {
  Rscript -e '
    Pkgs <- commandArgs(TRUE)
    cat(Pkgs[!vapply(Pkgs, function(p) nzchar(system.file(package = p)), logical(1))], sep = "\n")
  ' "$@" 2>/dev/null
}

# Advice shared by every "packages are missing and cannot be installed" path.
Cluster_Hint() {
  echo "       On a cluster, an R module often already provides them:" >&2
  echo "         module avail r      then  module load r/<version>" >&2
  echo "       Otherwise install once from a node with outbound network" >&2
  echo "       (a login node) — the library persists for later batch jobs." >&2
}

# Installs whatever is missing into the first writable library, from CRAN.
# Rscript never prompts for a mirror or offers to create a personal library the
# way interactive R does, so both are resolved explicitly. The site library on a
# cluster is read-only, so this lands in R_LIBS_USER there. CRAN is probed with
# a short timeout first: compute nodes usually have no outbound network, and an
# unreachable mirror would otherwise stall the job on a download.
Ensure_R_Packages() {
  local Missing
  Missing=$(Missing_Packages "${R_Packages[@]}")
  [[ -z $Missing ]] && return 0

  local Listed
  Listed=$(echo "$Missing" | tr '\n' ' ')

  if [[ $Install_Missing -eq 0 ]]; then
    echo "ERROR: missing R package(s): $Listed" >&2
    echo "       --no-install was given, so nothing was installed." >&2
    Cluster_Hint
    exit 1
  fi

  echo "Installing missing R package(s): $Listed"
  echo "(no binaries on Linux — these are compiled from source, which on a first"
  echo " install can take several minutes)"
  echo

  local Status=0
  Rscript -e '
    Pkgs <- commandArgs(TRUE)

    Repo <- unname(getOption("repos")["CRAN"])
    if (is.na(Repo) || !nzchar(Repo) || Repo == "@CRAN@")
      Repo <- "https://cloud.r-project.org"

    # Prefer the first writable library already on the path (the site library is
    # read-only on a cluster); fall back to the user library R names but has not
    # created yet.
    Lib <- Filter(function(p) file.access(p, 2) == 0, .libPaths())
    Lib <- if (length(Lib) > 0) Lib[1] else Sys.getenv("R_LIBS_USER")
    if (!nzchar(Lib)) {
      cat("no writable R library found and R_LIBS_USER is unset\n", file = stderr())
      quit(status = 4)
    }
    if (!dir.exists(Lib)) dir.create(Lib, recursive = TRUE)
    .libPaths(c(Lib, .libPaths()))

    cat("Library:   ", Lib, "\n")
    cat("Repository:", Repo, "\n\n")

    # Honours http_proxy/https_proxy, so a proxied login node still works.
    options(timeout = 20)
    Reachable <- tryCatch({
      Con <- url(Repo, open = "rb"); close(Con); TRUE
    }, error = function(e) FALSE, warning = function(w) FALSE)
    if (!Reachable) quit(status = 3)

    install.packages(Pkgs, lib = Lib, repos = Repo)
  ' $Missing || Status=$?

  if [[ $Status -ne 0 ]]; then
    echo >&2
    case $Status in
      3) echo "ERROR: CRAN is not reachable from this machine, so $Listed" >&2
         echo "       cannot be installed here." >&2
         Cluster_Hint ;;
      4) echo "ERROR: no writable R library to install into." >&2
         echo "       Set R_LIBS_USER to a writable path and rerun." >&2 ;;
      *) echo "ERROR: installing R package(s) failed — see the output above." >&2 ;;
    esac
    exit 1
  fi

  Missing=$(Missing_Packages "${R_Packages[@]}")
  if [[ -n $Missing ]]; then
    echo >&2
    echo "ERROR: still cannot load: $(echo "$Missing" | tr '\n' ' ')" >&2
    echo "       Install by hand in R, then rerun." >&2
    exit 1
  fi

  echo
  echo "R packages ready."
  echo
}


## * Reading the run configuration ############################################

# Filled by Inspect_Inputs, read by Show_Plan and Validate_Plan.
Scenarios=(); Folders=(); Status_Note=(); Scenario_Ok=()
Series_Ids=(); Series_Labels=(); Series_Models=(); Series_Kept=()
Needs_Runs=0; Needs_Stats=0; Needs_Csv=0
Ready_Count=0; Kept_Series=0

# Works out what each config file asks for and which of it is actually on disk,
# mirroring the source selection in 1-Ingest.R: numeric run ids come from the
# per-variable RDS, statistic ids from the plotData CSVs, csvFiles from the
# top-level Data-Input/<scenario>.csv.
Inspect_Inputs() {
  local File
  for File in "$Folder_Map" "$Scenario_Input"; do
    if [[ ! -f $File ]]; then
      echo "ERROR: $File not found (see README.md, Instructions steps 2-3)." >&2
      exit 1
    fi
  done

  local Id Label Model Rest
  while IFS=, read -r Id Label Model Rest; do
    [[ -z $Id ]] && continue

    Series_Ids+=("$Id")
    Series_Labels+=("$Label")
    Series_Models+=("$Model")

    # --no-subscenarios keeps only the rows with a blank label, matching the
    # Reported_Runs filter 0-Main.R applies for FRIDA_NO_SUBSCENARIOS.
    if [[ $No_SubScenarios -eq 1 && -n $Label ]]; then
      Series_Kept+=(0)
      continue
    fi
    Series_Kept+=(1)
    Kept_Series=$(( Kept_Series + 1 ))

    case "$Id" in
      csvFiles)        Needs_Csv=1 ;;
      *[!0-9]*)        Needs_Stats=1 ;;   # a statistic name
      *)               Needs_Runs=1 ;;    # all digits: a parameter-space run id
    esac
  done < <(tail -n +2 "$Scenario_Input" | tr -d '\r')

  local Folder Scenario Ok Note
  while IFS=, read -r Folder Scenario Rest; do
    [[ -z $Folder ]] && continue

    Ok=0
    Note=""

    if [[ $Needs_Runs -eq 1 || $Needs_Stats -eq 1 ]]; then
      if [[ ! -d "Data-Input/$Folder" ]]; then
        Note="no run folder"
      elif [[ $Needs_Runs -eq 1 && ! -d "Data-Input/$Folder/$PerVar_Subdir" ]]; then
        Note="no PerVarFiles-RDS"
      elif [[ $Needs_Stats -eq 1 && ! -d "Data-Input/$Folder/$PlotData_Subdir" ]]; then
        Note="no plotData"
      else
        Ok=1
        Note="folder"
      fi
    fi

    if [[ $Needs_Csv -eq 1 ]]; then
      if [[ -f "Data-Input/$Scenario.csv" ]]; then
        Ok=1
        Note="${Note:+$Note + }$Scenario.csv"
      elif [[ $Ok -eq 0 ]]; then
        Note="${Note:+$Note, }no $Scenario.csv"
      fi
    fi

    Scenarios+=("$Scenario")
    Folders+=("$Folder")
    Scenario_Ok+=("$Ok")
    Status_Note+=("$Note")
    if [[ $Ok -eq 1 ]]; then Ready_Count=$(( Ready_Count + 1 )); fi
  done < <(tail -n +2 "$Folder_Map" | tr -d '\r')

  # Explicit, so the function never inherits a false test as its exit status —
  # under set -e that would end the run silently.
  return 0
}


## * The plan #################################################################

# Everything the run will do, before it does any of it: which folder feeds which
# scenario and whether its data is there, which series each scenario contributes,
# and the Scenario names those series produce in the output.
Show_Plan() {
  local Sets_Listed="$1"
  local Baseline Region Year_Start Year_End Horizon
  Baseline=$(R_Param Baseline_Scenario)
  Region=$(R_Param Region_Name)
  Year_Start=$(R_Param Year_Start)
  Year_End=$(R_Param Year_End)

  if [[ $Year_Start == "NA" && $Year_End == "NA" ]]; then
    Horizon="full range in the data"
  else
    Horizon="$Year_Start to $Year_End"
  fi

  echo "================================================================"
  echo " Run plan — $Sets_Listed variable set"
  echo "================================================================"
  echo
  echo "Scenarios — $Folder_Map"
  echo

  local i Marker Sample_Scenario="" Baseline_Found=0
  for i in $(seq 0 $(( ${#Scenarios[@]} - 1 ))); do
    Marker=" "
    if [[ ${Scenarios[$i]} == "$Baseline" ]]; then
      Marker="*"
      if [[ ${Scenario_Ok[$i]} -eq 1 ]]; then Baseline_Found=1; fi
    fi
    [[ ${Scenario_Ok[$i]} -eq 1 && -z $Sample_Scenario ]] && Sample_Scenario="${Scenarios[$i]}"

    if [[ ${Scenario_Ok[$i]} -eq 1 ]]; then
      printf '  %s %-18s ready   [%s]\n' "$Marker" "${Scenarios[$i]}" "${Status_Note[$i]}"
    else
      printf '  %s %-18s SKIPPED [%s]\n' "$Marker" "${Scenarios[$i]}" "${Status_Note[$i]}"
    fi
    printf '      %s\n' "${Folders[$i]}"
  done

  [[ -z $Sample_Scenario ]] && Sample_Scenario="${Scenarios[0]-Scenario}"

  # A baseline that names no scenario present in this run is not fatal, but it
  # empties the Policy Cost variables, so it must not pass unremarked.
  if [[ $Baseline_Found -eq 1 ]]; then
    echo "  * $Baseline is the baseline for the Policy Cost variables"
  elif [[ -n $Baseline ]]; then
    echo "  ! Baseline_Scenario \"$Baseline\" (0-Main.R) matches no scenario with"
    echo "    data above — the Policy Cost variables will come out empty."
  fi

  echo
  echo "Series — $Scenario_Input, read from every scenario above"
  echo
  printf '     %-14s %-16s %-12s %s\n' "id" "subScenario" "model" "output Scenario"
  for i in $(seq 0 $(( ${#Series_Ids[@]} - 1 ))); do
    local Label Shown Output
    Label="${Series_Labels[$i]}"
    Shown="${Label:-(none)}"
    Output="$Sample_Scenario${Label:+:$Label}"

    if [[ ${Series_Kept[$i]} -eq 1 ]]; then
      printf '     %-14s %-16s %-12s %s\n' \
             "${Series_Ids[$i]}" "$Shown" "${Series_Models[$i]}" "$Output"
    else
      printf '     %-14s %-16s %-12s %s\n' \
             "${Series_Ids[$i]}" "$Shown" "-" "dropped (--no-subscenarios)"
    fi
  done

  echo
  echo "Output"
  echo
  local Set_Name
  for Set_Name in $Sets_Listed; do
    echo "     Data-Output/Data-Output-$Set_Name.csv and .xlsx"
  done
  echo "     $Ready_Count scenario(s) x $Kept_Series series = $(( Ready_Count * Kept_Series )) Scenario entries"
  echo "     Region $Region, years $Horizon"
  if [[ $No_SubScenarios -eq 1 ]]; then
    echo "     Sub-scenarios OFF — no Scenario:subScenario names in the output"
  fi
  echo
}

Validate_Plan() {
  if [[ $Kept_Series -eq 0 ]]; then
    echo "ERROR: no series left to report." >&2
    if [[ $No_SubScenarios -eq 1 ]]; then
      echo "       --no-subscenarios keeps only rows with a blank subScenario," >&2
      echo "       and every row in $Scenario_Input has a label." >&2
      echo "       Add an unlabelled row (e.g. defaultRun) or drop the option." >&2
    fi
    exit 1
  fi

  if [[ $Ready_Count -eq 0 ]]; then
    echo "ERROR: no input data found for any scenario in $Folder_Map." >&2
    [[ $Needs_Runs -eq 1 ]] && echo "       Run ids need Data-Input/<folder>/$PerVar_Subdir." >&2
    [[ $Needs_Stats -eq 1 ]] && echo "       Statistic ids need Data-Input/<folder>/$PlotData_Subdir." >&2
    [[ $Needs_Csv -eq 1 ]] && echo "       csvFiles needs Data-Input/<scenario>.csv." >&2
    [[ -x setup-data-links.sh ]] && echo "       ./setup-data-links.sh links the run folders into Data-Input/." >&2
    exit 1
  fi

  if [[ $Ready_Count -lt ${#Scenarios[@]} ]]; then
    echo "WARNING: $(( ${#Scenarios[@]} - Ready_Count )) scenario(s) will be skipped for missing data." >&2
    echo >&2
  fi
}

# Asks before running. A batch job (no terminal) proceeds on the plan alone,
# since there is nobody to answer; -y skips the prompt everywhere.
Confirm_Plan() {
  [[ $Assume_Yes -eq 1 ]] && return 0

  if [[ ! -t 0 ]]; then
    echo "No terminal to confirm on — proceeding with the plan above."
    echo
    return 0
  fi

  local Answer
  while true; do
    if ! read -r -p "Proceed? [Y/n]: " Answer; then
      echo >&2
      echo "ERROR: no answer given (input closed)." >&2
      exit 1
    fi
    case "$(printf '%s' "${Answer:-y}" | tr '[:upper:]' '[:lower:]')" in
      y|yes) return 0 ;;
      n|no)  echo "Cancelled — nothing was run."; exit 0 ;;
      *)     echo "  Please answer y or n." ;;
    esac
  done
}


## * Running a set ############################################################

# Runs the whole pipeline for one variable set. Returns the Rscript exit status.
Run_Set() {
  local Set_Name="$1"
  local Mapping="Mapping/Variable-Mapping-${Set_Name}.csv"
  local Calculate="2-Calculate-${Set_Name}.R"

  if [[ ! -f $Mapping || ! -f $Calculate ]]; then
    echo "ERROR: $Set_Name set is incomplete — expected $Mapping and $Calculate." >&2
    return 1
  fi

  echo
  echo "================================================================"
  echo " Running the $Set_Name variable set"
  echo "   mapping:   $Mapping"
  echo "   calculate: $Calculate"
  echo "================================================================"
  echo

  local Started=$SECONDS
  if ! FRIDA_VARIABLE_SET="$Set_Name" \
       FRIDA_NO_SUBSCENARIOS="$No_SubScenarios" \
       Rscript 0-Main.R; then
    echo
    echo "FAILED: $Set_Name set (see the R output above)." >&2
    return 1
  fi

  echo
  echo "Done: $Set_Name set in $(( SECONDS - Started ))s"
  local Output
  for Output in "Data-Output/Data-Output-${Set_Name}.csv" "Data-Output/Data-Output-${Set_Name}.xlsx"; do
    [[ -f $Output ]] && echo "  $Output ($(du -h "$Output" | cut -f1 | tr -d ' '))"
  done
  return 0
}


## * Choose the variable set ##################################################

Choice=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help|help)     Usage; exit 0 ;;
    -y|--yes)           Assume_Yes=1; shift ;;
    --no-subscenarios)  No_SubScenarios=1; shift ;;
    --no-install)       Install_Missing=0; shift ;;
    -*)
      echo "ERROR: unknown option \"$1\"." >&2
      echo >&2
      Usage >&2
      exit 1 ;;
    *)
      if ! Choice=$(Canonical_Set "$1"); then
        echo "ERROR: unknown variable set \"$1\"." >&2
        echo >&2
        Usage >&2
        exit 1
      fi
      shift ;;
  esac
done

if [[ -n $Choice ]]; then
  : # named on the command line
elif [[ ! -t 0 ]]; then
  echo "ERROR: no variable set given and no terminal to prompt on." >&2
  echo "       A batch job must name it, e.g. ./run-pipeline.sh compass" >&2
  echo >&2
  Usage >&2
  exit 1
else
  echo "FRIDA IAMC post-processing — which output do you want?"
  echo
  echo "  1) Compass      Scenario Compass variable set"
  echo "  2) Diagnostic   IAM community diagnostic assessment protocol"
  echo "  3) Both         run each set in turn"
  echo
  while true; do
    if ! read -r -p "Choice [1-3, default 1]: " Answer; then
      echo >&2
      echo "ERROR: no answer given (input closed)." >&2
      exit 1
    fi
    Answer="${Answer:-1}"
    if Choice=$(Canonical_Set "$Answer"); then
      break
    fi
    echo "  Please answer 1, 2, or 3 (or compass / diagnostic / both)."
  done
  echo
fi

if [[ $Choice == "Both" ]]; then
  Sets=("Compass" "Diagnostic")
else
  Sets=("$Choice")
fi


## * Run pipeline #############################################################

if ! command -v Rscript >/dev/null 2>&1; then
  echo "ERROR: Rscript not found on PATH." >&2
  # `module` is a shell function that a non-interactive shell may not see, so
  # fall back to the variables the module systems export.
  if command -v module >/dev/null 2>&1 ||
     [[ -n ${MODULESHOME:-} || -n ${LMOD_CMD:-} ]]; then
    echo "       This machine uses environment modules — load R first:" >&2
    echo "         module load r          (module avail r lists the versions)" >&2
  else
    echo "       Install R: https://cran.r-project.org" >&2
  fi
  exit 1
fi

Ensure_Utf8_Locale
Ensure_R_Packages

Inspect_Inputs
Show_Plan "${Sets[*]}"
Validate_Plan
Confirm_Plan

Failed=()
for Set_Name in "${Sets[@]}"; do
  Run_Set "$Set_Name" || Failed+=("$Set_Name")
done

echo
if [[ ${#Failed[@]} -gt 0 ]]; then
  echo "Pipeline finished with failures: ${Failed[*]}" >&2
  exit 1
fi

echo "Pipeline complete: ${Sets[*]}"
