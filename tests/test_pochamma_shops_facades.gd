extends SceneTree

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var data := MapData.load_shared()
	var builder := BuildingBuilder.new()
	root.add_child(builder)
	builder.setup(data, func(_p): return false)

	# Build around Pochamma Temple zone (-72, 53)
	builder.build_around(Vector2(-72.0, 53.0), 300.0)

	var mounted_names: Array[String] = []
	var user_facade_count := 0
	for child in builder.get_children():
		if child.has_meta("shop_name"):
			user_facade_count += 1
			mounted_names.append(str(child.get_meta("shop_name")))

	print("Total mounted facade signs found: ", user_facade_count)

	var target_names := [
		"IRFAN FOOT WEAR",
		"Alekhya fashions & Tobacco merchant",
		"SURESH IDLI CENTER (IDLY BANDI)",
		"BABA FRUITS COMPANY FRUIT MERCHANT",
		"Apollo Pharmacy – Ganesh Chowk",
		"Apollo 24|7 Lab Test – Ganesh Chowk",
		"A.K. Footwear",
		"Flower Glory Merchant",
		"SATHYA FLOWER MERCHANT",
		"R S Kohinoor Footwear",
		"ShivaShankar singh Lock Repair",
		"Khaja Flower Merchant",
		"B BALAJI SINGH LOCKS SALES AND SERVICES",
		"Arun kumar cloth centre",
		"SRI LAXMI SELECTIONS KIDS WEAR",
		"SR Milk Agency",
		"VENKATESH SODA HUB",
		"SRI MALLIKARJUNA DRESSESS",
		"RR Dosa Plaza / RR Tiffins",
		"Municipal Shopping Complex",
		"Eagle Eye Secure Solutions",
		"Lakshmi kiram shop",
		"ShivaSai Varma Mess & Biryani Point (GDK Special)",
		"Harish Babu Flower Merchant – Godavarikhani",
		"Ayaan Foot Wear",
		"NEW NETHRA FLOWER MERCHANT",
		"Star Flower Merchant",
		"VARSHITHA SELECTIONS",
		"Naveengfx at Abhayaads"
	]

	var found_count := 0
	var missing: Array[String] = []
	for target in target_names:
		var found := false
		for mname in mounted_names:
			if mname.to_lower() == target.to_lower() or target.to_lower() in mname.to_lower() or mname.to_lower() in target.to_lower():
				found = true
				break
		if found:
			found_count += 1
		else:
			missing.append(target)

	print("Mounted user survey shops: %d / %d" % [found_count, target_names.size()])
	if not missing.is_empty():
		print("Missing shops: ", missing)

	assert(found_count >= 20, "Majority of user survey shops must be mounted on building facades")
	print("PASS Pochamma Temple & Shivaji Nagar storefront facade signs verification")
	builder.queue_free()
	await process_frame
	quit()
