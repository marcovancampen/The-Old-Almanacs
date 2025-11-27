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
