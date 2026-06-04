#!/bin/bash
#
#SBATCH -J b0_hrs4_w3_s3_days4_ptc10
#SBATCH --nodes=1
#SBATCH --tasks-per-node=1
#SBATCH --cpus-per-task=32
#SBATCH -t 70:00:00
#SBATCH -o out-%J-%N
#SBATCH -e err-%J-%N
#SBATCH -p condo  
#SBATCH -q condo
#SBATCH -A csd769
#SBATCH --mail-type END
#SBATCH --mail-user zhz121@ucsd.edu
#SBATCH --mem=32GB

runname="b0_hrs4_w3_s3_days4_ptc10"

echo "I am running $runname"

export MODULEPATH=/cm/shared/modulefiles:$MODULEPATH
module purge
module load slurm
module load cpu/0.17.3
module load gurobi/10.0.1

source /etc/profile.d/modules.sh

julia ../code/run_all_tscc.jl $runname

exit 0
