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
include("bilevel_cvx_dr.jl")

ENV["COLUMNS"]=120; # Set so all c?olumns of DataFrames and Matrices are displayed
ENV["ROWS"]=30; # Set so all columns of DataFrames and Matrices are displayed

# Define storage parameters
storage_cap_mw = 80000
storage_cap_gw = Int(storage_cap_mw / 1000)
storage_duration = 4
one_way_efficiency = 0.95
start_soc = 0

# Define resource adequacy parameters
ra_scenario = ["baseline", "min_soc", "penalty"][1]
ra_penalty_cost = 20
ra_min_soc = 0.25;

# Set VRE/firm parameters
wind_cap_scale = 8
solar_cap_scale = 4
gas_cap_scale = 1

# Select a subset of the data files based on period
for week_number in 2:2
    week_number = week_number # weel 1, week 30/32
    simulation_days = 4
    T_period = 1:(24 * simulation_days)
    T_period_days = (week_number * 7 * 24 - 24 + 1):(week_number * 7 * 24 - 24 + 24 * simulation_days)

    # Set simulation parameters
    result_name = string("run-jl_test_", week_number, "week_", wind_cap_scale, "w_", solar_cap_scale, "s_" , storage_cap_gw, "b_", simulation_days, "days")

    # Load and format data
    datadir = joinpath(@__DIR__, "..", "data/data_WECC_very_small")
    # datadir = joinpath(@__DIR__, "..", "data/data_WECC_small_mod")
    gen_info = CSV.read(joinpath(datadir,"Generators_data.csv"), DataFrame);
    fuels = CSV.read(joinpath(datadir,"Fuels_data.csv"), DataFrame);
    loads = CSV.read(joinpath(datadir,"Demand.csv"), DataFrame);
    gen_variable = CSV.read(joinpath(datadir,"Generators_variability.csv"), DataFrame);

    # Rename all columns to lowercase
    for f in [gen_info, fuels, loads, gen_variable]
        rename!(f,lowercase.(names(f)))
    end

    # Keep only the relevant columns
    # select!(gen_info, 1:26, :stor) 
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

    # Run ED
    # Obtain the single-level ISO-control-case results
    self_schedule=false
    storage_quantity=nothing
    discharge_bin_fixed=false
    discharge_bin=nothing
    solution_ed = ed_bin(
        gen_df, loads, gen_variable, self_schedule, storage_quantity, discharge_bin_fixed, discharge_bin);

    # Print capacity mix
    grouped_gen_df = groupby(gen_df, :resource)
    grouped_gen_df = combine(grouped_gen_df, [:existing_cap_mw] .=> sum; renamecols=false)
    print(grouped_gen_df)

    # Plot generation mix
    result_folder_name = joinpath(@__DIR__, "..", "result", result_name)
    mkpath(result_folder_name)
    f1 = solution_ed.solution_gen_df |>
        @vlplot(:area,
        width=1200, height=500,
        x=:hour, y={:gen_sum, stack=:zero},
        color={"resource:n", scale={scheme="category10"}})
    f1 |> save(joinpath(result_folder_name, "iso_gen_mix.pdf"))

    # Plot storage behaviors
    f2 = solution_ed.solution_gen_df[(solution_ed.solution_gen_df.resource .== "PHS_charge") .| (solution_ed.solution_gen_df.resource .== "PHS_discharge"), :] |>
        @vlplot(:bar,
        width=600, height=300,
        x=:hour, y=:gen_sum,
        color={"resource:n", scale={scheme="category10"}})
    f2 |> save(joinpath(result_folder_name, "iso_storage.pdf"))

    f3 = solution_ed.price_df |>
        @vlplot(:line,
        width=600, height=300,
        x=:hour, y=:price)
    f3 |> save(joinpath(result_folder_name, "iso_price.pdf"))

    # Save iso-control operational results
    df_to_save = DataFrame(hour=Array(T_period))
    df_to_save.charge_power = solution_ed.solution_gen_df[(solution_ed.solution_gen_df.resource .== "PHS_charge"), :].gen_sum
    df_to_save.discharge_power = solution_ed.solution_gen_df[(solution_ed.solution_gen_df.resource .== "PHS_discharge"), :].gen_sum
    df_to_save.power = df_to_save.discharge_power - df_to_save.charge_power
    df_to_save.soc = solution_ed.solution_gen_df[(solution_ed.solution_gen_df.resource .== "PHS_SOC"), :].gen_sum
    df_to_save.demand = loads.demand
    df_to_save.price = solution_ed.price_df.price
    df_to_save.wind_gen_max = solution_ed.vre_df.wind_gen_max
    df_to_save.solar_gen_max = solution_ed.vre_df.solar_gen_max
    CSV.write(
        joinpath(result_folder_name, "df_iso.csv"), df_to_save, writeheader=true)

    # Run MILP Bilevel
    solution_sbed_cvx = sbed_cvx(gen_df, loads, gen_variable);

    # Plot generation mix
    f4 = solution_sbed_cvx.solution_gen_df |>
        @vlplot(:area,
        width=1200, height=500,
        x=:hour, y={:gen_sum, stack=:zero},
        color={"resource:n", scale={scheme="category10"}})
    f4 |> save(joinpath(result_folder_name, "bi_gen_mix.pdf"))

    # Plot storage cleared quantity
    storage_df = solution_sbed_cvx.storage_cleared
    f5 = storage_df[(storage_df.resource .== "PHS_charge") .| (storage_df.resource .== "PHS_discharge"), :] |>
    @vlplot(:bar,
        width=600, height=300,
        x=:hour, y={field=:gen_sum, title="Power Ratio (% of Max Power)"},
        color={"resource:n", scale={scheme="category10"}})
    f5 |> save(joinpath(result_folder_name, "bi_storage.pdf"))

    f6 = solution_sbed_cvx.price_df |>
        @vlplot(:line,
        width=600, height=300,
        x=:hour, y={field=:price, title="Price (\$/MWh)"},)
    f6 |> save(joinpath(result_folder_name, "bi_price.pdf"))

    # Plot storage soc
    storage_df = solution_sbed_cvx.storage_cleared
    f7 = storage_df[storage_df.resource .== "PHS_SOC", :] |>
    @vlplot(:line,
        width=600, height=300,
        x=:hour, y={field=:gen_sum, title="State of Energy (MWh)"},
        color={"resource:n", scale={scheme="category10"}})
    f7 |> save(joinpath(result_folder_name, "bi_soc.pdf"))

    # Save bi-level operational results
    df_to_save = DataFrame(hour=Array(T_period))
    df_to_save.charge_power = solution_sbed_cvx.solution_gen_df[(solution_sbed_cvx.solution_gen_df.resource .== "PHS_charge"), :].gen_sum
    df_to_save.discharge_power = solution_sbed_cvx.solution_gen_df[(solution_sbed_cvx.solution_gen_df.resource .== "PHS_discharge"), :].gen_sum
    df_to_save.power = df_to_save.discharge_power - df_to_save.charge_power
    df_to_save.soc = solution_sbed_cvx.storage_cleared[(solution_sbed_cvx.storage_cleared.resource .== "PHS_SOC"), :].gen_sum
    df_to_save.demand = loads.demand
    df_to_save.price = solution_sbed_cvx.price_df.price
    df_to_save.discharge_price_offer = solution_sbed_cvx.price_df.discharge_price_offer
    df_to_save.charge_price_offer = solution_sbed_cvx.price_df.charge_price_offer
    CSV.write(
        joinpath(result_folder_name, "df_bi.csv"), df_to_save, writeheader=true)

    # Run MILP Bilevel with DR
    solution_sbed_cvx_dr = sbed_cvx_dr(gen_df, loads, gen_variable);

    # Plot generation mix
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
    df_to_save = DataFrame(hour=Array(T_period))
    df_to_save.charge_power = solution_sbed_cvx_dr.solution_gen_df[(solution_sbed_cvx_dr.solution_gen_df.resource .== "PHS_charge"), :].gen_sum
    df_to_save.discharge_power = solution_sbed_cvx_dr.solution_gen_df[(solution_sbed_cvx_dr.solution_gen_df.resource .== "PHS_discharge"), :].gen_sum
    df_to_save.power = df_to_save.discharge_power - df_to_save.charge_power
    df_to_save.soc = solution_sbed_cvx_dr.storage_cleared[(solution_sbed_cvx_dr.storage_cleared.resource .== "PHS_SOC"), :].gen_sum
    df_to_save.demand = loads.demand
    df_to_save.price = solution_sbed_cvx_dr.price_df.price
    df_to_save.discharge_price_offer = solution_sbed_cvx_dr.price_df.discharge_price_offer
    df_to_save.charge_price_offer = solution_sbed_cvx_dr.price_df.charge_price_offer
    df_to_save.dr = solution_sbed_cvx_dr.dr_df.dr
    CSV.write(
        joinpath(result_folder_name, "df_bi_dr.csv"), df_to_save, writeheader=true)

    # Save key metrics
    summary = DataFrame()
    summary.result_vars = ["result_name", "simulation_days", "week_number", "storage_duration", 
        "ra_scenario", "storage_cap_gw", "onshore_wind_gw", "solar_gw"]
    summary.result_params = [result_name, simulation_days, week_number, storage_duration, 
        ra_scenario, storage_cap_mw / 1000,
        sum(gen_df[gen_df.resource .== "onshore_wind_turbine", :existing_cap_mw]) / 1000, 
        sum(gen_df[gen_df.resource .== "solar_photovoltaic", :existing_cap_mw]) / 1000
        ]
    summary.scenario_name = ["iso-control", "bi-level", "bi-level-dr", 0, 0, 0, 0, 0]
    summary.system_cost = [solution_ed.system_cost, solution_sbed_cvx.system_cost, solution_sbed_cvx_dr.system_cost, 0, 0, 0, 0, 0]
    summary.storage_profit = [solution_ed.storage_profit, solution_sbed_cvx.storage_profit, solution_sbed_cvx_dr.storage_profit, 0, 0, 0, 0, 0]
    summary.average_price = [Statistics.mean(solution_ed.price_df.price), Statistics.mean(solution_sbed_cvx.price_df.price), Statistics.mean(solution_sbed_cvx_dr.price_df.price), 0, 0, 0, 0, 0]
    CSV.write(
        joinpath(result_folder_name, "summary.csv"), summary, writeheader=true)

end
