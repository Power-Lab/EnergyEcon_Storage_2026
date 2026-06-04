#=
A bi-level model that has been converted to single level
Inputs:
    gen_df            dataframe with generator info
    loads             load by time
    gen_variable      capacity factors of variable generators in "wide" format
=#

function sbed_cvx(gen_df, loads, gen_variable)

    # Define generator sets
    G_var = gen_df[gen_df[!,:is_variable] .== 1, :r_id] 
    G_nonvar = gen_df[(gen_df[!,:is_variable] .== 0) .& (gen_df[!,:is_storage] .== 0), :r_id]
    G_stor = gen_df[gen_df[!,:is_storage] .== 1, :r_id][1:1]
    G = gen_df[gen_df[!,:is_storage] .== 0, :r_id]
    G_wind = gen_df[gen_df.resource .== "onshore_wind_turbine", :r_id]
    G_solar = gen_df[gen_df.resource .== "solar_photovoltaic", :r_id]

    # Define time period sets
    T = loads.hour
    T_red = loads.hour[1:end-1]
    T_peak = [if (mod(h, 18) .== 0) .| (mod(h, 19) .== 0) .| (mod(h, 20) .== 0) .| (mod(h, 21) .== 0)  
            h end for h in loads.hour]
    T_peak = T_peak[T_peak .!= nothing];

    # Process gen_variable data (wide to long conversion)
    gen_variable_long = stack(gen_variable, Not(:hour), 
                            variable_name=:gen_full,
                            value_name=:cf);
    gen_variable_long_cf = innerjoin(gen_variable_long, 
                                gen_df[gen_df.is_variable .== 1, [:r_id, :gen_full, :existing_cap_mw]],
                                on = :gen_full)

    # Create a bi-level model
    SBED_CVX = Model(
        Gurobi.Optimizer,
    )
    set_optimizer_attribute(SBED_CVX, "MIPGap", 0.001) # 0.1%
    set_optimizer_attribute(SBED_CVX, "TimeLimit", 2000) # seconds

    # Define upper-level decision variables
    @variables(SBED_CVX, begin
        SOC[G_stor, T]  >= 0  # in MWh
        CHAR_QUANTITY_OFFERED[G_stor, T]  >= 0  # in percentage
        DISC_QUANTITY_OFFERED[G_stor, T]  >= 0  # in percentage
        CHAR_PRICE_OFFER[T]  # in $/MWh
        DISC_PRICE_OFFER[T]  # in $/MWh
        SOC_AUX[G_stor] >= 0  # in MWh
    end)

    # Define lower-level decision variables
    @variables(SBED_CVX, begin
        GEN[G, T]  >= 0
        CHAR_CLEARED[G_stor, T]  >= 0  # in MW
        DISC_CLEARED[G_stor, T]  >= 0  # in MW
    end)
    
    # Define lower-level DUAL variables
    @variables(SBED_CVX, begin
        # (2b)        
        LAMBDA[T] # duals of equality constraints should be free
        # (2c)
        ALPHA_L[G, T] >= 0
        ALPHA_U[G, T] >= 0
        # (2d)
        BETA_L[G_stor, T] >= 0
        BETA_U[G_stor, T] >= 0
        # (2e)
        EPS_L[G_stor, T] >= 0
        EPS_U[G_stor, T] >= 0
        # (2f)
        UPSILON_L[G, T] >= 0
        UPSILON_U[G, T] >= 0
    end)

    # Replace the lower-level problem with its KKT conditions
    # KKT: primal feasibility
    @constraint(SBED_CVX, cDemand[t in T], 
        sum(GEN[i,t] for i in G) - sum(CHAR_CLEARED[i,t] for i in G_stor) + 
        sum(DISC_CLEARED[i,t] for i in G_stor) == loads[loads.hour .== t,:demand][1])
    
    # KKT: dual feasibility
    # (6a): L with respect to cleared charge power
    @constraint(SBED_CVX, cDF1b[t in T],
        (LAMBDA[t]) <= 1000 )  # VOLL
    @constraint(SBED_CVX, cDF1[i in G_stor, t in T],
        (- CHAR_PRICE_OFFER[t] + LAMBDA[t] + BETA_U[i,t] - BETA_L[i,t]) == 0 )
    # (6b): L with respect to cleared discharge power
    @constraint(SBED_CVX, cDF2[i in G_stor, t in T],
        (DISC_PRICE_OFFER[t] - LAMBDA[t] + EPS_U[i,t] - EPS_L[i,t]) == 0 )
    # (6c): L with respect to cleared generator power
    @constraint(SBED_CVX, cDF3[i in G, t in T_red],
        ((gen_df[gen_df.r_id .== i,:heat_rate_mmbtu_per_mwh][1] * gen_df[gen_df.r_id .== i,:fuel_cost][1] +
                gen_df[gen_df.r_id .== i,:var_om_cost_per_mwh][1]) - 
            LAMBDA[t] + ALPHA_U[i,t] - ALPHA_L[i,t] + 
            UPSILON_U[i,t] - UPSILON_L[i,t] - UPSILON_U[i,t+1] + UPSILON_L[i,t+1]
            ) == 0 )
    @constraint(SBED_CVX, cDF3_T[i in G],
        ((gen_df[gen_df.r_id .== i,:heat_rate_mmbtu_per_mwh][1] * gen_df[gen_df.r_id .== i,:fuel_cost][1] +
                gen_df[gen_df.r_id .== i,:var_om_cost_per_mwh][1]) - 
            LAMBDA[T[end]] + ALPHA_U[i,T[end]] - ALPHA_L[i,T[end]] + 
            UPSILON_U[i,T[end]] - UPSILON_L[i,T[end]]
            ) == 0 )
    
    # KKT: complementary slackness conditions (v2 applying the Big-M method to CS constraints)
    # (7a)
    M = 1000000
    @variable(SBED_CVX, BIN_CS1[G, T], Bin)
    @constraint(SBED_CVX, cCS1a[i in G, t in T], 
        GEN[i,t] <= M *  BIN_CS1[i,t])
    @constraint(SBED_CVX, cCS1b[i in G, t in T], 
        ALPHA_L[i,t] <= M * (1 - BIN_CS1[i,t]))
    
    # (7b)
    @constraint(SBED_CVX, cCapNonvar[i in G_nonvar, t in T], 
        GEN[i,t] <= gen_df[gen_df.r_id .== i,:existing_cap_mw][1])
    @constraint(SBED_CVX, cCapVar[i in 1:nrow(gen_variable_long_cf)], 
        GEN[gen_variable_long_cf[i,:r_id], gen_variable_long_cf[i,:hour] ] <= 
                    gen_variable_long_cf[i,:cf] * gen_variable_long_cf[i,:existing_cap_mw])
    @variable(SBED_CVX, BIN_CS2[G_nonvar, T], Bin)
    @constraint(SBED_CVX, cCS2aa[i in G_nonvar, t in T],
        (gen_df[gen_df.r_id .== i,:existing_cap_mw][1] - GEN[i,t]) <= M * BIN_CS2[i,t])
    @constraint(SBED_CVX, cCS2ab[i in G_nonvar, t in T],
        ALPHA_U[i,t] <= M * (1 - BIN_CS2[i,t]))

    @variable(SBED_CVX, BIN_CS2b[1:nrow(gen_variable_long_cf)], Bin)
    @constraint(SBED_CVX, cCS2ba[i in 1:nrow(gen_variable_long_cf)], 
        (gen_variable_long_cf[i,:cf] * gen_variable_long_cf[i,:existing_cap_mw] - 
         GEN[gen_variable_long_cf[i,:r_id], gen_variable_long_cf[i,:hour] ]) <= M * BIN_CS2b[i])
    @constraint(SBED_CVX, cCS2bb[i in 1:nrow(gen_variable_long_cf)], 
        ALPHA_U[gen_variable_long_cf[i,:r_id], gen_variable_long_cf[i,:hour] ] <= M * (1 - BIN_CS2b[i]))
    
    # (7c)
    @variable(SBED_CVX, BIN_CS3[G_stor, T], Bin)
    @constraint(SBED_CVX, cCS3a[i in G_stor, t in T], 
        CHAR_CLEARED[i,t] <= M *  BIN_CS3[i,t])
    @constraint(SBED_CVX, cCS3b[i in G_stor, t in T], 
        BETA_L[i,t] <= M * (1 - BIN_CS3[i,t]))

    # (7d)
    @constraint(SBED_CVX, cLowerCapCharge[i in G_stor, t in T], 
        CHAR_CLEARED[i,t] <= gen_df[gen_df.r_id .== i,:existing_cap_mw][1] * CHAR_QUANTITY_OFFERED[i,t])
    @variable(SBED_CVX, BIN_CS4[G_stor, T], Bin)
    @constraint(SBED_CVX, cCS4a[i in G_stor, t in T], 
        (gen_df[gen_df.r_id .== i,:existing_cap_mw][1] * CHAR_QUANTITY_OFFERED[i,t] - CHAR_CLEARED[i,t]) <= 
        M *  BIN_CS4[i,t])
    @constraint(SBED_CVX, cCS4b[i in G_stor, t in T], 
        BETA_U[i,t] <= M * (1 - BIN_CS4[i,t]))

    # (7e)
    @variable(SBED_CVX, BIN_CS5[G_stor, T], Bin)
    @constraint(SBED_CVX, cCS5a[i in G_stor, t in T], 
        DISC_CLEARED[i,t] <= M *  BIN_CS5[i,t])
    @constraint(SBED_CVX, cCS5b[i in G_stor, t in T], 
        EPS_L[i,t] <= M * (1 - BIN_CS5[i,t]))

    # (7f)
    @constraint(SBED_CVX, cLowerCapDischarge[i in G_stor, t in T], 
        DISC_CLEARED[i,t] <= gen_df[gen_df.r_id .== i,:existing_cap_mw][1] * DISC_QUANTITY_OFFERED[i,t])
    @variable(SBED_CVX, BIN_CS6[G_stor, T], Bin)
    @constraint(SBED_CVX, cCS6a[i in G_stor, t in T], 
        (gen_df[gen_df.r_id .== i,:existing_cap_mw][1] *  DISC_QUANTITY_OFFERED[i,t] - DISC_CLEARED[i,t]) <= 
        M *  BIN_CS6[i,t])
    @constraint(SBED_CVX, cCS6b[i in G_stor, t in T], 
        EPS_U[i,t] <= M * (1 - BIN_CS6[i,t]))

    # (7g)
    @constraint(SBED_CVX, cRampUp[i in G, t in T_red], 
        GEN[i,t+1] - GEN[i,t] <= gen_df[gen_df.r_id .== i,:existing_cap_mw][1] * 
                                 gen_df[gen_df.r_id .== i,:ramp_up_percentage][1] )
    @variable(SBED_CVX, BIN_CS7[G, T_red], Bin)
    @constraint(SBED_CVX, cCS7a[i in G, t in T_red],
        (gen_df[gen_df.r_id .== i,:existing_cap_mw][1] * gen_df[gen_df.r_id .== i,:ramp_up_percentage][1] +
        GEN[i,t] - GEN[i,t+1]) <= M * BIN_CS7[i,t])
    @constraint(SBED_CVX, cCS7b[i in G, t in T_red],
        UPSILON_U[i,t+1] <= M * (1 - BIN_CS7[i,t]))
    @constraint(SBED_CVX, cCS7c[i in G],
        UPSILON_U[i,1] == 0)

    # (7h)
    @constraint(SBED_CVX, cRampDn[i in G, t in T_red], 
        GEN[i,t] - GEN[i,t+1] <= gen_df[gen_df.r_id .== i,:existing_cap_mw][1] * 
                                 gen_df[gen_df.r_id .== i,:ramp_dn_percentage][1] )
    @variable(SBED_CVX, BIN_CS8[G, T_red], Bin)
    @constraint(SBED_CVX, cCS8a[i in G, t in T_red],
        (gen_df[gen_df.r_id .== i,:existing_cap_mw][1] * gen_df[gen_df.r_id .== i,:ramp_dn_percentage][1] +
         GEN[i,t+1] - GEN[i,t]) <= M * BIN_CS8[i,t])
    @constraint(SBED_CVX, cCS8b[i in G, t in T_red],
        UPSILON_L[i,t+1] <= M * (1 - BIN_CS8[i,t]))
    @constraint(SBED_CVX, cCS8c[i in G],
        UPSILON_L[i,1] == 0)

    # Add RA program requirements depending on the scenario choice
    if ra_scenario == "min_soc"
        # RA program min SOC requirements during peak hours
        @expression(SBED_CVX, ra_penalty_cost_total, 0)
        @constraint(SBED_CVX, cRASOC[i in G_stor, t in T_peak],
            SOC[i,t] >= gen_df[gen_df.r_id .== i,:existing_cap_mw][1] * storage_duration * ra_min_soc)
    elseif ra_scenario == "penalty"
        # Add RA noncompliance cost term if min SOC is violated during peak hours
        @expression(SBED_CVX, ra_penalty_cost_total, 
            sum(SOC_AUX[i] * ra_penalty_cost for i in G_stor))
        @constraint(SBED_CVX, cRAPenalty[i in G_stor, t in T_peak], 
            SOC_AUX[i] >= gen_df[gen_df.r_id .== i,:existing_cap_mw][1] * storage_duration * ra_min_soc - 
                            SOC[i,t])
    else  # baseline scenario
        @expression(SBED_CVX, ra_penalty_cost_total, 0)
    end

    # Add ramping charges on strategic storage
    if ramping_charge_scenario
        # ABS ramping charge term
        # Define the slack variable for the ramping charge term (must be non-negative)
        @variable(SBED_CVX, ramp_magnitude[i in G_stor, t in T[2:end]] >= 0)
        # Add constraints to "trap" the absolute value
        @constraint(SBED_CVX, [i in G_stor, t in T[2:end]], 
            ramp_magnitude[i,t] >= (DISC_CLEARED[i,t] - CHAR_CLEARED[i,t]) - (DISC_CLEARED[i,t-1] - CHAR_CLEARED[i,t-1]))
        @constraint(SBED_CVX, [i in G_stor, t in T[2:end]], 
            ramp_magnitude[i,t] >= -((DISC_CLEARED[i,t] - CHAR_CLEARED[i,t]) - (DISC_CLEARED[i,t-1] - CHAR_CLEARED[i,t-1])))
        @expression(SBED_CVX, ramping_charge_total, 
            sum(ramping_charge * ramp_magnitude[i,t] for i in G_stor, t in T[2:end]))
    else  # no ramping charges
        @expression(SBED_CVX, ramping_charge_total, 0.0)
    end

    @objective(SBED_CVX, Min, 
        - sum(
            loads[loads.hour .== t,:demand][1] * LAMBDA[t] for t in T) +
        sum( 
            (
                gen_df[gen_df.r_id .== i,:heat_rate_mmbtu_per_mwh][1] * gen_df[gen_df.r_id .== i,:fuel_cost][1] +
                gen_df[gen_df.r_id .== i,:var_om_cost_per_mwh][1]
                ) * GEN[i,t] for i in G_nonvar for t in T) + 
        sum(
            gen_df[gen_df.r_id .== i,:var_om_cost_per_mwh][1] * GEN[i,t] for i in G_var for t in T) +
        sum(
            gen_df[gen_df.r_id .== i,:existing_cap_mw][1] * ALPHA_U[i,t] for i in G_nonvar for t in T) +
        sum(
            gen_variable_long_cf[i,:cf] * gen_variable_long_cf[i,:existing_cap_mw] * 
            ALPHA_U[gen_variable_long_cf[i,:r_id], gen_variable_long_cf[i,:hour] ] for i in 1:nrow(gen_variable_long_cf)) +
        sum(
            gen_df[gen_df.r_id .== i,:existing_cap_mw][1] * gen_df[gen_df.r_id .== i,:ramp_dn_percentage][1] * 
            UPSILON_L[i,t] for i in G for t in T) +
        sum(
            gen_df[gen_df.r_id .== i,:existing_cap_mw][1] * gen_df[gen_df.r_id .== i,:ramp_up_percentage][1] *
            UPSILON_U[i,t] for i in G for t in T) +
        ra_penalty_cost_total +
        ramping_charge_total
    )      



    # (1b)(1c) Upper-level: storage offered charge/discharge power should be less than or equal to 100% of max power
    @constraint(SBED_CVX, cUpperCapCharge[i in G_stor, t in T], 
        CHAR_QUANTITY_OFFERED[i,t] <= 1.0)
    @constraint(SBED_CVX, cUpperCapDischarge[i in G_stor, t in T], 
        DISC_QUANTITY_OFFERED[i,t] <= 1.0)

    # (1d)(1e)(1f) Upper-level: SOC start/end/dyanmics/non-simultaneous charging and discharging
    @constraint(SBED_CVX, cUpperSOCStart[i in G_stor, t in T], 
        SOC[i,1] .== 
            gen_df[gen_df.r_id .== i,:existing_cap_mw][1] * storage_duration * start_soc + 
            CHAR_CLEARED[i,1] * one_way_efficiency - DISC_CLEARED[i,1] / one_way_efficiency)
    @constraint(SBED_CVX, cUpperCapEnergy[i in G_stor, t in T], 
        SOC[i,t] <= gen_df[gen_df.r_id .== i,:existing_cap_mw][1] * storage_duration)
    @constraint(SBED_CVX, cUpperSOC[i in G_stor, t in T[2:end]], 
        SOC[i,t] .== SOC[i,t-1] + CHAR_CLEARED[i,t] * one_way_efficiency - DISC_CLEARED[i,t] / one_way_efficiency)
    @variable(SBED_CVX, BIN_STOR[G_stor, T], Bin)
    @constraint(SBED_CVX, cNoCDa[i in G_stor, t in T], CHAR_CLEARED[i,t] <= M *  BIN_STOR[i,t])
    @constraint(SBED_CVX, cNoCDb[i in G_stor, t in T], DISC_CLEARED[i,t] <= M * (1 - BIN_STOR[i,t]))

    # Solve the bi-level SB-ED model that is converted to a single-level one
    optimize!(SBED_CVX)
    final_cost = objective_value(SBED_CVX)

    # Calculate the total system generation cost
    system_cost = sum( 
        (gen_df[gen_df.r_id .== i,:heat_rate_mmbtu_per_mwh][1] * gen_df[gen_df.r_id .== i,:fuel_cost][1] +
        gen_df[gen_df.r_id .== i,:var_om_cost_per_mwh][1]) * value.(GEN[i,t]) for i in G_nonvar for t in T) + 
        sum(
            gen_df[gen_df.r_id .== i,:var_om_cost_per_mwh][1] * value.(GEN[i,t]) for i in G_var for t in T) 

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
    solution_gen_df_ungrouped = copy(solution_gen_df)
    solution_gen_df = combine(groupby(solution_gen_df, [:resource, :hour]), 
                :gen => sum)
    solution_gen_df[solution_gen_df.resource .== "solar_photovoltaic", :resource] .= "_solar_photovoltaic"
    solution_gen_df[solution_gen_df.resource .== "onshore_wind_turbine", :resource] .= "_onshore_wind_turbine"
    solution_gen_df[solution_gen_df.resource .== "small_hydroelectric", :resource] .= "_small_hydroelectric"
    sort!(solution_gen_df, [:hour, :resource])

    # Append charge/discharge results to generation results
    charge_df = DataFrame(resource=repeat(["PHS_charge"], length(T)), hour=Array(T), gen_sum=value.(CHAR_CLEARED[G_stor[1], :]).data)
    discharge_df = DataFrame(resource=repeat(["PHS_discharge"], length(T)), hour=Array(T), gen_sum=value.(DISC_CLEARED[G_stor[1], :]).data)
    append!(solution_gen_df, charge_df[:,[:resource, :hour, :gen_sum]])
    append!(solution_gen_df, discharge_df[:,[:resource, :hour, :gen_sum]]);

    # Obtain cleared charge/discharge quantity
    storage_cleared = DataFrame()
    charge_sbed_df = DataFrame(resource=repeat(["PHS_charge"], length(T)), hour=Array(T), 
        gen_sum=value.(CHAR_CLEARED[G_stor[1], :]).data)
    discharge_sbed_df = DataFrame(resource=repeat(["PHS_discharge"], length(T)), hour=Array(T), 
        gen_sum=value.(DISC_CLEARED[G_stor[1], :]).data)
    soc_df = DataFrame(resource=repeat(["PHS_SOC"], length(T)), hour=Array(T), 
        gen_sum=value.(SOC[G_stor[1], :]).data)
    append!(storage_cleared, charge_sbed_df[:,[:resource, :hour, :gen_sum]])
    append!(storage_cleared, discharge_sbed_df[:,[:resource, :hour, :gen_sum]])
    append!(storage_cleared, soc_df[:,[:resource, :hour, :gen_sum]]);

    # Obtain offered quantity
    storage_offered = DataFrame()
    charge_sbed_offer_df = DataFrame(resource=repeat(["PHS_charge"], length(T)), hour=Array(T), 
        gen_sum=value.(CHAR_QUANTITY_OFFERED[G_stor[1], :]).data)
    discharge_sbed_offer_df = DataFrame(resource=repeat(["PHS_discharge"], length(T)), hour=Array(T), 
        gen_sum=value.(DISC_QUANTITY_OFFERED[G_stor[1], :]).data)
    append!(storage_offered, charge_sbed_offer_df[:,[:resource, :hour, :gen_sum]])
    append!(storage_offered, discharge_sbed_offer_df[:,[:resource, :hour, :gen_sum]])
                                            
    # Obtain prices and calculate storage profits
    price_df = DataFrame()
    price_df[!, :hour] = Array(T)
    price_df[!, :price] = value.(LAMBDA).data
    price_df[!, :discharge_price_offer] = value.(DISC_PRICE_OFFER).data
    price_df[!, :charge_price_offer] = value.(CHAR_PRICE_OFFER).data
    charge_cost = sum(price_df[:, :price] .* charge_sbed_df[:, :gen_sum])
    discharge_rev = sum(price_df[:, :price] .* discharge_sbed_df[:, :gen_sum])
    storage_profit = discharge_rev - charge_cost - ra_penalty_cost_total
    ramping_charge_total = JuMP.value(ramping_charge_total)

    # Obtain renewable max gen
    gen_variable_long_cf.max_gen = gen_variable_long_cf.cf .* gen_variable_long_cf.existing_cap_mw
    vre_df = DataFrame(hour=Array(T), solar_gen_max=0.0, wind_gen_max=0.0)
    for t in 1:nrow(vre_df)
        solar_df = filter(row -> row.r_id in G_solar, gen_variable_long_cf)
        vre_df[t, :solar_gen_max] = sum(solar_df[solar_df.hour .== t, :max_gen])
        wind_df = filter(row -> row.r_id in G_wind, gen_variable_long_cf)
        vre_df[t, :wind_gen_max] = sum(wind_df[wind_df.hour .== t, :max_gen])
    end

    return (
        solution_gen_df,
        solution_gen_df_ungrouped,
        storage_cleared,
        storage_offered,
        price_df,
        vre_df,
        storage_profit,
        ramping_charge_total,
        final_cost,
        system_cost,
        status = termination_status(SBED_CVX),
        mip_gap = float(MOI.get(SBED_CVX, MOI.RelativeGap()))
    )
                                            
end
