#!/usr/bin/env python3
"""Append wave3 archetypes + ~100 items, regenerate .tres.

  C:\\Users\\user\\AppData\\Local\\Python\\bin\\python.exe tools/content/append_wave3.py
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ARCH = ROOT / "tools" / "content" / "archetypes.csv"
ITEMS_CSV = ROOT / "tools" / "content" / "items.csv"
MARKER = "# ==== WAVE3 storage finds"

# CSV columns for items
COLS = [
    "id", "name_ru", "name_en", "archetype_id", "facets", "value_base",
    "mass_override", "liquid_id", "liquid_amount", "flammable", "illegal",
    "dusty_default", "nest_loot", "vendor_affinity", "wearable_slot",
    "break_threshold", "color", "scale", "tags", "lore_ru", "lore_en",
]

ARCH_ROWS = """
# ==== WAVE3 storage finds (procedural builders in ArchetypeMeshes)
toaster,toaster,ONE_HAND,0.28,0.18,0.18,1.8,5,0,3,0,0,c0c4c8,888888,0.7,0.05
blender,blender,ONE_HAND,0.2,0.4,0.2,2.2,5,0,3,0,0,222222,a0c8e0,0.7,0.05
coffee_maker,coffee_maker,ONE_HAND,0.28,0.35,0.22,2.5,4,0,3,0,0,101018,c0c0c8,0.8,0.02
snowglobe,snowglobe,POCKET,0.12,0.16,0.12,0.4,6,0,3,0,0,8a6a40,d0e8f8,0.5,0.05
vinyl,vinyl,ONE_HAND,0.3,0.02,0.3,0.25,3,0,3,0,0,e03030,101010,0.6,0.02
turntable,turntable,TWO_HAND,0.45,0.12,0.4,4.5,4,0,3,0,0,1a1a1a,c0a040,0.8,0.02
accordion,accordion,TWO_HAND,0.45,0.35,0.22,6.0,4,0,3,0,0,a02020,e8d0a0,0.8,0.02
harmonica,harmonica,POCKET,0.12,0.03,0.04,0.15,3,0,3,0,0,c0c0c8,222222,0.7,0.05
microscope,microscope,ONE_HAND,0.18,0.35,0.22,2.8,4,0,3,0,0,303038,a0a0a8,0.8,0.02
telescope,telescope,TWO_HAND,0.18,0.25,0.7,3.5,4,0,3,0,0,2a2a30,8a6a40,0.7,0.05
hairdryer,hairdryer,ONE_HAND,0.14,0.2,0.28,0.7,4,0,3,0,0,f0a0c0,333333,0.7,0.05
clothes_iron,clothes_iron,ONE_HAND,0.28,0.14,0.14,1.6,4,0,3,0,0,7090b0,333333,0.8,0.02
waffle_maker,waffle_maker,ONE_HAND,0.28,0.14,0.28,2.4,4,0,3,0,0,c03030,222222,0.8,0.02
juicer,juicer,ONE_HAND,0.2,0.28,0.2,1.8,5,0,3,0,0,f0f0f0,ff8020,0.7,0.05
gramophone,gramophone,TWO_HAND,0.4,0.45,0.4,8.0,5,0,3,0,0,6a4a28,c0a040,0.8,0.02
cash_register,cash_register,TWO_HAND,0.4,0.35,0.35,12.0,4,1,2,0,0,c02020,222222,0.9,0.0
abacus,abacus,ONE_HAND,0.35,0.22,0.08,0.8,4,0,3,0,0,8a5a30,d03030,0.7,0.05
hourglass,hourglass,ONE_HAND,0.12,0.28,0.12,0.5,6,0,3,0,0,6a4a28,e8d8a0,0.5,0.05
bowling_pin,bowling_pin,ONE_HAND,0.12,0.38,0.12,1.4,5,0,3,0,0,f0f0ee,d03030,0.6,0.1
helmet,helmet,ONE_HAND,0.28,0.22,0.28,1.2,4,0,3,0,0,2030a0,c0c0c0,0.8,0.05
megaphone,megaphone,ONE_HAND,0.22,0.18,0.4,1.0,4,0,3,0,0,f0a020,222222,0.7,0.05
aquarium,aquarium,TWO_HAND,0.55,0.35,0.3,6.0,7,0,3,0,0,404048,a0d0f0,0.5,0.02
rubber_duck,rubber_duck,POCKET,0.12,0.12,0.14,0.15,3,0,3,0,0,f0d020,f08020,0.8,0.15
lava_lamp,lava_lamp,ONE_HAND,0.14,0.4,0.14,1.1,5,0,3,0,1,303038,f040a0,0.6,0.05
crystal_ball,crystal_ball,ONE_HAND,0.18,0.22,0.18,1.0,6,0,3,0,0,6a4a28,d0e8f8,0.5,0.05
""".strip()


def I(iid, ru, en, arch, facets="", value=10, mass="", liquid="", liquid_amt="",
      flammable="", illegal="", dusty="", nest="", vendors="", wear="", brk="",
      color="", scale="", tags="", lore_ru="", lore_en="") -> dict:
    return {
        "id": iid, "name_ru": ru, "name_en": en, "archetype_id": arch, "facets": facets,
        "value_base": str(value), "mass_override": str(mass), "liquid_id": liquid,
        "liquid_amount": str(liquid_amt), "flammable": str(flammable), "illegal": str(illegal),
        "dusty_default": str(dusty), "nest_loot": nest, "vendor_affinity": vendors,
        "wearable_slot": wear, "break_threshold": str(brk), "color": color, "scale": str(scale),
        "tags": tags, "lore_ru": lore_ru, "lore_en": lore_en,
    }


ITEMS: list[dict] = [
    I("toaster_chrome", "Тостер хромированный", "Chrome Toaster", "toaster", "DIRTYABLE", 18, dusty=0.2, vendors="household", color="c8d0d8", tags="appliance",
      lore_ru="Жрёт вилки. Хлеб опционален.", lore_en="Eats forks. Bread optional."),
    I("toaster_burnt", "Тостер подгоревший", "Burnt Toaster", "toaster", "DIRTYABLE", 4, flammable=1, dusty=0.6, vendors="tiny", color="4a3030", tags="appliance",
      lore_ru="Пахнет как 1998-й.", lore_en="Smells like 1998."),
    I("toaster_jammed", "Тостер с застрявшим", "Jammed Toaster", "toaster", "DIRTYABLE|SHAKE_OUT", 12, flammable=1, dusty=0.3, nest="cash_5:0.35:1:1", vendors="household", color="a0a8b0", tags="appliance",
      lore_ru="Внутри что-то звенит. Надежда.", lore_en="Something rattles. Hope."),
    I("blender_kitchen", "Блендер кухонный", "Kitchen Blender", "blender", "FRAGILE|DIRTYABLE", 28, dusty=0.25, vendors="household", brk=4.8, color="222228", tags="appliance",
      lore_ru="Крышка есть. Инструкция — нет.", lore_en="Lid included. Manual not."),
    I("blender_mold", "Блендер с плесенью", "Moldy Blender", "blender", "FRAGILE|DIRTYABLE", 3, flammable=1, dusty=0.85, vendors="tiny", brk=4.2, color="204028", tags="appliance",
      lore_ru="Научный эксперимент.", lore_en="A science experiment."),
    I("blender_smoothie", "Блендер смузи-могила", "Smoothie Grave Blender", "blender", "FRAGILE|LIQUID", 8, liquid="water", liquid_amt=0.4, dusty=0.4, vendors="household", brk=4.0, color="303840", tags="appliance",
      lore_ru="Содержимое не идентифицировано.", lore_en="Contents not identified."),
    I("coffee_drip", "Кофеварка капельная", "Drip Coffee Maker", "coffee_maker", "DIRTYABLE|LIQUID", 22, liquid="water", liquid_amt=0.2, dusty=0.35, vendors="household", color="1a1a22", tags="appliance",
      lore_ru="Варит обиду и кофе.", lore_en="Brews resentment and coffee."),
    I("coffee_espresso_toy", "Эспрессо «как в баре»", "Toy Espresso Machine", "coffee_maker", "DIRTYABLE", 35, dusty=0.15, vendors="household|antique", color="e8e8f0", scale=0.85, tags="appliance",
      lore_ru="Пар есть. Давления нет.", lore_en="Steam yes. Pressure no."),
    I("coffee_army", "Кофеварка армейская", "Army Percolator", "coffee_maker", "DIRTYABLE", 16, dusty=0.45, vendors="tiny|household", color="3a4a30", tags="appliance",
      lore_ru="Переживёт ядерную зиму.", lore_en="Survives nuclear winter."),
    I("snowglobe_vegas", "Шар «Вегас»", "Vegas Snowglobe", "snowglobe", "FRAGILE", 40, dusty=0.1, vendors="antique|tiny", brk=3.2, color="8a6a40", tags="fragile|souvenir",
      lore_ru="Снег из микропластика.", lore_en="Snow is microplastic."),
    I("snowglobe_hamster", "Шар с хомяком", "Hamster Snowglobe", "snowglobe", "FRAGILE", 55, dusty=0.05, vendors="antique", brk=3.0, color="a08050", tags="fragile|hamster|souvenir",
      lore_ru="Хомяк машет. Или тонет.", lore_en="Hamster waves. Or drowns."),
    I("snowglobe_divorce", "Шар «наш дом»", "Our House Snowglobe", "snowglobe", "FRAGILE", 15, dusty=0.2, vendors="tiny", brk=3.0, color="6a4a28", tags="fragile|souvenir",
      lore_ru="Дом разломан пополам. Метафора.", lore_en="House split in half. Metaphor."),
    I("vinyl_bootleg", "Пластинка пиратская", "Bootleg Vinyl", "vinyl", "FRAGILE", 45, dusty=0.15, vendors="antique|tech", brk=5.0, color="c02828", tags="music",
      lore_ru="Сторона Б — тишина и шипение.", lore_en="Side B is hiss and silence."),
    I("vinyl_wedding", "Пластинка свадебная", "Wedding Vinyl", "vinyl", "FRAGILE", 25, dusty=0.2, vendors="antique", brk=5.0, color="e8e0d0", tags="music",
      lore_ru="Первый танец. Последний раз.", lore_en="First dance. Last time."),
    I("vinyl_blank", "Пластинка пустая", "Blank Vinyl", "vinyl", "FRAGILE", 8, dusty=0.1, vendors="tiny", brk=5.5, color="101010", tags="music",
      lore_ru="Можно нацарапать судьбу.", lore_en="Scratch your own destiny."),
    I("turntable_dj", "Вертушка диджея", "DJ Turntable", "turntable", "DIRTYABLE|FRAGILE", 180, dusty=0.25, vendors="tech|antique", brk=6.0, color="151515", tags="music|electronics",
      lore_ru="Игла гнутая. Душа — нет.", lore_en="Bent needle. Soul intact."),
    I("turntable_suitcase", "Вертушка-чемодан", "Suitcase Turntable", "turntable", "DIRTYABLE|FRAGILE|CONTAINER", 95, dusty=0.3, nest="vinyl_bootleg:0.5:1:1", vendors="tech", brk=6.5, color="6a4a28", tags="music|electronics",
      lore_ru="Портативное разочарование.", lore_en="Portable disappointment."),
    I("turntable_dead", "Вертушка мёртвая", "Dead Turntable", "turntable", "DIRTYABLE", 20, dusty=0.5, vendors="tiny|tech", brk=8.0, color="222222", tags="music|electronics",
      lore_ru="Крутится только от руки.", lore_en="Hand-crank only now."),
    I("accordion_soviet", "Баян советский", "Soviet Accordion", "accordion", "DIRTYABLE", 120, dusty=0.4, vendors="antique", color="a01818", tags="music",
      lore_ru="Орёт «Калинку» сам.", lore_en="Plays Kalinka unprompted."),
    I("accordion_kids", "Гармошка детская", "Kids Accordion", "accordion", "", 18, dusty=0.2, vendors="tiny", color="3080d0", scale=0.7, tags="music",
      lore_ru="Три кнопки. Все фальшивят.", lore_en="Three buttons. All flat."),
    I("accordion_wheezy", "Баян с астмой", "Wheezy Accordion", "accordion", "DIRTYABLE", 35, dusty=0.55, vendors="antique", color="702020", tags="music",
      lore_ru="Вдох длиннее выдоха.", lore_en="Inhale longer than exhale."),
    I("harmonica_blues", "Губная гармошка", "Blues Harmonica", "harmonica", "", 22, dusty=0.15, vendors="antique|tiny", color="c0c8d0", tags="music",
      lore_ru="Вкус чужих губ.", lore_en="Tastes like other mouths."),
    I("harmonica_rusty", "Гармошка ржавая", "Rusty Harmonica", "harmonica", "DIRTYABLE", 4, dusty=0.7, vendors="tiny", color="8a6040", tags="music",
      lore_ru="Ноты со скрипом.", lore_en="Notes with rust."),
    I("harmonica_gold", "Гармошка «золото»", "Gold Harmonica", "harmonica", "", 80, dusty=0.05, vendors="antique", color="e0c040", tags="music",
      lore_ru="Позолота слезает на язык.", lore_en="Gold leaf on your tongue."),
    I("microscope_school", "Микроскоп школьный", "School Microscope", "microscope", "FRAGILE|DIRTYABLE", 55, dusty=0.35, vendors="tech|household", brk=5.5, color="303040", tags="science",
      lore_ru="Увеличение ×ложь.", lore_en="Magnification ×lie."),
    I("microscope_spy", "Микроскоп шпиона", "Spy Microscope", "microscope", "FRAGILE", 140, dusty=0.1, vendors="tech|dark", brk=5.0, color="1a1a22", tags="science",
      lore_ru="Смотрит в душу и в пыль.", lore_en="Sees soul and dust."),
    I("microscope_toy", "Микроскоп игрушечный", "Toy Microscope", "microscope", "FRAGILE", 12, dusty=0.15, vendors="tiny", brk=4.5, color="e03030", scale=0.75, tags="science",
      lore_ru="Линза — бутылочное стекло.", lore_en="Lens is bottle glass."),
    I("telescope_pirate", "Подзорная труба", "Pirate Spyglass", "telescope", "FRAGILE", 90, dusty=0.3, vendors="antique", brk=5.5, color="2a2a30", tags="science|souvenir",
      lore_ru="Видит только долги.", lore_en="Only sees debts."),
    I("telescope_kids", "Телескоп детский", "Kids Telescope", "telescope", "FRAGILE", 20, dusty=0.2, vendors="tiny", brk=5.0, color="d03030", scale=0.8, tags="science",
      lore_ru="Луна размером с горошину.", lore_en="Moon is pea-sized."),
    I("telescope_broken", "Телескоп без линзы", "Lensless Telescope", "telescope", "DIRTYABLE", 8, dusty=0.5, vendors="tiny", brk=12.0, color="404048", tags="science",
      lore_ru="Отличная труба.", lore_en="Excellent tube."),
    I("hairdryer_salon", "Фен салонный", "Salon Hairdryer", "hairdryer", "DIRTYABLE", 30, dusty=0.2, vendors="household", color="f0a0c0", tags="appliance",
      lore_ru="Сушит нервы быстрее волос.", lore_en="Dries nerves first."),
    I("hairdryer_pink", "Фен розовый", "Pink Hairdryer", "hairdryer", "", 14, dusty=0.15, vendors="tiny", color="f060a0", tags="appliance",
      lore_ru="Шнур короче мечты.", lore_en="Cord shorter than dreams."),
    I("hairdryer_dead", "Фен сгоревший", "Dead Hairdryer", "hairdryer", "DIRTYABLE", 2, flammable=1, dusty=0.6, vendors="tiny", color="505050", tags="appliance",
      lore_ru="Пахнет озоном и поражением.", lore_en="Smells of ozone and loss."),
    I("iron_steam", "Утюг паровой", "Steam Iron", "clothes_iron", "DIRTYABLE|LIQUID", 24, liquid="water", liquid_amt=0.3, dusty=0.25, vendors="household", color="7090b0", tags="appliance",
      lore_ru="Пар есть. Подошва дырявая.", lore_en="Steam yes. Soleplate holey."),
    I("iron_soviet", "Утюг советский", "Soviet Iron", "clothes_iron", "HEAVY_CHEAP|DIRTYABLE", 18, dusty=0.4, vendors="household", color="4a6080", tags="appliance",
      lore_ru="Весит как правда.", lore_en="Weighs like truth."),
    I("iron_burn", "Утюг с клеймом", "Branded Iron", "clothes_iron", "DIRTYABLE", 10, dusty=0.5, vendors="tiny", color="606870", tags="appliance",
      lore_ru="Отпечаток «МАМА» на всём.", lore_en="Leaves MOM on everything."),
    I("waffle_heart", "Вафельница сердца", "Heart Waffle Maker", "waffle_maker", "DIRTYABLE", 32, dusty=0.3, vendors="household", color="c02828", tags="appliance",
      lore_ru="Сердечки с пригаром.", lore_en="Hearts with burn marks."),
    I("waffle_greasy", "Вафельница жирная", "Greasy Waffle Iron", "waffle_maker", "DIRTYABLE", 6, flammable=1, dusty=0.8, vendors="tiny", color="5a3030", tags="appliance",
      lore_ru="Не моется с 2004-го.", lore_en="Unwashed since 2004."),
    I("waffle_broken", "Вафельница клинит", "Seized Waffle Maker", "waffle_maker", "DIRTYABLE", 5, dusty=0.45, vendors="tiny", color="802020", tags="appliance",
      lore_ru="Открывается ломом.", lore_en="Opens with a crowbar."),
    I("juicer_citrus", "Соковыжималка", "Citrus Juicer", "juicer", "FRAGILE|DIRTYABLE", 28, dusty=0.3, vendors="household", brk=4.8, color="f0f0f0", tags="appliance",
      lore_ru="Выжимает апельсины и бюджет.", lore_en="Juices oranges and budgets."),
    I("juicer_manual", "Соковыжималка ручная", "Manual Juicer", "juicer", "FRAGILE", 16, dusty=0.2, vendors="household", brk=5.0, color="e8e0d0", tags="appliance",
      lore_ru="Рука устаёт раньше сока.", lore_en="Arm dies before juice."),
    I("juicer_bloody", "Соковыжималка «томаты»", "Tomato Juicer", "juicer", "FRAGILE|LIQUID|DIRTYABLE", 9, liquid="water", liquid_amt=0.5, dusty=0.55, vendors="tiny", brk=4.5, color="802020", tags="appliance",
      lore_ru="Надеемся что томаты.", lore_en="Hoping it's tomatoes."),
    I("gramophone_antique", "Граммофон антик", "Antique Gramophone", "gramophone", "FRAGILE|DIRTYABLE", 420, dusty=0.35, vendors="antique", brk=5.5, color="6a4a28", tags="music|fragile",
      lore_ru="Играет тоску на 78 оборотах.", lore_en="Plays longing at 78 rpm."),
    I("gramophone_plastic", "Граммофон пластик", "Plastic Gramophone", "gramophone", "FRAGILE", 40, dusty=0.15, vendors="tiny|antique", brk=4.5, color="c03030", scale=0.85, tags="music",
      lore_ru="Раструб клееный скотчем.", lore_en="Horn held by tape."),
    I("gramophone_horn", "Раструб без тела", "Horn Only", "gramophone", "FRAGILE|DIRTYABLE", 25, dusty=0.4, vendors="antique", brk=4.0, color="c0a040", scale=0.7, tags="music",
      lore_ru="Музыка воображаемая.", lore_en="Imaginary music."),
    I("register_diner", "Касса забегаловки", "Diner Register", "cash_register", "CONTAINER|DIRTYABLE|HEAVY_EXPENSIVE", 160, dusty=0.4, nest="cash_20:0.4:1:2|cash_5:0.6:1:3", vendors="household|antique", color="c01818", tags="appliance",
      lore_ru="Ящик заедает на «нет сдачи».", lore_en="Drawer jams on no change."),
    I("register_toy", "Касса игрушечная", "Toy Cash Register", "cash_register", "CONTAINER", 22, dusty=0.1, nest="cash_1:0.5:1:5", vendors="tiny", color="e03030", scale=0.65, tags="appliance",
      lore_ru="Монеты деревянные.", lore_en="Coins are wood."),
    I("register_stuck", "Касса заклинило", "Stuck Register", "cash_register", "CONTAINER|DIRTYABLE|LOCKED", 45, dusty=0.5, nest="cash_50:0.25:1:1", vendors="household|dark", color="801010", tags="appliance",
      lore_ru="Открывается только гневом.", lore_en="Opens only with rage."),
    I("abacus_school", "Счёты школьные", "School Abacus", "abacus", "", 18, dusty=0.25, vendors="tiny|household", color="8a5a30", tags="science",
      lore_ru="Считает до вранья.", lore_en="Counts until the lie."),
    I("abacus_gold_bead", "Счёты с «золотом»", "Gold-Bead Abacus", "abacus", "", 75, dusty=0.1, vendors="antique", color="c0a040", tags="science",
      lore_ru="Бусины крашеные.", lore_en="Beads are paint."),
    I("abacus_broken", "Счёты без бусин", "Beadless Abacus", "abacus", "DIRTYABLE", 3, dusty=0.4, vendors="tiny", color="6a4a28", tags="science",
      lore_ru="Считает ноль идеально.", lore_en="Counts zero perfectly."),
    I("hourglass_desk", "Песочные часы", "Desk Hourglass", "hourglass", "FRAGILE", 35, dusty=0.15, vendors="antique|household", brk=3.5, color="6a4a28", tags="fragile|souvenir",
      lore_ru="Песок кончился раньше срока.", lore_en="Sand quit early."),
    I("hourglass_giant", "Часы гигантские", "Giant Hourglass", "hourglass", "FRAGILE", 90, dusty=0.2, vendors="antique", brk=3.2, color="5a3a20", scale=1.6, tags="fragile",
      lore_ru="Нести вдвоём или никак.", lore_en="Carry together or not."),
    I("hourglass_empty", "Часы пустые", "Empty Hourglass", "hourglass", "FRAGILE", 12, dusty=0.25, vendors="tiny", brk=3.8, color="7a5a30", tags="fragile",
      lore_ru="Время украли.", lore_en="Time was stolen."),
    I("pin_lone", "Кегля одинокая", "Lone Bowling Pin", "bowling_pin", "FRAGILE", 14, dusty=0.2, vendors="tiny", brk=5.0, color="f0f0ee", tags="sport",
      lore_ru="Пара из десяти потеряна.", lore_en="Nine siblings missing."),
    I("pin_signed", "Кегля с автографом", "Signed Bowling Pin", "bowling_pin", "FRAGILE", 85, dusty=0.1, vendors="antique", brk=5.0, color="f8f8f0", tags="sport",
      lore_ru="Подпись нечитаемая. Ценнее.", lore_en="Illegible sig. Worth more."),
    I("pin_cracked", "Кегля треснутая", "Cracked Bowling Pin", "bowling_pin", "FRAGILE|DIRTYABLE", 5, dusty=0.45, vendors="tiny", brk=3.5, color="e0e0d8", tags="sport|fragile",
      lore_ru="Уже почти осколки.", lore_en="Already almost shards."),
    I("helmet_bike", "Шлем велосипедный", "Bike Helmet", "helmet", "WEARABLE|DIRTYABLE", 20, dusty=0.3, vendors="tiny", color="2030a0", wear="body", tags="wear",
      lore_ru="Трещины — это стиль.", lore_en="Cracks are style."),
    I("helmet_army_prop", "Каска бутафорская", "Prop Army Helmet", "helmet", "WEARABLE|DIRTYABLE", 30, dusty=0.35, vendors="antique|tiny", color="3a4a30", wear="body", tags="wear",
      lore_ru="Не держит пулю. Держит пыль.", lore_en="Stops dust not bullets."),
    I("helmet_football", "Шлем футбольный", "Football Helmet", "helmet", "WEARABLE|DIRTYABLE", 45, dusty=0.4, vendors="tiny", color="802020", wear="body", tags="wear",
      lore_ru="Запах раздевалки 1987.", lore_en="Locker room 1987."),
    I("megaphone_rally", "Мегафон митинга", "Rally Megaphone", "megaphone", "DIRTYABLE", 40, dusty=0.25, vendors="tiny|household", color="f0a020", tags="appliance",
      lore_ru="Всё ещё орёт лозунги.", lore_en="Still screaming slogans."),
    I("megaphone_kids", "Мегафон детский", "Kids Megaphone", "megaphone", "", 12, dusty=0.1, vendors="tiny", color="3080e0", scale=0.75, tags="appliance",
      lore_ru="Громкость — соседи ненавидят.", lore_en="Volume: neighbors hate you."),
    I("megaphone_broken", "Мегафон без рупора", "Broken Megaphone", "megaphone", "DIRTYABLE", 4, dusty=0.5, vendors="tiny", color="a07020", tags="appliance",
      lore_ru="Шёпот усиленный.", lore_en="Amplified whisper."),
    I("aquarium_empty", "Аквариум пустой", "Empty Aquarium", "aquarium", "FRAGILE|DIRTYABLE", 55, dusty=0.4, vendors="household", brk=3.8, color="404048", tags="fragile|pet",
      lore_ru="Гравий помнит рыбок.", lore_en="Gravel remembers fish."),
    I("aquarium_gravel", "Аквариум с гравием", "Gravel Aquarium", "aquarium", "FRAGILE|DIRTYABLE|SHAKE_OUT", 40, dusty=0.5, nest="cash_1:0.3:1:3", vendors="household", brk=3.8, color="505058", tags="fragile|pet",
      lore_ru="В гравии сюрпризы.", lore_en="Surprises in the gravel."),
    I("aquarium_cracked", "Аквариум треснутый", "Cracked Aquarium", "aquarium", "FRAGILE|DIRTYABLE|LIQUID", 15, liquid="water", liquid_amt=0.3, dusty=0.55, vendors="tiny", brk=2.8, color="384048", tags="fragile|pet",
      lore_ru="Течёт. Как и жизнь хозяина.", lore_en="Leaks. Like the owner."),
    I("duck_yellow", "Утка жёлтая", "Yellow Rubber Duck", "rubber_duck", "", 6, dusty=0.05, vendors="tiny", color="f0d020", tags="toy|gag",
      lore_ru="Пищит обвиняюще.", lore_en="Squeaks accusingly."),
    I("duck_army", "Утка в каске", "Army Duck", "rubber_duck", "", 18, dusty=0.1, vendors="tiny", color="3a5a30", tags="toy|gag",
      lore_ru="Готова к ванной войне.", lore_en="Ready for tub war."),
    I("duck_cursed", "Утка проклятая", "Cursed Duck", "rubber_duck", "", 33, dusty=0.15, vendors="dark|tiny", color="806020", tags="toy|gag",
      lore_ru="Глаза следят в темноте.", lore_en="Eyes follow in the dark."),
    I("lava_pink", "Лавовая лампа", "Pink Lava Lamp", "lava_lamp", "FRAGILE|DIRTYABLE", 70, dusty=0.2, vendors="antique|tech", brk=4.0, color="303038", tags="fragile|light",
      lore_ru="Пузыри ленивые как хозяин.", lore_en="Blobs lazy as the owner."),
    I("lava_dead", "Лавовая лампа мёртвая", "Dead Lava Lamp", "lava_lamp", "FRAGILE|DIRTYABLE", 12, dusty=0.45, vendors="tiny", brk=4.5, color="202028", tags="fragile|light",
      lore_ru="Лава застыла навсегда.", lore_en="Lava froze forever."),
    I("lava_party", "Лавовая лампа диско", "Disco Lava Lamp", "lava_lamp", "FRAGILE", 95, dusty=0.15, vendors="tech|antique", brk=3.8, color="201828", tags="fragile|light",
      lore_ru="Мигает в такт долгам.", lore_en="Pulses to your debt."),
    I("crystal_fortune", "Шар гадалки", "Fortune Crystal Ball", "crystal_ball", "FRAGILE", 110, dusty=0.2, vendors="antique|dark", brk=3.2, color="6a4a28", tags="fragile|gag",
      lore_ru="Показывает только прошлое.", lore_en="Only shows the past."),
    I("crystal_clear", "Шар пустой", "Clear Crystal Ball", "crystal_ball", "FRAGILE", 45, dusty=0.1, vendors="antique", brk=3.5, color="d0e8f8", tags="fragile",
      lore_ru="Будущее не загрузилось.", lore_en="Future failed to load."),
    I("crystal_cracked", "Шар треснутый", "Cracked Crystal Ball", "crystal_ball", "FRAGILE|DIRTYABLE", 20, dusty=0.35, vendors="tiny", brk=2.5, color="8a7a60", tags="fragile",
      lore_ru="Судьба дала трещину.", lore_en="Fate got a crack."),
    # reuse archetypes
    I("vase_motel_china", "Ваза мотельная", "Motel China Vase", "vase", "FRAGILE|DIRTYABLE", 18, dusty=0.55, vendors="tiny", brk=3.5, color="e8d0c0", tags="vase|fragile",
      lore_ru="Из номера 12. Залог не вернули.", lore_en="Room 12. Deposit kept."),
    I("vase_ash_urn_fake", "Урна «прах тёти»", "Auntie Ash Urn", "vase_tall", "FRAGILE|SHAKE_OUT|DIRTYABLE", 60, dusty=0.3, nest="cash_20:0.2:1:1|letter_aunt:0.4:1:1", vendors="antique", brk=3.8, color="c8c0b0", tags="vase|fragile",
      lore_ru="Прах оказался пеплом сигарет.", lore_en="Ashes were cigarette ash."),
    I("bottle_message", "Бутылка с запиской", "Message Bottle", "bottle", "FRAGILE|SHAKE_OUT|LIQUID", 28, liquid="water", liquid_amt=0.2, dusty=0.2, nest="letter_treasure:0.7:1:1", vendors="antique|tiny", brk=4.0, color="305060", tags="fragile",
      lore_ru="Записка: «верните бутылку».", lore_en="Note: return the bottle."),
    I("bottle_ship_glue", "Бутылка «корабль»", "Ship-in-Bottle Glue", "bottle", "FRAGILE|DIRTYABLE", 85, dusty=0.25, vendors="antique", brk=4.2, color="e8e0d0", tags="fragile|souvenir",
      lore_ru="Корабль приклеен криво.", lore_en="Ship glued crooked."),
    I("jar_marbles", "Банка шариков", "Jar of Marbles", "jar", "FRAGILE|SHAKE_OUT|CONTAINER", 22, dusty=0.15, nest="cash_1:0.4:1:4|ring_plastic:0.2:1:1", vendors="tiny", brk=4.0, color="c8d8e0", tags="fragile|toy",
      lore_ru="Потерянные шарики детства.", lore_en="Lost childhood marbles."),
    I("jar_teeth", "Банка зубов", "Jar of Teeth", "jar", "FRAGILE|SHAKE_OUT|DIRTYABLE", 15, dusty=0.4, vendors="dark|tiny", brk=4.0, color="e0e8e8", tags="fragile|gag",
      lore_ru="Зубная фея обанкротилась.", lore_en="Tooth fairy went bankrupt."),
    I("jar_glitter", "Банка блёсток", "Glitter Jar", "jar", "FRAGILE|LIQUID|DIRTYABLE", 8, liquid="water", liquid_amt=0.6, dusty=0.1, vendors="tiny", brk=3.5, color="f0a0d0", tags="fragile|gag",
      lore_ru="Блёстки вечны. Как сожаления.", lore_en="Glitter is forever."),
    I("glass_shot_cursed", "Стопка проклятая", "Cursed Shot Glass", "glass", "FRAGILE", 12, dusty=0.2, vendors="tiny|dark", brk=3.0, color="dce8f0", tags="fragile",
      lore_ru="После неё все говорят правду.", lore_en="Makes everyone honest."),
    I("plate_divorce", "Тарелка «его/её»", "Divorce Plate", "plate", "FRAGILE|DIRTYABLE", 9, dusty=0.45, vendors="tiny", brk=4.0, color="f0f0ee", tags="fragile",
      lore_ru="Разбита пополам идеально.", lore_en="Perfectly half-broken vibe."),
    I("bowl_cereal_stale", "Миска с хлопьями", "Stale Cereal Bowl", "bowl", "FRAGILE|DIRTYABLE|LIQUID", 3, liquid="water", liquid_amt=0.1, dusty=0.7, vendors="tiny", brk=4.5, color="e8e0d0", tags="fragile",
      lore_ru="Хлопья окаменели.", lore_en="Cereal fossilized."),
    I("cup_office_steal", "Кружка с работы", "Stolen Office Mug", "cup", "FRAGILE|DIRTYABLE", 4, dusty=0.35, vendors="tiny", brk=4.5, color="ffffff", tags="fragile",
      lore_ru="Логотип компании-банкрота.", lore_en="Logo of a dead company."),
    I("perfume_ex", "Духи бывшей", "Ex Perfume", "perfume", "FRAGILE|LIQUID", 25, dusty=0.1, vendors="antique|tiny", brk=3.8, color="e0c0d0", tags="fragile",
      lore_ru="Пахнет судебным иском.", lore_en="Smells like a lawsuit."),
    I("candle_seance", "Свеча спиритическая", "Seance Candle", "candle", "FRAGILE", 9, flammable=1, dusty=0.2, vendors="dark|tiny", brk=6.0, color="101018", tags="gag",
      lore_ru="Фитиль уже кто-то жевал.", lore_en="Wick pre-chewed."),
    I("lamp_lava_table", "Лампа «лава» стол", "Table Lava Lamp", "lamp_table", "FRAGILE|DIRTYABLE", 48, dusty=0.25, vendors="tech|household", brk=4.5, color="f040a0", tags="fragile|light",
      lore_ru="Путают с настоящей лавой.", lore_en="Confused with real lava."),
    I("frame_photo_ex", "Рамка с бывшим", "Ex Photo Frame", "frame_photo", "FRAGILE|DIRTYABLE", 8, dusty=0.3, vendors="tiny", brk=4.0, color="e8e0d0", tags="fragile",
      lore_ru="Лицо выцарапано.", lore_en="Face scratched out."),
    I("mirror_compact", "Зеркальце карманное", "Pocket Mirror", "mirror", "FRAGILE", 14, dusty=0.15, vendors="tiny|antique", brk=3.2, color="c0c0c8", scale=0.45, tags="fragile",
      lore_ru="Врёт о возрасте.", lore_en="Lies about your age."),
    I("statue_gnome_evil", "Гном злой", "Evil Garden Gnome", "statue", "FRAGILE|DIRTYABLE", 38, dusty=0.35, vendors="antique|household", brk=5.0, color="306030", tags="fragile|gag",
      lore_ru="Улыбка судебная.", lore_en="Lawsuit smile."),
    I("statue_flamingo_pair", "Фламинго садовый", "Garden Flamingo", "statue", "FRAGILE|DIRTYABLE", 22, dusty=0.3, vendors="household", brk=5.5, color="f060a0", tags="fragile",
      lore_ru="Пара потеряла вторую ногу.", lore_en="Mate lost the other leg."),
    I("bust_boss", "Бюст начальника", "Boss Bust", "bust", "FRAGILE|DIRTYABLE", 55, dusty=0.4, vendors="antique", brk=5.0, color="d0d0d8", tags="fragile",
      lore_ru="Бросать приятно.", lore_en="Satisfying to drop."),
    I("skull_candle_hold", "Череп-подсвечник", "Skull Candle Holder", "skull", "FRAGILE|DIRTYABLE", 48, flammable=1, dusty=0.25, vendors="dark|antique", brk=4.5, color="e8e0d0", tags="fragile|gag",
      lore_ru="Романтика кладбища.", lore_en="Cemetery romance."),
    I("plant_pot_fake_fern", "Горшок с папоротником", "Fake Fern Pot", "plant_pot", "FRAGILE|DIRTYABLE", 16, dusty=0.4, vendors="household", brk=4.8, color="8a6a40", tags="fragile",
      lore_ru="Пластик пыльный как живой.", lore_en="Dusty plastic looks alive."),
    I("fish_bowl_cracked", "Круглый аквариум", "Cracked Fish Bowl", "fish_bowl", "FRAGILE|LIQUID|DIRTYABLE", 20, liquid="water", liquid_amt=0.4, dusty=0.5, vendors="tiny", brk=3.0, color="a0d0f0", tags="fragile|pet",
      lore_ru="Рыбки съехали раньше.", lore_en="Fish moved out first."),
    I("globe_bar_empty", "Глобус-бар пустой", "Empty Bar Globe", "globe", "FRAGILE|CONTAINER|DIRTYABLE", 70, dusty=0.35, vendors="antique", brk=5.0, color="2a5a8a", tags="fragile",
      lore_ru="Мир открыт. Выпивка нет.", lore_en="World opens. Booze gone."),
    I("trophy_spelling", "Кубок за орфографию", "Spelling Bee Trophy", "trophy", "FRAGILE|DIRTYABLE", 40, dusty=0.3, vendors="antique|tiny", brk=5.5, color="e0c040", tags="fragile",
      lore_ru="Победитель написал верно.", lore_en="Winner spelled trophy right."),
    I("trophy_last_place", "Кубок за последнее", "Last Place Trophy", "trophy", "FRAGILE", 12, dusty=0.2, vendors="tiny", brk=5.0, color="c0c0c0", tags="fragile|gag",
      lore_ru="Честнее золота.", lore_en="More honest than gold."),
    I("typewriter_ribbon_box", "Коробка лент", "Ribbon Box", "box_small", "CONTAINER|SHAKE_OUT|DIRTYABLE", 10, dusty=0.3, nest="letter_debt:0.25:1:1", vendors="tiny", color="2a2a2a", tags="office",
      lore_ru="Ленты засохли. Слова тоже.", lore_en="Ribbons dried. Words too."),
    I("folder_divorce", "Папка «развод»", "Divorce Folder", "folder", "DOCUMENT|SHAKE_OUT", 15, dusty=0.2, nest="letter_debt:0.5:1:1|bill_iou:0.4:1:1", vendors="tiny", color="404060", tags="document",
      lore_ru="Толще романа.", lore_en="Thicker than a novel."),
    I("usb_blackmail", "Флешка «не открывать»", "Do-Not-Open USB", "usb", "DIRTYABLE", 35, dusty=0.1, vendors="dark|tech", color="222222", tags="electronics",
      lore_ru="Подпись маркером: НЕТ.", lore_en="Sharpie label: NO."),
    I("cassette_confession", "Кассета «признание»", "Confession Cassette", "cassette", "SHAKE_OUT|DIRTYABLE", 18, dusty=0.25, vendors="tiny|dark", color="5a4030", tags="music",
      lore_ru="Лента перемотана до дыр.", lore_en="Tape worn to holes."),
    I("radio_shower", "Радио в душ", "Shower Radio", "radio", "DIRTYABLE|FRAGILE", 16, dusty=0.4, vendors="household", brk=6.0, color="3080c0", tags="electronics",
      lore_ru="Всё ещё играет рекламу.", lore_en="Still plays ads."),
    I("phone_rotary", "Телефон дисковый", "Rotary Phone", "phone", "DIRTYABLE|HEAVY_CHEAP", 55, dusty=0.35, vendors="antique|tech", color="222228", tags="electronics",
      lore_ru="Набрать 911 — квест.", lore_en="Dialing 911 is a quest."),
    I("camera_disposable", "Одноразка просрочена", "Expired Disposable", "camera", "FRAGILE|DIRTYABLE", 8, dusty=0.2, vendors="tiny", brk=5.0, color="f0f0f0", scale=0.7, tags="electronics",
      lore_ru="Плёнка помнит 2003-й.", lore_en="Film remembers 2003."),
    I("watch_calculator", "Часы-калькулятор", "Calculator Watch", "watch", "DIRTYABLE", 28, dusty=0.15, vendors="tech|tiny", color="303038", tags="electronics",
      lore_ru="Считает лучше хозяина.", lore_en="Calculates better than you."),
    I("necklace_garlic", "Ожерелье из чеснока", "Garlic Necklace", "necklace", "DIRTYABLE|WEARABLE", 7, flammable=1, dusty=0.5, vendors="tiny", wear="body", tags="wear|gag",
      lore_ru="От вампиров и свиданий.", lore_en="Repels vampires and dates."),
    I("hat_propeller", "Шапка с пропеллером", "Propeller Hat", "hat", "WEARABLE|DIRTYABLE", 14, dusty=0.2, vendors="tiny", color="e03030", wear="body", tags="wear|gag",
      lore_ru="Взлетает только достоинство.", lore_en="Only dignity takes flight."),
    I("shoe_flipflop_one", "Шлёпанец один", "Single Flip-Flop", "shoe", "DIRTYABLE", 2, dusty=0.6, vendors="tiny", color="ff8020", tags="wear",
      lore_ru="Пара ушла к другой жизни.", lore_en="Mate left for a better life."),
    I("bag_evidence", "Пакет «улики»", "Evidence Bag", "bag", "CONTAINER|SHAKE_OUT|DIRTYABLE", 20, dusty=0.3, nest="usb_blackmail:0.35:1:1|letter_ransom:0.3:1:1", vendors="dark", color="e8e8c0", tags="container",
      lore_ru="Печать сорвана. Конечно.", lore_en="Seal broken. Of course."),
    I("box_moving_labels", "Коробка «кухня???»", "Kitchen??? Box", "box", "CONTAINER|DIRTYABLE", 12, dusty=0.45, nest="plate_ikeya:0.4:1:2|cup_okayest:0.5:1:2|jar_glitter:0.3:1:1", vendors="household", color="c9a97a", tags="container",
      lore_ru="Подпись с тремя вопросами.", lore_en="Label has three question marks."),
    I("chest_hope_empty", "Сундук надежды", "Empty Hope Chest", "chest", "CONTAINER|DIRTYABLE|LOCKED", 80, dusty=0.4, nest="dress_prom:0.25:1:1|letter_love:0.4:1:1", vendors="antique", color="5a3a20", tags="container",
      lore_ru="Надежда выветрилась.", lore_en="Hope aired out."),
    I("suitcase_airport", "Чемодан невостребованный", "Unclaimed Suitcase", "suitcase", "CONTAINER|DIRTYABLE|LOCKED", 65, dusty=0.35, nest="sock_single:0.7:1:2|perfume_ex:0.3:1:1|cash_20:0.2:1:1", vendors="household|dark", color="4a4a60", tags="container",
      lore_ru="Бирка: рейс отменён навсегда.", lore_en="Tag: flight cancelled forever."),
    I("jewelry_box_empty_fancy", "Шкатулка пустая", "Fancy Empty Box", "jewelry_box", "CONTAINER|FRAGILE|DIRTYABLE", 30, dusty=0.25, vendors="antique", brk=4.5, color="7a2040", tags="container",
      lore_ru="Бархат помнит кольца.", lore_en="Velvet remembers rings."),
    I("safe_piggy_broke", "Копилка-сейф", "Broken Piggy Safe", "coin_jar", "CONTAINER|FRAGILE|SHAKE_OUT", 25, dusty=0.3, nest="cash_10:0.5:1:2", vendors="tiny", brk=4.0, color="f0a0c0", scale=1.2, tags="container|fragile",
      lore_ru="Уже треснута для изъятия.", lore_en="Pre-cracked for withdrawal."),
    I("book_cursed_diary", "Дневник проклятый", "Cursed Diary", "book", "SHAKE_OUT|DIRTYABLE", 40, flammable=1, dusty=0.3, nest="letter_ransom:0.35:1:1|cash_5:0.2:1:1", vendors="dark|antique", color="2a1a2a", tags="document",
      lore_ru="Страницы сами перелистываются.", lore_en="Pages turn themselves."),
    I("book_cookbook_burnt", "Книга рецептов горелая", "Burnt Cookbook", "book", "DIRTYABLE", 6, flammable=1, dusty=0.7, vendors="tiny", color="3a2a20", tags="document",
      lore_ru="Рецепт огня на первой странице.", lore_en="Fire recipe on page one."),
    I("pillow_scream", "Подушка для крика", "Scream Pillow", "pillow", "DIRTYABLE", 11, dusty=0.4, vendors="tiny", color="806080", tags="cloth",
      lore_ru="Уже накричана.", lore_en="Pre-screamed."),
    I("rug_prayer_fake", "Коврик «молитва»", "Fake Prayer Rug", "rug", "DIRTYABLE", 28, flammable=1, dusty=0.35, vendors="antique|household", color="4a6a40", tags="cloth",
      lore_ru="Нарисована Мекка фломастером.", lore_en="Mecca drawn in marker."),
    I("mannequin_hand", "Рука манекена", "Mannequin Hand", "mannequin", "DIRTYABLE|FRAGILE", 18, dusty=0.3, vendors="tiny|antique", brk=6.0, color="f0e0d0", scale=0.35, tags="gag",
      lore_ru="Показывает куда нести хаул.", lore_en="Points where to haul."),
    I("doll_ventriloquist", "Кукла чревовещателя", "Ventriloquist Dummy", "doll", "DIRTYABLE|FRAGILE|ALIVE", 95, dusty=0.35, vendors="dark|antique", brk=5.0, color="f0e0c0", tags="gag|fragile",
      lore_ru="Челюсть сама. Шутки сами.", lore_en="Jaw moves itself. Jokes too."),
    I("toy_bear_cursed", "Мишка с глазами", "Watching Teddy", "toy_bear", "DIRTYABLE|SHAKE_OUT", 35, dusty=0.25, nest="usb_blackmail:0.15:1:1", vendors="dark|tiny", color="4a3020", tags="toy|gag",
      lore_ru="Пуговицы — камеры? Нет… да.", lore_en="Buttons cameras? No… yes."),
    I("ball_disco_mini", "Диско-шар мини", "Mini Disco Ball", "ball", "FRAGILE", 30, dusty=0.1, vendors="tech|tiny", brk=3.5, color="e0e8f0", scale=0.6, tags="fragile|gag",
      lore_ru="Дискотека в кармане.", lore_en="Pocket disco."),
    I("trumpet_school", "Труба школьная", "School Trumpet", "trumpet", "DIRTYABLE|FRAGILE", 45, dusty=0.4, vendors="antique", brk=5.5, color="c0a040", tags="music",
      lore_ru="Только «ту-ту» и слёзы.", lore_en="Only toots and tears."),
    I("drum_bongo_crack", "Бонго треснутое", "Cracked Bongo", "drum", "FRAGILE|DIRTYABLE", 18, dusty=0.45, vendors="tiny", brk=4.0, color="8a5a30", tags="music|fragile",
      lore_ru="Ритм утекает.", lore_en="Rhythm leaks out."),
    I("keyboard_sticky", "Синтезатор липкий", "Sticky Synth", "keyboard_music", "DIRTYABLE", 55, dusty=0.5, vendors="tech", color="222228", tags="music|electronics",
      lore_ru="Клавиши помнят газировку.", lore_en="Keys remember soda."),
    I("guitar_missing_string", "Гитара без струны", "Stringless Guitar", "guitar", "DIRTYABLE", 40, dusty=0.4, vendors="antique", color="6a4a28", tags="music",
      lore_ru="Пять струн — пять сожалений.", lore_en="Five strings five regrets."),
    I("bike_helmet_cam", "Шлем с «камерой»", "Helmet Cam Fake", "helmet", "WEARABLE|DIRTYABLE", 28, dusty=0.25, vendors="tiny", color="101018", wear="body", tags="wear|electronics",
      lore_ru="Камера — наклейка.", lore_en="Camera is a sticker."),
    I("oil_lamp_genie", "Лампа «джинн»", "Genie Oil Lamp", "jug", "FRAGILE|LIQUID|DIRTYABLE", 120, liquid="oil", liquid_amt=0.4, flammable=1, dusty=0.3, vendors="antique|dark", brk=4.0, color="c0a040", tags="fragile|gag",
      lore_ru="Джинн не выходит. Пахнет маслом.", lore_en="No genie. Just oil smell."),
]


def csv_escape(s: str) -> str:
    if any(c in s for c in ",\"\n"):
        return '"' + s.replace('"', '""') + '"'
    return s


def item_line(d: dict) -> str:
    return ",".join(csv_escape(str(d.get(c, ""))) for c in COLS)


def append_arch() -> None:
    text = ARCH.read_text(encoding="utf-8")
    if MARKER in text:
        text = text[: text.index(MARKER)].rstrip() + "\n"
    ARCH.write_text(text + "\n" + ARCH_ROWS + "\n", encoding="utf-8")
    n = sum(1 for l in ARCH_ROWS.splitlines() if l and not l.startswith("#"))
    print(f"archetypes +{n}")


def append_items() -> None:
    text = ITEMS_CSV.read_text(encoding="utf-8")
    if MARKER in text:
        text = text[: text.index(MARKER)].rstrip() + "\n"
    block = [MARKER + " (~%d cards)" % len(ITEMS)]
    block.extend(item_line(d) for d in ITEMS)
    ITEMS_CSV.write_text(text + "\n" + "\n".join(block) + "\n", encoding="utf-8")
    print(f"items +{len(ITEMS)}")


def main() -> None:
    append_arch()
    append_items()
    r = subprocess.run([sys.executable, str(ROOT / "tools" / "gen_content.py")], cwd=str(ROOT))
    if r.returncode != 0:
        sys.exit(r.returncode)
    print("gen_content OK")


if __name__ == "__main__":
    main()
