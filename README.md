# Bilevel Optimization for Energy Storage Bidding

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

This project implements a bilevel optimization model for strategic storage bidding in electricity markets. The upper level optimizes storage bidding decisions, while the lower level solves the economic dispatch problem that clears the market.

## Contents
 
- [Key Features](#key-features)
- [Installation](#installation)
  - [Prerequisites](#prerequisites)
  - [Setup](#setup)
- [Project Structure](#project-structure)
- [Usage](#usage)
  - [Basic Example](#basic-example)
  - [Custom Parameters](#custom-parameters)
  - [Batch Processing](#batch-processing)
  - [All Scenarios Used in This Paper](#all-scenarios-used-in-this-paper)
- [Analysis and Figure Reproduction](#analysis-and-figure-reproduction)
  - [Generate result_summary.csv](#generate-result_summarycsv)
  - [Running the Notebook](#running-the-notebook)
  - [What's In Scope](#whats-in-scope)
- [Data Sources](#data-sources)
- [License](#license)
- [Maintainer](#maintainer)

## Key Features

- **Bilevel Optimization**: Implements convex bilevel formulation for storage bidding
- **Economic Dispatch**: Solves lower-level market clearing with variable renewable energy (VRE) integration
- **Storage Modeling**: Supports configurable storage capacity, duration, and efficiency parameters
- **Scenario Setting**: Supports different VRE penetration levels, storage capacities, and other sensitivity factors
- **Batch Processing**: Includes scripts for running multi-period simulations on HPC clusters

## Installation

### Prerequisites

- [Julia](https://julialang.org/downloads/) (version 1.6 or later recommended)
- [Gurobi Optimizer](https://www.gurobi.com/downloads/gurobi-software/) (academic license available)
- Required Julia packages: JuMP, Gurobi, BilevelJuMP, DataFrames, CSV, Plots, VegaLite

### Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/Power-Lab/EnergyEcon_Storage_2026.git
   cd EnergyEcon_Storage_2026
   ```

2. Install Julia dependencies:
   ```julia
   using Pkg
   Pkg.add(["JuMP", "HiGHS", "Gurobi", "BilevelJuMP", "DataFrames", "CSV", "Plots", "VegaLite", "Statistics", "PrettyTables", "FileIO"])
   ```

3. Set up Gurobi license (follow Gurobi installation instructions)

## Project Structure

```
├── code/                       # Julia source code
│   ├── bilevel_cvx.jl          # Strategic Storage: convex bilevel formulation
│   ├── ed.jl                   # Central Control: economic dispatch model
│   ├── run.jl                  # Single-period run
│   └── run_all_periods.jl      # Multi-period run
├── data/                       # Input datasets
│   ├── data_WECC_small_mod/    # WECC system data
│   ├── data_WECC_large/        # WECC system data (more detailed)
├── batch/                      # SLURM batch scripts
├── figure/                     # Placeholder for generated plots
├── result/                     # Raw output, one folder per scenario (see "All
│                               # Scenarios Used in This Paper" above)
├── analysis/                   # Reproduces every table and figure in the paper
│   ├── plot.ipynb              # Main reproduction notebook (see below)
│   ├── result_summary.py       # Builds result_summary.csv from result_simplified/ (see below)
│   ├── result_summary.csv      # Scenario-level summary metrics
│   └── result_simplified/      # Per-scenario data used by plot.ipynb (see below)
└── LICENSE                     # MIT License
```

## Usage

### Basic Example

Run a simple single-period simulation:

```bash
julia code/run.jl
```

This will execute a bilevel optimization for a 4-day period with default parameters (20 GW storage capacity, 4-hour duration, wind scale 3x, solar scale 3x).

### Custom Parameters

All scenario parameters are specified via the run name passed on the command line — no script editing is required to reproduce any configuration used in the paper. The run name format is:

```
b{storage_gw}_hrs{duration}_w{wind_scale}_s{solar_scale}_days{simulation_days}_ptc{production_incentive}[_eff{efficiency}][_rc{ramping_charge}]
```

| Field | Meaning | Values used in the paper |
|---|---|---|
| `b{storage_gw}` | Storage capacity, GW | 0, 20, 40 |
| `hrs{duration}` | Storage duration, hours | 4 |
| `w{wind_scale}` / `s{solar_scale}` | Wind / solar capacity multiplier | `w1s1` = 15% VRE, `w3s3` = 40%, `w5s5` = 65%, `w7s7` = 80% |
| `days{simulation_days}` | Length of each simulation window, days | 4 |
| `ptc{incentive}` | Renewable production incentive, \$/MW | 0, 5, 10 |
| `eff{efficiency}` *(optional)* | Storage one-way efficiency, % | 85, 98 (default: 95 if omitted) |
| `rc{charge}` *(optional)* | Ramping charge, \$/MW | `rc01` = 0.1, `rc05` = 0.5, `rc1` = 1.0, `rc2` = 2.0 (default: off if omitted) |

Each run produces results for both Central Control and Strategic Storage (`run_iso` and `run_bi` are both enabled by default).

Example:
```bash
julia code/run_all_periods.jl b20_hrs4_w3_s3_days4_ptc10_eff85
```
runs 20 GW storage, 4-hour duration, 40% VRE, \$10/MW incentive, 85% efficiency, default (no) ramping charge.

### Batch Processing

For running the full multi-period simulation, run directly on a local machine or submit as a batch job on an HPC cluster:

```bash
# Run directly on a local PC
julia code/run_all_periods.jl <run_name>

# Run batch scripts on HPC
cd batch
sbatch <run_name>.sh
```

### All Scenarios Used in This Paper

The table below lists every model configuration used to produce the paper's results. Each row gives the run command and the resulting output folder under `result/`. Scenarios not directly cited in a specific table or figure are marked "Supplementary" — these were run as part of the broader sensitivity analysis but are not individually referenced in the published text.

#### Table 2 & Table 4 — VRE share × renewable incentive (20 GW, 95% efficiency, no ramping charge)

| VRE share | PTC (\$/MW) | Run command | Output folder | Paper reference |
|---|---|---|---|---|
| 15% | 0 | `julia code/run_all_periods.jl b20_hrs4_w1_s1_days4_ptc0` | `tscc_all_weeks_1w_1s_20b_4hrs_0ptc_4days` | Table 4 |
| 15% | 5 | `julia code/run_all_periods.jl b20_hrs4_w1_s1_days4_ptc5` | `tscc_all_weeks_1w_1s_20b_4hrs_-5ptc_4days` | Table 4 |
| 15% | 10 | `julia code/run_all_periods.jl b20_hrs4_w1_s1_days4_ptc10` | `tscc_all_weeks_1w_1s_20b_4hrs_-10ptc_4days` | Table 4 |
| 40% | 0 | `julia code/run_all_periods.jl b20_hrs4_w3_s3_days4_ptc0` | `tscc_all_weeks_3w_3s_20b_4hrs_0ptc_4days` | Table 2, Table 4 |
| 40% | 5 | `julia code/run_all_periods.jl b20_hrs4_w3_s3_days4_ptc5` | `tscc_all_weeks_3w_3s_20b_4hrs_-5ptc_4days` | Table 4 |
| 40% | 10 | `julia code/run_all_periods.jl b20_hrs4_w3_s3_days4_ptc10` | `tscc_all_weeks_3w_3s_20b_4hrs_-10ptc_4days` | Table 2, Table 4 |
| 65% | 0 | `julia code/run_all_periods.jl b20_hrs4_w5_s5_days4_ptc0` | `tscc_all_weeks_5w_5s_20b_4hrs_0ptc_4days` | Table 4 |
| 65% | 5 | `julia code/run_all_periods.jl b20_hrs4_w5_s5_days4_ptc5` | `tscc_all_weeks_5w_5s_20b_4hrs_-5ptc_4days` | Table 4 |
| 65% | 10 | `julia code/run_all_periods.jl b20_hrs4_w5_s5_days4_ptc10` | `tscc_all_weeks_5w_5s_20b_4hrs_-10ptc_4days` | Table 4 |
| 80% | 0 | `julia code/run_all_periods.jl b20_hrs4_w7_s7_days4_ptc0` | `tscc_all_weeks_7w_7s_20b_4hrs_0ptc_4days` | Table 2, Table 4 |
| 80% | 5 | `julia code/run_all_periods.jl b20_hrs4_w7_s7_days4_ptc5` | `tscc_all_weeks_7w_7s_20b_4hrs_-5ptc_4days` | Table 4 |
| 80% | 10 | `julia code/run_all_periods.jl b20_hrs4_w7_s7_days4_ptc10` | `tscc_all_weeks_7w_7s_20b_4hrs_-10ptc_4days` | Table 2, Table 4 |

#### Table 2 — No Storage benchmark (0 GW)

| VRE share | PTC (\$/MW) | Run command | Output folder | Paper reference |
|---|---|---|---|---|
| 40% | 10 | `julia code/run_all_periods.jl b0_hrs4_w3_s3_days4_ptc10` | `tscc_all_weeks_3w_3s_0b_4hrs_-10ptc_4days` | Table 2 |
| 80% | 10 | `julia code/run_all_periods.jl b0_hrs4_w7_s7_days4_ptc10` | `tscc_all_weeks_7w_7s_0b_4hrs_-10ptc_4days` | Table 2 |

#### Table 5 — Storage capacity sensitivity (40 GW, 95% efficiency, no ramping charge)

| VRE share | PTC (\$/MW) | Run command | Output folder | Paper reference |
|---|---|---|---|---|
| 15% | 10 | `julia code/run_all_periods.jl b40_hrs4_w1_s1_days4_ptc10` | `tscc_all_weeks_1w_1s_40b_4hrs_-10ptc_4days` | Supplementary |
| 40% | 0 | `julia code/run_all_periods.jl b40_hrs4_w3_s3_days4_ptc0` | `tscc_all_weeks_3w_3s_40b_4hrs_0ptc_4days` | Table 5 |
| 40% | 10 | `julia code/run_all_periods.jl b40_hrs4_w3_s3_days4_ptc10` | `tscc_all_weeks_3w_3s_40b_4hrs_-10ptc_4days` | Table 5 |
| 65% | 0 | `julia code/run_all_periods.jl b40_hrs4_w5_s5_days4_ptc0` | `tscc_all_weeks_5w_5s_40b_4hrs_0ptc_4days` | Supplementary |
| 65% | 10 | `julia code/run_all_periods.jl b40_hrs4_w5_s5_days4_ptc10` | `tscc_all_weeks_5w_5s_40b_4hrs_-10ptc_4days` | Supplementary |
| 80% | 0 | `julia code/run_all_periods.jl b40_hrs4_w7_s7_days4_ptc0` | `tscc_all_weeks_7w_7s_40b_4hrs_0ptc_4days` | Table 5 |
| 80% | 10 | `julia code/run_all_periods.jl b40_hrs4_w7_s7_days4_ptc10` | `tscc_all_weeks_7w_7s_40b_4hrs_-10ptc_4days` | Table 5 |

#### Table 5 — Storage efficiency sensitivity (20 GW, no ramping charge)

| VRE share | PTC (\$/MW) | Efficiency | Run command | Output folder | Paper reference |
|---|---|---|---|---|---|
| 40% | 0 | 85% | `julia code/run_all_periods.jl b20_hrs4_w3_s3_days4_ptc0_eff85` | `tscc_all_weeks_3w_3s_20b_4hrs_0ptc_4days_eff85` | Supplementary |
| 40% | 0 | 98% | `julia code/run_all_periods.jl b20_hrs4_w3_s3_days4_ptc0_eff98` | `tscc_all_weeks_3w_3s_20b_4hrs_0ptc_4days_eff98` | Supplementary |
| 40% | 10 | 85% | `julia code/run_all_periods.jl b20_hrs4_w3_s3_days4_ptc10_eff85` | `tscc_all_weeks_3w_3s_20b_4hrs_-10ptc_4days_eff85` | Table 5 |
| 40% | 10 | 98% | `julia code/run_all_periods.jl b20_hrs4_w3_s3_days4_ptc10_eff98` | `tscc_all_weeks_3w_3s_20b_4hrs_-10ptc_4days_eff98` | Table 5 |
| 80% | 0 | 85% | `julia code/run_all_periods.jl b20_hrs4_w7_s7_days4_ptc0_eff85` | `tscc_all_weeks_7w_7s_20b_4hrs_0ptc_4days_eff85` | Supplementary |
| 80% | 0 | 98% | `julia code/run_all_periods.jl b20_hrs4_w7_s7_days4_ptc0_eff98` | `tscc_all_weeks_7w_7s_20b_4hrs_0ptc_4days_eff98` | Supplementary |
| 80% | 10 | 85% | `julia code/run_all_periods.jl b20_hrs4_w7_s7_days4_ptc10_eff85` | `tscc_all_weeks_7w_7s_20b_4hrs_-10ptc_4days_eff85` | Table 5 |
| 80% | 10 | 98% | `julia code/run_all_periods.jl b20_hrs4_w7_s7_days4_ptc10_eff98` | `tscc_all_weeks_7w_7s_20b_4hrs_-10ptc_4days_eff98` | Table 5 |

#### Figure 6 — Ramping charge sensitivity (20 GW, 95% efficiency)

| VRE share | PTC (\$/MW) | Ramping charge (\$/MW) | Run command | Output folder | Paper reference |
|---|---|---|---|---|---|
| 40% | 0 | 0.1 | `julia code/run_all_periods.jl b20_hrs4_w3_s3_days4_ptc0_rc01` | `tscc_all_weeks_3w_3s_20b_4hrs_0ptc_4days_rc01` | Figure 6 |
| 40% | 0 | 0.5 | `julia code/run_all_periods.jl b20_hrs4_w3_s3_days4_ptc0_rc05` | `tscc_all_weeks_3w_3s_20b_4hrs_0ptc_4days_rc05` | Figure 6 |
| 40% | 0 | 1.0 | `julia code/run_all_periods.jl b20_hrs4_w3_s3_days4_ptc0_rc1` | `tscc_all_weeks_3w_3s_20b_4hrs_0ptc_4days_rc1` | Figure 6 |
| 40% | 0 | 2.0 | `julia code/run_all_periods.jl b20_hrs4_w3_s3_days4_ptc0_rc2` | `tscc_all_weeks_3w_3s_20b_4hrs_0ptc_4days_rc2` | Figure 6 |
| 40% | 10 | 0.1 | `julia code/run_all_periods.jl b20_hrs4_w3_s3_days4_ptc10_rc01` | `tscc_all_weeks_3w_3s_20b_4hrs_-10ptc_4days_rc01` | Figure 6 |
| 40% | 10 | 0.5 | `julia code/run_all_periods.jl b20_hrs4_w3_s3_days4_ptc10_rc05` | `tscc_all_weeks_3w_3s_20b_4hrs_-10ptc_4days_rc05` | Figure 6 |
| 40% | 10 | 1.0 | `julia code/run_all_periods.jl b20_hrs4_w3_s3_days4_ptc10_rc1` | `tscc_all_weeks_3w_3s_20b_4hrs_-10ptc_4days_rc1` | Figure 6 |
| 40% | 10 | 2.0 | `julia code/run_all_periods.jl b20_hrs4_w3_s3_days4_ptc10_rc2` | `tscc_all_weeks_3w_3s_20b_4hrs_-10ptc_4days_rc2` | Figure 6 |
| 80% | 0 | 0.1 | `julia code/run_all_periods.jl b20_hrs4_w7_s7_days4_ptc0_rc01` | `tscc_all_weeks_7w_7s_20b_4hrs_0ptc_4days_rc01` | Figure 6 |
| 80% | 0 | 0.5 | `julia code/run_all_periods.jl b20_hrs4_w7_s7_days4_ptc0_rc05` | `tscc_all_weeks_7w_7s_20b_4hrs_0ptc_4days_rc05` | Figure 6 |
| 80% | 0 | 1.0 | `julia code/run_all_periods.jl b20_hrs4_w7_s7_days4_ptc0_rc1` | `tscc_all_weeks_7w_7s_20b_4hrs_0ptc_4days_rc1` | Figure 6 |
| 80% | 0 | 2.0 | `julia code/run_all_periods.jl b20_hrs4_w7_s7_days4_ptc0_rc2` | `tscc_all_weeks_7w_7s_20b_4hrs_0ptc_4days_rc2` | Figure 6 |
| 80% | 10 | 0.1 | `julia code/run_all_periods.jl b20_hrs4_w7_s7_days4_ptc10_rc01` | `tscc_all_weeks_7w_7s_20b_4hrs_-10ptc_4days_rc01` | Figure 6 |
| 80% | 10 | 0.5 | `julia code/run_all_periods.jl b20_hrs4_w7_s7_days4_ptc10_rc05` | `tscc_all_weeks_7w_7s_20b_4hrs_-10ptc_4days_rc05` | Figure 6 |
| 80% | 10 | 1.0 | `julia code/run_all_periods.jl b20_hrs4_w7_s7_days4_ptc10_rc1` | `tscc_all_weeks_7w_7s_20b_4hrs_-10ptc_4days_rc1` | Figure 6 |
| 80% | 10 | 2.0 | `julia code/run_all_periods.jl b20_hrs4_w7_s7_days4_ptc10_rc2` | `tscc_all_weeks_7w_7s_20b_4hrs_-10ptc_4days_rc2` | Figure 6 |

**Total: 45 scenarios.**

## Analysis and Figure Reproduction

`analysis/plot.ipynb` reproduces every table and figure in the paper in Python from two inputs,
both read relative to the notebook's own location:

- **`result_summary.csv`** — one row per `(folder_name, scenario_name)`, with a
  column for every scenario-level metric (system cost, storage profit,
  negative-price statistics, etc.) used across all tables and figures.
- **`result_simplified/`** — per-scenario data including `hourly_dispatch_{central,strategic}.csv` and per-period, per-generator dispatch `generation/{iso,bi}_gen_*.csv`.

### Generate result_summary.csv

`result_summary.csv` is derived from the full scenario set described above, via
`analysis/result_summary.py`. The script locates every scenario folder's
`summary_system.csv` under `result_simplified/`, reshapes each into one row
per `(folder_name, scenario_name)`, and concatenates across all scenarios.

To regenerate `result_summary.csv`:

```bash
cd analysis
python result_summary.py --root result_simplified --out result_summary.csv
```

### Running the Notebook

Install the remaining dependencies:

```bash
pip install numpy pandas plotly
```

Then open `analysis/plot.ipynb` and run it top to bottom.

A pre-rendered export, `analysis/plot.html`, is also included — open it directly in
a browser to view all generated tables and figures without running any code.

### What's In Scope

The notebook directly reproduces Table 1, Table 2, Table 4, and Table 5 (including
its storage-capacity and storage-efficiency sensitivity components), as well as
Figure 3, Figure 4, Figure 5, and Figure 6 (including its ramping-charge
sensitivity component).

Out of scope:
- **Figures 1 and 2** — conceptual/framework diagrams, not derived from model
  outputs.
- **Table 3** — lists the parameter values used in the sensitivity analysis,
  not derived from model outputs.

## Data Sources

The project uses WECC (Western Electricity Coordinating Council) system data and synthetic datasets for testing. Data includes:
- Generator parameters and costs
- Load profiles
- Variable renewable energy capacity factors
- Fuel prices

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Maintainer

**Zhenhua Zhang**  
Email: zhenhua@ucsd.edu  
Affiliation: University of California, San Diego