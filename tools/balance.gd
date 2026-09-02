extends SceneTree
## Балансный отчёт по контенту. Ошибок не правит — считает и печатает.
## godot --headless --path . -s res://tools/balance.gd


func _init() -> void:
	await process_frame
	await process_frame
	var reg = root.get_node_or_null("Registry")
	if reg == null:
		printerr("no Registry")
		quit(1)
		return
	_items(reg)
	_lots(reg)
	_hunters(reg)
	_vendors(reg)
	_campaign(reg)
	quit(0)


func _items(reg) -> void:
	var items: Array = reg.all_items()
	print("\n=== ВЕЩИ: %d ===" % items.size())
	var buckets := {"1-15": 0, "16-60": 0, "61-250": 0, "251-1500": 0, "1500+": 0}
	var by_facet := {}
	var by_arch := {}
	var by_size := {0: 0, 1: 0, 2: 0, 3: 0, 4: 0}
	var total := 0
	var fragile := 0
	var illegal := 0
	var liquids := 0
	var containers := 0
	var no_tags := 0
	for d in items:
		total += d.value_base
		var v: int = d.value_base
		if v <= 15: buckets["1-15"] += 1
		elif v <= 60: buckets["16-60"] += 1
		elif v <= 250: buckets["61-250"] += 1
		elif v <= 1500: buckets["251-1500"] += 1
		else: buckets["1500+"] += 1
		for f in d.facets:
			by_facet[f] = int(by_facet.get(f, 0)) + 1
		by_arch[d.archetype_id] = int(by_arch.get(d.archetype_id, 0)) + 1
		var a = reg.archetype_for(d)
		if a:
			by_size[a.size_class] = int(by_size.get(a.size_class, 0)) + 1
		if d.is_fragile(): fragile += 1
		if d.illegal: illegal += 1
		if d.liquid_id != 0: liquids += 1
		if d.is_container(): containers += 1
		if d.tags.is_empty(): no_tags += 1
	print("цена: %s" % str(buckets))
	print("средняя цена: %.1f, сумма: %d" % [float(total) / maxf(1.0, items.size()), total])
	print("хрупких: %d, незаконных: %d, с жидкостью: %d, контейнеров: %d, без тегов: %d" % [fragile, illegal, liquids, containers, no_tags])
	print("по SizeClass (POCKET/1H/2H/TEAM/VEH): %s" % str(by_size))
	# архетипы, использованные мало
	var unused: Array = []
	for aid in reg.archetypes:
		if not by_arch.has(aid):
			unused.append(aid)
	if not unused.is_empty():
		print("НЕ ИСПОЛЬЗОВАННЫЕ архетипы (%d): %s" % [unused.size(), ", ".join(unused)])
	var facet_names := []
	for f in by_facet:
		facet_names.append("%s=%d" % [Types.FACET_NAMES.get(f, str(f)), by_facet[f]])
	print("фасеты: %s" % ", ".join(facet_names))
	# проверка целостности ссылок
	var bad := 0
	for d in items:
		for lr in d.nest_loot:
			if reg.item(lr.item_id) == null:
				print("  BAD nest_loot: %s → %s" % [d.id, lr.item_id])
				bad += 1
		for vid in d.vendor_affinity:
			if reg.vendor(vid) == null:
				print("  BAD vendor_affinity: %s → %s" % [d.id, vid])
				bad += 1
	print("битых ссылок: %d" % bad)


func _lots(reg) -> void:
	var lots: Array = reg.lots.values()
	print("\n=== ЛОТЫ: %d ===" % lots.size())
	if lots.is_empty():
		return
	var by_district := {}
	for l in lots:
		if not by_district.has(l.district_id):
			by_district[l.district_id] = []
		by_district[l.district_id].append(l)
	var district_names := {1: "HANGAR", 2: "STORAGE", 3: "GARAGES", 4: "PORT"}
	var grand_profit := 0.0
	for d in by_district:
		var arr: Array = by_district[d]
		arr.sort_custom(func(a, b): return a.order < b.order)
		print("\n-- %s (%d лотов)" % [district_names.get(d, str(d)), arr.size()])
		var dp := 0.0
		for l in arr:
			var val: int = l.total_value(reg)
			# ожидаемая выручка: продажа ~0.6× value, бой хрупкого ~15% его цены
			var fragile_val := 0
			for s in l.spawn_list:
				var def = reg.item(s.item_id)
				if def and def.is_fragile():
					fragile_val += def.value_base
				for n in s.nested:
					var nd = reg.item(n)
					if nd and nd.is_fragile():
						fragile_val += nd.value_base
			var revenue: float = (float(val) - float(fragile_val) * 0.15) * 0.6
			var net: float = revenue - float(l.min_bid) * 1.6 # платят обычно выше min_bid
			dp += net
			print("  %-14s %-8s items=%-3d value=%-6d min_bid=%-5d net≈%-7.0f %s%s" % [
				l.id, ["BAG", "LOCKER", "STORAGE", "GARAGE", "PORT"][l.lot_kind], l.item_count(), val, l.min_bid, net,
				["lean", "jackpot", "bust"][l.pacing_tag], "  🧹" if l.broom_required else ""])
		print("  итог района: net≈%.0f" % dp)
		grand_profit += dp
	print("\nКАМПАНИЯ: полный проход всех районов net≈%.0f (нужно на дом: %d)" % [grand_profit, 25000])
	print("проходов до дома: %.2f" % (25000.0 / maxf(1.0, grand_profit)))


func _hunters(reg) -> void:
	var hs: Array = reg.all_hunters()
	print("\n=== ХАНТЕРЫ: %d ===" % hs.size())
	for h in hs:
		print("  %-12s err=%.2f greed=%.2f bluff=%.2f setup=%.2f pat=%.2f aggr=%.2f temper=%.2f  %s" % [
			h.id, h.estimate_error, h.greed, h.bluff_chance, h.setup_chance, h.patience, h.aggression, h.brawl_temper, h.nickname_ru])


func _vendors(reg) -> void:
	var vs: Array = reg.all_vendors()
	print("\n=== СКУПЩИКИ: %d ===" % vs.size())
	for v in vs:
		print("  %-18s type=%d mult=%.2f green=%.2f unlock=%-5d illegal=%s фобии=%s" % [
			v.id, v.vendor_type, v.base_multiplier, v.green_zone_base, v.unlock_cost, str(v.buys_illegal), str(v.phobias)])


func _campaign(reg) -> void:
	print("\n=== ПРОВЕРКИ ТЗ ===")
	var need_tools := ["tool_flashlight", "tool_rag", "tool_bucket", "tool_tape", "tool_lockpick", "tool_lighter", "tool_plank", "tool_broom", "tool_phone"]
	for t in need_tools:
		if reg.item(t) == null:
			print("  ОТСУТСТВУЕТ инструмент: %s" % t)
	var need_tags := ["hamster", "mouse", "clown", "unicorn", "gag_gun", "gem", "painting", "tape", "rag", "lockpick", "broom", "phone", "lighter"]
	for t in need_tags:
		if reg.items_with_tag(t).is_empty():
			print("  НЕТ вещей с тегом: %s" % t)
	for cash in [1, 5, 10, 20, 50, 100, 500]:
		if reg.item("cash_%d" % cash) == null:
			print("  НЕТ купюры %d" % cash)
	print("  ачивок в json: %d" % (root.get_node("Achievements").defs.size()))
