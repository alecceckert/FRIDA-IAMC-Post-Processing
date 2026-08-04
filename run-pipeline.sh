#!/usr/bin/env bash
#
# Description:
#   End-to-end runner for the FRIDA IAMC post-processing pipeline. Asks which
#   variable set to build — Compass or Diagnostic — then runs 0-Main.R (stages
#   1-4) with that set via Rscript. Every other parameter still comes from
#   0-Main.R and Data-Config/.
#
#   Usage: ./run-pipeline.sh [compass|diagnostic|both]
#          With no argument it prompts for the choice.
#
#   Inputs:  Data-Input/ (FRIDA output folders), Data-Config/*.csv
#   Outputs: Data-Output/Data-Output-<set>.csv and .xlsx (plus stage
#            intermediates, all suffixed with the set name)

set -euo pipefail

Script_Dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$Script_Dir"


## * Helpers ##################################################################

Usage() {
  cat <<'EOF'
Usage: ./run-pipeline.sh [compass|diagnostic|both]

  compass      Scenario Compass variable set
  diagnostic   IAM community diagnostic assessment protocol
  both         run each set in turn (outputs do not overwrite each other)

With no argument the script prompts for the choice.
EOF
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
    echo "ERROR: Rscript not found on PATH. Install R (https://cran.r-project.org)." >&2
    exit 1
  fi

  local Missing
  Missing=$(Rscript -e 'cat(setdiff(c("tidyverse", "writexl"), rownames(installed.packages())), sep = " ")' 2>/dev/null)
  if [[ -n $Missing ]]; then
    echo "ERROR: missing R package(s): $Missing" >&2
    echo "       Install with: Rscript -e 'install.packages(c($(printf '"%s", ' $Missing | sed 's/, $//')))'" >&2
    exit 1
  fi

  Check_Input_Data
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

case "${1-}" in
  -h|--help|help) Usage; exit 0 ;;
esac

if [[ $# -gt 0 ]]; then
  if ! Choice=$(Canonical_Set "$1"); then
    echo "ERROR: unknown variable set \"$1\"." >&2
    echo >&2
    Usage >&2
    exit 1
  fi
elif [[ ! -t 0 ]]; then
  echo "ERROR: no variable set given and no terminal to prompt on." >&2
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
