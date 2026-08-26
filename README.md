# Bilevel Optimization for Energy Storage Bidding

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

This project implements a bilevel optimization model for strategic storage bidding in electricity markets. The upper level optimizes storage bidding decisions, while the lower level solves the economic dispatch problem that clears the market.

## Key Features

- **Bilevel Optimization**: Implements convex bilevel formulation for storage bidding
- **Economic Dispatch**: Solves lower-level market clearing with variable renewable energy (VRE) integration
- **Storage Modeling**: Supports configurable storage capacity, duration, and efficiency parameters
- **Scalable Scenarios**: Supports different VRE penetration levels, storage capacities, and other sensitivity factors
- **Batch Processing**: Includes scripts for running multiple scenarios on HPC clusters

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

## Usage

### Basic Example

Run a simple single-period simulation:

```
julia code/run.jl
```

This will execute a bilevel optimization for a 4-day period with default parameters (20 GW storage capacity, 4-hour duration, wind scale 3x, solar scale 3x).

### Batch Processing

For running multiple periods, use the batch scripts or directly run on a local PC:

```bash
# Run directly on a local PC
julia code/run_all_periods.jl b20_hrs4_w3_s3_days4_ptc10

# Run batch scripts on HPC
cd batch
sbatch b20_hrs4_w3_s3_days4_ptc10.sh
```

The run name format is: `b{storage_gw}_hrs{duration}_w{wind_scale}_s{solar_scale}_days{simulation_days}_ptc{production_incentive}`. For example, the table below shows the key run names:

| VRE share | Storage capacity | PTC ($/MW) | Run name |
|---|---|---|---|
| 40% | 20 GW | 0 | `b20_hrs4_w3_s3_days4_ptc0` |
| 40% | 20 GW | 10 | `b20_hrs4_w3_s3_days4_ptc10` |
| 80% | 20 GW | 0 | `b20_hrs4_w7_s7_days4_ptc0` |
| 80% | 20 GW | 10 | `b20_hrs4_w7_s7_days4_ptc10` |
| 40% | 40 GW | 10 | `b40_hrs4_w3_s3_days4_ptc10` |

### Custom Parameters

Modify key parameters in `code/run_all_periods.jl`:

- `storage_cap_gw`: Storage capacity in GW
- `storage_duration`: Storage duration in hours
- `one_way_efficiency`: Storage one-way efficiency
- `wind_cap_scale`: Wind capacity multiplier
- `solar_cap_scale`: Solar capacity multiplier
- `ramping_charge_scenario`: Ramping charge cost scenario
- `ramping_charge`: Storage ramping charge cost
- `bidding_ptc`: Renewable production tax incentive in $/MW

## Project Structure

```
├── code/                       # Julia source code
│   ├── bilevel_cvx.jl          # Strategic Storage: convex bilevel formulation
│   ├── ed.jl                   # Central Control: economic dispatch model
│   └── run.jl                  # Single-period run
│   └── run_all_periods.jl      # Multi-period run
├── data/                       # Input datasets
│   ├── data_WECC_small_mod/    # WECC system data
│   ├── data_WECC_large/        # WECC system data (more detailed)
├── batch/                      # SLURM batch scripts
├── figure/                     # Output figures
├── result/                     # Output results
└── LICENSE                     # MIT License
```

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