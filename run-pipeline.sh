#!/usr/bin/env bash
#
# Description:
#   End-to-end runner for the FRIDA IAMC post-processing pipeline. Asks which
#   variable set to build — Compass or Diagnostic — installs any missing R
#   package, then runs 0-Main.R (stages 1-4) with that set via Rscript. Every
#   other parameter still comes from 0-Main.R and Data-Config/.
#
#   Usage: ./run-pipeline.sh [compass|diagnostic|both] [--no-install]
#          With no set argument it prompts for the choice, so a batch job
#          (SLURM, no terminal) must name the set:
#
#            module load r
#            ./run-pipeline.sh compass
#
#          --no-install reports missing R packages instead of installing them,
#          for nodes with no outbound network.
#
#   Inputs:  Data-Input/ (FRIDA output folders), Data-Config/*.csv
#   Outputs: Data-Output/Data-Output-<set>.csv and .xlsx (plus stage
#            intermediates, all suffixed with the set name)

set -euo pipefail

Script_Dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$Script_Dir"

Install_Missing=1


## * Helpers ##################################################################

Usage() {
  cat <<'EOF'
Usage: ./run-pipeline.sh [compass|diagnostic|both] [--no-install]

  compass       Scenario Compass variable set
  diagnostic    IAM community diagnostic assessment protocol
  both          run each set in turn (outputs do not overwrite each other)

  --no-install  do not install missing R packages, just report them

With no set argument the script prompts for the choice; a batch job with no
terminal must name the set, e.g.  ./run-pipeline.sh compass
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

Preflight() {
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
  Check_Input_Data
}

# Every package the pipeline library()s: 1-Ingest/2-Calculate/3-Map load
# tidyverse, 4-Format-Export also loads writexl for the .xlsx output.
R_Packages=(tidyverse writexl)

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
  echo "(no binaries on Linux — a first tidyverse install compiles its"
  echo " dependencies and can take upwards of half an hour)"
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
}

# Every scenario in FolderScenarioMap.csv needs the source its ScenarioInput.csv
# ids read from: the run folder under Data-Input/ for run and statistic ids, or
# Data-Input/<scenario>.csv for csvFiles. Ingesting nothing fails mid-pipeline
# with an empty-column error, so say so up front instead.
Check_Input_Data() {
  local Map="Data-Config/FolderScenarioMap.csv"
  local Input="Data-Config/ScenarioInput.csv"

  local File
  for File in "$Map" "$Input"; do
    if [[ ! -f $File ]]; then
      echo "ERROR: $File not found (see README.md, Instructions steps 2-3)." >&2
      exit 1
    fi
  done

  # Which kinds of id the run asks for; csvFiles is the only one not read from
  # inside the scenario folder.
  local Ids Needs_Folders=0 Needs_Csv=0
  Ids=$(tail -n +2 "$Input" | tr -d '\r' | cut -d, -f1 | grep -v '^[[:space:]]*$' || true)
  grep -qvx "csvFiles" <<<"$Ids" && Needs_Folders=1
  grep -qx  "csvFiles" <<<"$Ids" && Needs_Csv=1

  local Row Folder Scenario Usable=0 Missing=()
  while IFS=, read -r Folder Scenario Row; do
    Folder="${Folder//$'\r'/}"; Scenario="${Scenario//$'\r'/}"
    [[ -z $Folder ]] && continue
    if { [[ $Needs_Folders -eq 1 ]] && [[ -d "Data-Input/$Folder" ]]; } ||
       { [[ $Needs_Csv -eq 1 ]] && [[ -f "Data-Input/$Scenario.csv" ]]; }; then
      Usable=$(( Usable + 1 ))
    else
      Missing+=("$Scenario")
    fi
  done < <(tail -n +2 "$Map" | tr -d '\r')

  if [[ $Usable -eq 0 ]]; then
    echo "ERROR: no input data found for any scenario in $Map." >&2
    [[ $Needs_Folders -eq 1 ]] && echo "       Run folders expected under Data-Input/<folder>/." >&2
    [[ $Needs_Csv -eq 1 ]] && echo "       csvFiles expects Data-Input/<scenario>.csv." >&2
    [[ -x setup-data-links.sh ]] && echo "       ./setup-data-links.sh links the run folders into Data-Input/." >&2
    exit 1
  fi

  if [[ ${#Missing[@]} -gt 0 ]]; then
    echo "WARNING: no data yet for ${#Missing[@]} scenario(s): ${Missing[*]}" >&2
    echo "         They will be skipped; the other $Usable will still run." >&2
    echo >&2
  fi
}

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
  if ! FRIDA_VARIABLE_SET="$Set_Name" Rscript 0-Main.R; then
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
    -h|--help|help) Usage; exit 0 ;;
    --no-install)   Install_Missing=0; shift ;;
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
fi


## * Run pipeline #############################################################

Preflight

if [[ $Choice == "Both" ]]; then
  Sets=("Compass" "Diagnostic")
else
  Sets=("$Choice")
fi

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
