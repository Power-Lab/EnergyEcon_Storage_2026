# Bilevel Optimization for Energy Storage Bidding

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

This project implements a bilevel optimization model for strategic storage bidding in electricity markets. The upper level optimizes storage bidding decisions, while the lower level solves the economic dispatch problem that clears the market.

## Key Features

- **Bilevel Optimization**: Implements both convex and non-convex bilevel formulations for storage bidding
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
   git clone https://github.com/zhenhuaplus/bilevel-storage.git
   cd bilevel-storage
   ```

2. Install Julia dependencies:
   ```julia
   using Pkg
   Pkg.add(["JuMP", "Gurobi", "BilevelJuMP", "DataFrames", "CSV", "Plots", "VegaLite", "Statistics", "PrettyTables", "FileIO"])
   ```

3. Set up Gurobi license (follow Gurobi installation instructions)

## Usage

### Basic Example

Run a simple simulation:

```julia
include("code/run.jl")
```

This will execute a bilevel optimization for a 4-day period with default parameters (20 GW storage capacity, 4-hour duration, wind scale 3x, solar scale 3x).

### Batch Processing

For running multiple periods, use the batch scripts:

```bash
# Run a specific scenario
sbatch batch/b20_hrs4_w3_s3_days4_ptc0.sh

# Or run directly with Julia
julia code/run_all_tscc.jl b20_hrs4_w3_s3_days4_ptc0
```

The run name format is: `b{storage_gw}_hrs{duration}_w{wind_scale}_s{solar_scale}_days{simulation_days}_ptc{production_incentive}`

### Custom Parameters

Modify parameters in `code/run.jl` or `code/run_all_tscc.jl`:

- `storage_cap_gw`: Storage capacity in GW
- `storage_duration`: Storage duration in hours
- `wind_cap_scale`: Wind capacity multiplier
- `solar_cap_scale`: Solar capacity multiplier
- `ra_scenario`: Resource adequacy constraint ("baseline", "min_soc", "penalty")
- `ramping_charge_scenario`: Ramping charge cost scenario

## Project Structure

```
├── code/                       # Julia source code
│   ├── bilevel_cvx.jl          # Convex bilevel formulation
│   ├── ed.jl                   # Economic dispatch model
│   └── run.jl                  # Single period run
│   └── run_all_tscc.jl         # HPC run for multiple periods
│   └── run_all_pc.jl           # Local run for multiple periods
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