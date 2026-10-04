"""
Shared helpers for the table*.py and figure*.py scripts in this folder.

By default the scripts read the model outputs provided in this repository
(analysis/result_summary.csv and analysis/result_simplified/).
"""

import argparse
import glob
from pathlib import Path

import pandas as pd

ANALYSIS_DIR = Path(__file__).resolve().parent
DATA_DIR = ANALYSIS_DIR.parent / "data"

# Plot styling shared by the figure scripts
color_order = ["#00629B", "#FFCD00", "#D462AD", "#C69214", "#6E963B", "#FC8900", "#00C6D7"]
font_dict = {"family": "Arial", "size": 24, "color": "#000000"}


def parse_args(description, summary=False, root=False):
    """Command-line options. --summary / --root are only offered to scripts that use them."""
    p = argparse.ArgumentParser(description=description)
    if summary:
        p.add_argument("--summary", type=Path, default=ANALYSIS_DIR / "result_summary.csv",
                       help="summary statistics file (default: %(default)s)")
    if root:
        p.add_argument("--root", type=Path, default=ANALYSIS_DIR / "result_simplified",
                       help="folder holding the per-scenario model outputs (default: %(default)s)")
    p.add_argument("--out", type=Path, default=ANALYSIS_DIR / "output",
                   help="folder where the table/figure files are saved (default: %(default)s)")
    return p.parse_args()


def load_summary(path):
    return pd.read_csv(path)


def get(summary, folder, scenario, metric):
    """One value from the summary statistics file. Stops with a clear message if the
    scenario has not been run / summarized yet."""
    row = summary[(summary.folder_name == folder) & (summary.scenario_name == scenario)]
    if row.empty:
        raise SystemExit(
            f"Scenario '{folder}' ({scenario}) is not in the summary statistics file.\n"
            "Run this scenario first (see the README) and regenerate the summary with "
            "result_summary.py.")
    return row[metric].iloc[0]


def find_scenario_dir(root, folder_name):
    """Locate a scenario folder under root, whether it sits directly inside it or one
    level deeper inside a category subfolder."""
    root = Path(root)
    direct = root / folder_name
    if direct.is_dir():
        return direct
    matches = glob.glob(str(root / "*" / folder_name))
    if matches:
        return Path(matches[0])
    raise SystemExit(f"Scenario folder '{folder_name}' not found under {root}.\n"
                     "Run this scenario first (see the README), or pass --root.")


def load_hourly(root, folder_name, scenario_name):
    """Hourly dispatch and prices ('bi-level' = Strategic Storage, 'iso-control' = Central Control)."""
    fname = "hourly_dispatch_strategic.csv" if scenario_name == "bi-level" else "hourly_dispatch_central.csv"
    return pd.read_csv(find_scenario_dir(root, folder_name) / fname)


def save_table(df, name, out_dir, title):
    """Print the table to the command line and save it as a CSV."""
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    path = out_dir / f"{name}.csv"
    print(f"\n{title}\n")
    print(df.to_string(index=False))
    df.to_csv(path, index=False)
    print(f"\nSaved {path}")


def save_figure(fig, name, out_dir):
    """Save the figure as a PDF."""
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    path = out_dir / f"{name}.pdf"
    fig.write_image(str(path))
    print(f"Saved {path}")
