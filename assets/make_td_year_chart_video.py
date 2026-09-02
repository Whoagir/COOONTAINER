"""Cleaner full-bleed video chart: X=year, Y=games + popularity line, labels on bars."""
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np

OUT = Path(__file__).with_name("td_rts_axis_chart_for_video.png")

YEARS = list(range(1998, 2009))
TD_COUNT = [0, 0, 2, 2, 3, 6, 10, 14, 22, 12, 9]
RTS_COUNT = [46, 27, 36, 44, 27, 26, 37, 23, 29, 28, 17]
POP = [5, 8, 18, 25, 35, 48, 62, 78, 92, 100, 88]

# Short labels for top of busy bars
LABELS = {
    2000: "Turret Def.",
    2001: "Sunken Def.",
    2002: "WC3",
    2003: "TFT + TD",
    2004: "Wintermaul\nGreen TD\nLTW",
    2005: "Master of\nDefence +\nфорки",
    2006: "Element TD\nGem · Legion\nMaul Wars\n+ форки",
    2007: "Desktop TD\nFlash Element\nBloons TD\nAntbuster",
    2008: "GemCraft\nProtector\nBTD2/3",
}

plt.rcParams.update(
    {
        "font.family": "DejaVu Sans",
        "axes.facecolor": "#0b1220",
        "figure.facecolor": "#070b14",
        "text.color": "#f1f5f9",
        "axes.labelcolor": "#e2e8f0",
        "xtick.color": "#e2e8f0",
        "ytick.color": "#e2e8f0",
        "axes.edgecolor": "#334155",
    }
)

fig, ax = plt.subplots(figsize=(16, 9), dpi=180)
ax2 = ax.twinx()
x = np.arange(len(YEARS))

bars = ax.bar(
    x,
    TD_COUNT,
    width=0.72,
    color=["#f97316" if y != 2006 else "#facc15" for y in YEARS],
    edgecolor="#fff7ed",
    linewidth=0.7,
    zorder=3,
    label="Кол-во заметных TD игр/карт за год",
)

# RTS as faint background stems
ax.bar(
    x,
    [r / 2.5 for r in RTS_COUNT],
    width=0.72,
    color="#0ea5e9",
    alpha=0.22,
    zorder=1,
    label="RTS-релизы (фон, ÷2.5)",
)

ax2.plot(
    x,
    POP,
    color="#a3e635",
    linewidth=3,
    marker="o",
    markersize=8,
    zorder=4,
    label="Популярность / охват TD (индекс)",
)
ax2.fill_between(x, POP, color="#a3e635", alpha=0.08, zorder=1)

for i, y in enumerate(YEARS):
    ax.text(i, TD_COUNT[i] + 0.35, str(TD_COUNT[i]), ha="center", fontsize=11, fontweight="bold", color="#fdba74")
    if y in LABELS and TD_COUNT[i] > 0:
        ax.text(
            i,
            max(TD_COUNT[i] * 0.45, 1.2),
            LABELS[y],
            ha="center",
            va="center",
            fontsize=6.5 if y >= 2004 else 7.5,
            color="#0f172a",
            fontweight="bold",
            linespacing=1.15,
            zorder=5,
        )

ax.axvline(YEARS.index(2006), color="#fde047", ls="--", lw=1.2, alpha=0.7, zorder=2)
ax.text(
    YEARS.index(2006),
    26.2,
    "← ПИК 2006: кто хитрее / умнее",
    ha="center",
    fontsize=12,
    fontweight="bold",
    color="#fde047",
)

ax.set_xticks(x)
ax.set_xticklabels([str(y) for y in YEARS], fontsize=12)
ax.set_xlim(-0.6, len(YEARS) - 0.4)
ax.set_ylim(0, 28)
ax2.set_ylim(0, 115)
ax.set_xlabel("Год →", fontsize=13)
ax.set_ylabel("Ось Y₁: сколько TD-игр/карт вышло", fontsize=12, color="#fb923c")
ax2.set_ylabel("Ось Y₂: популярность / игроки (индекс 0–100)", fontsize=12, color="#a3e635")
ax.tick_params(axis="y", colors="#fb923c")
ax2.tick_params(axis="y", colors="#a3e635")
ax.grid(axis="y", color="#1e293b", lw=1, zorder=0)

fig.suptitle(
    "График жанра: Tower Defense (и фон RTS) по годам",
    fontsize=18,
    fontweight="bold",
    color="white",
    y=0.98,
)
ax.set_title(
    "Столбики = количество · линия = популярность · подписи = какие игры",
    fontsize=11,
    color="#94a3b8",
    pad=10,
)

h1, l1 = ax.get_legend_handles_labels()
h2, l2 = ax2.get_legend_handles_labels()
ax.legend(h1 + h2, l1 + l2, loc="upper left", facecolor="#111827", edgecolor="#334155", fontsize=9)

fig.text(
    0.01,
    0.01,
    "TD counts — оценка заметных кастомок/хитов для нарратива ролика. "
    "Популярность — относительный индекс (не точный MAU). "
    "RTS counts — Wikipedia. Desktop TD: 15M+ plays к сер. 2007.",
    fontsize=7,
    color="#64748b",
)

plt.tight_layout(rect=[0, 0.03, 1, 0.95])
fig.savefig(OUT, facecolor=fig.get_facecolor())
print(f"Wrote {OUT}")
