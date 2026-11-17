local B = require("balance")
local MOD = "__WePlayThumper__"
local NAME = "wp-thumper-equipment"

-- Only list prerequisites that exist, so overhaul mods that rename techs don't break loading.
local function existing(techs)
  local out = {}
  for _, t in pairs(techs) do
    if data.raw.technology[t] then out[#out + 1] = t end
  end
  return out
end

data:extend({
  -- Item
  {
    type = "item",
    name = NAME,
    icon = MOD .. "/graphics/icons/thumper-equipment.png",
    icon_size = 64,
    place_as_equipment_result = NAME,
    subgroup = "military-equipment",
    order = "b[active-defense]-z[wp-thumper]",
    stack_size = 20,
  },

  -- Equipment: a battery that only charges. The script spends its energy on each thump.
  {
    type = "battery-equipment",
    name = NAME,
    sprite = {
      filename = MOD .. "/graphics/equipment/thumper-equipment.png",
      width = 128,
      height = 128,
      priority = "medium",
      scale = 0.5,
    },
    shape = {width = 2, height = 2, type = "full"},
    energy_source = {
      type = "electric",
      buffer_capacity = B.BUFFER,
      input_flow_limit = B.INPUT_FLOW,
      output_flow_limit = "0W",
      usage_priority = "tertiary",
    },
    categories = {"armor"},
  },

  -- Recipe: engines for the piston
  {
    type = "recipe",
    name = NAME,
    enabled = false,
    energy_required = 10,
    ingredients = {
      {type = "item", name = "engine-unit", amount = 4},
      {type = "item", name = "advanced-circuit", amount = 5},
      {type = "item", name = "steel-plate", amount = 10},
    },
    results = {{type = "item", name = NAME, amount = 1}},
  },

  -- Technology
  {
    type = "technology",
    name = NAME,
    icon = MOD .. "/graphics/technology/thumper-equipment.png",
    icon_size = 256,
    effects = {{type = "unlock-recipe", recipe = NAME}},
    prerequisites = existing({"modular-armor", "engine", "advanced-circuit", "military-2"}),
    unit = {
      count = 200,
      ingredients = {
        {"automation-science-pack", 1},
        {"logistic-science-pack", 1},
        {"military-science-pack", 1},
      },
      time = 30,
    },
    order = "g-h-z",
  },

  -- Sounds
  {
    type = "sound",
    name = "wp-thumper-thump",
    filename = MOD .. "/sounds/thump.ogg",
    volume = 0.7,
    audible_distance_modifier = 0.8,
  },
  {
    type = "sound",
    name = "wp-thumper-shockwave",
    variations = {
      {filename = MOD .. "/sounds/shockwave-1.ogg", volume = 0.6},
      {filename = MOD .. "/sounds/shockwave-2.ogg", volume = 0.6},
      {filename = MOD .. "/sounds/shockwave-3.ogg", volume = 0.6},
    },
    audible_distance_modifier = 0.8,
  },
})

-- Bricks: one animation per baked direction (0 = travelling north, clockwise),
-- 4 frames of 192 px at 64 px per tile (drawn at scale 0.5 x size by the script).
local bricks = {}
for dir = 0, B.BRICK_DIRECTIONS - 1 do
  bricks[#bricks + 1] = {
    type = "animation",
    name = "wp-thumper-brick-" .. dir,
    filename = MOD .. "/graphics/entity/thumper-brick-" .. dir .. ".png",
    width = 192,
    height = 192,
    frame_count = B.BRICK_FRAMES,
    line_length = B.BRICK_FRAMES,
    priority = "medium",
    flags = {"no-crop"},
  }
end
data:extend(bricks)

-- Dust puff: 10 frames of 128 px.
data:extend({{
  type = "animation",
  name = "wp-thumper-dust",
  filename = MOD .. "/graphics/entity/thumper-dust.png",
  width = 128,
  height = 128,
  frame_count = B.DUST_FRAMES,
  line_length = B.DUST_FRAMES,
  priority = "medium",
  flags = {"no-crop"},
}})

-- Lakebed: the cracked disc, cut into ring sectors packed into atlases.
local sectors = {}
for i, s in ipairs(require("lakebed_sectors")) do
  sectors[#sectors + 1] = {
    type = "sprite",
    name = "wp-thumper-lakebed-" .. i,
    filename = MOD .. "/graphics/entity/thumper-lakebed-" .. s.atlas .. ".png",
    x = s.x,
    y = s.y,
    width = s.w,
    height = s.h,
    priority = "medium",
    flags = {"no-crop"},
  }
end
data:extend(sectors)

-- Craters: 13 x 13 tiles at 64 px per tile (drawn at scale 0.5 by the script).
local craters = {}
for v = 1, B.CRATER_VARIANTS do
  craters[#craters + 1] = {
    type = "sprite",
    name = "wp-thumper-crater-" .. v,
    filename = MOD .. "/graphics/entity/thumper-crater-" .. v .. ".png",
    width = 832,
    height = 832,
    priority = "medium",
    flags = {"no-crop"},
  }
end
data:extend(craters)

-- Stagger: slows shoved enemies for a moment. Ten lengths, since a sticker's
-- duration is set per prototype; the script picks the closest.
local stickers = {}
for i = 1, 10 do
  stickers[#stickers + 1] = {
    type = "sticker",
    name = "wp-thumper-stagger-" .. i,
    flags = {"not-on-map"},
    hidden = true,
    duration_in_ticks = math.max(1, math.floor(B.STAGGER * i / 10)),
    target_movement_modifier = B.STAGGER_SPEED,
  }
end
data:extend(stickers)

-- Rough ground: one sticker per 5% of slowdown, up to 95%; the script keeps refreshing
-- the right one while an enemy is on cracked ground.
local rough = {}
for pct = B.ROUGH_STEP, 95, B.ROUGH_STEP do
  rough[#rough + 1] = {
    type = "sticker",
    name = "wp-thumper-rough-" .. pct,
    flags = {"not-on-map"},
    hidden = true,
    duration_in_ticks = B.ROUGH_STICKER_TICKS,
    target_movement_modifier = 1 - pct / 100,
  }
end
data:extend(rough)
