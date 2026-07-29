# Description:
#   Stage 2. Derives composite IAMC variables and applies unit conversions.
#   Derived rows are appended to All_Data under calc_ names; Stage 3 maps
#   them alongside raw pass-through keys.
#
#   Pass-throughs (no calculation, map directly via Variable-Mapping.csv):
#     any mapping row whose Variable key has no calc_ prefix, e.g.
#     emissions_total_ch4_emissions -> Emissions|CH4. Most Scenario Compass
#     variables are 1:1-unit pass-throughs (emissions by gas/sector,
#     capacities, land cover, labour force); see Variable-Mapping.csv.
#
#   This script implements the Scenario Compass variable set; the Diagnostic
#   (core protocol) set lives in 2-Calculate-Diagnostic.R. 0-Main.R sources one
#   of the two via Variable_Set.
#
#   Inputs:  2-Constants.R (shared conversion constants)
#            Data-Output/1-All_Data-Compass.RDS
#   Outputs: Data-Output/2-All_Data_Calc-Compass.RDS

library(tidyverse)
options(scipen = 999)


## * Preamble #################################################################

## ** Paths

# Default applies only when not already set (e.g. by 0-Main.R).
if (!exists("File_Suffix")) File_Suffix <- "-Compass"
Path_Output <- "Data-Output"
All_Data    <- readRDS(file.path(Path_Output, paste0("1-All_Data", File_Suffix, ".RDS")))

cat("Loaded All_Data:", nrow(All_Data), "rows\n")
cat("Variables:", paste(sort(unique(All_Data$Variable)), collapse = ", "), "\n\n")


## ** Conversion constants

# Shared with 2-Calculate-Diagnostic.R (TWh_to_EJ, ZJ_to_EJ, t_to_Mt,
# USD_to_bUSD, Defl_2021_to_2010). Caution: FRIDA.stmx declares the Energy
# Investments variables in c$/Year (plain USD), so this set scales them by
# USD_to_bUSD before deflating; the Diagnostic set deflates without scaling.
# The magnitude question should be settled once against real per-var data.
source("2-Constants.R")

# Compass-specific constants.
Mm2_to_bm2   <- 1e-3                     # 1 Mm2 (million m2) = 1e-3 billion m2
m3_to_km3    <- 1e-9                     # 1 m3 = 1e-9 km3
Share_to_Pct <- 100                      # dimensionless share -> percent

# 1 PCal/Mp/yr = 1e12 kcal / 1e6 people / 365.25 days = 2737.85 kcal/cap/day
PCal_per_Mp_Yr_to_kcal_cap_day <- 1e6 / 365.25

# Constant global land area, Mha. Source: FRIDA_to_IAMC.xlsx (Total Land Cover row).
Total_Land_Cover_Mha <- 8894.19

## ** Primary-energy-equivalent (input-equivalent) conversion

# Non-fossil primary energy is reported on the input-equivalent basis: the fuel
# a standard thermal plant would need to generate the same output, i.e.
# generation / conversion efficiency. The efficiency is FRIDA's own endogenous
# fossil-fuel conversion efficiency, taken per Scenario x Run x Year — the same
# convention the Diagnostic set uses, and what the mapping sheet asks for
# ("in primary energy units so apply conversion").
Fossil_Conversion_Efficiency <- All_Data |>
  filter(Variable ==
    "fossil_energy_conversion_efficiency_of_fossil_fuels_to_secondary_fossil_energy") |>
  select(Scenario, Run, Year, Efficiency = Value)

if (nrow(Fossil_Conversion_Efficiency) == 0)
  warning("FRIDA fossil-fuel conversion efficiency not found in All_Data — ",
          "input-equivalent primary energy variables will be empty.")


## * Stage 2: Calculate #######################################################

## ** Resource|Extraction|Coal ------------------------------------------

# Primary Fossil Energy FUEL for coal. FRIDA unit: ZJ/yr (zetta joules).
# Conversion factor ZJ_to_EJ = 1000 — verify against actual FRIDA output.
# Same FRIDA series as core Primary Energy|Coal (main project).
Calc_Data <- All_Data |>
  filter(Variable == "fossil_energy_coal_primary_fossil_energy_fuel") |>
  mutate(Variable = "calc_resource_extraction_coal_ej",
         Value    = Value * ZJ_to_EJ)

All_Data <- bind_rows(All_Data, Calc_Data)

## filter(All_Data, Variable == "calc_resource_extraction_coal_ej", Year == 2020)


## ** Resource|Extraction|Gas -------------------------------------------

Calc_Data <- All_Data |>
  filter(Variable == "fossil_energy_gas_primary_fossil_energy_fuel") |>
  mutate(Variable = "calc_resource_extraction_gas_ej",
         Value    = Value * ZJ_to_EJ)

All_Data <- bind_rows(All_Data, Calc_Data)

## filter(All_Data, Variable == "calc_resource_extraction_gas_ej", Year == 2020)


## ** Resource|Extraction|Oil -------------------------------------------

Calc_Data <- All_Data |>
  filter(Variable == "fossil_energy_oil_primary_fossil_energy_fuel") |>
  mutate(Variable = "calc_resource_extraction_oil_ej",
         Value    = Value * ZJ_to_EJ)

All_Data <- bind_rows(All_Data, Calc_Data)

## filter(All_Data, Variable == "calc_resource_extraction_oil_ej", Year == 2020)


## ** Secondary Energy|Electricity|Nuclear -------------------------------------

# Nuclear energy output (TWh/yr), reported as secondary electricity.
# Same FRIDA series as core Primary Energy|Nuclear (main project).
Calc_Data <- All_Data |>
  filter(Variable == "nuclear_energy_nuclear_energy_output") |>
  mutate(Variable = "calc_secondary_electricity_nuclear_ej",
         Value    = Value * TWh_to_EJ)

All_Data <- bind_rows(All_Data, Calc_Data)

## filter(All_Data, Variable == "calc_secondary_electricity_nuclear_ej", Year == 2020)


## ** Secondary Energy|Electricity|Solar ---------------------------------------

Calc_Data <- All_Data |>
  filter(Variable == "solar_energy_solar_energy_output") |>
  mutate(Variable = "calc_secondary_electricity_solar_ej",
         Value    = Value * TWh_to_EJ)

All_Data <- bind_rows(All_Data, Calc_Data)

## filter(All_Data, Variable == "calc_secondary_electricity_solar_ej", Year == 2020)


## ** Secondary Energy|Electricity|Wind ----------------------------------------

Calc_Data <- All_Data |>
  filter(Variable == "wind_energy_wind_energy_output") |>
  mutate(Variable = "calc_secondary_electricity_wind_ej",
         Value    = Value * TWh_to_EJ)

All_Data <- bind_rows(All_Data, Calc_Data)

## filter(All_Data, Variable == "calc_secondary_electricity_wind_ej", Year == 2020)


## ** Labor Force|Active -----------------------------------------------------

# Scenario Compass. Employed plus unemployed, both in Mp (millions of people).
Calc_Data <- All_Data |>
  filter(Variable %in% c("employment_employed", "employment_unemployed")) |>
  group_by(Scenario, Run, Year) |>
  summarise(Value = sum(Value, na.rm = TRUE), .groups = "drop") |>
  mutate(Variable = "calc_labour_force_active_m")

All_Data <- bind_rows(All_Data, Calc_Data)


## ** Labor Force|Unemployment [Rate] ------------------------------------------------

# Scenario Compass. FRIDA outputs a dimensionless share; IAMC unit is %.
Calc_Data <- All_Data |>
  filter(Variable == "employment_unemployment_rate") |>
  mutate(Variable = "calc_unemployment_rate_pct",
         Value    = Value * Share_to_Pct)

All_Data <- bind_rows(All_Data, Calc_Data)


## ** Food Availability [per capita] ------------------------------------------

# Scenario Compass. Total food supply (PCal/yr) over population (Mp) ->
# kcal/cap/day. Population join is per Scenario x Run x Year.
Calc_Data <- All_Data |>
  filter(Variable == "total_food_demand_total_food_supply") |>
  inner_join(
    All_Data |>
      filter(Variable == "demographics_population") |>
      select(Scenario, Run, Year, Population = Value),
    by = c("Scenario", "Run", "Year")
  ) |>
  mutate(Variable = "calc_food_availability_kcal_cap_day",
         Value    = Value / Population * PCal_per_Mp_Yr_to_kcal_cap_day) |>
  select(-Population)

All_Data <- bind_rows(All_Data, Calc_Data)

## filter(All_Data, Variable == "calc_food_availability_kcal_cap_day", Year == 2020)


## ** Food Availability|Crops [per capita] -------------------------------------------------

# Scenario Compass. Crop supply for vegetal products (PCal/yr) over population.
Calc_Data <- All_Data |>
  filter(Variable == "food_demand_crop_supply_for_vegetal_products") |>
  inner_join(
    All_Data |>
      filter(Variable == "demographics_population") |>
      select(Scenario, Run, Year, Population = Value),
    by = c("Scenario", "Run", "Year")
  ) |>
  mutate(Variable = "calc_food_availability_crops_kcal_cap_day",
         Value    = Value / Population * PCal_per_Mp_Yr_to_kcal_cap_day) |>
  select(-Population)

All_Data <- bind_rows(All_Data, Calc_Data)


## ** Food Availability|Livestock [per capita] ---------------------------------------------

# Scenario Compass. Animal products production (PCal/yr) over population.
Calc_Data <- All_Data |>
  filter(Variable == "animal_products_animal_products_production") |>
  inner_join(
    All_Data |>
      filter(Variable == "demographics_population") |>
      select(Scenario, Run, Year, Population = Value),
    by = c("Scenario", "Run", "Year")
  ) |>
  mutate(Variable = "calc_food_availability_livestock_kcal_cap_day",
         Value    = Value / Population * PCal_per_Mp_Yr_to_kcal_cap_day) |>
  select(-Population)

All_Data <- bind_rows(All_Data, Calc_Data)


## ** Food Intake|Crops [per capita] -------------------------------------------------------

# Scenario Compass. Direct crop demand per capita, PCal/Mp/yr -> kcal/cap/day.
Calc_Data <- All_Data |>
  filter(Variable == "food_demand_direct_crop_demand_per_capita") |>
  mutate(Variable = "calc_food_intake_crops_kcal_cap_day",
         Value    = Value * PCal_per_Mp_Yr_to_kcal_cap_day)

All_Data <- bind_rows(All_Data, Calc_Data)


## ** Intensity|Final Energy ---------------------------------------------------

# Final energy per unit of GDP. Numerator: Total Energy Output (TWh -> EJ), the
# same series that serves as the Final Energy proxy; denominator: real GDP
# deflated to 2010 USD. Joined per Scenario x Run x Year. Official unit:
# EJ/billion USD_2010.
Calc_Data <- All_Data |>
  filter(Variable == "energy_supply_total_energy_output") |>
  inner_join(All_Data |>
      filter(Variable == "gdp_real_gdp_in_2021c") |>
      select(Scenario, Run, Year, GDP = Value),
    by = c("Scenario", "Run", "Year")) |>
  mutate(Variable = "calc_final_energy_intensity_ej_busd2010",
         Value    = (Value * TWh_to_EJ) / (GDP * Defl_2021_to_2010)) |>
  select(-GDP)

All_Data <- bind_rows(All_Data, Calc_Data)

## filter(All_Data, Variable == "calc_final_energy_intensity_ej_busd2010", Year == 2020)


## ** GDP|PPP [Growth Rate per capita] -----------------------------------------

# Year-on-year percent growth of real GDP per capita, computed per Scenario x
# Run over the year sequence. The deflator cancels in the ratio, so the 2021c$
# series can be used directly. The first model year has no predecessor and is
# left out, so its output column stays blank for this variable.
Calc_Data <- All_Data |>
  filter(Variable == "gdp_real_gdp_in_2021c") |>
  inner_join(All_Data |>
      filter(Variable == "demographics_population") |>
      select(Scenario, Run, Year, Population = Value),
    by = c("Scenario", "Run", "Year")) |>
  mutate(Per_Capita = Value / Population) |>
  group_by(Scenario, Run) |>
  arrange(Year, .by_group = TRUE) |>
  mutate(Value = (Per_Capita / lag(Per_Capita) - 1) * 100) |>
  ungroup() |>
  filter(!is.na(Value)) |>
  mutate(Variable = "calc_gdp_pc_growth_pct") |>
  select(Scenario, Variable, Run, Year, Value)

All_Data <- bind_rows(All_Data, Calc_Data)

## filter(All_Data, Variable == "calc_gdp_pc_growth_pct", Year == 2020)


## ** Food Waste [per capita] --------------------------------------------------

# Food waste as the gap between what the food system supplies and what people
# eat: availability minus intake, both kcal/cap/day (the mapping sheet defines
# it as the difference between food availability and intake). Consumes the
# availability series computed above; intake is FRIDA's per-capita demand.
Calc_Data <- All_Data |>
  filter(Variable == "calc_food_availability_kcal_cap_day") |>
  inner_join(All_Data |>
      filter(Variable == "total_food_demand_average_daily_demand_per_capita") |>
      select(Scenario, Run, Year, Intake = Value),
    by = c("Scenario", "Run", "Year")) |>
  mutate(Variable = "calc_food_waste_kcal_cap_day",
         Value    = Value - Intake) |>
  select(-Intake)

All_Data <- bind_rows(All_Data, Calc_Data)

## filter(All_Data, Variable == "calc_food_waste_kcal_cap_day", Year == 2020)


## ** Land Cover (total) --------------------------------------------------------

# Scenario Compass. Constant total land area (no FRIDA variable). The
# Scenario x Run x Year grid is borrowed from land_use_cropland; if that
# variable is absent no rows are produced.
Calc_Data <- All_Data |>
  filter(Variable == "land_use_cropland") |>
  mutate(Variable = "calc_total_land_cover_mha",
         Value    = Total_Land_Cover_Mha)

All_Data <- bind_rows(All_Data, Calc_Data)


## ** Building Stock|Residential and Commercial|Floor Space|Gross --------------

# Scenario Compass. Actual useful floor area, Mm2 -> billion m2.
Calc_Data <- All_Data |>
  filter(Variable == "concrete_actual_useful_floor_area") |>
  mutate(Variable = "calc_building_floor_space_bm2",
         Value    = Value * Mm2_to_bm2)

All_Data <- bind_rows(All_Data, Calc_Data)


## ** Emissions|CO2|Other -----------------------------------------------------

# Scenario Compass. Concrete (industrial process) CO2 plus CCS storage
# leakage CO2, both in MtCO2/yr.
Calc_Data <- All_Data |>
  filter(Variable %in% c("concrete_co2_emissions",
                         "ccs_co2_emissions_from_leakage")) |>
  group_by(Scenario, Run, Year) |>
  summarise(Value = sum(Value, na.rm = TRUE), .groups = "drop") |>
  mutate(Variable = "calc_emissions_co2_other_mtco2")

All_Data <- bind_rows(All_Data, Calc_Data)


## ** Final Energy|Carbon Management -------------------------------------------

# Scenario Compass. DACC energy usage, TWh/yr -> EJ/yr.
Calc_Data <- All_Data |>
  filter(Variable == "energy_demand_dacc_energy_usage") |>
  mutate(Variable = "calc_final_energy_carbon_management_ej",
         Value    = Value * TWh_to_EJ)

All_Data <- bind_rows(All_Data, Calc_Data)


## ** Primary Energy|Non-Biomass Renewables ------------------------------------

# Renewable output (TWh) -> input-equivalent primary EJ: TWh_to_EJ divided by
# the fossil conversion efficiency (see Preamble).
Calc_Data <- All_Data |>
  filter(Variable == "renewable_energy_total_non_biomass_renewable_energy_output") |>
  inner_join(Fossil_Conversion_Efficiency, by = c("Scenario", "Run", "Year")) |>
  mutate(Variable = "calc_primary_energy_non_biomass_renewables_ej",
         Value    = Value * TWh_to_EJ / Efficiency) |>
  select(-Efficiency)

All_Data <- bind_rows(All_Data, Calc_Data)


## ** Primary Energy|Hydro -----------------------------------------------------

# Scenario Compass. Also mapped to Secondary Energy|Electricity|Hydro (there
# without the efficiency division — secondary energy stays at generation).
Calc_Data <- All_Data |>
  filter(Variable == "hydropower_energy_hydropower_energy_output") |>
  inner_join(Fossil_Conversion_Efficiency, by = c("Scenario", "Run", "Year")) |>
  mutate(Variable = "calc_primary_energy_hydro_ej",
         Value    = Value * TWh_to_EJ / Efficiency) |>
  select(-Efficiency)

All_Data <- bind_rows(All_Data, Calc_Data)


## ** Primary Energy|Fossil ----------------------------------------------------

# Scenario Compass. Secondary fossil energy output, TWh/yr -> EJ/yr.
# The mapping sheet says ZJ/yr, but FRIDA.stmx declares TWh/Year (verified
# 2026-07-07) - using TWh_to_EJ, not ZJ_to_EJ.
Calc_Data <- All_Data |>
  filter(Variable == "fossil_energy_secondary_fossil_energy_output") |>
  mutate(Variable = "calc_primary_energy_fossil_ej",
         Value    = Value * TWh_to_EJ)

All_Data <- bind_rows(All_Data, Calc_Data)


## ** Primary Energy|Coal|w/ CCS ----------------------------------------------

# FRIDA has no plant-level split of energy produced with vs without CCS, so
# the emissions-capture share stands in for it: effective share per fuel =
# share of emissions capturable (fuel module) x share of capturable emissions
# captured (CCS module), joined per Scenario x Run x Year. Capture — not
# storage — shares, matching the IAMC w/ CCS definition.
CCS_Share_Coal <- All_Data |>
  filter(Variable == "fossil_energy_coal_share_of_coal_emissions_capturable") |>
  inner_join(All_Data |>
      filter(Variable == "ccs_share_of_capturable_coal_emissions_captured") |>
      select(Scenario, Run, Year, Captured = Value),
    by = c("Scenario", "Run", "Year")) |>
  transmute(Scenario, Run, Year, Share = Value * Captured)

Calc_Data <- All_Data |>
  filter(Variable == "fossil_energy_coal_primary_fossil_energy_fuel") |>
  inner_join(CCS_Share_Coal, by = c("Scenario", "Run", "Year")) |>
  mutate(Variable = "calc_primary_energy_coal_wccs_ej",
         Value    = Value * ZJ_to_EJ * Share) |>
  select(-Share)

All_Data <- bind_rows(All_Data, Calc_Data)

## filter(All_Data, Variable == "calc_primary_energy_coal_wccs_ej", Year == 2020)


## ** Primary Energy|Gas|w/ CCS -----------------------------------------------

CCS_Share_Gas <- All_Data |>
  filter(Variable == "fossil_energy_gas_share_of_gas_emissions_capturable") |>
  inner_join(All_Data |>
      filter(Variable == "ccs_share_of_capturable_gas_emissions_captured") |>
      select(Scenario, Run, Year, Captured = Value),
    by = c("Scenario", "Run", "Year")) |>
  transmute(Scenario, Run, Year, Share = Value * Captured)

Calc_Data <- All_Data |>
  filter(Variable == "fossil_energy_gas_primary_fossil_energy_fuel") |>
  inner_join(CCS_Share_Gas, by = c("Scenario", "Run", "Year")) |>
  mutate(Variable = "calc_primary_energy_gas_wccs_ej",
         Value    = Value * ZJ_to_EJ * Share) |>
  select(-Share)

All_Data <- bind_rows(All_Data, Calc_Data)


## ** Primary Energy|Oil|w/ CCS -----------------------------------------------

CCS_Share_Oil <- All_Data |>
  filter(Variable == "fossil_energy_oil_share_of_oil_emissions_capturable") |>
  inner_join(All_Data |>
      filter(Variable == "ccs_share_of_capturable_oil_emissions_captured") |>
      select(Scenario, Run, Year, Captured = Value),
    by = c("Scenario", "Run", "Year")) |>
  transmute(Scenario, Run, Year, Share = Value * Captured)

Calc_Data <- All_Data |>
  filter(Variable == "fossil_energy_oil_primary_fossil_energy_fuel") |>
  inner_join(CCS_Share_Oil, by = c("Scenario", "Run", "Year")) |>
  mutate(Variable = "calc_primary_energy_oil_wccs_ej",
         Value    = Value * ZJ_to_EJ * Share) |>
  select(-Share)

All_Data <- bind_rows(All_Data, Calc_Data)


## ** Primary Energy|Fossil|w/ CCS --------------------------------------------

# Sum of the three per-fuel w/ CCS series computed above.
Calc_Data <- All_Data |>
  filter(Variable %in% c("calc_primary_energy_coal_wccs_ej",
                         "calc_primary_energy_gas_wccs_ej",
                         "calc_primary_energy_oil_wccs_ej")) |>
  group_by(Scenario, Run, Year) |>
  summarise(Value = sum(Value, na.rm = TRUE), .groups = "drop") |>
  mutate(Variable = "calc_primary_energy_fossil_wccs_ej")

All_Data <- bind_rows(All_Data, Calc_Data)


## ** Primary Energy|Biomass|w/ CCS and w/o CCS -------------------------------

# Biofuel secondary output split by the biofuel capture share; w/o CCS is the
# complement, so the two always sum to the full series. Converted to
# input-equivalent primary energy (divided by the fossil conversion
# efficiency), like the other non-fossil primary variables.
CCS_Share_Bio <- All_Data |>
  filter(Variable == "bio_fuel_energy_share_of_biofuel_emissions_capturable") |>
  inner_join(All_Data |>
      filter(Variable == "ccs_share_of_capturable_biofuel_emissions_captured") |>
      select(Scenario, Run, Year, Captured = Value),
    by = c("Scenario", "Run", "Year")) |>
  transmute(Scenario, Run, Year, Share = Value * Captured)

Bio_With_Share <- All_Data |>
  filter(Variable == "bio_fuel_energy_bio_fuel_secondary_energy_output") |>
  inner_join(CCS_Share_Bio, by = c("Scenario", "Run", "Year")) |>
  inner_join(Fossil_Conversion_Efficiency, by = c("Scenario", "Run", "Year"))

Calc_Data <- Bio_With_Share |>
  mutate(Variable = "calc_primary_energy_biomass_wccs_ej",
         Value    = Value * TWh_to_EJ / Efficiency * Share) |>
  select(-Share, -Efficiency)
All_Data <- bind_rows(All_Data, Calc_Data)

Calc_Data <- Bio_With_Share |>
  mutate(Variable = "calc_primary_energy_biomass_woccs_ej",
         Value    = Value * TWh_to_EJ / Efficiency * (1 - Share)) |>
  select(-Share, -Efficiency)
All_Data <- bind_rows(All_Data, Calc_Data)


## ** Water Withdrawal ---------------------------------------------------------

# Scenario Compass. Total water withdrawal, m3/yr -> km3/yr.
Calc_Data <- All_Data |>
  filter(Variable == "freshwater_total_water_withdrawal") |>
  mutate(Variable = "calc_water_withdrawal_km3",
         Value    = Value * m3_to_km3)

All_Data <- bind_rows(All_Data, Calc_Data)


## ** Water Withdrawal|Irrigation ----------------------------------------------

# Scenario Compass. Agricultural water withdrawal, m3/yr -> km3/yr.
Calc_Data <- All_Data |>
  filter(Variable == "freshwater_agricultural_water_withdrawal") |>
  mutate(Variable = "calc_water_withdrawal_irrigation_km3",
         Value    = Value * m3_to_km3)

All_Data <- bind_rows(All_Data, Calc_Data)


## ** Consumption ---------------------------------------------------------------

# Scenario Compass. Real private consumption (billion 2021 USD/yr) deflated.
# Also mapped to Expenditure|Households. Distinct from the Policy Cost|
# Consumption Loss calc, which awaits the baseline-minus-policy formulation.
Calc_Data <- All_Data |>
  filter(Variable == "circular_flow_real_private_consumption_2021c") |>
  mutate(Variable = "calc_consumption_busd2010",
         Value    = Value * Defl_2021_to_2010)

All_Data <- bind_rows(All_Data, Calc_Data)


## ** Debt ----------------------------------------------------------------------

# Scenario Compass. Real bank assets, billion 2021 USD (stock) deflated.
Calc_Data <- All_Data |>
  filter(Variable == "finance_real_bank_assets_2021c") |>
  mutate(Variable = "calc_debt_busd2010",
         Value    = Value * Defl_2021_to_2010)

All_Data <- bind_rows(All_Data, Calc_Data)


## ** Debt|Government ------------------------------------------------------------

# Scenario Compass. Real government debt, billion 2021 USD (stock) deflated.
Calc_Data <- All_Data |>
  filter(Variable == "government_real_government_debt_2021c") |>
  mutate(Variable = "calc_debt_government_busd2010",
         Value    = Value * Defl_2021_to_2010)

All_Data <- bind_rows(All_Data, Calc_Data)


## ** Expenditure|Government ------------------------------------------------------

# Scenario Compass. Real public expenditure deflated. The mapping sheet writes
# "2201c$" — assumed typo for 2021c$; verify stem against real FRIDA output.
Calc_Data <- All_Data |>
  filter(Variable == "government_real_public_expenditure_2021c") |>
  mutate(Variable = "calc_expenditure_government_busd2010",
         Value    = Value * Defl_2021_to_2010)

All_Data <- bind_rows(All_Data, Calc_Data)


## ** Revenue|Government ----------------------------------------------------------

# Scenario Compass. Real total public tax income deflated.
Calc_Data <- All_Data |>
  filter(Variable == "government_real_total_public_tax_income_2021c") |>
  mutate(Variable = "calc_revenue_government_busd2010",
         Value    = Value * Defl_2021_to_2010)

All_Data <- bind_rows(All_Data, Calc_Data)


## ** Investment ------------------------------------------------------------------

# Scenario Compass. Real total investment deflated.
Calc_Data <- All_Data |>
  filter(Variable == "finance_real_total_investment_2021c") |>
  mutate(Variable = "calc_investment_busd2010",
         Value    = Value * Defl_2021_to_2010)

All_Data <- bind_rows(All_Data, Calc_Data)


## ** Investment|Energy Supply -----------------------------------------------------

# Scenario Compass. FRIDA.stmx declares Energy Investments in c$/Year = plain
# constant 2021 USD (the Economy module uses bc$ for billions): scale to
# billions (x 1e-9) then deflate. Applies to all Energy Investments sections
# below; see the constants Preamble for the open magnitude question. The
# extraction/electricity stems below still need checking against real file
# names.
Calc_Data <- All_Data |>
  filter(Variable == "energy_investments_total_investment") |>
  mutate(Variable = "calc_investment_energy_supply_busd2010",
         Value    = Value * USD_to_bUSD * Defl_2021_to_2010)

All_Data <- bind_rows(All_Data, Calc_Data)


## ** Investment|Energy Supply|Extraction|Coal ---------------------------------------

# Scenario Compass. Coal investments in fossil fuel extraction capital, deflated.
Calc_Data <- All_Data |>
  filter(Variable == "energy_investments_coal_investments_allocated_to_capacity_construction_in_fossil_fuel_extraction_capital") |>
  mutate(Variable = "calc_investment_extraction_coal_busd2010",
         Value    = Value * USD_to_bUSD * Defl_2021_to_2010)

All_Data <- bind_rows(All_Data, Calc_Data)


## ** Investment|Energy Supply|Extraction|Oil -----------------------------------------

Calc_Data <- All_Data |>
  filter(Variable == "energy_investments_oil_gross_investments_in_fossil_fuel_extraction_capital") |>
  mutate(Variable = "calc_investment_extraction_oil_busd2010",
         Value    = Value * USD_to_bUSD * Defl_2021_to_2010)

All_Data <- bind_rows(All_Data, Calc_Data)


## ** Investment|Energy Supply|Extraction|Gas -----------------------------------------

Calc_Data <- All_Data |>
  filter(Variable == "energy_investments_gas_gross_investments_in_fossil_fuel_extraction_capital") |>
  mutate(Variable = "calc_investment_extraction_gas_busd2010",
         Value    = Value * USD_to_bUSD * Defl_2021_to_2010)

All_Data <- bind_rows(All_Data, Calc_Data)


## ** Investment|Energy Supply|Electricity|Solar --------------------------------------

# Scenario Compass. Units blank in the mapping sheet for the four electricity
# investment rows; FRIDA.stmx declares c$/Year — scale x 1e-9 then deflate.
Calc_Data <- All_Data |>
  filter(Variable == "energy_investments_investments_allocated_to_capacity_construction_in_solar_energy_capacity") |>
  mutate(Variable = "calc_investment_electricity_solar_busd2010",
         Value    = Value * USD_to_bUSD * Defl_2021_to_2010)

All_Data <- bind_rows(All_Data, Calc_Data)


## ** Investment|Energy Supply|Electricity|Wind ---------------------------------------

Calc_Data <- All_Data |>
  filter(Variable == "energy_investments_investments_allocated_to_capacity_construction_in_wind_energy_capacity") |>
  mutate(Variable = "calc_investment_electricity_wind_busd2010",
         Value    = Value * USD_to_bUSD * Defl_2021_to_2010)

All_Data <- bind_rows(All_Data, Calc_Data)


## ** Investment|Energy Supply|Electricity|Hydro --------------------------------------

Calc_Data <- All_Data |>
  filter(Variable == "energy_investments_investments_allocated_to_capacity_construction_in_hydropower_energy_capacity") |>
  mutate(Variable = "calc_investment_electricity_hydro_busd2010",
         Value    = Value * USD_to_bUSD * Defl_2021_to_2010)

All_Data <- bind_rows(All_Data, Calc_Data)


## ** Investment|Energy Supply|Electricity|Nuclear ------------------------------------

Calc_Data <- All_Data |>
  filter(Variable == "energy_investments_investments_in_nuclear_capacity") |>
  mutate(Variable = "calc_investment_electricity_nuclear_busd2010",
         Value    = Value * USD_to_bUSD * Defl_2021_to_2010)

All_Data <- bind_rows(All_Data, Calc_Data)


## ** Not implemented — noted only --------------------------------------------

# Mapping-sheet variables without a workable FRIDA source, left out of this
# set on purpose (full assessment: Mapping/FRIDA_Compass_VariableMapping_v1.xlsx):
#   - Useful Energy — FRIDA has no useful-energy accounting. The nearest
#     series, Total Energy Output, is delivered energy and already feeds
#     Final Energy; reporting it a second time under this name would mislead.
#   - Health|Child Mortality, Agricultural Demand — no agreed FRIDA source.
#   - Ocean|Acidification — no mapping identified; expected from outside the
#     pipeline (RCMIP script); candidate: Ocean.Warm surface ocean pH.
#   - CO2 Emissions / |Energy / |Food and Land Use — aliases of series already
#     reported as Emissions|CO2 (Diagnostic set), Emissions|CO2|Energy and
#     Emissions|CO2|AFOLU (this set).
# The additional pre-Compass variables from the mapping sheet (temperature
# anomaly, capacities, secondary energy by fuel) are outside this submission
# set; they are documented in Mapping/FRIDA_Additional_Variables_v1.xlsx.


## * Summary ##################################################################

cat("All_Data after Calculate:", nrow(All_Data), "rows\n")
cat("Calc variables added:\n")
for (V in sort(unique(All_Data$Variable[grepl("^calc_", All_Data$Variable)]))) cat(" ", V, "\n")

## head(All_Data)
## filter(All_Data, grepl("^calc_", Variable))


## * Export Intermediate ######################################################

saveRDS(All_Data, file.path(Path_Output, paste0("2-All_Data_Calc", File_Suffix, ".RDS")))
cat("\nSaved: Data-Output/2-All_Data_Calc", File_Suffix, ".RDS\n", sep = "")
