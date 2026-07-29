# Description:
#   Shared conversion constants, sourced by every 2-Calculate-<set>.R script.
#   Keeping them in one file guarantees both variable sets always deflate and
#   convert with identical factors. Constants used by only one set stay in the
#   owning calculate script's Preamble.
#
#   All constants are multiplicative: X_to_Y = multiply an X-denominated value
#   to get a Y-denominated value.

## * Shared Conversion Constants ##############################################

TWh_to_EJ   <- 0.0036                     # 1 TWh = 3.6e15 J = 0.0036 EJ
ZJ_to_EJ    <- 1000                       # 1 ZJ (zetta joule) = 1000 EJ
t_to_Mt     <- 1e-6                       # 1 t = 1e-6 Mt (1 Mt = 1,000,000 t)
USD_to_bUSD <- 1e-9                       # 1 USD = 1e-9 billion USD

# Constant 2021 USD -> constant 2010 USD. The manual mapping doc
# (FRIDA_IAMC_VariableMapping_v5.xlsx) gives the 2010->2021 inflation factor
# 1.36716299937247; inverted here for the deflation direction.
Defl_2021_to_2010 <- 1/1.36716299937247   # = 0.731445
