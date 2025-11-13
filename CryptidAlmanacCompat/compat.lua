-- Note: Jen's dependencies will also have to be updated to not display as incompatible.

-- Things that are not yet included:
-- single hand planets don't use the new colors
-- Banned cards in challenges (I think these need a full update anyway)

-- encoded handling
SMODS.Back:take_ownership("b_cry_encoded", {
	apply = function(self)
		G.GAME.joker_rate = 1
		G.GAME.planet_rate = 1
		G.GAME.tarot_rate = 1
		G.GAME.code_rate = 1e100
		G.E_MANAGER:add_event(Event({
			func = function()
				if G.jokers then
					if
						G.P_CENTERS["j_cry_CodeJoker"]
						and (G.GAME.banned_keys and not G.GAME.banned_keys["j_cry_CodeJoker"])
					then
						local card = create_card("Joker", G.jokers, nil, nil, nil, nil, "j_cry_CodeJoker")
						card:add_to_deck()
						card:start_materialize()
						G.jokers:emplace(card)
					end
					return true
				end
			end,
		}))
	end,
})


Cryptid_config.gameset_toggle = false -- prevents changing gamesets. Easy.

function Cryptid.gameset(card, center)
    return "madness"
end

-- This will have to get added to Jen's process_loc_text function
function SMODS.current_mod.process_loc_text()
    G.localization.descriptions.Other["jen_pointer"] = {
        name = "POINTER://",
        text = {
            "Create a card",
            "of {C:cry_code}your choice",
            "{C:inactive,s:0.8}(Exotic Jokers and OMEGA consumables excluded)",
        },
    }
end

local uhtr = update_hand_text
function update_hand_text(config, vals)
	if not vals.colour then
		vals.colour = G.C.UI.TEXT_DARK
	end
	uhtr(config, vals)
end


-- a guide on what these new functions do is in Cryptid/items/pointer.lua
Cryptid.pointerblistify("j_jen_kosmos") -- here as an example
Cryptid.pointerblistifytype("rarity", "jen_wondrous")
Cryptid.pointerblistifytype("rarity", "jen_extraordinary")
Cryptid.pointerblistifytype("rarity", "jen_ritualistic")
Cryptid.pointerblistifytype("rarity", "jen_transcendent")
Cryptid.pointerblistifytype("rarity", "jen_omegatranscendent")
Cryptid.pointerblistifytype("rarity", "jen_omnipotent")
Cryptid.pointerblistifytype("rarity", "jen_miscellaneous")
Cryptid.pointerblistifytype("rarity", "jen_junk")
Cryptid.pointerblistifytype("set", "jen_omegaconsumable")

Cryptid.pointeraliasify("j_jen_kosmos", "Kosmos") -- also here as an example, this will have to be done for every alias (won't let you create kosmos because of blacklist)

-- the old pointer thing, it's still case insensitive though (unless it's 1 letter long)
local aliases = {
	freddy = "freddy snowshoe",
	paupovlin = "paupovlin revere",
	poppin = "paupovlin revere",
	dandy = 'Dandicus "Dandy" Dancifer',
	jen = "jen walter",
	jen2 = "Jen Walter the Wondergeist",
	jen3 = "Jen Walter the Wondergeist (Ascended)",
	survivor = "the survivor",
	monk = "the monk",
	hunter = "the hunter",
	gourmand = "the gourmand",
	saint = "the saint",
	genius = "the genius",
	r_fool = "the genius",
	scientist = "the scientist",
	r_magician = "the scientist",
	lowlaywoman = "the low laywoman",
	laywoman = "the low laywoman",
	r_priestess = "the low laywoman",
	peasant = "the peasant",
	r_empress = "the peasant",
	servant = "the servant",
	r_emperor = "the servant",
	adversary = "the adversary",
	r_hierophant = "the adversary",
	rivals = "the rivals",
	r_lovers = "the rivals",
	hitchhiker = "the hitchhiker",
	r_chariot = "the hitchhiker",
	injustice = "c_jen_reverse_justice",
	r_justice = "c_jen_reverse_justice",
	extrovert = "the extrovert",
	r_hermit = "the extrovert",
	discofpenury = "the disc of penury",
	r_wheeloffortune = "the disc of penury",
	r_wof = "the disc of penury",
	infirmity = "infirmity",
	r_strength = "infirmity",
	zen = "zen",
	r_hangedman = "zen",
	life = "life",
	r_death = "life",
	prodigality = "prodigality",
	r_temperance = "prodigality",
	angel = "the angel",
	r_devil = "the angel",
	collapse = "the collapse",
	r_tower = "the collapse",
	flash = "the flash",
	r_star = "the flash",
	eclipsespectral = "c_jen_reverse_moon",
	eclipsetorat = "c_jen_reverse_moon",
	r_moon = "c_jen_reverse_moon",
	darkness = "the darkness",
	r_sun = "the darkness",
	cunctation = "cunctation",
	r_judgement = "cunctation",
	desolate = "desolate",
	r_world = "desolate",
	-- jen tokens
	topuptoken = "top-up token",
	sagittarius = "sagittarius a*",
	["sagitarius a*"] = "sagittarius a*", --minor spelling mistakes are forgiven
	sagitarius = "sagittarius a*", --minor spelling mistakes are forgiven
}
