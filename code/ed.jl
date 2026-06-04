#=
An Economic Dispatch model with the option to include storage self-scheduling bids
Inputs:
    gen_df            dataframe with generator info
    loads             load by time
    gen_variable      capacity factors of variable generators in "wide" format
    self_schedule     (optional, default is FALSE) if storage is self-scheduling
    storage_quantity  (optional) storage self-scheduling bids
=#

function ed(gen_df, loads, gen_variable, self_schedule=false, storage_quantity=nothing)
    
    # Initialize the model
    ED = Model(Gurobi.Optimizer)
    set_optimizer_attribute(ED, "MIPGap", 0.001) # 0.1%

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
    
    # Process gen_variable data (wide to long conversion)
    gen_variable_long = stack(gen_variable, 
                            Not(:hour), 
                            variable_name=:gen_full,
                            value_name=:cf);
    gen_variable_long_cf = innerjoin(gen_variable_long, 
                                gen_df[gen_df.is_variable .== 1, [:r_id, :gen_full, :existing_cap_mw]], 
                                on = :gen_full)
    
    # Define the decision variables   
    @variables(ED, begin
        GEN[G, T]  >= 0
        SOC[G_stor, T]  >= 0
        CHAR[G_stor, T]  >= 0
        DISC[G_stor, T]  >= 0
    end)
    # @variable(ED, DISC_STAT[G_stor, T], Bin)

    # Define the objective function
    @objective(ED, Min,
        sum( 
            (
                gen_df[gen_df.r_id .== i,:heat_rate_mmbtu_per_mwh][1] * gen_df[gen_df.r_id .== i,:fuel_cost][1] +
                gen_df[gen_df.r_id .== i,:var_om_cost_per_mwh][1]
                ) * GEN[i,t] 
                        for i in G_nonvar for t in T) + 
        sum(gen_df[gen_df.r_id .== i,:var_om_cost_per_mwh][1] * GEN[i,t] 
                        for i in G_var for t in T) 
        #     +
        # sum(DISC[i,t] * 
        #     discharge_price_offer for i in G_stor for t in T) -
        # sum(CHAR[i,t] * 
        #     charge_price_offer for i in G_stor for t in T) 
    )
    
    # Define the constraints
    # Demand constraint with storage charge/discharge power
    @constraint(ED, cDemand[t in T], 
        sum(GEN[i,t] for i in G) - sum(CHAR[i,t] for i in G_stor) + sum(DISC[i,t] for i in G_stor) == 
        loads[loads.hour .== t,:demand][1])

    # Non-VRE Capacity constraints
    @constraint(ED, cCapNonvar[i in G_nonvar, t in T], 
        GEN[i,t] <= gen_df[gen_df.r_id .== i,:existing_cap_mw][1])

    # VRE generation constraints
    @constraint(ED, cCapVar[i in 1:nrow(gen_variable_long_cf)], 
            GEN[gen_variable_long_cf[i,:r_id], gen_variable_long_cf[i,:hour] ] <= 
                        gen_variable_long_cf[i,:cf] *
                        gen_variable_long_cf[i,:existing_cap_mw]);
    
    # Storage power constraints
    if !self_schedule
        # @constraint(ED, cCapCharge[i in G_stor, t in T], 
        #     CHAR[i,t] <= gen_df[gen_df.r_id .== i,:existing_cap_mw][1] * 1 * (1 - DISC_STAT[i, t]))
        # @constraint(ED, cCapDischarge[i in G_stor, t in T], 
        #     DISC[i,t] <= gen_df[gen_df.r_id .== i,:existing_cap_mw][1] * 1 * DISC_STAT[i, t])
        @constraint(ED, cCapCharge[i in G_stor, t in T], 
            CHAR[i,t] <= gen_df[gen_df.r_id .== i,:existing_cap_mw][1] * 1)
        @constraint(ED, cCapDischarge[i in G_stor, t in T], 
            DISC[i,t] <= gen_df[gen_df.r_id .== i,:existing_cap_mw][1] * 1)
    else
        # if storage self-schedules, charge/discharge power should match self-scheduled quantity 
        charge_df = storage_quantity[storage_quantity.resource .== "PHS_charge", :gen_sum]
        @constraint(ED, cCapCharge[i in G_stor, t in T], 
            CHAR[i,t] == charge_df[t])
        discharge_df = storage_quantity[storage_quantity.resource .== "PHS_discharge", :gen_sum]
        @constraint(ED, cCapDischarge[i in G_stor, t in T], 
            DISC[i,t] == discharge_df[t])
    end

    # Storage SOC constraints
    @constraint(ED, cSOCStart[i in G_stor, t in T], 
        SOC[i,1] .== 
            gen_df[gen_df.r_id .== i,:existing_cap_mw][1] * storage_duration * start_soc + 
            CHAR[i,1] * one_way_efficiency - DISC[i,1] / one_way_efficiency)
    @constraint(ED, cSOC[i in G_stor, t in T[2:end]], 
        SOC[i,t] .== SOC[i,t-1] + CHAR[i,t] * one_way_efficiency - DISC[i,t] / one_way_efficiency)
    @constraint(ED, cCapEnergy[i in G_stor, t in T], 
        SOC[i,t] <= gen_df[gen_df.r_id .== i,:existing_cap_mw][1] * storage_duration)

    # Ramp up/down constraints
    @constraint(ED, cRampUp[i in G, t in T_red], 
        GEN[i,t+1] - GEN[i,t] <= gen_df[gen_df.r_id .== i,:existing_cap_mw][1] * 
                                 gen_df[gen_df.r_id .== i,:ramp_up_percentage][1] )
    @constraint(ED, cRampDn[i in G, t in T_red], 
        GEN[i,t] - GEN[i,t+1] <= gen_df[gen_df.r_id .== i,:existing_cap_mw][1] * 
                                 gen_df[gen_df.r_id .== i,:ramp_dn_percentage][1] )

#     # Storage no charging/discharging at the same time
#     M = 1000000 
#     @variable(ED, BIN_STOR[G_stor, T], Bin)
#     @constraint(ED, cNoCDa[i in G_stor, t in T], CHAR[i,t] <= M *  BIN_STOR[i,t])
#     @constraint(ED, cNoCDb[i in G_stor, t in T], DISC[i,t] <= M * (1 - BIN_STOR[i,t]))
    
    # Solve the problem
    optimize!(ED)

    # Create a dataframe of optimal values
    solution_df = DataFrame(value.(GEN).data, :auto)
    ax1 = value.(GEN).axes[1]
    ax2 = value.(GEN).axes[2]
    cols = names(solution_df)
    insertcols!(solution_df, 1, :r_id => ax1)
    solution_df = stack(solution_df, Not(:r_id), variable_name=:hour)
    solution_df.hour = foldl(replace, [cols[i] => ax2[i] for i in 1:length(ax2)], init=solution_df.hour)
    rename!(solution_df, :value => :gen)
    solution_df.hour = convert.(Int64, solution_df.hour)

    # Group generation by resource type
    solution_gen_df = innerjoin(solution_df, 
                        gen_df[!, [:r_id, :resource]], 
                        on = :r_id)
    solution_gen_df = combine(groupby(solution_gen_df, [:resource, :hour]), 
                :gen => sum)
    # Highlight VRE resources
    solution_gen_df[solution_gen_df.resource .== "solar_photovoltaic", :resource] .= "_solar_photovoltaic"
    solution_gen_df[solution_gen_df.resource .== "onshore_wind_turbine", :resource] .= "_onshore_wind_turbine"
    solution_gen_df[solution_gen_df.resource .== "small_hydroelectric", :resource] .= "_small_hydroelectric"
    sort!(solution_gen_df, [:hour, :resource])

    # Obtain charge/discharge results
    charge_df = DataFrame(resource=repeat(["PHS_charge"], length(T)), 
        hour=Array(T), 
        gen_sum=vec(sum(Array(value.(CHAR)), dims=1)))
    discharge_df = DataFrame(resource=repeat(["PHS_discharge"], 
        length(T)), hour=Array(T), 
        gen_sum=vec(sum(Array(value.(DISC)), dims=1)))
    soc_df = DataFrame(resource=repeat(["PHS_SOC"], 
        length(T)), hour=Array(T), 
        gen_sum=vec(sum(Array(value.(SOC)), dims=1)))
    append!(solution_gen_df, charge_df[:,[:resource, :hour, :gen_sum]])
    append!(solution_gen_df, discharge_df[:,[:resource, :hour, :gen_sum]])
    append!(solution_gen_df, soc_df[:,[:resource, :hour, :gen_sum]])
    
    # Obtain electricity prices
    price_df = DataFrame(hour=Array(T), price=0.0)
    for i in 1:nrow(price_df)
        price_df[i, :price] = dual(cDemand[i])
    end

    # Obtain storage profits
    charge_cost = sum(price_df[:, :price] .* charge_df[:, :gen_sum])
    discharge_rev = sum(price_df[:, :price] .* discharge_df[:, :gen_sum])
    storage_profit = discharge_rev - charge_cost

    # Return the solution results
    return (
        solution_gen_df, 
        storage_profit, 
        price_df,
        system_cost = objective_value(ED),
        status = termination_status(ED)
    )

end