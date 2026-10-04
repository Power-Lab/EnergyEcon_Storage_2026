"""
Figure 6: Impacts of ramping charges imposed on strategic storage.

Model runs needed (20 scenarios, 20 GW; see "Overview of All Scenarios" in the README):
    b20_hrs4_w{3_s3, 7_s7}_days4_ptc{0, 10}                      (no ramping charge)
    b20_hrs4_w{3_s3, 7_s7}_days4_ptc{0, 10}_rc{01, 05, 1, 2}    (ramping charge 0.1, 0.5, 1, 2 $/MW)

Usage:  python plot_figure6.py
"""

import plotly.graph_objects as go
from plotly.subplots import make_subplots

from common import color_order, get, load_summary, parse_args, save_figure

args = parse_args("Figure 6: impacts of ramping charges", summary=True)
summary = load_summary(args.summary)

rc_levels = [0, 0.1, 0.5, 1, 2]    # ramping charge, $/MW

# (incentive, VRE share, [folders for ramping charge 0, 0.1, 0.5, 1, 2])
rc_scenario_groups = [
    ("0", 40, [
        "tscc_all_weeks_3w_3s_20b_4hrs_0ptc_4days",
        "tscc_all_weeks_3w_3s_20b_4hrs_0ptc_4days_rc01",
        "tscc_all_weeks_3w_3s_20b_4hrs_0ptc_4days_rc05",
        "tscc_all_weeks_3w_3s_20b_4hrs_0ptc_4days_rc1",
        "tscc_all_weeks_3w_3s_20b_4hrs_0ptc_4days_rc2",
    ]),
    ("0", 80, [
        "tscc_all_weeks_7w_7s_20b_4hrs_0ptc_4days",
        "tscc_all_weeks_7w_7s_20b_4hrs_0ptc_4days_rc01",
        "tscc_all_weeks_7w_7s_20b_4hrs_0ptc_4days_rc05",
        "tscc_all_weeks_7w_7s_20b_4hrs_0ptc_4days_rc1",
        "tscc_all_weeks_7w_7s_20b_4hrs_0ptc_4days_rc2",
    ]),
    ("10", 40, [
        "tscc_all_weeks_3w_3s_20b_4hrs_-10ptc_4days",
        "tscc_all_weeks_3w_3s_20b_4hrs_-10ptc_4days_rc01",
        "tscc_all_weeks_3w_3s_20b_4hrs_-10ptc_4days_rc05",
        "tscc_all_weeks_3w_3s_20b_4hrs_-10ptc_4days_rc1",
        "tscc_all_weeks_3w_3s_20b_4hrs_-10ptc_4days_rc2",
    ]),
    ("10", 80, [
        "tscc_all_weeks_7w_7s_20b_4hrs_-10ptc_4days",
        "tscc_all_weeks_7w_7s_20b_4hrs_-10ptc_4days_rc01",
        "tscc_all_weeks_7w_7s_20b_4hrs_-10ptc_4days_rc05",
        "tscc_all_weeks_7w_7s_20b_4hrs_-10ptc_4days_rc1",
        "tscc_all_weeks_7w_7s_20b_4hrs_-10ptc_4days_rc2",
    ]),
]

styles = {
    ("0", 40): dict(dash="solid", symbol="circle", color=color_order[0]),
    ("0", 80): dict(dash="solid", symbol="circle", color=color_order[1]),
    ("10", 40): dict(dash="dash", symbol="circle", color=color_order[2]),
    ("10", 80): dict(dash="dash", symbol="circle", color=color_order[3]),
}
labels = {
    ("0", 40): "40% VRE, no renewable incentive",
    ("0", 80): "80% VRE, no renewable incentive",
    ("10", 40): "40% VRE, with a 10 $/MW renewable incentive",
    ("10", 80): "80% VRE, with a 10 $/MW renewable incentive",
}
fig6_font = {"family": "Arial", "size": 16, "color": "#000000"}

fig = make_subplots(rows=1, cols=3, horizontal_spacing=0.08,
                    subplot_titles=["(a) System Costs", "(b) Strategic Storage Profits", "(c) Total Ramping Charges"])

for incentive, vre, folders in rc_scenario_groups:
    style = styles[(incentive, vre)]
    sys_cost = [get(summary, f, "bi-level", "system_cost_no_ptc_no_storage") / 1e6 for f in folders]
    # Storage profit is shown net of the ramping charge (the two coincide when the charge is zero)
    profit = [get(summary, f, "bi-level", "storage_profit") if rc == 0
              else get(summary, f, "bi-level", "storage_profit_after_ramping_charge")
              for f, rc in zip(folders, rc_levels)]
    profit = [v / 1e6 for v in profit]
    rc_total = [0.0 if rc == 0 else get(summary, f, "bi-level", "ramping_charge_total") / 1e6
                for f, rc in zip(folders, rc_levels)]

    for col_idx, y in enumerate([sys_cost, profit, rc_total], start=1):
        fig.add_trace(go.Scatter(
            x=rc_levels, y=y, mode="lines+markers", name=labels[(incentive, vre)],
            line=dict(color=style["color"], width=3, dash=style["dash"]),
            marker=dict(size=12, symbol=style["symbol"]),
            showlegend=(col_idx == 1),
        ), row=1, col=col_idx)

for col_idx, ylabel in [(1, "System costs ($m)"), (2, "Storage profits ($m)"), (3, "Total ramping charges ($m)")]:
    fig.update_xaxes(title_text="Ramping charge ($/MW)", row=1, col=col_idx)
    fig.update_yaxes(title_text=ylabel, row=1, col=col_idx)

fig.update_layout(template="simple_white", barmode="group",
                  font=fig6_font,
                  margin=dict(l=0, r=0, b=0, t=25),
                  uniformtext_minsize=9, uniformtext_mode="show",
                  legend=dict(yanchor="top", y=1.2, xanchor="center", x=0.5, orientation="h"),
                  width=1200, height=600)
fig.update_annotations(font=fig6_font)
fig.update_xaxes(title_font=fig6_font)
fig.update_yaxes(title_font=fig6_font)

save_figure(fig, "figure6", args.out)
