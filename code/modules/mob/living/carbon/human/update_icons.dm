/*
	Global associative list for caching humanoid icons.
	Index format m or f, followed by a string of 0 and 1 to represent bodyparts followed by husk fat hulk skeleton 1 or 0.
	TODO: Proper documentation
	icon_key is [species.race_key][g][husk][fat][hulk][skeleton][ethnicity]
*/
GLOBAL_LIST_EMPTY(human_icon_cache)

	///////////////////////
	//UPDATE_ICONS SYSTEM//
	///////////////////////
/*

Another feature of this new system is that our lists are indexed. This means we can update specific overlays!
So we only regenerate icons when we need them to be updated! This is the main saving for this system.

In practice this means that:
	Everytime you do something minor like take a pen out of your pocket, we only update the in-hand overlay
	etc...


There are several things that need to be remembered:

>	Whenever we do something that should cause an overlay to update (which doesn't use standard procs
	( i.e. you do something like l_hand = /obj/item/something new(src) )
	You will need to call the relevant update_inv_* proc:
		update_inv_head()
		update_inv_wear_suit()
		update_inv_gloves()
		update_inv_shoes()
		update_inv_w_uniform()
		update_inv_glasse()
		update_inv_l_hand()
		update_inv_r_hand()
		update_inv_belt()
		update_inv_wear_id()
		update_inv_ears()
		update_inv_s_store()
		update_inv_pockets()
		update_inv_back()
		update_inv_handcuffed()
		update_inv_wear_mask()

	All of these are named after the variable they update from. They are defined at the mob/ level like
	update_clothing was, so you won't cause undefined proc runtimes with usr.update_inv_wear_id() if the usr is a
	corgi etc. Instead, it'll just return without doing any work. So no harm in calling it for corgis and such.


>	There are also these special cases:
		update_mutations()	//handles updating your appearance for certain mutations.  e.g TK head-glows
		UpdateDamageIcon()	//handles damage overlays for brute/burn damage //(will rename this when I geta round to it)
		update_body()	//Handles updating your mob's icon to reflect their gender/race/complexion etc
		update_hair()	//Handles updating your hair overlay (used to be update_face, but mouth and
																			...eyes were merged into update_body)
		update_targeted() // Updates the target overlay when someone points a gun at you

>	If you need to update all overlays you can use regenerate_icons(). it works exactly like update_clothing used to.


*/

#define ITEM_STATE_IF_SET(I) I.item_state ? I.item_state : I.icon_state


/mob/living/carbon/human
	var/list/overlays_standing[TOTAL_LAYERS]
	var/list/underlays_standing[TOTAL_UNDERLAYS]
	var/previous_damage_appearance // store what the body last looked like, so we only have to update it if something changed



/mob/living/carbon/human/apply_overlay(cache_index)
	var/list/to_add = list()
	SEND_SIGNAL(src, COMSIG_HUMAN_APPLY_OVERLAY, cache_index, to_add)
	if(islist(overlays_standing[cache_index]))
		for(var/i in overlays_standing[cache_index])
			var/image/I = i
			to_add += I
	else
		var/image/I = overlays_standing[cache_index]
		if(I)
			to_add += I
	overlays += to_add

/mob/living/carbon/human/remove_overlay(cache_index)
	var/list/to_remove = list()
	SEND_SIGNAL(src, COMSIG_HUMAN_REMOVE_OVERLAY, cache_index, to_remove)
	if(overlays_standing[cache_index])
		if(islist(overlays_standing[cache_index]))
			for(var/i in overlays_standing[cache_index])
				var/image/I = i
				to_remove += I
		else
			to_remove += overlays_standing[cache_index]
		overlays_standing[cache_index] = null
	overlays -= to_remove

/mob/living/carbon/human/apply_underlay(cache_index)
	var/image/I = underlays_standing[cache_index]
	if(I)
		underlays += I

/mob/living/carbon/human/remove_underlay(cache_index)
	if(underlays_standing[cache_index])
		underlays -= underlays_standing[cache_index]
		underlays_standing[cache_index] = null

GLOBAL_LIST_EMPTY(damage_icon_parts)
/mob/living/carbon/human/proc/get_damage_icon_part(damage_state, body_part)
	if(GLOB.damage_icon_parts["[damage_state]_[species.blood_color]_[body_part]"] == null)
		var/brutestate = copytext(damage_state, 1, 2)
		var/burnstate = copytext(damage_state, 2)
		var/icon/DI
		if(species.blood_color != "#A10808") //not human blood color
			DI = new /icon('icons/mob/dam_human.dmi', "grayscale_[brutestate]")// the damage icon for whole human in grayscale
			DI.Blend(species.blood_color, ICON_MULTIPLY) //coloring with species' blood color
		else
			DI = new /icon('icons/mob/dam_human.dmi', "human_[brutestate]")
		DI.Blend(new /icon('icons/mob/dam_human.dmi', "burn_[burnstate]"), ICON_OVERLAY)//adding burns
		DI.Blend(new /icon('icons/mob/dam_mask.dmi', body_part), ICON_MULTIPLY)		// mask with this organ's pixels
		GLOB.damage_icon_parts["[damage_state]_[species.blood_color]_[body_part]"] = DI
		return DI
	else
		return GLOB.damage_icon_parts["[damage_state]_[species.blood_color]_[body_part]"]

//DAMAGE OVERLAYS
//constructs damage icon for each organ from mask * damage field and saves it in our overlays_ lists
/mob/living/carbon/human/UpdateDamageIcon()

	if(species.species_flags & NO_DAMAGE_OVERLAY)
		return

	// first check whether something actually changed about damage appearance
	var/damage_appearance = ""

	for(var/datum/limb/O in limbs)
		if(O.limb_status & LIMB_DESTROYED)
			damage_appearance += "d"
		else
			damage_appearance += O.damage_state

	if(damage_appearance == previous_damage_appearance)
		// nothing to do here
		return

	remove_overlay(DAMAGE_LAYER)

	previous_damage_appearance = damage_appearance

	var/icon/standing = new('icons/mob/dam_human.dmi', "00")

	var/image/standing_image = image("icon" = standing, "layer" = -DAMAGE_LAYER)

	// blend the individual damage states with our icons
	for(var/o in limbs)
		var/datum/limb/limb_to_update = o
		limb_to_update.update_icon()

		if(limb_to_update.damage_state == "00")
			continue

		var/icon/DI = get_damage_icon_part(limb_to_update.damage_state, limb_to_update.icon_name)

		standing_image.overlays += DI

	overlays_standing[DAMAGE_LAYER]	= standing_image

	apply_overlay(DAMAGE_LAYER)

//BASE MOB SPRITE
/mob/living/carbon/human/proc/update_body(update_icons = 1, force_cache_update = 0)
	var/necrosis_color_mod = rgb(10,50,0)

	var/g = get_gender_name(gender)
	var/has_head = 0


	//CACHING: Generate an index key from visible bodyparts.
	//0 = destroyed, 1 = normal, 2 = robotic, 3 = necrotic.

	var/icon_key = "[species.race_key][g][ethnicity]"
	for(var/datum/limb/part in limbs)

		if(istype(part,/datum/limb/head) && !(part.limb_status & LIMB_DESTROYED))
			has_head = 1

		if(part.limb_status & LIMB_DESTROYED)
			icon_key = "[icon_key]0"
		else if(part.limb_status & LIMB_ROBOT)
			icon_key = "[icon_key]2"
		else if(part.limb_status & LIMB_NECROTIZED)
			icon_key = "[icon_key]3"
		else
			icon_key = "[icon_key]1"

	if(species.species_flags & HAS_SKIN_COLOR)
		icon_key += "-[features["mcolor"]]"

	icon_key = "[icon_key][ethnicity][species.name]"

	if(bodyparts_render_key != icon_key)
		var/icon/stand_icon = new(species.icon_template ? species.icon_template : 'icons/mob/human.dmi',"blank")

		bodyparts_render_key = icon_key

		remove_overlay(BODYPARTS_LAYER)

		var/icon/base_icon
		if(!force_cache_update && GLOB.human_icon_cache[icon_key])
			//Icon is cached, use existing icon.
			base_icon = GLOB.human_icon_cache[icon_key]

				//log_debug("Retrieved cached mob icon ([icon_key] \icon[GLOB.human_icon_cache[icon_key]]) for [src].")

		else

		//BEGIN CACHED ICON GENERATION.

			// Why don't we just make skeletons/shadows/golems a species? ~Z
			var/race_icon =   species.icobase
			var/deform_icon = species.icobase

			//Robotic limbs are handled in get_icon() so all we worry about are missing or dead limbs.
			//No icon stored, so we need to start with a basic one.
			var/datum/limb/chest = get_limb("chest")
			base_icon = chest.get_icon(race_icon,deform_icon,g)
			if(chest.limb_status & LIMB_NECROTIZED)
				base_icon.ColorTone(necrosis_color_mod)
				base_icon.SetIntensity(0.7)

			for(var/datum/limb/part in limbs)

				var/icon/temp //Hold the bodypart icon for processing.

			//That part makes left and right legs drawn topmost and lowermost when human looks WEST or EAST
			//And no change in rendering for other parts (they icon_position is 0, so goes to 'else' part)
				if(part.limb_status & LIMB_DESTROYED)
					continue

				if(istype(part, /datum/limb/chest)) //already done above
					continue

				if (istype(part, /datum/limb/groin) || istype(part, /datum/limb/head))
					temp = part.get_icon(race_icon,deform_icon,g)
				else
					temp = part.get_icon(race_icon,deform_icon)

				if(part.limb_status & LIMB_NECROTIZED)
					temp.ColorTone(necrosis_color_mod)
					temp.SetIntensity(0.7)

				//That part makes left and right legs drawn topmost and lowermost when human looks WEST or EAST
				//And no change in rendering for other parts (they icon_position is 0, so goes to 'else' part)
				if(part.icon_position&(LEFT|RIGHT))

					var/icon/temp2 = new('icons/mob/human.dmi',"blank")

					temp2.Insert(new/icon(temp,dir=NORTH),dir=NORTH)
					temp2.Insert(new/icon(temp,dir=SOUTH),dir=SOUTH)

					if(!(part.icon_position & LEFT))
						temp2.Insert(new/icon(temp,dir=EAST),dir=EAST)

					if(!(part.icon_position & RIGHT))
						temp2.Insert(new/icon(temp,dir=WEST),dir=WEST)

					base_icon.Blend(temp2, ICON_OVERLAY)

					if(part.icon_position & LEFT)
						temp2.Insert(new/icon(temp,dir=EAST),dir=EAST)

					if(part.icon_position & RIGHT)
						temp2.Insert(new/icon(temp,dir=WEST),dir=WEST)

					base_icon.Blend(temp2, ICON_UNDERLAY)

				else

					base_icon.Blend(temp, ICON_OVERLAY)

	//END CACHED ICON GENERATION.

			GLOB.human_icon_cache[icon_key] = base_icon

			//log_debug("Generated new cached mob icon ([icon_key] \icon[GLOB.human_icon_cache[icon_key]]) for [src]. [GLOB.human_icon_cache.len] cached mob icons.")

		//END CACHED ICON GENERATION.
		stand_icon.Blend(base_icon,ICON_OVERLAY)

		//Skin colour. Is in cache
		if (species.species_flags & HAS_SKIN_COLOR)
			stand_icon.Blend("#"+features["mcolor"], ICON_MULTIPLY)

		if(has_head)
			//Eyes
			var/icon/eyes = new/icon('icons/mob/human_face.dmi', species.eyes)
			eyes.Blend(rgb(r_eyes, g_eyes, b_eyes), ICON_ADD)
			stand_icon.Blend(eyes, ICON_OVERLAY)

			//Mouth	(lipstick!)
			if(lip_style && (species?.species_flags & HAS_LIPS))	//skeletons are allowed to wear lipstick no matter what you think, agouri.
				stand_icon.Blend(new/icon('icons/mob/human_face.dmi', "camo_[lip_style]_s"), ICON_OVERLAY)

		icon = null
		overlays_standing[BODYPARTS_LAYER] = image(stand_icon, layer = -BODYPARTS_LAYER)
		apply_overlay(BODYPARTS_LAYER)

	species?.update_body(src)
	update_body_markings()
	update_mutant_bodyparts()
	update_underwear()

/mob/living/carbon/human/proc/update_underwear()
	remove_overlay(UNDERWEAR_LAYER)
	if(species.species_flags & HAS_UNDERWEAR && show_underwear)
		//Underwear
		var/g = (gender == FEMALE) ? "f" : "m"
		var/icon/stand_icon = new('icons/mob/human.dmi',"blank")
		if(underwear == 1)
			stand_icon.Blend(new /icon('icons/mob/human.dmi', "blank"), ICON_OVERLAY)
		else if(underwear == 2 || underwear == 3)
			stand_icon.Blend(new /icon('icons/mob/human.dmi', "cryo[underwear]_[g]_s"), ICON_OVERLAY)

		if(ismarinejob(job)) //undoing override
			if(undershirt > 0 && undershirt < 5)
				stand_icon.Blend(new /icon('icons/mob/human.dmi', "cryoshirt[undershirt]_s"), ICON_OVERLAY)
		else if(undershirt > 0 && undershirt < 7)
			stand_icon.Blend(new /icon('icons/mob/human.dmi', "cryoshirt[undershirt]_s"), ICON_OVERLAY)
		overlays_standing[UNDERWEAR_LAYER] = image(stand_icon, layer = -UNDERWEAR_LAYER)
		apply_overlay(UNDERWEAR_LAYER)

/mob/living/carbon/human/proc/update_body_markings(forced_colour)
	if(!body_markings)
		remove_overlay(BODY_MARKINGS_LAYER)
		return
	var/g = (gender == FEMALE) ? "f" : "m"
	remove_overlay(BODY_MARKINGS_LAYER)
	var/override_color
	var/list/standing = list()
	for(var/datum/limb/part in limbs)
		var/body_zone = GLOB.bitflag_limb_to_string["[part.body_part]"]
		if(!body_markings[body_zone])
			continue
		for(var/key in body_markings[body_zone])
			var/datum/body_marking/BM = GLOB.body_markings[key]
			var/render_limb_string = body_zone
			switch(body_zone)
				/*
				if(BODY_ZONE_R_LEG, BODY_ZONE_L_LEG)
					if(use_digitigrade)
						render_limb_string = "digitigrade_[use_digitigrade]_[render_limb_string]"
				*/
				if(BODY_ZONE_CHEST)
					if(BM.gendered)
						render_limb_string = "[render_limb_string]_[g]"
			var/mutable_appearance/accessory_overlay = mutable_appearance(BM.icon, "[BM.icon_state]_[render_limb_string]", -BODY_MARKINGS_LAYER)
			if(override_color)
				accessory_overlay.color = "#[override_color]"
			else
				accessory_overlay.color = "#[body_markings[body_zone][key]]"
			standing += accessory_overlay
	overlays_standing[BODY_MARKINGS_LAYER] = standing
	apply_overlay(BODY_MARKINGS_LAYER)

/mob/living/carbon/human/proc/update_mutant_bodyparts(forced_colour)
	if(!mutant_bodyparts)
		remove_overlay(BODY_BEHIND_LAYER)
		remove_overlay(BODY_ADJ_LAYER)
		remove_overlay(BODY_FRONT_LAYER)
		return
	var/g = (gender == FEMALE) ? "f" : "m"

	var/list/bodyparts_to_add = list()
	var/new_renderkey = "[species.name]"

	for(var/key in mutant_bodyparts)
		var/datum/mutant_accessory/S = GLOB.mutant_accessories[key][mutant_bodyparts[key][MUTANT_INDEX_NAME]]
		if(!S || S.icon_state == "none")
			continue
		if(S.is_hidden(src))
			continue
		var/render_state
		if(S.special_render_case)
			render_state = S.get_special_render_state(src)
		else
			render_state = S.icon_state
		new_renderkey += "-[key]-[render_state]"
		bodyparts_to_add[S] = render_state

	if(new_renderkey == mutant_parts_render_key)
		return

	mutant_parts_render_key = new_renderkey

	remove_overlay(BODY_BEHIND_LAYER)
	remove_overlay(BODY_ADJ_LAYER)
	remove_overlay(BODY_FRONT_LAYER)

	var/list/standing	= list()

	var/specific_alpha = species.specific_alpha

	for(var/bodypart in bodyparts_to_add)
		var/datum/mutant_accessory/S = bodypart
		var/key = S.key

		var/x_shift = S.dimension_x
		var/render_state = bodyparts_to_add[S]

		var/override_color = forced_colour
		if(!override_color && S.special_colorize)
			override_color = S.get_special_render_colour(src, render_state)

		if(S.gender_specific)
			render_state = "[g]_[key]_[render_state]"
		else
			render_state = "m_[key]_[render_state]"

		for(var/layer in S.relevent_layers)
			var/layertext = mutant_bodyparts_layertext(layer)

			var/mutable_appearance/accessory_overlay = mutable_appearance(S.icon, layer = -layer)

			accessory_overlay.icon_state = "[render_state]_[layertext]"

			if(S.center)
				accessory_overlay = center_image(accessory_overlay, x_shift, S.dimension_y)


			if(!override_color)
				/*
				if(HAS_TRAIT(src, TRAIT_HUSK))
					if(S.color_src == USE_MATRIXED_COLORS) //Matrixed+husk needs special care, otherwise we get sparkle dogs
						accessory_overlay.color = HUSK_COLOR_LIST
					else
						accessory_overlay.color = "#AAA" //The gray husk color
				else
				*/
				switch(S.color_src)
					if(USE_ONE_COLOR)
						accessory_overlay.color = "#"+mutant_bodyparts[key][MUTANT_INDEX_COLOR_LIST][1]
					if(USE_MATRIXED_COLORS)
						var/list/color_list = mutant_bodyparts[key][MUTANT_INDEX_COLOR_LIST]
						var/alpha_value = specific_alpha //this is here and not with the alpha setting code below as setting the alpha on a matrix color mutable appearance breaks it (at least in this case)
						var/list/finished_list = list()
						finished_list += ReadRGB("[color_list[1]]00")
						finished_list += ReadRGB("[color_list[2]]00")
						finished_list += ReadRGB("[color_list[3]]00")
						finished_list += list(0,0,0,alpha_value)
						for(var/index in 1 to finished_list.len)
							finished_list[index] /= 255
						accessory_overlay.color = finished_list
					if(MUTCOLORS)
						accessory_overlay.color = "#[features["mcolor"]]"
					if(HAIR)
						accessory_overlay.color = "[rgb(r_hair, g_hair, b_hair)]"
					if(FACEHAIR)
						accessory_overlay.color = "[rgb(r_facial, g_facial, b_facial)]"
					if(EYECOLOR)
						accessory_overlay.color = "[rgb(r_eyes, g_eyes, b_eyes)]"
			else
				accessory_overlay.color = override_color
			standing += accessory_overlay

			//Here's EXTRA parts of accessories which I should get rid of sometime TODO i guess
			if(S.extra) //apply the extra overlay, if there is one
				var/mutable_appearance/extra_accessory_overlay = mutable_appearance(S.icon, layer = -layer)
				if(S.gender_specific)
					extra_accessory_overlay.icon_state = "[g]_[key]_extra_[S.icon_state]_[layertext]"
				else
					extra_accessory_overlay.icon_state = "m_[key]_extra_[S.icon_state]_[layertext]"
				if(S.center)
					extra_accessory_overlay = center_image(extra_accessory_overlay, S.dimension_x, S.dimension_y)


				switch(S.extra_color_src) //change the color of the extra overlay
					if(MUTCOLORS)
						extra_accessory_overlay.color = "#[features["mcolor"]]"
					if(MUTCOLORS2)
						extra_accessory_overlay.color = "#[features["mcolor2"]]"
					if(MUTCOLORS3)
						extra_accessory_overlay.color = "#[features["mcolor3"]]"
					if(HAIR)
						accessory_overlay.color = "[rgb(r_hair, g_hair, b_hair)]"
					if(FACEHAIR)
						accessory_overlay.color = "[rgb(r_facial, g_facial, b_facial)]"
					if(EYECOLOR)
						accessory_overlay.color = "[rgb(r_eyes, g_eyes, b_eyes)]"

				standing += extra_accessory_overlay

			if(S.extra2) //apply the extra overlay, if there is one
				var/mutable_appearance/extra2_accessory_overlay = mutable_appearance(S.icon, layer = -layer)
				if(S.gender_specific)
					extra2_accessory_overlay.icon_state = "[g]_[key]_extra2_[S.icon_state]_[layertext]"
				else
					extra2_accessory_overlay.icon_state = "m_[key]_extra2_[S.icon_state]_[layertext]"
				if(S.center)
					extra2_accessory_overlay = center_image(extra2_accessory_overlay, S.dimension_x, S.dimension_y)

				switch(S.extra2_color_src) //change the color of the extra overlay
					if(MUTCOLORS)
						extra2_accessory_overlay.color = "#[features["mcolor"]]"
					if(MUTCOLORS2)
						extra2_accessory_overlay.color = "#[features["mcolor2"]]"
					if(MUTCOLORS3)
						extra2_accessory_overlay.color = "#[features["mcolor3"]]"
					if(HAIR)
						accessory_overlay.color = "[rgb(r_hair, g_hair, b_hair)]"
					if(FACEHAIR)
						accessory_overlay.color = "[rgb(r_facial, g_facial, b_facial)]"
					if(EYECOLOR)
						accessory_overlay.color = "[rgb(r_eyes, g_eyes, b_eyes)]"

				standing += extra2_accessory_overlay
			if (specific_alpha != 255 && !override_color)
				for (var/ov in standing)
					var/image/overlay = ov
					if (!istype(overlay.color,/list)) //check for a list because setting the alpha of the matrix colors breaks the color (the matrix alpha is set above inside the matrix)
						overlay.alpha = specific_alpha

			overlays_standing[layer] += standing
			standing = list()

	apply_overlay(BODY_BEHIND_LAYER)
	apply_overlay(BODY_ADJ_LAYER)
	apply_overlay(BODY_FRONT_LAYER)

	return //

//HAIR OVERLAY
/mob/living/carbon/human/proc/update_hair()
	//Reset our hair
	remove_overlay(HAIR_LAYER)

	if(species.species_flags & HAS_NO_HAIR)
		return

	var/datum/limb/head/head_organ = get_limb("head")
	if(!head_organ || (head_organ.limb_status & LIMB_DESTROYED) )
		return

	//masks and helmets can obscure our hair.
	if((head?.flags_inv_hide & HIDEALLHAIR) || (wear_mask?.flags_inv_hide & HIDEALLHAIR))
		return

	//base icons
	var/icon/face_standing	= new /icon('icons/mob/human_face.dmi',"bald_s")

	if(f_style && !(wear_suit?.flags_inv_hide & HIDELOWHAIR) && !(wear_mask?.flags_inv_hide & HIDELOWHAIR))
		var/datum/sprite_accessory/facial_hair_style = GLOB.facial_hair_styles_list[f_style]
		if(facial_hair_style && facial_hair_style.species_allowed && (species.name in facial_hair_style.species_allowed))
			var/icon/facial_s = new/icon("icon" = facial_hair_style.icon, "icon_state" = "[facial_hair_style.icon_state]_s")
			if(facial_hair_style.do_colouration)
				facial_s.Blend(rgb(r_facial, g_facial, b_facial), ICON_ADD)

			face_standing.Blend(facial_s, ICON_OVERLAY)

	if(h_style && !(head?.flags_inv_hide & HIDETOPHAIR))
		var/datum/sprite_accessory/hair_style = GLOB.hair_styles_list[h_style]
		if(hair_style && (species.name in hair_style.species_allowed))
			var/icon/hair_s = new/icon("icon" = hair_style.icon, "icon_state" = "[hair_style.icon_state]_s")
			if(hair_style.do_colouration)
				var/icon/grad_s
				if(grad_style && grad_style != "None")
					var/datum/sprite_accessory/gradient = GLOB.hair_gradients_list[grad_style]
					grad_s = new/icon("icon" = gradient.icon, "icon_state" = gradient.icon_state)
					grad_s.Blend(hair_s, ICON_ADD)
					grad_s.Blend(rgb(r_grad, g_grad, b_grad), ICON_ADD)
				hair_s.Blend(rgb(r_hair, g_hair, b_hair), ICON_ADD)
				if(!isnull(grad_s))
					hair_s.Blend(grad_s, ICON_OVERLAY)

			face_standing.Blend(hair_s, ICON_OVERLAY)

	overlays_standing[HAIR_LAYER]	= image("icon"= face_standing, "layer" =-HAIR_LAYER)

	apply_overlay(HAIR_LAYER)

//Call when target overlay should be added/removed
/mob/living/carbon/human/update_targeted()
	remove_overlay(TARGETED_LAYER)
	var/image/I
	if(holo_card_color)
		if(I)
			I.overlays += image("icon" = 'icons/effects/Targeted.dmi', "icon_state" = "holo_card_[holo_card_color]")
		else
			I = image("icon" = 'icons/effects/Targeted.dmi', "icon_state" = "holo_card_[holo_card_color]", "layer" =-TARGETED_LAYER)
	if(I)
		overlays_standing[TARGETED_LAYER] = I
	apply_overlay(TARGETED_LAYER)


/* --------------------------------------- */
//For legacy support.
/mob/living/carbon/human/regenerate_icons()
	update_mutations(0)
	update_inv_w_uniform()
	update_inv_wear_id()
	update_inv_gloves()
	update_inv_glasses()
	update_inv_ears()
	update_inv_shoes()
	update_inv_s_store()
	update_inv_wear_mask()
	update_inv_head()
	update_inv_belt()
	update_inv_back()
	update_inv_wear_suit()
	update_inv_r_hand()
	update_inv_l_hand()
	update_inv_handcuffed()
	update_inv_pockets()
	update_fire()
	update_burst()
	UpdateDamageIcon()
	update_transform()
	update_headbite()
	update_underwear()
	update_mutant_bodyparts()
	update_body_markings()

/* --------------------------------------- */
//vvvvvv UPDATE_INV PROCS vvvvvv

/mob/living/carbon/human/update_inv_w_uniform()
	remove_overlay(UNIFORM_LAYER)
	update_mutant_bodyparts()
	if(!w_uniform)
		return
	if(client && hud_used?.hud_shown && hud_used.inventory_shown)
		w_uniform.screen_loc = ui_iclothing
		client.screen += w_uniform

	if(wear_suit?.flags_inv_hide & HIDEJUMPSUIT)
		return

	overlays_standing[UNIFORM_LAYER] = w_uniform.make_worn_icon(body_type = species.name, slot_name = slot_w_uniform_str, default_icon = 'icons/mob/uniform_0.dmi', default_layer = UNIFORM_LAYER)

	apply_overlay(UNIFORM_LAYER)
	species?.update_inv_w_uniform(src)

/mob/living/carbon/human/update_inv_wear_id()
	remove_overlay(ID_LAYER)
	if(!wear_id)
		return

	if(client && hud_used?.hud_shown)
		wear_id.screen_loc = ui_id
		client.screen += wear_id

	if(w_uniform?.displays_id || istype(wear_id, /obj/item/card/id/dogtag))
		overlays_standing[ID_LAYER]	= wear_id.make_worn_icon(body_type = species.name, slot_name = slot_wear_id_str, default_icon = 'icons/mob/mob.dmi', default_layer = ID_LAYER)

	apply_overlay(ID_LAYER)


/mob/living/carbon/human/update_inv_gloves()
	remove_overlay(GLOVES_LAYER)
	if(gloves)
		if(client && hud_used?.hud_shown && hud_used.inventory_shown)
			gloves.screen_loc = ui_gloves
			client.screen += gloves
		overlays_standing[GLOVES_LAYER]	= gloves.make_worn_icon(body_type = species.name, slot_name = slot_gloves_str, default_icon = 'icons/mob/hands.dmi', default_layer = GLOVES_LAYER)
		apply_overlay(GLOVES_LAYER)
		return

	if(!blood_color || !bloody_hands)
		return
	var/datum/limb/left_hand = get_limb("l_hand")
	var/datum/limb/right_hand = get_limb("r_hand")
	var/image/bloodsies
	if(left_hand.limb_status & LIMB_DESTROYED)
		if(right_hand.limb_status & LIMB_DESTROYED)
			return //No hands.
		bloodsies = image("icon" = 'icons/effects/blood.dmi', "icon_state" = "bloodyhand_right") //Only right hand.
	else if(right_hand.limb_status & LIMB_DESTROYED)
		bloodsies = image("icon" = 'icons/effects/blood.dmi', "icon_state" = "bloodyhand_left") //Only left hand.
	else
		bloodsies = image("icon" = 'icons/effects/blood.dmi', "icon_state" = "bloodyhands") //Both hands.

	bloodsies.color = blood_color
	overlays_standing[GLOVES_LAYER]	= bloodsies
	apply_overlay(GLOVES_LAYER)


/mob/living/carbon/human/update_inv_glasses()
	remove_overlay(GLASSES_LAYER)
	remove_overlay(GOGGLES_LAYER)
	if(!glasses)
		return
	if(client &&  hud_used?.hud_shown && hud_used.inventory_shown)
		glasses.screen_loc = ui_glasses
		client.screen += glasses
	if(glasses.goggles)
		overlays_standing[GOGGLES_LAYER] = glasses.make_worn_icon(body_type = species.name, slot_name = slot_glasses_str, default_icon = 'icons/mob/eyes.dmi', default_layer = GOGGLES_LAYER)
		apply_overlay(GOGGLES_LAYER)

	else
		overlays_standing[GLASSES_LAYER] = glasses.make_worn_icon(body_type = species.name, slot_name = slot_glasses_str, default_icon = 'icons/mob/eyes.dmi', default_layer = GLASSES_LAYER)
		apply_overlay(GLASSES_LAYER)

/mob/living/carbon/human/update_inv_ears()
	remove_overlay(EARS_LAYER)
	if(!wear_ear)
		return

	if(client && hud_used?.hud_shown && hud_used.inventory_shown)
		wear_ear.screen_loc = ui_wear_ear
		client.screen += wear_ear
	if((head?.flags_inv_hide & HIDEEARS) || (wear_mask?.flags_inv_hide & HIDEEARS))
		return

	overlays_standing[EARS_LAYER] = wear_ear.make_worn_icon(body_type = species.name, slot_name = slot_ear_str, default_icon = 'icons/mob/ears.dmi', default_layer = EARS_LAYER)
	apply_overlay(EARS_LAYER)

/mob/living/carbon/human/update_inv_shoes()
	remove_overlay(SHOES_LAYER)
	if(shoes)
		if(client && hud_used?.hud_shown && hud_used.inventory_shown)
			shoes.screen_loc = ui_shoes
			client.screen += shoes
	if(wear_suit?.flags_inv_hide & HIDESHOES)
		return

	if(shoes)
		overlays_standing[SHOES_LAYER] = shoes.make_worn_icon(body_type = species.name, slot_name = slot_shoes_str, default_icon = 'icons/mob/feet.dmi', default_layer = SHOES_LAYER)
	else if(feet_blood_color)
		var/image/bloodsies = image("icon" = 'icons/effects/blood.dmi', "icon_state" = "shoeblood")
		bloodsies.color = feet_blood_color
		overlays_standing[SHOES_LAYER] = bloodsies

	apply_overlay(SHOES_LAYER)

/mob/living/carbon/human/update_inv_s_store()
	remove_overlay(SUIT_STORE_LAYER)
	if(!s_store)
		return

	if(client && hud_used?.hud_shown)
		s_store.screen_loc = ui_sstore1
		client.screen += s_store

	overlays_standing[SUIT_STORE_LAYER] = s_store.make_worn_icon(body_type = species.name, slot_name = slot_s_store_str, default_icon = 'icons/mob/suit_slot.dmi', default_layer = SUIT_STORE_LAYER)
	apply_overlay(SUIT_STORE_LAYER)



/mob/living/carbon/human/update_inv_head()
	remove_overlay(HEAD_LAYER)
	update_mutant_bodyparts()
	if(!head)
		return

	if(client && hud_used?.hud_shown && hud_used.inventory_shown)
		head.screen_loc = ui_head
		client.screen += head

	overlays_standing[HEAD_LAYER] = head.make_worn_icon(body_type = species.name, slot_name = slot_head_str, default_icon = 'icons/mob/head_0.dmi', default_layer = HEAD_LAYER)

	apply_overlay(HEAD_LAYER)
	species?.update_inv_head(src)

/mob/living/carbon/human/update_inv_belt()
	remove_overlay(BELT_LAYER)
	if(!belt)
		return

	if(client && hud_used?.hud_shown)
		belt.screen_loc = ui_belt
		client.screen += belt

	overlays_standing[BELT_LAYER] = belt.make_worn_icon(body_type = species.name, slot_name = slot_belt_str, default_icon = 'icons/mob/belt.dmi', default_layer = BELT_LAYER)

	apply_overlay(BELT_LAYER)


/mob/living/carbon/human/update_inv_wear_suit()
	remove_overlay(SUIT_LAYER)
	update_mutant_bodyparts()
	species?.update_inv_wear_suit(src)
	if(!wear_suit)
		return

	if(client && hud_used?.hud_shown && hud_used.inventory_shown)
		wear_suit.screen_loc = ui_oclothing
		client.screen += wear_suit

	overlays_standing[SUIT_LAYER] = wear_suit.make_worn_icon(body_type = species.name, slot_name = slot_wear_suit_str, default_icon = 'icons/mob/suit_0.dmi', default_layer = SUIT_LAYER)

	apply_overlay(SUIT_LAYER)

/mob/living/carbon/human/update_inv_pockets()
	if(l_store)
		if(client && hud_used?.hud_shown)
			l_store.screen_loc = ui_storage1
			client.screen += l_store
	if(r_store)
		if(client && hud_used?.hud_shown)
			r_store.screen_loc = ui_storage2
			client.screen += r_store


/mob/living/carbon/human/update_inv_wear_mask()
	remove_overlay(FACEMASK_LAYER)
	if(!wear_mask)
		return

	if(head?.flags_inv_hide & HIDEMASK)
		return

	if(client && hud_used?.hud_shown && hud_used.inventory_shown)
		wear_mask.screen_loc = ui_mask
		client.screen += wear_mask

	overlays_standing[FACEMASK_LAYER] = wear_mask.make_worn_icon(body_type = species.name, slot_name = slot_wear_mask_str, default_icon = 'icons/mob/mask.dmi', default_layer = FACEMASK_LAYER)

	apply_overlay(FACEMASK_LAYER)


/mob/living/carbon/human/update_inv_back()
	remove_overlay(BACK_LAYER)
	if(!back)
		return
	if(client && hud_used?.hud_shown)
		back.screen_loc = ui_back
		client.screen += back

	overlays_standing[BACK_LAYER] = back.make_worn_icon(body_type = species.name, slot_name = slot_back_str, default_icon = 'icons/mob/back.dmi', default_layer = BACK_LAYER)

	apply_overlay(BACK_LAYER)


/mob/living/carbon/human/update_inv_handcuffed()
	remove_overlay(HANDCUFF_LAYER)
	if(!handcuffed)
		return
	overlays_standing[HANDCUFF_LAYER] = handcuffed.make_worn_icon(body_type = species.name, slot_name = slot_handcuffed_str, default_icon = 'icons/mob/mob.dmi', default_layer = HANDCUFF_LAYER)
	apply_overlay(HANDCUFF_LAYER)


/mob/living/carbon/human/update_inv_r_hand()
	remove_overlay(R_HAND_LAYER)
	if(!r_hand)
		return
	if(client && hud_used?.hud_version != HUD_STYLE_NOHUD)
		client.screen += r_hand
		r_hand.screen_loc = ui_rhand

	overlays_standing[R_HAND_LAYER] = r_hand.make_worn_icon(body_type = species.name, inhands = TRUE, slot_name = slot_r_hand_str, default_icon = 'icons/mob/items_righthand_0.dmi', default_layer = R_HAND_LAYER)

	apply_overlay(R_HAND_LAYER)


/mob/living/carbon/human/update_inv_l_hand()
	remove_overlay(L_HAND_LAYER)
	if(!l_hand)
		return

	if(client && hud_used?.hud_version != HUD_STYLE_NOHUD)
		client.screen += l_hand
		l_hand.screen_loc = ui_lhand

	overlays_standing[L_HAND_LAYER] = l_hand.make_worn_icon(body_type = species.name, inhands = TRUE, slot_name = slot_l_hand_str, default_icon = 'icons/mob/items_lefthand_0.dmi', default_layer = L_HAND_LAYER)
	apply_overlay(L_HAND_LAYER)

// Used mostly for creating head items
/mob/living/carbon/human/proc/generate_head_icon()
//gender no longer matters for the mouth, although there should probably be seperate base head icons.
//	var/g = "m"
//	if (gender == FEMALE)	g = "f"

	//base icons
	var/icon/face_lying		= new /icon('icons/mob/human_face.dmi',"bald_l")

	if(f_style)
		var/datum/sprite_accessory/facial_hair_style = GLOB.facial_hair_styles_list[f_style]
		if(facial_hair_style)
			var/icon/facial_l = new/icon("icon" = facial_hair_style.icon, "icon_state" = "[facial_hair_style.icon_state]_l")
			facial_l.Blend(rgb(r_facial, g_facial, b_facial), ICON_ADD)
			face_lying.Blend(facial_l, ICON_OVERLAY)

	if(h_style)
		var/datum/sprite_accessory/hair_style = GLOB.hair_styles_list[h_style]
		if(hair_style)
			var/icon/hair_l = new/icon("icon" = hair_style.icon, "icon_state" = "[hair_style.icon_state]_l")
			hair_l.Blend(rgb(r_hair, g_hair, b_hair), ICON_ADD)
			face_lying.Blend(hair_l, ICON_OVERLAY)

	//Eyes
	// Note: These used to be in update_face(), and the fact they're here will make it difficult to create a disembodied head
	var/icon/eyes_l = new/icon('icons/mob/human_face.dmi', "eyes_l")
	eyes_l.Blend(rgb(r_eyes, g_eyes, b_eyes), ICON_ADD)
	face_lying.Blend(eyes_l, ICON_OVERLAY)

	if(lip_style)
		face_lying.Blend(new/icon('icons/mob/human_face.dmi', "lips_[lip_style]_l"), ICON_OVERLAY)

	var/image/face_lying_image = new /image(icon = face_lying)
	return face_lying_image

/mob/living/carbon/human/update_headbite()
	remove_overlay(HEADBITE_LAYER)
	var/image/standing
	if(headbitten)
		standing = image("icon" = 'icons/Xeno/Effects.dmi',"icon_state" = "headbite_stand", "layer" =-HEADBITE_LAYER)

	overlays_standing[HEADBITE_LAYER]	= standing
	apply_overlay(HEADBITE_LAYER)

/mob/living/carbon/human/update_fire()
	remove_overlay(FIRE_LAYER)
	if(on_fire)
		switch(fire_stacks)
			if(1 to 14)	overlays_standing[FIRE_LAYER] = image("icon"='icons/mob/OnFire.dmi', "icon_state"="Standing_weak", "layer"=-FIRE_LAYER)
			if(15 to 20) overlays_standing[FIRE_LAYER] = image("icon"='icons/mob/OnFire.dmi', "icon_state"="Standing_medium", "layer"=-FIRE_LAYER)

		apply_overlay(FIRE_LAYER)

//This exists so sprite accessories can still be per-layer without having to include that layer's
//number in their sprite name, which causes issues when those numbers change.
/proc/mutant_bodyparts_layertext(layer)
	switch(layer)
		if(BODY_BEHIND_LAYER)
			return "BEHIND"
		if(BODY_ADJ_LAYER)
			return "ADJ"
		if(BODY_FRONT_LAYER)
			return "FRONT"