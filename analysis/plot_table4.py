"""
Table 4: Market outcomes under varying renewable generation shares and production incentives.

Model runs needed (10 scenarios, 20 GW, 95% efficiency; see "Overview of All Scenarios" in the README):
    ptc0:  b20_hrs4_w1_s1_days4_ptc0    b20_hrs4_w7_s7_days4_ptc0
    ptc5:  b20_hrs4_w{1_s1, 3_s3, 5_s5, 7_s7}_days4_ptc5
    ptc10: b20_hrs4_w{1_s1, 3_s3, 5_s5, 7_s7}_days4_ptc10

Usage:  python plot_table4.py
"""

from common import get, load_summary, parse_args, save_table
import pandas as pd

args = parse_args("Table 4: market outcomes by VRE share and incentive", summary=True)
summary = load_summary(args.summary)

# Only the combinations shown in the paper (40% and 80% VRE without an incentive
# are already in Table 2).
rows = [
    # (incentive, VRE share, scenario folder)
    (0,  "15%", "tscc_all_weeks_1w_1s_20b_4hrs_0ptc_4days"),
    (0,  "80%", "tscc_all_weeks_7w_7s_20b_4hrs_0ptc_4days"),
    (5,  "15%", "tscc_all_weeks_1w_1s_20b_4hrs_-5ptc_4days"),
    (5,  "40%", "tscc_all_weeks_3w_3s_20b_4hrs_-5ptc_4days"),
    (5,  "65%", "tscc_all_weeks_5w_5s_20b_4hrs_-5ptc_4days"),
    (5,  "80%", "tscc_all_weeks_7w_7s_20b_4hrs_-5ptc_4days"),
    (10, "15%", "tscc_all_weeks_1w_1s_20b_4hrs_-10ptc_4days"),
    (10, "40%", "tscc_all_weeks_3w_3s_20b_4hrs_-10ptc_4days"),
    (10, "65%", "tscc_all_weeks_5w_5s_20b_4hrs_-10ptc_4days"),
    (10, "80%", "tscc_all_weeks_7w_7s_20b_4hrs_-10ptc_4days"),
]


def negative_price_mean(value):
    return "N/A" if pd.isna(value) else round(value, 2)


table4 = pd.DataFrame([{
    "Renewable production incentive ($/MW)": ptc,
    "VRE share": vre,
    "CC: Average prices ($/MW)": round(get(summary, folder, "iso-control", "average_price"), 2),
    "CC: Frequency of negative prices (hours)": int(get(summary, folder, "iso-control", "neg_price_count")),
    "CC: Average negative prices ($/MW)": negative_price_mean(get(summary, folder, "iso-control", "neg_price_mean")),
    "SS: Average prices ($/MW)": round(get(summary, folder, "bi-level", "average_price"), 2),
    "SS: Frequency of negative prices (hours)": int(get(summary, folder, "bi-level", "neg_price_count")),
    "SS: Average negative prices ($/MW)": negative_price_mean(get(summary, folder, "bi-level", "neg_price_mean")),
} for ptc, vre, folder in rows])

print("CC = Central Control, SS = Strategic Storage")
save_table(table4, "table4", args.out,
           "Table 4: Market outcomes under varying renewable generation shares and incentives")
