"""
Table 2: System costs and storage profits under different scenarios.

Model runs needed (6 scenarios, see "Overview of All Scenarios" in the README):
    b20_hrs4_w3_s3_days4_ptc0     b20_hrs4_w3_s3_days4_ptc10     b0_hrs4_w3_s3_days4_ptc10
    b20_hrs4_w7_s7_days4_ptc0     b20_hrs4_w7_s7_days4_ptc10     b0_hrs4_w7_s7_days4_ptc10

Usage:  python plot_table2.py
"""

from common import get, load_summary, parse_args, save_table
import pandas as pd

args = parse_args("Table 2: system costs and storage profits", summary=True)
summary = load_summary(args.summary)

# System costs exclude the renewable production incentive (as in the paper's caption),
# so the metric is system_cost_no_ptc_no_storage rather than the raw system_cost.
rows = [
    # (incentive, VRE share, scenario folder, regime in the summary file, label in the paper)
    (0,  "40%", "tscc_all_weeks_3w_3s_20b_4hrs_0ptc_4days",   "iso-control", "Central Control"),
    (0,  "40%", "tscc_all_weeks_3w_3s_20b_4hrs_0ptc_4days",   "bi-level",    "Strategic Storage"),
    (0,  "80%", "tscc_all_weeks_7w_7s_20b_4hrs_0ptc_4days",   "iso-control", "Central Control"),
    (0,  "80%", "tscc_all_weeks_7w_7s_20b_4hrs_0ptc_4days",   "bi-level",    "Strategic Storage"),
    (10, "40%", "tscc_all_weeks_3w_3s_0b_4hrs_-10ptc_4days",  "iso-control", "No Storage"),
    (10, "40%", "tscc_all_weeks_3w_3s_20b_4hrs_-10ptc_4days", "iso-control", "Central Control"),
    (10, "40%", "tscc_all_weeks_3w_3s_20b_4hrs_-10ptc_4days", "bi-level",    "Strategic Storage"),
    (10, "80%", "tscc_all_weeks_7w_7s_0b_4hrs_-10ptc_4days",  "iso-control", "No Storage"),
    (10, "80%", "tscc_all_weeks_7w_7s_20b_4hrs_-10ptc_4days", "iso-control", "Central Control"),
    (10, "80%", "tscc_all_weeks_7w_7s_20b_4hrs_-10ptc_4days", "bi-level",    "Strategic Storage"),
]

table2 = pd.DataFrame([{
    "Renewable production incentive ($/MW)": ptc,
    "VRE share": vre,
    "Storage behavior scenario": label,
    "Storage capacity (GW)": get(summary, folder, scen, "storage_cap"),
    "System costs ($m)": round(get(summary, folder, scen, "system_cost_no_ptc_no_storage") / 1e6, 1),
    "Storage profits ($m)": "N/A" if label == "No Storage" else round(get(summary, folder, scen, "storage_profit") / 1e6, 1),
    "Average prices ($/MW)": round(get(summary, folder, scen, "average_price"), 2),
} for ptc, vre, folder, scen, label in rows])

save_table(table2, "table2", args.out, "Table 2: System costs and storage profits under different scenarios")
