"""
result_summary.py

Builds result_summary.csv from the raw per-scenario outputs in result_simplified/.

Usage:
    python result_summary.py
"""

import argparse
import glob
import os
import sys

import pandas as pd

# Target column order for result_summary.csv
COLUMNS = [
    "folder_name", "scenario_name", "vre_share", "ptc", "storage_cap",
    "efficiency", "ramping_charge", "system_cost", "storage_profit",
    "average_price", "storage_profit_per_yr", "system_cost_no_ptc_no_storage",
    "neg_price_count", "neg_price_mean", "ramping_charge_total",
    "storage_profit_after_ramping_charge",
]

# Metrics that are *input parameters* -- if missing/"N/A", default to a known
# value rather than leaving blank (e.g. no ramping charge applied means 0, not
# unknown).
INPUT_DEFAULTS = {
    "ramping_charge": 0.0,
}

# Metrics that are *computed outputs* -- if missing/"N/A", leave as NaN rather
# than fabricating a value (e.g. ramping_charge_total was never computed for a
# scenario that never had a ramping charge applied).
NUMERIC_METRICS = [
    "ptc", "storage_cap", "system_cost", "storage_profit", "average_price",
    "system_cost_no_ptc_no_storage", "neg_price_count", "neg_price_mean",
    "ramping_charge_total", "storage_profit_after_ramping_charge",
]


def find_summary_system_files(root):
    """Recursively find every summary_system.csv under root, regardless of
    nesting depth (flat or category-nested layout)."""
    pattern = os.path.join(root, "**", "summary_system.csv")
    return sorted(glob.glob(pattern, recursive=True))


def to_numeric(value):
    """Convert a value from summary_system.csv to numeric, treating 'N/A' as
    missing (NaN) rather than 0."""
    if isinstance(value, str) and value.strip().upper() == "N/A":
        return float("nan")
    return pd.to_numeric(value, errors="coerce")


def load_one_scenario(path):
    """Read one summary_system.csv and return a list of two row-dicts (one per
    scenario_name), matching result_summary.csv's schema."""
    df = pd.read_csv(path, index_col="Metric")

    rows = []
    for scenario_name in ["bi-level", "iso-control"]:
        if scenario_name not in df.columns:
            print(f"  WARNING: '{scenario_name}' column missing in {path}, skipping")
            continue

        col = df[scenario_name]
        row = {
            "folder_name": col["folder_name"],
            "scenario_name": scenario_name,
            "vre_share": col["vre_share"],
            "efficiency": to_numeric(col["storage_one_way_efficiency"]),
        }
        for metric in NUMERIC_METRICS:
            row[metric] = to_numeric(col[metric])
        for metric, default in INPUT_DEFAULTS.items():
            val = to_numeric(col[metric])
            row[metric] = default if pd.isna(val) else val

        row["storage_profit_per_yr"] = row["storage_profit"]  # confirmed identical; see docstring

        rows.append(row)
    return rows


def build_result_summary(root):
    paths = find_summary_system_files(root)
    if not paths:
        sys.exit(f"No summary_system.csv files found under {root!r}. Check --root.")

    print(f"Found {len(paths)} summary_system.csv files under {root!r}")

    all_rows = []
    seen_folders = set()
    duplicates_skipped = 0
    for path in paths:
        folder_name = os.path.basename(os.path.dirname(path))
        if folder_name in seen_folders:
            duplicates_skipped += 1
            continue
        seen_folders.add(folder_name)
        all_rows.extend(load_one_scenario(path))

    if duplicates_skipped:
        print(f"Skipped {duplicates_skipped} duplicate scenario folder(s) "
              f"(same folder_name appears under more than one category subfolder)")

    result = pd.DataFrame(all_rows)[COLUMNS]
    result = result.sort_values(
        ["vre_share", "ptc", "storage_cap", "efficiency", "ramping_charge", "scenario_name"]
    ).reset_index(drop=True)

    # ptc, storage_cap, and neg_price_count are always whole numbers (never NaN),
    # but upstream summary_system.csv files write them inconsistently -- some as
    # "20", others as "20.0" for the same value -- which forces the whole column
    # to float64 once concatenated. Cast explicitly so the output is consistent
    # regardless of how any individual source file happened to format it.
    for col in ["ptc", "storage_cap", "neg_price_count"]:
        result[col] = result[col].round().astype("int64")

    # system_cost and storage_profit: sub-dollar decimals aren't meaningful at
    # this scale ($m-$bn), and upstream summary_system.csv files vary in how
    # much precision they were written with (some ~10 significant figures, some
    # full Float64 precision -- see README). Rounding to the nearest dollar
    # removes that inconsistency along with the irrelevant decimals.
    result["system_cost"] = result["system_cost"].round().astype("int64")
    result["storage_profit"] = result["storage_profit"].round().astype("int64")
    result["storage_profit_per_yr"] = result["storage_profit"]  # re-derive from the now-rounded value

    # system_cost_no_ptc_no_storage: same reasoning as system_cost above, and
    # never NaN, so plain int64 is safe.
    result["system_cost_no_ptc_no_storage"] = result["system_cost_no_ptc_no_storage"].round().astype("int64")

    # storage_profit_after_ramping_charge: same reasoning, but this one IS NaN
    # for every scenario with no ramping charge applied (by design -- see the
    # NUMERIC_METRICS / NaN-handling note above). Plain int64 can't hold NaN, so
    # use pandas' nullable Int64 (capital I) to keep those rows blank rather
    # than fabricating a value for them.
    result["storage_profit_after_ramping_charge"] = (
        result["storage_profit_after_ramping_charge"].round().astype("Int64")
    )

    print(f"Built {len(result)} rows covering {result['folder_name'].nunique()} distinct scenarios")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default="result_simplified",
                         help="Root directory to search for scenario folders (default: result_simplified)")
    parser.add_argument("--out", default="result_summary.csv",
                         help="Output CSV path (default: result_summary.csv)")
    args = parser.parse_args()

    result = build_result_summary(args.root)
    result.to_csv(args.out, index=False)
    print(f"Wrote {args.out}")


if __name__ == "__main__":
    main()