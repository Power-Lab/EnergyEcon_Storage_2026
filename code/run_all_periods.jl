# Load packages
using JuMP, HiGHS
using Gurobi
using Plots;
using VegaLite
using Statistics
using DataFrames, CSV, PrettyTables
using FileIO
using BilevelJuMP

# Load functions
include("ed.jl")
include("ed_bin.jl")
include("bilevel_cvx.jl")

ENV["COLUMNS"]=120; # Set so all c?olumns of DataFrames and Matrices are displayed
ENV["ROWS"]=30; # Set so all columns of DataFrames and Matrices are displayed

# Read run name
runname = ARGS[1]
actfilename = split(runname, "_")

# Define storage parameters
storage_cap_gw = parse(Int64, actfilename[1][2:end])
storage_cap_mw = Int(storage_cap_gw * 1000)
storage_duration = parse(Int64, actfilename[2][4:end])
one_way_efficiency = 0.95
start_soc = 0

# Define resource adequacy parameters
ra_scenario = ["baseline", "min_soc", "penalty"][1]
ra_penalty_cost = 20
ra_min_soc = 0.25;

# Set ramping charge parameters
ramping_charge_scenario = false
ramping_charge = 0.1 # $/MWh

# Set VRE/firm parameters
wind_cap_scale = parse(Int64, actfilename[3][2:end])
solar_cap_scale = parse(Int64, actfilename[4][2:end])
gas_cap_scale = 1
bidding_ptc = - parse(Int64, actfilename[6][4:end])  # $/MWh

# Initialize dataframes
df_to_save_iso = DataFrame()
df_to_save_bi = DataFrame()
df_to_save_bi_dr = DataFrame()
params = DataFrame()
summary = DataFrame()

# Set simulation parameters
simulation_days = parse(Int64, actfilename[5][5:end])
run_iso = true
run_bi = true
run_bi_dr = false
result_name = string("tscc_", "all_weeks_", wind_cap_scale, "w_", solar_cap_scale, "s_" , 
    storage_cap_gw, "b_", storage_duration, "hrs_", bidding_ptc, "ptc_", simulation_days, "days")
result_folder_name = joinpath(@__DIR__, "..", "result", result_name)
result_gen_folder_name = joinpath(@__DIR__, "..", "result", result_name, "generation")
figure_folder_name = joinpath(@__DIR__, "..", "result", result_name, "figure")
mkpath(result_folder_name)
mkpath(result_gen_folder_name)
mkpath(figure_folder_name)    

# Select a subset of the data files based on period
for period_number in 1:90
    try
        period_number = period_number # weel 1, week 30/32
        T_period = 1:(24 * simulation_days)
        T_period_days = ((period_number - 1) * 24 * simulation_days + 1):(period_number * 24 * simulation_days)

        # Load and format data
        datadir = joinpath(@__DIR__, "..", "data/data_WECC_small_mod")
        gen_info = CSV.read(joinpath(datadir,"Generators_data.csv"), DataFrame);
        fuels = CSV.read(joinpath(datadir,"Fuels_data.csv"), DataFrame);
        loads = CSV.read(joinpath(datadir,"Demand.csv"), DataFrame);
        gen_variable = CSV.read(joinpath(datadir,"Generators_variability.csv"), DataFrame);

        # Rename all columns to lowercase
        for f in [gen_info, fuels, loads, gen_variable]
            rename!(f,lowercase.(names(f)))
        end

        # Keep only the relevant columns
        gen_df = leftjoin(gen_info,  fuels, on = :fuel)
        rename!(gen_df, :cost_per_mmbtu => :fuel_cost)
        gen_df[ismissing.(gen_df[:,:fuel_cost]), :fuel_cost] .= 0;

        if datadir == "data_hw3"
            # Process gen data for the HW3 dataset
            # Create "is_variable" column to indicate if this is a VRE (only for hw3 data)
            gen_df[!, :is_variable] .= false
            gen_df[in(["onshore_wind_turbine","small_hydroelectric","solar_photovoltaic"]).(gen_df.resource), :is_variable] .= true;
            # Create "is_storage" column to indicate if this is a storage unit (only for hw3 data)
            gen_df[!, :is_storage] .= false
            gen_df[in(["hydroelectric_pumped_storage"]).(gen_df.resource), :is_storage] .= true
            # Create full name of generator (only for hw3 data)
            gen_df.gen_full = lowercase.(gen_df.region .* "_" .* gen_df.resource .* "_" .* string.(gen_df.cluster) .* ".0");
        else
            # Process gen data for the WECC dataset
            # Convert from GMT to GMT-8
            gen_variable.hour = gen_variable.hour_0 .+ 1
            select!(gen_variable, Not([:hour_0]))
            gen_variable.hour = mod.(gen_variable.hour .- 9, 8760) .+ 1 
            sort!(gen_variable, :hour)
            loads.hour = mod.(loads.hour .- 9, 8760) .+ 1
            sort!(loads, :hour);
            # Select only the subperiod
            gen_variable = gen_variable[T_period_days, :]
            gen_variable.hour = T_period
            loads = loads[T_period_days, :]
            loads.hour = T_period
            # Create additional dataframes
            gen_df[!, :is_variable] .= 1.0 .- (1.0 .- gen_df[!, :vre]) .* (1.0 .- gen_df[!, :hydro])
            gen_df[!, :is_storage] .= gen_df[!, :stor]
            gen_df.resource .= lowercase.(replace.(gen_df.technology, " " => "_"))
            gen_df.gen_full = lowercase.(gen_df.resource .* "_" .* string.(gen_df.r_id));
        end
            
        # Remove generators with no capacity
        gen_df = gen_df[gen_df.existing_cap_mw .> 0,:];

        # Define generator sets
        G_var = gen_df[gen_df[!,:is_variable] .== 1, :r_id] 
        G_nonvar = gen_df[(gen_df[!,:is_variable] .== 0) .& (gen_df[!,:is_storage] .== 0), :r_id]
        G_stor = gen_df[gen_df[!,:is_storage] .== 1, :r_id][1:1]
        G = gen_df[gen_df[!,:is_storage] .== 0, :r_id]

        # Define time period sets
        T = loads.hour
        T_red = loads.hour[1:end-1]
        T_peak = [if (mod(h, 18) .== 0) .| (mod(h, 19) .== 0) .| (mod(h, 20) .== 0) .| (mod(h, 21) .== 0)  
                h end for h in loads.hour]
        T_peak = T_peak[T_peak .!= nothing];

        # WECC data sensitivity: storage
        gen_df[gen_df.r_id .== G_stor, :existing_cap_mw] .= storage_cap_mw

        # WECC data sensitivity: firm resources and VRE
        gen_df[gen_df.fuel .== "pacific_naturalgas", :existing_cap_mw] .= 
            gen_df[gen_df.fuel .== "pacific_naturalgas", :existing_cap_mw] .* gas_cap_scale
        gen_df[gen_df.resource .== "onshore_wind_turbine", :existing_cap_mw] .= 
            gen_df[gen_df.resource .== "onshore_wind_turbine", :existing_cap_mw] .* wind_cap_scale
        gen_df[gen_df.resource .== "solar_photovoltaic", :existing_cap_mw] .= 
            gen_df[gen_df.resource .== "solar_photovoltaic", :existing_cap_mw] .* solar_cap_scale

        # What if VRE bids into the market with PTC (negative prices)
        gen_df[in(["onshore_wind_turbine","solar_photovoltaic"]).(gen_df.resource), :var_om_cost_per_mwh] .= bidding_ptc

        # Print capacity mix
        grouped_gen_df = groupby(gen_df, :resource)
        grouped_gen_df = combine(grouped_gen_df, [:existing_cap_mw] .=> sum; renamecols=false)
        replace!(grouped_gen_df.resource, "hydroelectric_pumped_storage" => "storage")
        print(grouped_gen_df)
        CSV.write(joinpath(result_folder_name, "params_cap_mix.csv"), grouped_gen_df, writeheader=true)

        # Run ED
        if run_iso
            # Update start SOC
            if nrow(df_to_save_iso) != 0
                start_soc = last(df_to_save_iso.soc)
                # start_soc = 0
            end

            # Obtain the single-level ISO-control-case results
            self_schedule=false
            storage_quantity=nothing
            discharge_bin_fixed=false
            discharge_bin=nothing
            solution_ed_intermediate = ed_bin(gen_df, loads, gen_variable, self_schedule, storage_quantity, discharge_bin_fixed, discharge_bin);
            discharge_bin_fixed=true
            discharge_bin=solution_ed_intermediate.discharge_bin_df.discharge_bin
            solution_ed = ed_bin(gen_df, loads, gen_variable, self_schedule, storage_quantity, discharge_bin_fixed, discharge_bin);

            # Plot generation mix
            pivoted_gen_df = unstack(solution_ed.solution_gen_df, :hour, :resource, :gen_sum)
            f1 = solution_ed.solution_gen_df[solution_ed.solution_gen_df.resource .!= "PHS_SOC", :] |>
                @vlplot(:area,
                width=1200, height=500,
                x=:hour, y={:gen_sum, stack=:zero},
                color={"resource:n", scale={scheme="category10"}})
            f1 |> save(joinpath(figure_folder_name, "iso_gen_mix_$period_number.pdf"))

            # Plot storage behaviors
            f2 = solution_ed.solution_gen_df[(solution_ed.solution_gen_df.resource .== "PHS_charge") .| (solution_ed.solution_gen_df.resource .== "PHS_discharge"), :] |>
                @vlplot(:bar,
                width=600, height=300,
                x=:hour, y=:gen_sum,
                color={"resource:n", scale={scheme="category10"}})
            f2 |> save(joinpath(figure_folder_name, "iso_storage_$period_number.pdf"))

            f3 = solution_ed.price_df |>
                @vlplot(:line,
                width=600, height=300,
                x=:hour, y=:price)
            f3 |> save(joinpath(figure_folder_name, "iso_price_$period_number.pdf"))

            # Save iso-control operational results
            df_to_save = DataFrame(hour=Array(T_period_days))
            df_to_save.hour_simulation = T_period
            df_to_save.demand = loads.demand
            df_to_save.wind_gen_max = solution_ed.vre_df.wind_gen_max
            df_to_save.solar_gen_max = solution_ed.vre_df.solar_gen_max
            df_to_save = hcat(df_to_save, select!(pivoted_gen_df, Not(:hour)))
            rename!(df_to_save, [:PHS_charge => :charge_power, :PHS_discharge => :discharge_power, :PHS_SOC => :soc])
            df_to_save.power = df_to_save.discharge_power - df_to_save.charge_power
            df_to_save.net_demand = df_to_save.demand - df_to_save._onshore_wind_turbine - df_to_save._solar_photovoltaic
            df_to_save.price = solution_ed.price_df.price
            df_to_save.discharge_status = solution_ed.discharge_bin_df.discharge_bin
            append!(df_to_save_iso, df_to_save)

            # Save iso-control generation results
            CSV.write(joinpath(result_gen_folder_name, "iso_gen_$period_number.csv"), solution_ed.solution_gen_df_ungrouped, writeheader=true)
        end

        # Run MILP Bilevel
        if run_bi
            # Update start SOC
            if nrow(df_to_save_bi) != 0
                start_soc = last(df_to_save_bi.soc)
                # start_soc = 0
            end

            solution_sbed_cvx = sbed_cvx(gen_df, loads, gen_variable);

            # Plot generation mix
            pivoted_gen_df = unstack(solution_sbed_cvx.solution_gen_df, :hour, :resource, :gen_sum)
            f4 = solution_sbed_cvx.solution_gen_df[solution_sbed_cvx.solution_gen_df.resource .!= "PHS_SOC", :] |>
                @vlplot(:area,
                width=1200, height=500,
                x=:hour, y={:gen_sum, stack=:zero},
                color={"resource:n", scale={scheme="category10"}})
            f4 |> save(joinpath(figure_folder_name, "bi_gen_mix_$period_number.pdf"))

            # Plot storage cleared quantity
            storage_df = solution_sbed_cvx.storage_cleared
            f5 = storage_df[(storage_df.resource .== "PHS_charge") .| (storage_df.resource .== "PHS_discharge"), :] |>
            @vlplot(:bar,
                width=600, height=300,
                x=:hour, y={field=:gen_sum, title="Power Ratio (% of Max Power)"},
                color={"resource:n", scale={scheme="category10"}})
            f5 |> save(joinpath(figure_folder_name, "bi_storage_$period_number.pdf"))

            f6 = solution_sbed_cvx.price_df |>
                @vlplot(:line,
                width=600, height=300,
                x=:hour, y={field=:price, title="Price (\$/MWh)"},)
            f6 |> save(joinpath(figure_folder_name, "bi_price_$period_number.pdf"))

            # Plot storage soc
            storage_df = solution_sbed_cvx.storage_cleared
            f7 = storage_df[storage_df.resource .== "PHS_SOC", :] |>
            @vlplot(:line,
                width=600, height=300,
                x=:hour, y={field=:gen_sum, title="State of Energy (MWh)"},
                color={"resource:n", scale={scheme="category10"}})
            f7 |> save(joinpath(figure_folder_name, "bi_soc_$period_number.pdf"))

            # Save bi-level operational results
            df_to_save = DataFrame(hour=Array(T_period_days))
            df_to_save.hour_simulation = T_period
            df_to_save.demand = loads.demand
            df_to_save.wind_gen_max = solution_sbed_cvx.vre_df.wind_gen_max
            df_to_save.solar_gen_max = solution_sbed_cvx.vre_df.solar_gen_max
            df_to_save = hcat(df_to_save, select!(pivoted_gen_df, Not(:hour)))
            rename!(df_to_save, [:PHS_charge => :charge_power, :PHS_discharge => :discharge_power])
            df_to_save.soc = solution_sbed_cvx.storage_cleared[(solution_sbed_cvx.storage_cleared.resource .== "PHS_SOC"), :].gen_sum
            df_to_save.power = df_to_save.discharge_power - df_to_save.charge_power
            df_to_save.net_demand = df_to_save.demand - df_to_save._onshore_wind_turbine - df_to_save._solar_photovoltaic
            df_to_save.price = solution_sbed_cvx.price_df.price
            df_to_save.discharge_price_offer = solution_sbed_cvx.price_df.discharge_price_offer
            df_to_save.charge_price_offer = solution_sbed_cvx.price_df.charge_price_offer
            append!(df_to_save_bi, df_to_save)

            # Save bi-level generation results
            CSV.write(joinpath(result_gen_folder_name, "bi_gen_$period_number.csv"), solution_sbed_cvx.solution_gen_df_ungrouped, writeheader=true)
        end

        # Run MILP Bilevel with DR
        if run_bi_dr
            solution_sbed_cvx_dr = sbed_cvx_dr(gen_df, loads, gen_variable);

            # Plot generation mix
            pivoted_gen_df = unstack(solution_sbed_cvx_dr.solution_gen_df, :hour, :resource, :gen_sum)
            f8 = solution_sbed_cvx_dr.solution_gen_df |>
                @vlplot(:area,
                width=1200, height=500,
                x=:hour, y={:gen_sum, stack=:zero},
                color={"resource:n", scale={scheme="category10"}})
            f8 |> save(joinpath(result_folder_name, "bi_dr_gen_mix.pdf"))

            # Plot storage cleared quantity
            storage_df = solution_sbed_cvx_dr.storage_cleared
            f9 = storage_df[(storage_df.resource .== "PHS_charge") .| (storage_df.resource .== "PHS_discharge"), :] |>
            @vlplot(:bar,
                width=600, height=300,
                x=:hour, y={field=:gen_sum, title="Power Ratio (% of Max Power)"},
                color={"resource:n", scale={scheme="category10"}})
            f9 |> save(joinpath(result_folder_name, "bi_dr_storage.pdf"))

            f10 = solution_sbed_cvx_dr.price_df |>
                @vlplot(:line,
                width=600, height=300,
                x=:hour, y={field=:price, title="Price (\$/MWh)"},)
            f10 |> save(joinpath(result_folder_name, "bi_dr_price.pdf"))

            # Plot storage soc
            storage_df = solution_sbed_cvx_dr.storage_cleared
            f11 = storage_df[storage_df.resource .== "PHS_SOC", :] |>
            @vlplot(:line,
                width=600, height=300,
                x=:hour, y={field=:gen_sum, title="State of Energy (MWh)"},
                color={"resource:n", scale={scheme="category10"}})
            f11 |> save(joinpath(result_folder_name, "bi_dr_soc.pdf"))

            # Save bi-level operational results
            df_to_save = DataFrame(hour=Array(T_period_days))
            df_to_save.hour_simulation = T_period
            df_to_save.demand = loads.demand
            df_to_save = hcat(df_to_save, select!(pivoted_gen_df, Not(:hour)))
            rename!(df_to_save, [:PHS_charge => :charge_power, :PHS_discharge => :discharge_power])
            df_to_save.net_demand = df_to_save.demand - df_to_save._onshore_wind_turbine - 
                df_to_save._small_hydroelectric - df_to_save._solar_photovoltaic
            df_to_save.power = df_to_save.discharge_power - df_to_save.charge_power
            df_to_save.soc = solution_sbed_cvx_dr.storage_cleared[(solution_sbed_cvx_dr.storage_cleared.resource .== "PHS_SOC"), :].gen_sum
            df_to_save.price = solution_sbed_cvx_dr.price_df.price
            df_to_save.discharge_price_offer = solution_sbed_cvx_dr.price_df.discharge_price_offer
            df_to_save.charge_price_offer = solution_sbed_cvx_dr.price_df.charge_price_offer
            df_to_save.dr = solution_sbed_cvx_dr.dr_df.dr
            append!(df_to_save_bi_dr, df_to_save)
        end

        # Save key metrics
        params.result_vars = ["result_name", "simulation_days", "period_count", "storage_duration", 
            "ra_scenario", "storage_cap_gw", "onshore_wind_gw", "solar_gw", "bidding_ptc"]
        params.result_params = [result_name, simulation_days, period_number, storage_duration, 
            ra_scenario, storage_cap_mw / 1000,
            sum(gen_df[gen_df.resource .== "onshore_wind_turbine", :existing_cap_mw]) / 1000, 
            sum(gen_df[gen_df.resource .== "solar_photovoltaic", :existing_cap_mw]) / 1000,
            bidding_ptc
            ]

        if run_iso
            summary_one_run = DataFrame()
            summary_one_run.period_number = [period_number]
            summary_one_run.scenario_name = ["iso-control"]
            summary_one_run.status = [solution_ed.status]
            summary_one_run.mip_gap = [0.0]
            summary_one_run.system_cost = [solution_ed.system_cost]
            summary_one_run.storage_profit = [solution_ed.storage_profit]
            summary_one_run.ramping_charge_total = [0.0]
            summary_one_run.average_price = [Statistics.mean(solution_ed.price_df.price)]
            append!(summary, summary_one_run)
        end
        if run_bi
            summary_one_run = DataFrame()
            summary_one_run.period_number = [period_number]
            summary_one_run.scenario_name = ["bi-level"]
            summary_one_run.status = [solution_sbed_cvx.status]
            summary_one_run.mip_gap = [solution_sbed_cvx.mip_gap]
            summary_one_run.system_cost = [solution_sbed_cvx.system_cost]
            summary_one_run.storage_profit = [solution_sbed_cvx.storage_profit]
            summary_one_run.ramping_charge_total = [solution_sbed_cvx.ramping_charge_total]
            summary_one_run.average_price = [Statistics.mean(solution_sbed_cvx.price_df.price)]
            append!(summary, summary_one_run)
        end
        if run_bi_dr
            summary_one_run = DataFrame()
            summary_one_run.period_number = [period_number]
            summary_one_run.scenario_name = ["bi-level-dr"]
            summary_one_run.system_cost = [solution_sbed_cvx_dr.system_cost]
            summary_one_run.storage_profit = [solution_sbed_cvx_dr.storage_profit]
            summary_one_run.ramping_charge_total = [0.0]
            summary_one_run.average_price = [Statistics.mean(solution_sbed_cvx_dr.price_df.price)]
            append!(summary, summary_one_run)
        end
        
    catch
        println(string("Infeasible: ", "period", period_number))
    end

    # Save operational results
    CSV.write(joinpath(result_folder_name, "df_iso_all.csv"), df_to_save_iso, writeheader=true)
    CSV.write(joinpath(result_folder_name, "df_bi_all.csv"), df_to_save_bi, writeheader=true)
    CSV.write(joinpath(result_folder_name, "params.csv"), params, writeheader=true)
    CSV.write(joinpath(result_folder_name, "summary.csv"), summary, writeheader=true)

    # ============================================================
    # Post-processing
    # ============================================================
    println("Post-processing: ", result_folder_name)

    # (1) Remove the 'generation' folder
    if isdir(result_gen_folder_name)
        rm(result_gen_folder_name; recursive=true, force=true)
        println("  - Deleted 'generation' folder")
    end

    # (2) & (3) Rename CSV files
    renames = Dict(
        "df_bi_all.csv" => "hourly_dispatch_strategic.csv",
        "df_iso_all.csv" => "hourly_dispatch_central.csv"
    )
    for (old_name, new_name) in renames
        old_file_path = joinpath(result_folder_name, old_name)
        new_file_path = joinpath(result_folder_name, new_name)
        if isfile(old_file_path)
            mv(old_file_path, new_file_path; force=true)
            println("  - Renamed $old_name to $new_name")
        end
    end

    # (4) Update params_cap_mix.csv (resource names should already be updated upstream;
    #     kept here for parity in case that changes)
    params_cap_mix_path = joinpath(result_folder_name, "params_cap_mix.csv")
    if isfile(params_cap_mix_path)
        try
            df_cap_mix = CSV.read(params_cap_mix_path, DataFrame)
            if "resource" in names(df_cap_mix)
                replace!(df_cap_mix.resource, "hydroelectric_pumped_storage" => "storage")
                CSV.write(params_cap_mix_path, df_cap_mix, writeheader=true)
                println("  - Updated resource names in params_cap_mix.csv")
            end
        catch e
            println("  - Error processing CSV in $result_folder_name: $e")
        end
    end

    # (5) Rename summary.csv to summary_weekly.csv
    summary_old_path = joinpath(result_folder_name, "summary.csv")
    summary_new_path = joinpath(result_folder_name, "summary_weekly.csv")
    if isfile(summary_old_path)
        mv(summary_old_path, summary_new_path; force=true)
        println("  - Renamed summary.csv to summary_weekly.csv")
    end

end
