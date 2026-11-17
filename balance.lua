-- Balance numbers and tuning, shared by data.lua and control.lua.
-- First-pass values from the design notes: tune in game.

local B = {}

-- Equipment
B.BUFFER = "1MJ"              -- energy buffer
B.INPUT_FLOW = "300kW"        -- how fast it charges from the grid
B.THUMP_COST = 120000         -- J per thump (about 100 kW while thumping every 1.2 s)

-- Firing
B.TRIGGER_RADIUS = 10         -- fires when an enemy unit is this close (tiles)
B.REACH = 10                  -- the wave rolls out this far (tiles)
B.COOLDOWN = 72               -- ticks between thumps (1.2 s)
B.SCAN_TICKS = 6              -- how often ready wearers look for enemies

-- Wave
B.WAVE_SPEED = 1.0            -- tiles per tick (10 tiles in 10 ticks)
B.BOOM_DELAY = 6              -- ticks from the piston's clang to the boom; the crater, the wave
                              -- and the rumble start here (must match sounds/thump.ogg: 0.1 s)

-- Knockback (scaled by tier weight x fatigue x the knockback setting)
B.SHOVE = 8.0                 -- tiles, fresh enemy
B.SHOVE_TICKS = 6             -- the shove is spread over this many ticks, fast then easing off
B.STAGGER = 60                -- ticks of slowdown, fresh enemy
B.STAGGER_SPEED = 0.15        -- movement while staggered (fraction of normal)
B.USE_FATIGUE = true          -- each repeat thump on the same enemy does less
B.FATIGUE = 0.6               -- each repeat thump on the same enemy does this much of the last
B.FATIGUE_RESET = 600         -- ticks without a thump before an enemy is fresh again (10 s)
B.BLOCK_RADIUS = 0.35         -- shoves stop at walls, buildings, trees, rocks, cliffs and water

-- Tier weight from max health: small biter (15) x1, medium (75) x0.8,
-- big (375) x0.6, behemoth (3000) x0.35. Off for now: every enemy gets the same shove.
B.USE_TIER_WEIGHT = false
B.WEIGHT_BASE_HEALTH = 15
B.WEIGHT_PER_DECADE = 0.28
B.WEIGHT_MIN = 0.25

-- Damage (scaled by the damage setting); resistances apply
B.DAMAGE = 8
B.DAMAGE_TYPE = "physical"

-- Leading edge, built by tools/thumper_wave3.py and packed by tools/thumper_pack.py.
-- Bricks: rounded dirt ridges that pop up for a few ticks, tiny near the wearer and
-- growing toward the edge. 16 baked directions (light fixed at the top-left).
B.BRICK_FRAMES = 4            -- one tick each
B.BRICK_DIRECTIONS = 16
B.BRICK_NEAR = 0.55           -- size at the centre...
B.BRICK_FAR = 1.3             -- ...and at the edge
B.BRICK_ROW_STEP = 0.8        -- tiles between rows (x size)
B.BRICK_SPACING = 1.1         -- tiles between bricks along a row (x size)
B.BRICK_LAYERS = {"lower-object-above-shadow", "lower-object", "object"}  -- first that works

-- Dust: soft puffs riding just behind the front, growing with distance.
B.DUST_FRAMES = 10
B.DUST_TICKS_PER_FRAME = 2
B.DUST_NEAR = 1.0
B.DUST_FAR = 2.8
B.DUST_ROW_STEP = 1.0         -- x size
B.DUST_SPACING = 1.1          -- x size
B.DUST_LAYERS = {"smoke", "air-object", "object"}

-- Scar: the crater where the piston hit, plus the cracked lakebed around it. The
-- lakebed appears ring by ring as the front passes, then both stay for the
-- "scar duration" setting and fade out together.
B.CRATER_VARIANTS = 3
B.CRATER_SPACING = 2.0        -- thumping within this of a scar refreshes it instead of adding a crater
B.LAKEBED_SPACING = 6.0       -- ...and no new cracks within this of existing ones (they'd pile up)
B.LAKEBED_LAG = 1             -- ticks after the front reaches a ring
B.SCAR_FADE = 30 * 60         -- fades out over this after the scar duration
B.SCAR_MAX = 60               -- oldest go first past this
B.LAKEBED_MAX = 20            -- most cracked discs kept at once (about 160 pieces each)
-- Rough ground: enemy units on a scar's cracked ground are slowed for as long as the
-- cracks last. The "cracked ground slowdown strength" setting (0-100%) scales B.ROUGH_MAX.
B.ROUGH_RADIUS = 10.5         -- tiles, the cracked disc
B.ROUGH_TICKS = 10            -- how often units on the cracks are found and slowed
B.ROUGH_STICKER_TICKS = 20    -- each slow lasts this long, so it drops off soon after leaving
B.ROUGH_MAX = 0.5             -- slowdown at strength 1: 50% slower
B.ROUGH_STEP = 1              -- slowdown is rounded to 1% steps (one sticker each)
B.ROUGH_FATIGUE = 0.9         -- each fatigue level keeps 90% of the slowdown (10% less), so
                              -- thumped-often enemies get faster but never back to full speed
B.SCAR_LAYERS = {"ground-patch-higher2", "ground-patch-higher", "ground-patch", "decals"}

return B
