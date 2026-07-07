# Description:
#   Stage 2. Derives composite IAMC variables and applies unit conversions.
#   Derived rows are appended to All_Data under calc_ names; Stage 3 maps
#   them alongside raw pass-through keys.
#
#   Pass-throughs (no calculation, map directly via Variable-Mapping.csv):
#     ccs_captured_co2_to_store       -> Carbon Capture
#     emissions_total_co2_emissions   -> Emissions|CO2
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


## ** Parameters

# Reference scenario for baseline-relative variables (Policy Cost|Consumption
# Loss, Policy Cost|Additional Total Energy System Cost). Default applies only
# when not already set (e.g. by 0-Main.R).
if (!exists("Baseline_Scenario")) Baseline_Scenario <- "policy_CP"

if (!any(All_Data$Scenario == Baseline_Scenario)) {
  warning("Baseline_Scenario '", Baseline_Scenario,
          "' not found in ingested data — baseline-relative Policy Cost ",
          "variables will be empty.")
}

## ** Conversion constants

TWh_to_EJ  <- 0.0036                     # 1 TWh = 3.6e15 J = 0.0036 EJ
t_to_Mt    <- 1e-6                       # 1 t = 1e-6 Mt (1 Mt = 1,000,000 t)
ZJ_to_EJ   <- 1000                       # 1 ZJ (zetta joule) = 1000 EJ
# Constant 2021 USD -> constant 2010 USD. The manual mapping doc
# (FRIDA_IAMC_VariableMapping_v5.xlsx) gives the 2010->2021 inflation factor
# 1.36716299937247; inverted here for the deflation direction.
Defl_2021_to_2010 <- 1/1.36716299937247  # = 0.731445


## * Stage 2: Calculate #######################################################

## ** Emissions|CO2|Energy and Industrial Processes ---------------------------

# Formulation to calculate from FRIDA needs review

# Sum of energy CO2 and concrete (industrial process) CO2, both in MtCO2/yr.
# "Realized" = net of CCS capture from the energy system.

# Calc_Data <- All_Data |>
#   filter(Variable %in% c("emissions_realized_co2_emissions_from_energy",
#                           "concrete_co2_emissions")) |>
#   group_by(Scenario, Run, Year) |>
#   summarise(Value = sum(Value, na.rm = TRUE), .groups = "drop") |>
#   mutate(Variable = "calc_emissions_co2_energy_industrial")
# 
# All_Data <- bind_rows(All_Data, Calc_Data)

## filter(All_Data, Variable == "calc_emissions_co2_energy_industrial", Year == 2020)


## ** Emissions|Kyoto Gases ---------------------------------------------------

# FRIDA aggregates the Kyoto gases internally; its output is in tCO2e/yr.
# IAMC unit is Mt CO2e/yr -> divide by 1000000.
Calc_Data <- All_Data |>
  filter(Variable == "emissions_kyoto_gas_emissions") |>
  mutate(Variable = "calc_kyoto_gases_mtco2e",
         Value    = Value * t_to_Mt)

All_Data <- bind_rows(All_Data, Calc_Data)

## filter(All_Data, Variable == "calc_kyoto_gases_mtco2e", Year == 2020)


## ** Final Energy ------------------------------------------------------------

# FRIDA Total Energy Output (TWh/yr) used as proxy for final energy.
# This is a known approximation — FRIDA has no end-use sector breakdown.
Calc_Data <- All_Data |>
  filter(Variable == "energy_supply_total_energy_output") |>
  mutate(Variable = "calc_final_energy_ej",
         Value    = Value * TWh_to_EJ)

All_Data <- bind_rows(All_Data, Calc_Data)

## filter(All_Data, Variable == "calc_final_energy_ej", Year == 2020)


## ** Primary Energy ----------------------------------------------------------

# Same source as Final Energy — FRIDA Total Energy Output is used as proxy for both.
Calc_Data <- All_Data |>
  filter(Variable == "energy_supply_total_energy_output") |>
  mutate(Variable = "calc_primary_energy_ej",
         Value    = Value * TWh_to_EJ)

All_Data <- bind_rows(All_Data, Calc_Data)

## filter(All_Data, Variable == "calc_primary_energy_ej", Year == 2020)


## ** Primary Energy|Biomass --------------------------------------------------

# Bio fuel secondary energy output (TWh/yr) -> EJ/yr.
# Per v5 mapping, secondary output used as primary energy proxy for biomass.
Calc_Data <- All_Data |>
  filter(Variable == "bio_fuel_energy_bio_fuel_secondary_energy_output") |>
  mutate(Variable = "calc_primary_energy_biomass_ej",
         Value    = Value * TWh_to_EJ)

All_Data <- bind_rows(All_Data, Calc_Data)

## filter(All_Data, Variable == "calc_primary_energy_biomass_ej", Year == 2020)


## ** Primary Energy|Coal -----------------------------------------------------

# Primary Fossil Energy FUEL for coal. FRIDA unit: ZJ/yr (zetta joules).
# Conversion factor ZJ_to_EJ = 1000 — verify against actual FRIDA output.
Calc_Data <- All_Data |>
  filter(Variable == "fossil_energy_coal_primary_fossil_energy_fuel") |>
  mutate(Variable = "calc_primary_energy_coal_ej",
         Value    = Value * ZJ_to_EJ)

All_Data <- bind_rows(All_Data, Calc_Data)

## filter(All_Data, Variable == "calc_primary_energy_coal_ej", Year == 2020)


## ** Primary Energy|Gas ------------------------------------------------------

Calc_Data <- All_Data |>
  filter(Variable == "fossil_energy_gas_primary_fossil_energy_fuel") |>
  mutate(Variable = "calc_primary_energy_gas_ej",
         Value    = Value * ZJ_to_EJ)

All_Data <- bind_rows(All_Data, Calc_Data)

## filter(All_Data, Variable == "calc_primary_energy_gas_ej", Year == 2020)


## ** Primary Energy|Oil ------------------------------------------------------

Calc_Data <- All_Data |>
  filter(Variable == "fossil_energy_oil_primary_fossil_energy_fuel") |>
  mutate(Variable = "calc_primary_energy_oil_ej",
         Value    = Value * ZJ_to_EJ)

All_Data <- bind_rows(All_Data, Calc_Data)

## filter(All_Data, Variable == "calc_primary_energy_oil_ej", Year == 2020)


## ** Primary Energy|Nuclear --------------------------------------------------

# Nuclear energy output (TWh/yr). IAMC convention here: secondary electricity
# output reported directly (no thermal efficiency uplift applied).
Calc_Data <- All_Data |>
  filter(Variable == "nuclear_energy_nuclear_energy_output") |>
  mutate(Variable = "calc_primary_energy_nuclear_ej",
         Value    = Value * TWh_to_EJ)

All_Data <- bind_rows(All_Data, Calc_Data)

## filter(All_Data, Variable == "calc_primary_energy_nuclear_ej", Year == 2020)


## ** Primary Energy|Solar ----------------------------------------------------

Calc_Data <- All_Data |>
  filter(Variable == "solar_energy_solar_energy_output") |>
  mutate(Variable = "calc_primary_energy_solar_ej",
         Value    = Value * TWh_to_EJ)

All_Data <- bind_rows(All_Data, Calc_Data)

## filter(All_Data, Variable == "calc_primary_energy_solar_ej", Year == 2020)


## ** Primary Energy|Wind -----------------------------------------------------

Calc_Data <- All_Data |>
  filter(Variable == "wind_energy_wind_energy_output") |>
  mutate(Variable = "calc_primary_energy_wind_ej",
         Value    = Value * TWh_to_EJ)

All_Data <- bind_rows(All_Data, Calc_Data)

## filter(All_Data, Variable == "calc_primary_energy_wind_ej", Year == 2020)


## ** GDP|PPP -----------------------------------------------------------------

# Real GDP in constant 2021 USD (bc$/yr) deflated to 2010 USD.
# Deflator: BLS CPI-U ratio 2010/2021 (see Preamble constants).
Calc_Data <- All_Data |>
  filter(Variable == "gdp_real_gdp_in_2021c") |>
  mutate(Variable = "calc_gdp_ppp_busd2010",
         Value    = Value * Defl_2021_to_2010)

All_Data <- bind_rows(All_Data, Calc_Data)

## filter(All_Data, Variable == "calc_gdp_ppp_busd2010", Year == 2020)


## ** Price|Carbon ------------------------------------------------------------

# Carbon price as scenario input (GRAPH(TIME) path). FRIDA unit: c2021$/tCO2e.
# Deflated to USD_2010/tCO2. No quantity aggregation — direct unit conversion.
Calc_Data <- All_Data |>
  filter(Variable == "government_regulations_tax_on_co2e_emissions") |>
  mutate(Variable = "calc_price_carbon_usd2010",
         Value    = Value * Defl_2021_to_2010)

All_Data <- bind_rows(All_Data, Calc_Data)

## filter(All_Data, Variable == "calc_price_carbon_usd2010", Year == 2020)


## ** Policy Cost|Additional Total Energy System Cost -------------------------

# Additional energy system cost vs the reference scenario (Baseline_Scenario,
# set in 0-Main.R; default policy_CP): policy minus baseline — the OPPOSITE
# direction of Consumption Loss. Both come out positive when the policy is
# costly: consumption falls under policy (baseline - policy), energy system
# cost rises under policy (policy - baseline). Joined per Run x Year; runs
# absent from the baseline drop out; the baseline itself reports 0.
# FRIDA outputs billions despite the "c$/Year" unit label in the v5 mapping
# sheet (confirmed 2026-07-06) — deflation only, no magnitude scaling.
# Caveat: total energy investments is an investment flow, used here as a
# proxy for total energy system cost (no fuel costs or O&M).
Baseline_Investments <- All_Data |>
  filter(Variable == "energy_investments_total_investments",
         Scenario == Baseline_Scenario) |>
  select(Run, Year, Baseline_Value = Value)

Calc_Data <- All_Data |>
  filter(Variable == "energy_investments_total_investments") |>
  inner_join(Baseline_Investments, by = c("Run", "Year")) |>
  mutate(Variable = "calc_policy_cost_energy_system_busd2010",
         Value    = (Value - Baseline_Value) * Defl_2021_to_2010) |>
  select(-Baseline_Value)

All_Data <- bind_rows(All_Data, Calc_Data)

## filter(All_Data, Variable == "calc_policy_cost_energy_system_busd2010", Year == 2020)


## ** Policy Cost|Consumption Loss --------------------------------------------

# Consumption loss vs the reference scenario (Baseline_Scenario, set in
# 0-Main.R; default policy_CP): baseline minus policy, so losses are positive
# numbers per the protocol description. Joined per Run x Year — each run is
# compared to the same run in the baseline; runs absent from the baseline drop
# out. The baseline scenario itself reports 0 by definition.
# Deflation is applied after the difference (linear, so order is immaterial).
Baseline_Consumption <- All_Data |>
  filter(Variable == "circular_flow_real_private_consumption_2021c",
         Scenario == Baseline_Scenario) |>
  select(Run, Year, Baseline_Value = Value)

Calc_Data <- All_Data |>
  filter(Variable == "circular_flow_real_private_consumption_2021c") |>
  inner_join(Baseline_Consumption, by = c("Run", "Year")) |>
  mutate(Variable = "calc_policy_cost_consumption_loss_busd2010",
         Value    = (Baseline_Value - Value) * Defl_2021_to_2010) |>
  select(-Baseline_Value)

All_Data <- bind_rows(All_Data, Calc_Data)

## filter(All_Data, Variable == "calc_policy_cost_consumption_loss_busd2010", Year == 2020)


## * Summary ##################################################################

cat("All_Data after Calculate:", nrow(All_Data), "rows\n")
cat("Calc variables added:\n")
for (V in sort(unique(All_Data$Variable[grepl("^calc_", All_Data$Variable)]))) cat(" ", V, "\n")

## head(All_Data)
## filter(All_Data, grepl("^calc_", Variable))


## * Export Intermediate ######################################################

saveRDS(All_Data, file.path(Path_Output, "2-All_Data_Calc.RDS"))
cat("\nSaved: Data-Output/2-All_Data_Calc.RDS\n")
