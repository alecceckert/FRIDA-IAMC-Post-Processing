# Description:
#   Stage 3. Joins All_Data with Variable-Mapping.csv to replace FRIDA variable
#   keys with IAMC names and units. Unmapped variables are dropped by the join.
#
#   Inputs:  Data-Output/2-All_Data_Calc-<set>.RDS
#            Mapping/Variable-Mapping-<set>.csv  (IAMC Variable | IAMC Unit | IAMC Description | Variable)
#            (<set> via Path_Mapping/File_Suffix from Variable_Set in 0-Main.R)
#   Outputs: Data-Output/3-IAMC_Data-<set>.RDS
#            Columns: Scenario | Variable | Unit | Run | Year | Value

library(tidyverse)
options(scipen = 999)


## * Preamble #################################################################

## ** Paths

# Defaults apply only when not already set (e.g. by 0-Main.R).
if (!exists("Path_Mapping")) Path_Mapping <- file.path("Mapping", "Variable-Mapping-Diagnostic.csv")
if (!exists("File_Suffix"))  File_Suffix  <- "-Diagnostic"
Path_Output <- "Data-Output"

All_Data <- readRDS(file.path(Path_Output, paste0("2-All_Data_Calc", File_Suffix, ".RDS")))
Mapping  <- read_csv(Path_Mapping, show_col_types = FALSE)

cat("Loaded All_Data:", nrow(All_Data), "rows\n")
cat("Mapping entries:", nrow(Mapping), "\n\n")

## head(Mapping)


## * Stage 3: Map #############################################################

# Unmapped variables fall away. many-to-many is deliberate: one FRIDA/calc key
# may feed several IAMC variables (Compass: Consumption -> Consumption +
# Expenditure|Households; hydro -> Primary and Secondary Energy).
IAMC_Data <- All_Data |>
  inner_join(Mapping, by = "Variable", relationship = "many-to-many") |>
  select(
    Scenario,
    Variable = `IAMC Variable`,
    Unit     = `IAMC Unit`,
    Run,
    Year,
    Value
  )

cat("IAMC_Data:", nrow(IAMC_Data), "rows\n")
cat("IAMC variables mapped:\n")
for (IAMC_Variable_Name in sort(unique(IAMC_Data$Variable))) cat(" ", IAMC_Variable_Name, "\n")

# Mapping keys with no data yet
Missing_Keys <- setdiff(Mapping$Variable, unique(All_Data$Variable))
if (length(Missing_Keys) > 0) {
  cat("\nMapped keys with no data yet:", paste(Missing_Keys, collapse = ", "), "\n")
}

## head(IAMC_Data)
## filter(IAMC_Data, Scenario == "policy_C0to400-lin", Year == 2060)


## * Export Intermediate ######################################################

saveRDS(IAMC_Data, file.path(Path_Output, paste0("3-IAMC_Data", File_Suffix, ".RDS")))
cat("\nSaved: Data-Output/3-IAMC_Data", File_Suffix, ".RDS\n", sep = "")