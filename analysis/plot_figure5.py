"""
Figure 5: Supplier surplus by resource type.

Model runs needed (4 scenarios, see "Overview of All Scenarios" in the README):
    b20_hrs4_w3_s3_days4_ptc0     b20_hrs4_w3_s3_days4_ptc10
    b20_hrs4_w7_s7_days4_ptc0     b20_hrs4_w7_s7_days4_ptc10

This figure also needs the per-generator output (the generation/ subfolder inside
each scenario folder), which the model writes for every run.

Usage:  python plot_figure5.py
"""

import pandas as pd
import plotly.graph_objects as go
from plotly.subplots import make_subplots

from common import (DATA_DIR, color_order, find_scenario_dir, font_dict, get, load_hourly,
                    load_summary, parse_args, save_figure)

args = parse_args("Figure 5: supplier surplus by resource type", summary=True, root=True)
summary = load_summary(args.summary)

# --- Marginal cost of every generator (Var O&M + heat rate x fuel cost) ---------------
# This uses the model's input data (not the PTC-adjusted bids used inside the model).
model_data = DATA_DIR / "data_WECC_small_mod"
generators = pd.read_csv(model_data / "Generators_data.csv")
fuel_cost = dict(pd.read_csv(model_data / "Fuels_data.csv")[["Fuel", "Cost_per_MMBtu"]].values)


def marginal_cost(row):
    # Generators without fuel are marked "None" in the data; recent pandas versions read
    # that string as a missing value, so handle both.
    if pd.isna(row["Fuel"]) or row["Fuel"] == "None":
        return row["Var_OM_cost_per_MWh"]
    return row["Var_OM_cost_per_MWh"] + row["Heat_rate_MMBTU_per_MWh"] * fuel_cost[row["Fuel"]]


mc_by_rid = generators.assign(mc=generators.apply(marginal_cost, axis=1)).set_index("R_ID")["mc"]

# --- Resource groups ------------------------------------------------------------------
VRE_PTC_RESOURCES = {"onshore_wind_turbine", "solar_photovoltaic"}                    # earn the incentive
UNDERSCORE_RESOURCES = VRE_PTC_RESOURCES | {"small_hydroelectric"}                    # dispatched as VRE-like
WIND_SOLAR = {"onshore_wind_turbine", "solar_photovoltaic"}
NON_VRE_RENEWABLE = {"biomass", "conventional_hydroelectric", "small_hydroelectric", "geothermal", "nuclear"}
FOSSIL = {"conventional_steam_coal", "natural_gas_fired_combined_cycle",
          "natural_gas_fired_combustion_turbine", "natural_gas_steam_turbine"}


def compute_generator_surplus(folder_name, ptc):
    """Surplus (revenue - operating cost, $m) of each resource type, for both regimes."""
    scenario_dir = find_scenario_dir(args.root, folder_name)
    gen_dir = scenario_dir / "generation"
    if not gen_dir.is_dir():
        raise SystemExit(f"{gen_dir} not found. Figure 5 needs the per-generator output "
                         "(generation/ subfolder) of this scenario.")

    cap_mix = pd.read_csv(scenario_dir / "params_cap_mix.csv")
    cap_mix = cap_mix[cap_mix["resource"] != "storage"].reset_index(drop=True)
    df_bi = load_hourly(args.root, folder_name, "bi-level")
    df_iso = load_hourly(args.root, folder_name, "iso-control")

    def revenue(df, resource):
        # Wind and solar bid at minus the incentive, so the incentive is added back to the price
        if resource in UNDERSCORE_RESOURCES:
            price = df["price"] + ptc if resource in VRE_PTC_RESOURCES else df["price"]
            return (price * df["_" + resource]).sum() / 1e6
        return (df["price"] * df[resource]).sum() / 1e6

    cap_mix["revenues_bi"] = cap_mix["resource"].apply(lambda r: revenue(df_bi, r))
    cap_mix["revenues_iso"] = cap_mix["resource"].apply(lambda r: revenue(df_iso, r))

    costs_bi = {r: 0.0 for r in cap_mix["resource"]}
    costs_iso = {r: 0.0 for r in cap_mix["resource"]}
    for period in range(1, 91):
        for regime, costs in [("iso", costs_iso), ("bi", costs_bi)]:
            d = pd.read_csv(gen_dir / f"{regime}_gen_{period}.csv")
            d["cost"] = d["gen"] * d["r_id"].map(mc_by_rid) / 1e6
            for resource, total in d.groupby("resource")["cost"].sum().items():
                costs[resource] += total

    cap_mix["profits_bi"] = cap_mix["revenues_bi"] - cap_mix["resource"].map(costs_bi)
    cap_mix["profits_iso"] = cap_mix["revenues_iso"] - cap_mix["resource"].map(costs_iso)
    return cap_mix


def aggregate(cap_mix, profit_col):
    return {
        "Wind and solar resources": cap_mix.loc[cap_mix.resource.isin(WIND_SOLAR), profit_col].sum(),
        "Other clean energy resources": cap_mix.loc[cap_mix.resource.isin(NON_VRE_RENEWABLE), profit_col].sum(),
        "Fossil-fueled generators": cap_mix.loc[cap_mix.resource.isin(FOSSIL), profit_col].sum(),
    }


fig5_folders = [
    ("40%", 0,  "tscc_all_weeks_3w_3s_20b_4hrs_0ptc_4days"),
    ("40%", 10, "tscc_all_weeks_3w_3s_20b_4hrs_-10ptc_4days"),
    ("80%", 0,  "tscc_all_weeks_7w_7s_20b_4hrs_0ptc_4days"),
    ("80%", 10, "tscc_all_weeks_7w_7s_20b_4hrs_-10ptc_4days"),
]

rows = []
for vre, ptc, folder in fig5_folders:
    cap_mix = compute_generator_surplus(folder, ptc)
    for regime_label, profit_col, scenario_name in [("Central Control", "profits_iso", "iso-control"),
                                                    ("Strategic Storage", "profits_bi", "bi-level")]:
        agg = aggregate(cap_mix, profit_col)
        agg["Storage resources"] = get(summary, folder, scenario_name, "storage_profit") / 1e6
        agg["VRE penetration level"] = vre
        agg["Renewable production incentive"] = ptc
        agg["Control"] = regime_label
        rows.append(agg)

fig5_summary = pd.DataFrame(rows)
resource_type = ["Wind and solar resources", "Other clean energy resources", "Fossil-fueled generators", "Storage resources"]

# The data behind the figure (m$)
args.out.mkdir(parents=True, exist_ok=True)

data_1 = fig5_summary[fig5_summary["VRE penetration level"] == "40%"].reset_index(drop=True)
data_2 = fig5_summary[fig5_summary["VRE penetration level"] == "80%"].reset_index(drop=True)

fig = make_subplots(rows=2, cols=1, shared_yaxes=True, shared_xaxes=True, vertical_spacing=0.1,
                    subplot_titles=("(a) 40% VRE Generation Share", "(b) 80% VRE Generation Share"))

# Row order in data_1 / data_2: Central Control and Strategic Storage without the incentive (0, 1),
# then with the incentive (2, 3). Hatched bars = with the incentive.
bar_styles = [
    ("Central Control, No Renewable Incentive",  color_order[0], None),
    ("Strategic Storage, No Renewable Incentive", color_order[1], None),
    ("Central Control, With Renewable Incentive", color_order[0], dict(shape="/", fgcolor="white", size=8, solidity=0.5)),
    ("Strategic Storage, With Renewable Incentive", color_order[1], dict(shape="/", fgcolor=color_order[3], size=8, solidity=0.5)),
]
for panel_row, panel_data in [(1, data_1), (2, data_2)]:
    for i, (name, color, pattern) in enumerate(bar_styles):
        extra = {"marker_pattern": pattern} if pattern else {}
        fig.add_trace(go.Bar(x=resource_type, y=panel_data.loc[i, resource_type],
                             showlegend=(panel_row == 1), marker_color=color,
                             name=name, **extra), row=panel_row, col=1)

fig.update_layout(template="simple_white", barmode="group",
                  font=font_dict,
                  margin=dict(l=0, r=0, b=0, t=25),
                  uniformtext_minsize=9, uniformtext_mode="show",
                  legend=dict(yanchor="top", y=1.0, xanchor="right", x=1.0, orientation="h"),
                  width=900, height=1200,
                  yaxis_title="Total Surplus ($m)", yaxis2_title="Total Surplus ($m)")
fig.update_annotations(font=font_dict)
fig.update_xaxes(title_font=font_dict)
fig.update_yaxes(title_font=font_dict)

save_figure(fig, "figure5", args.out)
