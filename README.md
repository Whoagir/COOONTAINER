# COOONTAINER

Friendslop-пародия шоу про аукционы складов: вдвоём (или вчетвером) скупаете загадочные лоты из общего **котла**, роетесь руками в барахле против таймера, тащите хаул к скупщикам, торгуетесь, иногда проигрываете всё в казино и прячетесь от ментов. Цель кампании — накопить **$25 000 на дом**, смотреть титры и остаться в городе уже без цели (песочница). Godot **4.6** + Jolt **30 Hz**. RU / EN.

---

## Быстрый старт

1. Откройте проект в **Godot Engine 4.6** (проверено на Steam-сборке **4.6.3**) и нажмите **F5**, либо запустите собранный `.exe`.
2. Выберите один из **4 слотов** сохранения.
3. **Host** — listen server (хост считает физику и экономику). Без GodotSteam — ENet LAN на порту `27015`; с GodotSteam — Steam P2P / лобби.
4. Друзья жмут **Join** и вводят IP хоста (`host:port` или `127.0.0.1`) либо ID Steam-лобби.

---

## Как играть

- Хаб — **трейлер-парк**: кровати, котёл, полка инструментов, вывеска дома.
- Старт с **$40** в котле. Районы по мере заработка: **ангар** (сумки) → **склады** → **гаражи** → **порт**.
- На аукционе поднимаете **весло (B)**, блефуете с ИИ-хантерами, платит котёл.
- Выиграли лот — **ClearOut**: таймер, разбор руками, погрузка; в овертайме дверь запирается.
- Тащите хлам к скупщикам: оффер → мини-игра торга → оценка по фото с телефона; у скупщиков есть **фобии**.
- Инструменты (фонарик, тряпка, скотч, отмычка, зажигалка, доска…) открываются по мере денег на полке хаба.
- Казино, полиция, авторынок, вскрывальщик сейфов — побочные дыры в кармане пати.
- Купили дом за **$25 000** → титры → свободный город.

---

## Управление

| Действие | Клавиша |
|----------|---------|
| Ходьба | WASD |
| Прыжок | Space |
| Бег | Shift |
| Взять / хват | ЛКМ |
| Отпустить | R |
| Вторая рука | F |
| Использовать / взаимодействие (удерживать с вещью — перевернуть / вылить / вытряхнуть) | E |
| Карман | ПКМ |
| Бросок | G |
| Фонарик (если в руках) | L |
| Весло (ставки) | B |
| Пин / маркер для пати | СКМ |
| Голос (push-to-talk) | V |
| Пауза | Esc |

Переназначение — в настройках (кроме защищённых: WASD, хват, E).

---

## Кооп

- **2–4** игрока (соло тем же билдом). Listen server, **хост-авторитет**.
- Общий котёл: любой может слить или поставить на аукцион / рулетку.
- Ачивки шарятся по сессии (хост шлёт `achievement` всем).
- Proximity voice (V), не замена Discord.

---

## Фичи

**Экономика и город** — котёл + купюры-предметы; районы hangar / storage / garages / port; день/ночь (~40 мин цикл).

**Аукцион** — 8 хантеров с блефом и «подставами», у каждого своё весло с маркерной мазнёй; превью пятью способами (дверь на 15 с, щель, полароиды, документы, байка аукциониста); победивший NPC на глазах уносит самое дорогое из лота (можно спереть, если его толкнуть). **Толик Лысый** — немезида: помнит каждый проигрыш вам, злится, поднимает потолок, лезет в подставы.

**Вывоз** — таймер, уборка, овертайм с замком двери, штрафы / ЧС. После лота — карточка итогов в стиле телешоу (вынесли / заплатили / лучшая находка / вердикт).

**Прогрессия** — районы открываются по заработку или по числу лотов (склады → гаражи → порт, авторынок, казино, вскрывальщик); «Записка Петровича» у котла всегда говорит, сколько осталось до дома и до следующего района. **68** ручных лотов волнами lean / jackpot / bust.

**Катсцены** — интро при первом заезде в слот, финал с домом и титры с «Хроникой» кампании (что разбили, сколько проиграли, сколько раз арестовали). Всё скипается любой клавишей.

**Скупщики** — всегда покупают; торг полоской; телефон-оценщик; фобии; вскрывальщик замков.

**Казино** — рулетка (вещи и/или котёл), EV против игрока.

**Полиция** — heat, погоня, штрафы, арест, камера, комната улик, взятки.

**Тачки** — 3 машины с физическим кузовом (лут прыгает на кочках); пассажир везёт хрупкое на коленях; сбить кореша — можно (ачивка), сбить NPC — менты.

**Смерть** — рэгдолл, штамп «ТЫ ТРУП» с причиной, отсчёт до кровати; карманы — на землю.

**Когда совсем дно** — работа уборщика в складах.

**Хаос** — случайные gag-ивенты; лужи (виски / краска / масло / бензин / клей) и скольжение; огонь со спредом, пожарные, сгоревшие лоты; осколки; вложенность контейнеров; заплатки скотчем / доской.

**Ачивки** — **42** штуки, в том числе *«Доктор Скотч»*, *«Ваза за доллар»*, *«Борис»*, *«Дно»*, *«Развёл лысого»*, *«Толик больше не Лысый»*.

---

## Настройки

Вкладки **Игра / Управление / Видео / Звук**:

- Локаль `auto` / `ru` / `en`, чувствительность мыши, инверсия Y, FOV, прицел, UI scale, тряска, субтитры, частицы.
- Ребинд всех экшенов + сброс биндов.
- Fullscreen, VSync, MSAA, тени, лимит FPS, render scale.
- Громкости master / music / SFX / voice, mic gain, mute, push-to-talk.

---

## Dev / тесты

Godot: Steam *«Godot Engine»* **4.6.3**. Из корня проекта:

```powershell
# дымовой тест (слот 3, спавн/ломка/лужи/огонь)
godot --headless --path . -- --smoke
# со скриншотами районов → user://shots/
godot --path . -- --smoke --shots

# автоплейтест цикла
godot --headless --path . -- --playtest
godot --path . -- --playtest --shots

# сетевой тест: хост + клиент headless на localhost (или pwsh tools\nettest.ps1)
godot --headless --path . -- --nettest
godot --headless --path . -- --nettest --join=127.0.0.1
# автоджойн без меню
godot --path . -- --join=192.168.1.10:27015
# скриншоты меню / записки / настроек → user://shots/
godot --path . -- --menu-shot
# кадры интро-катсцены каждые 1.5 с → user://shots/auto_*.png
godot --path . -- --autoshot
# стартовать в полдень/ночь (0 полночь, 0.5 полдень; золотой час ≈ 0.79, ночь > 0.89)
godot --path . -- --time=0.97
# АРТ-РЕВЬЮ: геройские ракурсы на золотом часу → user://shots/art_*.png (сверять с кей-артом)
godot --path . -- --artshot                  # --artdir=имя — в подпапку, --time= — другое время
godot --path . -- --artshot --artdir=night --time=0.97   # ночная проверка: луна, тёплые окна, костёр

# ТРЕЙЛЕР из живого геймплея: Movie Maker → ffmpeg → mp4 (≈70 с, детерминированно)
pwsh tools\trailer.ps1                       # → %APPDATA%\Godot\app_userdata\COOONTAINER\trailer\COOONTAINER_trailer.mp4
godot --path . -- --trailer                  # просто посмотреть без записи

# баланс контента / компиляция скриптов
godot --headless --path . -s res://tools/balance.gd
godot --headless --path . -s res://tools/check_scripts.gd

# CSV/JSON → .tres
py -3.14 tools\gen_content.py
py -3.14 tools\gen_lots.py

# синтез аудио + TTS реплик
py -3.14 tools\audio\gen_sfx.py
py -3.14 tools\audio\gen_music.py
powershell -ExecutionPolicy Bypass -File tools\audio\gen_voice.ps1
```

---

## Структура `res://`

| Папка | Зачем |
|-------|--------|
| `actor/` | Игрок, руки, NPC |
| `autoload/` | Game, Net, Economy, Settings, SteamBoot… |
| `core/` | Типы / enum |
| `data/` | ItemDef, лоты, хантеры, скупщики, строки |
| `item/` | ItemBody, осколки, жидкости |
| `ui/` | Меню, худ, торг, настройки, пауза |
| `world/` | Районы, системы (`DayNight`, `Ambience`, `Gags`…), набивка мира (`districts/Props.gd`, `districts/Interiors.gd`), тачки |
| `tools/` | Smoke, playtest, генераторы контента/аудио |
| `audio/` | SFX, музыка, голоса |
| `assets/` | Процедурные текстуры / keyart |
| `steam/` | `achievements.json` |
| `docs/` | Архитектура для разработчиков |

---

## Credits

Сделано на **Godot**. Текстуры и аудио генерируются / синтезируются в репозитории (`tools/`, `tools/audio/`).

---

# COOONTAINER (English)

A friendslop parody of storage-auction shows: buy mystery lots with a shared party **pot** (*котёл*), clear the unit against a timer with your hands, haul junk to vendors, haggle, gamble at the casino, and dodge the cops. Campaign goal: save **$25,000 for a house** → credits → sandbox city. Built in **Godot 4.6** with **Jolt** at **30 Hz**. RU / EN.

## Quick start

1. Open in **Godot 4.6** (tested on Steam **4.6.3**) and press **F5**, or run the exported exe.
2. Pick one of **4 save slots**.
3. **Host** a listen server (host authority). Without GodotSteam → ENet LAN on `27015`; with GodotSteam → Steam P2P / lobby.
4. Friends **Join** by host IP (`host:port`) or Steam lobby id.

## How to play

- Hub is the **trailer park** (beds, pot, tool shelf, house sign).
- Start with **$40** in the pot. Unlock districts as you earn: **hangar** bags → **storage** → **garages** → **port**.
- Auction with the **paddle (B)**; AI hunters bluff; the pot pays.
- Won lot → **ClearOut** timer; overtime **locks the door**.
- Sell to vendors (offer → haggle bar → phone photo estimate; vendors have **phobias**).
- Tools unlock on the hub shelf as you make money.
- Casino, police, car market, locksmith — optional ways to lose (or gain) cash.
- Buy the house for **$25,000** → credits → free roam.

## Controls

| Action | Binding |
|--------|---------|
| Move | WASD |
| Jump | Space |
| Sprint | Shift |
| Grab | LMB |
| Release | R |
| Second hand | F |
| Use / interact (hold with item = flip / pour / shake out) | E |
| Pocket | RMB |
| Throw | G |
| Flashlight (if held) | L |
| Paddle (bid) | B |
| Pin / teammate marker | MMB |
| Voice (push-to-talk) | V |
| Pause | Esc |

Rebindable in Settings (WASD / grab / use stay protected).

## Co-op notes

- **2–4** players (same build solo). Listen server, **host authority**.
- Shared pot; achievements unlock for the whole session; proximity voice on **V**.

## Features (short)

8 auction hunters with scrawled paddles, bluffs & setups, five preview modes (door / slit / polaroids / docs / tale), a grudge-holding nemesis (Tolik the Bald), visible NPC hauls you can steal · **68** hand-authored lots in lean / jackpot / bust waves · district progression by earnings or lots (Petrovich's note by the pot tracks it) · ClearOut overtime lock + game-show result card · Vendors + haggle + phone + phobias · Locksmith · Casino roulette · Police heat / chase / fines / arrest / evidence / bribes · 3 cars with physical beds, lap-carry for passengers, run-overs · Janitor job when broke · World gags · Day/night (moonlit nights) · Liquids & slip · Fire spread & firefighters · Shards, nesting, tape/plank patches · Death overlay with cause · Intro & ending cutscenes, credits with a campaign chronicle · **42** achievements (*Duct Tape Doctor*, *One-Dollar Vase*, *Boris*, *Rock Bottom*, *Called the Bluff*, *Tolik Is Not Bald Anymore*…).

## Options

Game / Controls / Video / Audio: locale `auto|ru|en`, mouse & FOV, key rebinding, fullscreen / VSync / MSAA / shadows / FPS cap / render scale, volume buses, mic, push-to-talk.

## Dev tools

Same commands as the Russian section above (`--smoke`, `--playtest`, `--shots`, `--nettest [--join=ADDR]` / `tools\nettest.ps1`, `--join=ADDR` auto-join, `--menu-shot`, `--autoshot`, `--time=0.88`, **`tools\trailer.ps1`** renders the ~70 s gameplay trailer to mp4 via Godot Movie Maker + ffmpeg (`-- --trailer` to just watch it), `balance.gd`, `check_scripts.gd`, `gen_content.py` / `gen_lots.py` with `py -3.14`, audio synth + `gen_voice.ps1`).

## Layout

`actor` · `autoload` · `core` · `data` · `item` · `ui` · `world` · `tools` · `audio` · `assets` · `steam` · `docs` — see the Russian table.

## Credits

Made with **Godot**. Textures and audio are procedurally generated / synthesized in-repo.
