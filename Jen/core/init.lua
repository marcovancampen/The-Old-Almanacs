-- Jen Mod Core Initialization
-- Contains global setup, safety patches, and Jen table configuration

-- Ensure global Jen table exists even if TOML init patch is absent
Jen = Jen or {}

maxArrow = 2.5e4
local maxfloat = 1.7976931348623157e308

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
}

-- COMMON STRINGS
mayoverflow = '{C:inactive,s:0.65}(Does not require room, but may overflow)'
redeemprev = '{s:0.75}Also redeems {C:attention,s:0.75}previous tier for free{s:0.75} if not yet acquired'

-- Note: config.lua, fusion.lua, safety.lua, and bans.lua are loaded
-- by the main Jen.lua entry point using safe_load()

-- Initialize Incantation addons if not present
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

-- Register arrow scoring calculations for operator levels 3+
function register_arrow_scoring_calculations()
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

-- Stackable/Usable configurations
-- Safety checks for Incantation mod functions
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
