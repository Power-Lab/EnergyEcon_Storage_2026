"""
Table 5: Market outcomes under varying storage capacities and efficiencies.

Model runs needed (8 scenarios, see "Overview of All Scenarios" in the README):
    40 GW:  b40_hrs4_w{3_s3, 7_s7}_days4_ptc0    b40_hrs4_w{3_s3, 7_s7}_days4_ptc10
    20 GW:  b20_hrs4_w{3_s3, 7_s7}_days4_ptc10_eff85    b20_hrs4_w{3_s3, 7_s7}_days4_ptc10_eff98

Usage:  python plot_table5.py
"""

from common import get, load_summary, parse_args, save_table
import pandas as pd

args = parse_args("Table 5: storage capacity and efficiency sensitivity", summary=True)
summary = load_summary(args.summary)

rows = [
    # (capacity GW, efficiency, VRE share, incentive, scenario folder)
    (40, "95%", "40%", 0,  "tscc_all_weeks_3w_3s_40b_4hrs_0ptc_4days"),
    (40, "95%", "80%", 0,  "tscc_all_weeks_7w_7s_40b_4hrs_0ptc_4days"),
    (40, "95%", "40%", 10, "tscc_all_weeks_3w_3s_40b_4hrs_-10ptc_4days"),
    (40, "95%", "80%", 10, "tscc_all_weeks_7w_7s_40b_4hrs_-10ptc_4days"),
    (20, "85%", "40%", 10, "tscc_all_weeks_3w_3s_20b_4hrs_-10ptc_4days_eff85"),
    (20, "85%", "80%", 10, "tscc_all_weeks_7w_7s_20b_4hrs_-10ptc_4days_eff85"),
    (20, "98%", "40%", 10, "tscc_all_weeks_3w_3s_20b_4hrs_-10ptc_4days_eff98"),
    (20, "98%", "80%", 10, "tscc_all_weeks_7w_7s_20b_4hrs_-10ptc_4days_eff98"),
]

table5 = pd.DataFrame([{
    "Storage capacity (GW)": cap,
    "One-way efficiency": eff,
    "VRE share": vre,
    "Renewable incentive ($/MW)": ptc,
    "CC: System costs ($m)": round(get(summary, folder, "iso-control", "system_cost_no_ptc_no_storage") / 1e6, 1),
    "CC: Storage profits ($m)": round(get(summary, folder, "iso-control", "storage_profit") / 1e6, 1),
    "SS: System costs ($m)": round(get(summary, folder, "bi-level", "system_cost_no_ptc_no_storage") / 1e6, 1),
    "SS: Storage profits ($m)": round(get(summary, folder, "bi-level", "storage_profit") / 1e6, 1),
} for cap, eff, vre, ptc, folder in rows])

print("CC = Central Control, SS = Strategic Storage")
save_table(table5, "table5", args.out,
           "Table 5: Market outcomes under varying storage capacities and efficiencies")
