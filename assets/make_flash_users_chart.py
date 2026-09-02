"""Flash Player users / penetration chart for Bloons video essay."""
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np

OUT_DIR = Path(__file__).resolve().parent
OUT1 = OUT_DIR / "flash_users_chart_2000_2010.png"
OUT2 = OUT_DIR / "flash_users_chart_quote_2007.png"

# Published install-base milestones (millions). Interpolated between known claims.
# Sources: Macromedia/Adobe claims, CGW 2006 (~600M / 98%), Alphr Dec 2008 (~947M / 99%),
# TechTarget (~560M around FP8 / 2005), Wikipedia (~100M by 1999 Shockwave+Flash).
YEARS = list(range(1999, 2012))
INSTALL_M = {
    1999: 100,
    2000: 150,
    2001: 220,
    2002: 300,
    2003: 380,
    2004: 460,
    2005: 560,  # ~560M users / FP8 era
    2006: 620,  # Adobe: 600M+ desktops, 98%
    2007: 780,  # growing toward 1B + Flash games/video boom
    2008: 947,  # Adobe/Millward Brown Dec 2008
    2009: 980,
    2010: 1000,  # ~1B peak claims
    2011: 1000,
}

# Penetration of internet-connected desktops in mature markets (%)
PENETRATION = {
    1999: 70,
    2000: 78,
    2001: 84,
    2002: 88,
    2003: 92,
    2004: 95,
    2005: 97,
    2006: 98,
    2007: 98.5,
    2008: 99.0,
    2009: 99.0,
    2010: 99.0,
    2011: 98.5,
}

# Cultural / usage heat index (relative) — games, video sites, portals
HYPE = {
    1999: 20,
    2000: 28,
    2001: 35,
    2002: 42,
    2003: 50,
    2004: 58,
    2005: 68,  # FP8 video + Adobe buys Macromedia
    2006: 82,  # YouTube Flash video mainstream
    2007: 100,  # Digg / Flash games / Desktop TD / Bloons — «в небеса»
    2008: 95,
    2009: 88,
    2010: 75,  # Jobs letter / iPhone no Flash starts pressure
    2011: 55,
}


def style():
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


def make_main():
    style()
    years = YEARS
    x = np.arange(len(years))
    installs = [INSTALL_M[y] for y in years]
    pen = [PENETRATION[y] for y in years]
    hype = [HYPE[y] for y in years]

    fig, ax = plt.subplots(figsize=(16, 9), dpi=180)
    ax2 = ax.twinx()

    bars = ax.bar(
        x,
        installs,
        width=0.7,
        color=["#f59e0b" if y == 2007 else "#38bdf8" for y in years],
        edgecolor="#e0f2fe",
        linewidth=0.6,
        zorder=3,
        label="Установки Flash Player (млн ПК)",
    )
    for i, y in enumerate(years):
        ax.text(
            i,
            installs[i] + 18,
            f"{installs[i]}",
            ha="center",
            fontsize=8,
            color="#7dd3fc" if y != 2007 else "#fde68a",
            fontweight="bold",
        )

    ax2.plot(
        x,
        pen,
        color="#a3e635",
        lw=2.8,
        marker="o",
        ms=6,
        zorder=4,
        label="Проникновение на десктопах (%)",
    )
    ax2.plot(
        x,
        hype,
        color="#f472b6",
        lw=2.4,
        marker="s",
        ms=5,
        ls="--",
        zorder=4,
        label="Хайп контента / Flash-игры (индекс)",
    )

    # Quote zone 2006-2007
    i06, i07 = years.index(2006), years.index(2007)
    ax.axvspan(i06 - 0.4, i07 + 0.4, color="#f59e0b", alpha=0.12, zorder=1)
    ax.annotate(
        "2006–07: уже ~98% ПК,\nно база и хайп ещё летят вверх",
        xy=(i07, INSTALL_M[2007]),
        xytext=(i07 - 2.2, 880),
        fontsize=11,
        fontweight="bold",
        color="#fde68a",
        ha="center",
        arrowprops=dict(arrowstyle="->", color="#fde68a", lw=1.6),
        zorder=5,
    )

    ax.set_xticks(x)
    ax.set_xticklabels([str(y) for y in years], fontsize=11)
    ax.set_xlim(-0.6, len(years) - 0.4)
    ax.set_ylim(0, 1150)
    ax2.set_ylim(0, 110)
    ax.set_xlabel("Год →", fontsize=13)
    ax.set_ylabel("Ось Y₁: пользователи / установки (млн)", fontsize=12, color="#38bdf8")
    ax2.set_ylabel("Ось Y₂: % проникновения и индекс хайпа", fontsize=12, color="#a3e635")
    ax.tick_params(axis="y", colors="#38bdf8")
    ax2.tick_params(axis="y", colors="#a3e635")
    ax.grid(axis="y", color="#1e293b", lw=1, zorder=0)

    fig.suptitle(
        "Adobe / Macromedia Flash Player: сколько людей и насколько «везде»",
        fontsize=17,
        fontweight="bold",
        color="white",
        y=0.98,
    )
    ax.set_title(
        "Столбики = установка на ПК · зелёная линия = % десктопов · розовая = культурный хайп (игры/видео)",
        fontsize=10,
        color="#94a3b8",
        pad=8,
    )

    h1, l1 = ax.get_legend_handles_labels()
    h2, l2 = ax2.get_legend_handles_labels()
    ax.legend(h1 + h2, l1 + l2, loc="upper left", facecolor="#111827", edgecolor="#334155", fontsize=9)

    fig.text(
        0.01,
        0.012,
        "Источники (публичные заявления): ~100M к 1999; ~560M ~2005; 600M+/98% ~2006 (Adobe/CGW); "
        "~947M/99% Dec 2008 (Adobe/Millward Brown). Промежуточные годы — интерполяция. "
        "Индекс хайпа — нарративный (YouTube Flash, Digg, Flash-игры 2007).",
        fontsize=6.5,
        color="#64748b",
    )
    plt.tight_layout(rect=[0, 0.035, 1, 0.95])
    fig.savefig(OUT1, facecolor=fig.get_facecolor())
    print("Wrote", OUT1)


def make_quote_focus():
    """Simpler chart focused on the voiceover beat."""
    style()
    years = list(range(2003, 2011))
    x = np.arange(len(years))
    installs = [INSTALL_M[y] for y in years]
    pen = [PENETRATION[y] for y in years]

    fig, ax = plt.subplots(figsize=(16, 9), dpi=180)
    ax2 = ax.twinx()

    ax.fill_between(x, installs, color="#38bdf8", alpha=0.35, zorder=2)
    ax.plot(x, installs, color="#38bdf8", lw=3.5, marker="o", ms=9, zorder=3, label="Установки, млн")
    ax2.plot(x, pen, color="#a3e635", lw=3, marker="D", ms=7, zorder=3, label="% проникновения")

    for i, y in enumerate(years):
        ax.text(i, installs[i] + 25, f"{installs[i]}M", ha="center", fontsize=10, fontweight="bold", color="#7dd3fc")
        ax2.text(i, pen[i] - 3.5, f"{pen[i]}%", ha="center", fontsize=8, color="#bef264")

    i07 = years.index(2007)
    ax.axvline(i07, color="#f59e0b", ls="--", lw=2, alpha=0.9)
    ax.annotate(
        "«Уже на пике популярности,\nно разгоняется в небеса»",
        xy=(i07, INSTALL_M[2007]),
        xytext=(i07 + 0.35, 550),
        fontsize=13,
        fontweight="bold",
        color="#fde68a",
        arrowprops=dict(arrowstyle="->", color="#fde68a", lw=2),
    )
    # Explain both axes of the quote
    ax.text(
        0.02,
        0.97,
        "Пик % уже был (зелёная линия почти потолок)\n"
        "«Небеса» = рост абсолютной базы + взрыв Flash-контента/игр",
        transform=ax.transAxes,
        va="top",
        fontsize=11,
        color="#e2e8f0",
        bbox=dict(boxstyle="round,pad=0.4", facecolor="#1e293b", edgecolor="#475569"),
    )

    milestones = {
        2005: "Adobe\nпокупает\nMacromedia",
        2006: "YouTube\nна Flash",
        2007: "Digg +\nFlash-игры\nBloons/DTD",
        2008: "~1 млрд\nна горизонте",
    }
    for y, txt in milestones.items():
        i = years.index(y)
        ax.text(i, 180, txt, ha="center", va="bottom", fontsize=8, color="#fbbf24", linespacing=1.2)

    ax.set_xticks(x)
    ax.set_xticklabels([str(y) for y in years], fontsize=12)
    ax.set_ylim(0, 1150)
    ax2.set_ylim(90, 100.5)
    ax.set_xlabel("Год →", fontsize=13)
    ax.set_ylabel("Пользователи Flash Player (млн)", fontsize=12, color="#38bdf8")
    ax2.set_ylabel("Проникновение на интернет-ПК (%)", fontsize=12, color="#a3e635")
    ax.tick_params(axis="y", colors="#38bdf8")
    ax2.tick_params(axis="y", colors="#a3e635")
    ax.grid(axis="y", color="#1e293b", lw=1)

    fig.suptitle(
        "Почему 2007 — год Flash: база уже везде, а хайп только разгоняется",
        fontsize=16,
        fontweight="bold",
        color="white",
        y=0.97,
    )

    h1, l1 = ax.get_legend_handles_labels()
    h2, l2 = ax2.get_legend_handles_labels()
    ax.legend(h1 + h2, l1 + l2, loc="lower right", facecolor="#111827", edgecolor="#334155", fontsize=10)

    fig.text(
        0.01,
        0.01,
        "Цифры — публичные оценки Adobe/Macromedia (не аудитория одной игры). "
        "2006: 600M+/98%. 2008: ~947M/99%. 2007 выделен под озвучку ролика.",
        fontsize=7,
        color="#64748b",
    )
    plt.tight_layout(rect=[0, 0.03, 1, 0.94])
    fig.savefig(OUT2, facecolor=fig.get_facecolor())
    print("Wrote", OUT2)


if __name__ == "__main__":
    make_main()
    make_quote_focus()
