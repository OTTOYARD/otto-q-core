"""C8 — render the degradation chart and the anti-correlation curve as SVGs.

    python3 sites/site_alpha/make_charts.py

Pure function of the two committed JSON artifacts (which are themselves pure
functions of seed 424242): re-running regenerates the same charts from the same
run IDs. Colors are the validated reference palette (dataviz skill), slots 1-4
in fixed order per policy — never cycled; light surface; value labels shipped
(the relief rule for the lower-contrast slots).
"""
import json
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

HERE = Path(__file__).parent
SURFACE = "#fcfcfb"
INK, INK2 = "#0b0b0b", "#52514e"
SERIES = {"fifo": "#2a78d6", "greedy": "#eb6834",
          "otto_q_asis": "#1baf7a", "cpsat_alpha": "#eda100"}
POLICY_ORDER = ["fifo", "greedy", "otto_q_asis", "cpsat_alpha"]


def style(ax):
    ax.set_facecolor(SURFACE)
    for s in ("top", "right"):
        ax.spines[s].set_visible(False)
    for s in ("left", "bottom"):
        ax.spines[s].set_color("#d8d7d2")
    ax.tick_params(colors=INK2, labelsize=8)
    ax.yaxis.grid(True, color="#e8e7e2", linewidth=0.8)
    ax.set_axisbelow(True)


def degradation():
    m = json.loads((HERE / "failure_matrix_seed424242.json").read_text())
    cells = [c for c in m["cells"] if c.get("status") != "not_applicable"]
    scenarios = list(dict.fromkeys(c["scenario"] for c in cells))  # canonical order
    fig, axes = plt.subplots(2, 1, figsize=(11, 7.5), dpi=110)
    fig.patch.set_facecolor(SURFACE)
    for ax, metric, title, rot in (
        (axes[0], "total_tardy_min", "Total tardiness (min) — lower is better", 0),
        (axes[1], "cap_violation_kw_min", "Power-cap violation (kW·min) — cap-blind baselines pay here", 90),
    ):
        style(ax)
        w = 0.19
        top = 0
        for pi, pol in enumerate(POLICY_ORDER):
            xs, ys = [], []
            for si, sc in enumerate(scenarios):
                cell = next((c for c in cells if c["scenario"] == sc and c["policy"] == pol), None)
                if cell:
                    xs.append(si + (pi - 1.5) * w)
                    ys.append(cell["metrics"][metric])
            top = max(top, max(ys, default=0))
            bars = ax.bar(xs, ys, width=w * 0.9, color=SERIES[pol], label=pol,
                          edgecolor=SURFACE, linewidth=1)
            for b, y in zip(bars, ys):
                if y > 0:
                    ax.text(b.get_x() + b.get_width() / 2, y, f"{y:,.0f}",
                            ha="center", va="bottom", fontsize=6.2, color=INK2,
                            rotation=rot)
        ax.set_ylim(0, top * 1.22 if top else 1)   # headroom for labels/legend
        ax.set_xticks(range(len(scenarios)))
        ax.set_xticklabels([s.replace("_", "\n") for s in scenarios], fontsize=7, color=INK)
        ax.set_title(title, loc="left", fontsize=10, color=INK, pad=8)
    axes[0].legend(loc="lower right", bbox_to_anchor=(1.0, 1.0), frameon=False,
                   fontsize=8, ncols=4, labelcolor=INK2)
    fig.suptitle("Site Alpha — failure-scenario degradation by policy  ·  seed 424242 · CRN-paired · every bar regenerable from its run ID (failure_matrix_seed424242.json)",
                 fontsize=9.5, color=INK, x=0.01, ha="left")
    fig.tight_layout(rect=(0, 0, 1, 0.96))
    fig.savefig(HERE / "degradation_chart.svg", facecolor=SURFACE)
    print("wrote degradation_chart.svg")


def anticorrelation():
    c = json.loads((HERE / "anticorrelation_seed424242.json").read_text())
    rows = [r for r in c["rows"] if r["policy"] == "cpsat_alpha"]
    labels = [r["config"].replace(" (", "\n(") for r in rows]
    fig, axes = plt.subplots(1, 2, figsize=(11, 4.2), dpi=110)
    fig.patch.set_facecolor(SURFACE)
    for ax, metric, title, unit in (
        (axes[0], "peak_site_kw", "Peak site draw", "kW"),
        (axes[1], "turns", "Service-point turns", "turns"),
    ):
        style(ax)
        ys = [r["metrics"][metric] for r in rows]
        bars = ax.bar(range(len(rows)), ys, width=0.55, color="#2a78d6",
                      edgecolor=SURFACE, linewidth=1)
        for b, y, r in zip(bars, ys, rows):
            ax.text(b.get_x() + b.get_width() / 2, y, f"{y:,.0f} {unit}",
                    ha="center", va="bottom", fontsize=8, color=INK)
            ax.text(b.get_x() + b.get_width() / 2, y * 0.04, r["run_id"],
                    ha="center", va="bottom", fontsize=5.6, color=SURFACE, rotation=90)
        ax.set_xticks(range(len(rows)))
        ax.set_xticklabels(labels, fontsize=7.5, color=INK)
        ax.set_title(title, loc="left", fontsize=10, color=INK, pad=8)
    fig.suptitle("Site Alpha anti-correlation sweep — what tenant C's opportunity load does to the shared site  ·  cpsat_alpha · seed 424242 · CRN-paired",
                 fontsize=9.5, color=INK, x=0.01, ha="left")
    fig.tight_layout(rect=(0, 0, 1, 0.94))
    fig.savefig(HERE / "anticorrelation_curve.svg", facecolor=SURFACE)
    print("wrote anticorrelation_curve.svg")


if __name__ == "__main__":
    degradation()
    anticorrelation()
