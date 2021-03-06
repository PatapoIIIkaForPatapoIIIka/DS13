/*
	Corruption is an extension of the bay spreading plants system.

	Corrupted tiles spread out gradually from the marker, and from any placed nodes, up to a certain radius
*/
GLOBAL_LIST_EMPTY(corruption_sources)
GLOBAL_DATUM_INIT(corruption_seed, /datum/seed/corruption, new())

//We'll be using a subtype in addition to a seed, becuase there's a lot of special case behaviour here
/obj/effect/vine/corruption
	name = "corruption"
	icon = 'icons/effects/corruption.dmi'
	icon_state = ""

	max_health = 80
	max_growth = 1

	var/max_alpha = 215
	var/min_alpha = 20

	spread_chance = 100	//No randomness in this, spread as soon as its ready
	spread_distance = CORRUPTION_SPREAD_RANGE	//One node creates a screen-sized patch of corruption
	growth_type = 0
	var/vine_scale = 1.1
	var/datum/extension/corruption_source/source

	//This is only used for the uncommon edge case where this vine is on the border between multiple chunks
	//Don't give it a value if unused, saves memory
	var/list/chunks

	//To remove corruption, destroy the nodes that are spreading it
	can_cut = FALSE


	//No clicking this
	mouse_opacity = 0


/obj/effect/vine/corruption/New(var/newloc, var/datum/seed/newseed, var/obj/effect/vine/corruption/newparent, var/start_matured = 0, var/datum/extension/corruption_source/newsource)

	alpha = min_alpha


	if (!GLOB.corruption_seed)
		GLOB.corruption_seed = new /datum/seed/corruption()
	seed = GLOB.corruption_seed

	source = newsource
	if (!newsource)
		source = newparent.source
	source.register(src)
	.=..()

/obj/effect/vine/corruption/Destroy()
	if (source)
		source.unregister(src)
	.=..()




//No calculating, we'll input all these values in the variables above
/obj/effect/vine/corruption/calculate_growth()

	mature_time = rand_between(20 SECONDS, 30 SECONDS) / source.growth_speed	//How long it takes for one tile to mature and be ready to spread into its neighbors.
	mature_time *= 1 + (source.growth_distance_falloff * get_dist_3D(src, plant))	//Expansion gets slower as you get farther out. Additively stacking 15% increase per tile

	growth_threshold = max_health
	possible_children = INFINITY
	return

/obj/effect/vine/corruption/update_icon()
	icon_state = "corruption-[rand(1,3)]"


	var/matrix/M = matrix()
	M = M.Scale(vine_scale)	//We scale up the sprite so it slightly overlaps neighboring corruption tiles
	var/rotation = pick(list(0,90,180,270))	//Randomly rotate it
	transform = turn(M, rotation)

	//Lets add the edge sprites
	overlays.Cut()
	for(var/turf/simulated/floor/floor in get_neighbors(FALSE, FALSE))
		var/direction = get_dir(src, floor)
		var/vector2/offset = Vector2.FromDir(direction)
		offset *= (WORLD_ICON_SIZE * vine_scale)
		var/image/I = image(icon, src, "corruption-edge", layer+1, direction)
		I.pixel_x = offset.x
		I.pixel_y = offset.y
		I.appearance_flags = RESET_TRANSFORM	//We use reset transform to not carry over the rotation

		I.transform = I.transform.Scale(vine_scale)	//We must reapply the scale
		overlays.Add(I)


//Corruption gradually fades in/out as its health goes up/down
/obj/effect/vine/corruption/adjust_health(value)
	.=..()
	if (health > 0)
		var/healthpercent = health / max_health
		alpha = min_alpha + ((max_alpha - min_alpha) * healthpercent)


//Add the effect from being on corruption
/obj/effect/vine/corruption/Crossed(atom/movable/O)
	if (isliving(O))
		var/mob/living/L = O
		if (!has_extension(L, /datum/extension/corruption_effect) && L.stat != DEAD)
			set_extension(L, /datum/extension/corruption_effect)


//This proc finds any viable corruption source to use for us
/obj/effect/vine/corruption/proc/find_corruption_host()
	for (var/datum/extension/corruption_source/CS in GLOB.corruption_sources)
		if (CS.can_support(src))
			return CS

	return null



//Gradually dies off without a nearby host
/obj/effect/vine/corruption/Process()
	.=..()
	if (!plant)
		adjust_health(-(SSplants.wait*0.1))	//Plant subsystem has a 6 second delay oddly, so compensate for it here


/obj/effect/vine/corruption/can_regen()
	.=..()
	if (.)
		if (!plant || QDELETED(plant))
			return FALSE

//In addition to normal checks, we need a place to put our plant
/obj/effect/vine/corruption/can_spawn_plant()
	if (!plant || QDELETED(plant))
		return TRUE
	return FALSE

//We can only place plants under a marker or growth node
//And before placing, we should look for an existing one
/obj/effect/vine/corruption/spawn_plant()
	var/datum/extension/corruption_source/CS = find_corruption_host()
	if (!CS)
		plant = null
		return
	if (CS.register(src))
		calculate_growth()



/obj/effect/vine/corruption/is_necromorph()
	return TRUE

/obj/effect/vine/corruption/can_reach(var/turf/floor)
	if (!QDELETED(source) && source.can_support(floor))
		return TRUE

	//Possible future todo: See if any other nodes can support it if our parent can't?

	return FALSE


/obj/effect/vine/corruption/wake_up(var/wake_adjacent = TRUE)
	if (QDELETED(source))
		source = null
	.=..()
	if (plant && !QDELETED(plant))
		calculate_growth()



/obj/effect/vine/corruption/spread_to(turf/target_turf)
	.=..()
	var/obj/effect/vine/corruption/child = .
	if (istype(child))
		child.get_chunks()	//Populate the nearby chunks list, for later visual updates




/* Visualnet Handling */
//-------------------
/obj/effect/vine/corruption/get_visualnet_tiles(var/datum/visualnet/network)
	return trange(1, src)

/obj/effect/vine/corruption/watched_tile_updated(var/turf/T)
	source.needs_update = TRUE
	.=..()

//Finds all visualnet chunks that this vine could possibly infringe on.
/obj/effect/vine/corruption/proc/get_chunks()
	var/list/chunksfound = list(GLOB.necrovision.get_chunk(x, y, z))
	for (var/direction in list(NORTHEAST, NORTHWEST, SOUTHEAST, SOUTHWEST))
		var/turf/T = get_step(src, direction)
		var/datum/chunk/newchunk = GLOB.necrovision.get_chunk(T.x, T.y, T.z)
		if (istype(newchunk))
			chunksfound |= newchunk


	//We only care if there's more than one chunk
	if (chunksfound.len > 1)
		chunks = chunksfound

/obj/effect/vine/corruption/proc/update_chunks()
	//Clear the necrovision cache
	GLOB.necrovision.visibility_cache = list()
	if (chunks)
		for (var/datum/chunk/C as anything in chunks)
			C.visibility_changed()
	else
		var/turf/T = loc
		T.update_chunk(FALSE)


/* The seed */
//-------------------
/datum/seed/corruption
	display_name = "Corruption"
	no_icon = TRUE
	growth_stages = 1


/datum/seed/corruption/New()
	set_trait(TRAIT_IMMUTABLE,            1)            // If set, plant will never mutate. If -1, plant is highly mutable.
	set_trait(TRAIT_SPREAD,               2)            // 0 limits plant to tray, 1 = creepers, 2 = vines.
	set_trait(TRAIT_MATURATION,           0)            // Time taken before the plant is mature.
	set_trait(TRAIT_PRODUCT_ICON,         0)            // Icon to use for fruit coming from this plant.
	set_trait(TRAIT_PLANT_ICON,           'icons/effects/corruption.dmi')            // Icon to use for the plant growing in the tray.
	set_trait(TRAIT_PRODUCT_COLOUR,       0)            // Colour to apply to product icon.
	set_trait(TRAIT_POTENCY,              1)            // General purpose plant strength value.
	set_trait(TRAIT_REQUIRES_NUTRIENTS,   0)            // The plant can starve.
	set_trait(TRAIT_REQUIRES_WATER,       0)            // The plant can become dehydrated.
	set_trait(TRAIT_WATER_CONSUMPTION,    0)            // Plant drinks this much per tick.
	set_trait(TRAIT_LIGHT_TOLERANCE,      INFINITY)            // Departure from ideal that is survivable.
	set_trait(TRAIT_TOXINS_TOLERANCE,     INFINITY)            // Resistance to poison.
	set_trait(TRAIT_HEAT_TOLERANCE,       20)           // Departure from ideal that is survivable.
	set_trait(TRAIT_LOWKPA_TOLERANCE,     0)           // Low pressure capacity.
	set_trait(TRAIT_ENDURANCE,            100)          // Maximum plant HP when growing.
	set_trait(TRAIT_HIGHKPA_TOLERANCE,    INFINITY)          // High pressure capacity.
	set_trait(TRAIT_IDEAL_HEAT,           293)          // Preferred temperature in Kelvin.
	set_trait(TRAIT_NUTRIENT_CONSUMPTION, 0)         // Plant eats this much per tick.
	set_trait(TRAIT_PLANT_COLOUR,         "#ffffff")    // Colour of the plant icon.


/datum/seed/corruption/update_growth_stages()
	growth_stages = 1




/* Crossing Effect */
//-------------------
//Any mob that walks over a corrupted tile recieves this effect. It does varying things
	//On most mobs, it applies a slow to movespeed
	//On necromorphs, it applies a passive healing instead

/datum/extension/corruption_effect
	name = "Corruption Effect"
	expected_type = /mob/living
	flags = EXTENSION_FLAG_IMMEDIATE

	//Effects on necromorphs
	var/healing_per_tick = 1
	var/speedup = 1.15

	//Effects on non necros
	var/slowdown = 0.7	//Multiply speed by this


	var/speed_delta	//What absolute value we removed from the movespeed factor. This is cached so we can reverse it later

	var/necro = FALSE


/datum/extension/corruption_effect/New(var/datum/holder)
	.=..()
	var/mob/living/L = holder
	var/speed_factor = 0
	if (L.is_necromorph())
		necro = TRUE
		speed_factor = speedup //Necros are sped up
		to_chat(L, SPAN_DANGER("The corruption beneath speeds your passage and mends your vessel."))
	else
		to_chat(L, SPAN_DANGER("This growth underfoot is sticky and slows you down."))
		speed_factor = slowdown	//humans are slowed down

	var/newspeed = L.move_speed_factor * speed_factor
	speed_delta = L.move_speed_factor - newspeed
	L.move_speed_factor = newspeed

	START_PROCESSING(SSprocessing, src)


/datum/extension/corruption_effect/Process()
	var/mob/living/L = holder
	if (!L || !turf_corrupted(L) || L.stat == DEAD)
		//If the mob is no longer standing on a corrupted tile, we stop
		//Likewise if they're dead or gone
		remove_extension(holder, type)
		return PROCESS_KILL

	if (necro)
		L.heal_overall_damage(healing_per_tick)


/datum/extension/corruption_effect/Destroy()
	var/mob/living/L = holder
	if (istype(L))
		L.move_speed_factor += speed_delta	//Restore the movespeed to normal

	.=..()