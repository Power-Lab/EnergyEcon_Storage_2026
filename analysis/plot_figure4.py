"""
Figure 4: Storage dispatch and electricity prices using a representative period.

Model runs needed (1 scenario, see "Overview of All Scenarios" in the README):
    b20_hrs4_w3_s3_days4_ptc10

Usage:  python plot_figure4.py
"""

import numpy as np
import pandas as pd
import plotly.graph_objects as go
from plotly.subplots import make_subplots

from common import color_order, font_dict, load_hourly, parse_args, save_figure

args = parse_args("Figure 4: storage dispatch and prices in a representative period", root=True)

hour_idx_start, hour_idx_end = 3481, 3528
folder_name = "tscc_all_weeks_3w_3s_20b_4hrs_-10ptc_4days"

df_bi = load_hourly(args.root, folder_name, "bi-level")
df_iso = load_hourly(args.root, folder_name, "iso-control")

data = pd.DataFrame({
    "hour": np.array(df_bi.iloc[hour_idx_start:hour_idx_end].hour_simulation) - 24,
    "bi_price": np.array(df_bi.iloc[hour_idx_start:hour_idx_end].price),
    "bi_power": np.array(df_bi.iloc[hour_idx_start:hour_idx_end].power),
    "iso_price": np.array(df_iso.iloc[hour_idx_start:hour_idx_end].price),
    "iso_power": np.array(df_iso.iloc[hour_idx_start:hour_idx_end].power),
})

fig = make_subplots(rows=2, cols=1, shared_xaxes=False, vertical_spacing=0.1,
                    subplot_titles=("(a) Storage dispatch profile", "(b) Electricity prices"))
fig.add_trace(go.Scatter(x=data.hour, y=data.iso_power, line=dict(color=color_order[0], width=3),
                         name="Central control", mode="lines+markers"), row=1, col=1)
fig.add_trace(go.Scatter(x=data.hour, y=data.bi_power, line=dict(color=color_order[1], width=3),
                         name="Strategic storage", mode="lines+markers"), row=1, col=1)
fig.add_trace(go.Scatter(x=data.hour, y=data.iso_price, line=dict(color=color_order[0], width=3), showlegend=False,
                         name="ISO-control - prices", mode="lines+markers"), row=2, col=1)
fig.add_trace(go.Scatter(x=data.hour, y=data.bi_price, line=dict(color=color_order[1], width=3), showlegend=False,
                         name="Bi-level - prices", mode="lines+markers"), row=2, col=1)

fig.add_hline(y=0, line_dash="dash", line_color="#747678", line_width=3, row=1, col=1)
fig.add_hline(y=0, line_dash="dash", line_color="#747678", line_width=3, row=2, col=1)

fig.update_layout(template="simple_white", barmode="overlay",
                  font=font_dict,
                  margin=dict(l=0, r=0, b=0, t=25),
                  legend=dict(yanchor="top", y=1.0, xanchor="right", x=1.0, orientation="v"),
                  uniformtext_minsize=9, uniformtext_mode="show",
                  width=900, height=1200, yaxis_range=[-17000, 24500],
                  xaxis2_title="Hours", yaxis_title="Storage Power (MW)", yaxis2_title="Electricity Price ($/MW)")
fig.update_annotations(font=font_dict)
fig.update_xaxes(title_font=font_dict)
fig.update_yaxes(title_font=font_dict)

save_figure(fig, "figure4", args.out)
