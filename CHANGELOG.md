# Changelog

All notable changes to Jen Almanac's Modpack will be documented in this file.

## [Unreleased]

### Fixed

#### Steamodded Core (`smods/src/overrides.lua`)
- **HUD_blind_debuff assertion crash on save load**: Added early guard check to `HUD_blind_debuff` callback to safely skip execution when `G.HUD_blind` is not yet initialized. This prevents crashes when loading saved runs during UI initialization phase.
- **Removed overly strict HUD_blind equality assertion**: The assertion that checked `G.HUD_blind == e.UIBox` could fail during legitimate UI states. The early guard at the function entry is now sufficient to prevent initialization issues.

#### Jen Almanac (`Jen/Jen.lua`)
- **Ban system crash on nil center objects**: Wrapped `Jen:delete_hardbans()` with proper error handling using `pcall` to safely handle cases where `SMODS.Center:get_obj()` returns nil or an object without a `delete` method.
- **Type checking for center deletion**: Added type validation to verify that center objects exist and have a `delete` method before invoking it, preventing nil method call errors.
- **Graceful degradation on deletion failure**: Failed card deletions now log a warning instead of crashing, allowing the banning system to continue functioning even if individual card deletions fail.

### Technical Details

**Root Causes Addressed:**
1. During save load initialization, the HUD_blind UI callback could be triggered before `G.HUD_blind` was fully initialized in the global state, causing assertion failures.
2. The ban system attempted to delete center objects (cards, consumables, blinds) that were in Jen's ban configuration but either didn't exist or weren't properly registered in Steamodded's registry.

**Impact:**
- Saves now load without crashing
- Banned cards are correctly removed from the game pool
- Game remains stable even if edge cases occur during card deletion

