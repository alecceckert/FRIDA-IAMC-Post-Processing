# Description:
#   Stage 2. Derives composite IAMC variables and applies unit conversions.
#   Derived rows are appended to All_Data under calc_ names; Stage 3 maps
#   them alongside raw pass-through keys.
#
#   Inputs:  Data-Output/1-All_Data.RDS
#   Outputs: Data-Output/2-All_Data_Calc.RDS

library(tidyverse)
options(scipen = 999)


## * Preamble #################################################################

## ** Paths

Path_Output <- "Data-Output"
All_Data    <- readRDS(file.path(Path_Output, "1-All_Data.RDS"))

cat("Loaded All_Data:", nrow(All_Data), "rows\n")
cat("Variables:", paste(sort(unique(All_Data$Variable)), collapse = ", "), "\n\n")


## * Stage 2: Calculate #######################################################



## * Summary ##################################################################

cat("All_Data after Calculate:", nrow(All_Data), "rows\n")
cat("Variables:", paste(sort(unique(All_Data$Variable)), collapse = ", "), "\n")

## head(All_Data)
## filter(All_Data, grepl("^calc_", Variable))


## * Export Intermediate ######################################################

saveRDS(All_Data, file.path(Path_Output, "2-All_Data_Calc.RDS"))
cat("\nSaved: Data-Output/2-All_Data_Calc.RDS\n")
