"""
Table 1: Capacity mix in the WECC region.

Model runs needed: none (this table describes the input data).

Usage:  python plot_table1.py
"""

import pandas as pd

from common import DATA_DIR, parse_args, save_table

args = parse_args("Table 1: capacity mix in the WECC region")

# Table 1 describes the baseline WECC system (199.9 GW), which is the data_WECC_large
# dataset. (The model itself runs on data_WECC_small_mod, a smaller version of it.)
generators = pd.read_csv(DATA_DIR / "data_WECC_large" / "Generators_data.csv")

resource_group = {
    "Biomass": "Biomass",
    "Conventional Hydroelectric": "Hydro",
    "Small Hydroelectric": "Hydro",
    "Conventional Steam Coal": "Coal",
    "Geothermal": "Geothermal",
    "Natural Gas Fired Combined Cycle": "Natural gas",
    "Natural Gas Fired Combustion Turbine": "Natural gas",
    "Natural Gas Steam Turbine": "Natural gas",
    "Nuclear": "Nuclear",
    "Onshore Wind Turbine": "Wind",
    "Solar Photovoltaic": "Solar",
    "Hydroelectric Pumped Storage": "Energy storage",
}
generators["Resource type"] = generators["Technology"].map(resource_group)

table1 = generators.groupby("Resource type").agg(
    **{"Installed capacity (GW)": ("Existing_Cap_MW", lambda x: round(x.sum() / 1000, 1)),
       "Number of units": ("Num_units", "sum")}
).reindex(["Biomass", "Hydro", "Coal", "Geothermal", "Natural gas",
           "Nuclear", "Wind", "Solar", "Energy storage"]).reset_index()

save_table(table1, "table1", args.out, "Table 1: Capacity mix in the WECC region")
