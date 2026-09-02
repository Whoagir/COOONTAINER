"""Bar chart: TD/RTS volume by year + popularity index. For Bloons video essay."""
from pathlib import Path

import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch
import numpy as np

OUT = Path(__file__).with_name("td_rts_axis_chart_peak_2006.png")

YEARS = list(range(1998, 2009))

# Notable TD maps/games counted for the narrative (custom + early Flash/standalone).
# Exact commercial release dates for WC3 customs are fuzzy — clustered by boom year.
TD_COUNT = {
    1998: 0,
    1999: 0,
    2000: 2,   # Turret Defense…
    2001: 2,   # Sunken Defense…
    2002: 3,   # WC3 opens editor wave
    2003: 6,   # TFT + early WC3 TDs
    2004: 10,  # Wintermaul, Green TD, LTW…
    2005: 14,  # Master of Defence + forks
    2006: 22,  # PEAK: Element, Gem, Legion, Maul Wars…
    2007: 12,  # Flash Element, Desktop, Antbuster, Bloons, Onslaught…
    2008: 9,   # GemCraft, Protector, BTD sequels, early retail
}

# RTS titles released that year (Wikipedia chronology of RTS video games).
RTS_COUNT = {
    1998: 46,
    1999: 27,
    2000: 36,
    2001: 44,
    2002: 27,
    2003: 26,
    2004: 37,
    2005: 23,
    2006: 29,
    2007: 28,
    2008: 17,
}

# Relative TD audience/interest index (0–100). Not literal MAU —
# calibrated to known spikes (Desktop TD 15M+ plays mid-2007, Digg Bloons, WC3 lobby peak ~05–06).
POP_INDEX = {
    1998: 5,
    1999: 8,
    2000: 18,
    2001: 25,
    2002: 35,
    2003: 48,
    2004: 62,
    2005: 78,
    2006: 92,  # peak competition / map density
    2007: 100,  # Flash viral absolute audience
    2008: 88,
}

GAMES = {
    2000: ["Turret Defense (SC)"],
    2001: ["Sunken Defense (SC)"],
    2002: ["Warcraft III", "early WC3 TD"],
    2003: ["Frozen Throne", "TFT TD scenario", "early Green/Maul"],
    2004: ["Wintermaul", "Green TD", "Line Tower Wars", "Castle Fight"],
    2005: ["Master of Defence", "YouTD", "Enfos", "больше форков"],
    2006: [
        "Element TD",
        "Gem TD",
        "Legion TD",
        "Wintermaul Wars",
        "Warcraft Maul",
        "+ десятки форков",
    ],
    2007: [
        "Flash Element TD",
        "Desktop TD",
        "Antbuster",
        "Bloons TD",
        "Onslaught 2",
    ],
    2008: ["GemCraft", "Protector", "BTD2/3", "Defense Grid"],
}

td = [TD_COUNT[y] for y in YEARS]
rts = [RTS_COUNT[y] for y in YEARS]
pop = [POP_INDEX[y] for y in YEARS]
x = np.arange(len(YEARS))
w = 0.38

plt.rcParams.update(
    {
        "font.family": "DejaVu Sans",
        "axes.facecolor": "#0f172a",
        "figure.facecolor": "#0b1220",
        "text.color": "#e2e8f0",
        "axes.labelcolor": "#e2e8f0",
        "xtick.color": "#cbd5e1",
        "ytick.color": "#cbd5e1",
        "axes.edgecolor": "#334155",
    }
)

fig, ax = plt.subplots(figsize=(16, 9), dpi=160)
ax2 = ax.twinx()

bars_td = ax.bar(
    x - w / 2,
    td,
    width=w,
    color="#f97316",
    edgecolor="#fdba74",
    linewidth=0.8,
    label="TD: кол-во заметных игр/карт",
    zorder=3,
)
bars_rts = ax.bar(
    x + w / 2,
    [v / 2 for v in rts],  # visual scale: RTS÷2 so TD peak reads clearly
    width=w,
    color="#38bdf8",
    edgecolor="#7dd3fc",
    linewidth=0.8,
    alpha=0.85,
    label="RTS: кол-во релизов (÷2 для масштаба)",
    zorder=2,
)

# True RTS counts as text above blue bars
for i, y in enumerate(YEARS):
    ax.text(
        x[i] + w / 2,
        rts[i] / 2 + 0.6,
        str(rts[i]),
        ha="center",
        va="bottom",
        fontsize=7,
        color="#7dd3fc",
    )
    ax.text(
        x[i] - w / 2,
        td[i] + 0.4,
        str(td[i]),
        ha="center",
        va="bottom",
        fontsize=8,
        fontweight="bold",
        color="#fdba74",
    )

line = ax2.plot(
    x,
    pop,
    color="#a3e635",
    marker="o",
    linewidth=2.5,
    markersize=7,
    label="Индекс популярности / охвата TD",
    zorder=4,
)

ax.set_xticks(x)
ax.set_xticklabels([str(y) for y in YEARS], fontsize=11)
ax.set_xlabel("Год", fontsize=12)
ax.set_ylabel("Количество игр / карт за год", fontsize=12, color="#fdba74")
ax2.set_ylabel("Популярность TD (относительный индекс 0–100)", fontsize=12, color="#a3e635")
ax.set_ylim(0, 28)
ax2.set_ylim(0, 115)
ax.yaxis.label.set_color("#fdba74")
ax2.yaxis.label.set_color("#a3e635")
ax.tick_params(axis="y", colors="#fdba74")
ax2.tick_params(axis="y", colors="#a3e635")
ax.grid(axis="y", color="#1e293b", linewidth=1, zorder=0)

# Peak callout 2006
peak_i = YEARS.index(2006)
ax.annotate(
    "ПИК КОНКУРЕНЦИИ\n«кто хитрее / умнее»",
    xy=(peak_i - w / 2, TD_COUNT[2006]),
    xytext=(peak_i - 1.8, 25),
    fontsize=10,
    fontweight="bold",
    color="#fef08a",
    ha="center",
    arrowprops=dict(arrowstyle="->", color="#fef08a", lw=1.5),
    zorder=5,
)

# Game cards under chart as stacked labels for busy years
card_y = -0.02
fig.text(
    0.5,
    0.965,
    "TD + RTS по годам: сколько выходило и насколько жанр TD был горячим",
    ha="center",
    va="top",
    fontsize=16,
    fontweight="bold",
    color="#f8fafc",
)
fig.text(
    0.5,
    0.925,
    "Цитата ролика: к 2006 рынок TD-кастомок достигает пика · столбцы = кол-во · линия = популярность/охват",
    ha="center",
    va="top",
    fontsize=10,
    color="#94a3b8",
)

# Side legend panel with games per year (cards)
card_ax = fig.add_axes([0.72, 0.12, 0.26, 0.72])
card_ax.set_xlim(0, 1)
card_ax.set_ylim(0, 1)
card_ax.axis("off")
card_ax.set_title("Карточки игр (TD)", fontsize=11, color="#fdba74", pad=8)

yy = 0.98
for year in [2000, 2001, 2002, 2003, 2004, 2005, 2006, 2007, 2008]:
    games = GAMES.get(year, [])
    highlight = year == 2006
    box = FancyBboxPatch(
        (0.02, yy - 0.095),
        0.96,
        0.09,
        boxstyle="round,pad=0.01,rounding_size=0.02",
        linewidth=1.2 if highlight else 0.6,
        edgecolor="#fbbf24" if highlight else "#475569",
        facecolor="#1e293b" if not highlight else "#3b2f14",
    )
    card_ax.add_patch(box)
    card_ax.text(
        0.06,
        yy - 0.025,
        str(year),
        fontsize=8,
        fontweight="bold",
        color="#fbbf24" if highlight else "#94a3b8",
        va="top",
    )
    card_ax.text(
        0.06,
        yy - 0.055,
        " · ".join(games),
        fontsize=6.2,
        color="#e2e8f0",
        va="top",
        wrap=True,
    )
    yy -= 0.105

# Combined legend
h1, l1 = ax.get_legend_handles_labels()
h2, l2 = ax2.get_legend_handles_labels()
ax.legend(h1 + h2, l1 + l2, loc="upper left", frameon=True, facecolor="#1e293b", edgecolor="#334155", fontsize=8)

fig.text(
    0.02,
    0.02,
    "RTS counts: Wikipedia Chronology of RTS. TD counts = заметные карты/хиты (оценка для нарратива). "
    "Индекс популярности относительный (Desktop TD 15M+ plays 2007, WC3 lobby peak ~2005–06).",
    fontsize=7,
    color="#64748b",
)

ax.set_xlim(-0.6, len(YEARS) - 0.2)
plt.subplots_adjust(left=0.07, right=0.70, top=0.88, bottom=0.10)
fig.savefig(OUT, facecolor=fig.get_facecolor())
print(f"Wrote {OUT}")
