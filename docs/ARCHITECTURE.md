# COOONTAINER — архитектура кода (для разработчиков и субагентов)

Godot **4.7.2**, GDScript, Jolt, 30 Hz физика, physics interpolation. ТЗ: `DESIGN_TZ.md` (канон).
Рендер: Mobile. Все меши — процедурные примитивы (лоу-поли). Нет внешних ассетов.

## Проверка

```powershell
$g = "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
& $g --headless --path . --import                          # обновить кэш классов/импорт (после новых class_name / .csv / .wav)
& $g --headless --path . --quit-after 400 -- --smoke        # дымовой тест: стартует слот 3, спавнит вещи, ломает, льёт, жжёт
```
Ошибок `SCRIPT ERROR` быть не должно. `[smoke] DONE errors=0` — успех.

## Автолоады (порядок важен)

| Autoload | Что |
|---|---|
| `Registry` | `item(id)->ItemDef`, `archetype(id)`, `archetype_for(def)`, `lot(id)`, `lots_for_district(d)`, `hunter(id)`, `all_hunters()`, `vendor(id)`, `all_vendors()`, `items_with_tag(tag)`, `bills_for(amount)->Array[String]`. Грузит все `.tres` из `res://data/**`. |
| `SteamBoot` | `enabled`, `persona`, lobby/cloud/achievements/voice обёртки. Без GodotSteam — no-op. |
| `Game` | `app_state`, `world_mode` (Types.WorldMode), `set_world_mode(m)`, `save: Dictionary` (слот), `write_slot()`, `notify.emit(text, sec)` (тост худа), `stat_add(key, v)`, `stat(key)`, `haggle_skill()`, `haggle_skill_gain(v)`, `unlock_district(d)`, `is_district_unlocked(d)`, `unlock_vendor(id)`, `is_vendor_unlocked(id)`, `blacklist(d)`, `is_blacklisted(d)`, `lot_done(id)`, `lot_burned(id)`, `is_lot_burned(id)`, `try_buy_house()`, `HOUSE_PRICE`, `world: World`. |
| `Economy` | `pot`, `add(amount, reason)`, `try_spend(amount, reason)->bool`, `can_afford()`, `withdraw_bills(amount, at)`, `deposit_bill(body)`. Только хост меняет; сигнал `pot_changed(new, delta, reason)`, `broke()`. |
| `Net` | см. «Сеть». |
| `AudioBus` | `play_at(name, pos, db=0, pitch_rand=0.15, pitch_base=1)`, `play_ui(name)`, `play_music(name)`, `stop_music()`, `npc_shout(group, pos, pitch, category)->len`, `has(name)`. |
| `Achievements` | `unlock(id)`, `count(stat_key, ach_id, threshold)`. Ids — в `steam/achievements.json`. |
| `Voice` | push-to-talk V, proximity. Ничего звать не надо. |

`Types` (`core/types.gd`) — enum'ы: `SizeClass, Facet, LiquidId, Integrity, LotKind, InfoMode, PacingTag, VendorType, Phobia, WorldMode, District, PoliceTrigger` + слои `L_WORLD, L_PLAYER, L_ITEM, L_SHARD, L_VEHICLE, L_NPC, L_LIQUID, L_TRIGGER, L_RAGDOLL`.

## Сеть — правило одно: **хост считает, клиент просит**

- `Net.is_host()` — true в соло и у хоста. Всё, что меняет мир (спавн, деньги, состояние вещи), делать только если `Net.is_host()`.
- Клиент → хост: `Net.request_action(kind: String, data: Dictionary)`. Хост получает в `World.handle_action(peer, kind, data)`, который сначала обрабатывает базовые (`pocket_put/take, scrub, apply_tool, interact, grab_special, pin`), потом перебирает `$Systems/*` и зовёт `system.handle_action(peer, kind, data) -> bool` (вернул true — обработано).
- Хост → все: `Net.broadcast_event(kind, data)` (reliable; локально тоже приходит). Приходит в `World.on_net_event(kind, data)` → потом в каждую систему `on_net_event(kind, data)`. **На хосте событие тоже приходит** — проверяй `if Net.is_host(): return` там, где хост уже применил эффект сам.
- Хост → один пир: **только `Net.send_event(peer, kind, data)`**, никогда `_rpc_event.rpc_id(peer, …)` напрямую: rpc_id на собственный id при `call_remote` — `ERR_INVALID_PARAMETER` («RPC on yourself is not allowed»). `send_event` сам доставляет локально, когда `peer == my_id()` или игрок один, поэтому дублировать вызов «если это я — применить самому» не нужно.
- Новый пир: хост зовёт `system.send_full_state_to(peer)` если есть — шли ему `Net._rpc_event.rpc_id(peer, kind, data)`.
- Вещи: `Net.spawn_item(item_id, xform, state={}, parent_net_id=0) -> ItemBody` (хост), `Net.despawn_item(net_id)`, `Net.items: Dictionary[net_id → ItemBody]`, `Net.players: Dictionary[peer → Player]`, `Net.my_id()`, `Net.peer_count()`.
- Позиции NPC не снапшотятся автоматически: NPC мало и они почти стоят. Если NPC ходит — система шлёт `broadcast_event("npc_pos", {...})` изредка или NPC живёт только на хосте + косметика на клиенте. `Npc.say()` сама рассылает `npc_say`.

## Вещь — `ItemBody` (`item/ItemBody.gd`, RigidBody3D)

`ItemBody.create(def)`; поля: `def: ItemDef`, `arch: Archetype`, `net_id`, `proxy` (клиентская копия, freeze).
Состояния: `integrity (Types.Integrity)`, `dirt 0..1`, `paint_color`, `wet`, `taped`, `boarded`, `locked`, `lit`, `burnt`, `liquid_left`, `is_open`, `open_drawers`, `torn`, `glued`, `lot_id`.
Связи: `nested_in`, `nested: Array`, `held_by: Array[Hands]`, `worn_by`.
Методы (хост): `shatter()`, `spill(amount)`, `ignite()`, `extinguish()`, `add_dirt(v)`, `scrub(amount, wet_rag)`, `paint(color, strength)`, `soak(amount, liquid)`, `apply_patch(patch_def)`, `toggle_open(by)`, `toggle_drawer()`, `shake_out()`, `dump_all()`, `unlock_by(tool_def, chance)`, `nest_child(b)`, `unnest()`, `host_use(player, mode)` (E — прикол вещи).
Цена: `current_value(vendor: VendorDef = null) -> int` — f(value_base, integrity, dirt, paint, tape, vendor). Осколки = $1.
Сигналы: `broke, state_changed, opened, picked, dropped`. Описание: `describe()`.
Теги карточки (`def.tags`), на которые реагирует код: `tape, plank, nail, rag, lockpick, lighter, matches, flashlight, gag_gun, vase, painting, gem, mouse, hamster, clown, unicorn, no_pockets, broom, bucket, phone`.

## Архетипы — `Archetype` + `item/ArchetypeMeshes.gd`

`Archetype.tres`: `id, builder, scene (герой), shard_count, size_class, mass_default, dims (габарит, origin низ), cloth, container, container_capacity, base_color, secondary_color, friction, bounce, light_fixture`.
`builder` — имя статической функции `_b_<builder>` в ArchetypeMeshes. Список: `ArchetypeMeshes.builder_names()`. Узлы `Lid*` открываются, `Wall*` разъезжаются (сумка), `Drawer*` выдвигаются.
Герой (уникальная сцена): `scene` задана; корень Node3D может иметь `get_shapes() -> Array[{shape, xform}]`.

## Игрок — `Player` (`actor/player/Player.gd`, CharacterBody3D)

`peer_id`, `is_local()`, `head`, `camera`, `hands: Hands`, `hp`, `burning`, `drunk`, `dead`, `cuffed`, `wanted`, `in_custody`, `worn`, `pockets`, `respawn_point`.
Методы: `say(text)`, `look_target() -> Node`, `head_position()`, `take_damage(v, reason)`, `die(reason)`, `set_burning(v)`, `drink(a)`, `splash(liquid, amount)`, `wear(b)`, `unwear()`, `set_cuffed(v)`, `enter_vehicle(v)`, `exit_vehicle(pos)`, `toggle_paddle()`, `paddle()`.
`Hands`: `held[0..1]`, `active_hand` (0 правая / 1 левая, `swap_hand`=Q), `any_held()`, `holds_tag(tag)`, `host_grab(b, hand)`, `host_release_body(b, throw)`, `host_release_all()`. Мышь ведёт активную ладонь в `ARM_LEN` от плеча; вещь следует В ладонь (не «в воздухе»); `REACH`≈1.45 — высоко не достать без лестницы. Двуручный хват: обе ладони за одной точкой взгляда.

## Интерактивы мира

Любой `CollisionObject3D` (слой `L_TRIGGER` или `L_WORLD`) с методом `interact(player: Player)` — игрок жмёт E, хост вызывает. Опционально `interact_hint(player) -> String` для подсказки на прицеле. `on_grab(player)` — ЛКМ по нему (ручка тачки, NPC).

## Мир — `World` (`world/World.gd`)

`$City` (City.gd: `district_root(d)`, `district_at(pos)`, `lot_anchors(d)`), `$Items`, `$Players`, `$Npcs`, `$Systems/<Name>`, `$HUD`, `$Pause`.
`world.system("Auction")`, `find_marker(district, "Name")`, `local_player()`, `player_of(peer)`, `spawn_lot_contents(preset, cell_node) -> Array[ItemBody]`, `despawn_lot_items(lot_id)`, `items_in_radius(pos, r)`.
HUD: `hud.set_timer(sec, title_key, overtime)`, `hud.clear_timer()`, `hud.set_bid(amount, leader, yours)`, `hud.toast(text)`, `hud.show_subtitle(text)`, `hud.show_document(text)`, `hud.show_lot_card(dict)` (итог лота), `hud.show_death(reason, sec)` / `hide_death()`, `hud.show_credits()` (титры + `Cutscenes.chronicle()`).

Бюджет физики (§7.5): `World._process` раз в 1.5 с усыпляет самые дальние почти неподвижные тела, если бодрствующих > `AWAKE_BUDGET` (200). Осколки капает `Shard.MAX_SHARDS`.

### Катсцены — `Cinematic` (`world/systems/Cinematic.gd`, `$Systems/Cinematic`, локально у каждого)
Шот = Dictionary `{from, to, look, look_to, dur, fov, fov_to, title, sub, text_delay, fade_in, fade_out, shake, ease, on_start: Callable, follow: Node3D}` (при `follow` from/to/look — смещения от узла).
`play(shots, skippable)` → `await finished`; ручной режим для трейлера: `begin()` → `run([shot])` / `await sequence_done` … → `end()`; `card(title, sub, hold)`, `fade_to_black()`, `snap(pos, look)`.
Во время катсцены `Player.cinematic = true` (ввод и взгляд выключены, `cine_move` — куда бежать), `set_third_person(true)` показывает своё тело целиком; HUD скрыт; Esc в World игнорируется.
Сценарии — `world/Cutscenes.gd` (`intro(w)`, `ending(w)`, `chronicle()`); интро играет при первом спавне в слот (`save.intro_seen`), финал — при `WorldMode.CREDITS` перед титрами. Трейлер — `tools/Trailer.gd` (`--trailer`, запись `tools/trailer.ps1`).

### Арт-направление: гранёный лоу-поли + вечный золотой час
Кей-арт — рубленые фасетные формы, тёплый закат, лиловые тени. Инструменты:
- `core/LowPoly.gd` (static): `sphere(r, seg, rings)`, `capsule`, `cylinder`, `chamfer_box(size, bevel)` — гранёные меши с плоскими нормалями, кэш по параметрам; `facet(mesh, key)` — снять сглаживание с любого меша; `flatten(node)` — заменить круглые примитивы в поддереве. **Обход треугольников в Godot — по часовой снаружи**: `_tri` ориентирует так, чтобы правовинтовая нормаль смотрела К центру; наоборот — все коробки «вывернуты» (видны только дальние стенки, «объекты пустые с одной стороны»). Проверка глазами: `--artshot --probe=Dumpster1,4`. Персонажи, вещи, пропсы и тачки строятся через него — не через сырые `SphereMesh`/`CapsuleMesh`. **Материал на такие (общие, кэшированные) меши — только `material_override`**, не `set_surface_override_material`: per-surface override у общего меша при `free()` узла даёт ошибку рендер-сервера «Parameter material is null» (Godot 4.6+, воспроизводится и на 4.7). `ItemBody._collect_materials` поэтому берёт override целиком, а редкие многоповерхностные меши снимает в `NOTIFICATION_PREDELETE`.
- `DayNight`: ночь короткая (`NIGHT_FRAC`), солнце дольше висит низко (`SUN_SHAPE`), время на золотом часу течёт медленнее (`GOLD_SLOW`); `golden()` 0..1 — используют небо/туман/ambient/облака (`Clouds` под World). Новая игра стартует в `DEFAULT_TIME` (ранний вечер). Ориентиры: полдень 0.5, золотой час ≈ 0.79, ночь > 0.89.
- `CityDress`: земля города — `tex_dirt_tracks` (глина с колеёй), трейлер-парк — то же, холмы пыльные; кремовые стены не считаются деревом (`_is_woody` требует s > 0.3).
- `world/Terrain.gd` (`Terrain.dress(w)` из `CityDress` после `_walk`): плоский бокс земли и грунтовые блины районов → сетка квадратов (`CELL` 2.5 м / 1.5 м на блине) с шумом Перлина: выбоины 0…-`POTHOLE` только на пустырях (внутри районов лишь микрошум — полы стоят на y=0), темнее в яме (vertex color, `vertex_color_use_as_albedo`). Рельеф только вниз — коллизия остаётся плоской, ничего не висит. Кей-артовые «плитки» даёт не геометрия, а `TILT`: детерминированный наклон нормали на квадрат (одна на квадрат, не на треугольник). `_scatter`: галька/кирпичи/камни MultiMesh по пустырям (не на дорогах `Roads.segments`, не в районах). Загружается через `load()` — кэш `class_name` редактора может отставать.
- `Vehicle._vis/_box/_glass/_emis`: `_build()` диспатчит по `vtype` в `_build_pickup|_build_van|_build_truck` — капот с решёткой и круглыми фарами, цельная кабина со стёклами и швом двери, зеркала, крылья, борта, задний бампер с эмиссивными стопами, фаркоп, выхлоп (~55 мешей). Коллизии/сиденья/`_bed_zone`/колёса не трогать — только `_vis`. `_build_dust` — пыль из-под задних колёс при скорости > 2.5. **`_sink_check`**: тяжёлый лут, упавший в кузов, пробивает подвеску, лучи `VehicleWheel3D` стартуют под полом и теряют опору — кузов застревает в грунте и дёргается (v≈2 м/с, колёса «касаются» грунта изнутри — ни по контакту, ни по скорости не отфильтровать). Лечим чисто геометрией каждые 0.15 с: луч сверху вниз, хиты выше днища (навес, камера, бочки) пропускаем; низ колёс глубже земли на `SINK_DEPTH` 0.2 → подъём + обнуление вертикальной скорости. NPC-тачки из `NPC_CARS` не ставить на пропсы `Interiors` (склад (9,0,9) — бочки/ящики отодвинуты).
- Ревью тачек: `--artshot` → `art_02_pickup` (три четверти сзади, как на кей-арте), `art_03_pickup_front`, `art_04_pickup_side_low` + печать `pickup y=… wheels=[…]` (y кузова ≈ −0.05, колёса ≈ 0.32 — стоит на колёсах).
- Набивка мира: `world/districts/Props.gd` (двор трейлер-парка, пальмы/сагуаро/фламинго, столбы с проводами, фасады, кусты/камни/колеи между районами; **ghetto pack** — плотный двор вокруг трейлера: диваны, палатки, шины, заборы, бельевые, лужи/масляные пятна, тележки, матрасы, мусор; **horizon shacks** — 6–8 шалашей на пустоши 45–90 м от трейлера; **wasteland junk** — кластеры хлама между районами) и `world/districts/Interiors.gd` (`Interiors.dress(w)` из `CityDress`: стеллажи, автоматы, форклифт, обшивка трейлера). Оба идемпотентны (узел `Interior`/`Props`), только `MeshInstance3D` + редкие `OmniLight3D` без теней.
- Персонажи: `Npc`/`Player` строятся из `LowPoly` — огромные головы, овальные глаза, кепки; «жизнь» в `_process` (дыхание, моргание, взгляд на игрока, кивки при реплике, подскок хантера на «!»). Камера игрока — `Player._camera_feel(delta)` (боб, FOV спринта, присед при приземлении, `shake(strength)`).
- Вещи: `ArchetypeMeshes.Ctx.box(..., bevel)` → `chamfer_box`; декаль трещины (`tex_crack_decal`, detail-слой MUL) на CHIPPED и на id/тегах `cracked|broken`; пыль — десатурация, а не затемнение; `item/PuffFx.gd` — облачко пыли/осколков при жёстком ударе (≤ 6 одновременно).
- Звук фона: `world/systems/Ambience.gd` — два 2D-слоя (день/ночь `ambient_desert_day|night` и «где я» по району из `BY_DISTRICT`) с кроссфейдом, 3D-луп костра у маркера `Campfire`. Лупы синтезирует `tools/audio/gen_sfx.py` (`ambient_*`, `campfire_loop`, `wind_gust`); `AudioBus.loop_stream(name)` включает LOOP_FORWARD у WAV.
- Ревью: `godot --path . -- --artshot [--artdir=x] [--time=t]` → `user://shots/[x/]art_*.png` (трейлер-парк, пикап, хантеры в лицо, витрина геройских вещей `ArtShot.HERO_IDS`, игрок 3P, торговец, доска объявлений + меню вакансий, город).

### «Чем заняться» — улица, работа, игрушки (`world/systems/StreetLoot|Jobs|Interactables|HomeClutter.gd`)
Ответ на плейтест «мало объектов, непонятно куда идти за деньгами». Все четыре — хостовые системы под `Systems`, интерфейс объектов единый: `interact(player)` (E через `World.handle_action "interact"`) + `interact_hint(player)` (худ показывает при наведении).
- **StreetLoot** — при старте хост рассыпает ~70 дешёвых вещей (`value_base ≤ 60`, не `illegal`, не деньги, мелкие архетипы) по грунту с сидированным RNG, спящими; капля-респавн до `CAP=80`. 10 `Dumpster` (StaticBody3D): 3 заряда за игровые сутки, 1.2 с таймер → вещь с импульсом; 20% «находка» ($60–300, `STREET_FIND_*`), 10% крыса. Первый уличный подбор — тост `STREET_HINT`.
- **HomeClutter** — одноразовый «домашний» хлам у трейлера (35–50 `ItemBody`, `meta home`): стол/кухня/полка/кровати/пол/крыльцо/костёр; рейкаст на `L_WORLD`, сид `hash(slot)+7919`. Только если в сейве нет `home_clutter_done`; пропуск при `--nettest`. Первый подбор домашней вещи — тост `HOME_HINT` (`strings_home.csv`).
- **Jobs** — три `JobBoard` (трейлер-парк, ряд торговцев, выезд от полиции): доска с козырьком, кнопками, бак `TrashBin` (Area3D). E → хост шлёт `jobs_menu` этому пиру → локальный `JobsMenu` (CanvasLayer, CenterContainer — влезает в 720p). Пул 6 работ (`JOB_PAY`): `janitor` (делегат в `Janitor`, −40% при котле ≥ $50), `trash` (6 уличных вещей в бак), `delivery` (ящик → скупщик), `flyers` (4 района), `car_wash` (губка 8 с у тачки), `night_watch` (только ночью). Показывается 3, ротация каждые 6 мин или по завершении. Состояние — `jobs_state` (broadcast + `send_full_state_to`) → `HUD.set_objective(text, target)`: подсказка с расстоянием и стрелкой. **Подсказка после беды**: `Police._suggest_jobs()` (штраф/арест/выпуск) и `World._on_broke()` → `Jobs.suggest_work()` — 90 с цель «Денег мало → доска у трейлера».
- **Interactables** — 13 игрушек: торговые автоматы ($2 → напиток или «застряло», пинок), таксофоны (подсказки/ошиблись номером), дверь на `PortaPotty` (гэги), джукбокс в казино, груша у гаражей, лавки (сесть), насос на авторынке. Событие `interactable {id, kind, act}`; клиенты применяют меши/звук в `on_net_event`. `_safe()` сдвигает точку с дорог и лотов.
- **Ставка на аукционе** — `Paddle.consume_input()` вызывается из `Player._input` **до** GUI (цифры раньше съедал худ); `0–9`/Backspace — сумма, `R` — минимум, `+`/`-`/колесо — шаг, ЛКМ/Enter — поднять. Худ: панель `bid_panel` (верх-право, растёт влево) — топ, лидер, «Требуется», своя сумма, ряд клавиш. Низкая ставка → `auction_bid_reject` (тост + зуммер + красная вспышка весла); первая сессия BIDDING — коуч-тост `AUC_COACH` (флаг `bid_coached` в сейве). Весло: `Player.toggle_paddle()` поднимает только рядом с торгами (виден `bid_panel`), не в камере и не в машине; `lower_paddle()` — B повторно, конец режима AUCTION (`Game.world_mode_changed`), арест. Темп торгов: `Auction.SETTLE_SECONDS` (0.7 с между ставками хантеров) и `SETTLE_AFTER_PLAYER` (1.4 с после ставки игрока / когда его перебили), `GOING_SECONDS` 5 — чтобы цену успевали прочитать.
- **Скупщик — куда нести**: `DropZone` прилавка расширена на землю перед ним (бокс 3.6×2.4×3.0; `collision_layer = 0`, чтобы area не ловила луч взгляда), интерактив — весь фасад прилавка; жёлтая рамка + «СЮДА ХЛАМ» на земле (`_paint_sell_zone`, на +0.12 над полом — выше половиков). `_stand_hint` с вещью в руках говорит «положи → E». `_sell_guidance_tick`: скупщик зовёт игрока с вещью (раз в 20 с), первый раз с вещью вне лота — цель худа «Продай → скупщик» на 60 с. Крупную вещь на прилавок не поставишь — она продаётся с земли (тест `vendor_floor_zone`).
- **Полиция — камера**: `JailDoor`/`EvidenceDoor` в редакторе стоят в проёме; открытая = поднята на `DOOR_SLIDE` (`_apply_door(which, active, instant)`). На старте камеру открываем мгновенно. В камере ходить можно (движение блокируют только `cinematic`/пауза; наручники — вполсилы), держит решётка. `_on_arrived_station` не сажает, если дело уже закрыто (смерть в пути). Тесты `jail_open_start|jail_closes|jail_reopens`.
- **Огонь — очаги**: `Fire.hearths` (костёр у трейлера, `add_hearth(pos, r)`): игрок в очаге горит, горючее (`is_flammable()`: масло/бензин/бумага/ткань/облитое) в радиусе вспыхивает (`HEARTH_IGNITE_CHANCE` за 0.25 с), лужи поджигаются. Тест `campfire_ignites` (бочка масла в костре).
- **Руки**: покой — опущены к нижним углам (`_arm_base_*`), с вещью/веслом поднимаются к центру (`_ARM_UP_*`); пустая правая тянется к тому, на что смотрит игрок (`_arm_aim`, `look_target()` раз в 0.1 с).

### Прогрессия районов (`Game.DISTRICT_GATES`, `check_progression()`)
`[district, need_earned_total, need_lots_done]` — открывается по ЛЮБОМУ из порогов. Зовётся из `Economy.add`, `Game.lot_done`, при старте мира; клиентам — событие `district_unlocked` (и в `send_full_state_to`, `quiet: true`). `Game.next_gate()` — для «Записки Петровича» (TrailerHub) и подсказок.

### Районы (`world/districts/`)
`District.gd` (корень сцены района): `district_id, name_key, radius, unlock_cost`; сигналы `player_entered/exited`; `marker(name)`, `lot_anchors()`.
`LotAnchor.gd`: `lot_kind, cell_size, has_door, dark`; дети по имени `Cell` (пол ячейки, вход по +Z), `Door` (AnimatableBody3D), `Hunter0..7`, `Auctioneer`, `Caretaker`, `PlayerStand`, `PreviewSpot`, `Lamp`. `close_door()/open_door()`, `is_inside(pos)`, `cell_center()`.
Маркеры трейлер-парка: `Bed0..3`, `ToolShelf`, `JunkYard`, `PotSlot` (Area3D, PotSlot.gd), `HouseSign`.

## NPC — `Npc` (`actor/npc/Npc.gd`, CharacterBody3D)

`npc_group` (папка голоса), `body_color, height, fatness, hat, bald, voice_pitch, display_name`; `say(text, sec, category)`, `move_to(pos)`, `face(pos)`, `shove(impulse)`, `ragdoll_for(sec)`, сигнал `arrived`. Хост двигает.

## Контент

- `data/items/*.tres` — ItemDef. `data/archetypes/*.tres` — Archetype. `data/lots/*.tres` — LotPreset (spawn_list: LotSpawn). `data/hunters/*.tres` — AuctionBrain. `data/vendors/*.tres` — VendorDef.
- Строки: `data/strings/strings.csv` (`keys,ru,en`). В коде `tr("KEY")`. Имена вещей/NPC — в самих .tres (`name_ru/name_en`).
- Звук: `audio/sfx/<name>.wav` (имена, которые уже зовёт код: thud, thud_heavy, clink, flop, crack, shatter, squeak, ignite, hiss, tape, hammer_nail, locked_rattle, zip_open, lid_open, drawer, unlock, gulp, cork, tap, gag_bang, grab, whoosh, squelch, splash, pour, pocket, cloth, coin, coin_loss, cash_register, fanfare, buzzer, pin, rip, oof, death_wilhelm, siren, door_slam, door_roll, achievement, shout_generic, fire_loop), `audio/music/<name>.wav` (menu_loop, hub_loop, auction_loop, clearout_loop, casino_loop, vendor_loop, police_loop, janitor_loop, credits), `audio/voice/<ru|en>/<group>/<category>_NN.wav`.

## Контракт имён (все системы опираются на это)

**Id контента**
- Хантеры: `hunter_01 … hunter_08`. Скупщики: `vendor_tiny` (открыт сразу), `vendor_antique`, `vendor_household`, `vendor_tech`, `vendor_dark`.
- Лоты: `<district>_<NN>` (`hangar_01`, `storage_03`, `garages_02`, `port_01`), `order` = NN.
- Инструменты (код ждёт эти id и теги): `tool_flashlight[flashlight]`, `tool_rag[rag]`, `tool_bucket[bucket]`, `tool_tape[tape]`, `tool_lockpick[lockpick]`, `tool_lighter[lighter]`, `tool_plank[plank]`, `tool_nails[nail]`, `tool_broom[broom]`, `tool_phone[phone]`, `tool_paddle` не нужен (весло — не вещь).
- Купюры `cash_1/5/10/20/50/100/500` создаются Registry автоматически (архетип `bill`).
- Архетип id == имя билдера (`vase`, `dresser`, …) + герои `hero_hamster`, `hero_safe`, `hero_bag`, `hero_gag_gun`, `hero_plasma`, `hero_costume_clown`, `hero_costume_unicorn`.

**Маркеры в сценах районов** (ищутся `world.find_marker(district, "Name")` / `district.marker("Name")`)
- Трейлер-парк: `Bed0..3`, `ToolShelf`, `JunkYard`, `PotSlot` (PotSlot.gd), `HouseSign` (HouseSign.gd), `TrailerDoor`.
- Аукционные районы (Hangar/Storage/Garages/Port): `LotAnchor`-узлы `Lot0..LotN` (LotAnchor.gd, `lot_kind`), у каждого дети `Cell, Door, Hunter0..7, Auctioneer, Caretaker, PlayerStand, PreviewSpot, Lamp`. Lot0 в Hangar — сумки на столе (`has_door=false`).
- Скупщики: `VendorStand_<vendor_id>` (Node3D) с детьми `Counter` (StaticBody3D, верх стола на y≈1.0), `DropZone` (Area3D над столом), `NpcSpot`, `PlayerSpot`, `PhotoSpot`.
- Вскрывальщик: `LocksmithBench` (StaticBody3D), `LocksmithSpot`, `LocksmithDropZone` (Area3D).
- Казино: `CasinoTable` с детьми `BetZoneRed`, `BetZoneBlack` (Area3D), `Wheel` (Node3D), `DealerSpot`, `CasinoPotSlot` (PotSlot deposit_only).
- Участок: `JailCell` (Node3D центр пола), `JailDoor` (AnimatableBody3D), `EvidenceRoom` (Node3D), `EvidenceDoor` (AnimatableBody3D), `Desk`, `CopSpawn0..2`, `PoliceCarSpawn`, `Bribe` (Area3D на столе).
- Авторынок: `CarSlot0..3`, `DealerSpot`, `CarMarketSign`.
- Дороги: `Bump*` (StaticBody3D кочки), `RoadSign*` (Label3D). Миникарты нет.

**Строки**: каждая система/контент пишет свои в `data/strings/strings_<system>.csv` (`keys,ru,en`), грузятся Registry в рантайме. `strings.csv` — общие, не трогать параллельно.

## Стиль
- Типизированный GDScript, `class_name` у всего переиспользуемого. Никаких `get_node("/root/...")` — только автолоады.
- Никаких `print` в горячих путях. Ошибок/варнингов при `--smoke` быть не должно.
- Всё на русском в комментариях допустимо; строки UI — только через `tr()`.
