/decl/communication_channel/necrochat
	name = "Necrochat"
	expected_communicator_type = /client
	flags = COMMUNICATION_NO_GUESTS
	log_proc = /proc/log_necro
	show_preference_setting = /datum/client_preference/show_necrochat

/decl/communication_channel/necrochat/can_ignore(var/client/C)
	.=..()
	if (.)
		if (C.mob && C.mob.is_necromorph())
			return FALSE	//Necromorphs must listen to the necrochat


/decl/communication_channel/necrochat/can_communicate(var/client/C, var/message)
	. = ..()
	if(!.)
		return

	if(!C.holder)
		if (!C.mob || !C.mob.is_necromorph()) //Gotta be a necromorph to use this
			return FALSE


/decl/communication_channel/necrochat/do_communicate(var/client/C, var/message)

	var/list/messaged = list()	//Clients we've already sent to. Used to prevent doublesending to admins who are also playing necromorphs

	var/style = "necromorph"
	var/sender_name = ""
	if (C && C.mob)

		if (issignal(C.mob))


			if (is_marker_master(C.mob))
				style = "necromarker"
				sender_name = "Marker([C.ckey])"
			else
				style = "necrosignal"
				sender_name = "Signal([C.ckey])"
		else
			sender_name = C.mob.name


	message = "<span class='[style]'>[sender_name ? sender_name+": ":""][message]</span>"

	for (var/ckey in SSnecromorph.necromorph_players)
		var/datum/player/P = SSnecromorph.necromorph_players[ckey]
		if (P)
			var/client/target = P.get_client()
			if (target)
				receive_communication(C, target, message)
				messaged += target
		else
			//Shouldn't happen
			log_debug("Found invalid necromorph player key with no associated player datum [ckey]")
			SSnecromorph.necromorph_players -= ckey

	var/list/valid_admins = GLOB.admins - messaged
	for(var/client/target in valid_admins)
		receive_communication(C, target, message)




/mob/observer/eye/signal/say(var/message)
	sanitize_and_communicate(/decl/communication_channel/necrochat, client, message)



/mob/living/carbon/human/necromorph/say(var/message)
	sanitize_and_communicate(/decl/communication_channel/necrochat, client, message)

	if(prob(species.speech_chance) && check_audio_cooldown(SOUND_SPEECH))
		set_audio_cooldown(SOUND_SPEECH, 5 SECONDS)
		play_species_audio(src, SOUND_SPEECH, VOLUME_LOW, TRUE)



//Global Necromorph Procs
//-------------------------
/proc/message_necromorphs(var/message, var/include_admins = TRUE, var/messaged = list())
	//Message all the necromorphs
	for (var/ckey in SSnecromorph.necromorph_players)
		var/datum/player/P = SSnecromorph.necromorph_players[ckey]
		var/mob/M = P.get_mob()
		if (!(M in messaged))
			to_chat(M, message)
			messaged += M


	//Message all the admins too, but only if they have show necrochat enabled
	var/list/valid_admins = GLOB.admins - messaged
	for(var/client/C in valid_admins)
		if ((C.mob in messaged))
			continue
		if(C.get_preference_value(/datum/client_preference/show_necrochat) == GLOB.PREF_SHOW)
			to_chat(C.mob, message)
			messaged += C.mob

	//Message all the unitologists too
	/*
	for(var/atom/M in GLOB.unitologists_list)
		to_chat(M, "<span class='cult'>[src]: [message]</span>")
		*/