--Brought to you by the same person who made the quote "The Dark Ages of smods"
-- Re-brought to you by some guy who restored this modpack from the ashes.


-- Initialize hand level color sys loads

-- for mobile version
-- if G and G.C and G.C.HAND_L
-- if jl and jl.init_hand_level_colors then jl.init_hand_level_colors() end
-- end


-- Ensure global Jen table exists even if TOML init patch is absent
Jen = Jen or {}

maxArrow = 100

--Incantation.DelayStacking = Incantation.DelayStacking + 5

local maxfloat = 1.7976931348623157e308

local function checkerboard_text(txt)
	local str = ''
	local chars = jl.string_to_table(txt)
	local osc = false
	for i = 1, #chars do
		osc = not osc
		str = str .. '{X:' .. (osc and 'black' or 'inactive') .. ',C:' .. (osc and 'white' or 'black') .. '}' .. chars
			[i]
		if i == #chars then
			str = str .. '{}'
		end
	end
	return str
end


local function suit_to_uno(suit)
	suit = string.lower(suit)
	return suit == 'hearts' and 'red' or suit == 'spades' and 'blue' or suit == 'clubs' and 'green' or
		suit == 'diamonds' and 'yellow' or 'n/a'
end

local edited_default_colours = false
-- Provide Jen color globals normally injected via lovely.toml
if not G then G = {} end
if not G.C then G.C = {} end
G.C.jen_RGB = G.C.jen_RGB or { 0, 0, 0, 1 }
G.C.jen_RGB_HUE = G.C.jen_RGB_HUE or 0
G.C.almanac = G.C.almanac or { 0, 0, 1, 1 }
-- from cryptid.lua
SMODS.current_mod.optional_features = {
	retrigger_joker = true,
	post_trigger = true,
	--[[cardareas = {
		unscored = true,
		deck = true,
	},]]
	-- Here are some other ones Steamodded has
	-- Cryptid doesn't use them YET, but these should be uncommented if Cryptid uses them
	--[[
	quantum_enhancements = true,
	-- These ones add new card areas that Steamodded will calculate through
	-- Might already be useful for sticker calc
	cardareas = {
		discard = true,
	}
	]]
}

--COMMON STRINGS
local mayoverflow = '{C:inactive,s:0.65}(Does not require room, but may overflow)'
local redeemprev = '{s:0.75}Also redeems {C:attention,s:0.75}previous tier for free{s:0.75} if not yet acquired'

--INITIAL STUFF

local CFG = SMODS.current_mod.config



-- Initialize safety systems from ported lovely.toml patches
local function init_jen_safety_systems()
	-- Set up global lvcol function for Cryptid compatibility
	if not _G.lvcol then
		_G.lvcol = jl.lvcol
	end

	-- Initialize hand level color sys loads
	if G and G.C and G.C.HAND_LEVELS then
		if jl and jl.init_hand_level_colors
		then
			jl.init_hand_level_colors()
		end
	end

	-- Initialize Gateway destruction flag for "The Saint" protection
	if G and G.GAME then
		G.GAME.gateway_destroying_jokers = false
	end

	-- Install highlight guard (avoid highlighting non-play cards when extra scoring areas are active)
	if _G.highlight_card and not Jen._wrapped_highlight then
		Jen._wrapped_highlight = true
		local _orig_highlight_card = _G.highlight_card
		_G.highlight_card = function(card, ...)
			local cache = (G and G.GAME and G.GAME._jen_tick_cache) or nil
			local has_extra_scoring = cache and (cache.crimbo or cache.faceless)
				or (next(SMODS.find_card('j_jen_crimbo')) or next(SMODS.find_card('j_jen_faceless')))
			if card and card.area ~= G.play and has_extra_scoring then
				return
			end
			return _orig_highlight_card(card, ...)
		end
	end

	-- Initialize Cryptid compatibility functions (gameset, update_hand_text wrapper)
	-- Note: Encoded deck setup is done later in process_loc_text after all mods load
	if jl and jl.init_all_cryptid_compat then
		jl.init_all_cryptid_compat()
	end

	-- Ensure Crimbo/Faceless extra scoring cards are injected even without TOML patch
	if SMODS and SMODS.calculate_main_scoring and not Jen._wrapped_calc_main then
		Jen._wrapped_calc_main = true
		local _orig_calc_main = SMODS.calculate_main_scoring
		SMODS.calculate_main_scoring = function(context, scoring_hand)
			local cache = (G and G.GAME and G.GAME._jen_tick_cache) or nil
			local has_extra_scoring = cache and (cache.crimbo or cache.faceless)
				or (next(SMODS.find_card('j_jen_crimbo')) or next(SMODS.find_card('j_jen_faceless')))
			if scoring_hand and has_extra_scoring then
				if not G.GAME._jen_added_crimbo then
					add_crimbo_cards(scoring_hand)
					G.GAME._jen_added_crimbo = true
					Q(function()
						G.GAME._jen_added_crimbo = nil
						return true
					end)
				end
			end
			return _orig_calc_main(context, scoring_hand)
		end
	end

	-- Crash Fix for nil ability on cards
	-- Ensure `Card:update` and `Card:update_alert` are robust when `self.ability` is nil. Some mods/edge cases create cards without `ability` set transiently; provide safe defaults.
	local function _jen_safe_tostring(v)
		local ok, s = pcall(tostring, v)
		return ok and s or '<unprintable>'
	end

	local function _jen_log_nil_ability(card, ctx)
		pcall(function()
			local area = card and card.area or nil
			local cfg = card and card.config or nil
			local center = cfg and cfg.center or nil
			local id = card and (card.id or card.guid or '<no-id>') or '<no-card>'
			print(('JEN: nil ability found (%s) — id=%s area=%s facing=%s config.center=%s role=%s'):format(
				ctx or '?',
				_jen_safe_tostring(id),
				_jen_safe_tostring(area),
				_jen_safe_tostring(card and card.facing),
				_jen_safe_tostring(center),
				_jen_safe_tostring(card and card.role)
			))
		end)
	end

	-- Wrap Card.update to ensure ability exists and log when it's missing.
	local _orig_card_update = Card.update
	function Card:update(...)
		if not self then
			return _orig_card_update(self, ...)
		end
		if not self.ability then
			_jen_log_nil_ability(self, 'Card:update')
			self.ability = {}
		end
		return _orig_card_update(self, ...)
	end

	-- Wrap `update_alert` specifically to avoid crashes and keep existing behavior.
	local _orig_card_update_alert = Card.update_alert
	function Card:update_alert(...)
		if not self or not self.ability then
			if self then _jen_log_nil_ability(self, 'Card:update_alert') end
			return
		end
		return _orig_card_update_alert(self, ...)
	end
end

-- Register custom scoring calculations for arrow operators (deferred until colors are available)
local function register_arrow_scoring_calculations()
	if not SMODS or not SMODS.Scoring_Calculation then return false end
	if not G or not G.C then return false end

	-- Only register if not already registered
	if SMODS.Scoring_Calculations and SMODS.Scoring_Calculations.arrow_2 then return true end

	-- Register arrow_2 through arrow_5 with specific display text
	SMODS.Scoring_Calculation({
		key = 'arrow_2',
		func = function(self, chips, mult, flames)
			return to_big(chips):arrow(2, to_big(mult))
		end,
		text = '^^',
		colour = G.C.DARK_EDITION or { 0.8, 0.45, 0.85, 1 }
	})

	SMODS.Scoring_Calculation({
		key = 'arrow_3',
		func = function(self, chips, mult, flames)
			return to_big(chips):arrow(3, to_big(mult))
		end,
		text = '^^^',
		colour = G.C.CRY_EXOTIC or { 1, 0.5, 0, 1 }
	})

	SMODS.Scoring_Calculation({
		key = 'arrow_4',
		func = function(self, chips, mult, flames)
			return to_big(chips):arrow(4, to_big(mult))
		end,
		text = '^^^^',
		colour = G.C.CRY_EMBER or { 1, 0.2, 0.2, 1 }
	})

	SMODS.Scoring_Calculation({
		key = 'arrow_5',
		func = function(self, chips, mult, flames)
			return to_big(chips):arrow(5, to_big(mult))
		end,
		text = '^^^^^',
		colour = G.C.CRY_ASCENDANT or { 0.5, 1, 1, 1 }
	})

	-- Register arrow_6 through arrow_100 with {N} display format
	for i = 6, 100 do
		SMODS.Scoring_Calculation({
			key = 'arrow_' .. i,
			func = function(self, chips, mult, flames)
				return to_big(chips):arrow(i, to_big(mult))
			end,
			text = '{' .. i .. '}',
			colour = G.C.jen_RGB or { 1, 1, 1, 1 }
		})
	end

	return true
end

-- Hook into game initialization
local original_game_start_run = Game.start_run
function Game:start_run(args)
	init_jen_safety_systems()
	-- Register arrow scoring calculations if not already done
	if register_arrow_scoring_calculations then
		register_arrow_scoring_calculations()
	end
	-- Initialize Jen game defaults (migrated from lovely.toml patches)
	G.GAME.straddle = G.GAME.straddle or 0
	G.GAME.relief = G.GAME.relief or 0
	G.GAME.tension = G.GAME.tension or 0
	G.GAME.life = G.GAME.life or 100
	G.GAME.max_life = G.GAME.max_life or 100
	G.GAME.shield = G.GAME.shield or 0
	G.GAME.max_shield = G.GAME.max_shield or 0
	G.GAME.straddle_disp = G.GAME.straddle_disp or 0
	G.GAME.life_disp = G.GAME.life_disp or G.GAME.life
	G.GAME.max_life_disp = G.GAME.max_life_disp or G.GAME.max_life
	G.GAME.shield_disp = G.GAME.shield_disp or G.GAME.shield
	G.GAME.max_shield_disp = G.GAME.max_shield_disp or G.GAME.max_shield
	G.GAME.suits = G.GAME.suits or {}
	G.GAME.ranks = G.GAME.ranks or {}

	local result = original_game_start_run(self, args)

	-- Initialize scoring calculation based on current operator level
	-- This needs to happen after the game is initialized
	if get_final_operator and SMODS and SMODS.set_scoring_calculation then
		local op = get_final_operator()
		if op == 0 then
			SMODS.set_scoring_calculation('add')
		elseif op == 1 then
			SMODS.set_scoring_calculation('multiply')
		elseif op == 2 then
			SMODS.set_scoring_calculation('exponent')
		elseif op >= 3 then
			register_arrow_scoring_calculations()
			SMODS.set_scoring_calculation('arrow_' .. (op - 1))
		end
	end

	return result
end

-- Wondergeist leveling job processor
local function jen_start_wg_job(args)
	G.GAME._wg_jobs = G.GAME._wg_jobs or {}
	local key = tostring(args.hand_key) .. '|' .. tostring(args.op) .. '|' .. tostring(args.operand)
	local job = G.GAME._wg_jobs[key]
	if job then
		job.remaining = job.remaining + args.iterations
		job.total = (job.total or 0) + args.iterations
	else
		job = {
			hand_key = args.hand_key,
			op = args.op,
			operand = args.operand,
			remaining = args.iterations,
			total = args.iterations,
			chips = to_big(G.GAME.hands[args.hand_key].chips),
			mult = to_big(G.GAME.hands[args.hand_key].mult),
			batch_size = args.batch_size or 25,
			card = args.card,
			lv_instant = args.lv_instant,
			label = args.label,
		}
		G.GAME._wg_jobs[key] = job
	end
end

-- Screen wipe init flag: set during start_run to mirror TOML behavior safely
do
	local _orig_start_run = G and G.FUNCS and G.FUNCS.start_run
	if _orig_start_run and not Jen._wrapped_start_run then
		Jen._wrapped_start_run = true
		G.FUNCS.start_run = function(e, args)
			Jen.initialising = true
			local result = _orig_start_run(e, args)
			Q(function()
				Jen.initialising = nil
				return true
			end)
			return result
		end
	end
end

-- Also initialize when cards are first loaded
local original_init_game_object = Game.init_game_object
function Game:init_game_object()
	local result = original_init_game_object(self)
	init_jen_safety_systems()
	return result
end

-- UI Safety patch: Prevent UIElement color crashes
local original_uielement_draw_self = UIElement.draw_self
function UIElement:draw_self()
	-- Jen mod safety: ensure colour config is valid before drawing
	if self.config and self.config.colour == nil then
		self.config.colour = jl.safe_color(nil)
	end
	return original_uielement_draw_self(self)
end

-- Replace score intensity earned_score calculation safely (mirrors TOML patch)
local _orig_update_score_intensity = update_score_intensity
function update_score_intensity()
	local bigzero = to_big(0)
	if not G.GAME.blind or to_big(G.GAME.blind.chips or 0) <= bigzero then
		G.ARGS.score_intensity.earned_score = 0
	else
		G.ARGS.score_intensity.earned_score = get_chipmult_sum(G.GAME.current_round.current_hand.chips,
			G.GAME.current_round.current_hand.mult)
	end
	bigzero = nil
	local ret = _orig_update_score_intensity()
	-- Recalculate ambient and organ fields with OmegaNum safety when enabled
	if Big and Big.arrow and G.GAME.blind and to_big(G.GAME.blind.chips or 0) > to_big(0) then
		local notzero = to_big(G.ARGS.score_intensity.required_score) > to_big(0)
		local e_s = to_big(G.ARGS.score_intensity.earned_score)
		local r_s = to_big(G.ARGS.score_intensity.required_score + 1)
		local googol = to_big(1e100)
		local requirement5 = to_big(math.max(math.min(1, 0.1 * (math.log(e_s / (r_s:arrow(8, googol)), 5))), 0.))
		local requirement4 = to_big(math.max(math.min(1, 0.1 * (math.log(e_s / (r_s:arrow(3, googol)), 5))), 0.))
		local requirement3 = to_big(math.max(math.min(1, 0.1 * (math.log(e_s / (r_s:arrow(2, googol)), 5))), 0.))
		local requirement2 = to_big(math.max(math.min(1, 0.1 * (math.log(e_s / (r_s ^ googol), 5))), 0.))
		local requirement1 = math.max(math.min(1, 0.1 * math.log(e_s / (r_s * 1e100), 5)), 0.)
		if not G.ARGS.score_intensity.ambientDramatic then G.ARGS.score_intensity.ambientDramatic = 0 end
		if not G.ARGS.score_intensity.ambientSinister then G.ARGS.score_intensity.ambientSinister = 0 end
		if not G.ARGS.score_intensity.ambientSurreal3 then G.ARGS.score_intensity.ambientSurreal3 = 0 end
		if not G.ARGS.score_intensity.ambientSurreal2 then G.ARGS.score_intensity.ambientSurreal2 = 0 end
		if not G.ARGS.score_intensity.ambientSurreal1 then G.ARGS.score_intensity.ambientSurreal1 = 0 end
		G.ARGS.score_intensity.ambientDramatic = notzero and requirement5:to_number() or 0
		G.ARGS.score_intensity.ambientSinister = ((G.ARGS.score_intensity.ambientDramatic or 0) <= 0.05 and notzero) and
			requirement4:to_number() or 0
		if Jen and type(Jen) == 'table' then
			Jen.dramatic = G.ARGS.score_intensity.ambientDramatic > 0
			Jen.sinister = G.ARGS.score_intensity.ambientSinister > 0 or Jen.dramatic
		end
		G.ARGS.score_intensity.ambientSurreal3 = (not Jen.dramatic and not Jen.sinister) and requirement3:to_number() or
			0
		G.ARGS.score_intensity.ambientSurreal2 = ((not Jen.dramatic and not Jen.sinister) and (G.ARGS.score_intensity.ambientSurreal3 or 0) <= 0.05 and notzero) and
			requirement2:to_number() or 0
		G.ARGS.score_intensity.ambientSurreal1 = ((not Jen.dramatic and not Jen.sinister) and (G.ARGS.score_intensity.ambientSurreal3 or 0) <= 0.05 and (G.ARGS.score_intensity.ambientSurreal2 or 0) <= 0.05 and notzero) and
			requirement1 or 0
		G.ARGS.score_intensity.organ = (G.video_organ or ((G.ARGS.score_intensity.ambientSurreal3 or 0) <= 0.05 and (G.ARGS.score_intensity.ambientSurreal2 or 0) <= 0.05 and (G.ARGS.score_intensity.ambientSurreal1 or 0) <= 0.05 and notzero)) and
			math.max(
				math.min(1,
					0.1 * math.log(G.ARGS.score_intensity.earned_score / (G.ARGS.score_intensity.required_score + 1), 5)),
				0.) or 0
		notzero = nil
		e_s = nil
		r_s = nil
		googol = nil
		requirement5 = nil
		requirement4 = nil
		requirement3 = nil
		requirement2 = nil
		requirement1 = nil
	end
	return ret
end

-- Hook update_hand_text to ensure hand level colors are initialized
local original_update_hand_text = update_hand_text
function update_hand_text(config, vals)
	-- Ensure hand level colors are properly initialized for big numbers
	if G and G.C and G.C.HAND_LEVELS and not G.C.HAND_LEVELS_JEN_POPULATED then
		jl.init_hand_level_colors()
	end
	return original_update_hand_text(config, vals)
end

SMODS.Atlas {
	key = "modicon",
	path = "almanac_avatar.png",
	px = 34,
	py = 34
}

Jen = {
	fusions = {
		['Mutate Leshy'] = {
			cost = 50,
			output = 'j_jen_pawn',
			ingredients = {
				'j_jen_leshy',
				'j_jen_godsmarble'
			}
		},
		['Mutate Heket'] = {
			cost = 50,
			output = 'j_jen_knight',
			ingredients = {
				'j_jen_heket',
				'j_jen_godsmarble'
			}
		},
		['Mutate Kallamar'] = {
			cost = 50,
			output = 'j_jen_jester',
			ingredients = {
				'j_jen_kallamar',
				'j_jen_godsmarble'
			}
		},
		['Mutate Shamura'] = {
			cost = 50,
			output = 'j_jen_arachnid',
			ingredients = {
				'j_jen_shamura',
				'j_jen_godsmarble'
			}
		},
		['Mutate Lambert'] = {
			cost = 50,
			output = 'j_jen_reign',
			ingredients = {
				'j_jen_lambert',
				'j_jen_godsmarble'
			}
		},
		['Mutate Narinder'] = {
			cost = 50,
			output = 'j_jen_feline',
			ingredients = {
				'j_jen_narinder',
				'j_jen_godsmarble'
			}
		},
		['A M A L G A M A T E'] = {
			cost = 1e100,
			output = 'j_jen_amalgam',
			ingredients = {
				'j_jen_pawn',
				'j_jen_knight',
				'j_jen_jester',
				'j_jen_arachnid',
				'j_jen_reign',
				'j_jen_feline',
				'j_jen_sigil'
			}
		},
		['Mutate Clauneck'] = {
			cost = 50,
			output = 'j_jen_fateeater',
			ingredients = {
				'j_jen_clauneck',
				'j_jen_godsmarble'
			}
		},
		['Mutate Kudaai'] = {
			cost = 50,
			output = 'j_jen_foundry',
			ingredients = {
				'j_jen_kudaai',
				'j_jen_godsmarble'
			}
		},
		['Mutate Chemach'] = {
			cost = 50,
			output = 'j_jen_broken',
			ingredients = {
				'j_jen_chemach',
				'j_jen_godsmarble'
			}
		},
		['Mutate Aster Flynn'] = {
			cost = 5e3,
			output = 'j_jen_astrophage',
			ingredients = {
				'j_jen_aster',
				'j_jen_godsmarble'
			}
		},
		['Empower Landa Veris'] = {
			cost = 1e4,
			output = 'j_jen_bulwark',
			ingredients = {
				'j_jen_landa',
				'j_jen_godsmarble'
			}
		},
		['Corrupt Crimbo'] = {
			cost = 250,
			output = 'j_jen_faceless',
			ingredients = {
				'j_jen_crimbo',
				'j_jen_godsmarble'
			}
		},
		['Corrupt Alice'] = {
			cost = 5e3,
			output = 'j_jen_nexus',
			ingredients = {
				'j_jen_alice',
				'j_jen_godsmarble'
			}
		},
		['Corrupt Nyx'] = {
			cost = 1e3,
			output = 'j_jen_paragon',
			ingredients = {
				'j_jen_nyx',
				'j_jen_godsmarble'
			}
		},
		['Possess Oxy'] = {
			cost = 3e3,
			output = 'j_jen_inhabited',
			ingredients = {
				'j_jen_oxy',
				'j_jen_godsmarble'
			}
		},
		['Petrify Honey'] = {
			cost = 50,
			output = 'j_jen_cracked',
			ingredients = {
				'j_jen_honey',
				'j_jen_godsmarble'
			}
		},
		['Immolate Maxie'] = {
			cost = 2e3,
			output = 'j_jen_charred',
			ingredients = {
				'j_jen_maxie',
				'j_jen_godsmarble'
			}
		},
		['Empower Jen'] = {
			cost = 1e4,
			output = 'j_jen_wondergeist',
			ingredients = {
				'j_jen_jen',
				'j_jen_godsmarble'
			}
		},
		['Empower Jen (2nd Pass)'] = {
			cost = 1e6,
			output = 'j_jen_wondergeist2',
			ingredients = {
				'j_jen_wondergeist',
				'j_jen_godsmarble'
			}
		},
		['???'] = {
			cost = 1e100,
			output = 'c_jen_soul_omega',
			ingredients = {
				'c_soul',
				'c_black_hole',
				'c_jen_black_hole_omega',
				'c_cry_white_hole',
				'j_jen_godsmarble'
			}
		}
	},
	overpowered_rarities = {
		'jen_wondrous',
		'jen_extraordinary',
		'jen_ritualistic',
		'jen_transcendent',
		'jen_omegatranscendent',
		'jen_omnipotent',
		'jen_miscellaneous',
		'jen_junk'
	},
	locale_colours = {
		pink = 'FFAAD9',
		fuchsia = 'FF00B0',
		caramel = 'FFC14F',
		pastel_yellow = 'FFFC75',
		stone = '7A8087',
		darkstone = '53575B',
		lore = '9E2A9F',
		caption = '009A9A',
		uno = 'FF0000',
		almanac = '0000FF',
		blood = '880808'
	},
	config = {
		texture_pack = 'default',
		show_credits = true,
		show_captions = true,
		show_lore = true,
		astro = {
			initial = 0.70,
			increment = 0.002,
			decrement = 0.04,
			retrigger_mod = 2
		},
		suit_leveling = {
			Hearts = {
				chips = 1,
				mult = 5
			},
			Clubs = {
				chips = 5,
				mult = 1
			},
			Diamonds = {
				chips = 2,
				mult = 4
			},
			Spades = {
				chips = 4,
				mult = 2
			}
		},
		rank_leveling = {
			['2'] = {
				chips = 13,
				mult = 1
			},
			['3'] = {
				chips = 12,
				mult = 1
			},
			['4'] = {
				chips = 11,
				mult = 1
			},
			['5'] = {
				chips = 10,
				mult = 2
			},
			['6'] = {
				chips = 9,
				mult = 2
			},
			['7'] = {
				chips = 8,
				mult = 2
			},
			['8'] = {
				chips = 7,
				mult = 3
			},
			['9'] = {
				chips = 6,
				mult = 3
			},
			['10'] = {
				chips = 5,
				mult = 3
			},
			Jack = {
				chips = 4,
				mult = 4
			},
			Queen = {
				chips = 3,
				mult = 5
			},
			King = {
				chips = 2,
				mult = 6
			},
			Ace = {
				chips = 25,
				mult = 7
			},
		},
		wondrous_music = CFG.wondrous,
		extraordinary_music = CFG.extraordinary,
		save_compression_level = 9,
		punish_reroll_abuse = CFG.punish_reroll_abuse,
		shop_size_buff = 3,
		shop_voucher_count_buff = 2,
		shop_booster_pack_count_buff = 2,
		consumable_slot_count_buff = 18,
		verbose_astronomicon = false,
		verbose_astronomicon_omega = false,
		mana_cost = 25,
		HQ_vanillashaders = CFG.hq_shaders,
		malice_base = 3000,
		malice_increase = 1.13,
		omega_chance = 300,
		soul_omega_mod = 5,
		wee_sizemod = 1.5,
		-- Safety toggles for Kosmos/Malice calculation (enabled by default to avoid RAM spikes)
		safer_kosmos = true,
		kosmos_safety_threshold = 50, -- max malice tier increments processed per frame; remaining are deferred
		kosmos_gc_trigger_kb = 256000, -- trigger an early GC cycle if memory exceeds this (in KB). Was previously 1GB which is too late
		-- Malice scaling safety: set malice_exponent_cap to a number to approximate growth beyond that exponent, or nil/false for uncapped true formula
		malice_exponent_cap = 20,
		malice_cap_approximate = true, -- if true and malice_exponent_cap is set, use approximation instead of hard cap
		ante_threshold = 20,
		ante_pow10 = 100,
		ante_pow10_2 = 250,
		ante_pow10_3 = 500,
		ante_pow10_4 = 1000,
		ante_exponentiate = 50,
		ante_tetrate = 2500,
		ante_pentate = 5000,
		ante_polytate = 10000,
		polytate_factor = 1000,
		polytate_decrement = 1,
		scalar_base = 1,
		scalar_increment = .13,
		scalar_additivedivisor = 50,
		scalar_exponent = 1,
		straddle = {
			enabled = CFG.straddle,
			acceleration = true,
			skip_animation = CFG.straddle_skip_animation,
			backwards_mod = 2,
			progress_min = 3,
			progress_max = 7,
			progress_increment = 10
		},
		wondrous_music = CFG.wondrous,
		--[[
			Some cards/items while Almanac is installed are banned for at least one reason.
			These reasons could be, but are not necessarily limited to:
			- It's unreasonably exploitable (ex. Copy/Paste or Colorem creating infinite Code/Colour cards)
			- It's buggy/crashy
			- It doesn't fit with the context of Almanac
			- It's rendered too obsolete by Almanac's content
			- There is another card/item in Almanac which replaces it or does effectively the same thing

			Almanac still sticks with being intentionally unbalanced to oblivion. The bans are not done as an act to balance the mod; it's done as an act to give the recommended experience.
			
			If hardbanning an item (deleting it from the game on startup) causes crashes
			(apart from trying to continue a saved run that had the card),
			you can softban it (keep it on startup, but ban it from showing up in runs ASAP)
			by appending an exclamation mark (!) to the start of the codename.
			
			Almanac is best experienced with the banlist unmodified, but everyone is entitled to experience a mod how they want to experience it.
			If there's an item on here you'd prefer unbanned, comment it out by appending two hyphens (-) to the line (I recommend doing it that way) or deleting the line (not recommended).
			If you want to remove all bans; it's better to change the boolean below this text ("disable_bans") to true.
		]]
		disable_bans = CFG.disable_bans,
		bans = {
			--'example_of_commented_out_ban',
			'!j_cry_chocolate_dice',
			'!j_cry_curse_sob',
			'!j_cry_filler',
			'j_mf_colorem',
			'betm_jokers_j_balatro_mobile',
			'betm_jokers_j_gameplay_update',
			'betm_jokers_j_friends_of_jimbo',
			'c_ortalab_lot_hand',
			'j_cry_pity_prize',
			'j_cry_formidiulosus',
			'j_cry_oil_lamp', --I don't want it, keep it my friend
			'j_cry_tropical_smoothie',
			'!j_cry_jawbreaker',
			'j_cry_necromancer',
			'j_cry_mask',
			'j_cry_exposed',
			'j_cry_equilib',
			'j_cry_error',
			'j_cry_ghost',
			'j_cry_spy',
			'j_cry_copypaste',
			'j_cry_flip_side',
			'j_cry_crustulum', --crusty shit
			'j_sdm_cupidon',
			'j_sdm_0',
			'p_mupack_favoritepack',
			'c_prism_spectral_djinn',
			'e_cry_double_sided',
			'c_cry_meld',
			'c_cry_crash',
			'c_cry_rework',
			'c_cry_multiply',
			'c_cry_ctrl_v',
			'c_cry_ritual',
			'c_cry_adversary',
			'c_cry_chambered',
			'v_cry_double_down',
			'v_cry_double_slit',
			'v_cry_double_vision',
			'v_cry_curate',
			'e_cry_fragile',
			'bl_cruel_daring',
			'bl_cruel_reach',
			'bl_cry_obsidian_orb',
			'b_cry_e_deck',
			'b_cry_et_deck',
			'b_cry_sk_deck',
			'b_cry_st_deck',
			'b_cry_sl_deck',
		}
	}
}

function faceart(artist)
	return (Jen.config.texture_pack == 'default' and Jen.config.show_credits) and
		('{C:dark_edition,s:0.7,E:2}Floating sprite by : ' .. artist) or ''
end

function origin(world)
	return (Jen.config.texture_pack == 'default' and Jen.config.show_credits) and
		('{C:cry_exotic,s:0.7,E:2}Origin : ' .. world)
end

function au(world)
	return (Jen.config.texture_pack == 'default' and Jen.config.show_credits) and
		('{C:cry_blossom,s:0.7,E:2}A.U. : ' .. world)
end

function spriter(artist)
	return (Jen.config.texture_pack == 'default' and Jen.config.show_credits) and
		('{C:dark_edition,s:0.7,E:2}Sprite by : ' .. artist)
end

function caption(cap)
	return Jen.config.show_captions and ('{C:caption,s:0.7,E:1}' .. cap) or ''
end

function lore(txt)
	return Jen.config.show_lore and ('{C:lore,s:0.7,E:2}' .. txt) or ''
end

function init_cardbans()
	if not Jen.config.disable_bans then
		Jen:delete_hardbans()
	end
end

function Jen:delete_hardbans()
	for k, v in ipairs(Jen.config.bans) do
		if string.sub(v, 1, 1, true) ~= '!' then
			if G.P_CENTERS[v] then
				print('Deleting center : ' .. v)
				-- Safely attempt to delete the center object
				local success, err = pcall(function()
					local center_obj = SMODS.Center:get_obj(v)
					if center_obj and type(center_obj) == 'table' and center_obj.delete then
						center_obj:delete()
					end
				end)
				if not success then
					print('[JEN WARNING] Failed to delete center ' .. v .. ': ' .. tostring(err))
				end
				-- Instead of fully removing the center entry, replace it with a safe stub.
				G.P_CENTERS[v] = {
					_deleted_by_almanac = true,
					effect = "",
					name = "",
					set = 'Center',
				}
			elseif G.P_BLINDS[v] then
				G.P_BLINDS[v] = nil
			end
		end
	end
end

if Jen.config.HQ_vanillashaders then
	local background_shader = NFS.read(SMODS.current_mod.path .. 'assets/shaders/background.fs')
	local splash_shader = NFS.read(SMODS.current_mod.path .. 'assets/shaders/splash.fs')
	local flame_shader = NFS.read(SMODS.current_mod.path .. 'assets/shaders/flame.fs')
	G.SHADERS['background'] = love.graphics.newShader(background_shader)
	G.SHADERS['splash'] = love.graphics.newShader(splash_shader)
	G.SHADERS['flame'] = love.graphics.newShader(flame_shader)
end

local jen_modifierbadges = {
	unique = {
		text = {
			'Unique',
			'Can only own one copy'
		},
		col = HEX('8f00ff'),
		tcol = G.C.EDITION
	},
	fusable = {
		text = {
			'Fusable',
			'Can be combined'
		},
		col = G.C.GREEN,
		tcol = G.C.EDITION
	},
	immutable = {
		text = {
			'Immutable',
			'Unmodifiable values'
		},
		col = G.C.MONEY,
		tcol = G.C.CRY_TWILIGHT
	},
	dangerous = {
		text = {
			'Dangerous',
			'Unstable behaviour'
		},
		col = HEX('1a1a1a'),
		tcol = HEX('ff0000')
	},
	longful = {
		text = {
			'Longful',
			'Lengthy animations'
		},
		col = G.C.WHITE,
		tcol = G.C.JOKER_GREY
	},
	experimental = {
		text = {
			'Experimental',
			'May be very buggy'
		},
		col = G.C.FILTER,
		tcol = G.C.UI.TEXT_LIGHT
	},
	debuff_immune = {
		text = {
			'Impervious',
			'Cannot be debuffed'
		},
		col = G.C.JOKER_GREY,
		tcol = G.C.FILTER
	},
	permaeternal = {
		text = {
			'Permaeternal',
			'Has Eternal 24/7'
		},
		col = G.C.RED,
		tcol = G.C.UI.TEXT_LIGHT
	},
	dissolve_immune = {
		text = {
			'Indestructible',
			'Cannot dissolve'
		},
		col = G.C.CRY_AZURE,
		tcol = G.C.CRY_BLOSSOM
	},
	unhighlightable = {
		text = {
			'Unplayable/Unhighlightable',
			'Cannot select'
		},
		col = G.C.SECONDARY_SET.Tarot,
		tcol = G.C.SECONDARY_SET.Planet
	}
}

local evalcard_ref = eval_card
function eval_card(card, context)
	if card.playing_card and jl.sc(context) then
		if card.edition and card.edition.jen_wee then
			card_eval_status_text(card, 'extra', nil, nil, nil, {
				message = localize('k_upgrade_ex'),
				colour = G.C
					.FILTER
			})
			card.ability.wee_upgrades = (card.ability.wee_upgrades or 0) + (G.GAME.weeck and 3 or 1)
			card.ability.perma_bonus = (card.ability.perma_bonus or 0) +
				((((card.ability.name or '') == 'Stone Card' or card.config.center.no_rank) and 25 or card:get_id() == 2 and 60 or (card:get_id() * 3)) * (G.GAME.weeck and 3 or 1))
			card_eval_status_text(card, 'extra', nil, nil, nil,
				{ message = number_format(card.ability.perma_bonus), colour = G.C.CHIPS })
		end
		if card.gc and card:gc().set == 'Colour' and Jen.hv('colour', 1) then
			trigger_colour_end_of_round(card)
		end
	end
	return evalcard_ref(card, context)
end

local function calculate_scalefactor(text)
	local size = 0.9
	local font = G.LANG.font
	local max_text_width = 2 - 2 * 0.05 - 4 * 0.03 * size - 2 * 0.03
	local calced_text_width = 0
	for _, c in utf8.chars(text) do
		local tx = font.FONT:getWidth(c) * (0.33 * size) * G.TILESCALE * font.FONTSCALE +
			2.7 * 1 * G.TILESCALE * font.FONTSCALE
		calced_text_width = calced_text_width + tx / (G.TILESIZE * G.TILESCALE)
	end
	local scale_fac = calced_text_width > max_text_width and max_text_width / calced_text_width or 1
	return scale_fac
end

--borrowed from older version of cryptid
local smcmb = SMODS.create_mod_badges
function SMODS.create_mod_badges(obj, badges)
	smcmb(obj, badges)
	if obj and obj.misc_badge then
		local scale_fac = {}
		local scale_fac_len = 1
		if obj.misc_badge and obj.misc_badge.text then
			for i = 1, #obj.misc_badge.text do
				local calced_scale = calculate_scalefactor(obj.misc_badge.text[i])
				scale_fac[i] = calced_scale
				scale_fac_len = math.min(scale_fac_len, calced_scale)
			end
		end
		local ct = {}
		for i = 1, #obj.misc_badge.text do
			ct[i] = {
				string = obj.misc_badge.text[i]
			}
		end
		badges[#badges + 1] = {
			n = G.UIT.R,
			config = { align = "cm" },
			nodes = {
				{
					n = G.UIT.R,
					config = {
						align = "cm",
						colour = obj.misc_badge and obj.misc_badge.colour or G.C.RED,
						r = 0.1,
						minw = 2 / scale_fac_len,
						minh = 0.36,
						emboss = 0.05,
						padding = 0.03 * 0.9,
					},
					nodes = {
						{ n = G.UIT.B, config = { h = 0.1, w = 0.03 } },
						{
							n = G.UIT.O,
							config = {
								object = DynaText({
									string = ct or "ERROR",
									colours = { obj.misc_badge and obj.misc_badge.text_colour or G.C.WHITE },
									silent = true,
									float = true,
									shadow = true,
									offset_y = -0.03,
									spacing = 1,
									scale = 0.33 * 0.9,
								}),
							},
						},
						{ n = G.UIT.B, config = { h = 0.1, w = 0.03 } },
					},
				},
			},
		}
	end
	if obj then
		for k, v in pairs(jen_modifierbadges) do
			if obj[k] then
				local scale_fac = {}
				local scale_fac_len = 1
				if v.text then
					for i = 1, #v.text do
						local calced_scale = calculate_scalefactor(v.text[i])
						scale_fac[i] = calced_scale
						scale_fac_len = math.min(scale_fac_len, calced_scale)
					end
				end
				local ct = {}
				for i = 1, #v.text do
					ct[i] = {
						string = v.text[i]
					}
				end
				badges[#badges + 1] = {
					n = G.UIT.R,
					config = { align = "cm" },
					nodes = {
						{
							n = G.UIT.R,
							config = {
								align = "cm",
								colour = v and v.col or G.C.RED,
								r = 0.1,
								minw = 2 / scale_fac_len,
								minh = 0.36,
								emboss = 0.05,
								padding = 0.03 * 0.9,
							},
							nodes = {
								{ n = G.UIT.B, config = { h = 0.1, w = 0.03 } },
								{
									n = G.UIT.O,
									config = {
										object = DynaText({
											string = ct or "ERROR",
											colours = { v and v.tcol or G.C.WHITE },
											silent = true,
											float = true,
											shadow = true,
											offset_y = -0.03,
											spacing = 1,
											scale = 0.33 * 0.9,
										}),
									},
								},
								{ n = G.UIT.B, config = { h = 0.1, w = 0.03 } },
							},
						},
					},
				}
			end
		end
	end
end

--https://gist.github.com/efrederickson/4080372
local map = {
	I = 1,
	V = 5,
	X = 10,
	L = 50,
	C = 100,
	D = 500,
	M = 1000,
}
local numbers_roman = { 1, 5, 10, 50, 100, 500, 1000 }
local chars_roman = { "I", "V", "X", "L", "C", "D", "M" }
function roman(s)
	s = tonumber(s)
	if not s or s ~= s then error "Unable to convert to number" end
	if s == math.huge then error "Unable to convert infinity" end
	s = math.floor(s)
	if s <= 0 then return s end
	local ret = ""
	for i = #numbers_roman, 1, -1 do
		local num = numbers_roman[i]
		while s - num >= 0 and s > 0 do
			ret = ret .. chars_roman[i]
			s = s - num
		end
		--for j = i - 1, 1, -1 do
		for j = 1, i - 1 do
			local n2 = numbers_roman[j]
			if s - (num - n2) >= 0 and s < num and s > 0 and num - n2 ~= n2 then
				ret = ret .. chars_roman[j] .. chars_roman[i]
				s = s - (num - n2)
				break
			end
		end
	end
	return ret
end

function unroman(s)
	s = s:upper()
	local ret = 0
	local i = 1
	while i <= s:len() do
		local c = s:sub(i, i)
		if c ~= " " then
			local m = map[c] or error("Unknown Roman Numeral '" .. c .. "'")

			local next = s:sub(i + 1, i + 1)
			local nextm = map[next]

			if next and nextm then
				if nextm > m then
					ret = ret + (nextm - m)
					i = i + 1
				else
					ret = ret + m
				end
			else
				ret = ret + m
			end
		end
		i = i + 1
	end
	return ret
end

function start_straddle()
	if Jen.config.straddle.enabled then
		G.GAME.straddle_active = true
		G.GAME.straddle = G.GAME.straddle or 0
		G.GAME.straddle_progress = G.GAME.straddle_progress or 0
	end
end

local win_game_ref = win_game
function win_game()
	start_straddle()
	win_game_ref()
end

SMODS.Rarity {
	key = 'junk',
	loc_txt = {
		name = 'Junk'
	},
	badge_colour = G.C.JOKER_GREY
}

SMODS.Rarity {
	key = 'wondrous',
	loc_txt = {
		name = 'Wondrous'
	},
	badge_colour = G.C.CRY_EMBER
}

SMODS.Rarity {
	key = 'extraordinary',
	loc_txt = {
		name = 'Extraordinary'
	},
	badge_colour = G.C.CRY_AZURE
}

SMODS.Rarity {
	key = 'ritualistic',
	loc_txt = {
		name = 'Ritualistic'
	},
	badge_colour = G.C.BLACK
}

SMODS.Rarity {
	key = 'transcendent',
	loc_txt = {
		name = 'Transcendent'
	},
	badge_colour = G.C.jen_RGB
}

SMODS.Rarity {
	key = 'omegatranscendent',
	loc_txt = {
		name = 'Omegatranscendent'
	},
	badge_colour = G.C.CRY_ASCENDANT
}

SMODS.Rarity {
	key = 'omnipotent',
	loc_txt = {
		name = 'Omnipotent'
	},
	badge_colour = G.C.CRY_BLOSSOM
}

SMODS.Rarity {
	key = 'miscellaneous',
	loc_txt = {
		name = 'Miscellaneous'
	},
	badge_colour = G.C.JOKER_GREY
}

function Jen.hiddencard(card)
	if type(card) ~= 'table' then return false end
	if not G.GAME then return false end
	return (((card.name or '') == 'Black Hole' or (card.name or '') == 'The Soul' or card.hidden) and not G.GAME.obsidian) or
		card.hidden2
end

function Jen.overpowered(rarity)
	if type(rarity) == 'number' then return false end
	return jl.bf(rarity, Jen.overpowered_rarities)
end

function Card:speak(text, col)
	if type(text) == 'table' then text = text[math.random(#text)] end
	card_eval_status_text(self, 'extra', nil, nil, nil, { message = text, colour = col or G.C.FILTER })
end

local random_editions = {
	'foil',
	'holo',
	'polychrome',
	'jen_chromatic',
	'jen_polygloss',
	'jen_gilded',
	'jen_sequin',
	'jen_laminated',
	'jen_ink',
	'jen_prismatic',
	'jen_watered',
	'jen_sepia',
	'jen_reversed',
	'jen_diplopia',
	'cry_gold',
	'cry_mosaic',
	'cry_oversat',
	'cry_astral',
	'cry_blur'
}

local card_draw_ref = Card.draw
function Card:draw(layer)
	local CEN = self.gc and self:gc()
	if CEN then
		self.was_in_pack_area = G.pack_cards and self.area and self.area == G.pack_cards
		if (self.facing or '') == 'front' then
			if self.config then
				local should_scare = not CEN.cant_scare and ((Jen.gods() and CEN.fusable) or Jen.sinister)
				local should_scare2 = not CEN.cant_scare and ((Jen.gods() and CEN.fusable) or Jen.dramatic)
				if CEN.key == 'j_jen_dandy' and math.random(800) == 1 then
					self.dandy_glitch = math.random(10, 80)
					if self.children then
						if self.children.center then
							self.children.center:set_sprite_pos({ x = 0, y = 1 })
						end
						if self.children.floating_sprite then
							self.children.floating_sprite:set_sprite_pos({ x = 1, y = 1 })
						end
					end
				elseif self.dandy_glitch then
					if self.dandy_glitch <= 1 then
						if self.children then
							if self.children.center then
								self.children.center:set_sprite_pos({ x = 0, y = 0 })
							end
							if self.children.floating_sprite then
								self.children.floating_sprite:set_sprite_pos({ x = 1, y = 0 })
							end
						end
						self.dandy_glitch = nil
					else
						self.dandy_glitch = self.dandy_glitch - 1
					end
				end
				if not CEN.update and self.children.floating_sprite then
					if ((CEN.drama and should_scare2) or (CEN.sinis and should_scare)) and (CEN.sinis or CEN.drama) and not self.in_drama_state then
						self.in_drama_state = true
						self.children.floating_sprite:set_sprite_pos(CEN.drama or CEN.sinis)
					elseif not ((CEN.drama and should_scare2) or (CEN.sinis and should_scare)) and self.in_drama_state then
						self.in_drama_state = nil
						self.children.floating_sprite:set_sprite_pos(CEN.soul_pos)
					end
				end
				if self.in_drama_state then
					self:juice_up(0, math.random() / (Jen.dramatic and 3 or 6))
				end
				if self.area and next(self.area) then
					if self.ability then
						if CEN.permaeternal and G.jokers and self.area == G.jokers then
							self.ability.eternal = true
						end
						if CEN.debuff_immune or Jen.dandy_active then
							self.ability.perishable = false
							self.ability.perish_tally = 1e9
						end
					end
					if CEN.key == 'c_cry_pointer' and G.hand and self.area == G.hand and not self.lolnocryptidingpointerforyou then
						self.lolnocryptidingpointerforyou = true
						self:destroy()
						local pointer = create_card('Code', G.consumeables, nil, nil, nil, nil, 'c_cry_pointer',
							'fuck_cryptiding_pointer_because_there_is_no_need_for_a_budget_creative_mode_please_come_the_fuck_on')
						pointer.no_omega = true
						pointer:add_to_deck()
						G.consumeables:emplace(pointer)
					end
				end
				if CEN.gloss then
					if CEN.gloss_contrast then
						for i = 1, CEN.gloss_contrast do
							self.children.center:draw_shader(type(CEN.gloss) == 'string' and CEN.gloss or 'voucher', nil,
								self.ARGS.send_to_shader)
						end
					else
						self.children.center:draw_shader(type(CEN.gloss) == 'string' and CEN.gloss or 'voucher', nil,
							self.ARGS.send_to_shader)
					end
				end
				if (self.added_to_deck or (self.area and self.area == G.hand)) and not self.edition then
					if not CEN.ignore_kudaai and Jen.kudaai_active and (CEN.set ~= 'Booster' or self.area == G.consumeables) and not CEN.cannot_edition then
						self:set_edition(
							{ [random_editions[pseudorandom('kudaai_edition', 1, #random_editions)]] = true },
							true)
					end
				end
				if Jen.luke_active and self.ability and CEN.key ~= 'j_jen_hunter' and CEN.key ~= 'j_jen_luke' and CEN.set ~= 'jen_ability' then
					self.ability.cry_rigged = true
				end
			end
		else
			if CEN.key == 'c_cry_pointer' and G.hand and self.area == G.hand and not self.lolnocryptidingpointerforyou then
				self.lolnocryptidingpointerforyou = true
				self:destroy()
				local pointer = create_card('Code', G.consumeables, nil, nil, nil, nil, 'c_cry_pointer',
					'fuck_cryptiding_pointer_because_there_is_no_need_for_a_budget_creative_mode_please_come_the_fuck_on')
				pointer.no_omega = true
				pointer:add_to_deck()
				G.consumeables:emplace(pointer)
			end
		end
	end
	CEN = nil
	card_draw_ref(self, layer)
end

function Jen.add_fusion(key, cost, output, ...)
	local inputs = { ... }
	Jen.fusions[key] = { cost = cost, output = output, ingredients = inputs }
end

function Jen.find_matching_recipe(items)
	if #items <= 0 then return nil end
	for k, v in pairs(Jen.fusions) do
		local matches = 0
		for _, w in ipairs(v.ingredients) do
			for __, x in ipairs(items) do
				if x:gc().key == w then
					matches = matches + 1
					break
				end
			end
		end
		if matches >= #v.ingredients then
			return k
		end
	end
	return nil
end

function Jen.has_ingredients(key)
	if not Jen.fusions[key] then return false end
	local inputs = Jen.fusions[key].ingredients
	if #inputs <= 0 then
		Jen.fusions[key] = nil; return false
	end
	local acquired = 0
	for k, v in ipairs(inputs) do
		if #SMODS.find_card(v, true) > 0 then
			acquired = acquired + 1
		end
	end
	return acquired >= #inputs
end

function Jen.get_cards_for_recipe(key)
	if not Jen.fusions[key] then return false end
	local inputs = Jen.fusions[key].ingredients
	if #inputs <= 0 then
		Jen.fusions[key] = nil; return false
	end
	local acquired = 0
	local ingreds = {}
	for k, v in ipairs(inputs) do
		if #SMODS.find_card(v, true) > 0 then
			acquired = acquired + 1
			table.insert(ingreds, next(SMODS.find_card(v, true)))
		end
	end
	if acquired >= #inputs then return ingreds else return false end
end

function Jen.is_fusable(center)
	for k, v in pairs(Jen.fusions) do
		for __, w in pairs(v.ingredients) do
			if (type(center) == 'table' and w == center.key) or (type(center) == 'string' and w == center) then
				return k
			end
		end
	end
	return false
end

function fuse_cards(cards, output, fast)
	if fast then
		Q(function()
			play_sound('whoosh')
			for k, v in ipairs(cards) do
				G['jen_merge' .. k] = CardArea(G.play.T.x, G.play.T.y, G.play.T.w, G.play.T.h,
					{ type = 'play', card_limit = 5 })
				if v.area then
					v.area:remove_card(v)
				end
				G['jen_merge' .. k]:emplace(v)
			end
			return true
		end)
		delay(1.5)
		Q(function()
			play_sound('explosion_release1')
			for k, v in ipairs(cards) do
				v:flip()
				if G['jen_merge' .. k] then
					G['jen_merge' .. k]:remove_card(v)
					G['jen_merge' .. k]:remove()
					G['jen_merge' .. k] = nil
				end
				v:destroy(nil, true, nil, true)
			end
			return true
		end)
		Q(function()
			if output then
				if type(output) == 'function' then
					output()
				elseif type(output) == 'string' then
					local new_card = create_card(G.P_CENTERS[output].set,
						G.P_CENTERS[output].set == 'Joker' and G.jokers or G.consumeables, nil, nil, nil, nil, output,
						'fusion')
					G.play:emplace(new_card)
					delay(1.5)
					Q(function()
						G.play:remove_card(new_card)
						new_card:add_to_deck()
						if new_card.ability.set == 'Joker' then
							G.jokers:emplace(new_card)
						else
							G.consumeables:emplace(new_card)
						end
						return true
					end)
				end
			end
			return true
		end)
	else
		Q(function()
			play_sound('whoosh')
			for k, v in ipairs(cards) do
				G['jen_merge' .. k] = CardArea(G.play.T.x, G.play.T.y, G.play.T.w, G.play.T.h,
					{ type = 'play', card_limit = 5 })
				if v.area then
					v.area:remove_card(v)
				end
				G['jen_merge' .. k]:emplace(v)
			end
			return true
		end)
		delay(1.5)
		Q(function()
			for k, v in ipairs(cards) do
				v:flip()
				if k ~= 1 then
					if G['jen_merge' .. k] then
						G['jen_merge' .. k]:remove_card(v)
						G['jen_merge' .. k]:remove()
						G['jen_merge' .. k] = nil
					end
					v:destroy(nil, true, nil, true)
				end
			end
			return true
		end)
		delay(0.5)
		local card
		Q(function()
			card = G.jen_merge1.cards[1]
			card:explode()
			Q(function()
				if card then card:remove() end
				if G.jen_merge1 then
					G.jen_merge1:remove(); G.jen_merge1 = nil;
				end
				return true
			end)
			Q(function()
				if output then
					if type(output) == 'function' then
						output()
					elseif type(output) == 'string' then
						local new_card = create_card(G.P_CENTERS[output].set,
							G.P_CENTERS[output].set == 'Joker' and G.jokers or G.consumeables, nil, nil, nil, nil, output,
							'fusion')
						G.play:emplace(new_card)
						delay(1.5)
						Q(function()
							G.play:remove_card(new_card)
							new_card:add_to_deck()
							if new_card.ability.set == 'Joker' then
								G.jokers:emplace(new_card)
							else
								G.consumeables:emplace(new_card)
							end
							return true
						end)
					end
				end
				return true
			end)
			return true
		end)
	end
end

Jen.blind_scalar = {}
for i = 1, Jen.config.ante_polytate do
	Jen.blind_scalar[i] = to_big(1 + (Jen.config.scalar_base + (i / Jen.config.scalar_additivedivisor))) ^
		to_big(i * Jen.config.scalar_exponent)
end

if not IncantationAddons then
	IncantationAddons = {
		Stacking = {},
		Dividing = {},
		BulkUse = {},
		StackingIndividual = {},
		DividingIndividual = {},
		BulkUseIndividual = {}
	}
end

if not AurinkoAddons then
	AurinkoAddons = {}
end

local gsp = get_starting_params
function get_starting_params()
	newTable = gsp()
	newTable.consumable_slots = newTable.consumable_slots + Jen.config.consumable_slot_count_buff
	return newTable
end

function gameover()
	remove_save()

	if G.GAME.round_resets.ante <= G.GAME.win_ante then
		if not G.GAME.seeded and not G.GAME.challenge then
			inc_career_stat('c_losses', 1)
			set_deck_loss()
			set_joker_loss()
		end
	end

	play_sound('negative', 0.5, 0.7)
	play_sound('whoosh2', 0.9, 0.7)

	G.SETTINGS.paused = true
	G.FUNCS.overlay_menu {
		definition = create_UIBox_game_over(),
		config = { no_esc = true }
	}
	G.ROOM.jiggle = G.ROOM.jiggle + 3

	if G.GAME.round_resets.ante <= G.GAME.win_ante then
		local Jimbo = nil
		Q(function()
			if G.OVERLAY_MENU and G.OVERLAY_MENU:get_UIE_by_ID('jimbo_spot') then
				Jimbo = Card_Character({ x = 0, y = 5 })
				local spot = G.OVERLAY_MENU:get_UIE_by_ID('jimbo_spot')
				spot.config.object:remove()
				spot.config.object = Jimbo
				Jimbo.ui_object_updated = true
				Jimbo:add_speech_bubble('lq_' .. math.random(1, 10), nil, { quip = true })
				Jimbo:say_stuff(5)
			end
			return true
		end, 2.5, nil, 'after', false, false)
	end
	G.STATE_COMPLETE = true
end

if not AllowStacking then AllowStacking = function() end end
if not AllowDividing then AllowDividing = function() end end
if not AllowMassUsing then AllowMassUsing = function() end end
if not AllowBulkUse then AllowBulkUse = function() end end

AllowStacking('jen_ability')
AllowStacking('jen_omegaconsumable')
AllowStacking('jen_tokens')
AllowDividing('jen_uno')
AllowDividing('jen_ability')
AllowDividing('jen_omegaconsumable')
AllowDividing('jen_tokens')
AllowMassUsing('jen_uno')
AllowBulkUse('jen_tokens')

AurinkoAddons.jen_wee = function(card, hand, instant, amount)
	if card and not card.playing_card then
		local twos = {}
		local editioned_twos = {}
		for k, v in pairs(G.playing_cards) do
			if v:get_id() == 2 then
				table.insert(v.edition and editioned_twos or twos, v)
			end
		end
		if #twos > 0 or #editioned_twos > 0 then
			if not card.already_announced_message then
				card.already_announced_message = true
				Q(function()
					play_sound('gong', 0.94, 0.3)
					play_sound('gong', 0.94 * 1.5, 0.2)
					play_sound('tarot1', 1.5)
					return true
				end)
				jl.a(#twos + #editioned_twos .. 'x Twos', G.SETTINGS.GAMESPEED, 1.4, G.C.GREEN)
				jl.rd(1)
				QR(function()
					if card then card.already_announced_message = nil end
					return true
				end, 3)
			end
			if #twos > 0 then
				level_up_hand(nil, hand, true, #twos * amount, true, true, true)
			end
			for k, two in pairs(editioned_twos) do
				level_up_hand(two, hand, true, amount, true, true, true)
			end
			Q(function()
				twos = nil; editioned_twos = nil; return true
			end)
		end
	end
end

AurinkoAddons.jen_jumbo = function(card, hand, instant, amount)
	if card and not card.playing_card then
		local akqjs = {}
		local editioned_akqjs = {}
		for k, v in pairs(G.playing_cards) do
			if v:get_id() > 10 then
				table.insert(v.edition and editioned_akqjs or akqjs, v)
			end
		end
		if #akqjs > 0 or #editioned_akqjs > 0 then
			if not card.already_announced_message then
				card.already_announced_message = true
				Q(function()
					play_sound('gong', 0.94, 0.3)
					play_sound('gong', 0.94 * 1.5, 0.2)
					play_sound('tarot1', 1.5)
					return true
				end)
				jl.a(#akqjs + #editioned_akqjs .. 'x AKQJs', G.SETTINGS.GAMESPEED, 1.4, G.C.GREEN)
				jl.rd(1)
				QR(function()
					if card then card.already_announced_message = nil end
					return true
				end, 3)
			end
			if #akqjs > 0 then
				level_up_hand(nil, hand, true, #akqjs * amount, true, true, true)
			end
			for k, akqj in pairs(editioned_akqjs) do
				level_up_hand(akqj, hand, true, amount, true, true, true)
			end
			Q(function()
				akqjs = nil; editioned_akqjs = nil; return true
			end)
		end
	end
end

G.FUNCS.isomeganumenabled = function(e)
	if Big and Big.arrow then
		return true
	end
	return false
end

local function play_sound_q(sound, per, vol)
	G.E_MANAGER:add_event(Event({
		func = function()
			play_sound(sound, per, vol)
			return true
		end
	}))
end


local final_operations = {
	[-2] = { '/', 'IMPORTANT' },
	[-1] = { '-', 'GREY' },
	[0] = { '+', 'UI_CHIPS' },
	[1] = { 'X', 'UI_MULT' },
	[2] = { '^', { 0.8, 0.45, 0.85, 1 } },
	[3] = { '^^', 'DARK_EDITION' },
	[4] = { '^^^', 'CRY_EXOTIC' },
	[5] = { '^^^^', 'CRY_EMBER' },
	[6] = { '^^^^^', 'CRY_ASCENDANT' },
}

local sumcache_limit = 100

local chipmult_sum_cache = {}

function get_chipmult_sum(chips, mult)
	chips = chips or 0
	mult = mult or 0
	if #chipmult_sum_cache > sumcache_limit then
		for i = 1, sumcache_limit do
			table.remove(chipmult_sum_cache)
		end
	end
	local op = get_final_operator()
	if to_big(chips) == to_big(0) or to_big(mult) == to_big(0) then
		chips = 0
		mult = 0
		op = 0
	end
	local sum
	for k, v in ipairs(chipmult_sum_cache) do
		if v.oper == op and v.c == to_big(chips) and v.m == to_big(mult) then
			return v.result
		end
	end
	if op > 2 then
		sum = to_big(chips):arrow(math.min(maxArrow, op - 1), to_big(mult))
	elseif op == 2 then
		sum = to_big(chips) ^ to_big(mult)
	elseif op == 1 then
		sum = to_big(chips) * to_big(mult)
	elseif op == -1 then
		sum = to_big(chips) - to_big(mult)
	elseif op <= -2 then
		sum = to_big(chips) / to_big(mult)
	else
		sum = to_big(chips) + to_big(mult)
	end
	table.insert(chipmult_sum_cache, { oper = op, c = chips, m = mult, result = sum })
	return sum
end

function update_operator_display()
	local op = get_final_operator()
	local txt = ''
	local col = G.C.WHITE
	if not final_operations[op] then
		txt = '{' .. number_format(op - 1) .. '}'
		col = G.C.jen_RGB
	else
		txt = final_operations[op][1]
		col = type(final_operations[op][2]) == 'table' and final_operations[op][2] or G.C[final_operations[op][2]]
	end
	Q(function()
		play_sound('button', 1.1, 0.65)
		G.hand_text_area.op.config.text = txt
		G.hand_text_area.op.config.text_drawable:set(txt)
		G.hand_text_area.op.UIBox:recalculate()
		G.hand_text_area.op.config.colour = col
		G.hand_text_area.op:juice_up(0.8, 0.5)
		return true
	end)
end

function update_operator_display_custom(txt, col)
	Q(function()
		play_sound('button', 1.1, 0.65)
		G.hand_text_area.op.config.text = txt
		G.hand_text_area.op.config.text_drawable:set(txt)
		G.hand_text_area.op.UIBox:recalculate()
		G.hand_text_area.op.config.colour = (col or G.C.UI_MULT)
		G.hand_text_area.op:juice_up(0.8, 0.5)
		return true
	end)
end

function get_final_operator_offset()
	if not G.GAME then return 0 end
	if not G.GAME.finaloperator then G.GAME.finaloperator = 1 end
	if not G.GAME.finaloperator_offset then G.GAME.finaloperator_offset = 0 end
	return math.max(-1, G.GAME.finaloperator_offset)
end

function get_final_operator(absolute)
	if not G.GAME then return 0 end
	if not G.GAME.finaloperator then G.GAME.finaloperator = 1 end
	if not G.GAME.finaloperator_offset then G.GAME.finaloperator_offset = 0 end
	return math.max(0, math.min(maxArrow + 1, G.GAME.finaloperator + (absolute and 0 or get_final_operator_offset())))
end

function set_final_operator(value)
	G.GAME.finaloperator = math.min(math.max(value, 0), 101)
	local op = get_final_operator()
	if op == 0 then
		SMODS.set_scoring_calculation('add')
	elseif op == 1 then
		SMODS.set_scoring_calculation('multiply')
	elseif op == 2 then
		-- Level 2 is ^, use built-in exponent
		SMODS.set_scoring_calculation('exponent')
	elseif op >= 3 then
		-- Ensure arrow calculations are registered
		register_arrow_scoring_calculations()
		-- Level 3+ uses arrow_2, arrow_3, etc.
		local arrow_lvl = op - 1
		if arrow_lvl > 100 then arrow_lvl = 100 end
		SMODS.set_scoring_calculation('arrow_' .. arrow_lvl)
	end
	update_operator_display()
end

function set_final_operator_offset(value)
	G.GAME.finaloperator_offset = math.min(math.max(value, -1), 101)
	local op = get_final_operator()
	if op == 0 then
		SMODS.set_scoring_calculation('add')
	elseif op == 1 then
		SMODS.set_scoring_calculation('multiply')
	elseif op == 2 then
		-- Level 2 is ^, use built-in exponent
		SMODS.set_scoring_calculation('exponent')
	elseif op >= 3 then
		-- Ensure arrow calculations are registered
		register_arrow_scoring_calculations()
		-- Level 3+ uses arrow_2, arrow_3, etc.
		local arrow_lvl = op - 1
		if arrow_lvl > 100 then arrow_lvl = 100 end
		SMODS.set_scoring_calculation('arrow_' .. arrow_lvl)
	end
	update_operator_display()
end

function change_final_operator(mod)
	set_final_operator(get_final_operator(true) + mod)
end

function offset_final_operator(mod)
	set_final_operator_offset(get_final_operator_offset() + mod)
end

function get_kosmos()
	return jl.fc('j_jen_kosmos')
end

function get_malice()
	if not G.GAME then return to_big(0) end
	if not G.GAME.malice then G.GAME.malice = to_big(0) end
	if jl.invalid_number(number_format(G.GAME.malice)) then G.GAME.malice = to_big(maxfloat) end
	return (get_final_operator() >= (maxArrow + 1)) and to_big(0) or to_big(G.GAME.malice)
end

function get_max_malice(offset)
	offset = offset or 0
	local mod = math.max(0, (get_final_operator(true) - 1) + offset)
	if get_final_operator(true) + offset > maxArrow then return to_big(0) end

	-- Safety check to prevent Event Manager overflow from extremely large calculations
	-- This doesn't limit the final malice value, just prevents overwhelming the event system
	if mod > 100 then
		mod = 100 -- Cap the mod to prevent Event Manager crashes
	end
	-- Cache table for previously computed max malice tiers to avoid recomputation & big-int churn
	G.GAME._malice_cache = G.GAME._malice_cache or {}
	local key = mod .. '|' .. Jen.config.malice_base .. '|' .. Jen.config.malice_increase
	local cached = G.GAME._malice_cache[key]
	if cached then return cached end
	local base = to_big(Jen.config.malice_base) * to_big(math.max(1, mod + 1))
	local m = to_big(mod)
	local exp_cap = Jen.config.malice_exponent_cap
	local pow_component
	if exp_cap and Jen.config.malice_cap_approximate and mod > exp_cap then
		-- Approximate beyond cap to avoid runaway memory usage
		local capped_power = (to_big(Jen.config.malice_increase) ^ (m ^ to_big(exp_cap)))
		pow_component = capped_power * to_big(math.max(1, math.floor((mod * (mod + 1)) / (2 * exp_cap))))
	else
		pow_component = (to_big(Jen.config.malice_increase) ^ (m ^ (m + 1)))
	end
	local result = base * pow_component
	-- Store only a limited number of cache entries to bound memory
	G.GAME._malice_cache._order = G.GAME._malice_cache._order or {}
	table.insert(G.GAME._malice_cache._order, key)
	G.GAME._malice_cache[key] = result
	if #G.GAME._malice_cache._order > 128 then
		local old_key = table.remove(G.GAME._malice_cache._order, 1)
		G.GAME._malice_cache[old_key] = nil
	end
	return result
end

function check_malice(check)
	if get_final_operator(true) >= (maxArrow + 1) then return end
	if get_malice() ~= (check or to_big(0)) then return end
	local kosmos = get_kosmos()
	if check >= get_max_malice() then
		local maxmalice = get_max_malice()
		local increments = 0
		local safety_threshold = Jen.config.kosmos_safety_threshold or 50
		local gc_trigger = Jen.config.kosmos_gc_trigger_kb or 256000
		local max_iterations = 100 -- Additional safety to prevent Event Manager overflow
		while (not Jen.config.safer_kosmos or increments < safety_threshold) and increments < max_iterations do
			if collectgarbage("count") > gc_trigger then collectgarbage("collect") end
			if G.GAME.malice >= maxmalice and maxmalice > to_big(0) then
				G.GAME.malice = G.GAME.malice - maxmalice
				increments = increments + 1
				maxmalice = get_max_malice(increments)
			else
				break
			end
		end
		if maxmalice <= to_big(0) then G.GAME.malice = to_big(0) end
		play_sound_q('jen_enchant', 0.75, 1)
		jl.a('Operator Increased' .. (increments > 1 and (' x ' .. tostring(increments)) or ''), G.SETTINGS.GAMESPEED * 2,
			1, G.C.SECONDARY_SET.Tarot)
		jl.rd(2)
		G.jokers:change_size_absolute(increments)
		change_final_operator(increments)
		if Jen.config.safer_kosmos then
			maxmalice = get_max_malice()
			local next_check = get_malice()
			if G.GAME.malice >= maxmalice and maxmalice > to_big(0) then
				Q(function()
					check_malice(next_check)
					return true
				end, 0.1, nil, 'after')
			end
		end
	end
end

function add_malice(mod, now, unscaled)
	if jl.invalid_number(number_format(mod)) then return end
	if now or not Jen.config.safer_kosmos then
		if get_final_operator(true) >= (maxArrow + 1) then return end
		local kosmos = get_kosmos()
		if not kosmos then return end
		if not G.GAME.malice then G.GAME.malice = to_big(0) end
		local orig_malice = G.GAME.malice * to_big(1)
		local orig_maxmalice = get_max_malice()
		mod = to_big(mod)
		if not unscaled then
			mod = (math.abs(mod) * (to_big(Jen.config.malice_increase) ^ to_big(G.GAME.round_resets.ante)))
		end
		G.GAME.malice = G.GAME.malice + mod
		if jl.invalid_number(number_format(G.GAME.malice)) then G.GAME.malice = to_big(maxfloat) end
		if not kosmos.cumulative_malice then
			kosmos.cumulative_malice = (kosmos.cumulative_malice or to_big(0)) + mod
			Q(function()
				if kosmos then
					card_status_text(kosmos, '+' .. number_format(kosmos.cumulative_malice or to_big(0)), nil,
						0.05 * kosmos.T.h, G.C.RED, 0.6, 0.6, 0.4, 0.4, 'bm', 'jen_enchant', 0.5, 1)
					jl.a(
						'Malice : ' ..
						number_format(orig_malice + (kosmos.cumulative_malice or to_big(0))) ..
						' / ' .. number_format(orig_maxmalice), 3, 0.75, G.C.RED)
					kosmos.cumulative_malice = nil
					check_malice(G.GAME.malice)
				end
				return true
			end, 0.1, nil, 'after')
		else
			kosmos.cumulative_malice = (kosmos.cumulative_malice or to_big(0)) + mod
		end
	else
		Q(function()
			add_malice(mod, true, unscaled)
			return true
		end)
	end
end

function get_amalgam_value(rarity)
	rarity = tostring(rarity) or ''
	local malice = to_big(0)
	if rarity == '3' and get_final_operator(true) < 25 then
		malice = get_max_malice() * .1
	elseif rarity == 'cry_epic' and get_final_operator(true) < 100 then
		malice = get_max_malice() * (get_final_operator(true) < 50 and 1 or .25)
	elseif rarity == '4' and get_final_operator(true) < 1000 then
		malice = get_max_malice(get_final_operator(true) < 300 and 2 or get_final_operator(true) < 400 and 1 or 0) *
			(get_final_operator(true) < 500 and 1 or .25)
	elseif rarity == 'cry_exotic' and get_final_operator(true) < 3000 then
		malice = get_max_malice(get_final_operator(true) < 1500 and 4 or get_final_operator(true) < 1800 and 3 or
			get_final_operator(true) < 2100 and 2 or get_final_operator(true) < 2400 and 1 or 0)
	elseif rarity == 'jen_ritualistic' and get_final_operator(true) < 8000 then
		malice = get_max_malice(get_final_operator(true) < 5000 and 9 or get_final_operator(true) < 5500 and 4 or
			get_final_operator(true) < 6000 and 3 or get_final_operator(true) < 6500 and 2 or
			get_final_operator(true) < 7000 and 1 or 0)
	elseif rarity == 'jen_wondrous' and get_final_operator(true) < 20000 then
		malice = get_max_malice(get_final_operator(true) < 10000 and 24 or get_final_operator(true) < 12000 and 14 or
			get_final_operator(true) < 14000 and 9 or get_final_operator(true) < 16000 and 4 or
			get_final_operator(true) < 18000 and 2 or 0)
	elseif rarity == 'jen_extraordinary' then
		malice = get_max_malice(get_final_operator(true) < 21000 and 49 or get_final_operator(true) < 21500 and 29 or
			get_final_operator(true) < 22000 and 14 or get_final_operator(true) < 22500 and 7 or 0)
	elseif rarity == 'jen_transcendent' then
		malice = get_max_malice(get_final_operator(true) < 22500 and 99 or get_final_operator(true) < 23000 and 49 or
			get_final_operator(true) < 23500 and 24 or get_final_operator(true) < 24000 and 11 or 4)
	end
	return malice
end

function set_dollars(mod)
	mod = to_big(mod or 0)
	Q(function()
		local dollar_UI = G.HUD:get_UIE_by_ID('dollar_text_UI')
		local text = '=' .. localize('$')
		local col = G.C.FILTER
		G.GAME.dollars = mod
		dollar_UI.config.object:update()
		G.HUD:recalculate()
		attention_text({
			text = text .. number_format(mod),
			scale = 0.8,
			hold = 0.7,
			cover = dollar_UI.parent,
			cover_colour = col,
			align = 'cm',
		})
		play_sound('coin1')
		return true
	end)
end

local edr = ease_dollars
function ease_dollars(mod, instant, force_update)
	if to_big((G.GAME.dollars + mod ~= G.GAME.dollars and math.abs(mod))) > to_big((G.GAME.dollars / 1e6)) or force_update then
		edr(mod, instant)
		local should_clamp = jl.invalid_number(number_format(G.GAME.dollars)) or to_big(G.GAME.dollars) > to_big(1e100) or
			to_big(G.GAME.dollars) < to_big(-1e100)
		if should_clamp then
			G.GAME.dollars = jl.invalid_number(number_format(G.GAME.dollars)) and to_big(1e100) or
				to_big(math.min(math.max(G.GAME.dollars, -1e100), 1e100))
			ease_dollars(0, true, true)
		end
	end
end

function ease_tension(mod)
	Q(function()
		local tension_UI = G.HUD:get_UIE_by_ID('tension_UI_count')
		mod = mod or 0
		local text = '+'
		local col = G.C.CRY_TWILIGHT
		if mod < 0 then
			text = ''
			col = G.C.CRY_VERDANT
		end
		G.GAME.tension = G.GAME.tension + mod
		tension_UI.config.object:update()
		G.HUD:recalculate()
		attention_text({
			text = text .. mod,
			scale = 0.8,
			hold = 0.7,
			cover = tension_UI.parent,
			cover_colour = col,
			align = 'cm',
		})
		play_sound('jen_tension', mod < 0 and .6 or 1)
		play_sound('generic1')
		return true
	end)
	delay(.2)
end

function ease_relief(mod)
	Q(function()
		local relief_UI = G.HUD:get_UIE_by_ID('relief_UI_count')
		mod = mod or 0
		local text = '+'
		local col = G.C.CRY_EXOTIC
		if mod < 0 then
			text = ''
			col = G.C.CRY_EMBER
		end
		G.GAME.relief = G.GAME.relief + mod
		relief_UI.config.object:update()
		G.HUD:recalculate()
		attention_text({
			text = text .. mod,
			scale = 0.8,
			hold = 0.7,
			cover = relief_UI.parent,
			cover_colour = col,
			align = 'cm',
		})
		play_sound('jen_relief', mod < 0 and .6 or 1)
		play_sound('generic1')
		return true
	end)
	delay(.2)
end

function ease_straddle_display(mod)
	local should_update_to_straddle = false
	if not mod then
		if not tonumber(G.GAME.straddle_disp) then G.GAME.straddle_disp = 0 end
		mod = G.GAME.straddle - G.GAME.straddle_disp
		should_update_to_straddle = true
	end
	Q(function()
		local straddle_UI = G.HUD:get_UIE_by_ID('straddle_UI_count')
		mod = mod or 0
		local text = '+'
		local col = G.C.CRY_BLOSSOM
		if mod < 0 then
			text = ''
			col = G.C.CRY_AZURE
		end
		G.GAME.straddle_disp = should_update_to_straddle and G.GAME.straddle or
			((tonumber(G.GAME.straddle_disp) or 0) + mod)
		straddle_UI.config.object:update()
		G.HUD:recalculate()
		attention_text({
			text = text .. mod,
			scale = 0.8,
			hold = 0.7,
			cover = straddle_UI.parent,
			cover_colour = col,
			align = 'cm',
		})
		play_sound('highlight2', 0.5, 0.2)
		play_sound('generic1')
		return true
	end)
	delay(.2)
end

function progress_straddle(add)
	if not G.GAME.straddle_active or not Jen.config.straddle.enabled then return end
	local length_multiplier = 1
	if #SMODS.find_card('j_jen_pickel') > 0 then
		length_multiplier = length_multiplier * 2
	end
	if G.GAME.tortoise then
		length_multiplier = length_multiplier * 2
	end
	local MIN = Jen.config.straddle.progress_min * length_multiplier
	local MAX = Jen.config.straddle.progress_max * length_multiplier
	local spd = math.min(4, 1 + (G.GAME.straddle / 100))
	local spd_additive = .1 * spd
	local orig_straddle = G.GAME.straddle
	local to_next = math.min(MAX, MIN + math.floor(G.GAME.straddle / Jen.config.straddle.progress_increment))
	local progressbar = {}
	if not Jen.config.straddle.skip_animation then
		for i = 1, MAX do
			progressbar[i] = jl.rawcard(i > to_next and 'm_stone' or G.GAME.straddle >= 100 and 'm_gold' or 'c_base',
				1 / ((1 + (MAX / 10)) ^ .5), (2 / MAX) * i)
			progressbar[i].states.drag.can = false
			progressbar[i].no_ui = true
			if i <= G.GAME.straddle_progress then
				progressbar[i]:set_edition({ negative = true }, true, true)
			end
		end
		if (progressbar or {})[1] then progressbar[1]:add_dynatext('Straddle ' .. number_format(G.GAME.straddle)) end
		if (progressbar or {})[to_next] then
			progressbar[to_next]:add_dynatext(nil,
				'Straddle ' .. number_format(G.GAME.straddle + 1))
		end
		jl.rd(0.5)
	end
	while add > 0 and (spd < 8 or to_next < MAX) and not Jen.config.straddle.skip_animation do
		add = add - 1
		G.GAME.straddle_progress = G.GAME.straddle_progress + 1
		local target = progressbar[math.min(G.GAME.straddle_progress, MAX)]
		local silent_increase = spd > 4
		local should_gold = G.GAME.straddle >= 100
		local pitch_mod = .9 + (G.GAME.straddle_progress / 10)
		Q(function()
			if target then
				target:set_edition({ negative = true }, true, true)
				target:juice_up(0.8, 0.5)
			end
			if not silent_increase then
				play_sound('generic1', pitch_mod)
				play_sound('jen_straddle_tick', pitch_mod)
			end
			return true
		end)
		if G.GAME.straddle_progress >= to_next then
			G.GAME.straddle_progress = 0
			G.GAME.straddle = G.GAME.straddle + 1
			orig_straddle = orig_straddle + 1
			if target then target:remove_dynatext() end
			if (progressbar or {})[1] then progressbar[1]:remove_dynatext() end
			local new_next = math.min(MAX, MIN + math.floor(G.GAME.straddle / Jen.config.straddle.progress_increment))
			to_next = new_next
			if spd < 4 then jl.rd(1 / spd) end
			jl.a('Straddle ' .. number_format(G.GAME.straddle), G.SETTINGS.GAMESPEED * 2, 1,
				mix_colours(G.C.RED, G.C.UI.TEXT_LIGHT,
					math.min(1 + (Jen.config.straddle.progress_increment / 10),
						G.GAME.straddle / Jen.config.straddle.progress_increment) -
					(Jen.config.straddle.progress_increment / 10)))
			Q(function()
				for i = 1, MAX do
					if (progressbar or {})[i] then
						progressbar[i]:juice_up(1, 1)
						progressbar[i]:set_edition({ jen_prismatic = true }, true, true)
					end
				end
				play_sound('jen_straddle_increase')
				play_sound('generic1')
				return true
			end)
			if spd < 4 then jl.rd(1 / spd) end
			for i = 1, MAX do
				Q(function()
					if (progressbar or {})[i] then progressbar[i]:fake_dissolve() end
					return true
				end, spd < 4 and 0.1 or 0)
			end
			if spd < 4 then jl.rd(1 / spd) end
			Q(function()
				for i = 1, MAX do
					if (progressbar or {})[i] then
						progressbar[i]:start_materialize()
						progressbar[i]:set_ability(G.P_CENTERS
							[i > new_next and 'm_stone' or should_gold and 'm_gold' or 'c_base'])
						progressbar[i]:set_edition(nil, true, true)
					end
				end
				return true
			end, spd < 4 and 0.1 or 0)
			for i = 1, MAX do
				if i == 1 or i == to_next then
					if (progressbar or {})[i] then
						progressbar[i]:add_dynatext(i == 1 and ('Straddle ' .. number_format(G.GAME.straddle)),
							i == to_next and ('Straddle ' .. number_format(G.GAME.straddle + 1)))
					end
				end
			end
			ease_straddle_display(1)
			spd = spd + spd_additive
			spd_additive = math.min(spd_additive * 1.5, 4)
		end
		if spd < 4 then jl.rd(.25 / spd) end
	end
	if spd >= 8 or Jen.config.straddle.skip_animation then
		G.GAME.straddle_progress = G.GAME.straddle_progress + add
		local mass_add = math.floor(G.GAME.straddle_progress / to_next)
		G.GAME.straddle_progress = G.GAME.straddle_progress - (to_next * mass_add)
		G.GAME.straddle = G.GAME.straddle + mass_add
		local nxt = math.min(MAX, MIN + math.floor(G.GAME.straddle / Jen.config.straddle.progress_increment))
		if not Jen.config.straddle.skip_animation then
			Q(function()
				for i = 1, MAX do
					if (progressbar or {})[i] then
						progressbar[i]:remove_dynatext()
						if i == 1 or i == to_next then
							progressbar[i]:add_dynatext(i == 1 and ('Straddle ' .. number_format(G.GAME.straddle)),
								i == to_next and ('Straddle ' .. number_format(G.GAME.straddle + 1)))
						end
						progressbar[i]:set_ability(G.P_CENTERS
							[i > nxt and 'm_stone' or G.GAME.straddle >= 100 and 'm_gold' or 'c_base'])
						if i <= G.GAME.straddle_progress then
							progressbar[i]:set_edition({ negative = true }, true, true)
						else
							progressbar[i]:set_edition(nil, true, true)
						end
					end
				end
				return true
			end)
			if orig_straddle ~= G.GAME.straddle then
				jl.a('Straddle ' .. number_format(G.GAME.straddle),
					G.SETTINGS.GAMESPEED * 2, 1,
					mix_colours(G.C.RED, G.C.UI.TEXT_LIGHT,
						math.min(1 + (Jen.config.straddle.progress_increment / 10),
							G.GAME.straddle / Jen.config.straddle.progress_increment) -
						(Jen.config.straddle.progress_increment / 10)))
			end
			Q(function()
				play_sound('jen_straddle_increase')
				play_sound('generic1')
				return true
			end)
			ease_straddle_display()
		else
			G.GAME.straddle_disp = G.GAME.straddle
			local straddle_UI = G.HUD:get_UIE_by_ID('straddle_UI_count')
			if straddle_UI and straddle_UI.config and straddle_UI.config.object then
				straddle_UI.config.object:update()
			end
			if G.HUD then G.HUD:recalculate() end
		end
	end
	if not Jen.config.straddle.skip_animation then jl.rd(1) end
	if (progressbar or {})[1] then progressbar[1]:remove_dynatext() end
	if (progressbar or {})[to_next] then progressbar[to_next]:remove_dynatext() end
	Q(function()
		for i = 1, #progressbar do if (progressbar or {})[i] then progressbar[i]:destroy() end end
		return true
	end)
end

local crcr = calculate_reroll_cost
function calculate_reroll_cost(final_free)
	crcr(final_free)
	local numrolls = G.GAME.tension or 0
	if Jen.config.punish_reroll_abuse then
		if numrolls > 1 then
			G.GAME.current_round.reroll_cost = math.min(
				math.ceil(G.GAME.current_round.reroll_cost * (1.13 ^ (numrolls - 1))), 1e100)
		end
	end
end

local gfcor = G.FUNCS.cash_out
G.FUNCS.cash_out = function(e)
	if (G.GAME.relief or 0) > 0 then
		local mod = math.min(5, G.GAME.relief)
		if mod > G.GAME.tension then mod = G.GAME.tension end
		if mod > 0 then
			ease_tension(-mod)
		end
	end
	Q(function()
		if G.GAME.tension > 0 then
			ease_relief(1)
		elseif G.GAME.relief > 0 then
			ease_relief(-G.GAME.relief)
		end
		return true
	end)
	if #SMODS.find_card('j_jen_arin') > 0 then
		for k, v in pairs(SMODS.find_card('j_jen_arin')) do v:juice_up(0.6, 1) end
		for i = 1, #SMODS.find_card('j_jen_arin') * 3 do
			Q(function()
				local duplicate = create_card('Booster', G.consumeables, nil, nil, nil, nil, k, 'arin_pack')
				if duplicate.gc and duplicate:gc().set ~= 'Booster' then
					duplicate:set_ability(jl.rnd('arin_booster_equilibrium', nil, G.P_CENTER_POOLS.Booster), true, nil)
					duplicate:set_cost()
				end
				duplicate:add_to_deck()
				G.consumeables:emplace(duplicate)
				return true
			end, 0.2 / (#SMODS.find_card('j_jen_arin') / 3), nil, 'after')
		end
	end
	if #SMODS.find_card('j_jen_lugia') > 0 then
		for k, v in pairs(SMODS.find_card('j_jen_lugia')) do v:juice_up(0.6, 1) end
		for i = 1, #SMODS.find_card('j_jen_lugia') * 2 do
			Q(function()
				local duplicate = create_card('Voucher', G.consumeables, nil, nil, nil, nil, k, 'lugia_voucher')
				if duplicate.gc and duplicate:gc().set ~= 'Voucher' then
					duplicate:set_ability(jl.rnd('lugia_voucher_equilibrium', nil, G.P_CENTER_POOLS.Voucher), true, nil)
					duplicate:set_cost()
				end
				duplicate:add_to_deck()
				G.consumeables:emplace(duplicate)
				return true
			end, 0.2 / (#SMODS.find_card('j_jen_lugia') / 3), nil, 'after')
		end
	end
	QR(function()
		if Jen.config.punish_reroll_abuse then
			local numrolls = G.GAME.tension or 0
			if numrolls > 1 then
				G.GAME.current_round.reroll_cost = math.min(
					math.ceil(G.GAME.current_round.reroll_cost * (1.13 ^ (numrolls - 1))), 1e100)
			end
		end
		return true
	end, 99)
	gfcor(e)
end

local gfrsr = G.FUNCS.reroll_shop
G.FUNCS.reroll_shop = function(e)
	if Jen.config.punish_reroll_abuse then
		if G.GAME.relief > 0 then
			ease_relief(-G.GAME.relief)
		end
		ease_tension(jl.round((3 ^ #SMODS.find_card('j_jen_aym')) / (G.GAME.current_round.reroll_cost <= 0 and 4 or 1), 2))
		if Jen.config.straddle.enabled and Jen.config.punish_reroll_abuse and G.GAME.tension >= 20 then
			if not G.GAME.straddle_active then start_straddle() end
			progress_straddle(math.ceil((2 ^ math.min(1000, G.GAME.tension - 20))))
		end
	end
	gfrsr(e)
end

-- Store the original vanilla function
local vanilla_ease_ante = ease_ante

-- Initialize crash monitoring system from JenLib
if jl and jl.crash_monitor then
	jl.crash_monitor:setup()
else
	print("[JEN WARNING] JenLib crash monitoring not available - falling back to basic monitoring")
end

-- Override the global ease_ante function to ensure ALL calls go through our version
_G.ease_ante = function(mod, no_straddle, no_ante_boost, safe_rewind)
	-- Always log when our function is called
	-- Store original mod for vanilla function call to prevent crashes from astronomical values
	local original_mod = mod
	local total_mod = mod -- This will be the total including straddle bonus

	if mod > 0 then
		if G.GAME.tortoise then
			mod = mod / 2
		end
		-- Safety check for ante-based malice calculations to prevent Event Manager overflow
		-- This doesn't limit the final malice value, just prevents overwhelming the event system
		local malice_mod = mod
		if malice_mod > 100 then
			malice_mod = 100 -- Cap the exponent to prevent Event Manager crashes
		end
		add_malice(to_big(Jen.config.malice_base / 8) * (to_big(Jen.config.malice_increase) ^ malice_mod))
	end
	if Jen.config.straddle.enabled then
		if mod < 0 and not safe_rewind then
			G.GAME.cumulative_ante_rewind = (G.GAME.cumulative_ante_rewind or 0) + mod
		end
		if G.GAME.straddle_active and mod > 0 and not no_ante_boost then
			local straddle_bonus = (G.GAME.tortoise and (G.GAME.straddle / 2) or G.GAME.straddle)
			mod = mod + straddle_bonus
			total_mod = total_mod + straddle_bonus -- Add straddle bonus to total for vanilla function
		elseif not no_straddle and not G.GAME.straddle_active and ((G.GAME.round_resets.ante + mod) < 0 or (G.GAME.cumulative_ante_rewind or 0) > Jen.config.ante_threshold) then
			start_straddle()
		end
	end

	-- Cap the mod passed to vanilla function to prevent crashes from astronomical values
	local safe_mod = total_mod -- Use total_mod (including straddle bonus) instead of original_mod
	if math.abs(safe_mod) > 1000 then
		safe_mod = safe_mod > 0 and 1000 or -1000
	end

	-- Safely call the vanilla function with error handling
	local success, error_msg = pcall(function()
		vanilla_ease_ante(safe_mod)
	end)
	if not success then
		print("[JEN ERROR] Vanilla ease_ante crashed:", tostring(error_msg))
		-- Fallback: manually increment the Ante if vanilla function fails
		G.GAME.round_resets.ante = G.GAME.round_resets.ante + safe_mod
	end
	if jl.invalid_number(G.GAME.round_resets.ante) then
		G.GAME.round_resets.ante = maxfloat
	end
	local ANTE = G.GAME.round_resets.ante

	-- Ultra-aggressive memory management: process straddle immediately and force cleanup
	Q(function()
		-- Force immediate memory cleanup before heavy operations
		collectgarbage("collect")

		if Jen.config.straddle.enabled and G.GAME.straddle_active and mod ~= 0 and not no_straddle then
			if math.ceil(mod) > 1 then mod = mod - G.GAME.straddle end
			local add = (math.abs(mod) * (Jen.config.straddle.acceleration and math.ceil(math.max(1, (G.GAME.straddle - (Jen.config.straddle.progress_max ^ 2))) / Jen.config.straddle.progress_increment) or 1) * (mod < 0 and Jen.config.straddle.backwards_mod or 1))
			if ANTE < 0 then
				add = add + math.ceil(math.abs(ANTE) ^ 2)
			end
			if G.GAME.nitro then add = add * Jen.config.straddle.progress_min end
			add = math.min(add, 9e15)

			-- Process straddle with additional safety
			local success, error_msg = pcall(function()
				progress_straddle(add)
			end)
			if not success then
				print("[JEN ERROR] progress_straddle crashed:", tostring(error_msg))
			end
		end

		-- Force aggressive memory cleanup after heavy operation
		collectgarbage("collect")
		collectgarbage("collect") -- Double cleanup for safety
		return true
	end, 0.05, nil, 'immediate') -- Even faster processing

	-- Memory-efficient: update blind_ante immediately instead of scheduling event
	G.GAME.round_resets.blind_ante = G.GAME.round_resets.ante

	-- Emergency memory cleanup and monitoring
	local memory_before = collectgarbage("count")
	if memory_before > 100000 then -- If memory usage > 100MB
		print("[JEN WARNING] High memory usage detected:", math.floor(memory_before / 1024), "KB")
		-- Force aggressive cleanup
		collectgarbage("collect")
		collectgarbage("collect")
		collectgarbage("collect")
		local memory_after = collectgarbage("count")
		print("[JEN INFO] Memory cleaned up:", math.floor((memory_before - memory_after) / 1024), "KB")
	end

	-- Schedule periodic memory cleanup to prevent future crashes
	Q(function()
		collectgarbage("collect")
		return true
	end, 1.0, nil, 'after') -- Clean up every second

	-- Event Manager protection: limit event queue size
	if G.E_MANAGER and G.E_MANAGER.event_queue then
		local queue_size = #G.E_MANAGER.event_queue
		if queue_size > 1000 then -- If event queue gets too large
			print("[JEN WARNING] Large event queue detected:", queue_size, "events - forcing cleanup!")
			-- Force process some events to reduce queue
			for i = 1, math.min(100, queue_size) do
				if G.E_MANAGER.event_queue[1] then
					table.remove(G.E_MANAGER.event_queue, 1)
				end
			end
			print("[JEN INFO] Event queue reduced to:", #G.E_MANAGER.event_queue, "events")
		end
	end
end

-- Real-time crash handler monitoring
local crash_monitor_active = false
local function start_crash_monitoring()
	if crash_monitor_active then return end
	crash_monitor_active = true

	print("[JEN DEBUG] 🔍 Starting real-time crash handler monitoring...")

	-- Monitor every frame for crash handler activation
	Q(function()
		-- Check if we're in a crash state
		if G and G.E_MANAGER then
			local memory = collectgarbage("count")
			if memory > 200000 then -- If memory spikes above 200MB
				print("[JEN DEBUG] 🚨 HIGH MEMORY SPIKE DETECTED!")
				print("[JEN DEBUG] 💾 Current memory:", memory, "KB")
				print("[JEN DEBUG] 🕐 Time:", os.date("%H:%M:%S"))
				print("[JEN DEBUG] ⚠️ Crash handler may activate soon...")
			end
		end
		return true
	end, 0.1, nil, 'after') -- Check every 0.1 seconds
end

-- Start crash monitoring after a delay
Q(function()
	start_crash_monitoring()
	return true
end, 3.0, nil, 'after') -- Start after 3 seconds

function bulk_sell_cards(cards, include_eternal, doublesell)
	local value = 0
	for k, v in pairs(cards) do
		if include_eternal or not (v.ability or {}).eternal then
			if doublesell and (v.edition or {}).jen_diplopia then
				v:sell_card()
				Q(function()
					if v then v:sell_card() end
					return true
				end, 0.1, nil, 'after')
			else
				v:sell_card()
			end
		end
	end
end

function fastlv(card, hand, instant, amount, no_astronomy, no_astronomy_omega, no_jokers)
	if instant then
		level_up_hand(card, hand, instant, amount, no_astronomy, no_astronomy_omega, no_jokers)
	else
		jl.h(localize(hand, 'poker_hands'), G.GAME.hands[hand].chips + (G.GAME.hands[hand].l_chips * amount),
			G.GAME.hands[hand].mult + (G.GAME.hands[hand].l_mult * amount), G.GAME.hands[hand].level + amount, true)
		level_up_hand(card, hand, true, amount, no_astronomy, no_astronomy_omega, no_jokers)
		delay(0.1)
	end
end

local scr = Card.sell_card

function Card:sell_card()
	local CEN = self.gc and self:gc()
	if CEN and CEN.set ~= 'Planet' and CEN.key ~= 'c_black_hole' and Jen.hv('astronomy', 5) and not (self.edition or {}).negative and not (self.base or {}).value and not (self.base or {}).suit then
		for i = 1, self:getEvalQty() do
			Q(function()
				local card2 = create_card('Planet', G.consumeables, nil, nil, nil, nil, nil, 'astronomy5_planet')
				card2.no_omega = true
				play_sound('jen_draw')
				card2:add_to_deck()
				G.consumeables:emplace(card2)
				return true
			end)
		end
	end
	if Jen.hv('astronomy', 6) and CEN and not CEN.cant_astronomy then
		local hand = jl.rndhand()
		jl.th(hand)
		fastlv(self, hand, nil, self.sell_cost / 4)
		jl.ch()
	end
	if CEN and (CEN.key == 'j_cry_altgoogol' or CEN.key == 'j_blueprint') then
		for k, v in ipairs(G.jokers.cards) do
			if v.gc and v ~= self then
				local key = v:gc().key
				if key == 'j_cry_altgoogol' or key == 'j_blueprint' or key == 'c_cry_pointer' then
					v:remove_from_deck()
					v.area:remove_card(v)
					Q(function()
						if v then
							v:add_to_deck()
							G.jokers:emplace(v)
						end
						return true
					end, 0.1, nil, 'after')
				end
				key = nil
			end
		end
	end
	if CEN and CEN.set == 'Joker' and #SMODS.find_card('j_jen_amalgam') > 0 and get_kosmos() then
		local rare = tostring(CEN.rarity)
		local value = get_amalgam_value(rare)
		if value and to_big(value) > to_big(0) then
			add_malice(value, nil, true)
		end
	end
	scr(self)
end

function Card:sell_card_jokercalc()
	jl.jokers({ selling_card = true, card = self })
	self:sell_card()
end

function lvupallhands(amnt, card, fast)
	if not amnt then return end
	if amnt == 0 then return end
	if (G.SETTINGS.FASTFORWARD or 0) > 1 then fast = true end
	if fast then
		Q(function()
			if card then
				card:juice_up(0.8, 0.5)
			end
			return true
		end)
		jl.h(localize('k_all_hands'), (amnt > 0 and '+' or '-'), (amnt > 0 and '+' or '-'),
			(amnt > 0 and '+' or '-') .. number_format(math.abs(amnt)), true)
	else
		jl.th('all')
		Q(function()
			play_sound('tarot1')
			if card then card:juice_up(0.8, 0.5) end
			return true
		end, 0.2, nil, 'after')
		jl.h(localize('k_all_hands'), (amnt > 0 and '+' or '-'), (amnt > 0 and '+' or '-'),
			(amnt > 0 and '+' or '-') .. number_format(math.abs(amnt)), true)
		-- Reduced delay for better performance
		delay(0.5)
	end
	for k, v in pairs(G.GAME.hands) do
		level_up_hand(card, k, true, amnt)
	end
	jl.ch()
end

function black_hole_effect(card, amnt)
	if (G.SETTINGS.FASTFORWARD or 0) > 0 then
		lvupallhands(amnt, card)
	else
		-- Optimized Black Hole processing for better performance
		jl.h(localize('k_all_hands'), '...', '...', '')

		-- Reduced delays and combined operations for better performance
		Q(function()
			play_sound("tarot1")
			card:juice_up(0.8, 0.5)
			G.TAROT_INTERRUPT_PULSE = true
			return true
		end, 0.1, nil, 'after') -- Reduced from 0.2

		jl.hm('+', true)
		jl.hc('+', true)
		jl.hlv('+' .. amnt)

		-- Process all hands immediately for better performance (no batching to avoid event queue buildup)
		-- Set Black Hole processing flag for performance optimizations
		G.GAME._black_hole_processing = true

		-- Process all hands immediately without batching to reduce event queue
		for k, v in pairs(G.GAME.hands) do
			level_up_hand(card, k, true, amnt)
		end

		-- Final cleanup
		G.TAROT_INTERRUPT_PULSE = nil
		G.GAME._black_hole_processing = nil -- Clear the flag
		jl.ch()
	end
end

function Card:blackhole(amnt)
	black_hole_effect(self, amnt)
end

function Card:apply_cumulative_levels(hand)
	Q(function()
		Q(function()
			if self then
				if hand and G.GAME.hands[hand] then
					jl.th(hand)
					level_up_hand(self, hand, false, (self.cumulative_lvs or 1))
					self.cumulative_lvs = nil
					jl.ch()
				else
					lvupallhands(self.cumulative_lvs, self)
					self.cumulative_lvs = nil
				end
			end
			return true
		end, 0.2, nil, 'after')
		return true
	end, 0.2, nil, 'after')
end

local function change_blind_size(newsize, instant, silent)
	newsize = to_big(newsize)
	G.GAME.blind.chips = newsize
	local chips_UI = G.hand_text_area.blind_chips
	if instant then
		G.GAME.blind.chip_text = number_format(newsize)
		G.FUNCS.blind_chip_UI_scale(G.hand_text_area.blind_chips)
		if G.HUD_blind then G.HUD_blind:recalculate() end
		chips_UI:juice_up()
		if not silent then play_sound('chips2') end
	else
		Q(function()
			G.GAME.blind.chip_text = number_format(newsize)
			G.FUNCS.blind_chip_UI_scale(G.hand_text_area.blind_chips)
			if G.HUD_blind then G.HUD_blind:recalculate() end
			chips_UI:juice_up()
			if not silent then play_sound('chips2') end
			return true
		end)
	end
end

function card_status_text(card, text, xoffset, yoffset, colour, size, DELAY, juice, jiggle, align, sound, volume, pitch,
						  trig, F)
	if (DELAY or 0) <= 0 then
		if F and type(F) == 'function' then F(card) end
		attention_text({
			text = text,
			scale = size or 1,
			hold = 0.7,
			backdrop_colour = colour or (G.C.FILTER),
			align = align or 'bm',
			major = card,
			offset = { x = xoffset or 0, y = yoffset or (-0.05 * G.CARD_H) }
		})
		if sound then
			play_sound(sound, pitch or (0.9 + (0.2 * math.random())), volume or 1)
		end
		if juice then
			if type(juice) == 'table' then
				card:juice_up(juice[1], juice[2])
			elseif type(juice) == 'number' and juice ~= 0 then
				card:juice_up(juice, juice / 6)
			end
		end
		if jiggle then
			G.ROOM.jiggle = G.ROOM.jiggle + jiggle
		end
	else
		Q(function()
			if F and type(F) == 'function' then F(card) end
			attention_text({
				text = text,
				scale = size or 1,
				hold = 0.7 + (DELAY or 0),
				backdrop_colour = colour or (G.C.FILTER),
				align = align or 'bm',
				major = card,
				offset = { x = xoffset or 0, y = yoffset or (-0.05 * G.CARD_H) }
			})
			if sound then
				play_sound(sound, pitch or (0.9 + (0.2 * math.random())), volume or 1)
			end
			if juice then
				if type(juice) == 'table' then
					card:juice_up(juice[1], juice[2])
				elseif type(juice) == 'number' and juice ~= 0 then
					card:juice_up(juice, juice / 6)
				end
			end
			if jiggle then
				G.ROOM.jiggle = G.ROOM.jiggle + jiggle
			end
			return true
		end, DELAY, nil, trig)
	end
end

function Jen.gods()
	return #SMODS.find_card('j_jen_godsmarble') > 0
end

local cacsr = CardArea.change_size
function CardArea:change_size(mod, silent)
	cacsr(self, mod)
	if not silent then self:announce_sizechange(mod) end
end

function CardArea:announce_sizechange(mod, set)
	if (mod or 0) ~= 0 then
		Q(function()
			mod = mod or 0
			local text = 'Max +'
			local col = G.C.GREEN
			if set then
				text = 'Max ='
				col = G.C.FILTER
			elseif mod < 0 then
				text = 'Max -'
				col = G.C.RED
			end
			attention_text({
				text = text .. tostring(math.abs(mod)),
				scale = 1,
				hold = 1,
				cover = self,
				cover_colour = col,
				align = 'cm',
			})
			play_sound('highlight2', 0.715, 0.2)
			play_sound('generic1')
			return true
		end, nil, nil, 'immediate')
		delay(0.5)
	end
end

function CardArea:change_size_absolute(mod, silent)
	self.config.card_limit = self.config.card_limit + (mod or 0)
	if not silent then self:announce_sizechange(mod) end
end

function CardArea:set_size_absolute(mod, silent)
	self.config.card_limit = (mod or self.config.card_limit)
	if not silent then self:announce_sizechange(mod, true) end
end

function CardArea:announce_highlightchange(mod)
	if (mod or 0) ~= 0 then
		G.E_MANAGER:add_event(Event({
			trigger = 'immediate',
			func = function()
				mod = mod or 0
				local text = 'Highlights +'
				local col = G.C.PURPLE
				if mod < 0 then
					text = 'Highlights -'
					col = G.C.FILTER
				end
				attention_text({
					text = text .. tostring(math.abs(mod)),
					scale = 1,
					hold = 1,
					cover = self,
					cover_colour = col,
					align = 'cm',
				})
				play_sound('highlight2', 0.715, 0.2)
				play_sound('generic1')
				return true
			end
		}))
		delay(0.5)
	end
end

function CardArea:change_max_highlight(mod, silent)
	self.config.highlighted_limit = self.config.highlighted_limit + (mod or 0)
	if not silent then self:announce_highlightchange(mod) end
end

function ease_winante(mod)
	Q(function()
		local ante_UI = G.hand_text_area.ante
		mod = mod or 0
		local text = 'Max'
		local col = G.C.PURPLE
		if mod < 0 then
			text = text .. ' -'
			col = G.C.GREEN
		else
			text = text .. ' +'
		end
		ante_UI.config.object:update()
		G.GAME.win_ante = G.GAME.win_ante + mod
		G.HUD:recalculate()
		attention_text({
			text = text .. tostring(math.abs(mod)),
			scale = 0.6,
			hold = 0.9,
			cover = ante_UI.parent,
			cover_colour = col,
			align = 'cm',
		})
		play_sound('highlight2', 0.4, 0.2)
		play_sound('generic1')
		return true
	end, nil, nil, 'immediate')
end

local function multante(number)
	--local targetante = math.abs(G.GAME.round_resets.ante * (2 ^ (number or 1)))
	if G.GAME.round_resets.ante < 1 then
		ease_ante(math.abs(G.GAME.round_resets.ante) + 1)
	else
		ease_ante(math.min(1e308, G.GAME.round_resets.ante * (2 ^ (number or 1)) - G.GAME.round_resets.ante))
	end
	--[[if G.GAME.win_ante < targetante then
		G.E_MANAGER:add_event(Event({trigger = 'after', delay = 0.1, func = function()
			ease_winante(targetante - G.GAME.win_ante)
		return true end }))
	end]]
end

function hsv(h, s, v)
	if s <= 0 then return v, v, v end
	h = h * 6
	local c = v * s
	local x = (1 - math.abs((h % 2) - 1)) * c
	local m, r, g, b = (v - c), 0, 0, 0
	if h < 1 then
		r, g, b = c, x, 0
	elseif h < 2 then
		r, g, b = x, c, 0
	elseif h < 3 then
		r, g, b = 0, c, x
	elseif h < 4 then
		r, g, b = 0, x, c
	elseif h < 5 then
		r, g, b = x, 0, c
	else
		r, g, b = c, 0, x
	end
	return r + m, g + m, b + m
end

local maxie_desc = {
	'Create {C:attention}2 {C:green}random {C:attention}Boosters{}, and a fixed',
	'{C:green}~15% chance{} to also create a {C:green}random {C:attention}Voucher',
	'whenever you use any {C:attention}non-{C:dark_edition}Negative{}',
	''
}

local maxie_consumables = {
	Temperance = 'c_temperance',
	['The Hermit'] = 'c_hermit',
	['The Magician'] = 'c_magician',
	['The Centurion'] = 'c_jen_centurion',
	Enceladus = 'c_jen_enceladus',
	Cryptid = 'c_cryptid',
	Infirmity = 'c_jen_reverse_strength',
	['The Low Laywoman'] = 'c_jen_reverse_high_priestess',
	Cunctation = 'c_jen_reverse_judgement'
}

local maxie_added = 0

local misc_done = false

-- Hook modulate_sound to fix big number comparison issues
local modulate_sound_ref = modulate_sound
function modulate_sound(dt)
	-- Helper function to safely convert big numbers to regular numbers
	local function safe_to_number(val)
		if type(val) == 'table' and val.to_number then
			-- It's a big number, convert it
			return val:to_number()
		elseif type(val) == 'number' then
			-- Already a number
			return val
		else
			-- Fallback
			return 0
		end
	end

	-- Convert all score_intensity values to regular numbers before calling base function
	if G.ARGS and G.ARGS.score_intensity then
		for k, v in pairs(G.ARGS.score_intensity) do
			if type(v) == 'table' and v.to_number then
				G.ARGS.score_intensity[k] = safe_to_number(v)
			end
		end
	end

	-- Call the original function
	return modulate_sound_ref(dt)
end

local game_updateref = Game.update
function Game:update(dt)
	-- Safely wrap the original update call to prevent crashes
	local success, error_msg = pcall(function()
		-- Per-tick memo: cache expensive find_card scans used multiple times this frame
		G.GAME._jen_tick_cache = G.GAME._jen_tick_cache or {}
		local cache = G.GAME._jen_tick_cache
		cache.faceless = cache.faceless or (next(SMODS.find_card('j_jen_faceless')) and true or false)
		cache.crimbo = cache.crimbo or (next(SMODS.find_card('j_jen_crimbo')) and true or false)
		cache.kudaai_or_foundry = cache.kudaai_or_foundry or
			((#SMODS.find_card('j_jen_kudaai') + #SMODS.find_card('j_jen_foundry')) > 0)
		cache.bulwark_count = cache.bulwark_count or #SMODS.find_card('j_jen_bulwark')
		-- Process Wondergeist jobs if queued
		if G.GAME._wg_jobs then
			for k, job in pairs(G.GAME._wg_jobs) do
				if (job.remaining or 0) > 0 then
					local handstats = G.GAME.hands[job.hand_key]
					local cnt = math.min(job.batch_size, job.remaining)

					-- Optimized batch processing for better performance
					if cnt > 10 then
						-- For large batches, use exponential operations when possible
						if job.op == 2 and job.operand == 2 then
							-- ^^2 operation: use power of 2 for large batches
							local power = math.min(cnt, 100) -- Cap at reasonable power
							job.chips = job.chips:arrow(2, 2):arrow(2, power - 1)
							job.mult = job.mult:arrow(2, 2):arrow(2, power - 1)
							job.remaining = job.remaining - power
						elseif job.op == 3 and job.operand == 3 then
							-- ^^^3 operation: use power of 3 for large batches
							local power = math.min(cnt, 50) -- Cap at reasonable power for ^^^3
							job.chips = job.chips:arrow(3, 3):arrow(3, power - 1)
							job.mult = job.mult:arrow(3, 3):arrow(3, power - 1)
							job.remaining = job.remaining - power
						else
							-- Fallback to regular batch processing
							for i = 1, cnt do
								job.chips = job.chips:arrow(job.op, job.operand)
								job.mult = job.mult:arrow(job.op, job.operand)
							end
							job.remaining = job.remaining - cnt
						end
					else
						-- For small batches, use regular processing
						for i = 1, cnt do
							job.chips = job.chips:arrow(job.op, job.operand)
							job.mult = job.mult:arrow(job.op, job.operand)
						end
						job.remaining = job.remaining - cnt
					end

					handstats.chips = job.chips
					handstats.mult = job.mult
					if job.remaining <= 0 then
						if not job.lv_instant and job.card and job.label then
							delay(0.5)
							Q(function()
								job.card:juice_up(job.op - 1, job.op - 1)
								return true
							end)
							if job.op == 2 then
								play_sound_q('talisman_eechip'); play_sound_q('talisman_eemult')
							else
								play_sound_q('talisman_eeechip'); play_sound_q('talisman_eeemult')
							end
							jl.hcm(job.label .. ' (x' .. tostring(job.total or 0) .. ')',
								job.label .. ' (x' .. tostring(job.total or 0) .. ')', true)
							jl.hcm(handstats.chips, handstats.mult)
							delay(0.5)
						end
						G.GAME._wg_jobs[k] = nil
					end
				end
			end
		end
		if not Jen.bans_done then
			init_cardbans()
			Jen.bans_done = true
		end
		if not misc_done then
			if G.P_CENTERS.j_jen_maxie then
				for k, v in pairs(maxie_consumables) do
					local cen = G.P_CENTERS[v]
					if cen and Jen.config.disable_bans or (not jl.bf(v, Jen.config.bans) and not jl.bf('!' .. v, Jen.config.bans)) then
						if maxie_added >= 3 then
							maxie_desc[#maxie_desc] = maxie_desc[#maxie_desc] .. ','
							maxie_desc[#maxie_desc + 1] = ''
							maxie_added = 0
						end
						if maxie_desc[#maxie_desc] ~= '' then
							maxie_desc[#maxie_desc] = maxie_desc[#maxie_desc] ..
								', {C:' .. string.lower(cen.set) .. '}' .. k .. '{}'
						else
							maxie_desc[#maxie_desc] = '{C:' .. string.lower(cen.set) .. '}' .. k .. '{}'
						end
						maxie_added = maxie_added + 1
					end
				end
				maxie_desc[#maxie_desc + 1] = ' '
				maxie_desc[#maxie_desc + 1] = caption('#1#')
				maxie_desc[#maxie_desc + 1] = faceart('Maxie')
				G.P_CENTERS.j_jen_maxie.loc_txt.text = maxie_desc
				init_localization()
			end
			G.P_CENTERS.c_soul.fusable = true
			G.P_CENTERS.c_black_hole.fusable = true
			if G.P_CENTERS.c_cry_white_hole then G.P_CENTERS.c_cry_white_hole.fusable = true end
			misc_done = true
		end
	end)

	if not success then

	end

	-- Always call the original update, even if our stuff failed
	game_updateref(self, dt)
	if G.ARGS.LOC_COLOURS then
		if not Jen.initialised_locale_colours then
			for k, v in pairs(Jen.locale_colours) do
				G.ARGS.LOC_COLOURS[k] = HEX(v)
				self.C[k] = HEX(v)
				Jen.initialised_locale_colours = true
			end
		end

		-- Ensure jen_RGB_HUE is initialized in self.C before using it
		if self.C.jen_RGB_HUE then
			local r, g, b = hsv(self.C.jen_RGB_HUE / 360, .5, 1)

			self.C.jen_RGB[1] = r
			self.C.jen_RGB[3] = g
			self.C.jen_RGB[2] = b

			self.C.jen_RGB_HUE = (self.C.jen_RGB_HUE + 0.5) % 360
			G.ARGS.LOC_COLOURS.jen_RGB = self.C.jen_RGB
		end
	end
	if G.GAME then
		-- Fix for modulate_sound crash: Convert big numbers to regular numbers
		-- The base game's modulate_sound function doesn't handle big numbers properly
		if G.ARGS and G.ARGS.score_intensity then
			-- Helper function to safely convert big numbers to regular numbers
			local function safe_to_number(val)
				if type(val) == 'table' and val.to_number then
					-- It's a big number, convert it
					return val:to_number()
				elseif type(val) == 'number' then
					-- Already a number
					return val
				else
					-- Fallback
					return 0
				end
			end

			-- Convert all score_intensity values to regular numbers
			if G.ARGS.score_intensity.earned_score then
				local earned = to_big(G.ARGS.score_intensity.earned_score)
				if not earned:isFinite() then
					G.ARGS.score_intensity.earned_score = safe_to_number(to_big(G.ARGS.score_intensity.required_score))
				else
					G.ARGS.score_intensity.earned_score = safe_to_number(earned)
				end
			end

			if G.ARGS.score_intensity.required_score then
				G.ARGS.score_intensity.required_score = safe_to_number(G.ARGS.score_intensity.required_score)
			end

			-- Convert any other potential big number fields in score_intensity
			for k, v in pairs(G.ARGS.score_intensity) do
				if type(v) == 'table' and v.to_number then
					G.ARGS.score_intensity[k] = safe_to_number(v)
				end
			end
		end
		if not Jen.config.disable_bans and G.GAME.banned_keys then
			for k, v in ipairs(Jen.config.bans) do
				if string.sub(v, 1, 1) == '!' then
					G.GAME.banned_keys[string.sub(v, 2, string.len(v))] = true
				else
					G.GAME.banned_keys[v] = true
				end
			end
		end
		if G.GAME.modifiers then
			if not G.GAME.modifiers.jen_initialise_buffs then
				G.GAME.modifiers.jen_initialise_buffs = true
				G.GAME.modifiers.cry_booster_packs = (G.GAME.modifiers.cry_booster_packs or 2) +
					Jen.config.shop_booster_pack_count_buff
				change_shop_size(Jen.config.shop_size_buff)
				SMODS.change_voucher_limit(Jen.config.shop_voucher_count_buff)
			end
		end
		if G.GAME.orrery then
			local reference = ''
			local should_rebalance = false
			for k, v in pairs(G.GAME.hands) do
				if k ~= 'cry_WholeDeck' then
					if reference == '' then
						reference = k
					elseif v.chips ~= G.GAME.hands[reference].chips or v.mult ~= G.GAME.hands[reference].mult or v.level ~= G.GAME.hands[reference].level then
						should_rebalance = true
						break
					end
				end
			end
			if should_rebalance then
				local handcount = (#G.handlist - 1)
				local pools = {
					chips = to_big(0),
					mult = to_big(0),
					level = 0
				}
				for k, v in pairs(G.GAME.hands) do
					if k ~= 'cry_WholeDeck' then
						pools.chips = pools.chips + v.chips
						pools.mult = pools.mult + v.mult
						pools.level = pools.level + v.level
					end
				end
				for k, v in pairs(G.GAME.hands) do
					if k ~= 'cry_WholeDeck' then
						v.chips = pools.chips / handcount
						v.mult = pools.mult / handcount
						v.level = pools.level / handcount
					end
				end
				jl.h(localize('k_all_hands'), pools.chips / handcount, pools.mult / handcount, pools.level / handcount)
				delay(1)
				jl.ch()
			end
		end
		Jen.kudaai_active = (#SMODS.find_card('j_jen_kudaai') + #SMODS.find_card('j_jen_foundry')) > 0
		Jen.luke_active = #SMODS.find_card('j_jen_luke') > 0
		Jen.dandy_active = #SMODS.find_card('j_jen_dandy') > 0

		-- Ensure Gateway destruction flag is properly initialized
		if G.GAME.gateway_destroying_jokers == nil then
			G.GAME.gateway_destroying_jokers = false
		end

		Jen.should_play_extraordinary = #Cryptid.advanced_find_joker(nil, "jen_extraordinary", nil, nil, true) ~= 0 or
			get_kosmos() or #Cryptid.advanced_find_joker(nil, "jen_transcendent", nil, nil, true) ~= 0 or
			#Cryptid.advanced_find_joker(nil, "jen_omegatranscendent", nil, nil, true) ~= 0
		Jen.should_play_wondrous = not Jen.should_play_extraordinary and
			#Cryptid.advanced_find_joker(nil, "jen_wondrous", nil, nil, true) ~= 0
	end
end

local annoying = {
	colour = HEX('155fd9'),
	text_colour = HEX('ff8170'),
	text = {
		'Annoying Little Shit'
	}
}

local sevensins = {
	guilduryn = {
		colour = HEX('7c0000'),
		text_colour = G.C.RED,
		text = {
			'The Seven Sins',
			'Pride'
		}
	},
	hydrangea = {
		colour = HEX('7c0000'),
		text_colour = G.C.RED,
		text = {
			'The Seven Sins',
			'Wrath'
		}
	},
	heisei = {
		colour = HEX('7c0000'),
		text_colour = G.C.RED,
		text = {
			'The Seven Sins',
			'Greed'
		}
	},
	soryu = {
		colour = HEX('7c0000'),
		text_colour = G.C.RED,
		text = {
			'The Seven Sins',
			'Lust'
		}
	},
	shikigami = {
		colour = HEX('7c0000'),
		text_colour = G.C.RED,
		text = {
			'The Seven Sins',
			'Gluttony'
		}
	},
	leviathan = {
		colour = HEX('7c0000'),
		text_colour = G.C.RED,
		text = {
			'The Seven Sins',
			'Envy'
		}
	},
	behemoth = {
		colour = HEX('7c0000'),
		text_colour = G.C.RED,
		text = {
			'The Seven Sins',
			'Sloth'
		}
	}
}

local twitch = {
	colour = HEX('9164ff'),
	text_colour = G.C.jen_RGB,
	text = {
		'Twitch Series'
	}
}

local youtube = {
	colour = HEX('ff0000'),
	text_colour = G.C.jen_RGB,
	text = {
		'YouTube Series'
	}
}

local iconic = {
	colour = HEX('00ff99'),
	text_colour = G.C.jen_RGB,
	text = {
		'Icon Series'
	}
}

local jenfriend = {
	colour = HEX('7c7cff'),
	text_colour = G.C.jen_RGB,
	text = {
		'Friends of Jen Series'
	}
}

local gaming = {
	colour = HEX('7f00ff'),
	text_colour = G.C.jen_RGB,
	text = {
		'Gaming Legends Series'
	}
}

local secret = {
	colour = G.C.BLACK,
	text_colour = G.C.EDITION,
	text = {
		'Secret'
	}
}

--MISCELLANEOUS

local function abletouseabilities()
	return jl.canuse() and not jl.booster()
end

--CONSUMABLE TYPES

SMODS.ObjectTypes.Tarot.collection_rows = { 7, 7, 7 }
SMODS.ObjectTypes.Spectral.collection_rows = { 7, 7, 7 }
SMODS.ObjectTypes.Planet.collection_rows = { 7, 7, 7 }
SMODS.ObjectTypes.Planet.default = 'c_jen_debris'

SMODS.ConsumableType {
	key = 'jen_tokens',
	collection_rows = { 6, 6 },
	primary_colour = G.C.CHIPS,
	secondary_colour = G.C.VOUCHER,
	default = 'c_jen_token_tag_standard',
	loc_txt = {
		collection = 'Tokens',
		name = 'Token'
	},
	shop_rate = 3
}

SMODS.ConsumableType {
	key = 'jen_uno',
	collection_rows = { 7, 7, 7 },
	primary_colour = G.C.CHIPS,
	secondary_colour = HEX('ff0000'),
	default = 'c_jen_uno_null',
	loc_txt = {
		collection = 'UNO Cards',
		name = 'UNO'
	},
	shop_rate = 2
}

SMODS.ConsumableType {
	key = 'jen_ability',
	collection_rows = { 4, 4 },
	primary_colour = G.C.CHIPS,
	secondary_colour = G.C.GREEN,
	loc_txt = {
		collection = 'Ability Cards',
		name = 'Ability Card'
	},
	shop_rate = 0
}

SMODS.ConsumableType {
	key = 'jen_omegaconsumable',
	collection_rows = { 7, 7, 7 },
	primary_colour = G.C.CHIPS,
	secondary_colour = G.C.BLACK,
	default = 'c_jen_pluto_omega',
	loc_txt = {
		collection = 'Omega Cards',
		name = 'Omega'
	},
	shop_rate = 0
}



--SOUNDS

if Jen.config.wondrous_music then
	SMODS.Sound({
		key = "musicWondrous",
		path = "musicWondrous.ogg",
		volume = 1,
		select_music_track = function()
			return Jen.should_play_wondrous
		end,
	})
end

if Jen.config.extraordinary_music then
	SMODS.Sound({
		key = "musicExtraordinary",
		path = "musicExtraordinary.ogg",
		volume = 1,
		select_music_track = function()
			return Jen.should_play_extraordinary
		end,
	})
end

if Jen.config.icon_music then
	SMODS.Sound({
		key = "musicIcon",
		path = "musicIcon.ogg",
		pitch = 1,
		select_music_track = function()
			return ((SMODS.OPENED_BOOSTER or {}).ability or {}).icon_pack and G.booster_pack and
				not G.booster_pack.REMOVED
		end,
	})
end

SMODS.Sound({ key = 'uno', path = 'uno.ogg' })
SMODS.Sound({ key = 'misc1', path = 'misc1.ogg' })
SMODS.Sound({ key = 'done', path = 'done.ogg' })
SMODS.Sound({ key = 'e_crystal', path = 'e_crystal.ogg' })
SMODS.Sound({ key = 'grindstone', path = 'grindstone.ogg' })
SMODS.Sound({ key = 'metalhit', path = 'metal_hit.ogg' })
SMODS.Sound({ key = 'enlightened', path = 'enlightened.ogg' })
SMODS.Sound({ key = 'omegacard', path = 'omega_card.ogg' })
SMODS.Sound({ key = 'chime', path = 'chime.ogg' })
SMODS.Sound({ key = 'enchant', path = 'enchant.ogg' })
for i = 1, 2 do
	SMODS.Sound({ key = 'metalbreak' .. i, path = 'metal_break' .. i .. '.ogg' })
end
SMODS.Sound({ key = 'ambientSinister', path = 'ambientSinister.ogg' })
SMODS.Sound({ key = 'ambientDramatic', path = 'ambientDramatic.ogg' })
for i = 1, 3 do
	SMODS.Sound({ key = 'crystalhit' .. i, path = 'crystal_hit' .. i .. '.ogg' })
	SMODS.Sound({ key = 'hurt' .. i, path = 'hurt' .. i .. '.ogg' })
	SMODS.Sound({ key = 'ambientSurreal' .. i, path = 'ambientSurreal' .. i .. '.ogg' })
end
for i = 1, 8 do
	SMODS.Sound({ key = 'gore' .. i, path = 'gore' .. i .. '.ogg' })
end
for i = 1, 4 do
	SMODS.Sound({ key = 'boost' .. i, path = 'boost' .. i .. '.ogg' })
end
SMODS.Sound({ key = 'crystalbreak', path = 'crystal_break.ogg' })
SMODS.Sound({ key = 'wererich', path = 'wererich.ogg' })
SMODS.Sound({ key = 'tension', path = 'tension.ogg' })
SMODS.Sound({ key = 'relief', path = 'relief.ogg' })
SMODS.Sound({ key = 'straddle_tick', path = 'straddle_tick.ogg' })
SMODS.Sound({ key = 'straddle_increase', path = 'straddle_increase.ogg' })
SMODS.Sound({ key = 'mushroom1', path = 'mushroom1.ogg' })
SMODS.Sound({ key = 'mushroom2', path = 'mushroom2.ogg' })
SMODS.Sound({ key = 'draw', path = 'draw.ogg' })
SMODS.Sound({ key = 'pop', path = 'pop.ogg' })
SMODS.Sound({ key = 'gong', path = 'gong.ogg' })
SMODS.Sound({ key = 'heartbeat', path = 'warning_heartbeat.ogg' })
SMODS.Sound({ key = 'sin', path = 'e_sinned.ogg' })
for i = 1, 5 do
	SMODS.Sound({ key = 'collapse' .. i, path = 'collapse_' .. i .. '.ogg' })
end
for i = 1, 6 do
	SMODS.Sound({ key = 'grand' .. i, path = 'grand_dad' .. i .. '.ogg' })
end
--EDITION ASSETS

local shaders = {
	'chromatic',
	'gilded',
	'laminated',
	'reversed',
	'sepia',
	'wavy',
	'dithered',
	'watered',
	'sharpened',
	'missingtexture',
	'prismatic',
	'polygloss',
	'ink',
	'strobe',
	'sequin',
	'blaze',
	'encoded',
	'misprint',
	--'graymatter',
	--'hardstone',
	--'bedrock',
	--'bismuth',
	'unreal',
	'ionized',
	'diplopia',
	'moire'
}

local shaders2 = {
	'bloodfoil',
	'cosmic',
	'shaderpack_1',
	'shaderpack_4',
	'wtfwave'
}

local shaders3 = {
	'wee',
	'jumbo'
}

for k, v in pairs(shaders) do
	SMODS.Shader({ key = v, path = v .. '.fs' })
	SMODS.Sound({ key = 'e_' .. v, path = 'e_' .. v .. '.ogg' })
end

for k, v in pairs(shaders2) do
	SMODS.Shader({ key = v, path = v .. '.fs' })
end

for k, v in pairs(shaders3) do
	SMODS.Sound({ key = 'e_' .. v, path = 'e_' .. v .. '.ogg' })
end

--EDITIONS

SMODS.Edition({
	key = "dithered",
	loc_txt = {
		name = "Dithered",
		label = "Dithered",
		text = {
			"{C:red}#1#{} Chips",
			"{C:mult}+#2#{} Mult",
			'{C:dark_edition,s:0.7,E:2}Shader by : stupxd'
		}
	},
	discovered = true,
	unlocked = true,
	shader = 'dithered',
	config = { chips = -25, mult = 33 },
	sound = {
		sound = 'jen_e_dithered',
		per = 1,
		vol = 0.6
	},
	in_shop = true,
	weight = 8,
	extra_cost = 2,
	apply_to_float = false,
	loc_vars = function(self)
		return { vars = { self.config.chips, self.config.mult } }
	end,
	calculate = function(self, card, context)
		if context.edition and context.cardarea == G.jokers and context.joker_main then
			return {
				chips = self.config.chips,
				mult = self.config.mult
			}
		end
		if context.cardarea == G.play and context.main_scoring then
			return {
				chips = self.config.chips,
				mult = self.config.mult
			}
		end
	end
})

SMODS.Edition({
	key = "sharpened",
	loc_txt = {
		name = "Sharpened",
		label = "Sharpened",
		text = {
			"{C:chips}+#1#{} Chips",
			"{C:red}#2#{} Mult",
			'{C:dark_edition,s:0.7,E:2}Shader by : stupxd'
		}
	},
	discovered = true,
	unlocked = true,
	shader = 'sharpened',
	config = { chips = 333, mult = -5 },
	sound = {
		sound = 'jen_e_sharpened',
		per = 1.2,
		vol = 0.6
	},
	in_shop = true,
	weight = 8,
	extra_cost = 2,
	apply_to_float = false,
	loc_vars = function(self)
		return { vars = { self.config.chips, self.config.mult } }
	end,
	calculate = function(self, card, context)
		if context.edition and context.cardarea == G.jokers and context.joker_main then
			return {
				chips = self.config.chips,
				mult = self.config.mult
			}
		end
		if context.cardarea == G.play and context.main_scoring then
			return {
				chips = self.config.chips,
				mult = self.config.mult
			}
		end
	end
})

SMODS.Edition({
	key = "prismatic",
	loc_txt = {
		name = "Prismatic",
		label = "Prismatic",
		text = {
			"{X:mult,C:white}x#1#{C:mult} Mult{}, {X:chips,C:white}x#2#{C:chips} Chips",
			'and {C:money}+$#3#{} when scored',
			'{C:dark_edition,s:0.7,E:2}Shader by : Oiiman'
		}
	},
	shader = "prismatic",
	discovered = true,
	unlocked = true,
	config = { x_mult = 15, x_chips = 5, p_dollars = 5 },
	sound = {
		sound = 'jen_e_prismatic',
		per = 1.2,
		vol = 0.5
	},
	in_shop = true,
	weight = 0.2,
	extra_cost = 12,
	apply_to_float = false,
	get_weight = function(self)
		return G.GAME.edition_rate * self.weight
	end,
	loc_vars = function(self)
		return { vars = { self.config.x_mult, self.config.x_chips, self.config.p_dollars } }
	end,
	calculate = function(self, card, context)
		if context.post_joker or (context.main_scoring and context.cardarea == G.play) then
			return {
				x_mult = self.config.x_mult,
				x_chips = self.config.x_chips,
				dollars = self.config.p_dollars
			}
		end
	end
})
SMODS.Edition({
	key = "ionized",
	loc_txt = {
		name = "Ionised",
		label = "Ionised",
		text = {
			"{C:blue}+#1# Chips{}, {C:red,s:1.2}BUT",
			"{X:red,C:white}x#2#{C:red} Mult",
			'{C:dark_edition,s:0.7,E:2}Shader by : Oiiman'
		}
	},
	shader = "ionized",
	discovered = true,
	unlocked = true,
	config = { chips = 2000, x_mult = 0.5 },
	sound = {
		sound = 'jen_e_ionized',
		per = 1,
		vol = 0.5
	},
	in_shop = true,
	weight = 3,
	extra_cost = 7,
	apply_to_float = false,
	get_weight = function(self)
		return G.GAME.edition_rate * self.weight
	end,
	loc_vars = function(self)
		return { vars = { self.config.chips, self.config.x_mult } }
	end,
	calculate = function(self, card, context)
		if context.post_joker or (context.main_scoring and context.cardarea == G.play) then
			return {
				chips = self.config.chips,
				x_mult = self.config.x_mult
			}
		end
	end
})

SMODS.Edition({
	key = "misprint",
	loc_txt = {
		name = "Misprint",
		label = "Misprint",
		text = {
			"Card has {C:attention}unknown, random bonus values",
			'{C:inactive}({C:tarot}+{C:inactive}, {X:tarot,C:white}x{C:inactive}, and {X:tarot,C:dark_edition}^{C:inactive} Chips and/or Mult)',
			'{C:dark_edition,s:0.7,E:2}Shader by : stupxd'
		}
	},
	shader = "misprint",
	disable_base_shader = true,
	no_shadow = true,
	discovered = true,
	unlocked = true,
	config = {},
	sound = {
		sound = 'jen_e_misprint',
		per = 1,
		vol = 0.5
	},
	misc_badge = {
		colour = G.C.RARITY[3],
		text = {
			"Rare"
		}
	},
	in_shop = true,
	weight = 1.5,
	extra_cost = 8,
	apply_to_float = false,
	get_weight = function(self)
		return G.GAME.edition_rate * self.weight
	end,
})

local wee_description = {
	'{C:inactive}==On Jokers==',
	'Values of card {C:attention}increase by 8%',
	'whenever a {C:attention}2{} scores',
	'{C:inactive}(If possible)',
	' ',
	'{C:inactive}==On Playing Cards==',
	'{C:chips}Extra chips{} on card increases by',
	'{X:attention,C:white}3x{} the card\'s rank when scored',
	'{C:inactive}(2s gain +60 instead, rankless cards gain +25 instead)',
	' ',
	'{C:inactive,E:1,s:0.7}Haha, look; it\'s tiny!'
}

SMODS.Edition({
	key = "wee",
	no_edeck = true,
	loc_txt = {
		name = "Wee",
		label = "Wee",
		text = wee_description
	},
	on_apply = function(card)
		Q(function()
			card:shrink(Jen.config.wee_sizemod)
			return true
		end, nil, nil, nil, false, false)
	end,
	on_remove = function(card)
		Q(function()
			card:grow(Jen.config.wee_sizemod)
			return true
		end, nil, nil, nil, false, false)
	end,
	shader = false,
	discovered = true,
	unlocked = true,
	config = { twos_scored = 0 },
	sound = {
		sound = 'jen_e_wee',
		per = 1,
		vol = 0.5
	},
	in_shop = true,
	weight = 4,
	extra_cost = 5,
	apply_to_float = false,
	get_weight = function(self)
		return G.GAME.edition_rate * self.weight * (G.GAME.weeck and 222.22 or 1)
	end,
})

SMODS.Edition({
	key = "jumbo",
	no_edeck = true,
	loc_txt = {
		name = "Jumbo",
		label = "Jumbo",
		text = {
			"All card values are",
			"{C:attention}multiplied{} by {C:attention}up to 100",
			"{C:inactive}(If possible)",
			"{C:inactive,s:1}(May be less effective on some items)",
			"{C:inactive,E:1,s:0.7}Whoa, it's huge!!{}"
		}
	},
	misc_badge = {
		colour = G.C.RARITY[4],
		text = {
			"Legendary"
		}
	},
	on_apply = function(card)
		Q(function()
			card:grow(Jen.config.wee_sizemod)
			return true
		end, nil, nil, nil, false, false)
		local modifier = 100
		local obj = card:gc()
		if obj.set == 'Booster' or obj.jumbo_mod then
			modifier = obj.jumbo_mod or 10
		end
		local was_added = card.added_to_deck
		if was_added then
			card:remove_from_deck()
		end
		Cryptid.misprintize(card, { min = modifier, max = modifier }, nil, true)
		if was_added then
			card:add_to_deck()
		end
	end,
	on_remove = function(card)
		Q(function()
			card:shrink(Jen.config.wee_sizemod)
			return true
		end, nil, nil, nil, false, false)
		local modifier = 100
		local was_added = card.added_to_deck
		if was_added then
			card:remove_from_deck()
		end
		Cryptid.misprintize(card, { min = 1 / modifier, max = 1 / modifier }, nil, true)
		if was_added then
			card:add_to_deck()
		end
	end,
	shader = false,
	discovered = true,
	unlocked = true,
	config = { twos_scored = 0 },
	sound = {
		sound = 'jen_e_jumbo',
		per = 1,
		vol = 0.5
	},
	in_shop = true,
	weight = 0.8,
	extra_cost = 12,
	apply_to_float = false,
	get_weight = function(self)
		return G.GAME.edition_rate * self.weight
	end,
})

SMODS.Edition({
	key = "blaze",
	loc_txt = {
		name = "Blaze",
		label = "Blaze",
		text = {
			'Retrigger this card {C:attention}#1#{} time(s), {C:red,s:1.2}BUT',
			"{C:red}#2#{C:chips} Chips{} and {C:red}#3#{C:mult} Mult",
			'{C:dark_edition,s:0.7,E:2}Shader by : stupxd'
		}
	},
	shader = "blaze",
	discovered = true,
	unlocked = true,
	config = { retriggers = 5, chips = -5, mult = -1 },
	sound = {
		sound = 'jen_e_blaze',
		per = 1,
		vol = 0.5
	},
	in_shop = true,
	weight = 5,
	extra_cost = 7,
	apply_to_float = false,
	get_weight = function(self)
		return G.GAME.edition_rate * self.weight
	end,
	loc_vars = function(self)
		return { vars = { self.config.retriggers, self.config.chips, self.config.mult } }
	end,
	calculate = function(self, card, context)
		if context.edition and context.cardarea == G.jokers and context.joker_main then
			return {
				retriggers = self.config.retriggers,
				chips = self.config.chips,
				mult = self.config.mult
			}
		end
		if context.cardarea == G.play and context.main_scoring then
			return {
				repetitions = self.config.retriggers,
				chips = self.config.chips,
				mult = self.config.mult
			}
		end
	end
})

SMODS.Edition({
	key = "wavy",
	loc_txt = {
		name = "Wavy",
		label = "Wavy",
		text = {
			'Retrigger this card {C:attention}#1#{} time(s)',
			'{C:dark_edition,s:0.7,E:2}Shader by : stupxd'
		}
	},
	misc_badge = {
		colour = G.C.RARITY[3],
		text = {
			"Rare"
		}
	},
	shader = "wavy",
	disable_base_shader = true,
	no_shadow = true,
	discovered = true,
	unlocked = true,
	config = { retriggers = 30 },
	sound = {
		sound = 'jen_e_wavy',
		per = 1,
		vol = 0.5
	},
	in_shop = true,
	weight = 1,
	extra_cost = 13,
	apply_to_float = false,
	get_weight = function(self)
		return G.GAME.edition_rate * self.weight
	end,
	loc_vars = function(self)
		return { vars = { self.config.retriggers } }
	end,
	calculate = function(self, card, context)
		if context.edition and context.cardarea == G.jokers and context.joker_main then
			return {
				retriggers = self.config.retriggers
			}
		end
		if context.repetition and context.cardarea == G.play then
			return {
				repetitions = self.config.retriggers
			}
		end
	end
})

SMODS.Edition({
	key = "encoded",
	loc_txt = {
		name = "Encoded",
		label = "Encoded",
		text = {
			'Creates {C:attention}#1# {C:dark_edition}Negative {C:cry_code}Code{} cards',
			'when destroyed, sold or used',
			mayoverflow,
			'{C:dark_edition,s:0.7,E:2}Shader by : Oiiman'
		}
	},
	shader = "encoded",
	discovered = true,
	unlocked = true,
	config = { codes = 15 },
	sound = {
		sound = 'jen_e_encoded',
		per = 1,
		vol = 0.5
	},
	misc_badge = {
		colour = G.C.RARITY[3],
		text = {
			"Rare"
		}
	},
	in_shop = true,
	weight = 1,
	extra_cost = 9,
	apply_to_float = false,
	get_weight = function(self)
		return G.GAME.edition_rate * self.weight
	end,
	loc_vars = function(self)
		return { vars = { self.config.codes } }
	end
})

SMODS.Edition({
	key = "diplopia",
	loc_txt = {
		name = "Diplopia",
		label = "Diplopia",
		text = {
			'Retrigger this card {C:attention}#1#{} time(s)',
			'{C:attention}Resists{} being destroyed/sold {C:attention}once{}, after which',
			'this edition is then removed from the card',
			'{C:inactive}(Selling will still give money)',
			"{C:inactive}I'm... seeing... double...!",
			'{C:dark_edition,s:0.7,E:2}Shader by : Oiiman'
		}
	},
	shader = "diplopia",
	discovered = true,
	unlocked = true,
	config = { retriggers = 1 },
	sound = {
		sound = 'jen_e_diplopia',
		per = 1,
		vol = 0.8
	},
	in_shop = true,
	weight = 3,
	extra_cost = 7,
	apply_to_float = true,
	get_weight = function(self)
		return G.GAME.edition_rate * self.weight
	end,
	loc_vars = function(self)
		return { vars = { self.config.retriggers } }
	end,
	calculate = function(self, card, context)
		if context.edition and context.cardarea == G.jokers and context.joker_main then
			return {
				retriggers = self.config.retriggers
			}
		end
		if context.repetition and context.cardarea == G.play then
			return {
				repetitions = self.config.retriggers
			}
		end
	end
})

SMODS.Edition({
	key = "sequin",
	loc_txt = {
		name = "Sequin",
		label = "Sequin",
		text = {
			"{C:chips}+#1#{} Chips",
			"{C:red}+#2#{} Mult",
			'Can be {C:money}sold{} for {C:attention}three times{} its cost {C:inactive}(+200% profit)',
			'Minimum sell price is always at least {C:money}$6 {C:inactive}(+500% minimum profit)',
			'{C:dark_edition,s:0.7,E:2}Shader by : Oiiman'
		}
	},
	discovered = true,
	unlocked = true,
	shader = 'sequin',
	config = { chips = 25, mult = 2 },
	sound = {
		sound = 'jen_e_sequin',
		per = 1,
		vol = 0.4
	},
	in_shop = true,
	weight = 3,
	extra_cost = 0,
	apply_to_float = false,
	get_weight = function(self)
		return G.GAME.edition_rate * self.weight
	end,
	loc_vars = function(self)
		return { vars = { self.config.chips, self.config.mult } }
	end,
	calculate = function(self, card, context)
		if context.edition and context.cardarea == G.jokers and context.joker_main then
			return {
				chips = self.config.chips,
				mult = self.config.mult
			}
		end
		if context.cardarea == G.play and context.main_scoring then
			return {
				chips = self.config.chips,
				mult = self.config.mult
			}
		end
	end
})

local scr = Card.set_cost
function Card:set_cost()
	scr(self)
	if (self.edition or {}).jen_crystal then
		self.cost = 1
		self.sell_cost = 1
		self.sell_cost_label = self.facing == 'back' and '?' or self.sell_cost
	end
	if (self.edition or {}).jen_sequin then
		self.sell_cost = math.max(2, (self.sell_cost or 2), (self.cost or 2)) * 3
		self.sell_cost_label = self.facing == 'back' and '?' or self.sell_cost
	end
	if self.from_tag then
		self.sell_cost = 0
		self.sell_cost_label = 0
	end
end

SMODS.Edition {
	key = "laminated",
	loc_txt = {
		name = "Laminated",
		label = "Laminated",
		text = {
			"{C:blue}+#1# Chips{}, {C:red}+#2# Mult{}",
			"Card costs and sells for",
			"{C:purple}significantly less value{}"
		}
	},
	shader = "laminated",
	discovered = true,
	unlocked = true,
	config = { chips = 3, mult = 1 },
	sound = {
		sound = 'jen_e_laminated',
		per = 1,
		vol = 0.4
	},
	in_shop = true,
	weight = 8,
	extra_cost = -5,
	apply_to_float = false,
	get_weight = function(self)
		return G.GAME.edition_rate * self.weight
	end,
	loc_vars = function(self)
		return { vars = { self.config.chips, self.config.mult } }
	end,
	calculate = function(self, card, context)
		if context.edition and context.cardarea == G.jokers and context.joker_main then
			return {
				chips = self.config.chips,
				mult = self.config.mult
			}
		end
		if context.cardarea == G.play and context.main_scoring then
			return {
				chips = self.config.chips,
				mult = self.config.mult
			}
		end
	end
}

SMODS.Edition {
	key = "crystal",
	loc_txt = {
		name = "Crystal",
		label = "Crystal",
		text = {
			"{C:chips}+#1# Chips{}",
			"Card costs and sells for {C:money}$1{}"
		}
	},
	shader = "laminated",
	discovered = true,
	unlocked = true,
	disable_base_shader = true,
	no_shadow = true,
	config = { chips = 111 },
	sound = {
		sound = 'jen_e_crystal',
		per = 1,
		vol = 0.4
	},
	in_shop = true,
	weight = 4,
	extra_cost = 0,
	apply_to_float = false,
	get_weight = function(self)
		return G.GAME.edition_rate * self.weight
	end,
	loc_vars = function(self)
		return { vars = { self.config.chips } }
	end,
	calculate = function(self, card, context)
		if context.edition and context.cardarea == G.jokers and context.joker_main then
			return {
				chips = self.config.chips
			}
		end
		if context.cardarea == G.play and context.main_scoring then
			return {
				chips = self.config.chips
			}
		end
	end
}

SMODS.Edition {
	key = "sepia",
	loc_txt = {
		name = "Sepia",
		label = "Sepia",
		text = {
			"{C:blue}+#1# Chips{}, {C:red}+#2# Mult{}",
			"Card costs and sells for",
			"{C:money}significantly more value{}",
			'{C:dark_edition,s:0.7,E:2}Shader by : stupxd'
		}
	},
	shader = "sepia",
	discovered = true,
	unlocked = true,
	config = { chips = 150, mult = 9 },
	sound = {
		sound = 'jen_e_sepia',
		per = 1,
		vol = 0.5
	},
	in_shop = true,
	weight = 6,
	extra_cost = 20,
	get_weight = function(self)
		return G.GAME.edition_rate * self.weight
	end,
	apply_to_float = false,
	loc_vars = function(self)
		return { vars = { self.config.chips, self.config.mult } }
	end,
	calculate = function(self, card, context)
		local chips = self.config.chips
		local mult = self.config.mult
		if context.edition and context.cardarea == G.jokers and context.joker_main then
			return {
				chips = self.config.chips,
				mult = self.config.mult
			}
		end
		if context.cardarea == G.play and context.main_scoring then
			return {
				chips = self.config.chips,
				mult = self.config.mult
			}
		end
	end
}

SMODS.Edition {
	key = "ink",
	loc_txt = {
		name = "Ink",
		label = "Ink",
		text = {
			"{C:chips}+#1# Chips{}, {C:mult}+#2# Mult{}",
			"and {X:mult,C:white}X#3#{C:red} Mult{}",
			'{C:dark_edition,s:0.7,E:2}Shader by : Oiiman'
		}
	},
	shader = "ink",
	discovered = true,
	unlocked = true,
	config = { chips = 200, mult = 10, x_mult = 2 },
	sound = {
		sound = 'jen_e_ink',
		per = 1.2,
		vol = 0.4
	},
	in_shop = true,
	weight = 4,
	extra_cost = 7,
	apply_to_float = false,
	get_weight = function(self)
		return G.GAME.edition_rate * self.weight
	end,
	loc_vars = function(self)
		return { vars = { self.config.chips, self.config.mult, self.config.x_mult } }
	end,
	calculate = function(self, card, context)
		local chips = self.config.chips
		local mult = self.config.mult
		local x_mult = self.config.x_mult
		if context.edition and context.cardarea == G.jokers and context.joker_main then
			return {
				chips = self.config.chips,
				mult = self.config.mult,
				x_mult = self.config.x_mult
			}
		end
		if context.cardarea == G.play and context.main_scoring then
			return {
				chips = self.config.chips,
				mult = self.config.mult,
				x_mult = self.config.x_mult
			}
		end
	end
}

SMODS.Edition {
	key = "polygloss",
	loc_txt = {
		name = "Polygloss",
		label = "Polygloss",
		text = {
			"{C:chips}+#1#{}, {X:chips,C:white}x#2#{} & {X:chips,C:dark_edition}^#3#{} Chips",
			"{C:mult}+#4#{}, {X:mult,C:white}x#5#{} & {X:mult,C:dark_edition}^#6#{} Mult",
			"Generates {C:money}+$#7#",
			'{C:dark_edition,s:0.7,E:2}Shader by : Oiiman'
		}
	},
	discovered = true,
	unlocked = true,
	shader = 'polygloss',
	config = { chips = 1, mult = 1, x_chips = 1.1, x_mult = 1.1, e_chips = 1.01, e_mult = 1.01, p_dollars = 1 },
	in_shop = true,
	weight = 8,
	sound = {
		sound = 'jen_e_polygloss',
		per = 1.2,
		vol = 0.4
	},
	extra_cost = 2,
	apply_to_float = false,
	loc_vars = function(self)
		return { vars = { self.config.chips, self.config.x_chips, self.config.e_chips, self.config.mult, self.config.x_mult, self.config.e_mult, self.config.p_dollars } }
	end,
	calculate = function(self, card, context)
		local chips = self.config.chips
		local mult = self.config.mult
		local x_chips = self.config.x_chips
		local x_mult = self.config.x_mult
		local e_chips = self.config.e_chips
		local e_mult = self.config.e_mult
		local p_dollars = self.config.p_dollars
		if context.edition and context.cardarea == G.jokers and context.joker_main then
			return {
				chips = self.config.chips,
				mult = self.config.mult,
				x_chips = self.config.x_chips,
				x_mult = self.config.x_mult,
				e_chips = self.config.e_chips,
				e_mult = self.config.e_mult,
				p_dollars = self.config.p_dollars
			}
		end
		if context.cardarea == G.play and context.main_scoring then
			return {
				chips = self.config.chips,
				mult = self.config.mult,
				x_chips = self.config.x_chips,
				x_mult = self.config.x_mult,
				e_chips = self.config.e_chips,
				e_mult = self.config.e_mult,
				p_dollars = self.config.p_dollars
			}
		end
	end
}

SMODS.Edition {
	key = "gilded",
	loc_txt = {
		name = "Gilded",
		label = "Gilded",
		text = {
			"Generates {C:money}$#1#",
			"Card has an {C:red}extreme{C:money} buy & sell value",
			'{C:dark_edition,s:0.7,E:2}Shader by : Oiiman'
		}
	},
	discovered = true,
	unlocked = true,
	shader = 'gilded',
	config = { p_dollars = 20 },
	in_shop = true,
	weight = 2,
	sound = {
		sound = 'jen_e_gilded',
		per = 1,
		vol = 0.4
	},
	misc_badge = {
		colour = G.C.RARITY[3],
		text = {
			"Rare"
		}
	},
	extra_cost = 200,
	apply_to_float = false,
	loc_vars = function(self)
		return { vars = { self.config.p_dollars } }
	end,
	calculate = function(self, card, context)
		local p_dollars = self.config.p_dollars
		if context.edition and context.cardarea == G.jokers and context.joker_main then
			return {
				p_dollars = self.config.p_dollars
			}
		end
		if context.main_scoring and context.cardarea == G.play then
			return {
				p_dollars = self.config.p_dollars
			}
		end
	end
}

SMODS.Edition {
	key = "chromatic",
	loc_txt = {
		name = "Chromatic",
		label = "Chromatic",
		text = {
			"{C:chips}+#1#{} Chips",
			"{C:mult}+#2#{} Mult",
			'{C:dark_edition,s:0.7,E:2}Shader by : stupxd'
		}
	},
	discovered = true,
	unlocked = true,
	shader = 'chromatic',
	config = { chips = 10, mult = 4 },
	sound = {
		sound = 'jen_e_chromatic',
		per = 1,
		vol = 0.5
	},
	in_shop = true,
	weight = 8,
	extra_cost = 4,
	apply_to_float = false,
	loc_vars = function(self)
		return { vars = { self.config.chips, self.config.mult } }
	end,
	calculate = function(self, card, context)
		local chips = self.config.chips
		local mult = self.config.mult
		if context.edition and context.cardarea == G.jokers and context.joker_main then
			return {
				chips = self.config.chips,
				mult = self.config.mult
			}
		end
		if context.cardarea == G.play and context.main_scoring then
			return {
				chips = self.config.chips,
				mult = self.config.mult
			}
		end
	end
}

SMODS.Edition {
	key = "watered",
	loc_txt = {
		name = "Watercoloured",
		label = "Watercoloured",
		text = {
			"Retrigger this card {C:attention}#1#{} times",
			'{C:dark_edition,s:0.7,E:2}Shader by : stupxd'
		}
	},
	discovered = true,
	unlocked = true,
	shader = 'watered',
	config = { retriggers = 2 },
	sound = {
		sound = 'jen_e_watered',
		per = 1,
		vol = 0.4
	},
	in_shop = true,
	weight = 8,
	extra_cost = 4,
	apply_to_float = false,
	loc_vars = function(self)
		return { vars = { self.config.retriggers } }
	end,
	calculate = function(self, card, context)
		local retriggers = self.config.retriggers
		if context.edition and context.cardarea == G.jokers and context.joker_main and context.other_joker == self then
			return { repetitions = self.config.retriggers }
		end
		if context.repetition and context.cardarea == G.play then
			return { repetitions = self.config.retriggers }
		end
	end
}

SMODS.Edition {
	key = "reversed",
	loc_txt = {
		name = "Reversed",
		label = "Reversed",
		text = {
			'{C:chips}+#1#{} and {X:chips,C:white}x#2#{C:chips} Chips{},',
			'{C:mult}+#3#{} and {X:mult,C:white}x#4#{C:mult} Mult',
			'{C:dark_edition,s:0.7,E:2}Shader by : stupxd'
		}
	},
	discovered = true,
	unlocked = true,
	disable_base_shader = true,
	no_shadow = true,
	shader = 'reversed',
	config = { chips = 300, x_chips = 3, mult = 300, x_mult = 3 },
	sound = {
		sound = 'jen_e_reversed',
		per = 1,
		vol = 0.4
	},
	in_shop = true,
	weight = 0.1,
	extra_cost = 7,
	apply_to_float = false,
	loc_vars = function(self)
		return { vars = { self.config.chips, self.config.x_chips, self.config.mult, self.config.x_mult } }
	end,
	calculate = function(self, card, context)
		local chips = self.config.chips
		local x_chips = self.config.x_chips
		local mult = self.config.mult
		local x_mult = self.config.x_mult
		if context.edition and context.cardarea == G.jokers and context.joker_main then
			return {
				chips = self.config.chips,
				x_chips = self.config.x_chips,
				mult = self.config.mult,
				x_mult = self.config.x_mult
			}
		end
		if context.cardarea == G.play and context.main_scoring then
			return {
				chips = self.config.chips,
				x_chips = self.config.x_chips,
				mult = self.config.mult,
				x_mult = self.config.x_mult
			}
		end
	end
}

SMODS.Edition {
	key = "missingtexture",
	loc_txt = {
		name = "Missing Textures",
		label = "Missing Textures",
		text = {
			"{X:red,C:white}x#1#{C:red} Mult{}, {C:red,s:1.2}BUT",
			"{C:red}lose {C:money}$#2#{} when scored",
			'{C:inactive,S:0.7}Someone forgot to install Counter-Strike: Source...',
			'{C:dark_edition,s:0.7,E:2}Shader by : stupxd'
		}
	},
	discovered = true,
	unlocked = true,
	shader = 'missingtexture',
	config = { x_mult = 25, p_dollars = -5 },
	sound = {
		sound = 'jen_e_missingtexture',
		per = 1,
		vol = 0.6
	},
	in_shop = true,
	weight = 3,
	extra_cost = 7,
	apply_to_float = false,
	loc_vars = function(self)
		return { vars = { self.config.x_mult, math.abs(self.config.p_dollars) } }
	end,
	calculate = function(self, card, context)
		local x_mult = self.config.x_mult
		local p_dollars = self.config.p_dollars
		if context.edition and context.cardarea == G.jokers and context.joker_main then
			return {
				x_mult = self.config.x_mult,
				p_dollars = self.config.p_dollars
			}
		end
		if context.cardarea == G.play and context.main_scoring then
			return {
				x_mult = self.config.x_mult,
				p_dollars = self.config.p_dollars
			}
		end
	end
}

SMODS.Edition {
	key = "bloodfoil",
	loc_txt = {
		name = "Bloodfoil",
		label = "Bloodfoil",
		text = {
			"{X:jen_RGB,C:white,s:1.5}^^#1#{C:chips} Chips"
		}
	},
	misc_badge = {
		colour = G.C.RARITY['cry_exotic'],
		text = {
			"Exotic"
		}
	},
	shader = "bloodfoil",
	discovered = true,
	unlocked = true,
	config = { ee_chips = 1.2 },
	sound = {
		sound = 'negative',
		per = 0.5,
		vol = 1
	},
	weight = 0.04,
	extra_cost = 30,
	apply_to_float = false,
	get_weight = function(self)
		return G.GAME.edition_rate * self.weight * (250 ^ #SMODS.find_card('j_jen_bulwark'))
	end,
	loc_vars = function(self)
		return { vars = { self.config.ee_chips } }
	end,
	calculate = function(self, card, context)
		local ee_chips = self.config.ee_chips
		if context.edition and context.cardarea == G.jokers and context.joker_main then
			return {
				ee_chips = self.config.ee_chips
			}
		end
		if context.cardarea == G.play and context.main_scoring then
			return {
				ee_chips = self.config.ee_chips
			}
		end
	end
}

SMODS.Edition {
	key = "blood",
	no_edeck = true,
	loc_txt = {
		name = "Blood",
		label = "Blood",
		text = {
			"{X:jen_RGB,C:white,s:1.5}^^#1#{C:mult} Mult",
			'{C:dark_edition,s:0.7,E:2}Shader by : Oiiman'
		}
	},
	shader = "cosmic",
	discovered = true,
	unlocked = true,
	config = { ee_mult = 1.2 },
	sound = {
		sound = 'negative',
		per = 0.5,
		vol = 1
	},
	misc_badge = {
		colour = G.C.RARITY['cry_exotic'],
		text = {
			"Exotic"
		}
	},
	weight = 0.04,
	extra_cost = 30,
	apply_to_float = false,
	get_weight = function(self)
		return G.GAME.edition_rate * self.weight * (250 ^ #SMODS.find_card('j_jen_bulwark'))
	end,
	loc_vars = function(self)
		return { vars = { self.config.ee_mult } }
	end,
	calculate = function(self, card, context)
		local ee_mult = self.config.ee_mult
		if context.edition and context.cardarea == G.jokers and context.joker_main then
			return {
				ee_mult = self.config.ee_mult
			}
		end
		if context.cardarea == G.play and context.main_scoring then
			return {
				ee_mult = self.config.ee_mult
			}
		end
	end
}

SMODS.Edition {
	key = "moire",
	loc_txt = {
		name = "Moire",
		label = "Moire",
		text = {
			jl.pluschips('#1#') .. ', ' .. jl.mulchips('#2#') .. ', ' .. jl.expochips('#3#') .. ', ' .. jl.tetchips('#4#') .. ' & ' .. jl.penchips('#5#') .. ' Chips',
			jl.plusmult('#6#') .. ', ' .. jl.mulmult('#7#') .. ', ' .. jl.expomult('#8#') .. ', ' .. jl.tetmult('#9#') .. ' & ' .. jl.penmult('#10#') .. ' Mult',
			'{C:dark_edition,s:0.7,E:2}Shader by : Oiiman'
		}
	},
	misc_badge = {
		colour = G.C.jen_RGB,
		text = {
			"Wondrous"
		}
	},
	discovered = true,
	no_edeck = true,
	unlocked = true,
	shader = 'moire',
	config = { chips = math.pi * 1e4, x_chips = math.pi * 1e3, e_chips = math.pi * 100, ee_chips = math.pi * 10, eee_chips = math.pi, mult = math.pi * 1e4, x_mult = math.pi * 1e3, e_mult = math.pi * 100, ee_mult = math.pi * 10, eee_mult = math.pi },
	sound = {
		sound = 'jen_e_moire',
		per = 1,
		vol = 0.7
	},
	in_shop = true,
	weight = 0.01,
	extra_cost = math.pi * 1e3,
	apply_to_float = false,
	get_weight = function(self)
		return G.GAME.edition_rate * self.weight * (250 ^ #SMODS.find_card('j_jen_bulwark'))
	end,
	loc_vars = function(self)
		return { vars = { self.config.chips, self.config.x_chips, self.config.e_chips, self.config.ee_chips, self.config.eee_chips, self.config.mult, self.config.x_mult, self.config.e_mult, self.config.ee_mult, self.config.eee_mult } }
	end,
	calculate = function(self, card, context)
		local chips = self.config.chips
		local mult = self.config.mult
		local x_chips = self.config.x_chips
		local x_mult = self.config.x_mult
		local e_chips = self.config.e_chips
		local e_mult = self.config.e_mult
		local ee_chips = self.config.ee_chips
		local ee_mult = self.config.ee_mult
		local eee_chips = self.config.eee_chips
		local eee_mult = self.config.eee_mult
		if context.edition and context.cardarea == G.jokers and context.joker_main then
			return {
				chips = chips * math.pi,
				mult = mult * math.pi,
				x_chips = x_chips * math.pi,
				x_mult = x_mult * math.pi,
				e_chips = e_chips * math.pi,
				e_mult = e_mult * math.pi,
				ee_chips = ee_chips * math.pi,
				ee_mult = ee_mult * math.pi,
				eee_chips = eee_chips * math.pi,
				eee_mult = eee_mult * math.pi
			}
		end
		if context.cardarea == G.play and context.main_scoring then
			return {
				chips = chips * math.pi,
				mult = mult * math.pi,
				x_chips = x_chips * math.pi,
				x_mult = x_mult * math.pi,
				e_chips = e_chips * math.pi,
				e_mult = e_mult * math.pi,
				ee_chips = ee_chips * math.pi,
				ee_mult = ee_mult * math.pi,
				eee_chips = eee_chips * math.pi,
				eee_mult = eee_mult * math.pi
			}
		end
	end
}



local cs = Card.calculate_seal
function Card:calculate_seal(context)
	local tbl = cs(self, context)
	if tbl then
		if context.repetition and ((self.ability or {}).set or 'Joker') ~= 'Joker' then
			if self.edition then
				if self.edition.retriggers then
					tbl.repetitions = (tbl.repetitions or 0) + self.edition.retriggers
					tbl.message = tbl.message or localize('k_again_ex')
					tbl.card = tbl.card or self
					return {
						message = localize('k_again_ex'),
						repetitions = self.edition.retriggers,
						card = self
					}
				end
			end
		end
		return tbl
	end
end

--JOKER ATLASES
local atlases = {
	'sigil',
	'rai',
	'agares',
	'spice',
	'kosmos',
	'lambert',
	'leshy',
	'heket',
	'kallamar',
	'shamura',
	'narinder',
	'aym',
	'baal',
	'clauneck',
	'kudaai',
	'chemach',
	'haro',
	'suzaku',
	'ayanami',
	'ratau',
	'jen',
	'math',
	'koslo',
	'peppino',
	'noise',
	'poppin',
	'godsmarble',
	'pawn',
	'knight',
	'jester',
	'arachnid',
	'reign',
	'feline',
	'amalgam',
	'fateeater',
	'foundry',
	'broken',
	'wondergeist',
	'wondergeist2',
	'survivor',
	'monk',
	'hunter',
	'spearmaster',
	'artificer',
	'saint',
	'gourmand',
	'rivulet',
	'rot',
	'guilduryn',
	'hydrangea',
	'heisei',
	'soryu',
	'shikigami',
	'leviathan',
	'behemoth',
	'inferno',
	'alexandra',
	'arin',
	'kyle',
	'johnny',
	'murphy',
	'roffle',
	'luke',
	'7granddad',
	'gamingchair',
	'aster',
	'rin',
	'astrophage',
	'landa',
	'bulwark',
	'urizyth',
	'lugia',
	'vacuum',
	'nyx',
	'paragon',
	'jimbo',
	'betmma',
	'watto',
	'kori',
	'apollo',
	'hephaestus',
	'p03',
	'oxy',
	'honey',
	'inhabited',
	'cracked',
	'alice',
	'nexus',
	'swabbie',
	'pickel',
	'jeremy',
	'cheese',
	'crimbo',
	'faceless',
	'maxie',
	'charred',
	'dandy',
	'goob',
	'goob_lefthand',
	'goob_righthand',
	'boxten',
	'astro',
	'razzledazzle',
	'cosmo',
	'toodles',
	'finn',
	'connie'
}

for k, v in pairs(atlases) do
	SMODS.Atlas {
		key = 'jen' .. v,
		px = 71,
		py = 95,
		path = Jen.config.texture_pack .. '/j_jen_' .. v .. '.png'
	}
end

--MISCELLANEOUS ATLASES

SMODS.Atlas {
	key = 'jenhuge',
	px = 71,
	py = 95,
	path = Jen.config.texture_pack .. '/c_jen_huge.png'
}
SMODS.Atlas {
	key = 'jenbooster',
	px = 71,
	py = 95,
	path = Jen.config.texture_pack .. '/p_jen_boosters.png'
}
SMODS.Atlas {
	key = 'jenfuse',
	px = 71,
	py = 95,
	path = Jen.config.texture_pack .. '/c_jen_fuse.png'
}
SMODS.Atlas {
	key = 'jenuno',
	px = 71,
	py = 95,
	path = Jen.config.texture_pack .. '/c_jen_uno.png'
}
SMODS.Atlas {
	key = 'jendecks',
	px = 71,
	py = 95,
	path = Jen.config.texture_pack .. '/b_jen_decks.png'
}
SMODS.Atlas {
	key = 'jentags',
	px = 34,
	py = 34,
	path = Jen.config.texture_pack .. '/tag_jen.png'
}
SMODS.Atlas {
	key = 'jenyawetag',
	px = 71,
	py = 95,
	path = Jen.config.texture_pack .. '/c_jen_yawetag.png'
}
SMODS.Atlas {
	key = 'jennyx_c',
	px = 71,
	py = 95,
	path = Jen.config.texture_pack .. '/c_jen_nyx.png'
}
SMODS.Atlas {
	key = 'jenswabbie_c',
	px = 71,
	py = 95,
	path = Jen.config.texture_pack .. '/c_jen_swabbie.png'
}
SMODS.Atlas {
	key = 'jenartificer_c',
	px = 71,
	py = 95,
	path = Jen.config.texture_pack .. '/c_jen_artificer.png'
}
SMODS.Atlas {
	key = 'jenfateeater_c',
	px = 71,
	py = 95,
	path = Jen.config.texture_pack .. '/c_jen_fateeater.png'
}
SMODS.Atlas {
	key = 'jenfoundry_c',
	px = 71,
	py = 95,
	path = Jen.config.texture_pack .. '/c_jen_foundry.png'
}
SMODS.Atlas {
	key = 'jenbroken_c',
	px = 71,
	py = 95,
	path = Jen.config.texture_pack .. '/c_jen_broken.png'
}
SMODS.Atlas {
	key = 'jenroffle_c',
	px = 71,
	py = 95,
	path = Jen.config.texture_pack .. '/c_jen_roffle.png'
}
SMODS.Atlas {
	key = 'jengoob_c',
	px = 71,
	py = 95,
	path = Jen.config.texture_pack .. '/c_jen_goob.png'
}

SMODS.Atlas {
	key = 'jenhoxxes',
	px = 71,
	py = 95,
	path = Jen.config.texture_pack .. '/c_jen_hoxxes.png'
}

SMODS.Atlas {
	key = 'jenrtarots',
	px = 71,
	py = 95,
	path = Jen.config.texture_pack .. '/c_jen_reversetarots.png'
}

SMODS.Atlas {
	key = 'jenacc',
	px = 71,
	py = 95,
	path = Jen.config.texture_pack .. '/c_jen_acc.png'
}

SMODS.Atlas {
	key = 'jenblanks',
	px = 71,
	py = 95,
	path = Jen.config.texture_pack .. '/c_jen_blanks.png'
}

SMODS.Atlas {
	key = 'jenblinds',
	atlas_table = 'ANIMATION_ATLAS',
	frames = 21,
	px = 34,
	py = 34,
	path = Jen.config.texture_pack .. '/bl_jen_blinds.png'
}

SMODS.Atlas {
	key = 'jenepicblinds',
	atlas_table = 'ANIMATION_ATLAS',
	frames = 21,
	px = 34,
	py = 34,
	path = Jen.config.texture_pack .. '/bl_jen_epic_blinds.png'
}

SMODS.Atlas {
	key = 'jentokens',
	px = 71,
	py = 95,
	path = Jen.config.texture_pack .. '/c_jen_tokens.png'
}

SMODS.Atlas {
	key = 'jenenhance',
	px = 71,
	py = 95,
	path = Jen.config.texture_pack .. '/m_jen_enhancements.png'
}

SMODS.Atlas {
	key = 'jenomegaplanets',
	px = 71,
	py = 95,
	path = Jen.config.texture_pack .. '/c_jen_omegaplanets.png'
}

SMODS.Atlas {
	key = 'jenomegaspectrals',
	px = 71,
	py = 95,
	path = Jen.config.texture_pack .. '/c_jen_omegaspectrals.png'
}

SMODS.Atlas {
	key = 'jenomegatarots',
	px = 71,
	py = 95,
	path = Jen.config.texture_pack .. '/c_jen_omegatarots.png'
}

SMODS.Atlas {
	key = 'jenplanets',
	px = 71,
	py = 95,
	path = Jen.config.texture_pack .. '/c_jen_planets.png'
}

SMODS.Atlas {
	key = 'jenvouchers',
	px = 71,
	py = 95,
	path = Jen.config.texture_pack .. '/v_jen_vouchers.png'
}
SMODS.Atlas {
	key = 'jenbuttons',
	px = 32,
	py = 32,
	path = Jen.config.texture_pack .. '/jen_ui_buttons.png'
}

local csdr = Card.set_debuff

function Card:set_debuff(should_debuff)
	if self.ability.perishable then
		if not self.ability.perish_tally then self.ability.perish_tally = 5 end
	end
	csdr(self, should_debuff)
end

--DECKS

SMODS.Back {
	key = 'orrery',
	atlas = 'jendecks',
	pos = { x = 0, y = 0 },
	loc_txt = {
		name = 'Orrery Deck',
		text = {
			'All hands start at {X:chips,C:white}150{C:mult} X {X:red,C:white}1',
			'and are {C:cry_ascendant}equalised{} whenever their',
			'{C:chips}Chips{}, {C:mult}Mult{} or {C:planet}level {C:attention}change',
			'{C:inactive,s:0.6}T.E.F.D. excluded',
			spriter('ThreeCubed')
		}
	},
	apply = function(self)
		G.GAME.orrery = true
		Q(function()
			for k, v in pairs(G.GAME.hands) do
				v.chips = to_big(150)
				v.mult = to_big(1)
				v.level = to_big(1)
			end
			save_run()
			return true
		end)
	end
}

SMODS.Back {
	key = 'mysterious',
	atlas = 'jendecks',
	pos = { x = 1, y = 0 },
	loc_txt = {
		name = 'Mysterious Deck',
		text = {
			'{C:red}Warning : Highly unstable!',
			'Jokers, consumables, and',
			'playing cards are {C:green,E:1}randomised',
			'when they are added',
			'to your possession',
			spriter('mailingway')
		}
	},
	apply = function(self)
		G.GAME.mysterious = true
		Q(function()
			save_run()
			return true
		end)
	end
}

SMODS.Back {
	key = 'weeck',
	atlas = 'jendecks',
	pos = { x = 4, y = 1 },
	loc_txt = {
		name = 'Weeck',
		text = {
			'Start with a deck composed',
			'of a {C:dark_edition}Wee {C:attention}2',
			'of {C:attention}each suit',
			'The {C:dark_edition}Wee{} edition is',
			'{X:attention,C:white}222.22x{C:attention} more likely',
			'to appear over other editions',
			'{C:dark_edition}Wee{} scales {X:attention,C:white}3x{C:attention} faster',
			spriter('CrimboJimbo')
		}
	},
	apply = function(self)
		G.GAME.weeck = true
		Q(function()
			for k, v in pairs(G.playing_cards) do
				if v.base.id == 2 then
					v:set_edition({ jen_wee = true }, true, true)
				else
					v.area:remove_card(v)
					v:destroy()
				end
			end
			return true
		end)
		delay(1)
		Q(function()
			save_run()
			return true
		end)
	end
}

SMODS.Back {
	key = 'obsidian',
	atlas = 'jendecks',
	pos = { x = 2, y = 1 },
	loc_txt = {
		name = 'Obsidian Deck',
		text = {
			'{C:attention}Hidden{} cards {C:inactive}(ex. {C:spectral}The Soul{C:inactive})',
			'can {C:attention}appear normally{},',
			'{C:spectral}Spectral{} cards may',
			'appear in the {C:attention}shop{},',
			'{C:jen_RGB,E:1}Omega{} consumables appear',
			'{C:attention}twice{} as often',
			spriter('CrimboJimbo')
		}
	},
	config = {
		spectral_rate = 2
	},
	apply = function(self)
		G.GAME.obsidian = true
	end
}

SMODS.Back {
	key = 'tortoise',
	atlas = 'jendecks',
	pos = { x = 3, y = 1 },
	loc_txt = {
		name = 'Tortoise Deck',
		text = {
			'{C:attention}Ante increases{} are {C:attention}half{} as strong,',
			'{C:attention}Straddle{} takes {C:attention}twice as long{} to increase',
			spriter('laviolive')
		}
	},
	apply = function(self)
		G.GAME.tortoise = true
	end
}

if Jen.config.straddle.enabled then
	SMODS.Back {
		key = 'nitro',
		atlas = 'jendecks',
		pos = { x = 1, y = 1 },
		loc_txt = {
			name = 'Acceleration Deck',
			text = {
				'{C:attention}Straddle{} is enabled {C:attention}pre-endless',
				'and {C:attention}increases {X:attention,C:white}' .. number_format(Jen.config.straddle.progress_min) .. 'x{C:attention} as fast{},',
				'create an {C:tarot}Empowered Pack{} and',
				'a random {C:attention}Booster Pack{} in',
				'the {C:attention}consumable tray{} after',
				'defeating the {C:attention}Boss Blind',
				spriter('mailingway')
			}
		},
		apply = function(self)
			G.GAME.straddle_active = true
			G.GAME.nitro = true
			G.GAME.straddle = 0
			G.GAME.straddle_progress = 0
		end,
		trigger_effect = function(self, args)
			if args.context == "eval" and G.GAME.last_blind and G.GAME.last_blind.boss then
				Q(function()
					local pack = create_card('Booster', G.consumeables, nil, nil, nil, nil, 'p_cry_empowered',
						'nitro_empowered')
					if pack.gc and pack:gc().set ~= 'Booster' then
						pack:set_ability(G.P_CENTERS.p_cry_empowered, true, nil)
						pack:set_cost()
					end
					pack:add_to_deck()
					G.consumeables:emplace(pack)
					return true
				end)
				Q(function()
					local pack2 = create_card('Booster', G.consumeables, nil, nil, nil, nil, nil, 'nitro_bonus')
					if pack2.gc and pack2:gc().set ~= 'Booster' then
						pack2:set_ability(jl.rnd('nitro_bonus_equilibrium', nil, G.P_CENTER_POOLS.Booster), true, nil)
						pack2:set_cost()
					end
					pack2:add_to_deck()
					G.consumeables:emplace(pack2)
					return true
				end)
			end
		end
	}
end

--ENHANCEMENTS

SMODS.Enhancement {
	key = 'xchip',
	loc_txt = {
		name = 'Multichip Card',
		text = {
			jl.mulchips('#1#') .. ' Chips',
			'{C:cry_exotic,s:0.6,E:1}Power Card{}'
		}
	},
	config = { mod = 1.5 },
	pos = { x = 1, y = 0 },
	unlocked = true,
	discovered = true,
	atlas = 'jenenhance',
	loc_vars = function(self, info_queue, center)
		return { vars = { ((center or {}).ability or {}).mod or 1.5 } }
	end,
	calculate = function(self, card, context)
		if jl.sc(context) then
			return { xchips = self.config.mod }
		end
	end
}

SMODS.Enhancement {
	key = 'echip',
	loc_txt = {
		name = 'Powerchip Card',
		text = {
			jl.expochips('#1#') .. ' Chips',
			'{C:cry_exotic,s:0.6,E:1}Power Card{}'
		}
	},
	config = { mod = 1.09 },
	pos = { x = 2, y = 0 },
	unlocked = true,
	discovered = true,
	atlas = 'jenenhance',
	loc_vars = function(self, info_queue, center)
		return { vars = { ((center or {}).ability or {}).mod or 1.09 } }
	end,
	calculate = function(self, card, context)
		if jl.sc(context) then
			return { echips = self.config.mod }
		end
	end
}

SMODS.Enhancement {
	key = 'xmult',
	loc_txt = {
		name = 'Multimult Card',
		text = {
			jl.mulmult('#1#') .. ' Mult',
			'{C:cry_exotic,s:0.6,E:1}Power Card{}'
		}
	},
	config = { mod = 2 },
	pos = { x = 3, y = 0 },
	unlocked = true,
	discovered = true,
	atlas = 'jenenhance',
	loc_vars = function(self, info_queue, center)
		return { vars = { ((center or {}).ability or {}).mod or 2 } }
	end,
	calculate = function(self, card, context)
		if jl.sc(context) then
			return { xmult = self.config.mod }
		end
	end
}

SMODS.Enhancement {
	key = 'emult',
	loc_txt = {
		name = 'Powermult Card',
		text = {
			jl.expomult('#1#') .. ' Mult',
			'{C:cry_exotic,s:0.6,E:1}Power Card{}'
		}
	},
	config = { mod = 1.13 },
	pos = { x = 5, y = 0 },
	unlocked = true,
	discovered = true,
	atlas = 'jenenhance',
	loc_vars = function(self, info_queue, center)
		return { vars = { ((center or {}).ability or {}).mod or 1.13 } }
	end,
	calculate = function(self, card, context)
		if jl.sc(context) then
			return { emult = self.config.mod }
		end
	end
}

SMODS.Enhancement {
	key = 'power',
	loc_txt = {
		name = 'Supercharged Card',
		text = {
			jl.mulchips('#1#') .. ' Chips',
			jl.mulmult('#2#') .. ' Mult',
			jl.expochips('#3#') .. ' Chips',
			jl.expomult('#4#') .. ' Mult',
			'{C:cry_exotic,s:0.6,E:1}Power Card{}'
		}
	},
	config = { mod1 = 1.25, mod2 = 1.5, mod3 = 1.08, mod4 = 1.11 },
	pos = { x = 4, y = 0 },
	unlocked = true,
	discovered = true,
	atlas = 'jenenhance',
	loc_vars = function(self, info_queue, center)
		return { vars = { ((center or {}).ability or {}).mod1 or 1.25, ((center or {}).ability or {}).mod2 or 1.25, ((center or {}).ability or {}).mod3 or 1.08, ((center or {}).ability or {}).mod4 or 1.11 } }
	end,
	calculate = function(self, card, context)
		if jl.sc(context) then
			return {
				xchips = self.config.mod1,
				xmult = self.config.mod2,
				echips = self.config.mod3,
				emult = self.config
					.mod4
			}
		end
	end
}

SMODS.Enhancement {
	key = 'surreal',
	loc_txt = {
		name = 'Surreal Card',
		text = {
			'{C:attention}Ignores{} card selection limit',
			'{C:inactive}(e.g. can be used to play 6+ cards){}'
		}
	},
	pos = { x = 6, y = 1 },
	unlocked = true,
	discovered = true,
	atlas = 'jenenhance',
}

local function faceinplay()
	if not G.play then return 0 end
	if not G.play.cards then return 0 end
	local qty = 0
	for k, v in pairs(G.play.cards) do
		if v:is_face() then qty = qty + 1 end
	end
	return qty
end

SMODS.Enhancement {
	key = 'astro',
	loc_txt = {
		name = 'Astro Card',
		text = {
			'Creates a {C:planet}Planet{} card',
			mayoverflow,
			'{C:cry_exotic,s:0.6,E:1}Power Card{}'
		}
	},
	pos = { x = 0, y = 0 },
	unlocked = true,
	discovered = true,
	atlas = 'jenenhance',
	calculate = function(self, card, context, effect)
		if jl.sc(context) then
			Q(function()
				local card2 = create_card('Planet', G.consumeables, nil, nil, nil, nil, nil, 'astro_card')
				card2:add_to_deck()
				G.consumeables:emplace(card2)
				return true
			end, nil, nil, 'after')
		end
	end
}

SMODS.Enhancement {
	key = 'fortune',
	loc_txt = {
		name = 'Fortune Card',
		text = {
			'Creates a {C:tarot}Tarot{} card',
			mayoverflow,
			'{C:cry_exotic,s:0.6,E:1}Power Card{}'
		}
	},
	pos = { x = 6, y = 0 },
	atlas = 'jenenhance',
	unlocked = true,
	discovered = true,
	calculate = function(self, card, context, effect)
		if jl.sc(context) then
			Q(function()
				local card2 = create_card('Tarot', G.consumeables, nil, nil, nil, nil, nil, 'fortune_card')
				card2:add_to_deck()
				G.consumeables:emplace(card2)
				return true
			end, nil, nil, 'after')
		end
	end
}

SMODS.Enhancement {
	key = 'atman',
	loc_txt = {
		name = 'Atman Card',
		text = {
			'Creates a {C:spectral}Spectral{} card',
			mayoverflow,
			'{C:cry_exotic,s:0.6,E:1}Power Card{}'
		}
	},
	pos = { x = 8, y = 0 },
	atlas = 'jenenhance',
	unlocked = true,
	discovered = true,
	calculate = function(self, card, context, effect)
		if jl.sc(context) then
			Q(function()
				local card2 = create_card('Spectral', G.consumeables, nil, nil, nil, nil, nil, 'osmium_card')
				card2:add_to_deck()
				G.consumeables:emplace(card2)
				return true
			end, nil, nil, 'after')
		end
	end
}

SMODS.Enhancement {
	key = 'potassium',
	loc_txt = {
		name = 'Potassium Card',
		text = {
			'Creates a {C:dark_edition}Negative {C:attention}Gros Michel',
			'{C:red}Destroyed{} after scoring',
			'{C:cry_exotic,s:0.6,E:1}Power Card'
		}
	},
	disposable = true,
	pos = { x = 7, y = 1 },
	atlas = 'jenenhance',
	unlocked = true,
	discovered = true,
	calculate = function(self, card, context)
		if jl.sc(context) then
			Q(function()
				local k19 = create_card('Joker', G.jokers, nil, nil, nil, nil, 'j_gros_michel', 'nanner')
				k19.no_forced_edition = true
				k19:set_edition({ negative = true }, true)
				k19.no_forced_edition = nil
				k19:add_to_deck()
				G.jokers:emplace(k19)
				return true
			end)
		end
		if context.destroy_card == card and context.cardarea == G.play then
			return { remove = true }
		end
	end
}

SMODS.Enhancement {
	key = 'fizzy',
	loc_txt = {
		name = 'Fizzy Card',
		text = {
			'Creates a {C:attention}Double Tag{}',
			'{C:red}Destroyed{} after scoring',
			'{C:cry_exotic,s:0.6,E:1}Power Card{}'
		}
	},
	disposable = true,
	pos = { x = 8, y = 1 },
	atlas = 'jenenhance',
	unlocked = true,
	discovered = true,
	calculate = function(self, card, context, effect)
		if jl.sc(context) then
			G.E_MANAGER:add_event(Event({
				trigger = 'after',
				func = function()
					add_tag(Tag('tag_double'))
					return true
				end
			}))
		end
		if context.destroy_card == card and context.cardarea == G.play then
			return { remove = true }
		end
	end
}

SMODS.Enhancement {
	key = 'water',
	loc_txt = {
		name = 'Water Card',
		text = {
			'{C:green}Always scores{}'
		}
	},
	always_scores = true,
	pos = { x = 9, y = 0 },
	atlas = 'jenenhance'
}

SMODS.Enhancement {
	key = 'handy',
	loc_txt = {
		name = 'Handy Card',
		text = {
			'{C:blue}+1{} hand this round',
			'{C:red}Destroyed{} after scoring',
			'{C:cry_exotic,s:0.6,E:1}Power Card'
		}
	},
	disposable = true,
	pos = { x = 1, y = 1 },
	atlas = 'jenenhance',
	unlocked = true,
	discovered = true,
	calculate = function(self, card, context)
		if jl.sc(context) then
			ease_hands_played(1)
		end
		if context.destroy_card == card and context.cardarea == G.play then
			return { remove = true }
		end
	end
}

SMODS.Enhancement {
	key = 'tossy',
	loc_txt = {
		name = 'Tossy Card',
		text = {
			'{C:red}+1{} discard this round',
			'{C:cry_exotic,s:0.6,E:1}Power Card{}'
		}
	},
	pos = { x = 3, y = 1 },
	atlas = 'jenenhance',
	unlocked = true,
	discovered = true,
	calculate = function(self, card, context, effect)
		if jl.sc(context) then
			ease_discard(1)
		end
	end
}

SMODS.Enhancement {
	key = 'juggler',
	loc_txt = {
		name = 'Juggling Card',
		text = {
			'{C:attention}+1{} hand size this round',
			'{C:cry_exotic,s:0.6,E:1}Power Card{}'
		}
	},
	pos = { x = 2, y = 1 },
	atlas = 'jenenhance',
	unlocked = true,
	discovered = true,
	calculate = function(self, card, context, effect)
		if jl.sc(context) then
			G.hand:change_size(1)
			G.GAME.round_resets.temp_handsize = (G.GAME.round_resets.temp_handsize or 0) + 1
		end
	end
}

SMODS.Enhancement {
	key = 'cash',
	loc_txt = {
		name = 'Cash Card',
		text = {
			'{C:money}+$#1#{} when scored',
			'{C:red}Destroyed{} after scoring',
			'{C:cry_exotic,s:0.6,E:1}Power Card'
		}
	},
	config = { p_dollars = 10 },
	disposable = true,
	pos = { x = 4, y = 1 },
	atlas = 'jenenhance',
	unlocked = true,
	discovered = true,
	loc_vars = function(self, info_queue, center)
		return { vars = { ((center or {}).ability or {}).p_dollars } }
	end,
	calculate = function(self, card, context)
		if jl.sc(context) then
			G.GAME.p_dollars = (G.GAME.p_dollars or 0) + self.config.p_dollars
		end
		if context.destroy_card == card and context.cardarea == G.play then
			return { remove = true }
		end
	end
}

local handinacard = {
	[1] = { 'High Card', 'Lonely' },
	[2] = { 'Pair', 'Twin' },
	[3] = { 'Two Pair', 'Siamese' },
	[4] = { 'Three of a Kind', 'Triplet' },
	[5] = { 'Straight', 'Sequential' },
	[6] = { 'Flush', 'Symbolic' },
	[7] = { 'Full House', 'Descendant' },
	[8] = { 'Four of a Kind', 'Quadruplet' },
	[9] = { 'Straight Flush', 'Tsunami' },
	[10] = { 'Five of a Kind', 'Quintuplet' },
	[11] = { 'Flush House', 'Ascendant' },
	[12] = { 'Flush Five', 'Identity' }
}

for k, v in ipairs(handinacard) do
	SMODS.Enhancement {
		key = string.lower(v[2]),
		loc_txt = {
			name = v[2] .. ' Card',
			text = {
				'Gives the {C:chips}Chips{} & {C:mult}Mult{} of {C:attention}' .. v[1] .. '{},',
				'then is {C:red}destroyed{} after scoring is finished',
				' ',
				'{C:inactive,s:1.5}({X:chips,C:white,s:1.5}#1#{s:1.5} & {X:mult,C:white,s:1.5}#2#{C:inactive,s:1.5})',
				'{C:cry_epic,s:0.6,E:1}Hand Card{}'
			}
		},
		disposable = true,
		pos = { x = k - 1, y = 2 },
		atlas = 'jenenhance',
		unlocked = true,
		discovered = true,
		loc_vars = function(self, info_queue, center)
			local tbl = ((G.GAME or {}).hands or {})[v[1]] or {}
			return { vars = { tbl.chips or '???', tbl.mult or '???' } }
		end,
		calculate = function(self, card, context)
			if jl.sc(context) then
				local tbl = ((G.GAME or {}).hands or {})[v[1]] or {}
				if tbl and next(tbl) then
					if not card.cashed_out then
						card.cashed_out = true
					end
					return {
						chips = tbl.chips,
						mult = tbl.mult
					}
				end
			end
			if context.destroy_card == card and context.cardarea == G.play then
				return { remove = true }
			end
		end
	}
end

SMODS.Enhancement {
	key = 'exotic',
	loc_txt = {
		name = 'Exotic Card',
		text = {
			'Has {C:attention}double{} the {C:attention}combined upsides{}',
			'of {C:attention}all vanilla + {C:almanac,E:1}Almanac{} enhancements',
			'{C:red}Destroyed{} after scoring',
			'{C:inactive}(Excludes Hand Card and Super Power Card enhancements){}',
			'{C:jen_RGB,s:0.6,E:1}Super Power Card{}'
		}
	},
	config = { h_dollars = 6, p_dollars = 20, chips = 160, mult = 8, h_x_mult = 2.25, mod1 = 3.515625, mod2 = 9, mod3 = 1.2, mod4 = 1.3 },
	disposable = true,
	any_suit = true,
	always_scores = true,
	pos = { x = 0, y = 1 },
	atlas = 'jenenhance',
	unlocked = true,
	discovered = true,
	calculate = function(self, card, context, effect)
		if jl.sc(context) then
			for i = 1, 6 do
				G.E_MANAGER:add_event(Event({
					trigger = 'after',
					func = function()
						local ii = math.ceil(i / 2)
						local card2 = create_card(ii == 1 and 'Planet' or ii == 2 and 'Tarot' or 'Spectral',
							G.consumeables, nil, nil, nil, nil, nil, 'exotic_card' .. i)
						card2:add_to_deck()
						G.consumeables:emplace(card2)
						ii = nil
						return true
					end
				}))
			end
			for i = 1, 2 do
				Q(function()
					local k19 = create_card('Joker', G.jokers, nil, nil, nil, nil, 'j_gros_michel', 'nanner')
					k19.no_forced_edition = true
					k19:set_edition({ negative = true }, true)
					k19.no_forced_edition = nil
					k19:add_to_deck()
					G.jokers:emplace(k19)
					return true
				end)
			end
			ease_hands_played(2)
			ease_discard(2)
			G.hand:change_size(2)
			Q(function()
				add_tag(Tag('tag_double')); add_tag(Tag('tag_double')); return true
			end)
			G.GAME.round_resets.temp_handsize = (G.GAME.round_resets.temp_handsize or 0) + 2
			return {
				xchips = self.config.mod1,
				xmult = self.config.mod2,
				echips = self.config.mod3,
				emult = self.config
					.mod4
			}
		end
		if context.destroy_card == card and context.cardarea == G.play then
			return { remove = true }
		end
	end
}


-- Load jokers from separate file
local jokers_path = SMODS.current_mod.path .. 'Jen_Jokers.lua'
assert(loadfile(jokers_path))()

SMODS.Consumable {
	key = 'sizeoflife',
	loc_txt = {
		name = 'The Size of Life',
		text = {
			'Apply {C:dark_edition}Wee{} on',
			'up to {C:attention}#1#{} selected card(s)',
			spriter('mailingway')
		}
	},
	config = { max_highlighted = 1 },
	set = 'Tarot',
	pos = { x = 2, y = 0 },
	cost = 3,
	unlocked = true,
	discovered = true,
	atlas = 'jenacc',
	loc_vars = function(self, info_queue, center)
		return { vars = { ((center or {}).ability or {}).max_highlighted or 1 } }
	end,
	can_use = function(self, card)
		return jl.canuse() and #G.hand.highlighted <= (card.ability.max_highlighted + (card.area == G.hand and 1 or 0)) and
			#G.hand.highlighted > (card.area == G.hand and 1 or 0)
	end,
	use = function(self, card, area, copier)
		if #G.hand.highlighted > 0 then
			for k, v in pairs(G.hand.highlighted) do
				v:set_edition({ jen_wee = true })
				Q(function()
					G.hand:remove_from_highlighted(v)
					return true
				end)
			end
		end
	end
}


local jokerinatarot_blurbs = {
	"Hey! Pick me!",
	"You wouldn't say no to a free negative me, would you?",
	"Sometimes, an extra four mult goes a long way!",
	"I won't take up space, I promise!",
	"Don't ask how I ended up in a tarot!",
	"Hee-hee, hoo-hoo!",
	"Who knew even fortunes could be a circus act?",
	"Looks like the joke is on the crystal globe!",
	"It's a little cramped in this tarot...!",
	"Ouch, I think the joke is on me!",
	"Looks like the joke is on you!",
	"I'm not just a clown; I'm the whole circus!",
	"Seems a little suspicious for a jolly old fella like me to be in this card...",
	"I can't help if I'm still in this silly old card, break me out!",
	"Let me tell you, you'd love the show going on in this tarot!",
	"I'd give you more tickets to JimCon, but I'm fresh out.",
	"I've heard of a round buffoon that lives in a pretty funky town...",
	"I can't give four mult if I'm still in this card!",
	"I'm rooting for you! Even if it means I'll never get out of this card...",
	"Who knew I'd have access to a great show? That show being you!",
	"The stakes are only gonna rise here!",
	"Juggling is one of my favourite passtimes!",
	"I wonder what's the deal with pairs?",
	"You don't need to understand math to enjoy watching the digits climb!",
	"You should meet my friend Joseph; he's stuck in a Planet card!",
	"M!",
	"Hotfix!"
}

local jokerinaplanet_blurbs = {
	"Hey, can you hear me? You gotta get me outta here.",
	"I don't trust Jimbo...",
	"This card is making me feel breathless. Literally!",
	"How did I even get here?",
	"I don't even like astronomy.",
	"John, wherever you are... HEEEEEEEEEELP!!!",
	"Get me outta here, man!!",
	"Why must I be in this dang card?",
	"I guess I could help you...",
	"Have you been grinding for that one-in-a-thousand chance for Jimbo?",
	"I need some Joker-Cola...",
	"Have you seen John? He's my friend, and I heard he's got himself into a Tarot card...",
	"M... I guess?",
	"Hotfix... I guess?"
}

SMODS.Consumable {
	key = 'jokerinatarot',
	loc_txt = {
		name = 'Joker-in-a-Tarot',
		text = {
			'Create a {C:dark_edition}Negative {C:attention}default Joker',
			'{C:green}0.1% chance{} to create {C:jen_RGB,E:1,s:1.5}Jimbo{} instead',
			"{C:inactive,E:1}#1#{}"
		}
	},
	config = {},
	set = 'Tarot',
	pos = { x = 0, y = 1 },
	cost = 3,
	unlocked = true,
	discovered = true,
	atlas = 'jenacc',
	loc_vars = function(self, info_queue, center)
		return { vars = { jokerinatarot_blurbs[math.random(#jokerinatarot_blurbs)] } }
	end,
	can_use = function(self, card)
		return jl.canuse()
	end,
	use = function(self, card, area, copier)
		if jl.chance('jokerinatarot_secret', 1000, true) then
			local card2 = create_card('Joker', G.jokers, nil, nil, nil, nil, 'j_jen_jimbo', 'jokerfromatarot')
			G.jokers:emplace(card2)
			play_sound_q('jen_omegacard', 1, 0.75)
			card2:add_to_deck()
			jl.a('Hee-hee, hoo-hoo!!', G.SETTINGS.GAMESPEED, 1, G.C.DARK_EDITION)
			jl.rd(1)
		else
			local card2 = create_card('Joker', G.jokers, nil, nil, nil, nil, 'j_joker', 'jokerfromatarot')
			card2.no_forced_edition = true
			card2:set_edition({ negative = true }, true)
			card2.no_forced_edition = nil
			card2.base_cost = 1
			card2.extra_cost = 0
			card2.cost = 1
			card2.sell_cost = 1
			card2.sell_cost_label = card2.facing == 'back' and '?' or card2.sell_cost
			card2:add_to_deck()
			G.jokers:emplace(card2)
		end
	end,
	bulk_use = function(self, card, area, copier, number)
		for i = 1, number do
			if jl.chance('jokerinatarot_secret', 1000, true) then
				local card2 = create_card('Joker', G.jokers, nil, nil, nil, nil, 'j_jen_jimbo', 'jokerfromatarot')
				G.jokers:emplace(card2)
				play_sound_q('jen_omegacard', 1, 0.75)
				card2:add_to_deck()
				jl.a('Hee-hee, hoo-hoo!!', G.SETTINGS.GAMESPEED, 1, G.C.DARK_EDITION)
				jl.rd(1)
			else
				local card2 = create_card('Joker', G.jokers, nil, nil, nil, nil, 'j_joker', 'jokerfromatarot')
				card2.no_forced_edition = true
				card2:set_edition({ negative = true }, true)
				card2.no_forced_edition = nil
				card2.base_cost = 1
				card2.extra_cost = 0
				card2.cost = 1
				card2.sell_cost = 1
				card2.sell_cost_label = card2.facing == 'back' and '?' or card2.sell_cost
				card2:add_to_deck()
				G.jokers:emplace(card2)
			end
		end
	end
}

SMODS.Consumable {
	key = 'jokerinaplanet',
	loc_txt = {
		name = 'Joker-in-a-Planet',
		text = {
			"For each {C:attention}default Joker{}, {C:planet}level up",
			'a {C:attention}random discovered poker hand{} by {C:attention}1',
			'plus {C:attention}1{} for each {C:attention}other default Joker{} that came before it',
			'{C:jen_RGB,E:1,s:1.5}Jimbo{} levels up by {X:planet,C:dark_edition}^1.13{} instead',
			"{C:inactive,E:1}#1#{}"
		}
	},
	ignore_allplanets = true,
	set = 'Planet',
	pos = { x = 1, y = 1 },
	cost = 3,
	unlocked = true,
	discovered = true,
	atlas = 'jenacc',
	in_pool = function() return #SMODS.find_card('j_joker') > 0 end,
	loc_vars = function(self, info_queue, center)
		return { vars = { jokerinaplanet_blurbs[math.random(#jokerinaplanet_blurbs)] } }
	end,
	can_use = function(self, card)
		return jl.canuse()
	end,
	use = function(self, card, area, copier)
		local hand = 'n/a'
		local upgrades = 0
		if #SMODS.find_card('j_joker') + #SMODS.find_card('j_jen_jimbo') > 0 then
			for k, v in ipairs(SMODS.find_card('j_joker')) do
				hand = jl.rndhand()
				jl.th(hand)
				Q(function()
					v:juice_up(1, 0.5)
					return true
				end)
				upgrades = upgrades + 1
				level_up_hand(card, hand, nil, upgrades)
			end
			for k, v in ipairs(SMODS.find_card('j_jen_jimbo')) do
				hand = jl.rndhand()
				local lvs = math.ceil(G.GAME.hands[hand].level ^ 1.13) - G.GAME.hands[hand].level
				jl.th(hand)
				Q(function()
					v:juice_up(1, 0.5)
					return true
				end)
				level_up_hand(card, hand, nil, lvs)
			end
			jl.ch()
		else
			jl.a('No default jokers!', G.SETTINGS.GAMESPEED, 0.65, G.C.RED, 'timpani')
			jl.rd(1)
		end
	end,
	bulk_use = function(self, card, area, copier, number)
		local hand = 'n/a'
		local upgrades = 0
		if #SMODS.find_card('j_joker') + #SMODS.find_card('j_jen_jimbo') > 0 then
			for i = 1, number do
				upgrades = 0
				for k, v in ipairs(SMODS.find_card('j_joker')) do
					hand = jl.rndhand()
					jl.th(hand)
					Q(function()
						v:juice_up(1, 0.5)
						return true
					end)
					upgrades = upgrades + 1
					level_up_hand(card, hand, nil, upgrades)
				end
				for k, v in ipairs(SMODS.find_card('j_jen_jimbo')) do
					hand = jl.rndhand()
					local lvs = math.ceil(G.GAME.hands[hand].level ^ 1.13) - G.GAME.hands[hand].level
					jl.th(hand)
					Q(function()
						v:juice_up(1, 0.5)
						return true
					end)
					level_up_hand(card, hand, nil, lvs)
				end
			end
			jl.ch()
		else
			jl.a('No default jokers!', G.SETTINGS.GAMESPEED, 0.65, G.C.RED, 'timpani')
			jl.rd(1)
		end
	end
}

SMODS.Consumable {
	key = 'moon',
	loc_txt = {
		name = 'Moon',
		text = {
			'Creates up to {C:attention}#1#',
			'random {C:attention}consumable(s)',
			'{C:inactive}(Copies edition of this card if it has one)',
			mayoverflow,
			spriter('mailingway')
		}
	},
	config = { extra = { extraconsumables = 1 } },
	set = 'Planet',
	set_card_type_badge = natsat,
	pos = { x = 3, y = 2 },
	cost = 3,
	jumbo_mod = 3,
	aurinko = true,
	unlocked = true,
	discovered = true,
	atlas = 'jenacc',
	loc_vars = function(self, info_queue, center)
		return { vars = { math.ceil((((center or {}).ability or {}).extra or {}).extraconsumables or 1) } }
	end,
	can_use = function(self, card)
		return jl.canuse()
	end,
	use = function(self, card, area, copier)
		if not card.already_used_once then
			card.already_used_once = true
			for i = 1, math.ceil(card.ability.extra.extraconsumables) do
				Q(function()
					play_sound('jen_draw')
					local card2 = create_card('Consumeables', G.consumeables, nil, nil, nil, nil, nil, 'moon_planet')
					if card.edition then
						card2:set_edition(card.edition, true)
					end
					card2:add_to_deck()
					G.consumeables:emplace(card2)
					card:juice_up(0.3, 0.5)
					return true
				end, 0.4, nil, 'after')
			end
			Q(function()
				Q(function()
					if card then card.already_used_once = nil end
					return true
				end)
				return true
			end)
			delay(0.6)
		end
	end,
	bulk_use = function(self, card, area, copier, number)
		if not card.already_used_once then
			local quota = math.ceil(card.ability.extra.extraconsumables) * number
			card.already_used_once = true
			if quota > 20 then
				for i = 1, quota do
					local card2 = create_card('Consumeables', G.consumeables, nil, nil, nil, nil, nil, 'moon_planet')
					if card.edition then
						card2:set_edition(card.edition, true)
					end
					card2:add_to_deck()
					G.consumeables:emplace(card2)
					card:juice_up(0.3, 0.5)
				end
			else
				for i = 1, quota do
					Q(function()
						play_sound('jen_draw')
						local card2 = create_card('Consumeables', G.consumeables, nil, nil, nil, nil, nil, 'moon_planet')
						if card.edition then
							card2:set_edition(card.edition, true)
						end
						card2:add_to_deck()
						G.consumeables:emplace(card2)
						card:juice_up(0.3, 0.5)
						return true
					end, 0.4, nil, 'after')
				end
			end
			Q(function()
				Q(function()
					if card then card.already_used_once = nil end
					return true
				end)
				return true
			end)
			delay(0.6)
		end
	end
}

SMODS.Consumable {
	key = 'spacestation',
	loc_txt = {
		name = 'Space Station',
		text = {
			'Upgrade your {C:attention}most played poker hand',
			'by {C:attention}#1#{} level(s)',
			'{C:inactive}(#2#)',
			spriter('mailingway')
		}
	},
	config = { extra = { levels = 1 } },
	jumbo_mod = 3,
	set = 'Planet',
	set_card_type_badge = spacecraft,
	pos = { x = 4, y = 2 },
	cost = 3,
	ayanami = true,
	aurinko = true,
	unlocked = true,
	discovered = true,
	atlas = 'jenacc',
	loc_vars = function(self, info_queue, center)
		return { vars = { (((center or {}).ability or {}).extra or {}).levels or 1, localize(jl.favhand(), 'poker_hands') } }
	end,
	can_use = function(self, card)
		return jl.canuse()
	end,
	use = function(self, card, area, copier)
		local hand = jl.favhand()
		card:do_jen_astronomy(hand)
		jl.th(hand)
		level_up_hand(card, hand, nil, card.ability.extra.levels)
		jl.ch()
	end,
	bulk_use = function(self, card, area, copier, number)
		local hand = jl.favhand()
		card:do_jen_astronomy(hand, number)
		jl.th(hand)
		level_up_hand(card, hand, nil, card.ability.extra.levels * number)
		jl.ch()
	end
}

SMODS.Consumable {
	key = 'dysnomia',
	loc_txt = {
		name = 'Dysnomia',
		text = {
			'{C:green}Randomly{} shifts the level of',
			'{C:attention}all poker hands{} by',
			'{C:red}#1#{} to {C:attention}#2#{} level(s)',
			spriter('mailingway')
		}
	},
	config = { extra = { down = -1, up = 2 } },
	set = 'Planet',
	set_card_type_badge = natsat,
	pos = { x = 5, y = 2 },
	cost = 3,
	jumbo_mod = 3,
	aurinko = true,
	unlocked = true,
	discovered = true,
	atlas = 'jenacc',
	loc_vars = function(self, info_queue, center)
		return { vars = { math.floor((((center or {}).ability or {}).extra or {}).down or -1), math.ceil((((center or {}).ability or {}).extra or {}).up or 2) } }
	end,
	can_use = function(self, card)
		return jl.canuse()
	end,
	use = function(self, card, area, copier)
		if card.ability.cry_rigged then
			Q(function()
				play_sound('gong', 0.94, 0.3)
				play_sound('gong', 0.94 * 1.5, 0.2)
				play_sound('tarot1', 1.5)
				return true
			end)
			jl.a('Rigged!', G.SETTINGS.GAMESPEED / 2, 1.4, G.C.SET.Code)
			jl.rd(.5)
			lvupallhands(math.ceil(card.ability.extra.up), card)
		else
			jl.th('all')
			Q(function()
				play_sound("tarot1")
				card:juice_up(0.8, 0.5)
				G.TAROT_INTERRUPT_PULSE = true
				return true
			end, 0.2, nil, 'after')
			update_hand_text({ delay = 0 }, { mult = "?", notifcol = G.C.JOKER_GREY, StatusText = true })
			Q(function()
				play_sound("tarot1")
				card:juice_up(0.8, 0.5)
				return true
			end, 0.9, nil, 'after')
			update_hand_text({ delay = 0 }, { chips = "?", notifcol = G.C.JOKER_GREY, StatusText = true })
			Q(function()
				play_sound("tarot1")
				card:juice_up(0.8, 0.5)
				G.TAROT_INTERRUPT_PULSE = nil
				return true
			end, 0.9, nil, 'after')
			update_hand_text({ sound = "button", volume = 0.7, pitch = 0.9, delay = 0 },
				{ level = card.ability.extra.down .. '~+' .. card.ability.extra.up })
			delay(1.3)
			for _, hand in ipairs(G.handlist) do
				local shift = pseudorandom('dysnomia', math.floor(card.ability.extra.down),
					math.ceil(card.ability.extra.up))
				if shift ~= 0 then
					level_up_hand(card, hand, true, shift)
				end
				jl.th(hand)
			end
			jl.ch()
		end
	end,
	bulk_use = function(self, card, area, copier, number)
		if card.ability.cry_rigged then
			Q(function()
				play_sound('gong', 0.94, 0.3)
				play_sound('gong', 0.94 * 1.5, 0.2)
				play_sound('tarot1', 1.5)
				return true
			end)
			jl.a('Rigged!', G.SETTINGS.GAMESPEED / 2, 1.4, G.C.SET.Code)
			jl.rd(.5)
			lvupallhands(math.ceil(card.ability.extra.up) * number, card)
		else
			local hands = {}
			for i = 1, number do
				for _, hand in ipairs(G.handlist) do
					hands[hand] = (hands[hand] or 0) +
						pseudorandom('dysnomia', math.floor(card.ability.extra.down), math.ceil(card.ability.extra.up))
				end
			end
			jl.th('all')
			Q(function()
				play_sound("tarot1")
				card:juice_up(0.8, 0.5)
				G.TAROT_INTERRUPT_PULSE = true
				return true
			end, 0.2, nil, 'after')
			update_hand_text({ delay = 0 }, { mult = "?", notifcol = G.C.JOKER_GREY, StatusText = true })
			Q(function()
				play_sound("tarot1")
				card:juice_up(0.8, 0.5)
				return true
			end, 0.9, nil, 'after')
			update_hand_text({ delay = 0 }, { chips = "?", notifcol = G.C.JOKER_GREY, StatusText = true })
			Q(function()
				play_sound("tarot1")
				card:juice_up(0.8, 0.5)
				G.TAROT_INTERRUPT_PULSE = nil
				return true
			end, 0.9, nil, 'after')
			update_hand_text({ sound = "button", volume = 0.7, pitch = 0.9, delay = 0 },
				{ level = card.ability.extra.down * number .. '~+' .. card.ability.extra.up * number })
			delay(1.3)
			for hand, lv in pairs(hands) do
				if lv ~= 0 then
					level_up_hand(card, hand, true, lv)
				end
				jl.th(hand)
			end
			jl.ch()
		end
	end
}

SMODS.Consumable {
	key = 'asteroid',
	loc_txt = {
		name = 'Asteroid',
		text = {
			'{C:planet}Level up{} all {C:purple}poker hands',
			'by {C:attention}#1#{}, plus another {C:attention}#1#',
			'for each {C:spectral}Spectral{} card used this run',
			'{C:inactive}(Currently #2#)',
			'{C:dark_edition,s:0.7,E:2}Art by : abreaker'
		}
	},
	config = { extra = { levels = 0.15 } },
	jumbo_mod = 3,
	set = 'Planet',
	pos = { x = 0, y = 0 },
	cost = 3,
	aurinko = true,
	unlocked = true,
	discovered = true,
	atlas = 'jenplanets',
	loc_vars = function(self, info_queue, center)
		local lv = (((center or {}).ability or {}).extra or {}).levels or 0.15
		return { vars = { lv, lv * (jl.ctu('spectral') + 1) } }
	end,
	can_use = function(self, card)
		return jl.canuse()
	end,
	use = function(self, card, area, copier)
		card:blackhole(card.ability.extra.levels * (jl.ctu('spectral') + 1))
	end,
	bulk_use = function(self, card, area, copier, number)
		card:blackhole(card.ability.extra.levels * (jl.ctu('spectral') + 1) * number)
	end
}

SMODS.Consumable {
	key = 'voy1',
	loc_txt = {
		name = 'Voyager 1',
		text = {
			'{C:planet}Level up{} all {C:purple}poker hands',
			'by {C:attention}#1#{}, plus another {C:attention}#1#',
			'for each {C:planet}Planet{} card used this run',
			'{C:inactive}(Currently #2#)',
			'{C:dark_edition,s:0.7,E:2}Art by : ThreeCubed'
		}
	},
	config = { extra = { levels = 0.05 } },
	jumbo_mod = 3,
	set_card_type_badge = spacecraft,
	set = 'Planet',
	pos = { x = 1, y = 0 },
	cost = 3,
	aurinko = true,
	unlocked = true,
	discovered = true,
	atlas = 'jenplanets',
	loc_vars = function(self, info_queue, center)
		local lv = (((center or {}).ability or {}).extra or {}).levels or 0.05
		return { vars = { lv, lv * (jl.ctu('planet') + 1) } }
	end,
	can_use = function(self, card)
		return jl.canuse()
	end,
	use = function(self, card, area, copier)
		card:blackhole(card.ability.extra.levels * jl.ctu('planet'))
	end,
	bulk_use = function(self, card, area, copier, number)
		card:blackhole(card.ability.extra.levels * jl.ctu('planet') * number)
	end
}

SMODS.Consumable {
	key = 'nebula',
	loc_txt = {
		name = 'Nebula',
		text = {
			'{C:planet}Level up{} all {C:purple}poker hands',
			'by {C:attention}#1#{}, plus another {C:attention}#1#',
			'for each {C:tarot}Tarot{} card used this run',
			'{C:inactive}(Currently #2#)',
			'{C:dark_edition,s:0.7,E:2}Art by : hexatheboi'
		}
	},
	config = { extra = { levels = 0.1 } },
	jumbo_mod = 3,
	set_card_type_badge = stardust,
	set = 'Planet',
	pos = { x = 2, y = 0 },
	cost = 3,
	aurinko = true,
	unlocked = true,
	discovered = true,
	atlas = 'jenplanets',
	loc_vars = function(self, info_queue, center)
		local lv = (((center or {}).ability or {}).extra or {}).levels or 0.1
		return { vars = { lv, lv * (jl.ctu('tarot') + 1) } }
	end,
	can_use = function(self, card)
		return jl.canuse()
	end,
	use = function(self, card, area, copier)
		card:blackhole(card.ability.extra.levels * (jl.ctu('tarot') + 1))
	end,
	bulk_use = function(self, card, area, copier, number)
		card:blackhole(card.ability.extra.levels * (jl.ctu('tarot') + 1) * number)
	end
}

SMODS.Consumable {
	key = 'deimos',
	loc_txt = {
		name = 'Deimos',
		text = {
			'Take {C:attention}all but one{} levels from',
			'all {C:purple}poker hands{}, then',
			'{C:attention}equally redistribute{} taken levels',
			'across all {C:attention}discovered {C:purple}poker hands',
			'{C:dark_edition,s:0.7,E:2}Art by : smg9000'
		}
	},
	ignore_allplanets = true,
	set = 'Planet',
	pos = { x = 0, y = 1 },
	cost = 5,
	unlocked = true,
	discovered = true,
	atlas = 'jenplanets',
	can_use = function(self, card)
		return jl.canuse()
	end,
	use = function(self, card, area, copier)
		local HANDS = {}
		local numhands = 0
		local levels = 0
		for k, v in pairs(G.GAME.hands) do
			if v.visible then
				HANDS[k] = true
				numhands = numhands + 1
			end
			if to_big(v.level) > to_big(1) then
				levels = levels + math.max(0, v.level - 1)
				level_up_hand(nil, k, true, -v.level + 1, true, true)
			end
		end
		jl.th('all')
		delay(1)
		levels = jl.round(levels / numhands, 2)
		Q(function()
			play_sound('gong', 0.94, 0.3)
			play_sound('gong', 0.94 * 1.5, 0.2)
			play_sound('tarot1', 1.5)
			card:juice_up(1, 0.5)
			return true
		end)
		jl.h(localize('k_all_hands'), '=', '=', '=' .. number_format(levels + 1), true)
		delay(1)
		for k, v in pairs(HANDS) do
			level_up_hand(nil, k, true, levels, true, true)
		end
		jl.ch()
	end,
	bulk_use = function(self, card, area, copier, number)
		local HANDS = {}
		local numhands = 0
		local levels = 0
		for k, v in pairs(G.GAME.hands) do
			if v.visible then
				HANDS[k] = true
				numhands = numhands + 1
			end
			if to_big(v.level) > to_big(1) then
				levels = levels + math.max(0, v.level - 1)
				level_up_hand(nil, k, true, -v.level + 1, true, true)
			end
		end
		jl.th('all')
		delay(1)
		levels = jl.round(levels / numhands, 2)
		Q(function()
			play_sound('gong', 0.94, 0.3)
			play_sound('gong', 0.94 * 1.5, 0.2)
			play_sound('tarot1', 1.5)
			card:juice_up(1, 0.5)
			return true
		end)
		jl.h(localize('k_all_hands'), '=', '=', '=' .. number_format(levels + 1), true)
		delay(1)
		for k, v in pairs(HANDS) do
			level_up_hand(nil, k, true, levels, true, true)
		end
		jl.ch()
	end
}

SMODS.Consumable {
	key = 'phobos',
	loc_txt = {
		name = 'Phobos',
		text = {
			'Take {C:attention}#1# level(s){} from your',
			'{C:attention}most-leveled poker hand(s)',
			'and {C:attention}add three times{} the amount taken',
			'to your {C:attention}most played hand',
			'{C:inactive}(#2#)',
			'{C:inactive}(Can target itself)',
			'{C:dark_edition,s:0.7,E:2}Art by : Basilloon'
		}
	},
	ayanami = true,
	jumbo_mod = 3,
	config = { level_mod = 1 },
	set = 'Planet',
	pos = { x = 1, y = 1 },
	cost = 5,
	unlocked = true,
	discovered = true,
	ayanami = true,
	atlas = 'jenplanets',
	can_use = function(self, card)
		return jl.canuse()
	end,
	loc_vars = function(self, info_queue, center)
		return { vars = { ((center or {}).ability or {}).level_mod or 1, localize(jl.favhand(), 'poker_hands') } }
	end,
	use = function(self, card, area, copier)
		local hands = {}
		local max_level = 0
		local levels = 0
		for k, v in pairs(G.GAME.hands) do
			if to_big(v.level) > to_big(max_level) then
				hands = { [k] = true }
				max_level = v.level
			elseif to_big(v.level) == to_big(max_level) then
				hands[k] = true
			end
		end
		for k, v in pairs(hands) do
			levels = levels + card.ability.level_mod
			jl.th(k)
			level_up_hand(card, k, false, -card.ability.level_mod)
		end
		local fav = jl.favhand()
		card:do_jen_astronomy(fav, levels * 3)
		jl.th(fav)
		level_up_hand(card, fav, false, levels * 3)
		jl.ch()
	end,
	bulk_use = function(self, card, area, copier, number)
		local current_levels = {}
		local hands = {}
		local fav = jl.favhand()
		local max_level = 0
		local levels = 0
		for k, v in pairs(G.GAME.hands) do
			current_levels[k] = v.level
		end
		for i = 1, number do
			hands = {}
			levels = 0
			for k, v in pairs(G.GAME.hands) do
				if current_levels[k] > to_big(max_level) then
					hands = { [k] = true }
					max_level = v.level
				elseif current_levels[k] == to_big(max_level) then
					hands[k] = true
				end
			end
			for k, v in pairs(hands) do
				levels = levels + card.ability.level_mod
				current_levels[k] = current_levels[k] - card.ability.level_mod
			end
			current_levels[fav] = current_levels[fav] + (levels * 3)
		end
		for k, v in pairs(current_levels) do
			if v > G.GAME.hands[k].level then
				card:do_jen_astronomy(fav, v - G.GAME.hands[k].level)
			end
			if v ~= G.GAME.hands[k].level then
				jl.th(k)
				level_up_hand(card, k, false, v - G.GAME.hands[k].level)
			end
		end
		jl.ch()
	end
}

SMODS.Consumable {
	key = 'pallas',
	loc_txt = {
		name = '2 Pallas',
		text = {
			'Level up all {C:purple}poker hands',
			'by {C:attention}one-fifth{} of a level',
			'{C:dark_edition,s:0.7,E:2}Art by : ThreeCubed'
		}
	},
	set = 'Planet',
	pos = { x = 2, y = 1 },
	cost = 4,
	unlocked = true,
	discovered = true,
	atlas = 'jenplanets',
	can_use = function(self, card)
		return jl.canuse()
	end,
	use = function(self, card, area, copier)
		card:blackhole(0.2)
	end,
	bulk_use = function(self, card, area, copier, number)
		card:blackhole(0.2 * number)
	end
}

SMODS.Consumable {
	key = 'vesta',
	loc_txt = {
		name = '4 Vesta',
		text = {
			'{C:red}Level down{} your {C:attention}most played poker hand',
			'by {C:attention}#1#{}, but {C:planet}level up',
			'all {C:attention}other {C:purple}poker hands',
			'by {C:attention}half of that amount',
			'{C:inactive}(#2#)',
			'{C:dark_edition,s:0.7,E:2}Art by : ThreeCubed'
		}
	},
	jumbo_mod = 3,
	config = { level_mod = 2 },
	set = 'Planet',
	pos = { x = 0, y = 2 },
	cost = 6,
	unlocked = true,
	discovered = true,
	atlas = 'jenplanets',
	loc_vars = function(self, info_queue, center)
		return { vars = { ((center or {}).ability or {}).level_mod or 1, localize(jl.favhand(), 'poker_hands') } }
	end,
	can_use = function(self, card)
		return jl.canuse()
	end,
	use = function(self, card, area, copier)
		local fav = jl.favhand()
		local mod = card.ability.level_mod
		jl.th(fav)
		level_up_hand(card, fav, nil, -mod)
		delay(0.5)
		jl.h('Other Hands', '...', '...', '')
		Q(function()
			play_sound("tarot1")
			card:juice_up(0.8, 0.5)
			G.TAROT_INTERRUPT_PULSE = true
			return true
		end, 0.2, nil, 'after')
		update_hand_text({ delay = 0 }, { mult = "+", StatusText = true })
		Q(function()
			play_sound("tarot1")
			card:juice_up(0.8, 0.5)
			return true
		end, 0.9, nil, 'after')
		update_hand_text({ delay = 0 }, { chips = "+", StatusText = true })
		Q(function()
			play_sound("tarot1")
			card:juice_up(0.8, 0.5)
			G.TAROT_INTERRUPT_PULSE = nil
			return true
		end, 0.9, nil, 'after')
		update_hand_text({ sound = "button", volume = 0.7, pitch = 0.9, delay = 0 }, { level = "+" .. (mod / 2) })
		delay(1.3)
		for k, v in pairs(G.GAME.hands) do
			if k ~= fav then
				level_up_hand(card, k, true, mod / 2)
			end
		end
		jl.ch()
	end,
	bulk_use = function(self, card, area, copier, number)
		local fav = jl.favhand()
		local mod = card.ability.level_mod * number
		jl.th(fav)
		level_up_hand(card, fav, nil, -mod)
		delay(0.5)
		jl.h('Other Hands', '...', '...', '')
		Q(function()
			play_sound("tarot1")
			card:juice_up(0.8, 0.5)
			G.TAROT_INTERRUPT_PULSE = true
			return true
		end, 0.2, nil, 'after')
		update_hand_text({ delay = 0 }, { mult = "+", StatusText = true })
		Q(function()
			play_sound("tarot1")
			card:juice_up(0.8, 0.5)
			return true
		end, 0.9, nil, 'after')
		update_hand_text({ delay = 0 }, { chips = "+", StatusText = true })
		Q(function()
			play_sound("tarot1")
			card:juice_up(0.8, 0.5)
			G.TAROT_INTERRUPT_PULSE = nil
			return true
		end, 0.9, nil, 'after')
		update_hand_text({ sound = "button", volume = 0.7, pitch = 0.9, delay = 0 }, { level = "+" .. (mod / 2) })
		delay(1.3)
		for k, v in pairs(G.GAME.hands) do
			level_up_hand(card, k, true, mod / 2)
		end
		jl.ch()
	end
}

SMODS.Consumable {
	key = 'hygiea',
	set = 'Planet',
	loc_txt = {
		name = '10 Hygiea',
		text = {
			'Create between {C:attention}#1#{} to {C:attention}#2#',
			'random {C:attention}playing ("CCD") {C:planet}Planet {C:attention}cards',
			'and shuffle them into your deck',
			'{C:inactive}(Suit and rank will be random, most editions will carry over)',
			'{C:dark_edition,s:0.7,E:2}Art by : ThreeCubed'
		}
	},
	ignore_allplanets = true,
	config = { min_planets = 2, max_planets = 4 },
	pos = { x = 1, y = 2 },
	cost = 4,
	jumbo_mod = 3,
	unlocked = true,
	discovered = true,
	atlas = 'jenplanets',
	loc_vars = function(self, info_queue, center)
		return { vars = { math.ceil(((center or {}).ability or {}).min_planets or 1), math.ceil(((center or {}).ability or {}).max_planets or 3) } }
	end,
	can_use = function(self, card)
		return jl.canuse()
	end,
	use = function(self, card, area, copier)
		local cards = {}
		local objects = {}
		local ccdamnt = pseudorandom('hygiearandom', math.ceil(card.ability.min_planets),
			math.ceil(card.ability.max_planets))
		for i = 1, ccdamnt do
			cards[i] = true
			local new = create_playing_card(nil, G.play, nil, i ~= 1, { G.C.SECONDARY_SET.Planet })
			if card.edition and not card.edition.negative and not card.edition.jen_jumbo and not card.edition.cry_double_sided then
				new:set_edition(card.edition)
			end
			table.insert(objects, new)
		end
		jl.rd(0.5)
		for k, v in ipairs(objects) do
			Q(function()
				play_sound('card1')
				v:juice_up(0.3, 0.3)
				v:flip()
				return true
			end, 0.2, 'REAL')
		end
		jl.rd(0.5)
		for k, v in ipairs(objects) do
			Q(function()
				play_sound('card1', 0.9)
				v:set_ability(jl.rnd('jen_hygiea', nil, G.P_CENTER_POOLS.Planet), true, nil)
				v:juice_up(0.3, 0.3)
				v:flip()
				return true
			end, 0.2, 'REAL')
		end
		jl.rd(1.5)
		for k, v in ipairs(objects) do
			Q(function()
				play_sound('card1', 1.1)
				v:add_to_deck()
				G.play:remove_card(v)
				G.deck:emplace(v)
				return true
			end, 0.2, 'REAL')
		end
		Q(function()
			if next(cards) then
				playing_card_joker_effects(cards)
			end
			return true
		end)
	end,
	bulk_use = function(self, card, area, copier, number)
		local cards = {}
		local objects = {}
		local ccdamnt = pseudorandom('hygiearandom', math.ceil(card.ability.min_planets) * number,
			math.ceil(card.ability.max_planets) * number)
		for i = 1, ccdamnt do
			cards[i] = true
			local new = create_playing_card(nil, G.play, nil, i ~= 1, { G.C.SECONDARY_SET.Planet })
			if card.edition and not card.edition.negative and not card.edition.jen_jumbo and not card.edition.cry_double_sided then
				new:set_edition(card.edition)
			end
			table.insert(objects, new)
		end
		jl.rd(0.5 / number)
		for k, v in ipairs(objects) do
			Q(function()
				play_sound('card1')
				v:juice_up(0.3, 0.3)
				v:flip()
				return true
			end, 0.2 / number, 'REAL')
		end
		jl.rd(0.5 / number)
		for k, v in ipairs(objects) do
			Q(function()
				play_sound('card1', 0.9)
				v:set_ability(jl.rnd('jen_hygiea', nil, G.P_CENTER_POOLS.Planet), true, nil)
				v:juice_up(0.3, 0.3)
				v:flip()
				return true
			end, 0.2 / number, 'REAL')
		end
		jl.rd(1.5 / number)
		for k, v in ipairs(objects) do
			Q(function()
				play_sound('card1', 1.1)
				v:add_to_deck()
				G.play:remove_card(v)
				G.deck:emplace(v)
				return true
			end, 0.2 / number, 'REAL')
		end
		Q(function()
			if next(cards) then
				playing_card_joker_effects(cards)
			end
			return true
		end)
	end
}

SMODS.Consumable {
	key = 'io',
	loc_txt = {
		name = 'Io',
		text = {
			'{C:planet}Level up{} all {C:purple}poker hands',
			'by {C:attention}#1#{}, plus another {C:attention}#1#',
			'for each {C:cry_code}Code{} card used this run',
			'{C:inactive}(Currently #2#)',
			'{C:dark_edition,s:0.7,E:2}Art by : ThreeCubed'
		}
	},
	config = { extra = { levels = 0.1 } },
	jumbo_mod = 3,
	set_card_type_badge = galilean,
	set = 'Planet',
	pos = { x = 2, y = 2 },
	cost = 3,
	aurinko = true,
	unlocked = true,
	discovered = true,
	atlas = 'jenplanets',
	loc_vars = function(self, info_queue, center)
		local lv = (((center or {}).ability or {}).extra or {}).levels or 0.1
		return { vars = { lv, lv * (jl.ctu('code') + 1) } }
	end,
	can_use = function(self, card)
		return jl.canuse()
	end,
	use = function(self, card, area, copier)
		card:blackhole(card.ability.extra.levels * (jl.ctu('code') + 1))
	end,
	bulk_use = function(self, card, area, copier, number)
		card:blackhole(card.ability.extra.levels * (jl.ctu('code') + 1) * number)
	end
}

SMODS.Consumable {
	key = 'europa',
	loc_txt = {
		name = 'Europa',
		text = {
			'Exchange the {C:attention}rightmost consumable',
			'for {C:attention}#1# {C:planet}Planet{} per {C:money}$#2#',
			'of sell value that consumable has',
			mayoverflow,
			'{C:dark_edition,s:0.7,E:2}Art by : ThreeCubed'
		}
	},
	no_ratau = true,
	ignore_allplanets = true,
	config = { exchange = 1, exchange_rate = 0.5 },
	jumbo_mod = 3,
	set_card_type_badge = galilean,
	set = 'Planet',
	pos = { x = 0, y = 3 },
	cost = 3,
	aurinko = true,
	unlocked = true,
	discovered = true,
	atlas = 'jenplanets',
	loc_vars = function(self, info_queue, center)
		return { vars = { math.ceil(((center or {}).ability or {}).exchange or 1), ((center or {}).ability or {}).exchange_rate or 0.5 } }
	end,
	can_use = function(self, card)
		return jl.canuse()
	end,
	use = function(self, card, area, copier)
		local did_exchange = false
		local target = G.consumeables.cards[#G.consumeables.cards]
		if target and not (target.ability or {}).eternal then
			local absolute_value = target.sell_cost / target:getQty()
			if absolute_value >= card.ability.exchange_rate then
				local budget = absolute_value
				while budget >= card.ability.exchange_rate do
					did_exchange = true
					for i = 1, math.ceil(card.ability.exchange) do
						G.E_MANAGER:add_event(Event({
							trigger = 'after',
							delay = 0.4,
							func = function()
								play_sound('jen_draw')
								local card2 = create_card('Planet', G.consumeables, nil, nil, nil, nil, nil,
									'europa_exchange')
								if card.edition then
									card2:set_edition(card.edition, true)
								end
								card2:add_to_deck()
								G.consumeables:emplace(card2)
								card:juice_up(0.3, 0.5)
								target:juice_up(0.3, 0.5)
								return true
							end
						}))
					end
					budget = budget - card.ability.exchange_rate
				end
			end
		end
		if not did_exchange then
			jl.a('No valid consumable!', G.SETTINGS.GAMESPEED, 0.65, G.C.RED, 'timpani')
			jl.rd(1)
		else
			if not target:getInfinite() then
				Q(function()
					if target:getQty() > 1 then target:subQty(1) else target:start_dissolve() end
					return true
				end)
			end
		end
	end,
	bulk_use = function(self, card, area, copier, number)
		local did_exchange = false
		local target = G.consumeables.cards[#G.consumeables.cards]
		if target and not (target.ability or {}).eternal then
			local absolute_value = target.sell_cost / target:getQty()
			if absolute_value >= card.ability.exchange_rate then
				local budget = absolute_value
				while budget >= card.ability.exchange_rate do
					did_exchange = true
					for i = 1, math.ceil(card.ability.exchange) do
						Q(function()
							play_sound('jen_draw')
							local card2 = create_card('Planet', G.consumeables, nil, nil, nil, nil, nil,
								'europa_exchange')
							if card.edition then
								card2:set_edition(card.edition, true)
							end
							card2:add_to_deck()
							G.consumeables:emplace(card2)
							card:juice_up(0.3, 0.5)
							target:juice_up(0.3, 0.5)
							return true
						end, 0.4, nil, 'after')
					end
					budget = budget - card.ability.exchange_rate
				end
			end
		end
		if not did_exchange then
			jl.a('No valid consumable!', G.SETTINGS.GAMESPEED, 0.65, G.C.RED, 'timpani')
			jl.rd(1)
		else
			if not target:getInfinite() then
				Q(function()
					if target:getQty() > 1 then target:subQty(1) else target:start_dissolve() end
					return true
				end)
			end
		end
	end
}

SMODS.Consumable {
	key = 'ganymede',
	loc_txt = {
		name = 'Ganymede',
		text = {
			'{C:attention}Most played poker hand{} gains',
			'the {C:chips}Chips{} of a {C:green}random{},',
			'{C:attention}different discovered poker hand',
			'{C:inactive}(#1#)',
			'{C:dark_edition,s:0.7,E:2}Art by : ThreeCubed'
		}
	},
	set_card_type_badge = galilean,
	set = 'Planet',
	pos = { x = 1, y = 3 },
	cost = 4,
	unlocked = true,
	discovered = true,
	atlas = 'jenplanets',
	loc_vars = function(self, info_queue, center)
		return { vars = { localize(jl.favhand(), 'poker_hands') } }
	end,
	can_use = function(self, card)
		return jl.canuse()
	end,
	use = function(self, card, area, copier)
		update_operator_display_custom(' ', G.C.WHITE)
		local hand = jl.favhand()
		local sel = jl.rndhand(hand, 'jen_ganymede')
		if (G.SETTINGS.FASTFORWARD or 0) < 1 then
			for i = 1, math.random(6, 12) do
				jl.th(G.handlist[math.random(#G.handlist)])
				delay(0.2)
			end
		end
		jl.h(localize(sel, 'poker_hands'), G.GAME.hands[sel].chips, '', G.GAME.hands[sel].level)
		delay(2)
		jl.hc('')
		Q(function()
			play_sound('timpani')
			return true
		end)
		update_operator_display_custom('+' .. number_format(G.GAME.hands[sel].chips), G.C.CHIPS)
		delay(2)
		jl.h(localize(hand, 'poker_hands'), G.GAME.hands[hand].chips, '', G.GAME.hands[hand].level)
		delay(2)
		G.GAME.hands[hand].chips = G.GAME.hands[hand].chips + G.GAME.hands[sel].chips
		jl.hc(G.GAME.hands[hand].chips, true)
		Q(function()
			play_sound('talisman_xchip')
			return true
		end)
		update_operator_display_custom(' ', G.C.WHITE)
		delay(1)
		jl.th(hand)
		update_operator_display()
		delay(1)
		jl.ch()
	end,
	bulk_use = function(self, card, area, copier, number)
		update_operator_display_custom(' ', G.C.WHITE)
		local hand = jl.favhand()
		local sels = {}
		local rand = ''
		local total = to_big(0)
		for i = 1, number do
			rand = jl.rndhand(hand, 'jen_ganymede')
			sels[rand] = (sels[rand] or 0) + 1
		end
		if (G.SETTINGS.FASTFORWARD or 0) < 1 then
			for i = 1, math.random(6, 12) do
				jl.th(G.handlist[math.random(#G.handlist)])
				delay(0.2)
			end
		end
		for k, v in pairs(sels) do
			jl.h(localize(k, 'poker_hands'), G.GAME.hands[k].chips, v > 1 and ('x' .. v) or '', G.GAME.hands[k].level)
			delay(1)
			if v > 1 then
				Q(function()
					play_sound('talisman_xchip', 1.5)
					return true
				end)
				jl.hcm(G.GAME.hands[k].chips * v, '')
			end
			total = total + to_big(G.GAME.hands[k].chips * v)
			local txt = number_format(total)
			delay(1)
			jl.hc('')
			Q(function()
				play_sound('timpani')
				return true
			end)
			update_operator_display_custom('+' .. txt, G.C.CHIPS)
			delay(1)
		end
		delay(1)
		jl.h(localize(hand, 'poker_hands'), G.GAME.hands[hand].chips, '', G.GAME.hands[hand].level)
		delay(1)
		G.GAME.hands[hand].chips = G.GAME.hands[hand].chips + total
		jl.hc(G.GAME.hands[hand].chips, true)
		Q(function()
			play_sound('talisman_xchip')
			return true
		end)
		update_operator_display_custom(' ', G.C.WHITE)
		delay(1)
		jl.th(hand)
		update_operator_display()
		delay(1)
		jl.ch()
	end
}

SMODS.Consumable {
	key = 'callisto',
	loc_txt = {
		name = 'Callisto',
		text = {
			'{C:attention}Most played poker hand{} gains',
			'the {C:mult}Mult{} of a {C:green}random{},',
			'{C:attention}different discovered poker hand',
			'{C:inactive}(#1#)',
			'{C:dark_edition,s:0.7,E:2}Art by : ThreeCubed'
		}
	},
	set_card_type_badge = galilean,
	set = 'Planet',
	pos = { x = 2, y = 3 },
	cost = 4,
	unlocked = true,
	discovered = true,
	atlas = 'jenplanets',
	loc_vars = function(self, info_queue, center)
		return { vars = { localize(jl.favhand(), 'poker_hands') } }
	end,
	can_use = function(self, card)
		return jl.canuse()
	end,
	use = function(self, card, area, copier)
		update_operator_display_custom(' ', G.C.WHITE)
		local hand = jl.favhand()
		local sel = jl.rndhand(hand, 'jen_callisto')
		if (G.SETTINGS.FASTFORWARD or 0) < 1 then
			for i = 1, math.random(6, 12) do
				jl.th(G.handlist[math.random(#G.handlist)])
				delay(0.2)
			end
		end
		jl.h(localize(sel, 'poker_hands'), '', G.GAME.hands[sel].mult, G.GAME.hands[sel].level)
		delay(2)
		jl.hm('')
		Q(function()
			play_sound('timpani')
			return true
		end)
		update_operator_display_custom(number_format(G.GAME.hands[sel].mult) .. '+', G.C.MULT)
		delay(2)
		jl.h(localize(hand, 'poker_hands'), '', G.GAME.hands[hand].mult, G.GAME.hands[hand].level)
		delay(2)
		G.GAME.hands[hand].mult = G.GAME.hands[hand].mult + G.GAME.hands[sel].mult
		jl.hm(G.GAME.hands[hand].mult, true)
		Q(function()
			play_sound('multhit2')
			return true
		end)
		update_operator_display_custom(' ', G.C.WHITE)
		delay(1)
		jl.th(hand)
		update_operator_display()
		delay(1)
		jl.ch()
	end,
	bulk_use = function(self, card, area, copier, number)
		update_operator_display_custom(' ', G.C.WHITE)
		local hand = jl.favhand()
		local sels = {}
		local rand = ''
		local total = to_big(0)
		for i = 1, number do
			rand = jl.rndhand(hand, 'jen_callisto')
			sels[rand] = (sels[rand] or 0) + 1
		end
		if (G.SETTINGS.FASTFORWARD or 0) < 1 then
			for i = 1, math.random(6, 12) do
				jl.th(G.handlist[math.random(#G.handlist)])
				delay(0.2)
			end
		end
		for k, v in pairs(sels) do
			jl.h(localize(k, 'poker_hands'), v > 1 and (v .. 'x') or '', G.GAME.hands[k].mult, G.GAME.hands[k].level)
			delay(1)
			if v > 1 then
				Q(function()
					play_sound('multhit2', 1.5)
					return true
				end)
				jl.hcm('', G.GAME.hands[k].mult * v)
			end
			total = total + to_big(G.GAME.hands[k].mult * v)
			local txt = number_format(total)
			delay(1)
			jl.hm('')
			Q(function()
				play_sound('timpani')
				return true
			end)
			update_operator_display_custom(txt .. '+', G.C.MULT)
			delay(1)
		end
		delay(1)
		jl.h(localize(hand, 'poker_hands'), '', G.GAME.hands[hand].mult, G.GAME.hands[hand].level)
		delay(1)
		G.GAME.hands[hand].mult = G.GAME.hands[hand].mult + total
		jl.hm(G.GAME.hands[hand].mult, true)
		Q(function()
			play_sound('multhit2')
			return true
		end)
		update_operator_display_custom(' ', G.C.WHITE)
		delay(1)
		jl.th(hand)
		update_operator_display()
		delay(1)
		jl.ch()
	end
}

SMODS.Consumable {
	key = 'mimas',
	loc_txt = {
		name = 'Mimas',
		text = {
			'Increases the {C:attention}most played poker hand\'s',
			'{C:chips}Chips-per-level{} and {C:mult}Mult-per-level',
			'by {C:attention}one-fifth of the square root{} of its {C:attention}current {C:chips}Chips{} & {C:mult}Mult{},',
			'then {C:attention}increase the hand\'s current {C:chips}Chips{} & {C:mult}Mult',
			'to reflect on its new {C:chips}Chips-per-level{} and {C:mult}Mult-per-level',
			'{C:inactive}(#1#)',
			'{C:dark_edition,s:0.7,E:2}Art by : smg9000'
		}
	},
	set_card_type_badge = natsat,
	set = 'Planet',
	pos = { x = 0, y = 4 },
	cost = 4,
	unlocked = true,
	discovered = true,
	atlas = 'jenplanets',
	loc_vars = function(self, info_queue, center)
		return { vars = { localize(jl.favhand(), 'poker_hands') } }
	end,
	can_use = function(self, card)
		return jl.canuse()
	end,
	use = function(self, card, area, copier)
		local hand = jl.favhand()
		local data = G.GAME.hands[hand]
		update_operator_display_custom('Per Lv.', G.C.WHITE)
		jl.h(localize(hand, 'poker_hands'), data.l_chips, data.l_mult, data.level)
		local old_lchips = G.GAME.hands[hand].l_chips
		local old_lmult = G.GAME.hands[hand].l_mult
		local added_chips = (G.GAME.hands[hand].chips ^ .5) / 5
		local added_mult = (G.GAME.hands[hand].mult ^ .5) / 5
		G.GAME.hands[hand].l_chips = old_lchips + added_chips
		G.GAME.hands[hand].l_mult = old_lmult + added_mult
		G.E_MANAGER:add_event(Event({
			trigger = "after",
			delay = 0.2,
			func = function()
				play_sound("tarot1")
				card:juice_up(0.8, 0.5)
				G.TAROT_INTERRUPT_PULSE = true
				return true
			end,
		}))
		update_hand_text({ delay = 0 }, { mult = G.GAME.hands[hand].l_mult, StatusText = true })
		G.E_MANAGER:add_event(Event({
			trigger = "after",
			delay = 0.9,
			func = function()
				play_sound("tarot1")
				card:juice_up(0.8, 0.5)
				G.TAROT_INTERRUPT_PULSE = nil
				return true
			end,
		}))
		update_hand_text({ delay = 0 }, { chips = G.GAME.hands[hand].l_chips, StatusText = true })
		delay(4)
		update_operator_display()
		jl.th(hand)
		G.GAME.hands[hand].chips = G.GAME.hands[hand].chips + (added_chips * data.level)
		G.GAME.hands[hand].mult = G.GAME.hands[hand].mult + (added_mult * data.level)
		Q(function()
			play_sound("tarot1")
			card:juice_up(0.8, 0.5)
			G.TAROT_INTERRUPT_PULSE = true
			return true
		end, 0.2, nil, 'after')
		update_hand_text({ delay = 0 }, { mult = G.GAME.hands[hand].mult, StatusText = true })
		Q(function()
			play_sound("tarot1")
			card:juice_up(0.8, 0.5)
			G.TAROT_INTERRUPT_PULSE = nil
			return true
		end, 0.9, nil, 'after')
		update_hand_text({ delay = 0 }, { chips = G.GAME.hands[hand].chips, StatusText = true })
		delay(4)
		jl.ch()
	end,
	bulk_use = function(self, card, area, copier, number)
		local hand = jl.favhand()
		local data = G.GAME.hands[hand]
		update_operator_display_custom('Per Lv.', G.C.WHITE)
		jl.h(localize(hand, 'poker_hands'), data.l_chips, data.l_mult, data.level)
		local old_lchips = G.GAME.hands[hand].l_chips
		local old_lmult = G.GAME.hands[hand].l_mult
		local old_chips = G.GAME.hands[hand].chips
		local old_mult = G.GAME.hands[hand].mult
		local added_chips = 0
		local added_mult = 0
		for i = 1, math.max(1, number) do
			added_chips = added_chips + ((old_chips ^ .5) / 5)
			added_mult = added_mult + ((old_mult ^ .5) / 5)
			old_chips = old_chips + (added_chips * data.level)
			old_mult = old_mult + (added_mult * data.level)
		end
		G.GAME.hands[hand].l_chips = old_lchips + added_chips
		G.GAME.hands[hand].l_mult = old_lmult + added_mult
		Q(function()
			play_sound("tarot1")
			card:juice_up(0.8, 0.5)
			G.TAROT_INTERRUPT_PULSE = true
			return true
		end, 0.2, nil, 'after')
		update_hand_text({ delay = 0 }, { mult = G.GAME.hands[hand].l_mult, StatusText = true })
		Q(function()
			play_sound("tarot1")
			card:juice_up(0.8, 0.5)
			G.TAROT_INTERRUPT_PULSE = nil
			return true
		end, 0.9, nil, 'after')
		update_hand_text({ delay = 0 }, { chips = G.GAME.hands[hand].l_chips, StatusText = true })
		delay(4)
		update_operator_display()
		jl.th(hand)
		G.GAME.hands[hand].chips = old_chips
		G.GAME.hands[hand].mult = old_mult
		G.E_MANAGER:add_event(Event({
			trigger = "after",
			delay = 0.2,
			func = function()
				play_sound("tarot1")
				card:juice_up(0.8, 0.5)
				G.TAROT_INTERRUPT_PULSE = true
				return true
			end,
		}))
		update_hand_text({ delay = 0 }, { mult = G.GAME.hands[hand].mult, StatusText = true })
		G.E_MANAGER:add_event(Event({
			trigger = "after",
			delay = 0.9,
			func = function()
				play_sound("tarot1")
				card:juice_up(0.8, 0.5)
				G.TAROT_INTERRUPT_PULSE = nil
				return true
			end,
		}))
		update_hand_text({ delay = 0 }, { chips = G.GAME.hands[hand].chips, StatusText = true })
		delay(4)
		jl.ch()
	end
}

SMODS.Consumable {
	key = 'enceladus',
	loc_txt = {
		name = 'Enceladus',
		text = {
			'Gain {C:money}$#1#{} for each time',
			'your {C:attention}most played poker hand',
			'has been played',
			'{C:inactive}(Max of $#2#)',
			'{C:inactive}(Currently #3#, {C:money}$#4#{C:inactive})',
			spriter('mailingway')
		}
	},
	config = { max_payout = 50, earnings = 1 },
	set_card_type_badge = natsat,
	set = 'Planet',
	pos = { x = 1, y = 4 },
	cost = 3,
	unlocked = true,
	discovered = true,
	atlas = 'jenplanets',
	loc_vars = function(self, info_queue, center)
		return { vars = { ((center or {}).ability or {}).earnings or 1, ((center or {}).ability or {}).max_payout or 50, localize(jl.favhand(), 'poker_hands'), (((center or {}).ability or {}).earnings or 1) * ((((G.GAME or {}).hands or {})[jl.favhand()] or {}).played or 0) } }
	end,
	can_use = function(self, card)
		return jl.canuse()
	end,
	use = function(self, card, area, copier)
		local hand = jl.favhand()
		delay(1)
		ease_dollars(math.min(G.GAME.hands[hand].played * card.ability.earnings, card.ability.max_payout))
		Q(function()
			card:juice_up(0.8, 0.5)
			return true
		end)
	end,
	bulk_use = function(self, card, area, copier, number)
		local hand = jl.favhand()
		delay(1)
		ease_dollars(math.min(G.GAME.hands[hand].played * card.ability.earnings, card.ability.max_payout) * number)
		Q(function()
			card:juice_up(0.8, 0.5)
			return true
		end)
	end
}

SMODS.Consumable {
	key = 'tethys',
	loc_txt = {
		name = 'Tethys',
		text = {
			'Level up all {C:purple}poker hands',
			'by {C:attention}one-tenth{} of a level',
			'for every {C:attention}Joker{} you have',
			'{C:inactive}(Currently #1#)',
			'{C:dark_edition,s:0.7,E:2}Art by : Zahrizi'
		}
	},
	set = 'Planet',
	pos = { x = 2, y = 4 },
	cost = 4,
	unlocked = true,
	discovered = true,
	atlas = 'jenplanets',
	loc_vars = function(self, info_queue, center)
		return { vars = { not G.jokers and 0 or (#G.jokers.cards * 0.1) } }
	end,
	can_use = function(self, card)
		return jl.canuse()
	end,
	use = function(self, card, area, copier)
		card:blackhole(#G.jokers.cards * 0.1)
	end,
	bulk_use = function(self, card, area, copier, number)
		card:blackhole(#G.jokers.cards * 0.1 * number)
	end
}

SMODS.Consumable {
	key = 'dione',
	loc_txt = {
		name = 'Dione',
		text = {
			'{C:red}Least leveled poker hand{} gains',
			'{C:attention}one-fifth{} of the {C:planet}levels',
			'from the {C:blue}most played poker hand',
			'{C:inactive}(Currently {C:red}#1#{C:inactive} and {C:blue}#2#{C:inactive})',
			spriter('mailingway')
		}
	},
	set = 'Planet',
	pos = { x = 0, y = 5 },
	cost = 4,
	unlocked = true,
	discovered = true,
	atlas = 'jenplanets',
	loc_vars = function(self, info_queue, center)
		return { vars = { localize(jl.lowhand(), 'poker_hands'), localize(jl.favhand(), 'poker_hands') } }
	end,
	can_use = function(self, card)
		return jl.canuse()
	end,
	use = function(self, card, area, copier)
		local hand1 = jl.favhand()
		local hand2 = jl.lowhand()
		local mod = G.GAME.hands[hand1].level / 5
		card:do_jen_astronomy(hand2, mod)
		jl.th(hand2)
		level_up_hand(card, hand2, nil, mod)
		jl.ch()
	end,
	bulk_use = function(self, card, area, copier, number)
		local hand1 = jl.favhand()
		local hand2 = jl.lowhand()
		local mod = G.GAME.hands[hand1].level / 5
		if hand1 == hand2 then
			for i = 1, number do
				mod = (G.GAME.hands[hand1].level + mod) / 5
			end
		else
			mod = mod * number
		end
		card:do_jen_astronomy(hand2, mod)
		jl.th(hand2)
		level_up_hand(card, hand2, nil, mod)
		jl.ch()
	end
}

local function rhea_value()
	if not G.playing_cards then return 0 end
	local val = 0
	for k, v in ipairs(G.playing_cards) do
		if (v.edition or {}).jen_wee then
			val = val + (0.02 * (1 + (v.ability.wee_upgrades or 0)))
		end
	end
	return val
end

SMODS.Consumable {
	key = 'rhea',
	loc_txt = {
		name = 'Rhea',
		text = {
			'All hands gain {C:attention}+0.02 {C:planet}levels{}, plus {C:attention}another +0.02',
			'for each {C:dark_edition}Wee {C:attention}playing card',
			'as well as by how many times',
			'said card {C:attention}has been upgraded by {C:dark_edition}Wee',
			'{C:inactive}(Currently #1#)',
			'{C:dark_edition,s:0.7,E:2}Art by : abreaker'
		}
	},
	set = 'Planet',
	pos = { x = 1, y = 5 },
	cost = 2,
	unlocked = true,
	discovered = true,
	atlas = 'jenplanets',
	loc_vars = function(self, info_queue, center)
		return { vars = { rhea_value() + 0.02 } }
	end,
	can_use = function(self, card)
		return jl.canuse()
	end,
	use = function(self, card, area, copier)
		card:blackhole(rhea_value() + 0.02)
	end,
	bulk_use = function(self, card, area, copier, number)
		card:blackhole((rhea_value() + 0.02) * number)
	end
}

local function faces_in_deck()
	local count = 0
	if not G.playing_cards then return count end
	for k, v in ipairs(G.playing_cards) do
		if v:is_face() then
			count = count + 1
		end
	end
	return count
end

local function odds_in_deck()
	local count = 0
	if not G.playing_cards then return count end
	if #SMODS.find_card('j_cry_maximized') > 0 then return count end
	for k, v in ipairs(G.playing_cards) do
		if v.base.id and not v:norankorsuit() and v.base.id ~= 13 and v.base.id ~= 12 and v.base.id ~= 11 and (math.floor(v.base.id / 2) ~= (v.base.id / 2) or v.base.id == 14) then
			count = count + 1
		end
	end
	return count
end

local function evens_in_deck()
	local count = 0
	if not G.playing_cards then return count end
	if #SMODS.find_card('j_cry_maximized') > 0 then
		if #SMODS.find_card('j_pareidolia') > 0 then
			return count
		else
			for k, v in ipairs(G.playing_cards) do
				if v.base.id and not v:norankorsuit() and not v:is_face() then
					count = count + 1
				end
			end
		end
	else
		for k, v in ipairs(G.playing_cards) do
			if v.base.id and not v:norankorsuit() and v.base.id < 11 and math.floor(v.base.id / 2) == (v.base.id / 2) then
				count = count + 1
			end
		end
	end
	return count
end

local function suits_in_deck(suit)
	local count = 0
	if not G.playing_cards then return count end
	for k, v in ipairs(G.playing_cards) do
		if v:is_suit(suit) then
			count = count + 1
		end
	end
	return count
end

SMODS.Consumable {
	key = 'titan',
	loc_txt = {
		name = 'Titan',
		text = {
			'All hands gain {C:attention}+0.01 {C:planet}levels{}, plus {C:attention}another +0.01',
			'for each {C:attention}face card{} in your deck',
			'{C:inactive}(J, Q, K)',
			'{C:inactive}(Currently #1#)',
			'{C:dark_edition,s:0.7,E:2}Art by : Maxie'
		}
	},
	set = 'Planet',
	pos = { x = 2, y = 5 },
	cost = 3,
	unlocked = true,
	discovered = true,
	atlas = 'jenplanets',
	loc_vars = function(self, info_queue, center)
		return { vars = { (faces_in_deck() + 1) / 100 } }
	end,
	can_use = function(self, card)
		return jl.canuse()
	end,
	use = function(self, card, area, copier)
		card:blackhole((faces_in_deck() + 1) / 100)
	end,
	bulk_use = function(self, card, area, copier, number)
		card:blackhole(((faces_in_deck() + 1) / 100) * number)
	end
}

SMODS.Consumable {
	key = 'hyperion',
	loc_txt = {
		name = 'Hyperion',
		text = {
			'All hands gain {C:attention}+0.005 {C:planet}levels{}, plus {C:attention}another +0.005',
			'for each {C:attention}odd-numbered card{} in your deck',
			'{C:inactive}(A, 3, 5, 7, 9)',
			'{C:inactive}(Currently #1#)',
			'{C:dark_edition,s:0.7,E:2}Art by : Maxie'
		}
	},
	set = 'Planet',
	pos = { x = 0, y = 6 },
	cost = 3,
	unlocked = true,
	discovered = true,
	atlas = 'jenplanets',
	loc_vars = function(self, info_queue, center)
		return { vars = { tostring((odds_in_deck() + 1) / 200) } }
	end,
	can_use = function(self, card)
		return jl.canuse()
	end,
	use = function(self, card, area, copier)
		card:blackhole((odds_in_deck() + 1) / 200)
	end,
	bulk_use = function(self, card, area, copier, number)
		card:blackhole(((odds_in_deck() + 1) / 200) * number)
	end
}

SMODS.Consumable {
	key = 'iapetus',
	loc_txt = {
		name = 'Iapetus',
		text = {
			'All hands gain {C:attention}+0.005 {C:planet}levels{}, plus {C:attention}another +0.005',
			'for each {C:attention}even-numbered card{} in your deck',
			'{C:inactive}(2, 4, 6, 8, 10)',
			'{C:inactive}(Currently #1#)',
			spriter('mailingway')
		}
	},
	set = 'Planet',
	pos = { x = 1, y = 6 },
	cost = 3,
	unlocked = true,
	discovered = true,
	atlas = 'jenplanets',
	loc_vars = function(self, info_queue, center)
		return { vars = { tostring((evens_in_deck() + 1) / 200) } }
	end,
	can_use = function(self, card)
		return jl.canuse()
	end,
	use = function(self, card, area, copier)
		card:blackhole((evens_in_deck() + 1) / 200)
	end,
	bulk_use = function(self, card, area, copier, number)
		card:blackhole(((evens_in_deck() + 1) / 200) * number)
	end
}

SMODS.Consumable {
	key = 'phoebe',
	loc_txt = {
		name = 'Phoebe',
		text = {
			'All hands gain {C:attention}+0.05 {C:planet}levels',
			'for each time that hand has been {C:attention}played',
			'{C:dark_edition,s:0.7,E:2}Art by : Basilloon'
		}
	},
	set = 'Planet',
	pos = { x = 2, y = 6 },
	cost = 3,
	unlocked = true,
	discovered = true,
	atlas = 'jenplanets',
	can_use = function(self, card)
		return jl.canuse()
	end,
	use = function(self, card, area, copier)
		jl.th('all')
		G.E_MANAGER:add_event(Event({
			trigger = "after",
			delay = 0.2,
			func = function()
				play_sound("tarot1")
				card:juice_up(0.8, 0.5)
				G.TAROT_INTERRUPT_PULSE = true
				return true
			end,
		}))
		update_hand_text({ delay = 0 }, { mult = "+", StatusText = true })
		G.E_MANAGER:add_event(Event({
			trigger = "after",
			delay = 0.9,
			func = function()
				play_sound("tarot1")
				card:juice_up(0.8, 0.5)
				return true
			end,
		}))
		update_hand_text({ delay = 0 }, { chips = "+", StatusText = true })
		G.E_MANAGER:add_event(Event({
			trigger = "after",
			delay = 0.9,
			func = function()
				play_sound("tarot1")
				card:juice_up(0.8, 0.5)
				G.TAROT_INTERRUPT_PULSE = nil
				return true
			end,
		}))
		update_hand_text({ sound = "button", volume = 0.7, pitch = 0.9, delay = 0 }, { level = '+?' })
		delay(1.3)
		for k, v in pairs(G.GAME.hands) do
			if v.played > 0 then
				level_up_hand(card, k, true, v.played / 20)
				jl.th(k)
			end
		end
		jl.ch()
	end,
	bulk_use = function(self, card, area, copier, number)
		jl.th('all')
		G.E_MANAGER:add_event(Event({
			trigger = "after",
			delay = 0.2,
			func = function()
				play_sound("tarot1")
				card:juice_up(0.8, 0.5)
				G.TAROT_INTERRUPT_PULSE = true
				return true
			end,
		}))
		update_hand_text({ delay = 0 }, { mult = "+", StatusText = true })
		G.E_MANAGER:add_event(Event({
			trigger = "after",
			delay = 0.9,
			func = function()
				play_sound("tarot1")
				card:juice_up(0.8, 0.5)
				return true
			end,
		}))
		update_hand_text({ delay = 0 }, { chips = "+", StatusText = true })
		G.E_MANAGER:add_event(Event({
			trigger = "after",
			delay = 0.9,
			func = function()
				play_sound("tarot1")
				card:juice_up(0.8, 0.5)
				G.TAROT_INTERRUPT_PULSE = nil
				return true
			end,
		}))
		update_hand_text({ sound = "button", volume = 0.7, pitch = 0.9, delay = 0 }, { level = '+?' })
		delay(1.3)
		for k, v in pairs(G.GAME.hands) do
			if v.played > 0 then
				level_up_hand(card, k, true, (v.played / 20) * number)
				jl.th(k)
			end
		end
		jl.ch()
	end
}

local suitsindeck_planets = {
	{
		n = 'Miranda',
		s = 'Hearts',
		p = { x = 0, y = 7 },
		a = 'ThreeCubed'
	},
	{
		n = 'Ariel',
		s = 'Clubs',
		p = { x = 1, y = 7 },
		a = 'Zahrizi'
	},
	{
		n = 'Umbriel',
		s = 'Spades',
		p = { x = 2, y = 7 },
		a = 'abreaker'
	},
	{
		n = 'Titania',
		s = 'Diamonds',
		p = { x = 0, y = 8 },
		a = 'mailingway'
	}
}

for k, v in ipairs(suitsindeck_planets) do
	SMODS.Consumable {
		key = string.lower(v.n),
		loc_txt = {
			name = v.n,
			text = {
				'All hands gain {C:attention}+0.01 {C:planet}levels{}, plus {C:attention}another +0.01',
				'for each {C:' .. string.lower(string.sub(v.s, 1, string.len(v.s) - 1)) .. '}' .. string.sub(v.s, 1, string.len(v.s) - 1) .. '{} in your deck',
				'{C:inactive}(Currently #1#)',
				'{C:dark_edition,s:0.7,E:2}Art by : ' .. v.a
			}
		},
		set = 'Planet',
		pos = v.p,
		cost = 3,
		unlocked = true,
		discovered = true,
		atlas = 'jenplanets',
		loc_vars = function(self, info_queue, center)
			return { vars = { (suits_in_deck(v.s) + 1) / 100 } }
		end,
		can_use = function(self, card)
			return jl.canuse()
		end,
		use = function(self, card, area, copier)
			card:blackhole((suits_in_deck(v.s) + 1) / 100)
		end,
		bulk_use = function(self, card, area, copier, number)
			card:blackhole(((suits_in_deck(v.s) + 1) / 100) * number)
		end
	}
end

local function count_identical_cards(rank, suit)
	local count = 0
	if not G.playing_cards then return count end
	for k, v in ipairs(G.playing_cards) do
		if not v:norankorsuit() and (v.base.id or 0) == rank and (v.base.suit or '') == suit and not v.oberon_created then
			count = count + 1
		end
	end
	return count
end

SMODS.Consumable {
	key = 'oberon',
	loc_txt = {
		name = 'Oberon',
		text = {
			'Shows a card with a {C:attention}random rank and suit{},',
			'then for each card in your deck',
			'that is {C:attention}identical in rank and suit',
			'to the shown card, {C:planet}upgrade {C:attention}all poker hands',
			'Level amount starts at {C:attention}0.25{}, and {C:attention}doubles each time',
			'{C:inactive}(ex. if you had 3 Jack of Hearts and',
			'{C:inactive}Jack of Hearts was the shown card,',
			'{C:inactive}all poker hands would level up',
			'{C:inactive}by +0.25, then by +0.5, then by +1, for a total of +1.75)',
			spriter('mailingway')
		}
	},
	set = 'Planet',
	pos = { x = 1, y = 8 },
	cost = 3,
	unlocked = true,
	discovered = true,
	atlas = 'jenplanets',
	can_use = function(self, card)
		return jl.canuse()
	end,
	use = function(self, card, area, copier)
		jl.ch()
		jl.hcm('', '')
		update_operator_display_custom(' ', G.C.WHITE)
		local evaluator = create_playing_card(nil, G.play, nil, nil, { G.C.SECONDARY_SET.Planet })
		evaluator.oberon_created = true
		if card.edition then
			evaluator:set_edition(card.edition, true, true)
		end
		local cumulative = 0
		delay(3)
		jl.hn(SMODS.Ranks[evaluator.base.value].key .. ' of ' .. SMODS.Suits[evaluator.base.suit].key)
		play_sound_q('button')
		Q(function()
			if evaluator then
				evaluator:juice_up(0.8, 0.5)
				evaluator.highlighted = true
			end
			return true
		end)
		delay(3)
		local identical = count_identical_cards(evaluator.base.id, evaluator.base.suit)
		if identical > 0 then
			play_sound_q('button')
			jl.hm('x' .. identical)
			delay(3)
			for i = 1, identical do
				cumulative = cumulative + ((2 ^ (i - 1)) / 4)
				play_sound_q('button', 1.1)
				jl.hcm('+' .. number_format(cumulative), i == identical and '' or ('x' .. (identical - i)))
				delay(0.25)
			end
			delay(2.75)
			update_operator_display()
			card:blackhole(cumulative)
		else
			jl.hcm('Nope!', 'Nope!')
			play_sound_q('timpani')
			delay(3)
			update_operator_display()
		end
		Q(function()
			if evaluator then
				evaluator.highlighted = false
				evaluator:destroy()
			end
			return true
		end)
		jl.ch()
	end,
	bulk_use = function(self, card, area, copier, number)
		jl.ch()
		jl.hcm('', '')
		update_operator_display_custom(' ', G.C.WHITE)
		local evaluators = {}
		for i = 1, number do
			evaluators[i] = create_playing_card(nil, G.play, nil, nil, { G.C.SECONDARY_SET.Planet })
			evaluators[i].oberon_created = true
			if card.edition then
				evaluators[i]:set_edition(card.edition, true, true)
			end
		end
		local cumulative = 0
		delay(3)
		for k, evaluator in ipairs(evaluators) do
			jl.hn(SMODS.Ranks[evaluator.base.value].key .. ' of ' .. SMODS.Suits[evaluator.base.suit].key)
			play_sound_q('button')
			Q(function()
				if evaluator then
					evaluator:juice_up(0.8, 0.5)
					evaluator.highlighted = true
				end
				return true
			end)
			delay(3)
			local identical = count_identical_cards(evaluator.base.id, evaluator.base.suit)
			if identical > 0 then
				play_sound_q('button')
				jl.hm('x' .. identical)
				delay(3)
				for i = 1, identical do
					cumulative = cumulative + ((2 ^ (i - 1)) / 4)
					play_sound_q('button', 1.1)
					jl.hcm('+' .. number_format(cumulative), i == identical and '' or ('x' .. (identical - i)))
					delay(0.25)
				end
				delay(2.75)
			else
				if cumulative <= 0 then jl.hcm('Nope!', 'Nope!') else jl.hc('Nope!') end
				play_sound_q('timpani')
				delay(3)
			end
			Q(function()
				if evaluator then evaluator.highlighted = false end
				return true
			end)
		end
		update_operator_display()
		if cumulative > 0 then
			card:blackhole(cumulative)
		end
		Q(function()
			for k, evaluator in ipairs(evaluators) do if evaluator then evaluator:destroy() end end
			return true
		end)
		jl.ch()
	end
}

SMODS.Consumable {
	key = 'orcus',
	loc_txt = {
		name = 'Orcus',
		text = {
			'Your {C:blue}most played hand{} will',
			'{C:purple,E:1}siphon {C:attention}half{} of the {C:planet}levels',
			'from the {C:red}poker hands{} that are {C:attention}adjacent{} to it',
			'{C:inactive}({C:red}#1# {C:purple}>> {C:blue}#2# {C:purple}<< {C:red}#3#{C:inactive})',
			spriter('mailingway')
		}
	},
	set = 'Planet',
	ayanami = true,
	pos = { x = 2, y = 8 },
	cost = 5,
	unlocked = true,
	discovered = true,
	atlas = 'jenplanets',
	loc_vars = function(self, info_queue, center)
		local fav = jl.favhand()
		local hands = jl.adjacenthands(fav)
		return { vars = { hands.backhand and localize(hands.backhand, 'poker_hands') or '<none>', localize(fav, 'poker_hands'), hands.forehand and localize(hands.forehand, 'poker_hands') or '<none>' } }
	end,
	can_use = function(self, card)
		return jl.canuse()
	end,
	use = function(self, card, area, copier)
		local fav = jl.favhand()
		local hands = jl.adjacenthands(fav)
		local lv = to_big(0)
		local levels_siphoned = to_big(0)
		if hands.backhand then
			if G.GAME.hands[hands.backhand].level > to_big(0) then
				jl.th(hands.backhand)
				lv = G.GAME.hands[hands.backhand].level / to_big(2)
				level_up_hand(card, hands.backhand, nil, -lv)
				levels_siphoned = lv
			end
		end
		if hands.forehand then
			if G.GAME.hands[hands.forehand].level > to_big(0) then
				jl.th(hands.forehand)
				lv = G.GAME.hands[hands.forehand].level / to_big(2)
				level_up_hand(card, hands.forehand, nil, -lv)
				levels_siphoned = levels_siphoned + lv
			end
		end
		card:do_jen_astronomy(fav, levels_siphoned)
		jl.th(fav)
		level_up_hand(card, fav, nil, levels_siphoned)
		jl.ch()
	end,
	bulk_use = function(self, card, area, copier, number)
		local fav = jl.favhand()
		local hands = jl.adjacenthands(fav)
		local lv = to_big(0)
		local levels_siphoned = to_big(0)
		local divisor = to_big(2) - (1 / (2 ^ (number - 1)))
		if hands.backhand then
			if G.GAME.hands[hands.backhand].level > to_big(0) then
				jl.th(hands.backhand)
				lv = (G.GAME.hands[hands.backhand].level / divisor)
				level_up_hand(card, hands.backhand, nil, -lv)
				levels_siphoned = lv
			end
		end
		if hands.forehand then
			if G.GAME.hands[hands.forehand].level > to_big(0) then
				jl.th(hands.forehand)
				lv = (G.GAME.hands[hands.forehand].level / divisor)
				level_up_hand(card, hands.forehand, nil, -lv)
				levels_siphoned = levels_siphoned + lv
			end
		end
		card:do_jen_astronomy(fav, levels_siphoned)
		jl.th(fav)
		level_up_hand(card, fav, nil, levels_siphoned)
		jl.ch()
	end
}

SMODS.Consumable {
	key = 'vanth',
	loc_txt = {
		name = 'Vanth',
		text = {
			'{C:attention}Rounds{} all hand levels {C:attention}up',
			'to the {C:attention}next integer',
			'{C:inactive}(ex. 2.43 >becomes> 3, 5.81 >becomes> 6)',
			spriter('mailingway')
		}
	},
	set = 'Planet',
	pos = { x = 0, y = 9 },
	cost = 3,
	unlocked = true,
	discovered = true,
	atlas = 'jenplanets',
	can_use = function(self, card)
		return jl.canuse()
	end,
	use = function(self, card, area, copier)
		for k, v in ipairs(G.handlist) do
			if to_big(G.GAME.hands[v].level) < to_big(9e15) then
				if math.ceil(G.GAME.hands[v].level) ~= G.GAME.hands[v].level then
					level_up_hand(nil, v, true, math.ceil(G.GAME.hands[v].level) - G.GAME.hands[v].level, true, true)
				end
			end
		end
		jl.th('all')
		delay(1)
		jl.h(localize('k_all_hands'), '+', '+', '=ceil(#)', true)
		Q(function()
			card:juice_up(1, 0.5)
			play_sound('highlight2', 1, 0.6)
			return true
		end)
		delay(3)
		jl.ch()
	end,
	bulk_use = function(self, card, area, copier, number)
		for k, v in ipairs(G.handlist) do
			if to_big(G.GAME.hands[v].level) < to_big(9e15) then
				if math.ceil(G.GAME.hands[v].level) ~= G.GAME.hands[v].level then
					level_up_hand(nil, v, true, math.ceil(G.GAME.hands[v].level) - G.GAME.hands[v].level, true, true)
				end
			end
		end
		jl.th('all')
		delay(1)
		jl.h(localize('k_all_hands'), '+', '+', '=ceil(#)', true)
		Q(function()
			card:juice_up(1, 0.5)
			play_sound('highlight2', 1, 0.6)
			return true
		end)
		delay(3)
		jl.ch()
	end
}

SMODS.Consumable {
	key = 'charon',
	loc_txt = {
		name = 'Charon',
		text = {
			'{C:attention}Two {C:green}random {C:attention}discovered{} poker hands',
			'will {C:attention}swap over{} their statistics',
			'{C:inactive}(Chips, Mult, Chips/Level, Mult/Level, Level, Times Played)',
			spriter('mailingway')
		}
	},
	set = 'Planet',
	pos = { x = 1, y = 9 },
	cost = 6,
	unlocked = true,
	discovered = true,
	ignore_allplanets = true,
	atlas = 'jenplanets',
	can_use = function(self, card)
		return jl.canuse()
	end,
	use = function(self, card, area, copier)
		local hand1 = jl.rndhand()
		local hand2 = jl.rndhand(hand1)
		local card1 = jl.rawcard(jl.planethand(hand1), 1, 0.5)
		local card2 = jl.rawcard(jl.planethand(hand2), 1, 1.5)
		local hand1data = {
			chips = G.GAME.hands[hand1].chips,
			l_chips = G.GAME.hands[hand1].l_chips,
			mult = G.GAME.hands[hand1].mult,
			l_mult = G.GAME.hands[hand1].l_mult,
			level = G.GAME.hands[hand1].level,
			played = G.GAME.hands[hand1].played
		}
		if (G.SETTINGS.FASTFORWARD or 0) <= 0 then
			jl.h('', '', '', '')
			delay(1)
			jl.th(hand1)
			Q(function()
				card1:juice_up(0.3, 0.5); return true
			end)
			delay(2)
			update_operator_display_custom('Per Lv.', G.C.WHITE)
			jl.hcm(G.GAME.hands[hand1].l_chips, G.GAME.hands[hand1].l_mult)
			delay(2)
			update_operator_display()
			jl.th(hand2)
			Q(function()
				card2:juice_up(0.3, 0.5); return true
			end)
			delay(2)
			update_operator_display_custom('Per Lv.', G.C.WHITE)
			jl.hcm(G.GAME.hands[hand2].l_chips, G.GAME.hands[hand2].l_mult)
			delay(2)
			update_operator_display()
			jl.h('', '', '', '')
		else
			jl.ch()
		end
		delay(1)
		Q(function()
			card:juice_up(0.3, 0.5); play_sound('tarot1'); return true
		end)
		delay(0.5)
		Q(function()
			card1:fake_dissolve(); card2:fake_dissolve(); return true
		end)
		delay(0.5)
		card:speak('Swapped!')
		Q(function()
			card1:set_ability(G.P_CENTERS[jl.planethand(hand2)]); card2:set_ability(G.P_CENTERS[jl.planethand(hand1)]); card1
				:start_materialize(); card2:start_materialize(); play_sound('jen_misc1'); return true
		end)
		G.GAME.hands[hand1].chips = G.GAME.hands[hand2].chips
		G.GAME.hands[hand1].l_chips = G.GAME.hands[hand2].l_chips
		G.GAME.hands[hand1].mult = G.GAME.hands[hand2].mult
		G.GAME.hands[hand1].l_mult = G.GAME.hands[hand2].l_mult
		G.GAME.hands[hand1].level = G.GAME.hands[hand2].level
		G.GAME.hands[hand1].played = G.GAME.hands[hand2].played
		G.GAME.hands[hand2].chips = hand1data.chips
		G.GAME.hands[hand2].l_chips = hand1data.l_chips
		G.GAME.hands[hand2].mult = hand1data.mult
		G.GAME.hands[hand2].l_mult = hand1data.l_mult
		G.GAME.hands[hand2].level = hand1data.level
		G.GAME.hands[hand2].played = hand1data.played
		delay(1)
		if (G.SETTINGS.FASTFORWARD or 0) <= 0 then
			jl.th(hand2)
			Q(function()
				card1:juice_up(0.3, 0.5)
				return true
			end)
			delay(2)
			update_operator_display_custom('Per Lv.', G.C.WHITE)
			jl.hcm(G.GAME.hands[hand2].l_chips, G.GAME.hands[hand2].l_mult)
			delay(2)
			update_operator_display()
			jl.th(hand1)
			Q(function()
				card2:juice_up(0.3, 0.5)
				return true
			end)
			delay(2)
			update_operator_display_custom('Per Lv.', G.C.WHITE)
			jl.hcm(G.GAME.hands[hand1].l_chips, G.GAME.hands[hand1].l_mult)
			delay(2)
			update_operator_display()
			jl.ch()
		end
		Q(function()
			card1:destroy(); card2:destroy(); hand1data = nil; return true
		end)
	end
}

SMODS.Consumable {
	key = 'haumea',
	loc_txt = {
		name = 'Haumea',
		text = {
			'Your {C:red}most played hand{} will',
			'{C:planet}upgrade{} the {C:blue}poker hands{} that are',
			'{C:attention}adjacent{} to it by a {C:attention}fourth',
			'of its current level',
			'{C:inactive}({C:blue}#1# {C:green}<< {C:red}#2# {C:green}>> {C:blue}#3#{C:inactive})',
			spriter('mailingway')
		}
	},
	set = 'Planet',
	ayanami = true,
	pos = { x = 2, y = 9 },
	cost = 5,
	unlocked = true,
	discovered = true,
	atlas = 'jenplanets',
	loc_vars = function(self, info_queue, center)
		local fav = jl.favhand()
		local hands = jl.adjacenthands(fav)
		return { vars = { hands.backhand and localize(hands.backhand, 'poker_hands') or '<none>', localize(fav, 'poker_hands'), hands.forehand and localize(hands.forehand, 'poker_hands') or '<none>' } }
	end,
	can_use = function(self, card)
		return jl.canuse()
	end,
	use = function(self, card, area, copier)
		local fav = jl.favhand()
		local hands = jl.adjacenthands(fav)
		local mod = G.GAME.hands[fav].level / 4
		if to_big(G.GAME.hands[fav].level) > to_big(0) then
			if hands.backhand then
				card:do_jen_astronomy(hands.backhand, mod)
				jl.th(hands.backhand)
				level_up_hand(card, hands.backhand, nil, mod)
			end
			if hands.forehand then
				card:do_jen_astronomy(hands.forehand, mod)
				jl.th(hands.forehand)
				level_up_hand(card, hands.forehand, nil, mod)
			end
		end
		jl.ch()
	end,
	bulk_use = function(self, card, area, copier, number)
		local fav = jl.favhand()
		local hands = jl.adjacenthands(fav)
		local mod = (G.GAME.hands[fav].level / 4) * number
		if to_big(G.GAME.hands[fav].level) > to_big(0) then
			if hands.backhand then
				card:do_jen_astronomy(hands.backhand, mod)
				jl.th(hands.backhand)
				level_up_hand(card, hands.backhand, nil, mod)
			end
			if hands.forehand then
				card:do_jen_astronomy(hands.forehand, mod)
				jl.th(hands.forehand)
				level_up_hand(card, hands.forehand, nil, mod)
			end
		end
		jl.ch()
	end
}

local namaka_data = {
	Tarot = G.C.SECONDARY_SET.Tarot,
	Planet = G.C.SECONDARY_SET.Planet,
	Spectral = G.C.SECONDARY_SET.Spectral,
	Code = HEX('14b341')
}

SMODS.Consumable {
	key = 'namaka',
	loc_txt = {
		name = 'Namaka',
		text = {
			'The number of {C:tarot}Tarots{}, {C:planet}Planets{}, {C:spectral}Spectrals{} or {C:code}Codes',
			'you have used throughout the run are',
			'{C:attention}applied as levels{} to {C:attention}four random {C:purple}poker hands',
			'{C:inactive}(The same hand can be picked multiple times)',
			'{C:inactive}({C:tarot}#1#{C:inactive}, {C:planet}#2#{C:inactive}, {C:spectral}#3#{C:inactive}, {C:code}#4#{C:inactive})',
			spriter('mailingway')
		}
	},
	set = 'Planet',
	set_card_type_badge = natsat,
	pos = { x = 0, y = 10 },
	cost = 5,
	unlocked = true,
	discovered = true,
	atlas = 'jenplanets',
	loc_vars = function(self, info_queue, center)
		local fav = jl.favhand()
		local hands = jl.adjacenthands(fav)
		return { vars = { jl.ctu('tarot'), jl.ctu('planet'), jl.ctu('spectral'), jl.ctu('code') } }
	end,
	can_use = function(self, card)
		return jl.canuse()
	end,
	use = function(self, card, area, copier)
		jl.ch()
		jl.hcm('', '')
		update_operator_display_custom(' ', G.C.WHITE)
		delay(1)
		for k, v in pairs(namaka_data) do
			local amt = jl.ctu(string.lower(k))
			update_operator_display_custom(k, v)
			delay(2)
			update_operator_display_custom('+' .. number_format(amt), v)
			delay(2)
			if to_big(amt) > to_big(0) then
				local sel = jl.rndhand(nil, 'jen_namaka_' .. string.lower(k))
				if (G.SETTINGS.FASTFORWARD or 0) < 1 then
					for i = 1, math.random(3, 6) do
						jl.th(G.handlist[math.random(#G.handlist)])
						delay(0.15)
					end
				end
				jl.th(sel)
				delay(1)
				level_up_hand(card, sel, nil, amt)
			else
				play_sound_q('timpani')
				update_operator_display_custom('Nope!', G.C.RED)
				delay(1)
			end
			delay(1)
		end
		jl.ch()
		update_operator_display()
	end,
	bulk_use = function(self, card, area, copier, number)
		jl.ch()
		jl.hcm('', '')
		update_operator_display_custom(' ', G.C.WHITE)
		delay(1)
		for i = 1, number do
			for k, v in pairs(namaka_data) do
				local amt = jl.ctu(string.lower(k))
				update_operator_display_custom(k, v)
				delay(2 / i)
				update_operator_display_custom('+' .. number_format(amt), v)
				delay(2 / i)
				if to_big(amt) > to_big(0) then
					local sel = jl.rndhand(nil, 'jen_namaka_' .. string.lower(k))
					if i == 1 and (G.SETTINGS.FASTFORWARD or 0) < 1 then
						for i = 1, math.random(3, 6) do
							jl.th(G.handlist[math.random(#G.handlist)])
							delay(0.15)
						end
					end
					jl.th(sel)
					delay(1 / i)
					level_up_hand(card, sel, nil, amt)
				else
					play_sound_q('timpani')
					update_operator_display_custom('Nope!', G.C.RED)
					delay(1)
				end
				delay(1 / i)
			end
		end
		jl.ch()
		update_operator_display()
	end
}


--UNO CONSUMABLES

local uno_data = {
	values = {
		'2', '3', '4', '5', '6', '7', '8', '9', '10', 'Jack', 'Queen', 'King', 'Ace'
	},
	colours = {
		Red = 'Hearts',
		Blue = 'Spades',
		Green = 'Clubs',
		Yellow = 'Diamonds'
	}
}

SMODS.Consumable {
	key = 'uno_uno',
	loc_txt = {
		name = 'UNO',
		text = {
			'Level up {C:attention}all ranks',
			'and {C:hearts}s{C:spades}u{C:clubs}i{C:diamonds}t{C:attention}s{} by {C:attention}1',
			spriter('jenwalter666')
		}
	},
	set = 'Spectral',
	pos = { x = 2, y = 4 },
	cost = 3,
	hidden = true,
	unlocked = true,
	discovered = true,
	soul_set = 'jen_uno',
	soul_rate = .05,
	atlas = 'jenuno',
	ignore_kudaai = true,
	can_use = function(self, card)
		return jl.canuse()
	end,
	can_mass_use = true,
	use = function(self, card, area, copier)
		delay(1)
		play_sound_q('jen_uno')
		jl.a('UNO!', 2, 1, G.C.MONEY)
		Q(function()
			if card then card:juice_up(0.8, 0.5) end
			return true
		end)
		delay(2)
		jl.h('All Ranks & Suits', '...', '...', '')
		delay(.5)
		if (G.SETTINGS.FASTFORWARD or 0) < 1 then
			G.E_MANAGER:add_event(Event({
				trigger = 'after',
				delay = 0.9,
				func = function()
					play_sound('tarot1')
					if card then card:juice_up(0.8, 0.5) end
					return true
				end
			}))
			jl.hc('+', true)
			G.E_MANAGER:add_event(Event({
				trigger = 'after',
				delay = 0.9,
				func = function()
					play_sound('tarot1')
					if card then card:juice_up(0.8, 0.5) end
					return true
				end
			}))
			jl.hm('+', true)
			Q(function()
				play_sound('tarot1')
				if card then card:juice_up(0.8, 0.5) end
				return true
			end, 0.9, nil, 'after')
			jl.hlv('+1')
			play_sound_q('button', 0.9, 0.7)
		else
			Q(function()
				play_sound('tarot1')
				if card then card:juice_up(0.8, 0.5) end
				return true
			end, 0.9, nil, 'after')
			jl.h('All Ranks & Suits', '+', '+', '+1', true)
		end
		delay(1)
		for a, b in ipairs(uno_data.values) do
			level_up_rank(card, b, true, 1)
		end
		for c, d in pairs(uno_data.colours) do
			level_up_suit(card, d, true, 1)
		end
		jl.ch()
	end,
	bulk_use = function(self, card, area, copier, number)
		delay(1)
		play_sound_q('jen_uno')
		jl.a('UNO!', 2, 1, G.C.MONEY)
		Q(function()
			if card then card:juice_up(0.8, 0.5) end
			return true
		end)
		delay(2)
		jl.h('All Ranks & Suits', '...', '...', '')
		delay(.5)
		if (G.SETTINGS.FASTFORWARD or 0) < 1 then
			Q(function()
				play_sound('tarot1')
				if card then card:juice_up(0.8, 0.5) end
				return true
			end, 0.2, nil, 'after')
			jl.hc('+', true)
			Q(function()
				play_sound('tarot1')
				if card then card:juice_up(0.8, 0.5) end
				return true
			end, 0.2, nil, 'after')
			jl.hm('+', true)
			Q(function()
				play_sound('tarot1')
				if card then card:juice_up(0.8, 0.5) end
				return true
			end, 0.2, nil, 'after')
			jl.hlv('+' .. number)
			play_sound_q('button', 0.9, 0.7)
		else
			Q(function()
				play_sound('tarot1')
				if card then card:juice_up(0.8, 0.5) end
				return true
			end, 0.2, nil, 'after')
			jl.h('All Ranks & Suits', '+', '+', '+' .. number, true)
		end
		delay(1)
		for a, b in ipairs(uno_data.values) do
			level_up_rank(card, b, true, number)
		end
		for c, d in pairs(uno_data.colours) do
			level_up_suit(card, d, true, number)
		end
		jl.ch()
	end
}

for a, b in ipairs(uno_data.values) do
	for c, d in pairs(uno_data.colours) do
		SMODS.Consumable {
			key = 'uno_' .. string.lower(c) .. string.lower(b),
			loc_txt = {
				name = c .. ' ' .. b,
				text = {
					'Level up {C:attention}' .. b .. 's{} and {C:' .. string.lower(d) .. '}' .. d,
					'{C:attention}' .. b .. 's{C:inactive} | {V:1}lvl.#1#{} : {X:chips,C:white}+#2#{} & {X:mult,C:white}+#3#',
					'{C:' .. string.lower(d) .. '}' .. d .. '{C:inactive} | {V:2}lvl.#4#{} : {X:chips,C:white}+#5#{} & {X:mult,C:white}+#6#',
					spriter('jenwalter666')
				}
			},
			set = 'jen_uno',
			pos = { x = (a - 1) % 10, y = (d == 'Hearts' and 0 or d == 'Spades' and 1 or d == 'Clubs' and 2 or d == 'Diamonds' and 3 or 0) + (a > 10 and 5 or 0) },
			cost = b == 'Ace' and 3 or 2,
			unlocked = true,
			discovered = true,
			atlas = 'jenuno',
			ignore_kudaai = true,
			can_mass_use = true,
			loc_vars = function(self, info_queue, center)
				if not G.GAME or not (G.GAME or {}).suits or not (G.GAME or {}).ranks then
					return {
						vars = {
							1,
							Jen.config.rank_leveling[b].chips,
							Jen.config.rank_leveling[b].mult,
							1,
							Jen.config.suit_leveling[d].chips,
							Jen.config.suit_leveling[d].mult,
							colours = {
								G.C.UI.TEXT_DARK,
								G.C.UI.TEXT_DARK
							}
						},
					}
				end
				return {
					vars = {
						G.GAME.ranks[b].level,
						G.GAME.ranks[b].l_chips,
						G.GAME.ranks[b].l_mult,
						G.GAME.suits[d].level,
						G.GAME.suits[d].l_chips,
						G.GAME.suits[d].l_mult,
						colours = {
							G.GAME.ranks[b].level <= to_big(7200) and
							G.C.HAND_LEVELS['!' .. number_format(G.GAME.ranks[b].level)] or
							G.C.HAND_LEVELS[number_format(G.GAME.ranks[b].level)] or G.C.UI.TEXT_DARK,
							G.GAME.suits[d].level <= to_big(7200) and
							G.C.HAND_LEVELS['!' .. number_format(G.GAME.suits[d].level)] or
							G.C.HAND_LEVELS[number_format(G.GAME.suits[d].level)] or G.C.UI.TEXT_DARK
						}
					},
				}
			end,
			can_use = function(self, card)
				return jl.canuse()
			end,
			use = function(self, card, area, copier)
				level_up_rank(card, b, nil, 1, true)
				level_up_suit(card, d, nil, 1)
			end,
			bulk_use = function(self, card, area, copier, number)
				level_up_rank(card, b, nil, number, true)
				level_up_suit(card, d, nil, number)
			end
		}
	end
end

for k, v in pairs(uno_data.colours) do
	SMODS.Consumable {
		key = 'uno_' .. string.lower(k) .. 'drawtwo',
		loc_txt = {
			name = k .. ' Draw Two',
			text = {
				'Creates {C:attention}2 {C:' .. string.lower(v) .. '}' .. k,
				'{C:attention}numerical {C:uno}UNO{} cards',
				mayoverflow,
				spriter('jenwalter666')
			}
		},
		set = 'jen_uno',
		pos = { x = 3, y = k == 'Red' and 5 or k == 'Blue' and 6 or k == 'Green' and 7 or k == 'Yellow' and 8 or 5 },
		cost = 4,
		unlocked = true,
		discovered = true,
		atlas = 'jenuno',
		ignore_kudaai = true,
		can_mass_use = true,
		can_use = function(self, card)
			return jl.canuse()
		end,
		use = function(self, card, area, copier)
			if not card.already_used_once then
				card.already_used_once = true
				for i = 1, 2 do
					G.E_MANAGER:add_event(Event({
						trigger = 'after',
						delay = 0.4,
						func = function()
							play_sound('jen_draw')
							local card2 = create_card('Consumeables', G.consumeables, nil, nil, nil, nil,
								'c_jen_uno_' ..
								string.lower(k) ..
								string.lower(pseudorandom_element(uno_data.values,
									pseudoseed('unodrawtwo_' .. string.lower(k)))), 'unodrawtwo_' .. string.lower(k))
							--[[if card.edition then
								card2:set_edition(card.edition, true)
							end]]
							card2:add_to_deck()
							G.consumeables:emplace(card2)
							card:juice_up(0.3, 0.5)
							return true
						end
					}))
				end
				Q(function()
					Q(function()
						if card then card.already_used_once = nil end
						return true
					end)
					return true
				end)
				delay(0.6)
			end
		end,
		bulk_use = function(self, card, area, copier, number)
			if not card.already_used_once then
				local quota = 2 * number
				card.already_used_once = true
				if quota > 40 then
					for i = 1, quota do
						local card2 = create_card('Consumeables', G.consumeables, nil, nil, nil, nil,
							'c_jen_uno_' ..
							string.lower(k) ..
							string.lower(pseudorandom_element(uno_data.values,
								pseudoseed('unodrawtwo' .. string.lower(k)))), 'unodrawtwo_' .. string.lower(k))
						--[[if card.edition then
							card2:set_edition(card.edition, true)
						end]]
						card2:add_to_deck()
						G.consumeables:emplace(card2)
						card:juice_up(0.3, 0.5)
					end
				else
					for i = 1, quota do
						Q(function()
							play_sound('jen_draw')
							local card2 = create_card('Consumeables', G.consumeables, nil, nil, nil, nil,
								'c_jen_uno_' ..
								string.lower(k) ..
								string.lower(pseudorandom_element(uno_data.values,
									pseudoseed('unodrawtwo' .. string.lower(k)))), 'unodrawtwo_' .. string.lower(k))
							--[[if card.edition then
									card2:set_edition(card.edition, true)
								end]]
							card2:add_to_deck()
							G.consumeables:emplace(card2)
							card:juice_up(0.3, 0.5)
							return true
						end, 0.4, nil, 'after')
					end
				end
				Q(function()
					Q(function()
						if card then card.already_used_once = nil end
						return true
					end)
					return true
				end)
				delay(0.6)
			end
		end
	}

	SMODS.Consumable {
		key = 'uno_' .. string.lower(k) .. 'skip',
		loc_txt = {
			name = k .. ' Skip',
			text = {
				'{C:' .. string.lower(v) .. '}' .. v .. '{C:red} siphons{} up to{C:attention} half a level',
				'from {C:attention}all{} of the {C:attention}other{} suits',
				spriter('jenwalter666')
			}
		},
		set = 'jen_uno',
		pos = { x = 4, y = k == 'Red' and 5 or k == 'Blue' and 6 or k == 'Green' and 7 or k == 'Yellow' and 8 or 5 },
		cost = 4,
		unlocked = true,
		discovered = true,
		atlas = 'jenuno',
		ignore_kudaai = true,
		can_mass_use = true,
		can_use = function(self, card)
			return jl.canuse()
		end,
		use = function(self, card, area, copier)
			jl.h('Other Ranks & Suits', '...', '...', '')
			if (G.SETTINGS.FASTFORWARD or 0) < 1 then
				Q(function()
					play_sound('tarot1')
					if card then card:juice_up(0.8, 0.5) end
					return true
				end, 0.9, nil, 'after')
				jl.hc('-', true)
				Q(function()
					play_sound('tarot1')
					if card then card:juice_up(0.8, 0.5) end
					return true
				end, 0.9, nil, 'after')
				jl.hm('-', true)
				Q(function()
					play_sound('tarot1')
					if card then card:juice_up(0.8, 0.5) end
					return true
				end, 0.9, nil, 'after')
				jl.hlv('-0~0.5')
				play_sound_q('button', 0.9, 0.7)
			else
				Q(function()
					play_sound('tarot1')
					if card then card:juice_up(0.8, 0.5) end
					return true
				end, 0.9, nil, 'after')
				jl.h('Other Ranks & Suits', '-', '-', '-0~0.5', true)
			end
			delay(1.3)
			local siphoned = to_big(0)
			for a, b in pairs(uno_data.colours) do
				if b ~= v then
					local to_siphon = to_big(math.max(0, math.min(G.GAME.suits[b].level, 0.5)))
					siphoned = siphoned + to_siphon
					level_up_suit(card, b, true, -to_siphon)
				end
			end
			level_up_suit(card, v, nil, siphoned)
		end,
		bulk_use = function(self, card, area, copier, number)
			jl.h('Other Ranks & Suits', '...', '...', '')
			if (G.SETTINGS.FASTFORWARD or 0) < 1 then
				G.E_MANAGER:add_event(Event({
					trigger = 'after',
					delay = 0.9,
					func = function()
						play_sound('tarot1')
						if card then card:juice_up(0.8, 0.5) end
						return true
					end
				}))
				jl.hc('-', true)
				G.E_MANAGER:add_event(Event({
					trigger = 'after',
					delay = 0.9,
					func = function()
						play_sound('tarot1')
						if card then card:juice_up(0.8, 0.5) end
						return true
					end
				}))
				jl.hm('-', true)
				G.E_MANAGER:add_event(Event({
					trigger = 'after',
					delay = 0.9,
					func = function()
						play_sound('tarot1')
						if card then card:juice_up(0.8, 0.5) end
						return true
					end
				}))
				jl.hlv('-0~' .. (number / 2))
				play_sound_q('button', 0.9, 0.7)
			else
				Q(function()
					play_sound('tarot1')
					if card then card:juice_up(0.8, 0.5) end
					return true
				end, 0.9, nil, 'after')
				jl.h('Other Ranks & Suits', '-', '-', '-0~' .. (number / 2), true)
			end
			delay(1.3)
			local siphoned = to_big(0)
			for a, b in pairs(uno_data.colours) do
				if b ~= v then
					local to_siphon = to_big(math.max(0, math.min(G.GAME.suits[b].level, number / 2)))
					siphoned = siphoned + to_siphon
					level_up_suit(card, b, true, -to_siphon)
				end
			end
			level_up_suit(card, v, nil, siphoned)
		end
	}

	SMODS.Consumable {
		key = 'uno_' .. string.lower(k) .. 'reverse',
		loc_txt = {
			name = k .. ' Reverse',
			text = {
				'Swap the level of {C:' .. string.lower(v) .. '}' .. v,
				'with the level of the {C:attention}highest',
				'level among the {C:attention}other suits{},',
				'then {C:attention}level up both suits by 1',
				spriter('jenwalter666')
			}
		},
		set = 'jen_uno',
		pos = { x = 5, y = k == 'Red' and 5 or k == 'Blue' and 6 or k == 'Green' and 7 or k == 'Yellow' and 8 or 5 },
		cost = 4,
		unlocked = true,
		discovered = true,
		atlas = 'jenuno',
		ignore_kudaai = true,
		can_mass_use = true,
		can_use = function(self, card)
			return jl.canuse()
		end,
		use = function(self, card, area, copier)
			local selected = v
			local highest = to_big(0)
			for a, b in pairs(uno_data.colours) do
				if b ~= v then
					if G.GAME.suits[b].level > highest then
						highest = G.GAME.suits[b].level
						selected = b
					end
				end
			end
			delay(.5)
			local level1 = G.GAME.suits[v].level
			local level2 = G.GAME.suits[selected].level
			if level1 ~= level2 then
				Q(function()
					card:juice_up(0.3, 0.5); play_sound('tarot1'); return true
				end)
				delay(.25)
				play_sound_q('jen_misc1')
				card:speak('Swapped!')
				level_up_suit(card, v, nil, level2 - level1, true)
				level_up_suit(card, selected, nil, level1 - level2, true)
				Q(function()
					card:juice_up(0.3, 0.5); play_sound('tarot2'); return true
				end)
			else
				card:speak('No change!')
				Q(function()
					card:juice_up(0.3, 0.5); play_sound('tarot1'); return true
				end)
			end
			delay(.25)
			play_sound_q('jen_misc1', 1.15)
			level_up_suit(card, selected, nil, 1, true)
			level_up_suit(card, v, nil, 1)
		end,
		bulk_use = function(self, card, area, copier, number)
			local selected = v
			local highest = to_big(0)
			for a, b in pairs(uno_data.colours) do
				if b ~= v then
					if G.GAME.suits[b].level > highest then
						highest = G.GAME.suits[b].level
						selected = b
					end
				end
			end
			delay(.5)
			local level1 = G.GAME.suits[v].level
			local level2 = G.GAME.suits[selected].level
			if level1 ~= level2 and number / 2 ~= math.ceil(number / 2) then
				Q(function()
					card:juice_up(0.3, 0.5); play_sound('tarot1'); return true
				end)
				delay(.25)
				play_sound_q('jen_misc1')
				card:speak('Swapped!')
				level_up_suit(card, v, nil, level2 - level1, true)
				level_up_suit(card, selected, nil, level1 - level2, true)
				Q(function()
					card:juice_up(0.3, 0.5); play_sound('tarot2'); return true
				end)
			else
				card:speak('No change!')
				Q(function()
					card:juice_up(0.3, 0.5); play_sound('tarot1'); return true
				end)
			end
			delay(.25)
			play_sound_q('jen_misc1', 1.15)
			level_up_suit(card, selected, nil, number, true)
			level_up_suit(card, v, nil, number)
		end
	}
end

SMODS.Consumable {
	key = 'uno_wild',
	loc_txt = {
		name = 'Wild',
		text = {
			'Level up {C:attention}all {C:hearts}s{C:spades}u{C:clubs}i{C:diamonds}t{C:attention}s',
			'by {C:attention}#1#{}, plus {C:attention}another #1#',
			'for {C:attention}each playing card',
			'in deck that {C:attention}has the relative suit',
			'{C:inactive}({C:hearts}#2#{C:inactive}, {C:spades}#3#{C:inactive}, {C:clubs}#4#{C:inactive}, {C:diamonds}#5#{C:inactive})',
			spriter('jenwalter666')
		}
	},
	config = { levels = 0.1 },
	set = 'jen_uno',
	pos = { x = 0, y = 4 },
	cost = 3,
	unlocked = true,
	discovered = true,
	atlas = 'jenuno',
	ignore_kudaai = true,
	can_mass_use = true,
	loc_vars = function(self, info_queue, center)
		local suits = jl.countsuit()
		if type(suits) ~= 'table' then suits = {} end
		return { vars = { ((center or {}).ability or {}).levels or 0.1, suits.Hearts or 0, suits.Spades or 0, suits.Clubs or 0, suits.Diamonds or 0 } }
	end,
	can_use = function(self, card)
		return jl.canuse()
	end,
	use = function(self, card, area, copier)
		for k, v in pairs(jl.countsuit()) do
			level_up_suit(card, k, nil, v * card.ability.levels, true)
		end
		jl.ch()
	end,
	bulk_use = function(self, card, area, copier, number)
		for k, v in pairs(jl.countsuit()) do
			level_up_suit(card, k, nil, v * card.ability.levels * number, true)
		end
		jl.ch()
	end
}

SMODS.Consumable {
	key = 'uno_drawfour',
	loc_txt = {
		name = 'Wild Draw Four',
		text = {
			'Create {C:attention}4{} random {C:uno}UNO{}',
			'cards and level up {C:attention}all {C:hearts}s{C:spades}u{C:clubs}i{C:diamonds}t{C:attention}s',
			'by {C:attention}#1#{}, plus {C:attention}another #1#',
			'for {C:attention}each playing card',
			'in deck that {C:attention}has the relative suit',
			'{C:inactive}({C:hearts}#2#{C:inactive}, {C:spades}#3#{C:inactive}, {C:clubs}#4#{C:inactive}, {C:diamonds}#5#{C:inactive})',
			mayoverflow,
			spriter('jenwalter666')
		}
	},
	config = { levels = 0.05 },
	set = 'jen_uno',
	pos = { x = 1, y = 4 },
	cost = 5,
	unlocked = true,
	discovered = true,
	atlas = 'jenuno',
	ignore_kudaai = true,
	can_mass_use = true,
	loc_vars = function(self, info_queue, center)
		local suits = jl.countsuit()
		if type(suits) ~= 'table' then suits = {} end
		return { vars = { ((center or {}).ability or {}).levels or 0.05, suits.Hearts or 0, suits.Spades or 0, suits.Clubs or 0, suits.Diamonds or 0 } }
	end,
	can_use = function(self, card)
		return jl.canuse()
	end,
	use = function(self, card, area, copier)
		for k, v in pairs(jl.countsuit()) do
			level_up_suit(card, k, nil, v * card.ability.levels, true)
		end
		jl.ch()
		if not card.already_used_once then
			card.already_used_once = true
			for i = 1, 4 do
				G.E_MANAGER:add_event(Event({
					trigger = 'after',
					delay = 0.4,
					func = function()
						play_sound('jen_draw')
						local card2 = create_card('jen_uno', G.consumeables, nil, nil, nil, nil, nil, 'unodrawfour')
						--[[if card.edition then
								card2:set_edition(card.edition, true)
							end]]
						card2:add_to_deck()
						G.consumeables:emplace(card2)
						card:juice_up(0.3, 0.5)
						return true
					end
				}))
			end
			Q(function()
				Q(function()
					if card then card.already_used_once = nil end
					return true
				end)
				return true
			end)
			delay(0.6)
		end
	end,
	bulk_use = function(self, card, area, copier, number)
		for k, v in pairs(jl.countsuit()) do
			level_up_suit(card, k, nil, v * card.ability.levels * number, true)
		end
		if not card.already_used_once then
			card.already_used_once = true
			for i = 1, 4 * number do
				Q(function()
					play_sound('jen_draw')
					local card2 = create_card('jen_uno', G.consumeables, nil, nil, nil, nil, nil, 'unodrawfour')
					--[[if card.edition then
								card2:set_edition(card.edition, true)
							end]]
					card2:add_to_deck()
					G.consumeables:emplace(card2)
					card:juice_up(0.3, 0.5)
					return true
				end, 0.4, nil, 'after')
			end
			Q(function()
				Q(function()
					if card then card.already_used_once = nil end
					return true
				end)
				return true
			end)
			delay(0.6)
		end
		jl.ch()
	end
}

SMODS.Consumable {
	key = 'uno_wild_paint',
	loc_txt = {
		name = 'Wild Paint',
		text = {
			'Level up {C:attention}all {C:hearts}s{C:spades}u{C:clubs}i{C:diamonds}t{C:attention}s',
			'by {C:attention}#1#{}, plus {C:attention}another #1#',
			'for {C:attention}each playing card',
			'in deck that {C:attention}has the relative suit{},',
			'and create a {C:attention}Draw Two{} of relative colours',
			'for {C:attention}every 2 occurrences{} of that suit',
			'{C:inactive}({C:hearts}#2#{C:inactive}, {C:spades}#3#{C:inactive}, {C:clubs}#4#{C:inactive}, {C:diamonds}#5#{C:inactive})',
			spriter('jenwalter666')
		}
	},
	config = { levels = 0.01 },
	set = 'Spectral',
	pos = { x = 3, y = 4 },
	cost = 5,
	hidden = true,
	unlocked = true,
	discovered = true,
	soul_set = 'jen_uno',
	atlas = 'jenuno',
	ignore_kudaai = true,
	can_mass_use = true,
	loc_vars = function(self, info_queue, center)
		local suits = jl.countsuit()
		if type(suits) ~= 'table' then suits = {} end
		return { vars = { ((center or {}).ability or {}).levels or 0.01, suits.Hearts or 0, suits.Spades or 0, suits.Clubs or 0, suits.Diamonds or 0 } }
	end,
	can_use = function(self, card)
		return jl.canuse()
	end,
	use = function(self, card, area, copier)
		for k, v in pairs(jl.countsuit()) do
			level_up_suit(card, k, nil, v * card.ability.levels, true)
			if v / 2 > 1 then
				Q(function()
					play_sound('jen_draw')
					local card2 = create_card('Consumeables', G.consumeables, nil, nil, nil, nil,
						'c_jen_uno_' .. suit_to_uno(k) .. 'drawtwo', 'uno_paint')
					if math.floor(v / 2) > 1 then
						card2:setQty(math.floor(v / 2))
						card2:create_stack_display()
					end
					card2:add_to_deck()
					G.consumeables:emplace(card2)
					card:juice_up(0.3, 0.5)
					return true
				end, 0.4, nil, 'after')
			end
			delay(0.6)
		end
		jl.ch()
	end,
	bulk_use = function(self, card, area, copier, number)
		for k, v in pairs(jl.countsuit()) do
			level_up_suit(card, k, nil, v * card.ability.levels * number, true)
			if v / 2 > 1 then
				Q(function()
					play_sound('jen_draw')
					local card2 = create_card('Consumeables', G.consumeables, nil, nil, nil, nil,
						'c_jen_uno_' .. suit_to_uno(k) .. 'drawtwo', 'uno_paint')
					card2:setQty(math.floor(v / 2) * number)
					card2:create_stack_display()
					card2:add_to_deck()
					G.consumeables:emplace(card2)
					card:juice_up(0.3, 0.5)
					return true
				end, 0.4, nil, 'after')
			end
			delay(0.6)
		end
		jl.ch()
	end
}

SMODS.Consumable {
	key = 'uno_null',
	loc_txt = {
		name = 'Null',
		text = {
			'Does nothing',
			spriter('jenwalter666')
		}
	},
	set = 'jen_uno',
	pos = { x = 9, y = 9 },
	cost = 1,
	unlocked = true,
	discovered = true,
	atlas = 'jenuno',
	can_mass_use = true,
	in_pool = function() return false end,
	can_use = function(self, card)
		return jl.canuse()
	end,
	use = function(self, card, area, copier)
	end,
	bulk_use = function(self, card, area, copier, number)
	end
}

--OMEGA CONSUMABLES

local omegaconsumables = {
	'ankh',
	'aura',
	'black_hole',
	'ceres',
	'chariot',
	'cryptid',
	'death',
	'deja_vu',
	'devil',
	'earth',
	'ectoplasm',
	'emperor',
	'empress',
	'eris',
	'familiar',
	'fool',
	'grim',
	'hanged_man',
	'hermit',
	'hex',
	'hierophant',
	'high_priestess',
	'immolate',
	'incantation',
	'judgement',
	'jupiter',
	'justice',
	'lovers',
	'magician',
	'mars',
	'medium',
	'mercury',
	'moon',
	'neptune',
	'ouija',
	'planet_x',
	'pluto',
	'saturn',
	'sigil',
	'soul',
	'star',
	'strength',
	'sun',
	'talisman',
	'temperance',
	'tower',
	'trance',
	'uranus',
	'venus',
	'wheel_of_fortune',
	'world',
	'wraith'
}

local omegaplanets = {
	{
		n = 'Pluto',
		c = 'pluto',
		h = 'High Card',
		y = 9
	},
	{
		n = 'Mercury',
		c = 'mercury',
		h = 'Pair',
		y = 6
	},
	{
		n = 'Uranus',
		c = 'uranus',
		h = 'Two Pair',
		y = 11
	},
	{
		n = 'Venus',
		c = 'venus',
		h = 'Three of a Kind',
		y = 12
	},
	{
		n = 'Saturn',
		c = 'saturn',
		h = 'Straight',
		y = 10
	},
	{
		n = 'Jupiter',
		c = 'jupiter',
		h = 'Flush',
		y = 4
	},
	{
		n = 'Earth',
		c = 'earth',
		h = 'Full House',
		y = 2
	},
	{
		n = 'Mars',
		c = 'mars',
		h = 'Four of a Kind',
		y = 5
	},
	{
		n = 'Neptune',
		c = 'neptune',
		h = 'Straight Flush',
		y = 7
	},
	{
		n = 'Planet X',
		c = 'planet_x',
		h = 'Five of a Kind',
		y = 8
	},
	{
		n = 'Ceres',
		c = 'ceres',
		h = 'Flush House',
		y = 1
	},
	{
		n = 'Eris',
		c = 'eris',
		h = 'Flush Five',
		y = 3
	}
}

for k, v in pairs(omegaplanets) do
	SMODS.Consumable {
		key = v.c .. '_omega',
		loc_txt = {
			name = v.n .. ' {C:dark_edition}Omega',
			text = {
				'{C:attention,s:1.5,E:1}' .. v.h .. '',
				' ',
				'{C:attention}Triples {C:chips}Chips{}, {C:chips}Level Chips{}, {C:mult}Mult{}, and {C:mult}Level Mult{},',
				'and then {C:attention}doubles{} current {C:planet}level'
			}
		},
		set = 'jen_omegaconsumable',
		pos = { x = 0, y = v.y },
		soul_pos = { x = 1, y = v.y },
		cost = 15,
		no_doe = true,
		aurinko = true,
		unlocked = true,
		discovered = true,
		gloss = true,
		soul_rate = 0,
		atlas = 'jenomegaplanets',
		hidden = true,
		hidden2 = true,
		can_stack = true,
		can_divide = true,
		can_bulk_use = true,
		can_mass_use = true,
		can_use = function(self, card)
			return jl.canuse()
		end,
		use = function(self, card, area, copier)
			local hand = v.h
			update_operator_display_custom('Per Lv.', G.C.WHITE)
			update_hand_text({ sound = 'button', volume = 0.7, pitch = 0.8, delay = 0.3 },
				{
					handname = localize(hand, 'poker_hands'),
					chips = G.GAME.hands[hand].l_chips,
					mult = G.GAME.hands
						[hand].l_mult,
					level = G.GAME.hands[hand].level
				})
			G.GAME.hands[hand].l_chips = G.GAME.hands[hand].l_chips * 3
			G.GAME.hands[hand].l_mult = G.GAME.hands[hand].l_mult * 3
			Q(function()
				play_sound('jen_boost1', 1, 0.4)
				card:juice_up(0.8, 0.5)
				return true
			end, 1, nil, 'after')
			update_hand_text({ delay = 1 }, { chips = 'x3', StatusText = true })
			Q(function()
				play_sound('jen_boost2', 1, 0.4)
				card:juice_up(0.8, 0.5)
				return true
			end, 1, nil, 'after')
			update_hand_text({ delay = 1 }, { mult = 'x3', StatusText = true })
			update_hand_text({ sound = 'button', volume = 0.7, pitch = 1, delay = 1 },
				{ chips = G.GAME.hands[hand].l_chips, mult = G.GAME.hands[hand].l_mult })
			delay(2)
			update_operator_display()
			update_hand_text({ sound = 'button', volume = 0.7, pitch = 0.8, delay = 1 },
				{ chips = G.GAME.hands[hand].chips, mult = G.GAME.hands[hand].mult })
			G.GAME.hands[hand].chips = G.GAME.hands[hand].chips * 3
			G.GAME.hands[hand].mult = G.GAME.hands[hand].mult * 3
			Q(function()
				play_sound('jen_boost3', 1, 0.4)
				card:juice_up(0.8, 0.5)
				return true
			end, 1, nil, 'after')
			update_hand_text({ delay = 1 }, { chips = 'x3', StatusText = true })
			Q(function()
				play_sound('jen_boost4', 1, 0.4)
				card:juice_up(0.8, 0.5)
				return true
			end, 1, nil, 'after')
			update_hand_text({ delay = 1 }, { mult = 'x3', StatusText = true })
			update_hand_text({ sound = 'button', volume = 0.7, pitch = 1, delay = 1 },
				{ chips = G.GAME.hands[hand].chips, mult = G.GAME.hands[hand].mult })
			level_up_hand(card, hand, false, G.GAME.hands[hand].level)
			jl.ch()
		end,
		bulk_use = function(self, card, area, copier, number)
			local hand = v.h
			local factor = to_big(3) ^ number
			update_operator_display_custom('Per Lv.', G.C.WHITE)
			update_hand_text({ sound = 'button', volume = 0.7, pitch = 0.8, delay = 0.3 },
				{
					handname = localize(hand, 'poker_hands'),
					chips = G.GAME.hands[hand].l_chips,
					mult = G.GAME.hands
						[hand].l_mult,
					level = G.GAME.hands[hand].level
				})
			G.GAME.hands[hand].l_chips = G.GAME.hands[hand].l_chips * factor
			G.GAME.hands[hand].l_mult = G.GAME.hands[hand].l_mult * factor
			Q(function()
				play_sound('jen_boost1', 1, 0.4)
				card:juice_up(0.8, 0.5)
				return true
			end, 1, nil, 'after')
			update_hand_text({ delay = 0.3 }, { chips = 'x' .. number_format(factor), StatusText = true })
			Q(function()
				play_sound('jen_boost2', 1, 0.4)
				card:juice_up(0.8, 0.5)
				return true
			end, 1, nil, 'after')
			update_hand_text({ delay = 0.3 }, { mult = 'x' .. number_format(factor), StatusText = true })
			update_hand_text({ sound = 'button', volume = 0.7, pitch = 1, delay = 1 },
				{ chips = G.GAME.hands[hand].l_chips, mult = G.GAME.hands[hand].l_mult })
			delay(2)
			update_operator_display()
			update_hand_text({ sound = 'button', volume = 0.7, pitch = 0.8, delay = 1 },
				{ chips = G.GAME.hands[hand].chips, mult = G.GAME.hands[hand].mult })
			G.GAME.hands[hand].chips = G.GAME.hands[hand].chips * 3
			G.GAME.hands[hand].mult = G.GAME.hands[hand].mult * 3
			Q(function()
				play_sound('jen_boost3', 1, 0.4)
				card:juice_up(0.8, 0.5)
				return true
			end, 1, nil, 'after')
			update_hand_text({ delay = 0.3 }, { chips = 'x' .. number_format(factor), StatusText = true })
			Q(function()
				play_sound('jen_boost4', 1, 0.4)
				card:juice_up(0.8, 0.5)
				return true
			end, 1, nil, 'after')
			update_hand_text({ delay = 0.3 }, { mult = 'x' .. number_format(factor), StatusText = true })
			update_hand_text({ sound = 'button', volume = 0.7, pitch = 1, delay = 1 },
				{ chips = G.GAME.hands[hand].chips, mult = G.GAME.hands[hand].mult })
			level_up_hand(card, hand, false,
				G.GAME.hands[hand].level * (number <= 1 and number or (2 ^ number)) -
				(number <= 1 and 0 or G.GAME.hands[hand].level))
			jl.ch()
		end
	}
end

SMODS.Consumable {
	key = 'black_hole_omega',
	loc_txt = {
		name = '{C:dark_edition}Sagittarius A*',
		text = {
			'{C:attention}Nonuples {C:chips}Chips{}, {C:chips}Level Chips{}, {C:mult}Mult{}, and {C:mult}Level Mult{},',
			'and then {C:attention}quadruples{} current {C:planet}level{} of {C:purple}all poker hands'
		}
	},
	set = 'jen_omegaconsumable',
	pos = { x = 0, y = 0 },
	soul_pos = { x = 1, y = 0 },
	cost = 15,
	soul_rate = 0,
	fusable = true,
	no_doe = true,
	unlocked = true,
	discovered = true,
	atlas = 'jenomegaplanets',
	gloss = true,
	hidden = true,
	hidden2 = true,
	can_stack = true,
	can_divide = true,
	can_bulk_use = true,
	can_mass_use = true,
	can_use = function(self, card)
		return jl.canuse()
	end,
	use = function(self, card, area, copier)
		update_operator_display_custom('Per Lv.', G.C.WHITE)
		jl.th('all')
		Q(function()
			play_sound('jen_boost1', 1, 0.4)
			card:juice_up(0.8, 0.5)
			return true
		end, 1, nil, 'after')
		update_hand_text({ delay = 1 }, { chips = 'x9', StatusText = true })
		Q(function()
			play_sound('jen_boost2', 1, 0.4)
			card:juice_up(0.8, 0.5)
			return true
		end, 1, nil, 'after')
		update_hand_text({ delay = 1 }, { mult = 'x9', StatusText = true })
		update_hand_text({ sound = 'button', volume = 0.7, pitch = 1, delay = 1 }, { chips = '+++', mult = '+++' })
		delay(2)
		update_operator_display()
		update_hand_text({ sound = 'button', volume = 0.7, pitch = 0.8, delay = 1 }, { chips = '...', mult = '...' })
		Q(function()
			play_sound('jen_boost3', 1, 0.4)
			card:juice_up(0.8, 0.5)
			return true
		end, 1, nil, 'after')
		update_hand_text({ delay = 1 }, { chips = 'x9', StatusText = true })
		Q(function()
			play_sound('jen_boost4', 1, 0.4)
			card:juice_up(0.8, 0.5)
			return true
		end, 1, nil, 'after')
		update_hand_text({ delay = 1 }, { mult = 'x9', StatusText = true })
		update_hand_text({ sound = 'button', volume = 0.7, pitch = 1, delay = 1 }, { chips = '+++', mult = '+++' })
		update_hand_text({ sound = 'button', volume = 0.7, pitch = 1, delay = 1 }, { level = 'x4' })
		for k, v in pairs(G.handlist) do
			local hand = v
			G.GAME.hands[hand].l_chips = G.GAME.hands[hand].l_chips * 9
			G.GAME.hands[hand].l_mult = G.GAME.hands[hand].l_mult * 9
			G.GAME.hands[hand].chips = G.GAME.hands[hand].chips * 9
			G.GAME.hands[hand].mult = G.GAME.hands[hand].mult * 9
			level_up_hand(card, hand, true, G.GAME.hands[hand].level * 3)
		end
		jl.ch()
	end,
	bulk_use = function(self, card, area, copier, number)
		local factor = to_big(9) ^ number
		update_operator_display_custom('Per Lv.', G.C.WHITE)
		jl.th('all')
		Q(function()
			play_sound('jen_boost1', 1, 0.4)
			card:juice_up(0.8, 0.5)
			return true
		end, 1, nil, 'after')
		update_hand_text({ delay = 1 }, { chips = 'x' .. number_format(factor), StatusText = true })
		Q(function()
			play_sound('jen_boost2', 1, 0.4)
			card:juice_up(0.8, 0.5)
			return true
		end, 1, nil, 'after')
		update_hand_text({ delay = 1 }, { mult = 'x' .. number_format(factor), StatusText = true })
		update_hand_text({ sound = 'button', volume = 0.7, pitch = 1, delay = 1 }, { chips = '+++', mult = '+++' })
		delay(2)
		update_operator_display()
		update_hand_text({ sound = 'button', volume = 0.7, pitch = 0.8, delay = 1 }, { chips = '...', mult = '...' })
		Q(function()
			play_sound('jen_boost3', 1, 0.4)
			card:juice_up(0.8, 0.5)
			return true
		end, 1, nil, 'after')
		update_hand_text({ delay = 1 }, { chips = 'x' .. number_format(factor), StatusText = true })
		Q(function()
			play_sound('jen_boost4', 1, 0.4)
			card:juice_up(0.8, 0.5)
			return true
		end, 1, nil, 'after')
		update_hand_text({ delay = 1 }, { mult = 'x' .. number_format(factor), StatusText = true })
		update_hand_text({ sound = 'button', volume = 0.7, pitch = 1, delay = 1 }, { chips = '+++', mult = '+++' })
		update_hand_text({ sound = 'button', volume = 0.7, pitch = 1, delay = 1 },
			{ level = 'x' .. number_format(4 ^ number) })
		for k, v in pairs(G.handlist) do
			local hand = v
			G.GAME.hands[hand].l_chips = G.GAME.hands[hand].l_chips * factor
			G.GAME.hands[hand].l_mult = G.GAME.hands[hand].l_mult * factor
			G.GAME.hands[hand].chips = G.GAME.hands[hand].chips * factor
			G.GAME.hands[hand].mult = G.GAME.hands[hand].mult * factor
			level_up_hand(card, hand, true,
				(G.GAME.hands[hand].level * (number <= 1 and 4 or (4 ^ number))) - G.GAME.hands[hand].level)
		end
		jl.ch()
	end
}

SMODS.Consumable {
	key = 'ankh_omega',
	set = 'jen_omegaconsumable',
	loc_txt = {
		name = 'Ankh {C:dark_edition}Omega',
		text = {
			'Create {C:attention}4{} copies',
			'of a {C:attention}selected Joker',
			'{C:inactive}(Chooses randomly if no Joker is chosen)',
			'{C:inactive}(Does not require room, but may overflow)'
		}
	},
	pos = { x = 0, y = 0 },
	soul_pos = { x = 1, y = 0 },
	cost = 20,
	soul_rate = 0,
	unlocked = true,
	discovered = true,
	no_doe = true,
	hidden = true,
	hidden2 = true,
	gloss = true,
	atlas = 'jenomegaspectrals',
	can_use = function(self, card)
		return jl.canuse() and #((G.jokers or {}).cards or {}) > 0
	end,
	use = function(self, card, area, copier)
		local joker = G.jokers.highlighted[1]
		if not joker then
			joker = G.jokers.cards[pseudorandom('ankhexrandom', 1, #G.jokers.cards)]
		end
		if joker then
			for i = 1, 4 do
				local ankhcard = copy_card(joker)
				ankhcard:start_materialize()
				ankhcard:add_to_deck()
				G.jokers:emplace(ankhcard)
			end
		end
	end,
	bulk_use = function(self, card, area, copier, number)
		local joker = G.jokers.highlighted[1]
		if not joker then
			joker = G.jokers.cards[pseudorandom('ankhexrandom', 1, #G.jokers.cards)]
		end
		if joker then
			for i = 1, 4 * number do
				local ankhcard = copy_card(joker)
				ankhcard:start_materialize()
				ankhcard:add_to_deck()
				G.jokers:emplace(ankhcard)
			end
		end
	end
}

SMODS.Consumable {
	key = 'aura_omega',
	set = 'jen_omegaconsumable',
	loc_txt = {
		name = 'Aura {C:dark_edition}Omega',
		text = {
			'Apply a random {C:cry_exotic}Exotic Edition',
			'to any {C:attention}selected Joker{} and/or to',
			'{C:attention}any number{} of {C:attention}selected playing cards',
			'{C:inactive}(Can overwrite editions)'
		}
	},
	pos = { x = 0, y = 1 },
	soul_pos = { x = 1, y = 1 },
	cost = 20,
	soul_rate = 0,
	unlocked = true,
	discovered = true,
	no_doe = true,
	hidden = true,
	hidden2 = true,
	gloss = true,
	atlas = 'jenomegaspectrals',
	can_use = function(self, card)
		return jl.canuse() and (#G.jokers.highlighted + #G.hand.highlighted) > 0 and #G.jokers.highlighted <= 1
	end,
	use = function(self, card, area, copier)
		local joker = G.jokers.highlighted[1]
		if joker then
			joker:set_edition({ [exotic_editions[pseudorandom('auraexrandom', 1, #exotic_editions)]] = true })
		end
		if #G.hand.highlighted > 0 then
			for k, v in pairs(G.hand.highlighted) do
				v:set_edition({ [exotic_editions[pseudorandom('auraexrandom', 1, #exotic_editions)]] = true })
			end
		end
	end
}

SMODS.Consumable {
	key = 'cryptid_omega',
	set = 'jen_omegaconsumable',
	loc_txt = {
		name = 'Cryptid {C:dark_edition}Omega',
		text = {
			'Create {C:attention}20{} copies of',
			'{C:attention}any number{} of {C:attention}selected playing cards'
		}
	},
	pos = { x = 0, y = 2 },
	soul_pos = { x = 1, y = 2 },
	cost = 20,
	soul_rate = 0,
	unlocked = true,
	discovered = true,
	no_doe = true,
	hidden = true,
	hidden2 = true,
	gloss = true,
	atlas = 'jenomegaspectrals',
	can_use = function(self, card)
		return jl.canuse() and #G.hand.highlighted > (card.area == G.hand and 1 or 0)
	end,
	use = function(self, card, area, copier)
		if #G.hand.highlighted > 0 then
			for k, v in ipairs(G.hand.highlighted) do
				for i = 1, 20 do
					local cryptidcard = copy_card(v)
					cryptidcard:start_materialize()
					cryptidcard:add_to_deck()
					G.hand:emplace(cryptidcard)
					G.playing_card = (G.playing_card and G.playing_card + 1) or 1
					table.insert(G.playing_cards, cryptidcard)
				end
			end
		end
	end,
	bulk_use = function(self, card, area, copier, number)
		if #G.hand.highlighted > 0 then
			for k, v in ipairs(G.hand.highlighted) do
				for i = 1, 20 * number do
					local cryptidcard = copy_card(v)
					cryptidcard:start_materialize()
					cryptidcard:add_to_deck()
					G.hand:emplace(cryptidcard)
					G.playing_card = (G.playing_card and G.playing_card + 1) or 1
					table.insert(G.playing_cards, cryptidcard)
				end
			end
		end
	end
}

local exsealcards = {
	{
		n = 'Deja Vu',
		c = 'deja_vu',
		s = 'Red',
		y = 3
	},
	{
		n = 'Medium',
		c = 'medium',
		s = 'Purple',
		y = 10
	},
	{
		n = 'Talisman',
		c = 'talisman',
		s = 'Gold',
		y = 13
	},
	{
		n = 'Trance',
		c = 'trance',
		s = 'Blue',
		y = 14
	}
}

for k, v in pairs(exsealcards) do
	SMODS.Consumable {
		key = v.c .. '_omega',
		set = 'jen_omegaconsumable',
		loc_txt = {
			name = v.n .. ' {C:dark_edition}Omega',
			text = {
				'Apply a {C:attention}' .. v.s .. ' Seal{} to',
				'{C:attention}all playing cards{} you currently have'
			}
		},
		pos = { x = 0, y = v.y },
		soul_pos = { x = 1, y = v.y },
		cost = 20,
		soul_rate = 0,
		unlocked = true,
		discovered = true,
		no_doe = true,
		hidden = true,
		hidden2 = true,
		gloss = true,
		atlas = 'jenomegaspectrals',
		can_use = function(self, card)
			return jl.canuse()
		end,
		use = function(self, card, area, copier)
			if G.hand and G.hand.cards then
				for _, card in pairs(G.hand.cards) do
					card:set_seal(v.s, k > 50, k > 50)
				end
			end
			if G.deck and G.deck.cards then
				for _, card in pairs(G.deck.cards) do
					card:set_seal(v.s, true, true)
				end
			end
		end
	}
end

SMODS.Consumable {
	key = 'ectoplasm_omega',
	set = 'jen_omegaconsumable',
	loc_txt = {
		name = 'Ectoplasm {C:dark_edition}Omega',
		text = {
			'Apply {C:dark_edition}Negative{} to {C:attention}every Joker',
			'{C:inactive}(Overwrites any existing edition, except for Exotic+ editions)'
		}
	},
	pos = { x = 0, y = 4 },
	soul_pos = { x = 1, y = 4 },
	cost = 100,
	soul_rate = 0,
	unlocked = true,
	discovered = true,
	no_doe = true,
	hidden = true,
	hidden2 = true,
	gloss = true,
	atlas = 'jenomegaspectrals',
	can_use = function(self, card)
		return jl.canuse() and #((G.jokers or {}).cards or {}) > 0
	end,
	use = function(self, card, area, copier)
		for k, v in pairs(G.jokers.cards) do
			if not v:is_exotic_edition() then
				v.no_forced_edition = true
				v:set_edition({ negative = true }, k > 200, k > 200)
				v.no_forced_edition = nil
			end
		end
	end
}

SMODS.Consumable {
	key = 'familiar_omega',
	set = 'jen_omegaconsumable',
	loc_txt = {
		name = 'Familiar {C:dark_edition}Omega',
		text = {
			'Add a {C:attention}full set{} of {C:jen_RGB,E:1}Moire {C:attention}Kings{},',
			'{C:cry_exotic,E:1}Blood {C:attention}Queens{} and {C:cry_exotic,E:1}Bloodfoil {C:attention}Jacks',
			'to your deck'
		}
	},
	pos = { x = 0, y = 5 },
	soul_pos = { x = 1, y = 5 },
	cost = 100,
	soul_rate = 0,
	unlocked = true,
	discovered = true,
	no_doe = true,
	hidden = true,
	hidden2 = true,
	gloss = true,
	atlas = 'jenomegaspectrals',
	can_use = function(self, card)
		return jl.canuse()
	end,
	use = function(self, card, area, copier)
		createcardset('_K', nil, 'jen_moire', 1)
		createcardset('_Q', nil, 'jen_blood', 1)
		createcardset('_J', nil, 'jen_bloodfoil', 1)
	end,
	bulk_use = function(self, card, area, copier, number)
		createcardset('_K', nil, 'jen_moire', number)
		createcardset('_Q', nil, 'jen_blood', number)
		createcardset('_J', nil, 'jen_bloodfoil', number)
	end
}

SMODS.Consumable {
	key = 'grim_omega',
	set = 'jen_omegaconsumable',
	loc_txt = {
		name = 'Grim {C:dark_edition}Omega',
		text = {
			'Add two {C:attention}full sets{} of',
			'{C:jen_RGB,E:1}Moire {C:attention}Aces{} to your deck'
		}
	},
	pos = { x = 0, y = 6 },
	soul_pos = { x = 1, y = 6 },
	cost = 80,
	soul_rate = 0,
	unlocked = true,
	discovered = true,
	no_doe = true,
	hidden = true,
	hidden2 = true,
	gloss = true,
	atlas = 'jenomegaspectrals',
	can_use = function(self, card)
		return jl.canuse()
	end,
	use = function(self, card, area, copier)
		createcardset('_A', nil, 'jen_moire', 2)
	end,
	bulk_use = function(self, card, area, copier, number)
		createcardset('_A', nil, 'jen_moire', 2 * number)
	end
}

SMODS.Consumable {
	key = 'hex_omega',
	set = 'jen_omegaconsumable',
	loc_txt = {
		name = 'Hex {C:dark_edition}Omega',
		text = {
			'Apply a random {C:cry_exotic,E:1}Exotic Edition{} to',
			'a {C:green}random selection{} of {C:attention}half',
			'of your {C:attention}Jokers{} that {C:attention}do not already have',
			'an {C:cry_exotic,E:1}Exotic Edition'
		}
	},
	pos = { x = 0, y = 7 },
	soul_pos = { x = 1, y = 7 },
	cost = 150,
	soul_rate = 0,
	unlocked = true,
	discovered = true,
	no_doe = true,
	hidden = true,
	hidden2 = true,
	gloss = true,
	atlas = 'jenomegaspectrals',
	can_use = function(self, card)
		return jl.canuse()
	end,
	use = function(self, card, area, copier)
		local possible_selections = {}
		for k, v in pairs(G.jokers.cards) do
			if not v:is_exotic_edition() then
				table.insert(possible_selections, v)
			end
		end
		if #possible_selections > 0 then
			local selections = {}
			local toselect = math.ceil(#possible_selections / 2)
			local tries = 1e4
			local choice
			while toselect > 0 and tries > 0 do
				choice = possible_selections[pseudorandom('hex_omega_selection', 1, #possible_selections)]
				if not choice.selectedbyhexex then
					choice.selectedbyhexex = true
					table.insert(selections, choice)
					toselect = toselect - 1
				end
				tries = tries - 1
			end
			if #selections > 0 then
				for k, v in pairs(selections) do
					v:set_edition({ [exotic_editions[pseudorandom('hexexrandom', 1, #exotic_editions)]] = true })
				end
			else
				card_status_text(card, 'No targets!', nil, 0.05 * card.T.h, G.C.RED, nil, 0.6, nil, nil, 'bm', 'cancel',
					1, 0.9)
			end
		else
			card_status_text(card, 'No targets!', nil, 0.05 * card.T.h, G.C.RED, nil, 0.6, nil, nil, 'bm', 'cancel', 1,
				0.9)
		end
	end
}

SMODS.Consumable {
	key = 'immolate_omega',
	set = 'jen_omegaconsumable',
	loc_txt = {
		name = 'Immolate {C:dark_edition}Omega',
		text = {
			'Select {C:attention}any number{} of playing cards to {C:red}destroy{},',
			"For each destroyed card; {C:money}money{} is {C:attention}multiplied{} by {C:attention}R{},",
			"all hands {C:planet}level up{} by {X:green,C:white}3x{C:attention}R{},",
			"and increase Joker slots by {C:attention}R",
			'{C:inactive}(R = card rank)',
			'{C:inactive}(Stones are treated as a 2)'
		}
	},
	pos = { x = 0, y = 8 },
	soul_pos = { x = 1, y = 8 },
	cost = 200,
	soul_rate = 0,
	unlocked = true,
	discovered = true,
	no_doe = true,
	hidden = true,
	hidden2 = true,
	gloss = true,
	atlas = 'jenomegaspectrals',
	can_use = function(self, card)
		return jl.canuse() and #G.hand.highlighted > (card.area == G.hand and 1 or 0)
	end,
	use = function(self, card, area, copier)
		if #G.hand.highlighted > 0 then
			for k, v in pairs(G.hand.highlighted) do
				local rank = v:norank() and 2 or v:get_id()
				if rank >= 1 then
					ease_dollars(math.min(1e308, G.GAME.dollars * rank - G.GAME.dollars))
					G.E_MANAGER:add_event(Event({
						trigger = 'after',
						func = function()
							v:juice_up(0.5, 0.5)
							return true
						end
					}))
					delay(0.25)
					lvupallhands(rank * 3, v, true)
					delay(0.25)
					G.jokers:change_size_absolute(rank)
					delay(0.25)
					G.E_MANAGER:add_event(Event({
						trigger = 'after',
						func = function()
							v:start_dissolve()
							return true
						end
					}))
				end
			end
		end
	end
}

SMODS.Consumable {
	key = 'incantation_omega',
	set = 'jen_omegaconsumable',
	loc_txt = {
		name = 'Incantation {C:dark_edition}Omega',
		text = {
			'Add a {C:attention}full set{} of cards {C:attention}2{} through {C:attention}10',
			'to your deck, with {C:cry_exotic,E:1}Bloodfoil{} on {C:attention}odd ranks{} and {C:cry_exotic,E:1}Blood{} on {C:attention}even ranks'
		}
	},
	pos = { x = 0, y = 9 },
	soul_pos = { x = 1, y = 9 },
	cost = 175,
	soul_rate = 0,
	unlocked = true,
	discovered = true,
	no_doe = true,
	hidden = true,
	hidden2 = true,
	gloss = true,
	atlas = 'jenomegaspectrals',
	can_use = function(self, card)
		return jl.canuse()
	end,
	use = function(self, card, area, copier)
		createcardset('_2', nil, 'jen_blood', 1)
		createcardset('_3', nil, 'jen_bloodfoil', 1)
		createcardset('_4', nil, 'jen_blood', 1)
		createcardset('_5', nil, 'jen_bloodfoil', 1)
		createcardset('_6', nil, 'jen_blood', 1)
		createcardset('_7', nil, 'jen_bloodfoil', 1)
		createcardset('_8', nil, 'jen_blood', 1)
		createcardset('_9', nil, 'jen_bloodfoil', 1)
		createcardset('_T', nil, 'jen_blood', 1)
	end,
	bulk_use = function(self, card, area, copier, number)
		createcardset('_2', nil, 'jen_blood', number)
		createcardset('_3', nil, 'jen_bloodfoil', number)
		createcardset('_4', nil, 'jen_blood', number)
		createcardset('_5', nil, 'jen_bloodfoil', number)
		createcardset('_6', nil, 'jen_blood', number)
		createcardset('_7', nil, 'jen_bloodfoil', number)
		createcardset('_8', nil, 'jen_blood', number)
		createcardset('_9', nil, 'jen_bloodfoil', number)
		createcardset('_T', nil, 'jen_blood', number)
	end
}

SMODS.Consumable {
	key = 'ouija_omega',
	set = 'jen_omegaconsumable',
	loc_txt = {
		name = 'Ouija {C:dark_edition}Omega',
		text = {
			'Select {C:attention}any number{} of cards,',
			'all other cards whose rank',
			'{C:attention}does not match any of the selected cards',
			'will be removed and {C:money}sold',
			'{C:inactive}(Removes Diplopia from card before selling)'
		}
	},
	pos = { x = 0, y = 11 },
	soul_pos = { x = 1, y = 11 },
	cost = 175,
	soul_rate = 0,
	unlocked = true,
	discovered = true,
	no_doe = true,
	hidden = true,
	hidden2 = true,
	gloss = true,
	atlas = 'jenomegaspectrals',
	can_use = function(self, card)
		return jl.canuse() and #G.hand.highlighted > (card.area == G.hand and 1 or 0)
	end,
	use = function(self, card, area, copier)
		local targets = {}
		if #G.hand.highlighted > 0 then
			for k, v in pairs(G.playing_cards) do
				local safe = false
				if not v.highlighted then
					for a, b in pairs(G.hand.highlighted) do
						if b:get_id() == v:get_id() or (b:norank() and v:norank()) then
							safe = true
							break
						end
					end
				end
				if not safe and not v.highlighted then
					if v.edition and v.edition.jen_diplopia then
						v:set_edition(nil, true, true)
					end
					table.insert(targets, v)
				end
			end
		end
		if #targets > 0 then
			bulk_sell_cards(targets, true, true)
		end
	end
}

SMODS.Consumable {
	key = 'sigil_omega',
	set = 'jen_omegaconsumable',
	loc_txt = {
		name = 'Sigil {C:dark_edition}Omega',
		text = {
			'Select {C:attention}any number{} of cards,',
			'all other cards whose suit',
			'{C:attention}does not match any of the selected cards',
			'will be removed and {C:money}sold',
			'{C:inactive}(Ignores effect of Wilds; card\'s ACTUAL suit must match)',
			'{C:inactive}(Removes Diplopia from card before selling)'
		}
	},
	pos = { x = 0, y = 12 },
	soul_pos = { x = 1, y = 12 },
	soul_rate = 0,
	cost = 175,
	unlocked = true,
	discovered = true,
	no_doe = true,
	hidden = true,
	hidden2 = true,
	gloss = true,
	atlas = 'jenomegaspectrals',
	can_use = function(self, card)
		return jl.canuse() and #G.hand.highlighted > (card.area == G.hand and 1 or 0)
	end,
	use = function(self, card, area, copier)
		local targets = {}
		if #G.hand.highlighted > 0 then
			for k, v in pairs(G.playing_cards) do
				local safe = false
				if not v.highlighted then
					for a, b in pairs(G.hand.highlighted) do
						if (b:norank() and v:norank()) or b.base.suit == v.base.suit then
							safe = true
							break
						end
					end
				end
				if not safe and not v.highlighted then
					if v.edition and v.edition.jen_diplopia then
						v:set_edition(nil, true, true)
					end
					table.insert(targets, v)
				end
			end
		end
		if #targets > 0 then
			bulk_sell_cards(targets, true, true)
		end
	end
}

SMODS.Consumable {
	key = 'wraith_omega',
	set = 'jen_omegaconsumable',
	loc_txt = {
		name = 'Wraith {C:dark_edition}Omega',
		text = {
			'Create one of every {C:cry_epic,E:1}Epic{} and',
			'{C:legendary,E:1}Legendary {C:almanac,E:1}Jen\'s Almanac {C:attention}Joker',
			mayoverflow
		}
	},
	pos = { x = 0, y = 15 },
	soul_pos = { x = 1, y = 15 },
	cost = 175,
	soul_rate = 0,
	hidden = true,
	hidden2 = true,
	unlocked = true,
	discovered = true,
	no_doe = true,
	gloss = true,
	atlas = 'jenomegaspectrals',
	can_use = function(self, card)
		return jl.canuse()
	end,
	use = function(self, card, area, copier)
		for k, v in pairs(G.P_CENTERS) do
			if v.set == 'Joker' and string.sub(k, 1, 6) == 'j_jen_' and (tostring(v.rarity) == 'cry_epic' or (type(v.rarity) == 'number' and v.rarity == 4)) then
				local card2 = jl.card(v.key)
				card2:add_to_deck()
				G.jokers:emplace(card2)
			end
		end
	end
}

local omegaconsumables = {
	'world', 'sun', 'star', 'moon',
	'magician', 'empress', 'hierophant', 'lovers', 'chariot', 'justice', 'devil', 'tower'
}

SMODS.Consumable {
	key = 'fool_omega',
	set = 'jen_omegaconsumable',
	loc_txt = {
		name = 'The Fool {C:dark_edition}Omega',
		text = {
			'Create {C:attention}2{} random',
			'{C:red,E:1}Omega{} cards',
			'{C:inactive}(Excludes Balatro\'s Soul)',
			mayoverflow
		}
	},
	pos = { x = 0, y = 0 },
	soul_pos = { x = 1, y = 0 },
	cost = 175,
	soul_rate = 0,
	hidden = true,
	hidden2 = true,
	unlocked = true,
	discovered = true,
	no_doe = true,
	atlas = 'jenomegatarots',
	can_use = function(self, card)
		return jl.canuse()
	end,
	use = function(self, card, area, copier)
		local to_generate = 2
		local cntr
		while to_generate > 0 do
			cntr = ('c_jen_' .. pseudorandom_element(omegaconsumables, pseudoseed('fool_omega')) .. '_omega')
			while cntr == 'c_jen_soul_omega' do
				cntr = ('c_jen_' .. pseudorandom_element(omegaconsumables, pseudoseed('fool_omega')) .. '_omega')
			end
			if G.P_CENTERS[cntr] then
				local card2 = create_card('jen_omegaconsumable', G.consumeables, nil, nil, nil, nil, cntr, 'fool_omega')
				card2:add_to_deck()
				G.consumeables:emplace(card2)
				to_generate = to_generate - 1
			end
		end
	end
}

local omega_copyamount = 19
local enhancetarots_info = {
	{ b = 'magician',   o = 'The Magician',   c = 'Lucky', omega = 4 },
	{ b = 'empress',    o = 'The Empress',    c = 'Mult',  omega = 5 },
	{ b = 'hierophant', o = 'The Hierophant', c = 'Bonus', omega = 6 },
	{ b = 'lovers',     o = 'The Lovers',     c = 'Wild',  omega = 7 },
	{ b = 'chariot',    o = 'The Chariot',    c = 'Steel', omega = 8 },
	{ b = 'justice',    o = 'Justice',        c = 'Glass', omega = 9 },
	{ b = 'devil',      o = 'The Devil',      c = 'Gold',  omega = 10 },
	{ b = 'tower',      o = 'The Tower',      c = 'Stone', omega = 11 }
}

for k, v in ipairs(enhancetarots_info) do
	SMODS.Consumable {
		key = v.b .. '_omega',
		set = 'jen_omegaconsumable',
		loc_txt = {
			name = v.o .. ' {C:dark_edition}Omega',
			text = {
				'Select {C:attention}any number{} of cards to enhance to {C:attention}' .. v.c .. '{} cards,',
				'{C:red}destroy all other cards{} and {C:attention}duplicate the selected cards ' .. omega_copyamount .. ' times'
			}
		},
		pos = { x = 0, y = v.omega },
		soul_pos = { x = 1, y = v.omega },
		cost = 35,
		soul_rate = 0,
		hidden = true,
		hidden2 = true,
		unlocked = true,
		discovered = true,
		no_doe = true,
		atlas = 'jenomegatarots',
		can_use = function(self, card)
			return jl.canuse() and #G.hand.highlighted > (card.area == G.hand and 1 or 0)
		end,
		use = function(self, card, area, copier)
			local targets = {}
			for k, v in ipairs(G.playing_cards) do
				if not v.highlighted then v:destroy() end
			end
			delay(1)
			if #G.hand.highlighted > 0 then
				Q(function()
					play_sound('tarot1')
					card:juice_up(0.3, 0.5)
					return true
				end, 0.4, nil, 'after')
				for i = 1, #G.hand.highlighted do
					local CARD = G.hand.highlighted[i]
					table.insert(targets, CARD)
					local percent = 1.15 - (i - 0.999) / (#G.hand.highlighted - 0.998) * 0.3
					Q(function()
						CARD:flip(); play_sound('card1', percent); CARD:juice_up(0.3, 0.3); return true
					end, 0.15, nil, 'after')
				end
				delay(0.2)
				for i = 1, #G.hand.highlighted do
					local CARD = G.hand.highlighted[i]
					local percent = 0.85 + (i - 0.999) / (#G.hand.highlighted - 0.998) * 0.3
					Q(
						function()
							G.hand:remove_from_highlighted(CARD); CARD:flip(); CARD:set_ability(v.e, true, nil); play_sound(
								'tarot2', percent); CARD:juice_up(0.3, 0.3); return true
						end, 0.15, nil, 'after')
				end
			end
			Q(function()
				for k, v in ipairs(targets) do
					for i = 1, omega_copyamount do
						local dupe = copy_card(v)
						dupe:start_materialize()
						dupe:add_to_deck()
						G.hand:emplace(dupe)
						G.playing_card = (G.playing_card and G.playing_card + 1) or 1
						table.insert(G.playing_cards, dupe)
					end
				end
				return true
			end)
		end
	}
end

SMODS.Consumable {
	key = 'high_priestess_omega',
	set = 'jen_omegaconsumable',
	loc_txt = {
		name = 'The High Priestess {C:dark_edition}Omega',
		text = {
			'Every {C:attention}Joker{}, {C:attention}consumable{},',
			'and {C:attention}playing card{} will trigger',
			'as if they were {C:spectral}Black Holes'
		}
	},
	pos = { x = 0, y = 2 },
	soul_pos = { x = 1, y = 2 },
	cost = 200,
	soul_rate = 0,
	dangerous = true,
	hidden = true,
	hidden2 = true,
	unlocked = true,
	discovered = true,
	no_doe = true,
	atlas = 'jenomegatarots',
	can_use = function(self, card)
		return jl.canuse()
	end,
	use = function(self, card, area, copier)
		local uneditioned_lvups = not card.edition and 1 or 0
		if card.edition then
			lvupallhands(card:getQty(), card, true)
		end
		for k, v in ipairs(G.jokers.cards) do
			if v.edition then
				lvupallhands(1, v, true)
			else
				uneditioned_lvups = uneditioned_lvups + 1
			end
		end
		for k, v in ipairs(G.consumeables.cards) do
			if v.edition then
				lvupallhands(v:getQty(), v, true)
			else
				uneditioned_lvups = uneditioned_lvups + v:getQty()
			end
		end
		for k, v in ipairs(G.playing_cards) do
			if v.edition then
				lvupallhands(1, v, true)
			else
				uneditioned_lvups = uneditioned_lvups + 1
			end
		end
		if uneditioned_lvups > 0 then
			lvupallhands(uneditioned_lvups, nil, true)
		end
	end
}

SMODS.Consumable {
	key = 'emperor_omega',
	set = 'jen_omegaconsumable',
	loc_txt = {
		name = 'The Emperor {C:dark_edition}Omega',
		text = {
			'Create a random {C:cry_exotic,E:1}Exotic {C:attention}Joker',
			'for every {C:attention}King{} in your deck',
			'Temporarily create a {X:attention}Showman',
			'for the joker-creation process',
			mayoverflow
		}
	},
	pos = { x = 0, y = 4 },
	soul_pos = { x = 1, y = 4 },
	cost = 300,
	soul_rate = 0,
	hidden = true,
	hidden2 = true,
	unlocked = true,
	discovered = true,
	no_doe = true,
	atlas = 'jenomegatarots',
	can_use = function(self, card)
		return jl.canuse()
	end,
	use = function(self, card, area, copier)
		local showman = create_card('Joker', G.jokers, nil, nil, nil, nil, 'j_ring_master', 'tempshowman')
		showman.ability.eternal = true
		showman:add_to_deck()
		G.jokers:emplace(showman)
		local exotics_to_create = 0
		for k, v in ipairs(G.playing_cards) do
			if not v:norank() and v:get_id() == 13 then
				exotics_to_create = exotics_to_create + 1
			end
		end
		if exotics_to_create < 0 then exotics_to_create = 1 end
		for i = 1, exotics_to_create do
			G.E_MANAGER:add_event(Event({
				trigger = 'after',
				delay = 0.4,
				func = function()
					play_sound('timpani')
					local exotic = create_card('Joker', G.jokers, nil, "cry_exotic", nil, nil, nil, 'cry_gateway')
					exotic:add_to_deck()
					G.jokers:emplace(exotic)
					exotic:juice_up(0.3, 0.5)
					return true
				end
			}))
		end
		Q(function()
			showman:destroy()
			return true
		end)
	end
}

SMODS.Consumable {
	key = 'hermit_omega',
	set = 'jen_omegaconsumable',
	loc_txt = {
		name = 'The Hermit {C:dark_edition}Omega',
		text = {
			'Gain {X:money,C:dark_edition,s:1.25}+$^2{C:inactive,s:0.75} (+$#1#)'
		}
	},
	pos = { x = 0, y = 9 },
	soul_pos = { x = 1, y = 9 },
	cost = 50,
	soul_rate = 0,
	hidden = true,
	hidden2 = true,
	unlocked = true,
	discovered = true,
	no_doe = true,
	atlas = 'jenomegatarots',
	can_use = function(self, card)
		return jl.canuse()
	end,
	loc_vars = function(self, info_queue, center)
		return { vars = { ((G.GAME or {}).dollars or 0) ^ 2 } }
	end,
	use = function(self, card, area, copier)
		ease_dollars(G.GAME.dollars ^ 2)
	end
}

SMODS.Consumable {
	key = 'wheel_of_fortune_omega',
	set = 'jen_omegaconsumable',
	loc_txt = {
		name = 'The Wheel of Fortune {C:dark_edition}Omega',
		text = {
			'Create {C:dark_edition,s:1.5,E:1}#1#{} random {C:attention}consumables',
			'Temporarily create a {X:attention}Showman',
			'for the consumable-creation process',
			'{C:inactive}(Created cards cannot roll for OMEGA)'
		}
	},
	pos = { x = 0, y = 10 },
	soul_pos = { x = 1, y = 10 },
	cost = 50,
	soul_rate = 0,
	hidden = true,
	hidden2 = true,
	unlocked = true,
	discovered = true,
	no_doe = true,
	atlas = 'jenomegatarots',
	can_use = function(self, card)
		return jl.canuse()
	end,
	loc_vars = function(self, info_queue, center)
		return { vars = { (CFG and CFG.omega_wheel_count) or (Jen and Jen.config and Jen.config.omega_wheel_count) or 200 } }
	end,
	use = function(self, card, area, copier)
		local used_consumable = copier or card
		local showman = create_card('Joker', G.jokers, nil, nil, nil, nil, 'j_ring_master', 'tempshowman')
		showman.ability.eternal = true
		showman:add_to_deck()
		G.jokers:emplace(showman)
		Q(function()
			local count = (CFG and CFG.omega_wheel_count) or (Jen and Jen.config and Jen.config.omega_wheel_count) or 200
			local max_cap = 500 -- absolute safety ceiling (restored from previous 5000 test cap)
			for i = 1, math.min(count, max_cap) do
				G.E_MANAGER:add_event(Event({
					trigger = 'after',
					delay = 0.1,
					func = function()
						play_sound('timpani')
						local _card = create_card('Consumeables', G.consumables, nil, nil, nil, nil, nil, 'wofomega')
						_card.no_omega = true
						_card:add_to_deck()
						G.consumeables:emplace(_card)
						used_consumable:juice_up(0.3, 0.5)
						return true
					end
				}))
			end
			Q(function()
				showman:destroy()
				return true
			end)
			return true
		end)
	end
}

local suittarots_info = {
	{ b = 'world', s = 'Spades',   o = 0 },
	{ b = 'sun',   s = 'Hearts',   o = 1 },
	{ b = 'star',  s = 'Diamonds', o = 2 },
	{ b = 'moon',  s = 'Clubs',    o = 3 }
}

for kk, vv in pairs(suittarots_info) do
	SMODS.Consumable {
		key = vv.b .. '_omega',
		set = 'jen_omegaconsumable',
		loc_txt = {
			name = 'The ' .. string.upper(string.sub(vv.b, 1, 1)) .. string.sub(vv.b, 2, string.len(vv.b)) .. ' {C:dark_edition}Omega',
			text = {
				'Convert {C:attention}all {C:' .. string.lower(vv.s) .. '}' .. vv.s .. '{} in full deck',
				'into {C:cry_exotic,E:1}Exotic{} cards',
				'{C:inactive}(Does not consider Wilds, the actual suit must match)'
			}
		},
		pos = { x = 0, y = vv.o },
		soul_pos = { x = 1, y = vv.o },
		cost = 250,
		soul_rate = 0,
		hidden = true,
		hidden2 = true,
		unlocked = true,
		discovered = true,
		no_doe = true,
		atlas = 'jenomegatarots',
		can_use = function(self, card)
			return jl.canuse()
		end,
		use = function(self, card, area, copier)
			play_sound('jen_pop')
			for k, v in ipairs(G.playing_cards) do
				if v.base.suit == vv.s and not v:nosuit() then
					if v.area == G.hand then
						Q(
							function()
								v:set_ability(G.P_CENTERS['m_jen_exotic'])
								play_sound('jen_pop')
								v:juice_up(1, 0.5)
								return true
							end, 0.75)
					else
						v:set_ability(G.P_CENTERS['m_jen_exotic'])
					end
				end
			end
		end
	}
end

local randtext = { 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T',
	'U', 'V', 'W', 'X', 'Y', 'Z', ' ', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p',
	'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '+', '-', '?',
	'!', '$', '%', '[', ']', '(', ')' }

local function obfuscatedtext(length)
	local str = ''
	for i = 1, length do
		str = str .. randtext[math.random(#randtext)]
	end
	return str
end

function createfulldeck()
	for k, v in pairs(G.P_CARDS) do
		local card = create_card('Base', G.deck, nil, nil, nil, nil, nil, 'jen_soul_omega')
		card:set_base(v)
		card:add_to_deck()
		G.deck:emplace(card)
	end
end

SMODS.Consumable {
	key = 'soul_omega',
	set = 'jen_omegaconsumable',
	loc_txt = {
		name = '{C:red,s:3}Balatro\'s Soul',
		text = {
			'{C:red,s:5,E:1}?????'
		}
	},
	pos = { x = 0, y = 22 },
	soul_pos = { x = 1, y = 22, extra = { x = 2, y = 22 } },
	cost = 0,
	soul_rate = 0,
	gloss = true,
	hidden = true,
	hidden2 = true,
	unlocked = true,
	discovered = true,
	no_doe = true,
	atlas = 'jenomegatarots',
	can_use = function(self, card)
		return jl.canuse() and not ((G.GAME or {}).banned_keys or {}).c_jen_soul_omega and
			#SMODS.find_card('j_jen_kosmos', true) <= 0
	end,
	use = function(self, card, area, copier)
		if not G.GAME.banned_keys then G.GAME.banned_keys = {} end
		G.GAME.banned_keys.c_jen_soul_omega = true
		jl.rd(1)
		for i = 1, 60 do
			card_status_text(card, obfuscatedtext(math.random(6, 18)), nil, 0.05 * card.T.h, G.C.RED, 0.6, 2.5 - (i / 50),
				0.4, 0.4, 'bm', 'generic1')
		end
		Q(function()
			for k, v in pairs(G.jokers.cards) do
				v:destroy()
			end
			for k, v in pairs(G.consumeables.cards) do
				v:destroy()
			end
			for k, v in pairs(G.playing_cards) do
				v:destroy()
			end
			for k, v in pairs(G.GAME.tags) do
				v:remove()
			end
			return true
		end)
		jl.rd(3)
		if G.GAME.round_resets.ante > 2 then ease_ante(math.floor(-G.GAME.round_resets.ante / 4 * 3), true, true, true) end
		createfulldeck()
		jl.a('Baaaa.', G.SETTINGS.GAMESPEED, 1, G.C.RED)
		card.sell_cost = 0
		Q(function()
			local kosmos = create_card('Joker', G.jokers, nil, nil, nil, nil, 'j_jen_kosmos', 'thekingslayer')
			kosmos.ability.eternal = true
			kosmos:add_to_deck()
			G.jokers:emplace(kosmos)
			Q(function()
				G.jokers:set_size_absolute(1)
				set_dollars(4)
				return true
			end, 0.1, nil, 'after')
			G.consumeables:change_size_absolute(G.consumeables.config.card_limit)
			return true
		end, 1)
	end
}

--VOUCHERS

function Jen.hv(key, level)
	return G.GAME.used_vouchers['v_jen_' .. key .. (level == 13 and '_omega' or level)]
end

local vchrs = {
	colour = {
		depend = 'MoreFluff',
		n = 'Palettalium',
		p = { x = 5, y = 0 },
		tiers = 13,
		price = 5,
		increment = 3,
		multiplier = 1.1,
		tiers_desc = {
			{ --1
				'{C:attention}Playing ("CCD") {C:colourcard}Colour{} cards will',
				'{C:attention}gain a round{} when they score'
			},
			{ --2
				'{C:attention}Leftover rounds{} on used {C:colourcard}Colour{} cards',
				'are {C:attention}randomly redistributed{} to other {C:colourcard}Colour{} cards',
				' ',
				redeemprev
			},
			{ --3
				'{C:dark_edition}Polychrome {C:colourcard}Colour{} cards',
				'add {C:attention}half of their max rounds',
				'to {C:attention}all other {C:colourcard}Colour{} cards when used',
				' ',
				redeemprev
			},
			{ --4
				'{C:colourcard}Colour{} cards increase the {C:planet}level',
				'of {C:attention}all poker hands{} by the following equation when used:',
				'{X:attention,C:white}(Current Rounds / 2) + (Max Rounds / 4) + (Current Charges * 5)',
				' ',
				redeemprev
			},
			{ --5
				'At the end of round,',
				'{C:colourcard}Colour{} cards in the consumable tray',
				'{C:attention}gain a round{} for every {C:attention}round of progress they already have',
				' ',
				redeemprev
			},
			{ --6
				'At the end of round,',
				'{C:colourcard}Colour{} cards in the consumable tray',
				'{C:attention}gain progress equal to their maximum progress',
				' ',
				redeemprev
			},
			{ --7
				'Adds {C:attention}cycles{} to the end-of-round progression process',
				'of all {C:colourcard}Colour{} cards in the consumable tray, starting at {C:attention}one cycle',
				'Multiply number of cycles by {C:attention}the amount of progress{} they currently have {C:attention}plus one',
				' ',
				redeemprev
			},
			{ --8
				'Number of {C:attention}cycles{} from {C:attention}Palettalium VII',
				'is {C:attention}multiplied{} by the {C:colourcard}Colour{} card\'s',
				'{C:attention}maximum amount of progress',
				' ',
				redeemprev
			},
			{ --9
				'Number of {C:attention}cycles{} that {C:attention}Palettalium VII',
				'starts at is {C:attention}increased{} from one cycle to {C:attention}three cycles',
				' ',
				redeemprev
			},
			{ --10
				'Removes the {C:dark_edition}Polychrome',
				'requirement from {C:attention}Palettalium III',
				' ',
				redeemprev
			},
			{ --11
				'{C:colourcard}Colour{} cards add their',
				'{C:attention}current charges{} as {C:attention}rounds',
				'to {C:attention}all other {C:colourcard}Colour{} cards when used',
				' ',
				redeemprev
			},
			{ --12
				'{C:dark_edition}Negative {C:colourcard}Colour{} cards add',
				'rounds to {C:attention}all other {C:colourcard}Colour{} cards',
				'based on the following equation:',
				'{X:attention,C:white}((A+B+1)*(C+D+1))*(E^F)',
				'{C:inactive}A = Negative\'s maximum progress',
				'{C:inactive}B = Negative\'s current progress',
				'{C:inactive}C = Target\'s maximum progress',
				'{C:inactive}D = Target\'s current progress',
				'{C:inactive}E = Negative\'s current charges + 1',
				'{C:inactive}F = (Number of Colour cards / 10) + 1, max 1.5',
				'{C:inactive}Result is rounded up, max of 100,000 iterations per card',
				redeemprev
			},
			{ --Omega
				'{C:attention}Palettalium II through XII{} now',
				'trigger when {C:attention}adding {C:colourcard}Colours',
				'to the consumable tray',
				redeemprev
			},
		}
	},
	astronomy = {
		n = 'Astronomicon',
		p = { x = 3, y = 0 },
		tiers = 13,
		price = 10,
		increment = 3,
		multiplier = 1.15,
		tiers_desc = {
			{ --1
				'{C:attention}Specific-hand {C:planet}Planets{} will also',
				'upgrade {C:attention}adjacent{} poker hands',
				'{C:inactive}(ex. using Mercury to upgrade Pair will also upgrade High Card and Two Pair)'
			},
			{ --2
				'{C:attention}Specific-hand {C:planet}Planets{} will also',
				'upgrade {C:attention}non-adjacent{} poker hands by {C:attention}one-tenth',
				' ',
				redeemprev
			},
			{ --3
				'{C:attention}Specific-hand {C:planet}Planets{} will',
				'{C:attention}repeat{} for every held {C:planet}Planet{} consumable',
				'{C:inactive}(ex. using Mercury while there are 3 other Planet cards will level up Pair 3 extra times)',
				' ',
				redeemprev
			},
			{ --4
				'{C:attention}Specific-hand {C:planet}Planets{} will',
				'{C:attention}repeat at half strength{} for every held {C:attention}non-{C:planet}Planet{} consumable',
				'{C:inactive}(ex. using Mercury while there are 3 Spectrals will level up Pair 1.5 extra times)',
				' ',
				redeemprev
			},
			{ --5
				'{C:money}Selling{} any card that is',
				'{C:red}not{} a {C:dark_edition}Negative{}, a {C:planet}Planet{} and/or a {C:attention}playing card',
				'will generate a {C:planet}Planet{} card',
				mayoverflow,
				'{C:inactive}(Black Hole excluded)',
				' ',
				redeemprev
			},
			{ --6
				'{C:money}Selling{} any card will',
				'{C:planet}level up{} a {C:green}random',
				'{C:attention}discovered poker hand{} by',
				'a {C:attention}fourth{} of its {C:money}sell value',
				' ',
				redeemprev
			},
			{ --7
				'{C:attention}Removing cards{} in most ways',
				'will {C:planet}level up{} a {C:green}random',
				'{C:attention}discovered poker hand{} by',
				'an {C:attention}eighth{} of its {C:money}sell value',
				'{C:inactive}(Applies on top of Astronomicon VI)',
				' ',
				redeemprev
			},
			{ --8
				'Hand levelups are {C:attention}twice as strong',
				'{C:inactive}(ex. what would be 3 level-ups is now 6)',
				' ',
				redeemprev
			},
			{ --9
				'If a hand {C:red}levels down{} from a card that has an {C:dark_edition}edition{},',
				'that edition\'s effect is applied by the {C:attention}absolute value{} of the level change',
				'{C:inactive}(ex. if a Polychrome levels down a hand, it will still give {X:mult,C:white}x1.5{C:inactive} Mult instead of {X:mult,C:white}/1.5{C:inactive})',
				' ',
				redeemprev
			},
			{ --10
				'Hand levelups are {C:attention}five times as strong',
				'{C:inactive}(ex. what would be 3 level-ups is now 15)',
				' ',
				redeemprev
			},
			{ --11
				'Whenever hand levels are {C:red}lost{},',
				'{C:attention}25% of those levels{} are',
				'instead {C:attention}redirected to the most played hand',
				'{C:inactive}(Does not trigger joker effects or Astronomicon)',
				' ',
				redeemprev
			},
			{ --12
				'{C:attention}Most-played hand{} gains a {C:attention}10% dividend',
				'whenever {C:attention}any other hand{} levels up',
				'{C:inactive}(Does not trigger joker effects or Astronomicon)',
				'{C:attention}Astronomicon I and II{} now also',
				'extend to {C:attention}second-adjacent{} hands',
				' ',
				redeemprev
			},
			{ --Omega
				'Whenever a hand {C:attention}gains levels{},',
				'the hand that comes {C:attention}before{} it',
				'will {C:attention}upgrade by half of that amount',
				'if the amount is {C:attention}at least 1 or more',
				'{C:inactive}(ex. if Straight leveled up 4 times,',
				'{C:inactive}then Three of a Kind levels up 2 times, which',
				'{C:inactive}then levels up Two Pair 1 time, which',
				'{C:inactive}then levels up Pair 0.5 times, and stops there)',
				' ',
				redeemprev
			},
		}
	},
	singularity = {
		n = 'Singularium',
		p = { x = 6, y = 0 },
		tiers = 9,
		price = 10,
		increment = 5,
		multiplier = 1.15,
		tiers_desc = {
			{ --1
				'Create a {C:dark_edition}Negative {C:spectral}Black Hole',
				'when opening a {C:planet}Celestial Pack',
				mayoverflow
			},
			{ --2
				'Create a {C:dark_edition}Negative {C:spectral}Black Hole',
				'when a {C:attention}non-{C:dark_edition}Negative {C:planet}Planet{} is used',
				mayoverflow,
				redeemprev
			},
			{ --3
				'{C:spectral}Black Holes{} level up',
				'{C:attention}all suits and ranks{} as well',
				redeemprev
			},
			{ --4
				'{C:spectral}Black Holes{} are',
				'{C:attention}25 times{} as strong',
				redeemprev
			},
			{ --5
				'{C:spectral}Black Holes{} have a',
				'{C:green}10% chance{} to create',
				'a random {C:planet}Planet{} when used',
				'{C:inactive,s:0.8}(Limited to 100 successful rolls in a single stack)',
				mayoverflow,
				redeemprev
			},
			{ --6
				'{C:spectral}Black Holes{} are',
				'{C:attention}300 times{} as strong',
				'{C:inactive,s:0.8}(Overwrites Singularium IV)',
				redeemprev
			},
			{ --7
				'{C:spectral}Black Holes{} multiply',
				'{C:chips}Chips-per-Level{} and {C:mult}Mult-per-Level',
				'of all hands by {C:attention}2{} when used',
				redeemprev
			},
			{ --8
				'{C:attention}Singularium VII{} now',
				'applies to {C:attention}ranks and suits',
				redeemprev
			},
			{ --9
				'{C:attention}Singularium I and II{} create',
				'{C:attention}three times{} as many {C:spectral}Black Holes',
				redeemprev
			}
		}
	},
	reserve = {
		n = 'Reservia',
		p = { x = 7, y = 0 },
		tiers = 6,
		price = 6,
		increment = 8,
		multiplier = 1.2,
		tiers_desc = {
			{ --1
				'You may {C:attention}reserve {C:planet}Planets{} from',
				'{C:attention}Boosters{} and add them to',
				'your consumable tray without using them'
			},
			{ --2
				'You may {C:attention}reserve {C:tarot}Tarots{} from',
				'{C:attention}Boosters{} and add them to',
				'your consumable tray without using them',
				redeemprev
			},
			{ --3
				'You may {C:attention}reserve {C:spectral}Spectrals{} from',
				'{C:attention}Boosters{} and add them to',
				'your consumable tray without using them',
				redeemprev
			},
			{ --4
				'When using a {C:attention}Booster{} consumable,',
				'a {C:attention}copy of the used card',
				'is added to your consumable tray',
				mayoverflow,
				redeemprev
			},
			{ --5
				'When using a {C:attention}Booster{} consumable,',
				'there is a {C:green}~33.33% chance',
				'that a {C:attention}new random card of the same type',
				'will appear in the {C:attention}Booster{} choices and',
				'{C:attention}not subtract 1{} from the number of choices you can choose',
				redeemprev
			},
			{ --6
				'{C:attention}Reservia IV{} now also gives a',
				'{C:attention}random consumable of the same type',
				mayoverflow,
				redeemprev
			}
		}
	}
}

local cor = Card.open
function Card:open()
	if self.ability.set == "Booster" and string.find(string.lower(self.ability.name), 'celestial') and Jen.hv('singularity', 1) then
		Q(function()
			local card2 = create_card('Spectral', G.consumeables, nil, nil, nil, nil, 'c_black_hole',
				'singularity1_blackhole')
			card2.no_omega = true
			if Jen.hv('singularity', 9) then
				card2:setQty(3)
				card2:create_stack_display()
			end
			card2:set_edition({ negative = true }, true)
			play_sound('jen_draw')
			card2:add_to_deck()
			G.consumeables:emplace(card2)
			return true
		end)
	end
	return cor(self)
end

for k, v in pairs(vchrs) do
	if not v.depend or (SMODS.Mods[v.depend] or {}).can_load then
		for i = 1, math.min(v.tiers, 13) do
			local RED = {}
			if i > 1 then
				RED[1] = 'v_jen_' .. k .. i - 1
			else
				RED = nil
			end
			SMODS.Voucher {
				key = k .. (i == 13 and '_omega' or i),
				loc_txt = {
					name = v.n .. ' ' .. (i == 13 and 'Omega' or roman(i)),
					text = v.tiers_desc[i]
				},
				pos = { x = 0, y = i == 13 and 14 or 0 },
				soul_pos = { x = v.p.x, y = v.p.y, extra = { x = 0, y = i } },
				cost = math.ceil((v.price + (v.increment * (i - 1))) * (i == 13 and 3 or 1) * ((v.multiplier or 1) ^ (i - 1))),
				unlocked = true,
				discovered = true,
				autoredeem = RED,
				atlas = 'jenvouchers',
				in_pool = function() return (((G.GAME or {}).round_resets or {}).ante or 0) > (i - 2) end
			}
		end
	end
end

local crr = Card.redeem --local catr = Card.apply_to_run
function Card:redeem()  --Card:apply_to_run(center)
	crr(self)           --catr(self, center)
	if self and self.gc and self:gc().autoredeem then
		for k, v in ipairs(self:gc().autoredeem) do
			if not G.GAME.used_vouchers[v] then
				jl.voucher(v) --Q(function() jl.voucher(v) return true end)
			end
		end
	end
end

local function chance_for_omega(is_soul)
	if is_soul and type(is_soul) == 'string' then
		is_soul = (is_soul or '') == 'soul'
	end
	local chance = (Jen.config.omega_chance * (is_soul and Jen.config.soul_omega_mod or 1)) - 1
	if #SMODS.find_card('j_jen_apollo') > 0 then
		for _, claunecksmentor in ipairs(SMODS.find_card('j_jen_apollo')) do
			if is_soul then
				chance = chance /
					(((claunecksmentor.ability.omegachance_amplifier < Jen.config.soul_omega_mod and 1 or 0) + claunecksmentor.ability.omegachance_amplifier) / Jen.config.soul_omega_mod)
			else
				chance = chance / claunecksmentor.ability.omegachance_amplifier
			end
		end
	end
	if G.GAME and G.GAME.obsidian then chance = chance / 2 end
	return chance + 1
end

local omegas_found = 0

local ccr = create_card

function create_card(_type, area, legendary, _rarity, skip_materialize, soulable, forced_key, key_append)
	local card = ccr(_type, area, legendary, _rarity, skip_materialize, soulable, forced_key, key_append)
	if G.STAGE ~= G.STAGES.MAIN_MENU and card.gc then
		local cen = card:gc()
		for k, v in ipairs(omegaconsumables) do
			if cen.key == ('c_' .. v) and G.P_CENTERS['c_jen_' .. v .. '_omega'] and not G.GAME.banned_keys['c_jen_' .. v .. '_omega'] and jl.chance('omega_replacement', chance_for_omega(v), true) then
				G.E_MANAGER:add_event(Event({
					trigger = 'after',
					blockable = false,
					blocking = false,
					func = function()
						if card and not card.no_omega then
							card:set_ability(G.P_CENTERS['c_jen_' .. v .. '_omega'])
							card:set_cost()
							if chance_for_omega(v) > 10 then play_sound('jen_omegacard', 1, 0.4) end
							card:juice_up(1.5, 1.5)
							if omegas_found <= 0 then
								Q(function()
									play_sound_q('jen_chime', 1, 0.65); jl.a(
										'Omega!' .. (omegas_found > 1 and (' x ' .. number_format(omegas_found)) or ''),
										G.SETTINGS.GAMESPEED, 1, G.C.jen_RGB); jl.rd(1); omegas_found = 0; return true
								end)
							end
							omegas_found = omegas_found + 1
						end
						return true
					end
				}))
				break
			end
		end
	end
	return card
end

local csar = Card.set_ability

function Card:set_ability(center, initial, delay_sprites)
	if self and self.gc then
		if self.added_to_deck and self:gc().unchangeable and not self.jen_ignoreunchangeable then
			return false
		end
	end
	-- Ensure we always pass a valid center to the original setter to avoid leaving
	-- `self.ability` nil (which causes crashes in UI code that indexes it).
	local safe_center = center
	if not safe_center then
		safe_center = (G and G.P_CENTERS and G.P_CENTERS['c_base']) or nil
	end
	if not safe_center then
		-- As a last resort, create a minimal fallback center stub.
		safe_center = {
			set = 'Default',
			name = '',
			effect = '',
			consumeable = false,
			unlocked = true,
			pos = { x = 0, y = 0 },
		}
	end
	csar(self, safe_center, initial, delay_sprites)
	if #SMODS.find_card('j_jen_ratau') > 0 and self.gc and self:gc().key ~= 'c_base' and string.sub(self:gc().key, 1, 2) == 'c_' and not self:gc().no_ratau then
		local mod = 1
		for k, ratsmakemecrazy in pairs(SMODS.find_card('j_jen_ratau')) do
			mod = mod * (ratsmakemecrazy.ability.modifier or 3)
		end
		local tbl = { min = mod, max = mod }
		Cryptid.misprintize(self, tbl, nil, true)
	end
end

--OVERRIDES AND OTHER FUNCTIONS

local gigo = Game.init_game_object
function Game:init_game_object()
	local ret = gigo(self)
	for _, suit in ipairs(SMODS.Suit.obj_buffer) do
		ret.suits[suit] = {
			level = to_big(1),
			chips = to_big(0),
			mult = to_big(0),
			l_chips = to_big((Jen.config.suit_leveling[suit] or {}).chips or 0),
			l_mult = to_big((Jen.config.suit_leveling[suit] or {}).mult or 0)
		}
	end
	for _, rank in ipairs(SMODS.Rank.obj_buffer) do
		ret.ranks[rank] = {
			level = to_big(1),
			chips = to_big(0),
			mult = to_big(0),
			l_chips = to_big((Jen.config.rank_leveling[rank] or {}).chips or 0),
			l_mult = to_big((Jen.config.rank_leveling[rank] or {}).mult or 0)
		}
	end
	return ret
end

local cgcb = Card.get_chip_bonus
function Card:get_chip_bonus()
	if self.debuff then return to_big(0) end
	local ret = cgcb(self)
	if G.GAME.suits[self.base.suit] and self.ability.effect ~= 'Stone Card' and not self:nosuit() then
		ret = ret + G.GAME.suits[self.base.suit].chips
	end
	if G.GAME.ranks[self.base.value] and self.ability.effect ~= 'Stone Card' and not self:norank() then
		ret = ret + G.GAME.ranks[self.base.value].chips
	end
	return ret
end

local cgcm = Card.get_chip_mult
function Card:get_chip_mult()
	if self.debuff then return to_big(0) end
	local ret = cgcm(self)
	if G.GAME.suits[self.base.suit] and self.ability.effect ~= 'Stone Card' and not self:nosuit() then
		ret = ret + G.GAME.suits[self.base.suit].mult
	end
	if G.GAME.ranks[self.base.value] and self.ability.effect ~= 'Stone Card' and not self:norank() then
		ret = ret + G.GAME.ranks[self.base.value].mult
	end
	return ret
end

--USER INTERFACE
function is_valid_suit_rank(s, r)
	return (not SMODS.Ranks[r].in_pool or SMODS.Ranks[r]:in_pool({ suit = s })) and
		(not SMODS.Suits[s].in_pool or SMODS.Suits[s]:in_pool({ rank = r }))
end

function prune_valid_suits()
	local suits = {}
	for i = 1, #SMODS.Suit.obj_buffer do
		local v = SMODS.Suit.obj_buffer[i]
		if is_valid_suit_rank(v, G.suitrank.rank) then
			table.insert(suits, v)
		end
	end
	return suits
end

function prune_valid_ranks()
	local ranks = {}
	for i = 1, #SMODS.Rank.obj_buffer do
		local v = SMODS.Rank.obj_buffer[i]
		if is_valid_suit_rank(G.suitrank.suit, v) then
			table.insert(ranks, v)
		end
	end
	return ranks
end

function G.FUNCS.inc_sr_suit()
	local suits = prune_valid_suits()
	-- Find current suit position
	local pos = 0
	for i = 1, #suits do
		if suits[i] == G.suitrank.suit then
			pos = i
			break
		end
	end
	G.suitrank.suit = suits[(pos % #suits) + 1]
	recalc_suitrank()
end

function G.FUNCS.dec_sr_suit()
	local suits = prune_valid_suits()
	-- Find current suit position
	local pos = 0
	for i = 1, #suits do
		if suits[i] == G.suitrank.suit then
			pos = i
			break
		end
	end
	G.suitrank.suit = suits[(pos - 2) % #suits + 1]
	recalc_suitrank()
end

function G.FUNCS.inc_sr_rank()
	local ranks = prune_valid_ranks()
	-- Find current rank position
	local pos = 0
	for i = 1, #ranks do
		if ranks[i] == G.suitrank.rank then
			pos = i
			break
		end
	end
	G.suitrank.rank = ranks[(pos % #ranks) + 1]
	recalc_suitrank()
end

function G.FUNCS.dec_sr_rank()
	local ranks = prune_valid_ranks()
	-- Find current rank position
	local pos = 0
	for i = 1, #ranks do
		if ranks[i] == G.suitrank.rank then
			pos = i
			break
		end
	end
	G.suitrank.rank = ranks[(pos - 2) % #ranks + 1]
	recalc_suitrank()
end

local ckpu = Controller.key_press_update
function Controller:key_press_update(key, dt)
	if Cryptid.safe_get(G, "suitrank", "card") then
		if key == 'left' or key == 'a' then
			G.FUNCS.dec_sr_suit()
		elseif key == 'right' or key == 'd' then
			G.FUNCS.inc_sr_suit()
		elseif key == 'down' or key == 's' then
			G.FUNCS.dec_sr_rank()
		elseif key == 'up' or key == 'w' then
			G.FUNCS.inc_sr_rank()
		end
	end
	return ckpu(self, key, dt)
end

function recalc_suitrank()
	SMODS.change_base(G.suitrank.card, G.suitrank.suit, G.suitrank.rank)
	G.suitrank.suitconfig.name = localize(G.suitrank.suit, 'suits_plural')
	G.suitrank.rankconfig.name = localize(G.suitrank.rank, 'ranks')
	for _, k in pairs({ "color", "outline_color", "level_color", "text_color" }) do
		if not G.suitrank.suitconfig[k] then
			G.suitrank.suitconfig[k] = {}
		end
		if not G.suitrank.rankconfig[k] then
			G.suitrank.rankconfig[k] = {}
		end
	end
	for i = 1, 4 do
		G.suitrank.suitconfig.color[i] = G.C.SUITS[G.suitrank.suit][i]
		G.suitrank.suitconfig.outline_color[i] = darken(G.C.SUITS[G.suitrank.suit], 0.3)[i]
		G.suitrank.suitconfig.level_color[i] = G.C.HAND_LEVELS[number_format(G.GAME.suits[G.suitrank.suit].level)][i]
		G.suitrank.suitconfig.text_color[i] = lighten(G.C.SUITS[G.suitrank.suit], 0.6)[i]
		G.suitrank.rankconfig.color[i] = darken(G.C.SECONDARY_SET.Tarot, 0.3)[i]
		G.suitrank.rankconfig.outline_color[i] = darken(G.C.SECONDARY_SET.Tarot, 0.65)[i]
		G.suitrank.rankconfig.level_color[i] = G.C.HAND_LEVELS[number_format(G.GAME.ranks[G.suitrank.rank].level)][i]
		G.suitrank.rankconfig.text_color[i] = lighten(G.C.SECONDARY_SET.Tarot, 0.6)[i]
	end
	G.suitrank.suitconfig.level = localize('k_level_prefix') .. number_format(G.GAME.suits[G.suitrank.suit].level)
	G.suitrank.suitconfig.count = jl.countsuit()[G.suitrank.suit] or 0
	G.suitrank.suitconfig.chips = "+" .. number_format(G.GAME.suits[G.suitrank.suit].chips)
	G.suitrank.suitconfig.mult = "+" .. number_format(G.GAME.suits[G.suitrank.suit].mult)
	G.suitrank.rankconfig.level = localize('k_level_prefix') .. number_format(G.GAME.ranks[G.suitrank.rank].level)
	G.suitrank.rankconfig.count = jl.countrank()[G.suitrank.rank] or 0
	G.suitrank.rankconfig.chips = "+" .. number_format(G.GAME.ranks[G.suitrank.rank].chips)
	G.suitrank.rankconfig.mult = "+" .. number_format(G.GAME.ranks[G.suitrank.rank].mult)
end

function UIBox_button_w_sprite(args)
	args = args or {}
	args.button = args.button or "exit_overlay_menu"
	args.func = args.func or nil
	args.colour = args.colour or G.C.RED
	args.choice = args.choice or nil
	args.chosen = args.chosen or nil
	args.minw = args.minw or 2.7
	args.maxw = args.maxw or (args.minw - 0.2)
	if args.minw < args.maxw then args.maxw = args.minw - 0.2 end
	args.minh = args.minh or 0.9
	args.scale = args.scale or 0.5
	args.focus_args = args.focus_args or nil
	args.text_colour = args.text_colour or G.C.UI.TEXT_LIGHT
	local but_UIT = args.col == true and G.UIT.C or G.UIT.R

	local but_UI_label = {}

	local button_pip = nil
	table.insert(but_UI_label,
		{
			n = G.UIT.R,
			config = { align = "cm", padding = 0, minw = args.minw, maxw = args.maxw },
			nodes = {
				{ n = G.UIT.O, config = { object = args.sprite, scale = args.scale, shadow = args.shadow, focus_args = button_pip and args.focus_args or nil, func = button_pip, ref_table = args.ref_table } }
			}
		})
	if args.label then
		for k, v in ipairs(args.label) do
			if k == #args.label and args.focus_args and args.focus_args.set_button_pip then
				button_pip = 'set_button_pip'
			end
			table.insert(but_UI_label,
				{
					n = G.UIT.R,
					config = { align = "cm", padding = 0, minw = args.minw, maxw = args.maxw },
					nodes = {
						{ n = G.UIT.T, config = { text = v, scale = args.scale, colour = args.text_colour, shadow = args.shadow, focus_args = button_pip and args.focus_args or nil, func = button_pip, ref_table = args.ref_table } }
					}
				})
		end
	end

	return
	{
		n = but_UIT,
		config = { align = 'cm' },
		nodes = {
			{
				n = G.UIT.C,
				config = {
					align = "cm",
					padding = args.padding or 0,
					r = 0.1,
					hover = true,
					colour = args.colour,
					one_press = args.one_press,
					button = (args.button ~= 'nil') and args.button or nil,
					choice = args.choice,
					chosen = args.chosen,
					focus_args = args.focus_args,
					minh = args.minh - 0.3 * (args.count and 1 or 0),
					shadow = true,
					func = args.func,
					id = args.id,
					back_func = args.back_func,
					ref_table = args.ref_table,
					mid = args.mid
				},
				nodes =
					but_UI_label
			} }
	}
end

local mcp = Moveable.calculate_parrallax
function Moveable:calculate_parrallax()
	if self.no_parallax then
		self.shadow_parrallax = { x = 0, y = 0 }
	end
	return mcp(self)
end

function ui_suits_ranks()
	if not G.suitrank then
		G.suitrank = {}
	end
	if G.suitrank.card then
		G.suitrank.card:remove()
	end
	if not G.suitrank.rank or not G.suitrank.suit or not is_valid_suit_rank(G.suitrank.suit, G.suitrank.rank) then
		for i = 1, #SMODS.Rank.obj_buffer do
			local r = SMODS.Rank.obj_buffer[i]
			for j = 1, #SMODS.Suit.obj_buffer do
				local s = SMODS.Suit.obj_buffer[j]
				if is_valid_suit_rank(s, r) then
					G.suitrank.suit = s
					G.suitrank.rank = r
					break
				end
			end
		end
	end
	G.suitrank.card = Card(0, 0, 1.5 * G.CARD_W, 1.5 * G.CARD_H, G.P_CARDS.S_A, G.P_CENTERS.c_base)
	G.suitrank.card.ambient_tilt = 0
	G.suitrank.card.states.hover.can = false
	G.suitrank.card.hover_tilt = 0
	G.suitrank.card.no_parallax = true
	G.suitrank.card.shadow = false
	if not G.suitrank.suitconfig then
		G.suitrank.suitconfig = {}
	end
	if not G.suitrank.rankconfig then
		G.suitrank.rankconfig = {}
	end
	recalc_suitrank()

	--A bunch of local functions to define core nodes, so as to make the code easier to read
	local function sr_name(type)
		return {
			n = G.UIT.R,
			config = { align = "cl", colour = G.C.CLEAR, r = 0.2, },
			nodes = {
				{ n = G.UIT.O, config = { object = DynaText({ string = { { ref_table = G.suitrank[type .. "config"], ref_value = "name" } }, scale = 0.8, shadow = true, colours = { G.C.WHITE } }) } },
			}
		}
	end
	local function sr_level(type)
		return {
			n = G.UIT.R,
			config = { align = "cr", colour = G.C.CLEAR },
			nodes = {
				{
					n = G.UIT.R,
					config = { align = "cm", padding = 0.05, r = 0.1, colour = G.suitrank[type .. "config"].level_color, minw = 1.7, outline = 0.8, outline_colour = G.suitrank[type .. "config"].outline_color },
					nodes = {
						{ n = G.UIT.T, config = { ref_table = G.suitrank[type .. "config"], ref_value = "level", scale = 0.5, colour = G.C.UI.TEXT_DARK } }
					}
				}
			}
		}
	end
	local function sr_count(type)
		return { {
			n = G.UIT.C,
			config = { align = "cl" },
			nodes = {
				{ n = G.UIT.T, config = { text = '#', scale = 0.45, colour = G.C.WHITE, shadow = true } }
			}
		},
			{
				n = G.UIT.C,
				config = { align = "cm", padding = 0.05, colour = G.suitrank[type .. "config"].outline_color, r = 0.1, minw = 0.9 },
				nodes = {
					{ n = G.UIT.T, config = { ref_table = G.suitrank[type .. "config"], ref_value = "count", scale = 0.45, colour = G.suitrank[type .. "config"].text_color, shadow = true } },
				}
			} }
	end

	local function sr_values(type)
		return {
			n = G.UIT.R,
			config = { align = "cr" },
			nodes = {
				{
					n = G.UIT.C,
					config = { align = "cm", padding = 0.03, r = 0.1, colour = G.C.CHIPS, minw = 0.8 },
					nodes = {
						{ n = G.UIT.T, config = { ref_table = G.suitrank[type .. "config"], ref_value = "chips", scale = 0.45, colour = G.C.UI.TEXT_LIGHT } },
					}
				}, { n = G.UIT.B, config = { w = 0.1, h = 0.1 } },
				{
					n = G.UIT.C,
					config = { align = "cm", padding = 0.03, r = 0.1, colour = G.C.MULT, minw = 0.8 },
					nodes = {
						{ n = G.UIT.T, config = { ref_table = G.suitrank[type .. "config"], ref_value = "mult", scale = 0.45, colour = G.C.UI.TEXT_LIGHT } }
					}
				},
			}
		}
	end

	local function sr_hand(type)
		return {
			n = G.UIT.R,
			config = { align = "cm", colour = G.suitrank[type .. "config"].color, minw = 7, minh = 2, r = 0.2, outline = 1, outline_colour = G.suitrank[type .. "config"].outline_color, padding = 0.3 },
			nodes = {
				{
					n = G.UIT.C,
					config = { align = "cl", colour = G.C.CLEAR, r = 0.2, padding = 0.03, minw = 3.5 },
					nodes = {
						sr_name(type),
						{
							n = G.UIT.R,
							config = { align = "cl", colour = G.C.CLEAR, r = 0.2 },
							nodes = {
								sr_count(type)[1],
								sr_count(type)[2],
							}
						}
					}
				},
				{
					n = G.UIT.C,
					config = { align = "cr", colour = G.C.CLEAR, r = 0.2, padding = 0.03, minw = 3.5 },
					nodes = {
						sr_level(type),
						sr_values(type),
					}
				},
			}
		}
	end

	local function sr_card()
		return {
			n = G.UIT.C,
			config = { align = "cm", colour = G.C.CLEAR, },
			nodes = {
				{
					n = G.UIT.R,
					config = { minw = 2, minh = 1.5, colour = G.C.CLEAR, padding = 0.15, align = "bm" },
					nodes = {
						UIBox_button_w_sprite({
							colour = G.C.CLEAR,
							button = "inc_sr_rank",
							sprite = Sprite(0, 0, 1, 1, G.ASSET_ATLAS["jen_jenbuttons"], { x = 0, y = 0 }),
							scale = 0.6,
							minw = 1,
						})
					}
				},
				{
					n = G.UIT.R,
					config = { minw = 2, minh = 1.5, colour = G.C.CLEAR, padding = 0.15 },
					nodes = {
						{
							n = G.UIT.C,
							config = { align = "cr", colour = G.C.CLEAR, },
							nodes = {
								UIBox_button_w_sprite({
									colour = G.C.CLEAR,
									button = "dec_sr_suit",
									sprite = Sprite(0, 0, 1, 1, G.ASSET_ATLAS["jen_jenbuttons"], { x = 3, y = 0 }),
									scale = 0.6,
									minw = 1,
								})
							}
						},
						{ n = G.UIT.B, config = { w = 0.15, h = 0.15 } }, --I have no idea why this is off center by default
						{
							n = G.UIT.C,
							config = { minw = 2.5, align = "cm", colour = G.C.CLEAR, },
							nodes = {
								{ n = G.UIT.O, config = { colour = G.C.BLUE, object = G.suitrank.card, hover = false, can_collide = false } },
							}
						},
						{
							n = G.UIT.C,
							config = { align = "cl", colour = G.C.CLEAR, },
							nodes = {
								UIBox_button_w_sprite({
									colour = G.C.CLEAR,
									button = "inc_sr_suit",
									sprite = Sprite(0, 0, 1, 1, G.ASSET_ATLAS["jen_jenbuttons"], { x = 1, y = 0 }),
									scale = 0.6,
									minw = 1,
								})
							}
						},
					}
				},
				{
					n = G.UIT.R,
					config = { minw = 2, minh = 1.5, colour = G.C.CLEAR, padding = 0.15, align = "tm" },
					nodes = {
						UIBox_button_w_sprite({
							colour = G.C.CLEAR,
							button = "dec_sr_rank",
							sprite = Sprite(0, 0, 1, 1, G.ASSET_ATLAS["jen_jenbuttons"], { x = 2, y = 0 }),
							scale = 0.6,
							minw = 1,
						})
					}
				},
			}
		}
	end

	return {
		n = G.UIT.ROOT,
		config = { align = "cm", minw = 3, padding = 0.1, r = 0.1, colour = G.C.CLEAR },
		nodes = {
			{
				n = G.UIT.R,
				config = { align = "cm", colour = G.C.CLEAR, },
				nodes = {
					sr_card(),
					{
						n = G.UIT.C,
						config = { align = "cm", colour = G.C.CLEAR, minw = 6, padding = 0.3 },
						nodes = {
							sr_hand("suit"),
							sr_hand("rank"),
						}
					}
				}
			}
		}
	}
end

G.FUNCS.current_suits_ranks = function(e)
	G.SETTINGS.paused = true
	G.FUNCS.overlay_menu { definition = ui_suits_ranks() }
end

local mainmenuref = Game.main_menu
Game.main_menu = function(change_context)
	if not edited_default_colours then
		for i = 1, 7 do manage_level_colour(i, true) end
		edited_default_colours = true
	end
	--if not G.PROFILES[G.SETTINGS.profile].all_unlocked then
	G.PROFILES[G.SETTINGS.profile].all_unlocked = true
	for k, v in pairs(G.P_CENTERS) do
		if not v.demo and not v.wip then
			v.alerted = true
			v.discovered = true
			v.unlocked = true
		end
	end
	for k, v in pairs(G.P_BLINDS) do
		if not v.demo and not v.wip then
			v.alerted = true
			v.discovered = true
			v.unlocked = true
		end
	end
	for k, v in pairs(G.P_TAGS) do
		if not v.demo and not v.wip then
			v.alerted = true
			v.discovered = true
			v.unlocked = true
		end
	end
	set_profile_progress()
	set_discover_tallies()
	G:save_progress()
	G.FILE_HANDLER.force = true
	--end
	local ret = mainmenuref(change_context)
	local newcard = create_card("Joker", G.title_top, nil, nil, nil, nil, "j_jen_jen", "almanac_title")
	G.title_top:emplace(newcard)
	newcard:start_materialize()
	newcard:resize(1.1 * 1.2)
	newcard.no_ui = true
	-- make the title screen use different background colors
	G.SPLASH_BACK:define_draw_steps({
		{
			shader = "splash",
			send = {
				{ name = "time",       ref_table = G.TIMERS, ref_value = "REAL_SHADER" },
				{ name = "vort_speed", val = 0.4 },
				{ name = "colour_1",   ref_table = G.C,      ref_value = "CRY_TWILIGHT" },
				{ name = "colour_2",   ref_table = G.C,      ref_value = "CRY_EMBER" },
			},
		},
	})
	Jen.dramatic = false
	Jen.sinister = false
	return ret
end

local uhtr = update_hand_text
function update_hand_text(config, vals)
	if vals and vals.level and type(vals.level) == 'table' and vals.level.array and vals.level.array[1] and is_number(vals.level) then
		local lv = to_big(vals.level)
		local lvstr = number_format(lv)
		if not G.C.HAND_LEVELS[lvstr] then
			if lv <= to_big(0) then
				G.C.HAND_LEVELS[lvstr] = G.C.RED
			else
				manage_level_colour(lv)
			end
		end
	end
	uhtr(config, vals)
end

local copyref = copy_card
function copy_card(card, a, b, c, d)
	local dupe = copyref(card, a, b, c, d)
	if dupe and dupe.gc and dupe:gc().uncopyable then
		Q(function()
			Q(function()
				if dupe then dupe:destroy() end
				return true
			end)
			return true
		end)
	end
	return dupe
end

G.FUNCS.can_skip_booster = function(e)
	e.config.colour = G.C.GREY
	e.config.button = 'skip_booster'
end

function G.FUNCS.text_super_juice(e, _amount, unlimited)
	if type(_amount) == "table" then
		if _amount > to_big(1e300) then
			_amount = 1e300
		else
			_amount = _amount:to_number()
		end
	end
	if e and e.config and e.config.object and next(e.config.object) then
		e.config.object:set_quiver(unlimited and (0.002 * _amount) or math.min(1, 0.002 * _amount))
		e.config.object:pulse(unlimited and (0.3 + 0.003 * _amount) or math.min(10, 0.3 + 0.003 * _amount))
		e.config.object:update_text()
		e.config.object:align_letters()
		e:update_object()
	end
end

function G.FUNCS.tsj_specific(e, quiver, pulse)
	if e and e.config and e.config.object and next(e.config.object) then
		e.config.object:set_quiver(quiver)
		e.config.object:pulse(pulse)
		e.config.object:update_text()
		e.config.object:align_letters()
		e:update_object()
	end
end

G.FUNCS.hand_mult_UI_set = function(e)
	local new_mult_text = number_format(G.GAME.current_round.current_hand.mult)
	if new_mult_text ~= G.GAME.current_round.current_hand.mult_text then
		G.GAME.current_round.current_hand.mult_text = new_mult_text
		e.config.object.scale = 0.46 / (math.max(1, string.len(new_mult_text) - 8) ^ .2)
		e.config.object:update_text()
		if not G.TAROT_INTERRUPT_PULSE then
			G.FUNCS.text_super_juice(e,
				math.max(0,
					math.floor(math.log10((type(G.GAME.current_round.current_hand.mult) == 'number' or type(G.GAME.current_round.current_hand.mult) == 'table') and
						G.GAME.current_round.current_hand.mult or 0))))
		else
			G.FUNCS.text_super_juice(e, 0, 0)
		end
	end
end

G.FUNCS.hand_chip_UI_set = function(e)
	local new_chip_text = number_format(G.GAME.current_round.current_hand.chips)
	if new_chip_text ~= G.GAME.current_round.current_hand.chip_text then
		G.GAME.current_round.current_hand.chip_text = new_chip_text
		e.config.object.scale = 0.46 / (math.max(1, string.len(new_chip_text) - 8) ^ .2)
		e.config.object:update_text()
		if not G.TAROT_INTERRUPT_PULSE then
			G.FUNCS.text_super_juice(e,
				math.max(0,
					math.floor(math.log10((type(G.GAME.current_round.current_hand.chips) == 'number' or type(G.GAME.current_round.current_hand.chips) == 'table') and
						G.GAME.current_round.current_hand.chips or 0))))
		else
			G.FUNCS.text_super_juice(e, 0, 0)
		end
	end
end

G.FUNCS.hand_chip_total_UI_set = function(e)
	if to_big(G.GAME.current_round.current_hand.chip_total) < to_big(1) then
		G.GAME.current_round.current_hand.chip_total_text = ''
	else
		local new_chip_total_text = number_format(G.GAME.current_round.current_hand.chip_total)
		if new_chip_total_text ~= G.GAME.current_round.current_hand.chip_total_text then
			e.config.object.scale = scale_number(G.GAME.current_round.current_hand.chip_total, 0.95, 1e8)

			G.GAME.current_round.current_hand.chip_total_text = new_chip_total_text
			if not G.ARGS.hand_chip_total_UI_set or to_big(G.ARGS.hand_chip_total_UI_set) < to_big(G.GAME.current_round.current_hand.chip_total) then
				G.FUNCS.text_super_juice(e,
					math.max(0,
						math.floor(math.log10((type(G.GAME.current_round.current_hand.chip_total) == 'number' or type(G.GAME.current_round.current_hand.chip_total) == 'table') and
							G.GAME.current_round.current_hand.chip_total or 0))))
			else
				G.FUNCS.text_super_juice(e, 0, 0)
			end
			G.ARGS.hand_chip_total_UI_set = G.GAME.current_round.current_hand.chip_total
		end
	end
end

local caer = CardArea.emplace

function CardArea:emplace(card, location, stay_flipped)
	if G.jokers and G.hand and G.deck and G.consumeables and (self == G.jokers or self == G.hand or self == G.deck or self == G.consumeables) and G.GAME.mysterious and card.ability and not card.ability.mysterious_created and not card.created_from_split then
		card.ability.mysterious_created = true
		local cen = card.gc and card:gc()
		if cen and not cen.no_mysterious then
			--Q(function()
			if self == G.jokers then
				Q(function()
					if card then
						if card.added_to_deck then
							card:remove_from_deck()
							card.added_to_deck = nil
						end
						card:flip()
						card:juice_up(0.3, 0.3)
						play_sound('card1', 1, 0.6)
					end
					return true
				end, 1.5)
				delay(1.5)
				Q(function()
					if card then
						card:flip()
						card:juice_up(0.3, 0.3)
						play_sound('card3', 1, 0.6)
						card:set_ability(jl.rnd('mysterious_deck_joker', { 'no_mysterious' }, G.P_CENTER_POOLS.Joker))
						if not card.added_to_deck then
							card:add_to_deck()
							Q(function()
								if card then
									local newcen = card.gc and card:gc()
									if newcen then
										if newcen.abilitycard and #SMODS.find_card(newcen.abilitycard) <= 0 then
											Q(function()
												local traysize = G.consumeables.config.card_limit + 1
												G.consumeables.config.card_limit = #G.consumeables.cards + 1
												local abi = create_card('jen_ability', G.consumeables, nil, nil, nil, nil,
													newcen.abilitycard, nil)
												abi.no_forced_edition = true
												abi:add_to_deck()
												G.consumeables:emplace(abi)
												abi.ability.eternal = true
												G.consumeables.config.card_limit = traysize
												Q(function()
													if abi then check_ability_card_validity(abi) end
													return true
												end)
												return true
											end)
										end
									end
								end
								return true
							end)
						end
					end
					return true
				end, 1.5)
			elseif self == G.consumeables and cen.set ~= 'jen_ability' then
				Q(function()
					if card then
						if card.added_to_deck then
							card:remove_from_deck()
							card.added_to_deck = nil
						end
						card:flip()
						card:juice_up(0.3, 0.3)
						play_sound('card1', 1, 0.6)
					end
					return true
				end, 1.5)
				delay(1.5)
				Q(function()
					if card then
						card:flip()
						card:juice_up(0.3, 0.3)
						play_sound('card3', 1, 0.6)
						card:set_ability(jl.rnd('mysterious_deck_consumable',
							cen.hidden and { 'no_doe', 'no_grc' } or { 'hidden', 'no_doe', 'no_grc' },
							G.P_CENTER_POOLS[cen.set]))
						if not card.added_to_deck then
							card:add_to_deck()
						end
					end
					return true
				end, 1.5)
			elseif (card.base or {}).value or (card.base or {}).suit then
				jl.randomise({ card })
			end
			--return true end)
			--delay(1)
		end
		Q(function()
			if card and self then caer(self, card, location, stay_flipped) end
			return true
		end)
	else
		caer(self, card, location, stay_flipped)
	end
end

local add_to_deckref = Card.add_to_deck
function Card.add_to_deck(self, from_debuff)
	local cen = self.gc and self:gc()
	if not from_debuff then
		if cen then
			if cen.unique then
				for k, v in ipairs(G.jokers.cards) do
					if v ~= self and v:gc().key == cen.key then
						ease_dollars(self.sell_cost or 0)
						self:destroy()
						return --blocked
					end
				end
			end
			if not G.GAME.mysterious and G.consumeables and cen and cen.abilitycard and type(cen.abilitycard) == 'string' and #SMODS.find_card(cen.abilitycard) <= 0 then
				Q(function()
					if #SMODS.find_card(cen.abilitycard) <= 0 then
						local traysize = G.consumeables.config.card_limit + 1
						G.consumeables.config.card_limit = #G.consumeables.cards + 1
						local abi = create_card('jen_ability', G.consumeables, nil, nil, nil, nil, cen.abilitycard, nil)
						abi.no_forced_edition = true
						abi:add_to_deck()
						G.consumeables:emplace(abi)
						abi.ability.eternal = true
						G.consumeables.config.card_limit = traysize
						Q(function()
							if abi then check_ability_card_validity(abi) end
							return true
						end)
					end
					return true
				end)
			end
			if G.consumeables and cen and cen.fusable and #SMODS.find_card('c_jen_fuse') <= 0 then
				local traysize = G.consumeables.config.card_limit + 1
				G.consumeables.config.card_limit = #G.consumeables.cards + 1
				local abi = create_card('jen_ability', G.consumeables, nil, nil, nil, nil, 'c_jen_fuse', nil)
				abi.no_forced_edition = true
				abi:add_to_deck()
				G.consumeables:emplace(abi)
				abi.ability.eternal = true
				G.consumeables.config.card_limit = traysize
			end
			if cen.set == 'Colour' and Jen.hv('colour', 13) then
				n_random_colour_rounds(math.max(0, self.ability.partial_rounds or 0))
				for k, v in ipairs(G.consumeables.cards) do
					if v:gc().set == 'Colour' then
						for i = 1, math.ceil(math.max(self.ability.upgrade_rounds or 1, 1) / 2) do
							trigger_colour_end_of_round(v)
						end
					end
				end
				for k, v in ipairs(G.consumeables.cards) do
					if v:gc().set == 'Colour' then
						for i = 1, (math.max(self.ability.upgrade_rounds or 1, 1) + math.max(self.ability.partial_rounds or 0, 0)) * 3 * math.max(self.ability.partial_rounds or 1, 1) * math.max(self.ability.upgrade_rounds or 1, 1) do
							trigger_colour_end_of_round(v)
						end
					end
				end
				local no_colours = 1
				for k, v in ipairs(G.consumeables.cards) do
					if v:gc().set == 'Colour' then
						no_colours = no_colours + 1
					end
				end
				for k, v in ipairs(G.consumeables.cards) do
					if v:gc().set == 'Colour' then
						for i = 1, math.min(1e5, math.ceil(((math.max(self.ability.upgrade_rounds or 1, 1) + math.max(self.ability.partial_rounds or 0, 0) + 1) * (math.max(v.ability.upgrade_rounds or 1, 1) + math.max(v.ability.partial_rounds or 0, 0) + 1)) * (((self.ability.val or 0) + 1) ^ math.min(1.5, (1 + (no_colours / 20)))))) do
							trigger_colour_end_of_round(v)
						end
					end
				end
				self:blackhole(((self.ability.partial_rounds or 0) * 0.5) + ((self.ability.upgrade_rounds or 0) * 0.25) +
					((self.ability.val or 0) * ((self.ability.upgrade_rounds or 0) * 5)))
			end
		end
		jl.jokers({ jen_adding_card = true, card = self })
	elseif cen then
		if cen.unique then
			for k, v in ipairs(G.jokers.cards) do
				if v ~= self and v:gc().key == cen.key then
					ease_dollars(self.sell_cost or 0)
					self:destroy()
					return --blocked
				end
			end
		end
	end
	add_to_deckref(self, from_debuff)
	if cen then
		if cen.unique then
			QR(function()
				if self then
					for k, v in ipairs(G.jokers.cards) do
						if v ~= self and v:gc().key == cen.key then
							ease_dollars(self.sell_cost or 0)
							self:remove_from_deck()
							self:destroy()
							self = nil
							break
						end
					end
				end
				return true
			end, 199)
		end
	end
end

function check_ability_card_validity(card)
	if not card or not G.jokers then return end
	local cen = card.gc and card:gc()
	if not cen then return end
	local should_remove = true
	for i = 1, #G.jokers.cards do
		local cur = G.jokers.cards[i]
		local curcen = cur.gc and cur:gc()
		if curcen then
			if (curcen.abilitycard or 'n/a') == cen.key then
				should_remove = false
				break
			end
		end
	end
	if should_remove then
		for k, v in pairs(SMODS.find_card(cen.key, true)) do
			if not (v.edition or {}).negative then
				G.consumeables.config.card_limit = G.consumeables.config.card_limit - 1
			end
			v.no_malice = true
			v:destroy()
		end
	end
end

local rfd = Card.remove_from_deck
function Card.remove_from_deck(self, from_debuff)
	if G.jokers and G.consumeables then
		if self.added_to_deck and self.config and self.gc and self:gc() and self:gc().abilitycard and type(self:gc().abilitycard) == 'string' then
			local cen = self:gc()
			Q(function()
				if #SMODS.find_card(cen.key, true) <= 0 then
					for k, v in pairs(SMODS.find_card(cen.abilitycard)) do
						check_ability_card_validity(v)
					end
				end
				return true
			end)
		end
		if self.added_to_deck and self.config and self.gc and self:gc() and self:gc().fusable then
			local can_still_fuse = false
			for k, v in ipairs(G.jokers.cards) do
				if v.gc and v:gc().fusable then
					can_still_fuse = true
					break
				end
			end
			if not can_still_fuse then
				for k, v in ipairs(G.consumeables.cards) do
					if v.gc and v:gc().fusable then
						can_still_fuse = true
						break
					end
				end
			end
			if not can_still_fuse then
				for k, v in pairs(SMODS.find_card('c_jen_fuse')) do
					if not (v.edition or {}).negative then
						G.consumeables.config.card_limit = G.consumeables.config.card_limit - 1
					end
					v:destroy()
				end
			end
		end
	end
	rfd(self, from_debuff)
end

local ten = to_big(10)
local gbar = get_blind_amount
local defaultblindsize = to_big(100)
function get_blind_amount(ante)
	-- Ensure we operate on a primitive number for the base game function to avoid table< comparisons
	ante = to_number(ante)
	local amnt
	if math.floor(ante) ~= ante then
		-- fractional ante interpolation (proper fractional part)
		local frac = ante - math.floor(ante)
		local lower, upper = math.floor(ante), math.ceil(ante)
		-- delegate to original function with numeric args only
		local lower_amt = gbar(lower)
		local upper_amt = gbar(upper)
		amnt = (lower_amt * (1 - frac)) + (upper_amt * frac)
	else
		amnt = gbar(ante)
	end
	local overante = math.max(0, ante - Jen.config.ante_threshold)
	if not amnt then amnt = defaultblindsize end
	if type(amnt) ~= 'table' then amnt = to_big(amnt) end
	if overante > 0 then
		local scalar = Jen.blind_scalar[math.min(overante, #Jen.blind_scalar)] or 1
		amnt = amnt * scalar
		-- If the amount has already blown up to an invalid/infinite value, cap and exit early
		if jl.invalid_number(number_format(amnt)) then return to_big(maxfloat) end
		if overante >= Jen.config.ante_pow10_4 then
			amnt = ten ^ ten ^ ten ^ ten ^ amnt
		elseif overante >= Jen.config.ante_pow10_3 then
			amnt = ten ^ ten ^ ten ^ amnt
		elseif overante >= Jen.config.ante_pow10_2 then
			amnt = ten ^ ten ^ amnt
		elseif overante >= Jen.config.ante_pow10 then
			amnt = ten ^ amnt
		end
		-- Recheck after exponentiation to avoid unsafe arrow operations on NaN/Infinity
		if jl.invalid_number(number_format(amnt)) then return to_big(maxfloat) end
		if overante >= Jen.config.ante_exponentiate then
			amnt = amnt ^ amnt
		end
		-- Only apply arrow operations if value remains valid; recheck before each step
		if overante >= Jen.config.ante_tetrate then
			if jl.invalid_number(number_format(amnt)) then return to_big(maxfloat) end
			amnt = amnt:arrow(2, 2)
		end
		if overante >= Jen.config.ante_pentate then
			if jl.invalid_number(number_format(amnt)) then return to_big(maxfloat) end
			amnt = amnt:arrow(3, 2)
		end
		if overante >= Jen.config.ante_polytate then
			if jl.invalid_number(number_format(amnt)) then return to_big(maxfloat) end
			local arrows = 4 + math.floor((overante - Jen.config.ante_polytate + 1) / Jen.config.polytate_factor)
			local operand = 2 + math.max(0, arrows - 4 - Jen.config.polytate_factor)
			amnt = amnt:arrow(math.min(maxArrow, arrows), operand)
		end
	end
	return amnt
end

local ignorelimit_playingcards = { 'm_jen_surreal', 'm_jen_exotic' }
local athr = CardArea.add_to_highlighted
function CardArea:add_to_highlighted(card, silent)
	if card and card.gc then
		if card:gc().unhighlightable then
			return false
		end
	end
	if self.config.type ~= 'shop' and self.config.type ~= 'joker' and self.config.type ~= 'consumeable' then
		local surreals = 0
		for k, v in ipairs(self.highlighted) do
			if jl.bf(v.ability.name, ignorelimit_playingcards) then surreals = surreals + 1 end
		end
		local exception = false
		if #SMODS.find_card('j_jen_honey') > 0 then
			local ID = card:get_id()
			local prevcard = self.highlighted[#self.highlighted]
			if prevcard then
				local honeys = SMODS.find_card('j_jen_honey')
				local prevcardID = prevcard:get_id()
				for i = 1, #honeys do
					if (ID == (prevcardID - i) or ID == (prevcardID + i)) then
						exception = true
						honeys[i]:juice_up(0.5, 0.5)
						break
					end
				end
			end
		end
		if #SMODS.find_card('j_jen_cosmo') > 0 and not exception then
			local cosmos = SMODS.find_card('j_jen_cosmo')
			for i = 1, #cosmos do
				if card.config.center.key ~= 'c_base' then
					exception = true
					cosmos[i]:juice_up(0.5, 0.5)
					break
				end
			end
		end
		if #self.highlighted < surreals + self.config.highlighted_limit or jl.bf(card.ability.name, ignorelimit_playingcards) or exception then
			self.highlighted[#self.highlighted + 1] = card
			if card.children and card.children.center then
				card:highlight(true)
			end
			if not silent then play_sound('cardSlide1') end
			if self == G.hand and G.STATE == G.STATES.SELECTING_HAND then
				self:parse_highlighted()
			end
			return
		end
	end
	if card and card.children and card.children.center then
		athr(self, card, silent)
	end
end

local csar = Card.set_ability
function Card:set_ability(center, initial, delay_sprites)
	if self and self.gc then
		if self.added_to_deck and self:gc().unchangeable and not self.jen_ignoreunchangeable then
			return false
		end
	end
	csar(self, center, initial, delay_sprites)
end

function check_for_unlock(args)
	return
end

function unlock_achievement(achievement_name)
	return
end

-- Add can_reserve_card function for Reservia voucher
G.FUNCS.can_reserve_card = function(e)
	if e.config.ref_table then
		local card = e.config.ref_table
		if card.ability.consumeable then
			-- Check if we can still reserve cards (room in consumable area AND pack has choices remaining)
			if #G.consumeables.cards < G.consumeables.config.card_limit and G.GAME.pack_choices and G.GAME.pack_choices > 0 then
				e.config.colour = G.C.GREEN
				e.config.button = 'reserve_card'
			else
				e.config.colour = G.C.UI.BACKGROUND_INACTIVE
				e.config.button = nil
			end
		end
	end
end

-- Add reserve_card function to handle the reserve button action
G.FUNCS.reserve_card = function(e)
	local card = e.config.ref_table
	if card and card.area == G.pack_cards and card.ability.consumeable then
		local cen = card.gc and card:gc()
		if cen and ((Jen.hv('reserve', 1) and cen.set == 'Planet') or (Jen.hv('reserve', 2) and cen.set == 'Tarot') or (Jen.hv('reserve', 3) and cen.set == 'Spectral')) then
			-- This is a reserve action, add to consumable tray
			if #G.consumeables.cards < G.consumeables.config.card_limit and G.GAME.pack_choices and G.GAME.pack_choices > 0 then
				card.area:remove_card(card)
				card:add_to_deck()
				G.consumeables:emplace(card)
				play_sound('card1')

				-- Decrement the pack's choice counter
				G.GAME.pack_choices = G.GAME.pack_choices - 1

				-- Check if we've used all choices and should close the pack
				if G.GAME.pack_choices <= 0 then
					G.FUNCS.skip_booster(e)
				end
			end
		end
	end
end

local guiduasbr = G.UIDEF.use_and_sell_buttons
function G.UIDEF.use_and_sell_buttons(card)
	if (card.area == G.pack_cards and G.pack_cards) and card.ability.consumeable then
		local cen = card.gc and card:gc()
		if cen and ((Jen.hv('reserve', 1) and cen.set == 'Planet') or (Jen.hv('reserve', 2) and cen.set == 'Tarot') or (Jen.hv('reserve', 3) and cen.set == 'Spectral')) then
			return {
				n = G.UIT.ROOT,
				config = { padding = -0.1, colour = G.C.CLEAR },
				nodes = {
					{
						n = G.UIT.R,
						config = {
							ref_table = card,
							r = 0.08,
							padding = 0.1,
							align = "bm",
							minw = 0.5 * card.T.w - 0.15,
							minh = 0.7 * card.T.h,
							maxw = 0.7 * card.T.w - 0.15,
							hover = true,
							shadow = true,
							colour = G.C.UI.BACKGROUND_INACTIVE,
							one_press = true,
							button = "use_card",
							func = "can_reserve_card",
						},
						nodes = {
							{
								n = G.UIT.T,
								config = {
									text = 'RESERVE',
									colour = G.C.UI.TEXT_LIGHT,
									scale = 0.55,
									shadow = true,
								},
							},
						},
					},
					{
						n = G.UIT.R,
						config = {
							ref_table = card,
							r = 0.08,
							padding = 0.1,
							align = "bm",
							minw = 0.5 * card.T.w - 0.15,
							maxw = 0.9 * card.T.w - 0.15,
							minh = 0.1 * card.T.h,
							hover = true,
							shadow = true,
							colour = G.C.UI.BACKGROUND_INACTIVE,
							one_press = true,
							button = 'kekw',
							func = "can_use_consumeable",
						},
						nodes = {
							{
								n = G.UIT.T,
								config = {
									text = localize("b_use"),
									colour = G.C.UI.TEXT_LIGHT,
									scale = 0.45,
									shadow = true,
								},
							},
						},
					},
					{ n = G.UIT.R, config = { align = "bm", w = 7.7 * card.T.w } },
					{ n = G.UIT.R, config = { align = "bm", w = 7.7 * card.T.w } },
					{ n = G.UIT.R, config = { align = "bm", w = 7.7 * card.T.w } },
					{ n = G.UIT.R, config = { align = "bm", w = 7.7 * card.T.w } }
				},
			}
		end
	end
	return guiduasbr(card)
end

for i = 1, 2 do
	SMODS.Booster {
		key = 'ministandard' .. i,
		loc_txt = {
			name = 'Mini Standard Pack',
			text = {
				'Choose {C:attention}#1#{} of up to',
				'{C:attention}#2# playing cards{} to',
				'add to your deck',
				spriter('cozyori')
			}
		},
		atlas = 'jenbooster',
		pos = { x = 6, y = i - 1 },
		weight = .8,
		cost = 2,
		config = { extra = 2, choose = 1 },
		discovered = true,
		loc_vars = function(self, info_queue, card)
			return { vars = { card.ability.choose, card.ability.extra } }
		end,
		ease_background_colour = function(self) ease_background_colour_blind(G.STATES.STANDARD_PACK) end,
		create_UIBox = function(self) return create_UIBox_standard_pack() end,
		particles = function(self)
			G.booster_pack_sparkles = Particles(1, 1, 0, 0, {
				timer = 0.015,
				scale = 0.3,
				initialize = true,
				lifespan = 3,
				speed = 0.2,
				padding = -1,
				attach = G.ROOM_ATTACH,
				colours = { G.C.BLACK, G.C.RED },
				fill = true
			})
			G.booster_pack_sparkles.fade_alpha = 1
			G.booster_pack_sparkles:fade(1, 0)
		end,
		create_card = function(self, card, i)
			local _edition = poll_edition('standard_edition' .. G.GAME.round_resets.ante, 2, true)
			local _seal = SMODS.poll_seal({ mod = 10 })
			return {
				set = (pseudorandom(pseudoseed('stdset' .. G.GAME.round_resets.ante)) > 0.6) and "Enhanced" or
					"Base",
				edition = _edition,
				seal = _seal,
				area = G.pack_cards,
				skip_materialize = true,
				soulable = true,
				key_append =
				"sta"
			}
		end,
	}
end

for i = 1, 2 do
	SMODS.Booster {
		key = 'miniarcana' .. i,
		loc_txt = {
			name = 'Mini Arcana Pack',
			text = {
				'Choose {C:attention}#1#{} of up to',
				'{C:attention}#2# {C:tarot}Tarot{} cards to',
				'be used immediately',
				spriter('mailingway')
			}
		},
		atlas = 'jenbooster',
		pos = { x = 3 + i, y = 1 },
		weight = .8,
		cost = 2,
		config = { extra = 2, choose = 1 },
		discovered = true,
		draw_hand = true,
		loc_vars = function(self, info_queue, card)
			return { vars = { card.ability.choose, card.ability.extra } }
		end,
		ease_background_colour = function(self) ease_background_colour_blind(G.STATES.TAROT_PACK) end,
		create_UIBox = function(self) return create_UIBox_arcana_pack() end,
		particles = function(self)
			G.booster_pack_sparkles = Particles(1, 1, 0, 0, {
				timer = 0.015,
				scale = 0.2,
				initialize = true,
				lifespan = 1,
				speed = 1.1,
				padding = -1,
				attach = G.ROOM_ATTACH,
				colours = { G.C.WHITE, lighten(G.C.PURPLE, 0.4), lighten(G.C.PURPLE, 0.2), lighten(G.C.GOLD, 0.2) },
				fill = true
			})
			G.booster_pack_sparkles.fade_alpha = 1
			G.booster_pack_sparkles:fade(1, 0)
		end,
		create_card = function(self, card, i)
			local _card
			if G.GAME.used_vouchers.v_omen_globe and pseudorandom('omen_globe') > 0.8 then
				_card = {
					set = "Spectral",
					area = G.pack_cards,
					skip_materialize = true,
					soulable = true,
					key_append =
					"ar2"
				}
			else
				_card = {
					set = "Tarot",
					area = G.pack_cards,
					skip_materialize = true,
					soulable = true,
					key_append =
					"ar1"
				}
			end
			return _card
		end
	}
end

for i = 1, 2 do
	SMODS.Booster {
		key = 'minicelestial' .. i,
		loc_txt = {
			name = 'Mini Celestial Pack',
			text = {
				'Choose {C:attention}#1#{} of up to',
				'{C:attention}#2# {C:planet}Planet{} cards to',
				'be used immediately',
				spriter('mailingway')
			}
		},
		atlas = 'jenbooster',
		pos = { x = 3 + i, y = 0 },
		weight = .8,
		cost = 2,
		config = { extra = 2, choose = 1 },
		discovered = true,
		loc_vars = function(self, info_queue, card)
			return { vars = { card.ability.choose, card.ability.extra } }
		end,
		ease_background_colour = function(self) ease_background_colour_blind(G.STATES.PLANET_PACK) end,
		create_UIBox = function(self) return create_UIBox_celestial_pack() end,
		particles = function(self)
			G.booster_pack_stars = Particles(1, 1, 0, 0, {
				timer = 0.07,
				scale = 0.1,
				initialize = true,
				lifespan = 15,
				speed = 0.1,
				padding = -4,
				attach = G.ROOM_ATTACH,
				colours = { G.C.WHITE, HEX('a7d6e0'), HEX('fddca0') },
				fill = true
			})
			G.booster_pack_meteors = Particles(1, 1, 0, 0, {
				timer = 2,
				scale = 0.05,
				lifespan = 1.5,
				speed = 4,
				attach = G.ROOM_ATTACH,
				colours = { G.C.WHITE },
				fill = true
			})
		end,
		create_card = function(self, card, i)
			local _card
			if G.GAME.used_vouchers.v_telescope and i == 1 then
				local _planet, _hand, _tally = nil, nil, 0
				for k, v in ipairs(G.handlist) do
					if G.GAME.hands[v].visible and G.GAME.hands[v].played > _tally then
						_hand = v
						_tally = G.GAME.hands[v].played
					end
				end
				if _hand then
					for k, v in pairs(G.P_CENTER_POOLS.Planet) do
						if v.config.hand_type == _hand then
							_planet = v.key
						end
					end
				end
				_card = {
					set = "Planet",
					area = G.pack_cards,
					skip_materialize = true,
					soulable = true,
					key = _planet,
					key_append =
					"pl1"
				}
			else
				_card = {
					set = "Planet",
					area = G.pack_cards,
					skip_materialize = true,
					soulable = true,
					key_append =
					"pl1"
				}
			end
			return _card
		end
	}
end

for i = 1, 2 do
	SMODS.Booster {
		key = 'minispectral' .. i,
		loc_txt = {
			name = 'Mini Spectral Pack',
			text = {
				'Choose {C:attention}#1#{} of up to',
				'{C:attention}#2# {C:spectral}Spectral{} cards to',
				'be used immediately',
				spriter('mailingway')
			}
		},
		atlas = 'jenbooster',
		pos = { x = 3 + i, y = 2 },
		weight = .45,
		cost = 2,
		config = { extra = 1, choose = 1 },
		discovered = true,
		draw_hand = true,
		loc_vars = function(self, info_queue, card)
			return { vars = { card.ability.choose, card.ability.extra } }
		end,
		ease_background_colour = function(self) ease_background_colour_blind(G.STATES.SPECTRAL_PACK) end,
		create_UIBox = function(self) return create_UIBox_spectral_pack() end,
		particles = function(self)
			G.booster_pack_sparkles = Particles(1, 1, 0, 0, {
				timer = 0.015,
				scale = 0.1,
				initialize = true,
				lifespan = 3,
				speed = 0.2,
				padding = -1,
				attach = G.ROOM_ATTACH,
				colours = { G.C.WHITE, lighten(G.C.GOLD, 0.2) },
				fill = true
			})
			G.booster_pack_sparkles.fade_alpha = 1
			G.booster_pack_sparkles:fade(1, 0)
		end,
		create_card = function(self, card, i)
			return { set = "Spectral", area = G.pack_cards, skip_materialize = true, soulable = true, key_append = "spe" }
		end,
	}
end

for i = 1, 4 do
	SMODS.Booster {
		key = 'unopack' .. i,
		loc_txt = {
			name = 'UNO Pack',
			text = {
				'Choose {C:attention}#1#{} of up to',
				'{C:attention}#2# {C:uno}UNO{} cards to',
				'be used immediately',
				spriter('ocksie')
			}
		},
		atlas = 'jenbooster',
		pos = { x = i - 1, y = 1 },
		weight = 1,
		cost = 4,
		config = { extra = 3, choose = 1 },
		discovered = true,
		loc_vars = function(self, info_queue, card)
			return { vars = { card.ability.choose, card.ability.extra } }
		end,
		ease_background_colour = function(self)
			ease_background_colour { new_colour = HEX(i == 1 and 'ED1C24' or i == 2 and '0072BC' or i == 3 and '50AA44' or i == 4 and 'FFDE16' or 'ED1C24'), special_colour = HEX('000000'), contrast = 5 }
		end,
		create_UIBox = function(self)
			local _size = SMODS.OPENED_BOOSTER.ability.extra
			G.pack_cards = CardArea(
				G.ROOM.T.x + 9 + G.hand.T.x, G.hand.T.y,
				math.max(1, math.min(_size, 5)) * G.CARD_W * 1.1,
				1.05 * G.CARD_H,
				{ card_limit = _size, type = 'consumeable', highlight_limit = 1 })

			local t = {
				n = G.UIT.ROOT,
				config = { align = 'tm', r = 0.15, colour = G.C.CLEAR, padding = 0.15 },
				nodes = {
					{
						n = G.UIT.R,
						config = { align = "cl", colour = G.C.CLEAR, r = 0.15, padding = 0.1, minh = 2, shadow = true },
						nodes = {
							{
								n = G.UIT.R,
								config = { align = "cm" },
								nodes = {
									{
										n = G.UIT.C,
										config = { align = "cm", padding = 0.1 },
										nodes = {
											{
												n = G.UIT.C,
												config = { align = "cm", r = 0.2, colour = G.C.CLEAR, shadow = true },
												nodes = {
													{ n = G.UIT.O, config = { object = G.pack_cards } }, }
											} }
									} }
							},
							{ n = G.UIT.R, config = { align = "cm" }, nodes = {} },
							{
								n = G.UIT.R,
								config = { align = "tm" },
								nodes = {
									{ n = G.UIT.C, config = { align = "tm", padding = 0.05, minw = 2.4 }, nodes = {} },
									{
										n = G.UIT.C,
										config = { align = "tm", padding = 0.05 },
										nodes = {
											UIBox_dyn_container({
												{
													n = G.UIT.C,
													config = { align = "cm", padding = 0.05, minw = 4 },
													nodes = {
														{
															n = G.UIT.R,
															config = { align = "bm", padding = 0.05 },
															nodes = {
																{ n = G.UIT.O, config = { object = DynaText({ string = { 'UNO Pack ' }, colours = { G.C.WHITE }, shadow = true, rotate = true, bump = true, spacing = 2, scale = 0.7, maxw = 4, pop_in = 0.5 }) } } }
														},
														{
															n = G.UIT.R,
															config = { align = "bm", padding = 0.05 },
															nodes = {
																{ n = G.UIT.O, config = { object = DynaText({ string = { localize('k_choose') .. ' ' }, colours = { G.C.WHITE }, shadow = true, rotate = true, bump = true, spacing = 2, scale = 0.5, pop_in = 0.7 }) } },
																{ n = G.UIT.O, config = { object = DynaText({ string = { { ref_table = G.GAME, ref_value = 'pack_choices' } }, colours = { G.C.WHITE }, shadow = true, rotate = true, bump = true, spacing = 2, scale = 0.5, pop_in = 0.7 }) } } }
														}, }
												}
											}), }
									},
									{
										n = G.UIT.C,
										config = { align = "tm", padding = 0.05, minw = 2.4 },
										nodes = {
											{ n = G.UIT.R, config = { minh = 0.2 }, nodes = {} },
											{
												n = G.UIT.R,
												config = { align = "tm", padding = 0.2, minh = 1.2, minw = 1.8, r = 0.15, colour = G.C.GREY, one_press = true, button = 'skip_booster', hover = true, shadow = true, func = 'can_skip_booster' },
												nodes = {
													{ n = G.UIT.T, config = { text = localize('b_skip'), scale = 0.5, colour = G.C.WHITE, shadow = true, focus_args = { button = 'y', orientation = 'bm' }, func = 'set_button_pip' } } }
											} }
									} }
							} }
					} }
			}
			return t
		end,
		create_card = function(self, card, i)
			return { set = 'jen_uno', area = G.pack_cards, skip_materialize = true, soulable = true, key_append = 'uno' }
		end
	}
end

for i = 1, 2 do
	SMODS.Booster {
		key = 'jumbounopack' .. i,
		loc_txt = {
			name = 'Jumbo UNO Pack',
			text = {
				'Choose {C:attention}#1#{} of up to',
				'{C:attention}#2# {C:uno}UNO{} cards to',
				'be used immediately',
				spriter('ocksie')
			}
		},
		atlas = 'jenbooster',
		pos = { x = i - 1, y = 2 },
		weight = 1,
		cost = 6,
		config = { extra = 5, choose = 1 },
		discovered = true,
		loc_vars = function(self, info_queue, card)
			return { vars = { card.ability.choose, card.ability.extra } }
		end,
		ease_background_colour = function(self)
			ease_background_colour { new_colour = HEX(i == 1 and 'ED1C24' or i == 2 and '0072BC' or 'ED1C24'), special_colour = HEX('000000'), contrast = 5 }
		end,
		create_UIBox = function(self)
			local _size = SMODS.OPENED_BOOSTER.ability.extra
			G.pack_cards = CardArea(
				G.ROOM.T.x + 9 + G.hand.T.x, G.hand.T.y,
				math.max(1, math.min(_size, 5)) * G.CARD_W * 1.1,
				1.05 * G.CARD_H,
				{ card_limit = _size, type = 'consumeable', highlight_limit = 1 })

			local t = {
				n = G.UIT.ROOT,
				config = { align = 'tm', r = 0.15, colour = G.C.CLEAR, padding = 0.15 },
				nodes = {
					{
						n = G.UIT.R,
						config = { align = "cl", colour = G.C.CLEAR, r = 0.15, padding = 0.1, minh = 2, shadow = true },
						nodes = {
							{
								n = G.UIT.R,
								config = { align = "cm" },
								nodes = {
									{
										n = G.UIT.C,
										config = { align = "cm", padding = 0.1 },
										nodes = {
											{
												n = G.UIT.C,
												config = { align = "cm", r = 0.2, colour = G.C.CLEAR, shadow = true },
												nodes = {
													{ n = G.UIT.O, config = { object = G.pack_cards } }, }
											} }
									} }
							},
							{ n = G.UIT.R, config = { align = "cm" }, nodes = {} },
							{
								n = G.UIT.R,
								config = { align = "tm" },
								nodes = {
									{ n = G.UIT.C, config = { align = "tm", padding = 0.05, minw = 2.4 }, nodes = {} },
									{
										n = G.UIT.C,
										config = { align = "tm", padding = 0.05 },
										nodes = {
											UIBox_dyn_container({
												{
													n = G.UIT.C,
													config = { align = "cm", padding = 0.05, minw = 4 },
													nodes = {
														{
															n = G.UIT.R,
															config = { align = "bm", padding = 0.05 },
															nodes = {
																{ n = G.UIT.O, config = { object = DynaText({ string = { 'UNO Pack ' }, colours = { G.C.WHITE }, shadow = true, rotate = true, bump = true, spacing = 2, scale = 0.7, maxw = 4, pop_in = 0.5 }) } } }
														},
														{
															n = G.UIT.R,
															config = { align = "bm", padding = 0.05 },
															nodes = {
																{ n = G.UIT.O, config = { object = DynaText({ string = { localize('k_choose') .. ' ' }, colours = { G.C.WHITE }, shadow = true, rotate = true, bump = true, spacing = 2, scale = 0.5, pop_in = 0.7 }) } },
																{ n = G.UIT.O, config = { object = DynaText({ string = { { ref_table = G.GAME, ref_value = 'pack_choices' } }, colours = { G.C.WHITE }, shadow = true, rotate = true, bump = true, spacing = 2, scale = 0.5, pop_in = 0.7 }) } } }
														}, }
												}
											}), }
									},
									{
										n = G.UIT.C,
										config = { align = "tm", padding = 0.05, minw = 2.4 },
										nodes = {
											{ n = G.UIT.R, config = { minh = 0.2 }, nodes = {} },
											{
												n = G.UIT.R,
												config = { align = "tm", padding = 0.2, minh = 1.2, minw = 1.8, r = 0.15, colour = G.C.GREY, one_press = true, button = 'skip_booster', hover = true, shadow = true, func = 'can_skip_booster' },
												nodes = {
													{ n = G.UIT.T, config = { text = localize('b_skip'), scale = 0.5, colour = G.C.WHITE, shadow = true, focus_args = { button = 'y', orientation = 'bm' }, func = 'set_button_pip' } } }
											} }
									} }
							} }
					} }
			}
			return t
		end,
		create_card = function(self, card, i)
			return { set = 'jen_uno', area = G.pack_cards, skip_materialize = true, soulable = true, key_append = 'uno' }
		end
	}
end

for i = 1, 2 do
	SMODS.Booster {
		key = 'megaunopack' .. i,
		loc_txt = {
			name = 'Mega UNO Pack',
			text = {
				'Choose {C:attention}#1#{} of up to',
				'{C:attention}#2# {C:uno}UNO{} cards to',
				'be used immediately',
				spriter('ocksie')
			}
		},
		atlas = 'jenbooster',
		pos = { x = i + 1, y = 2 },
		weight = .25,
		cost = 8,
		config = { extra = 5, choose = 2 },
		discovered = true,
		loc_vars = function(self, info_queue, card)
			return { vars = { card.ability.choose, card.ability.extra } }
		end,
		ease_background_colour = function(self)
			ease_background_colour { new_colour = HEX('2a2a2a'), special_colour = HEX('000000'), contrast = 5 }
		end,
		create_UIBox = function(self)
			local _size = SMODS.OPENED_BOOSTER.ability.extra
			G.pack_cards = CardArea(
				G.ROOM.T.x + 9 + G.hand.T.x, G.hand.T.y,
				math.max(1, math.min(_size, 5)) * G.CARD_W * 1.1,
				1.05 * G.CARD_H,
				{ card_limit = _size, type = 'consumeable', highlight_limit = 1 })

			local t = {
				n = G.UIT.ROOT,
				config = { align = 'tm', r = 0.15, colour = G.C.CLEAR, padding = 0.15 },
				nodes = {
					{
						n = G.UIT.R,
						config = { align = "cl", colour = G.C.CLEAR, r = 0.15, padding = 0.1, minh = 2, shadow = true },
						nodes = {
							{
								n = G.UIT.R,
								config = { align = "cm" },
								nodes = {
									{
										n = G.UIT.C,
										config = { align = "cm", padding = 0.1 },
										nodes = {
											{
												n = G.UIT.C,
												config = { align = "cm", r = 0.2, colour = G.C.CLEAR, shadow = true },
												nodes = {
													{ n = G.UIT.O, config = { object = G.pack_cards } }, }
											} }
									} }
							},
							{ n = G.UIT.R, config = { align = "cm" }, nodes = {} },
							{
								n = G.UIT.R,
								config = { align = "tm" },
								nodes = {
									{ n = G.UIT.C, config = { align = "tm", padding = 0.05, minw = 2.4 }, nodes = {} },
									{
										n = G.UIT.C,
										config = { align = "tm", padding = 0.05 },
										nodes = {
											UIBox_dyn_container({
												{
													n = G.UIT.C,
													config = { align = "cm", padding = 0.05, minw = 4 },
													nodes = {
														{
															n = G.UIT.R,
															config = { align = "bm", padding = 0.05 },
															nodes = {
																{ n = G.UIT.O, config = { object = DynaText({ string = { 'UNO Pack ' }, colours = { G.C.WHITE }, shadow = true, rotate = true, bump = true, spacing = 2, scale = 0.7, maxw = 4, pop_in = 0.5 }) } } }
														},
														{
															n = G.UIT.R,
															config = { align = "bm", padding = 0.05 },
															nodes = {
																{ n = G.UIT.O, config = { object = DynaText({ string = { localize('k_choose') .. ' ' }, colours = { G.C.WHITE }, shadow = true, rotate = true, bump = true, spacing = 2, scale = 0.5, pop_in = 0.7 }) } },
																{ n = G.UIT.O, config = { object = DynaText({ string = { { ref_table = G.GAME, ref_value = 'pack_choices' } }, colours = { G.C.WHITE }, shadow = true, rotate = true, bump = true, spacing = 2, scale = 0.5, pop_in = 0.7 }) } } }
														}, }
												}
											}), }
									},
									{
										n = G.UIT.C,
										config = { align = "tm", padding = 0.05, minw = 2.4 },
										nodes = {
											{ n = G.UIT.R, config = { minh = 0.2 }, nodes = {} },
											{
												n = G.UIT.R,
												config = { align = "tm", padding = 0.2, minh = 1.2, minw = 1.8, r = 0.15, colour = G.C.GREY, one_press = true, button = 'skip_booster', hover = true, shadow = true, func = 'can_skip_booster' },
												nodes = {
													{ n = G.UIT.T, config = { text = localize('b_skip'), scale = 0.5, colour = G.C.WHITE, shadow = true, focus_args = { button = 'y', orientation = 'bm' }, func = 'set_button_pip' } } }
											} }
									} }
							} }
					} }
			}
			return t
		end,
		create_card = function(self, card, i)
			return { set = 'jen_uno', area = G.pack_cards, skip_materialize = true, soulable = true, key_append = 'uno' }
		end
	}
end

for i = 1, 2 do
	SMODS.Booster {
		key = 'miniunopack' .. i,
		loc_txt = {
			name = 'Mini UNO Pack',
			text = {
				'Choose {C:attention}#1#{} of up to',
				'{C:attention}#2# {C:uno}UNO{} cards to',
				'be used immediately',
				spriter('ocksie')
			}
		},
		atlas = 'jenbooster',
		pos = { x = i - 1, y = 3 },
		weight = .8,
		cost = 2,
		config = { extra = 2, choose = 1 },
		discovered = true,
		loc_vars = function(self, info_queue, card)
			return { vars = { card.ability.choose, card.ability.extra } }
		end,
		ease_background_colour = function(self)
			ease_background_colour { new_colour = HEX(i == 1 and 'FFDE16' or i == 2 and '50AA44' or 'FFDE16'), special_colour = HEX('000000'), contrast = 5 }
		end,
		create_UIBox = function(self)
			local _size = SMODS.OPENED_BOOSTER.ability.extra
			G.pack_cards = CardArea(
				G.ROOM.T.x + 9 + G.hand.T.x, G.hand.T.y,
				math.max(1, math.min(_size, 5)) * G.CARD_W * 1.1,
				1.05 * G.CARD_H,
				{ card_limit = _size, type = 'consumeable', highlight_limit = 1 })

			local t = {
				n = G.UIT.ROOT,
				config = { align = 'tm', r = 0.15, colour = G.C.CLEAR, padding = 0.15 },
				nodes = {
					{
						n = G.UIT.R,
						config = { align = "cl", colour = G.C.CLEAR, r = 0.15, padding = 0.1, minh = 2, shadow = true },
						nodes = {
							{
								n = G.UIT.R,
								config = { align = "cm" },
								nodes = {
									{
										n = G.UIT.C,
										config = { align = "cm", padding = 0.1 },
										nodes = {
											{
												n = G.UIT.C,
												config = { align = "cm", r = 0.2, colour = G.C.CLEAR, shadow = true },
												nodes = {
													{ n = G.UIT.O, config = { object = G.pack_cards } }, }
											} }
									} }
							},
							{ n = G.UIT.R, config = { align = "cm" }, nodes = {} },
							{
								n = G.UIT.R,
								config = { align = "tm" },
								nodes = {
									{ n = G.UIT.C, config = { align = "tm", padding = 0.05, minw = 2.4 }, nodes = {} },
									{
										n = G.UIT.C,
										config = { align = "tm", padding = 0.05 },
										nodes = {
											UIBox_dyn_container({
												{
													n = G.UIT.C,
													config = { align = "cm", padding = 0.05, minw = 4 },
													nodes = {
														{
															n = G.UIT.R,
															config = { align = "bm", padding = 0.05 },
															nodes = {
																{ n = G.UIT.O, config = { object = DynaText({ string = { 'UNO Pack ' }, colours = { G.C.WHITE }, shadow = true, rotate = true, bump = true, spacing = 2, scale = 0.7, maxw = 4, pop_in = 0.5 }) } } }
														},
														{
															n = G.UIT.R,
															config = { align = "bm", padding = 0.05 },
															nodes = {
																{ n = G.UIT.O, config = { object = DynaText({ string = { localize('k_choose') .. ' ' }, colours = { G.C.WHITE }, shadow = true, rotate = true, bump = true, spacing = 2, scale = 0.5, pop_in = 0.7 }) } },
																{ n = G.UIT.O, config = { object = DynaText({ string = { { ref_table = G.GAME, ref_value = 'pack_choices' } }, colours = { G.C.WHITE }, shadow = true, rotate = true, bump = true, spacing = 2, scale = 0.5, pop_in = 0.7 }) } } }
														}, }
												}
											}), }
									},
									{
										n = G.UIT.C,
										config = { align = "tm", padding = 0.05, minw = 2.4 },
										nodes = {
											{ n = G.UIT.R, config = { minh = 0.2 }, nodes = {} },
											{
												n = G.UIT.R,
												config = { align = "tm", padding = 0.2, minh = 1.2, minw = 1.8, r = 0.15, colour = G.C.GREY, one_press = true, button = 'skip_booster', hover = true, shadow = true, func = 'can_skip_booster' },
												nodes = {
													{ n = G.UIT.T, config = { text = localize('b_skip'), scale = 0.5, colour = G.C.WHITE, shadow = true, focus_args = { button = 'y', orientation = 'bm' }, func = 'set_button_pip' } } }
											} }
									} }
							} }
					} }
			}
			return t
		end,
		create_card = function(self, card, i)
			return { set = 'jen_uno', area = G.pack_cards, skip_materialize = true, soulable = true, key_append = 'uno' }
		end
	}
end

for i = 1, 2 do
	SMODS.Booster {
		key = 'standardbundle' .. i,
		loc_txt = {
			name = 'Standard Bundle',
			text = {
				'Choose {C:attention}#1#{} of up to',
				'{C:attention}#2# playing cards{} to',
				'add to your deck',
				spriter('cozyori')
			}
		},
		atlas = 'jenbooster',
		pos = { x = i + 6, y = 0 },
		weight = .1,
		cost = 10,
		config = { extra = 10, choose = 5 },
		discovered = true,
		loc_vars = function(self, info_queue, card)
			return { vars = { card.ability.choose, card.ability.extra } }
		end,
		ease_background_colour = function(self) ease_background_colour_blind(G.STATES.STANDARD_PACK) end,
		create_UIBox = function(self) return create_UIBox_standard_pack() end,
		particles = function(self)
			G.booster_pack_sparkles = Particles(1, 1, 0, 0, {
				timer = 0.015,
				scale = 0.3,
				initialize = true,
				lifespan = 3,
				speed = 0.2,
				padding = -1,
				attach = G.ROOM_ATTACH,
				colours = { G.C.BLACK, G.C.RED },
				fill = true
			})
			G.booster_pack_sparkles.fade_alpha = 1
			G.booster_pack_sparkles:fade(1, 0)
		end,
		create_card = function(self, card, i)
			local _edition = poll_edition('standard_edition' .. G.GAME.round_resets.ante, 2, true)
			local _seal = SMODS.poll_seal({ mod = 10 })
			return {
				set = (pseudorandom(pseudoseed('stdset' .. G.GAME.round_resets.ante)) > 0.6) and "Enhanced" or
					"Base",
				edition = _edition,
				seal = _seal,
				area = G.pack_cards,
				skip_materialize = true,
				soulable = true,
				key_append =
				"sta"
			}
		end,
	}
end

for i = 1, 2 do
	SMODS.Booster {
		key = 'arcanabundle' .. i,
		loc_txt = {
			name = 'Arcana Bundle',
			text = {
				'Choose {C:attention}#1#{} of up to',
				'{C:attention}#2# {C:tarot}Tarot{} cards to',
				'be used immediately',
				spriter('cozyori')
			}
		},
		atlas = 'jenbooster',
		pos = { x = i + 6, y = 1 },
		weight = .1,
		cost = 10,
		config = { extra = 10, choose = 5 },
		discovered = true,
		draw_hand = true,
		loc_vars = function(self, info_queue, card)
			return { vars = { card.ability.choose, card.ability.extra } }
		end,
		ease_background_colour = function(self) ease_background_colour_blind(G.STATES.TAROT_PACK) end,
		create_UIBox = function(self) return create_UIBox_arcana_pack() end,
		particles = function(self)
			G.booster_pack_sparkles = Particles(1, 1, 0, 0, {
				timer = 0.015,
				scale = 0.2,
				initialize = true,
				lifespan = 1,
				speed = 1.1,
				padding = -1,
				attach = G.ROOM_ATTACH,
				colours = { G.C.WHITE, lighten(G.C.PURPLE, 0.4), lighten(G.C.PURPLE, 0.2), lighten(G.C.GOLD, 0.2) },
				fill = true
			})
			G.booster_pack_sparkles.fade_alpha = 1
			G.booster_pack_sparkles:fade(1, 0)
		end,
		create_card = function(self, card, i)
			local _card
			if G.GAME.used_vouchers.v_omen_globe and pseudorandom('omen_globe') > 0.8 then
				_card = {
					set = "Spectral",
					area = G.pack_cards,
					skip_materialize = true,
					soulable = true,
					key_append =
					"ar2"
				}
			else
				_card = {
					set = "Tarot",
					area = G.pack_cards,
					skip_materialize = true,
					soulable = true,
					key_append =
					"ar1"
				}
			end
			return _card
		end
	}
end

for i = 1, 2 do
	SMODS.Booster {
		key = 'celestialbundle' .. i,
		loc_txt = {
			name = 'Celestial Bundle',
			text = {
				'Choose {C:attention}#1#{} of up to',
				'{C:attention}#2# {C:planet}Planet{} cards to',
				'be used immediately',
				spriter('cozyori')
			}
		},
		atlas = 'jenbooster',
		pos = { x = i + 6, y = 2 },
		weight = .8,
		cost = 10,
		config = { extra = 10, choose = 5 },
		discovered = true,
		loc_vars = function(self, info_queue, card)
			return { vars = { card.ability.choose, card.ability.extra } }
		end,
		ease_background_colour = function(self) ease_background_colour_blind(G.STATES.PLANET_PACK) end,
		create_UIBox = function(self) return create_UIBox_celestial_pack() end,
		particles = function(self)
			G.booster_pack_stars = Particles(1, 1, 0, 0, {
				timer = 0.07,
				scale = 0.1,
				initialize = true,
				lifespan = 15,
				speed = 0.1,
				padding = -4,
				attach = G.ROOM_ATTACH,
				colours = { G.C.WHITE, HEX('a7d6e0'), HEX('fddca0') },
				fill = true
			})
			G.booster_pack_meteors = Particles(1, 1, 0, 0, {
				timer = 2,
				scale = 0.05,
				lifespan = 1.5,
				speed = 4,
				attach = G.ROOM_ATTACH,
				colours = { G.C.WHITE },
				fill = true
			})
		end,
		create_card = function(self, card, i)
			local _card
			if G.GAME.used_vouchers.v_telescope and i == 1 then
				local _planet, _hand, _tally = nil, nil, 0
				for k, v in ipairs(G.handlist) do
					if G.GAME.hands[v].visible and G.GAME.hands[v].played > _tally then
						_hand = v
						_tally = G.GAME.hands[v].played
					end
				end
				if _hand then
					for k, v in pairs(G.P_CENTER_POOLS.Planet) do
						if v.config.hand_type == _hand then
							_planet = v.key
						end
					end
				end
				_card = {
					set = "Planet",
					area = G.pack_cards,
					skip_materialize = true,
					soulable = true,
					key = _planet,
					key_append =
					"pl1"
				}
			else
				_card = {
					set = "Planet",
					area = G.pack_cards,
					skip_materialize = true,
					soulable = true,
					key_append =
					"pl1"
				}
			end
			return _card
		end
	}
end

SMODS.Booster {
	key = 'spectralbundle',
	loc_txt = {
		name = 'Spectral Bundle',
		text = {
			'Choose {C:attention}#1#{} of up to',
			'{C:attention}#2# {C:spectral}Spectral{} cards to',
			'be used immediately',
			spriter('cozyori')
		}
	},
	atlas = 'jenbooster',
	pos = { x = 7, y = 3 },
	weight = .075,
	cost = 10,
	config = { extra = 8, choose = 4 },
	discovered = true,
	draw_hand = true,
	loc_vars = function(self, info_queue, card)
		return { vars = { card.ability.choose, card.ability.extra } }
	end,
	ease_background_colour = function(self) ease_background_colour_blind(G.STATES.SPECTRAL_PACK) end,
	create_UIBox = function(self) return create_UIBox_spectral_pack() end,
	particles = function(self)
		G.booster_pack_sparkles = Particles(1, 1, 0, 0, {
			timer = 0.015,
			scale = 0.1,
			initialize = true,
			lifespan = 3,
			speed = 0.2,
			padding = -1,
			attach = G.ROOM_ATTACH,
			colours = { G.C.WHITE, lighten(G.C.GOLD, 0.2) },
			fill = true
		})
		G.booster_pack_sparkles.fade_alpha = 1
		G.booster_pack_sparkles:fade(1, 0)
	end,
	create_card = function(self, card, i)
		return { set = "Spectral", area = G.pack_cards, skip_materialize = true, soulable = true, key_append = "spe" }
	end,
}

SMODS.Booster {
	key = 'iconpack',
	loc_txt = {
		name = '{C:red}Icon Pack',
		text = {
			'Choose {C:attention}#1#{} of up to',
			'{C:attention}#2# {C:almanac,E:1}Almanac {C:attention}Jokers',
			'{C:green}#3#% chance{} to contain {C:dark_edition,E:1}Jen\'s Sigil',
			'if you have {C:blood}Kosmos',
			'{C:green}2% chance{} to contain an {C:cry_azure,s:1.5,E:1}Extraordinary{} Joker',
			' ',
			'{C:red}Contains only Rot if the',
			'{C:red}current Ante is not greater',
			'{C:red}than the furthest Ante an',
			'{C:red}Icon Pack was opened this run',
			'{C:inactive}(Currently {V:1}Ante #4#{C:inactive})',
			spriter('mailingway')
		},
	},
	atlas = 'jenbooster',
	pos = { x = 0, y = 0 },
	weight = 1,
	cost = 15,
	config = { extra = 5, choose = 1, icon_pack = true },
	discovered = true,
	in_pool = function()
		return (G.GAME.latest_ante_icon_pack_opening or 0) < G.GAME.round_resets.ante
	end,
	loc_vars = function(self, info_queue, card)
		return { vars = { card.ability.choose, card.ability.extra, math.min(1, 1 / (100 - (G.GAME.icon_pity or 0))) * 100, tostring(((G.GAME or {}).latest_ante_icon_pack_opening or 0)), colours = { ((G.GAME or {}).latest_ante_icon_pack_opening or 0) < (((G.GAME or {}).round_resets or {}).ante or 0) and G.C.GREEN or G.C.RED } } }
	end,
	create_card = function(self, card, i)
		if (G.GAME.latest_ante_icon_pack_opening or 0) < G.GAME.round_resets.ante then
			local possible = {}
			for k, v in pairs(G.P_CENTERS) do
				if v.set == 'Joker' and string.sub(k, 1, 6) == 'j_jen_' and not Jen.overpowered(v.rarity) then
					table.insert(possible, v.key)
				end
			end
			if math.floor(i) == math.floor(SMODS.OPENED_BOOSTER.ability.extra) then
				G.GAME.latest_ante_icon_pack_opening = G.GAME.round_resets.ante
				if get_kosmos() then
					if jl.chance('iconpack_sigil', math.max(1, 100 - (G.GAME.icon_pity or 0)), true) then
						G.GAME.icon_pity = 0
						QR(function()
							Q(function()
								play_sound_q('jen_chime', .5, 0.65); jl.a('Sigil!', G.SETTINGS.GAMESPEED * 3, 2,
									G.C.almanac); jl.rd(3); return true
							end)
							return true
						end, 99)
						return {
							set = 'Joker',
							area = G.pack_cards,
							skip_materialize = true,
							soulable = false,
							key =
							'j_jen_sigil',
							key_append = "almanac"
						}
					else
						G.GAME.icon_pity = (G.GAME.icon_pity or 0) + 1
					end
				end
				return {
					set = 'Joker',
					area = G.pack_cards,
					skip_materialize = true,
					soulable = false,
					key =
						pseudorandom_element(possible, pseudoseed('almanac' .. G.GAME.round_resets.ante)),
					key_append = "almanac"
				}
			elseif math.floor(i) == 1 and jl.chance('iconpack_extraordinary', 50, true) then
				QR(function()
					Q(function()
						play_sound_q('jen_chime', .75, 0.65); jl.a('Extraordinary!', G.SETTINGS.GAMESPEED * 2.5, 1.25,
							G.C.jen_RGB); jl.rd(2.5); return true
					end)
					return true
				end, 99)
				return create_card("Joker", G.pack_cards, nil, 'jen_extraordinary', true, true, nil, 'almanac')
			else
				return {
					set = 'Joker',
					area = G.pack_cards,
					skip_materialize = true,
					soulable = false,
					key =
						pseudorandom_element(possible, pseudoseed('almanac' .. G.GAME.round_resets.ante)),
					key_append = "almanac"
				}
			end
		else
			return {
				set = 'Joker',
				area = G.pack_cards,
				skip_materialize = true,
				soulable = false,
				key = 'j_jen_rot',
				key_append =
				"almanac"
			}
		end
	end,
	ease_background_colour = function(self)
		ease_background_colour { new_colour = HEX('000000'), special_colour = HEX('ff0000'), contrast = 5 }
	end,
	create_UIBox = function(self)
		local _size = SMODS.OPENED_BOOSTER.ability.extra
		G.pack_cards = CardArea(
			G.ROOM.T.x + 9 + G.hand.T.x, G.hand.T.y,
			math.max(1, math.min(_size, 5)) * G.CARD_W * 1.1,
			1.05 * G.CARD_H,
			{ card_limit = _size, type = 'consumeable', highlight_limit = 1 })

		local t = {
			n = G.UIT.ROOT,
			config = { align = 'tm', r = 0.15, colour = G.C.CLEAR, padding = 0.15 },
			nodes = {
				{
					n = G.UIT.R,
					config = { align = "cl", colour = G.C.CLEAR, r = 0.15, padding = 0.1, minh = 2, shadow = true },
					nodes = {
						{
							n = G.UIT.R,
							config = { align = "cm" },
							nodes = {
								{
									n = G.UIT.C,
									config = { align = "cm", padding = 0.1 },
									nodes = {
										{
											n = G.UIT.C,
											config = { align = "cm", r = 0.2, colour = G.C.CLEAR, shadow = true },
											nodes = {
												{ n = G.UIT.O, config = { object = G.pack_cards } }, }
										} }
								} }
						},
						{ n = G.UIT.R, config = { align = "cm" }, nodes = {} },
						{
							n = G.UIT.R,
							config = { align = "tm" },
							nodes = {
								{ n = G.UIT.C, config = { align = "tm", padding = 0.05, minw = 2.4 }, nodes = {} },
								{
									n = G.UIT.C,
									config = { align = "tm", padding = 0.05 },
									nodes = {
										UIBox_dyn_container({
											{
												n = G.UIT.C,
												config = { align = "cm", padding = 0.05, minw = 4 },
												nodes = {
													{
														n = G.UIT.R,
														config = { align = "bm", padding = 0.05 },
														nodes = {
															{ n = G.UIT.O, config = { object = DynaText({ string = { 'Icon Pack ' }, colours = { G.C.CRY_ASCENDANT }, shadow = true, rotate = true, bump = true, spacing = 2, scale = 0.7, maxw = 4, pop_in = 0.5 }) } } }
													},
													{
														n = G.UIT.R,
														config = { align = "bm", padding = 0.05 },
														nodes = {
															{ n = G.UIT.O, config = { object = DynaText({ string = { 'Indoctrinate ' }, colours = { G.C.CRY_BLOSSOM }, shadow = true, rotate = true, bump = true, spacing = 2, scale = 0.5, pop_in = 0.7 }) } },
															{ n = G.UIT.O, config = { object = DynaText({ string = { { ref_table = G.GAME, ref_value = 'pack_choices' } }, colours = { G.C.CRY_EXOTIC }, shadow = true, rotate = true, bump = true, spacing = 2, scale = 0.5, pop_in = 0.7 }) } } }
													}, }
											}
										}), }
								},
								{
									n = G.UIT.C,
									config = { align = "tm", padding = 0.05, minw = 2.4 },
									nodes = {
										{ n = G.UIT.R, config = { minh = 0.2 }, nodes = {} },
										{
											n = G.UIT.R,
											config = { align = "tm", padding = 0.2, minh = 1.2, minw = 1.8, r = 0.15, colour = G.C.GREY, one_press = true, button = 'skip_booster', hover = true, shadow = true, func = 'can_skip_booster' },
											nodes = {
												{ n = G.UIT.T, config = { text = localize('b_skip'), scale = 0.5, colour = G.C.WHITE, shadow = true, focus_args = { button = 'y', orientation = 'bm' }, func = 'set_button_pip' } } }
										} }
								} }
						} }
				} }
		}
		return t
	end,
}

--BLINDS

if SMODS.BlindEdition then
	SMODS.BlindEdition:take_ownership('ble_base', {
		key = 'base',
		loc_txt = {
			name = "Base",
			text = { "No additional effects" }
		},
		has_text = false,
		weight = 8
	})
	SMODS.BlindEdition:take_ownership('ble_foil', {
		key = 'foil',
		blind_shader = 'foil',
		loc_txt = {
			name = "Foil",
			text = { "+50% blind size" }
		},
		special_colour = G.C.CHIPS,
		blind_size_mult = 1.5,
		contrast = 3,
		weight = 0.4,
		set_blind = function(self, blind_on_deck)
			play_sound_q('foil1', 0.9)
		end,
		dollars_mod = 1
	})
	SMODS.BlindEdition:take_ownership('ble_holographic', {
		key = 'holographic',
		blind_shader = 'holo',
		loc_txt = {
			name = "Holographic",
			text = { "-1 hand size" }
		},
		special_colour = G.C.MULT,
		contrast = 3,
		weight = 0.3,
		set_blind = function(self, blind_on_deck)
			play_sound_q('holo1', 0.9)
			G.hand:change_size(-1)
		end,
		defeat = function(self, blind_on_deck)
			G.hand:change_size(1)
		end,
		dollars_mod = 2
	})
	SMODS.BlindEdition:take_ownership('ble_polychrome', {
		key = 'polychrome',
		blind_shader = 'polychrome',
		weight = 0.2,
		dollars_mod = 3,
		loc_txt = {
			name = "Polychrome",
			text = { "-1 hand" }
		},
		new_colour = G.C.FILTER,
		special_colour = G.C.CHIPS,
		tertiary_colour = G.C.MULT,
		contrast = 3,
		set_blind = function(self, blind_on_deck)
			play_sound_q('polychrome1', 0.9)
			Q(function()
				if G.GAME.current_round.hands_left > 1 then ease_hands_played(-1) end
				return true
			end, 0.1, nil, 'after')
		end
	})
	SMODS.BlindEdition:take_ownership('ble_negative', {
		key = 'negative',
		blind_shader = { 'negative', 'negative_shine' },
		weight = 0.01,
		loc_txt = {
			name = "Negative",
			text = {
				"+700% blind size,",
				"+1 joker slot reward"
			}
		},
		blind_size_mult = 8,
		special_colour = G.C.BLACK,
		new_colour = G.C.SECONDARY_SET.Spectral,
		contrast = 3,
		set_blind = function(self, blind_on_deck)
			play_sound_q('negative', 0.9)
		end,
		defeat = function(self, blind_on_deck)
			if G.jokers then G.jokers:change_size_absolute(1) end
		end
	})
	SMODS.BlindEdition {
		key = 'laminated',
		blind_shader = 'jen_laminated',
		loc_txt = {
			name = "Laminated",
			text = { "No reward money" }
		},
		special_colour = G.C.SECONDARY_SET.Planet,
		contrast = 3,
		set_blind = function(self, blind_on_deck)
			play_sound_q('jen_e_laminated', 0.9)
		end,
		weight = 0.111,
		dollars_mod = function(self, dollars)
			return 0
		end
	}
	SMODS.BlindEdition {
		key = 'chromatic',
		blind_shader = 'jen_chromatic',
		loc_txt = {
			name = "Chromatic",
			text = { "All hands -0.5 levels" }
		},
		special_colour = G.C.CHIPS,
		new_colour = G.C.MULT,
		contrast = 3,
		set_blind = function(self, blind_on_deck)
			play_sound_q('jen_e_chromatic', 0.9)
			lvupallhands(-0.5)
		end,
		weight = 0.25,
		dollars_mod = 2
	}
	SMODS.BlindEdition {
		key = 'ionized',
		blind_shader = 'jen_ionized',
		loc_txt = {
			name = "Ionised",
			text = { "#1#'s level",
				"gets halved" }
		},
		new_colour = G.C.FILTER,
		contrast = 3,
		set_blind = function(self, blind_on_deck)
			play_sound_q('jen_e_ionized', 0.9)
			jl.th(jl.favhand())
			level_up_hand(G.GAME.blind.children.animatedSprite, jl.favhand(), nil,
				-(G.GAME.hands[jl.favhand()].level / 2))
			jl.ch()
		end,
		loc_vars = function(self, blind_on_deck)
			return { localize(jl.favhand(), 'poker_hands') }
		end,
		collection_loc_vars = function(self, blind_on_deck)
			return { 'Most played hand' }
		end,
		weight = 0.15,
		dollars_mod = 4
	}
	SMODS.BlindEdition {
		key = 'gilded',
		blind_shader = 'jen_gilded',
		loc_txt = {
			name = "Gilded",
			text = { "+$20 extra reward money" }
		},
		special_colour = G.C.FILTER,
		new_colour = G.C.MONEY,
		contrast = 3,
		set_blind = function(self, blind_on_deck)
			play_sound_q('jen_e_gilded', 0.9)
		end,
		weight = 0.02,
		dollars_mod = 20
	}
	SMODS.BlindEdition {
		key = 'sharpened',
		blind_shader = 'jen_sharpened',
		loc_txt = {
			name = "Sharpened",
			text = { "+5 random Rental",
				"playing cards" }
		},
		new_colour = G.C.BLACK,
		special_colour = G.C.WHITE,
		contrast = 3,
		set_blind = function(self, blind_on_deck)
			play_sound_q('jen_e_sharpened', 0.9)
			for i = 1, 5 do
				local rental = create_playing_card(nil, G.play, nil, nil, { G.C.MONEY })
				rental.ability.rental = true
				rental:add_to_deck()
				G.play:remove_card(rental)
				G.deck:emplace(rental)
			end
		end,
		weight = 0.15,
		dollars_mod = 2
	}
	--[[SMODS.BlindEdition {
		key = 'diplopia',
		blind_shader = 'jen_diplopia',
		loc_txt = {
			name = "Diplopia",
			text = {"Blind has a second chance",
			"+100% reward money"}
		},
		special_colour = G.C.JOKER_GREY,
		contrast = 3,
		set_blind = function(self, blind_on_deck)
			play_sound_q('jen_e_diplopia', 0.9)
		end,
		weight = 0.1,
		dollars_mod = function(self, dollars)
			return (dollars or 0)*2
		end
	}]]
end

local disblref = Blind.disable

function Blind:disable()
	local obj = self.config.blind
	if obj then
		if obj.immunity then
			play_sound('cancel', 0.8, 1)
			jl.a(obj.immunity_quote or 'Blind is immune!', G.SETTINGS.GAMESPEED * 2, 0.8, obj.boss_colour or G.C.RED)
			G.GAME.blind:wiggle()
			return true
		end
	end
	return disblref(self)
end

local gfrb = G.FUNCS.reroll_boss
G.FUNCS.reroll_boss = function(e)
	local obj = G.P_BLINDS[G.GAME.round_resets.blind_choices.Boss]
	if obj.boss.epic then
		play_sound('cancel', 0.8, 1)
		jl.a(localize('k_nope_ex'), G.SETTINGS.GAMESPEED * 2, 0.8, obj.boss_colour or G.C.RED)
	else
		return gfrb(e)
	end
end

local function update_scoring_mode()
	if get_final_operator and SMODS and SMODS.set_scoring_calculation then
		local op = get_final_operator()
		if op == 0 then
			SMODS.set_scoring_calculation('add')
		elseif op == 1 then
			SMODS.set_scoring_calculation('multiply')
		elseif op == 2 then
			SMODS.set_scoring_calculation('exponent')
		elseif op == 3 then
			register_arrow_scoring_calculations()
			SMODS.set_scoring_calculation('arrow_2')
		elseif op == 4 then
			register_arrow_scoring_calculations()
			SMODS.set_scoring_calculation('arrow_3')
		elseif op == 5 then
			register_arrow_scoring_calculations()
			SMODS.set_scoring_calculation('arrow_4')
		elseif op == 6 then
			register_arrow_scoring_calculations()
			SMODS.set_scoring_calculation('arrow_5')
		end
	end
end

SMODS.Blind {
	loc_txt = {
		name = 'The Descending',
		text = { 'Decrease Chip-Mult', 'operator by 1 level' }
	},
	key = 'descending',
	config = {},
	boss = { min = 1, max = 10, hardcore = true },
	boss_colour = HEX("b200ff"),
	atlas = 'jenblinds',
	pos = { x = 0, y = 0 },
	vars = {},
	dollars = 15,
	mult = .5,
	defeat = function(self)
		if not G.GAME.blind.disabled and get_final_operator_offset() < 0 then
			offset_final_operator(1)
			update_scoring_mode()
		end
	end,
	set_blind = function(self, reset, silent)
		if not reset then
			offset_final_operator(-1)
			update_scoring_mode()
		end
	end,
	disable = function(self)
		if get_final_operator_offset() < 0 then
			offset_final_operator(1)
			update_scoring_mode()
		end
	end
}

SMODS.Blind {
	loc_txt = {
		name = 'The Grief',
		text = { 'Disabling this blind', 'will destroy every Joker,', 'including Eternals' }
	},
	key = 'grief',
	config = {},
	boss = { min = 4, max = 10, no_orb = true, hardcore = true },
	boss_colour = HEX("0026ff"),
	atlas = 'jenblinds',
	pos = { x = 0, y = 1 },
	vars = {},
	dollars = 7,
	mult = 2,
	in_pool = function() return #SMODS.find_card('j_chicot') > 0 end,
	defeat = function(self)
	end,
	set_blind = function(self, reset, silent)
	end,
	disable = function(self)
		for k, v in pairs(G.jokers.cards) do
			if v:gc().key ~= 'j_jen_kosmos' then
				v:start_dissolve()
			end
		end
	end
}

SMODS.Blind {
	loc_txt = {
		name = 'The Eater',
		text = { 'Destroy all cards', 'previously played this ante,', '+5% score requirement per card destroyed' }
	},
	key = 'eater',
	config = {},
	boss = { min = 1, max = 10, hardcore = true },
	boss_colour = HEX("ff7f7f"),
	atlas = 'jenblinds',
	pos = { x = 0, y = 2 },
	vars = {},
	dollars = 7,
	mult = 2,
	defeat = function(self)
	end,
	set_blind = function(self, reset, silent)
		if not next(SMODS.find_card('j_chicot')) then
			local size_multiplier = 1
			for k, card in ipairs(G.playing_cards) do
				if card.ability.played_this_ante then
					card:start_dissolve()
					size_multiplier = size_multiplier + 0.05
				end
			end
			change_blind_size(G.GAME.blind.chips * size_multiplier)
		end
	end,
	disable = function(self)
	end
}

SMODS.Blind {
	loc_txt = {
		name = 'The Wee',
		text = { 'All non-Wee Jokers debuffed,', 'only 2s or Wees can be played' }
	},
	key = 'wee',
	config = {},
	boss = { min = 1, max = 10, no_orb = true, hardcore = true },
	boss_colour = HEX("7F3F3F"),
	atlas = 'jenblinds',
	pos = { x = 0, y = 3 },
	vars = {},
	dollars = 2,
	mult = 22 / 300,
	debuff_hand = function(self, cards, hand, handname, check)
		for k, v in ipairs(cards) do
			if (v:norank() or v:get_id() ~= 2) and not (v.edition or {}).jen_wee then
				return true
			end
		end
	end,
	get_loc_debuff_text = function(self)
		return "Hand must contain only 2s or Wee cards"
	end,
	recalc_debuff = function(self, card, from_blind)
		return card.area and card.area ~= G.consumeables and (card:norank() or card:get_id() ~= 2) and
			not (card.edition or {}).jen_wee
	end,
}

SMODS.Blind {
	loc_txt = {
		name = 'The One',
		text = { 'Play only 1 hand, no discards' }
	},
	key = 'one',
	config = {},
	boss = { min = 4, max = 10, no_orb = true, hardcore = true },
	boss_colour = HEX('000000'),
	atlas = 'jenblinds',
	pos = { x = 0, y = 4 },
	vars = {},
	dollars = 7,
	mult = 0.75,
	defeat = function(self)
	end,
	set_blind = function(self, reset, silent)
		if not next(SMODS.find_card('j_chicot')) then
			ease_hands_played(-G.GAME.current_round.hands_left + 1)
			ease_discard(-G.GAME.current_round.discards_left)
		end
	end,
	disable = function(self)
	end
}

SMODS.Blind {
	loc_txt = {
		name = 'The Bisected',
		text = { 'Halved hand size' }
	},
	key = 'bisected',
	config = {},
	boss = { min = 2, max = 10, hardcore = true },
	boss_colour = HEX("7f0000"),
	atlas = 'jenblinds',
	pos = { x = 0, y = 5 },
	vars = {},
	dollars = 9,
	mult = 1.75,
	defeat = function(self)
		if not G.GAME.blind.disabled and self.handsize_mod then
			G.hand:change_size(self.handsize_mod)
			self.handsize_mod = nil
		end
	end,
	set_blind = function(self, reset, silent)
		if not reset then
			self.handsize_mod = math.floor(G.hand.config.card_limit / 2)
			G.hand:change_size(-self.handsize_mod)
		end
	end,
	disable = function(self)
		if self.handsize_mod then
			G.hand:change_size(self.handsize_mod)
			self.handsize_mod = nil
		end
	end
}

SMODS.Blind {
	loc_txt = {
		name = 'The Press',
		text = { '-2 hand size per play,', 'discard leftmost and rightmost cards', 'in hand per play' }
	},
	key = 'press',
	config = {},
	boss = { min = 1, max = 10, no_orb = true, hardcore = true },
	boss_colour = HEX("21007f"),
	atlas = 'jenblinds',
	pos = { x = 0, y = 6 },
	vars = {},
	dollars = 12,
	mult = 2,
	press_play = function(self)
		G.E_MANAGER:add_event(Event({
			func = function()
				if G.hand.cards[1] then
					draw_card(G.hand, G.discard, 100, 'down', false, G.hand.cards[1])
				end
				if G.hand.cards[#G.hand.cards] and G.hand.cards[#G.hand.cards] ~= G.hand.cards[1] then
					draw_card(G.hand, G.discard, 100, 'down', false, G.hand.cards[#G.hand.cards])
				end
				return true
			end
		}))
		G.GAME.blind.triggered = true
		self.handsize_mod = (self.handsize_mod or 0) + 2
		G.hand:change_size(-2)
	end,
	defeat = function(self)
		if not G.GAME.blind.disabled and self.handsize_mod then
			G.hand:change_size(self.handsize_mod or 0)
			self.handsize_mod = nil
		end
	end,
	set_blind = function(self, reset, silent)
		if not reset then
			self.handsize_mod = 0
		end
	end,
	disable = function(self)
		if self.handsize_mod then
			G.hand:change_size(self.handsize_mod)
			self.handsize_mod = nil
		end
	end
}

SMODS.Blind {
	loc_txt = {
		name = 'The Solo',
		text = { 'Must play only one card' }
	},
	key = 'solo',
	config = {},
	boss = { min = 3, max = 10, no_orb = true, hardcore = true },
	boss_colour = HEX("cd7998"),
	atlas = 'jenblinds',
	pos = { x = 0, y = 7 },
	vars = {},
	dollars = 10,
	mult = 1,
	debuff_hand = function(self, cards, hand, handname, check)
		return #cards > 1
	end
}

SMODS.Blind {
	loc_txt = {
		name = 'ERR://91*M%/',
		text = { '??????????' }
	},
	key = 'error',
	config = {},
	boss = { min = 1, max = 10, no_orb = true, hardcore = true },
	boss_colour = HEX("ff00ff"),
	atlas = 'jenblinds',
	pos = { x = 0, y = 8 },
	vars = {},
	dollars = 5,
	mult = 1,
	press_play = function(self)
		for i = 1, pseudorandom('err91_randomise', 3, 9) do
			Q(function()
				local bsize = G.GAME.blind.chips
				change_blind_size(bsize * Cryptid.log_random(pseudoseed('err91_randomisesize' .. i), 0.873, 1.265))
				G.GAME.blind:wiggle()
				G.GAME.blind.dollars = math.max(1, G.GAME.blind.dollars + pseudorandom('err91_randomisepayout', -1, 2))
				G.GAME.current_round.dollars_to_be_earned = G.GAME.blind.dollars > 8 and ('$' .. G.GAME.blind.dollars) or
					(string.rep(localize('$'), G.GAME.blind.dollars) .. '')
				if G.HUD_blind then
					local ui_e = G.HUD_blind:get_UIE_by_ID("dollars_to_be_earned")
					if ui_e and ui_e.config and ui_e.config.object and ui_e.config.object.update_text then
						ui_e.config.object:update_text()
						ui_e.config.object:juice_up(0.2, 0.2)
					end
				end
				return true
			end, 1)
		end
		G.GAME.blind.triggered = true
	end
}

SMODS.Blind {
	loc_txt = {
		name = 'The Insignia',
		text = { 'Hand must contain', 'only one suit' }
	},
	key = 'insignia',
	config = {},
	boss = { min = 2, max = 10, no_orb = true, hardcore = true },
	boss_colour = HEX("a5aa00"),
	atlas = 'jenblinds',
	pos = { x = 0, y = 9 },
	vars = {},
	dollars = 7,
	mult = 2,
	debuff_hand = function(self, cards, hand, handname, check)
		local numsuits = 0
		local checked_suits = {}
		for k, card in ipairs(cards) do
			if not card:nosuit() and not checked_suits[card.base.suit] then
				numsuits = numsuits + 1
				checked_suits[card.base.suit] = true
				if numsuits > 1 then return true end
			end
		end
		if numsuits < 1 then return true end
	end
}

SMODS.Blind {
	loc_txt = {
		name = 'The Palette',
		text = { 'Hand must contain', 'at least three suits' }
	},
	key = 'palette',
	config = {},
	boss = { min = 1, max = 10, no_orb = true },
	boss_colour = HEX("ff9cff"),
	atlas = 'jenblinds',
	pos = { x = 0, y = 10 },
	vars = {},
	dollars = 7,
	mult = 2,
	debuff_hand = function(self, cards, hand, handname, check)
		local numsuits = 0
		local checked_suits = {}
		for k, card in ipairs(cards) do
			if not card:nosuit() and not checked_suits[card.base.suit] then
				numsuits = numsuits + 1
				checked_suits[card.base.suit] = true
				if numsuits >= 3 then break end
			end
		end
		return numsuits < 3
	end
}

SMODS.Blind {
	loc_txt = {
		name = 'Ahneharka',
		text = { '+1 Ante per $2 owned,', 'x3 Ante if less than $1 owned (max 1e1 Ante increase)' }
	},
	key = 'epicox',
	config = {},
	showdown = true,
	boss = { min = 1, max = 10, no_orb = true, showdown = true, hardcore = true, epic = true },
	boss_colour = HEX("673305"),
	atlas = 'jenepicblinds',
	pos = { x = 0, y = 0 },
	vars = {},
	dollars = 25,
	mult = 1e9,
	ignore_showdown_check = true,
	in_pool = function(self)
		return G.GAME.round > Jen.config.ante_threshold * 2
	end,
	set_blind = function(self, reset, silent)
		if not reset then
			-- Normalize potentially Big values to primitive numbers for safe math/comparisons
			local dollars = to_number(G.GAME.dollars)
			local base_ante = to_number(G.GAME.round_resets.ante)
			-- Gold-based ante increase with hard cap to avoid overflow/straddle runaway
			local quota = (dollars < 1) and (base_ante * 3) or (dollars / 2)
			quota = math.min(quota or 0, 1e1)
			if jl.invalid_number(quota) then quota = 1e1 end
			local target_ante = base_ante + quota
			G.GAME.blind.chips = get_blind_amount(target_ante) * G.GAME.blind.mult * G.GAME.starting_params.ante_scaling
			G.GAME.blind.chip_text = number_format(G.GAME.blind.chips)
			-- Bypass Straddle mechanics for this ante increase (no start/progress/boost)
			ease_ante(quota, true, true)
			Q(function()
				G.GAME.round_resets.blind_ante = G.GAME.round_resets.ante; G.GAME.blind:set_text()
				return true
			end)
		end
	end
}

SMODS.Blind {
	loc_txt = {
		name = 'Sokeudentalo',
		text = { 'First hand drawn face-down,', 'plays must have at least 3 cards,', 'no identical cards (rank + suit),', 'and 2/3 of played cards must be face-down' }
	},
	key = 'epichouse',
	config = {},
	showdown = true,
	boss = { min = 1, max = 10, no_orb = true, showdown = true, hardcore = true, epic = true },
	boss_colour = HEX("2d4b5d"),
	atlas = 'jenepicblinds',
	pos = { x = 0, y = 1 },
	vars = {},
	dollars = 25,
	mult = 1e9,
	ignore_showdown_check = true,
	in_pool = function(self)
		return G.GAME.round > Jen.config.ante_threshold * 2
	end,
	debuff_hand = function(self, cards, hand, handname, check)
		-- Plays must have at least 3 cards
		if #cards < 3 then return true end
		-- No identical cards (rank + suit) and at least 2/3 face-down
		local numfacedown = 0
		local alreadyhad = {}
		for _, card in ipairs(cards) do
			local suit = (card.base and card.base.suit) or ''
			local suitandrank = card:get_id() .. '_' .. suit
			if alreadyhad[suitandrank] then return true end
			alreadyhad[suitandrank] = true
			if card.facing == 'back' then numfacedown = numfacedown + 1 end
		end
		return numfacedown < math.ceil((#cards * 2) / 3)
	end,
	stay_flipped = function(self, area, card)
		if G.GAME.blind.facedown then
			if not G.GAME.blind.firstpass then
				G.GAME.blind.firstpass = true
				Q(function()
					Q(function()
						G.GAME.blind.firstpass = nil
						G.GAME.blind.facedown = nil
						return true
					end)
					return true
				end)
			end
			return true
		end
	end,
	set_blind = function(self, reset, silent)
		if not reset then
			G.GAME.blind.prepped = true
			G.GAME.blind.facedown = true
		end
	end
}

SMODS.Blind {
	loc_txt = {
		name = 'Ruttoklubi',
		text = { 'If played hand contains', 'no Clubs (ignoring suit modifiers), instantly lose' }
	},
	key = 'epicclub',
	config = {},
	showdown = true,
	boss = { min = 1, max = 10, no_orb = true, showdown = true, hardcore = true, epic = true },
	boss_colour = HEX("677151"),
	atlas = 'jenepicblinds',
	pos = { x = 0, y = 2 },
	vars = {},
	dollars = 25,
	mult = 1e9,
	ignore_showdown_check = true,
	in_pool = function(self)
		return G.GAME.round > Jen.config.ante_threshold * 2
	end,
	modify_hand = function(self, cards, poker_hands, text, mult, hand_chips)
		local safe = false
		for k, v in ipairs(cards) do
			if v.base.suit == 'Clubs' then
				safe = true
				break
			end
		end
		if not safe then
			gameover()
			return to_big(0), to_big(0), true
		end
		return hand_chips, mult, false
	end
}

SMODS.Blind {
	loc_txt = {
		name = 'Sabotöörikala',
		text = { 'Add Stone cards equal to', 'triple the number of cards in deck,', 'no hands containing rankless/suitless cards allowed' }
	},
	key = 'epicfish',
	config = {},
	showdown = true,
	boss = { min = 1, max = 10, no_orb = true, showdown = true, hardcore = true, epic = true },
	boss_colour = HEX("94BBDA"),
	atlas = 'jenepicblinds',
	pos = { x = 0, y = 3 },
	vars = {},
	dollars = 25,
	mult = 1e9,
	ignore_showdown_check = true,
	in_pool = function(self)
		return G.GAME.round > Jen.config.ante_threshold * 2
	end,
	set_blind = function(self, reset, silent)
		if not reset then
			for i = 1, #G.playing_cards * 3 do
				G.E_MANAGER:add_event(Event({
					delay = 0.1,
					func = function()
						G.playing_card = (G.playing_card and G.playing_card + 1) or 1
						local card = Card(G.play.T.x + G.play.T.w / 2, G.play.T.y, G.CARD_W, G.CARD_H,
							pseudorandom_element(G.P_CARDS, pseudoseed('epicfish_stone')), G.P_CENTERS.m_stone,
							{ playing_card = G.playing_card })
						if math.floor(i / 2) ~= i then play_sound('card1') end
						table.insert(G.playing_cards, card)
						G.deck:emplace(card)
						return true
					end
				}))
			end
		end
	end,
	debuff_hand = function(self, cards, hand, handname, check)
		for k, v in ipairs(cards) do
			if v:norank() or v:nosuit() then
				return true
			end
		end
	end
}

SMODS.Blind {
	loc_txt = {
		name = 'Epätoivonikkuna',
		text = { 'If played hand contains', 'no Diamonds (ignoring suit modifiers), instantly lose' }
	},
	key = 'epicwindow',
	config = {},
	showdown = true,
	boss = { min = 1, max = 10, no_orb = true, showdown = true, hardcore = true, epic = true },
	boss_colour = HEX("5e5a53"),
	atlas = 'jenepicblinds',
	pos = { x = 0, y = 4 },
	vars = {},
	dollars = 25,
	mult = 1e9,
	ignore_showdown_check = true,
	in_pool = function(self)
		return G.GAME.round > Jen.config.ante_threshold * 2
	end,
	modify_hand = function(self, cards, poker_hands, text, mult, hand_chips)
		local safe = false
		for k, v in ipairs(cards) do
			if v.base.suit == 'Diamonds' then
				safe = true
				break
			end
		end
		if not safe then
			gameover()
			return to_big(0), to_big(0), true
		end
		return hand_chips, mult, false
	end
}

SMODS.Blind {
	loc_txt = {
		name = 'Verenvuotokoukku',
		text = { 'Destroy all cards in deck', 'that have the same rank & suit as another' }
	},
	key = 'epichook',
	config = {},
	showdown = true,
	boss = { min = 1, max = 10, no_orb = true, showdown = true, hardcore = true, epic = true },
	boss_colour = HEX("5d2414"),
	atlas = 'jenepicblinds',
	pos = { x = 0, y = 5 },
	vars = {},
	dollars = 25,
	mult = 1e9,
	ignore_showdown_check = true,
	in_pool = function(self)
		return G.GAME.round > Jen.config.ante_threshold * 2
	end,
	set_blind = function(self, reset, silent)
		local entries = {}
		if not reset then
			for k, v in ipairs(G.playing_cards) do
				if not v:norankorsuit() then
					local face = v.base.suit .. '_' .. v.base.id
					if not entries[face] then entries[face] = {} end
					table.insert(entries[face], v)
				end
			end
			for k, v in pairs(entries) do
				if #v > 1 then
					for kk, vv in pairs(v) do
						vv:destroy()
					end
				end
			end
		end
	end
}

SMODS.Blind {
	loc_txt = {
		name = 'Tuskallisetkäsiraudat',
		text = { 'Hand size set to 2,', 'must play only Pairs' }
	},
	key = 'epicmanacle',
	config = {},
	showdown = true,
	boss = { min = 1, max = 10, no_orb = true, showdown = true, hardcore = true, epic = true },
	boss_colour = HEX("a2a2a2"),
	atlas = 'jenepicblinds',
	pos = { x = 0, y = 6 },
	vars = {},
	dollars = 25,
	mult = 1e9,
	ignore_showdown_check = true,
	debuff = { hand = { h_size_ge = 2, h_size_le = 2 } },
	get_loc_debuff_text = function(self)
		return "Hand must be a Pair"
	end,
	debuff_hand = function(self, cards, hand, handname, check)
		if handname ~= 'Pair' and not G.GAME.blind.disabled then
			if not check then G.GAME.blind.triggered = true end
			return true
		end
		return false
	end,
	in_pool = function(self)
		return G.GAME.round > Jen.config.ante_threshold * 2
	end,
	defeat = function(self)
		if not G.GAME.blind.disabled and self.handsize_mod then
			G.hand:change_size(self.handsize_mod)
		end
	end,
	set_blind = function(self, reset, silent)
		if not reset then
			self.handsize_mod = G.hand.config.card_limit - 2
			G.hand:change_size(-self.handsize_mod)
		end
	end,
	disable = function(self)
		if self.handsize_mod then
			G.hand:change_size(self.handsize_mod)
		end
	end
}

SMODS.Blind {
	loc_txt = {
		name = 'Ylitsepääsemätönseinä',
		text = { 'Dramatically rescale blind size if', 'score requirement reached', 'before last hand' }
	},
	key = 'epicwall',
	config = {},
	showdown = true,
	boss = { min = 1, max = 10, no_orb = true, showdown = true, hardcore = true, epic = true },
	boss_colour = HEX("4d325c"),
	atlas = 'jenepicblinds',
	pos = { x = 0, y = 7 },
	vars = {},
	dollars = 25,
	mult = 1e100,
	ignore_showdown_check = true,
	in_pool = function(self)
		return G.GAME.round > Jen.config.ante_threshold * 2
	end,
	set_blind = function(self, reset, silent)
		if not reset then
			self.reference_ante = G.GAME.round_resets.ante
		end
	end,
	cry_after_play = function(self)
		if G.GAME.chips >= G.GAME.blind.chips and G.GAME.current_round.hands_left > 0 then
			G.GAME.blind:wiggle()
			local to_ease = G.GAME.blind.chips
			self.reference_ante = math.ceil((self.reference_ante or G.GAME.round_resets.ante) * 1.5)
			G.E_MANAGER:add_event(Event({
				trigger = 'ease',
				blocking = false,
				ref_table = G.GAME.blind,
				ref_value = 'chips',
				ease_to = get_blind_amount(self.reference_ante) * 1e100,
				delay = 0.5,
				func = (function(t) return math.floor(t) end)
			}))
		end
	end
}

-- CONFIGURATION TAB
local function almanac_toggle(name, value, col)
	return {
		n = G.UIT.R,
		config = { align = "cl", padding = 0 },
		nodes = {
			{
				n = G.UIT.C,
				config = { align = "cl", padding = 0.05 },
				nodes = {
					create_toggle { active_colour = G.C.almanac, col = true, label = "", scale = 0.85, w = 0, shadow = true, ref_table = CFG, ref_value = value }
				}
			},
			{
				n = G.UIT.C,
				config = { align = "c", padding = 0 },
				nodes = {
					{ n = G.UIT.T, config = { text = name, scale = 0.35, colour = col or G.C.UI.TEXT_LIGHT } }
				}
			}
		}
	}
end

-- Omega Wheel config adjust functions (defined once globally for safety)
if not G.FUNCS.inc_omega_wheel then
	local function omega_step()
		local safe_isDown = (love and love.keyboard and type(love.keyboard.isDown) == 'function') and
			love.keyboard.isDown or function() return false end
		local shift = safe_isDown('lshift') or safe_isDown('rshift')
		local ctrl = safe_isDown('lctrl') or safe_isDown('rctrl')
		return shift and 50 or ctrl and 5 or 25
	end
	G.FUNCS.inc_omega_wheel = function(e)
		CFG.omega_wheel_count = math.min(500, (CFG.omega_wheel_count or 0) + omega_step())
		CFG.omega_wheel_string = 'Omega Wheel Count: ' .. tostring(CFG.omega_wheel_count)
		if e and e.config and e.config.object and e.config.object.update_text then e.config.object:update_text() end
	end
end
if not G.FUNCS.dec_omega_wheel then
	G.FUNCS.dec_omega_wheel = function(e)
		local safe_isDown = (love and love.keyboard and type(love.keyboard.isDown) == 'function') and
			love.keyboard.isDown or function() return false end
		local shift = safe_isDown('lshift') or safe_isDown('rshift')
		local ctrl = safe_isDown('lctrl') or safe_isDown('rctrl')
		local step = shift and 50 or ctrl and 5 or 25
		CFG.omega_wheel_count = math.max(1, (CFG.omega_wheel_count or 0) - step)
		CFG.omega_wheel_string = 'Omega Wheel Count: ' .. tostring(CFG.omega_wheel_count)
		if e and e.config and e.config.object and e.config.object.update_text then e.config.object:update_text() end
	end
end

SMODS.current_mod.config_tab = function()
	CFG.omega_wheel_count = CFG.omega_wheel_count or 200
	CFG.omega_wheel_string = 'Omega Wheel Count: ' .. tostring(CFG.omega_wheel_count)
	return {
		n = G.UIT.ROOT,
		config = { r = 0.1, align = "cm", padding = 0.1, colour = G.C.BLACK, minw = 8, minh = 4 },
		nodes = {
			{
				n = G.UIT.R,
				config = { padding = 0.05 },
				nodes = {
					{
						n = G.UIT.C,
						config = { minw = G.ROOM.T.w * 0.25, padding = 0.05 },
						nodes = {
							{ n = G.UIT.T, config = { text = 'A game restart is required for changes to apply', scale = 0.35, colour = G.C.UI.TEXT_LIGHT } },
						}
					}
				}
			},
			create_toggle({
				label = "Skip Straddle Animation",
				ref_table = CFG,
				ref_value = "straddle_skip_animation",
				callback = function(val)
					if Jen and Jen.config and Jen.config.straddle then
						Jen.config.straddle.skip_animation = val
					end
				end
			}),
			almanac_toggle('Enable banned items', 'disable_bans', G.C.RED),
			{
				n = G.UIT.R,
				config = { padding = 0.05 },
				nodes = {
					{
						n = G.UIT.C,
						config = { minw = G.ROOM.T.w * 0.25, padding = 0.05 },
						nodes = {
							{ n = G.UIT.T, config = { text = 'Almanac is intended to be played with banned items turned off', scale = 0.25, colour = G.C.UI.TEXT_LIGHT } },
						}
					}
				}
			},
			almanac_toggle('Straddle mechanics', 'straddle'),
			almanac_toggle('Smoother background & score flames', 'hq_shaders'),
			almanac_toggle('Curb reroll abuse (Tension + Relief)', 'punish_reroll_abuse'),
			almanac_toggle('Wondrous Joker music (by mthd2023)', 'wondrous'),
			almanac_toggle('Extraordinary+ Joker music (by mthd2023)', 'extraordinary'),
			-- Omega Wheel count slider (Shift=+/-50, Ctrl=+/-5, default +/-25 handled in prev functions if reused)
			create_slider({
				label = 'Omega Wheel Count',
				w = 6,
				h = 0.5,
				text_scale = 0.32,
				label_scale = 0.35,
				ref_table =
					CFG,
				ref_value = 'omega_wheel_count',
				min = 1,
				max = 500,
				callback = 'omega_wheel_slider_cb',
				decimal_places = 0
			}),
		}
	}
end

-- Validation for text input apply
if not G.FUNCS.apply_omega_wheel_input then
	G.FUNCS.apply_omega_wheel_input = function(e)
		local val = tonumber(CFG.omega_wheel_count)
		if not val then val = 200 end
		val = math.floor(math.max(1, math.min(500, val)))
		CFG.omega_wheel_count = val
		CFG.omega_wheel_string = 'Omega Wheel Count: ' .. tostring(val)
		if jl and jl.a then jl.a('Set to ' .. val, G.SETTINGS.GAMESPEED, 0.6, G.C.GREEN) end
	end
end

-- Slider callback (called after create_slider updates value)
if not G.FUNCS.omega_wheel_slider_cb then
	G.FUNCS.omega_wheel_slider_cb = function(e)
		local v = tonumber(CFG.omega_wheel_count) or 200
		v = math.max(1, math.min(500, math.floor(v + 0.5)))
		CFG.omega_wheel_count = v
		CFG.omega_wheel_string = 'Omega Wheel Count: ' .. v
	end
end


--LOCALISATION
function SMODS.current_mod.process_loc_text()
	G.localization.descriptions.Other["card_suitstats"] = {
		text = {
			"{s:0.8,C:inactive}({s:0.8,V:2}#4# {s:0.8,C:inactive}| {s:0.8,V:1}lvl.#1#{s:0.8,C:inactive}) {s:0.8,C:white,X:chips}+#2#{s:0.8} & {C:white,X:mult,s:0.8}+#3#{s:0.8}",
		}
	}
	G.localization.descriptions.Other["card_rankstats"] = {
		text = {
			"{s:0.8,C:inactive}({s:0.8,V:2}#4#s {s:0.8,C:inactive}| {s:0.8,V:1}lvl.#1#{s:0.8,C:inactive}) {s:0.8,C:white,X:chips}+#2#{s:0.8} & {C:white,X:mult,s:0.8}+#3#{s:0.8}",
		}
	}
	G.localization.misc.dictionary["b_suits"] = "Suits"
	G.localization.misc.dictionary["b_ranks"] = "Ranks"

	-- Cryptid POINTER:// compatibility - override description to mention OMEGA consumables
	-- Update both localization and card center if they exist

	-- Initialize Cryptid Encoded deck (must run after all mods load)
	if jl and jl.setup_encoded_deck then
		jl.setup_encoded_deck()
	end

	-- Note: Pointer blacklist/aliases are set up at module level (end of file)
	-- not here, because they need to run earlier in the load sequence
end

-- ========================================
-- CRYPTID COMPATIBILITY - MODULE LEVEL INIT
-- These must run at module load time, not inside functions
-- ========================================

-- Setup Cryptid pointer compatibility immediately when mod loads
if Cryptid and jl then
	print('[JEN DEBUG] Running module-level Cryptid pointer setup')

	-- Update POINTER:// card description if it exists
	if G and G.P_CENTERS and G.P_CENTERS.c_cry_pointer then
		G.P_CENTERS.c_cry_pointer.config.extra = "(Exotic Jokers and OMEGA consumables excluded)"
		print('[JEN DEBUG] Updated POINTER:// card center description')
	end

	-- Check if pointer functions exist
	if Cryptid.pointerblistifytype and Cryptid.pointeraliasify then
		print('[JEN DEBUG] Cryptid pointer functions found, setting up blacklist and aliases')

		-- Setup blacklist and aliases immediately
		if jl.setup_pointer_blacklist then
			jl.setup_pointer_blacklist()
		end

		if jl.setup_pointer_aliases then
			jl.setup_pointer_aliases()
		end
	else
		print('[JEN DEBUG] Cryptid pointer functions not available yet')
	end
else
	print('[JEN DEBUG] Cryptid or JenLib not available for module-level init')
end

-- On game load, check if P03 is in deck and update exotic blacklist accordingly
-- Hook into the game's start_run function to check for P03 on save load
local jen_original_start_run = Game.start_run
function Game:start_run(args)
	local result = jen_original_start_run(self, args)

	print('[JEN DEBUG] start_run called - checking for P03')

	-- Use a deferred event to check after everything is loaded
	G.E_MANAGER:add_event(Event({
		func = function()
			if Cryptid and Cryptid.pointerblistifytype then
				local has_p03 = false
				if G and G.jokers and G.jokers.cards then
					print('[JEN DEBUG] Checking ' .. #G.jokers.cards .. ' jokers for P03 on load')
					for _, card in ipairs(G.jokers.cards) do
						if card and card.config and card.config.center and card.config.center.key == 'j_jen_p03' then
							has_p03 = true
							print('[JEN DEBUG] Found P03 in deck on load!')
							break
						end
					end
				end

				if has_p03 then
					Cryptid.pointerblistifytype("rarity", "cry_exotic", true)
					print('[JEN DEBUG] Save load: P03 found - enabled Exotic creation')
				else
					Cryptid.pointerblistifytype("rarity", "cry_exotic", false)
					print('[JEN DEBUG] Save load: No P03 - disabled Exotic creation')
				end
			end
			return true
		end
	}))
	return result
end
