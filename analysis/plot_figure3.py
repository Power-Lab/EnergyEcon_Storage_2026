"""
Figure 3: Electricity price duration curves under different scenarios.

Model runs needed (4 scenarios, see "Overview of All Scenarios" in the README):
    b20_hrs4_w3_s3_days4_ptc10    b0_hrs4_w3_s3_days4_ptc10
    b20_hrs4_w7_s7_days4_ptc10    b0_hrs4_w7_s7_days4_ptc10

Usage:  python plot_figure3.py
"""

import plotly.graph_objects as go
from plotly.subplots import make_subplots

from common import color_order, font_dict, load_hourly, parse_args, save_figure

args = parse_args("Figure 3: price duration curves", root=True)

fig = make_subplots(rows=2, cols=1, shared_yaxes=True, shared_xaxes=False, vertical_spacing=0.1,
                    subplot_titles=("(a) 40% VRE Generation Share", "(b) 80% VRE Generation Share"))


def add_price_duration(row, storage_folder, no_storage_folder, with_legend):
    df_iso = load_hourly(args.root, storage_folder, "iso-control").sort_values("price", ascending=False).reset_index(drop=True)
    df_bi = load_hourly(args.root, storage_folder, "bi-level").sort_values("price", ascending=False).reset_index(drop=True)
    df_bi = df_bi[df_bi["price"] < 1000].reset_index(drop=True)
    df_no = load_hourly(args.root, no_storage_folder, "iso-control").sort_values("price", ascending=False).reset_index(drop=True)

    fig.add_trace(go.Scatter(x=df_iso.index, y=df_iso.price, showlegend=False,
                             line=dict(color=color_order[0], width=1), marker=dict(size=5),
                             name="Central control", mode="markers"), row=row, col=1)
    fig.add_trace(go.Scatter(x=df_bi.index, y=df_bi.price, showlegend=False,
                             line=dict(color=color_order[1], width=1), marker=dict(size=5),
                             name="Strategic storage", mode="markers"), row=row, col=1)
    fig.add_trace(go.Scatter(x=df_no.index, y=df_no.price, showlegend=False,
                             line=dict(color=color_order[2], width=1), marker=dict(size=5),
                             name="No storage", mode="markers"), row=row, col=1)

    if with_legend:
        # Off-chart dummy points that exist only to draw larger legend markers
        for name, color in [("No storage", color_order[2]), ("Central control", color_order[0]),
                            ("Strategic storage", color_order[1])]:
            fig.add_trace(go.Scatter(x=[0], y=[-100], showlegend=True,
                                     line=dict(color=color, width=1), marker=dict(size=15),
                                     name=name, mode="markers"), row=row, col=1)


add_price_duration(1, "tscc_all_weeks_3w_3s_20b_4hrs_-10ptc_4days", "tscc_all_weeks_3w_3s_0b_4hrs_-10ptc_4days", with_legend=True)
add_price_duration(2, "tscc_all_weeks_7w_7s_20b_4hrs_-10ptc_4days", "tscc_all_weeks_7w_7s_0b_4hrs_-10ptc_4days", with_legend=False)

fig.add_hline(y=0, line_dash="dash", line_color="#747678", line_width=3, row=1, col=1)
fig.add_hline(y=0, line_dash="dash", line_color="#747678", line_width=3, row=2, col=1)

fig.update_layout(template="simple_white", barmode="overlay",
                  font=font_dict,
                  margin=dict(l=0, r=0, b=0, t=30),
                  uniformtext_minsize=20, uniformtext_mode="show",
                  legend=dict(yanchor="top", y=1.0, xanchor="right", x=1.0, orientation="v"),
                  width=900, height=1200,
                  yaxis_range=[-15, 65], yaxis2_range=[-15, 65],
                  xaxis2_title="Number of Hours", yaxis_title="Electricity Price ($/MW)", yaxis2_title="Electricity Price ($/MW)")
fig.update_annotations(font=font_dict)
fig.update_xaxes(title_font=font_dict)
fig.update_yaxes(title_font=font_dict)

save_figure(fig, "figure3", args.out)
