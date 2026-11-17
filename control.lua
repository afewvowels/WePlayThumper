-- WePlay: Thumper — Shockwave Equipment
--
-- A piston backpack that slams the ground when enemy units come close. The piston
-- clangs, and a tenth of a second later the boom punches a crater at the wearer's
-- feet and a shockwave rolls outward: a front of rounded dirt bricks and dust that
-- grow as they go, leaving the ground cracked like a dry lakebed. The crater and the
-- cracks stay for a while, then fade.
-- Enemies are hit when the front reaches them: a little damage, a shove outward and a
-- short stagger, then they're sent straight back at the wearer. Thumper buys time;
-- it never stops melee.

local B = require("balance")

local EQUIPMENT = "wp-thumper-equipment"
local HIT_TYPES = {"unit", "spider-unit", "turret", "unit-spawner"}
local TRIGGER_TYPES = {"unit", "spider-unit"}
local BRICK_LIFE = B.BRICK_FRAMES
local DUST_LIFE = B.DUST_FRAMES * B.DUST_TICKS_PER_FRAME
local DUST_SPEED = 1 / B.DUST_TICKS_PER_FRAME
local SECTORS = require("lakebed_sectors")
for i, sec in ipairs(SECTORS) do
  sec.sprite = "wp-thumper-lakebed-" .. i
end
table.sort(SECTORS, function(a, b) return a.ring < b.ring end)

---------------------------------------------------------------------------
-- Leading-edge layout: the same pattern every thump, built once from a fixed seed
-- (plain Lua maths, so it's identical for everyone in multiplayer).
-- Bricks grow from B.BRICK_NEAR to B.BRICK_FAR with distance; dust puffs likewise.
---------------------------------------------------------------------------

local FRONT = {}   -- {kind = "brick"|"dust", dx, dy, dir, scale, delay}, by delay
do
  local seed = 20261117
  local function rnd()
    seed = (seed * 16807) % 2147483647
    return seed / 2147483647
  end
  local function normal(sd)
    local u1, u2 = math.max(rnd(), 1e-9), rnd()
    return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2) * sd
  end
  local function lerp(a, b, t) return a + (b - a) * math.min(1, math.max(0, t)) end

  local r = 0.6
  while r <= B.REACH + 1e-6 do
    local sc = lerp(B.BRICK_NEAR, B.BRICK_FAR, r / B.REACH)
    local n = math.max(5, math.floor(2 * math.pi * r / (B.BRICK_SPACING * sc) + 0.5))
    local off = rnd() * 2 * math.pi / n
    for i = 0, n - 1 do
      local ang = off + 2 * math.pi * i / n + normal(0.04)
      local rr = r + normal(0.12 * sc)
      local ori = (ang / (2 * math.pi)) % 1
      FRONT[#FRONT + 1] = {
        kind = "brick",
        dx = math.sin(ang) * rr, dy = -math.cos(ang) * rr,
        dir = math.floor(ori * B.BRICK_DIRECTIONS + 0.5) % B.BRICK_DIRECTIONS,
        scale = sc,
        delay = math.max(0, math.floor(rr / B.WAVE_SPEED + 0.5)),
      }
    end
    r = r + B.BRICK_ROW_STEP * sc
  end

  r = 1.0
  while r <= B.REACH + 1e-6 do
    local sc = lerp(B.DUST_NEAR, B.DUST_FAR, r / B.REACH)
    local n = math.max(4, math.floor(2 * math.pi * r / (B.DUST_SPACING * sc) + 0.5))
    local off = rnd() * 2 * math.pi / n
    for i = 0, n - 1 do
      local ang = off + 2 * math.pi * i / n + normal(0.1)
      local rr = r + normal(0.3)
      FRONT[#FRONT + 1] = {
        kind = "dust",
        dx = math.sin(ang) * rr, dy = -math.cos(ang) * rr,
        scale = sc,
        delay = math.max(0, math.floor(rr / B.WAVE_SPEED + 0.5) + 1),
      }
    end
    r = r + B.DUST_ROW_STEP * sc
  end
  table.sort(FRONT, function(a, b) return a.delay < b.delay end)
end

-- The shove is spread over B.SHOVE_TICKS: fast at first, easing off.
local SHOVE_SHARE = {}
do
  local n, sum = B.SHOVE_TICKS, 0
  for i = 1, n do sum = sum + (n - i + 1) end
  for i = 1, n do SHOVE_SHARE[i] = (n - i + 1) / sum end
end

---------------------------------------------------------------------------
-- Storage
---------------------------------------------------------------------------

local function init_storage()
  storage.ready = storage.ready or {}       -- player index -> tick it can thump again
  storage.waves = storage.waves or {}       -- waves in flight
  storage.shoves = storage.shoves or {}     -- unit number -> shove in progress
  storage.fatigue = storage.fatigue or {}   -- unit number -> {n = thumps taken, last = tick}
  storage.scars = storage.scars or {}       -- crater + lakebed, oldest first (see place_scar)
  storage.latest = storage.latest or {}     -- player index -> their newest cracks (the only ones that slow)
  if storage.craters then                   -- 0.1.x craters: let them go
    for _, c in pairs(storage.craters) do
      if c.obj and c.obj.valid then c.obj.destroy() end
    end
    storage.craters = nil
  end
  storage.weights = storage.weights or {}   -- prototype name -> tier weight
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function dist(a, b)
  local dx, dy = a.x - b.x, a.y - b.y
  return math.sqrt(dx * dx + dy * dy)
end

local function setting_fraction(name)
  return settings.global[name].value / 100
end

local function enemy_forces(force)
  local out = {}
  for _, f in pairs(game.forces) do
    if force.is_enemy(f) then out[#out + 1] = f end
  end
  return out
end

-- The grid with the best Thumper for this player: highest quality, vehicle wins ties.
local function find_source(player)
  local best, best_level, best_vehicle
  local function consider(grid, is_vehicle)
    if not (grid and grid.valid) then return end
    local eq = grid.find(EQUIPMENT)
    if not eq then return end
    local level = eq.quality and eq.quality.level or 0
    if not best or level > best_level or (level == best_level and is_vehicle and not best_vehicle) then
      best, best_level, best_vehicle = eq, level, is_vehicle
    end
  end
  local character = player.character
  if character and character.valid then consider(character.grid, false) end
  local vehicle = player.vehicle
  if vehicle and vehicle.valid then consider(vehicle.grid, true) end
  if not best then return nil end
  local center = (vehicle and vehicle.valid) and vehicle or character
  if not (center and center.valid) then return nil end
  return best, center
end

-- Tier weight from max health: small biters fly, behemoths stumble.
local function weight(e)
  if not B.USE_TIER_WEIGHT then return 1 end
  local name = e.name
  local w = storage.weights[name]
  if w then return w end
  local p = e.prototype
  local ok, health = pcall(function() return p.get_max_health() end)
  if not ok or not health then
    ok, health = pcall(function() return p.max_health end)
    if not ok or not health then health = 100 end
  end
  local ratio = math.max(health, B.WEIGHT_BASE_HEALTH) / B.WEIGHT_BASE_HEALTH
  w = 1 - B.WEIGHT_PER_DECADE * math.log(ratio, 10)
  w = math.max(B.WEIGHT_MIN, math.min(1, w))
  storage.weights[name] = w
  return w
end

-- Shove fatigue: each thump on the same enemy does B.FATIGUE of the last,
-- until it goes B.FATIGUE_RESET ticks without one.
local function take_fatigue(un, tick)
  if not B.USE_FATIGUE then return 1 end
  local f = storage.fatigue[un]
  if not f or tick - f.last > B.FATIGUE_RESET then
    f = {n = 0}
    storage.fatigue[un] = f
  end
  local m = B.FATIGUE ^ f.n
  f.n = f.n + 1
  f.last = tick
  return m
end

local function water_at(surface, x, y)
  local tile = surface.get_tile(x, y)
  if not (tile and tile.valid) then return false end
  local ok, wet = pcall(tile.collides_with, "water_tile")
  return ok and wet
end

-- Would a shoved unit bump into something solid at p? (walls, buildings, trees,
-- rocks, cliffs, water). Other units don't block.
local function blocked(e, p)
  local surface = e.surface
  local tile = surface.get_tile(p.x, p.y)
  if tile and tile.valid then
    local ok, collides = pcall(tile.collides_with, "player")
    if ok and collides then return true end
  end
  for _, o in pairs(surface.find_entities_filtered({position = p, radius = B.BLOCK_RADIUS, collision_mask = "player"})) do
    if o ~= e and o.type ~= "unit" and o.type ~= "character" and o.type ~= "car" and o.type ~= "spider-vehicle" then
      return true
    end
  end
  return false
end

-- Is this character off the ground? Thumper only works standing on the ground.
--   Jetpack (and forks): asks the mod, and also checks for its swapped "-jetpack"
--   flying character.
--   Mech armor (or any armor that provides flight): there's no "is flying" flag in the
--   API, so it counts as flying when it's over something it can't walk on: water,
--   void, or a building, wall, tree or rock (that's when mech armor hovers).
local function airborne(center)
  if not (center and center.valid and center.type == "character") then return false end
  if string.sub(center.name, -8) == "-jetpack" then return true end
  for _, iface in pairs({"jetpack", "jetpack-rapid", "rapid-jetpack"}) do
    local funcs = remote.interfaces[iface]
    if funcs and funcs.is_jetpacking then
      local ok, flying = pcall(remote.call, iface, "is_jetpacking", {character = center})
      if ok and flying then return true end
    end
  end
  local ok, flight = pcall(function()
    local inv = center.get_inventory(defines.inventory.character_armor)
    local armor = inv and inv[1]
    return armor and armor.valid_for_read and armor.prototype.provides_flight
  end)
  if not (ok and flight) then return false end
  local surface, p = center.surface, center.position
  local tile = surface.get_tile(p.x, p.y)
  if tile and tile.valid then
    local ok2, collides = pcall(tile.collides_with, "player")
    if ok2 and collides then return true end
  end
  for _, o in pairs(surface.find_entities_filtered({position = p, radius = 0.4, collision_mask = "player"})) do
    if o ~= center and o.type ~= "character" and o.type ~= "unit" and o.type ~= "spider-unit" then
      return true
    end
  end
  return false
end

-- Send a shoved enemy straight back at the wearer, so it doesn't wander off to
-- rejoin its group or go back to whatever it was doing before it chased them.
local function attack_order(e, target)
  if not (e and e.valid and target and target.valid) then return end
  local c = e.commandable
  if c and c.valid then
    pcall(c.set_command, {type = defines.command.attack, target = target, distraction = defines.distraction.by_enemy})
  end
end

---------------------------------------------------------------------------
-- Per-player sound and graphics settings
---------------------------------------------------------------------------

local function player_wants(player, setting)
  local ok, value = pcall(function() return player.mod_settings[setting].value end)
  return not ok or value ~= false
end

-- Who sees the effects: {all = true}, {none = true}, or {list = {player indices}}.
local view_cache
local function viewers()
  if view_cache then return view_cache end
  local list, everyone = {}, true
  for _, player in pairs(game.connected_players) do
    if player_wants(player, "wp-thumper-graphics") then
      list[#list + 1] = player.index
    else
      everyone = false
    end
  end
  if everyone then view_cache = {all = true, list = list}
  elseif #list == 0 then view_cache = {none = true}
  else view_cache = {list = list} end
  return view_cache
end

local function apply_view(obj, refresh)
  if not (obj and obj.valid) then return obj end
  local v = viewers()
  if v.none then
    obj.visible = false
  elseif v.all and not refresh then
    return obj
  else
    obj.visible = true
    obj.players = v.list
  end
  return obj
end

local function play(surface, pos, path)
  local listeners, everyone = {}, true
  for _, player in pairs(game.connected_players) do
    if player_wants(player, "wp-thumper-sound") then
      listeners[#listeners + 1] = player
    else
      everyone = false
    end
  end
  if everyone then
    surface.play_sound({path = path, position = pos})
  else
    for _, player in pairs(listeners) do
      if player.surface == surface then player.play_sound({path = path, position = pos}) end
    end
  end
end

-- Draw with the first render layer that works, and remember it.
local layer_ok = {}
local function draw_layered(fn, args, layers, key)
  if layer_ok[key] then
    args.render_layer = layer_ok[key]
    return fn(args)
  end
  for _, layer in pairs(layers) do
    args.render_layer = layer
    local ok, obj = pcall(fn, args)
    if ok and obj then
      layer_ok[key] = layer
      return obj
    end
  end
end

---------------------------------------------------------------------------
-- Crater
---------------------------------------------------------------------------

local function scar_hold()
  return settings.global["wp-thumper-scar-seconds"].value * 60
end

local function set_level(obj, l)
  if obj and obj.valid then obj.color = {r = l, g = l, b = l, a = l} end
end

local function scar_objects(sc)
  local list = {}
  if sc.crater then list[#list + 1] = sc.crater end
  if sc.sectors then for _, o in pairs(sc.sectors) do list[#list + 1] = o end end
  return list
end

local function destroy_scar(sc)
  sc.dead = true
  for _, o in pairs(scar_objects(sc)) do if o.valid then o.destroy() end end
end

local function refresh_scar(sc, tick)
  sc.born = tick
  if sc.fading then
    for _, o in pairs(scar_objects(sc)) do set_level(o, 1) end
    sc.fading = nil
  end
end

-- A thump's scar: the crater where the piston hit, and (unless there are cracks
-- close by already) a cracked lakebed disc that the wave reveals ring by ring.
-- Returns the scar if it should get new cracks, so the wave can reveal them.
local function place_scar(surface, pos, tick, force, owner)
  local near_crater, near_lake
  local cs2, ls2 = B.CRATER_SPACING ^ 2, B.LAKEBED_SPACING ^ 2
  for _, sc in pairs(storage.scars) do
    if sc.surface == surface.index then
      local d2 = (sc.x - pos.x) ^ 2 + (sc.y - pos.y) ^ 2
      if d2 < cs2 and sc.crater and sc.crater.valid then near_crater = near_crater or sc end
      if d2 < ls2 and sc.sectors then near_lake = near_lake or sc end
    end
  end
  if near_crater then refresh_scar(near_crater, tick) end
  -- thumping on cracks you've already made keeps them as your rough ground
  if near_lake and owner then storage.latest[owner] = near_lake end
  if near_lake and near_lake ~= near_crater then refresh_scar(near_lake, tick) end
  if near_crater and near_lake then return nil end
  if water_at(surface, pos.x, pos.y) then return nil end

  local sc = {surface = surface.index, x = pos.x, y = pos.y, born = tick, force = force}
  if not near_crater then
    sc.crater = draw_layered(rendering.draw_sprite, {
      sprite = "wp-thumper-crater-" .. math.random(B.CRATER_VARIANTS),
      target = {x = pos.x, y = pos.y},
      surface = surface,
      x_scale = 0.5,
      y_scale = 0.5,
    }, B.SCAR_LAYERS, "scar")
    apply_view(sc.crater)
  end
  local reveal = nil
  if not near_lake then
    sc.sectors = {}
    sc.rot = math.random() * 2 * math.pi   -- every disc turned a different way
    reveal = sc
    if owner then storage.latest[owner] = sc end   -- your newest cracks are the rough ground
  end
  if not sc.crater and not reveal then return nil end
  local list = storage.scars
  list[#list + 1] = sc
  -- keep the numbers down: oldest cracks first, then oldest scars
  local lakes = 0
  for i = #list, 1, -1 do
    if list[i].sectors then
      lakes = lakes + 1
      if lakes > B.LAKEBED_MAX then
        for _, o in pairs(list[i].sectors) do if o.valid then o.destroy() end end
        list[i].sectors = nil
      end
    end
  end
  while #list > B.SCAR_MAX do destroy_scar(table.remove(list, 1)) end
  return reveal
end

-- Draw one ring sector of a scar's lakebed, turned by the scar's rotation.
local function reveal_sector(sc, sec, surface)
  if not sc.sectors then return end
  local c, s_ = math.cos(sc.rot), math.sin(sc.rot)
  local x = sc.x + sec.dx * c - sec.dy * s_
  local y = sc.y + sec.dx * s_ + sec.dy * c
  local obj = draw_layered(rendering.draw_sprite, {
    sprite = sec.sprite,
    target = {x = x, y = y},
    surface = surface,
    orientation = sc.rot / (2 * math.pi),
    x_scale = 0.5,
    y_scale = 0.5,
  }, B.SCAR_LAYERS, "scar")
  if obj then
    apply_view(obj)
    if sc.fading then set_level(obj, sc.level or 1) end
    sc.sectors[#sc.sectors + 1] = obj
  end
end

local function update_scars(tick)
  local hold = scar_hold()
  local list = storage.scars
  local i = 1
  while i <= #list do
    local sc = list[i]
    local age = tick - sc.born
    if age >= hold + B.SCAR_FADE then
      destroy_scar(sc)
      table.remove(list, i)
    else
      if age > hold then
        local l = 1 - (age - hold) / B.SCAR_FADE
        sc.level, sc.fading = l, true
        for _, o in pairs(scar_objects(sc)) do set_level(o, l) end
      end
      i = i + 1
    end
  end
end

-- Rough ground: enemy units on a scar's cracks are slowed while the cracks last.
-- The slow is a short sticker, refreshed every B.ROUGH_TICKS while they stay on it.
-- Hard mode: players on cracked ground are slowed too, unless their armor has
-- movement-bonus equipment (an exoskeleton, or a modded one).
local function has_exoskeleton(character)
  local grid = character.grid
  if not (grid and grid.valid) then return false end
  for _, eq in pairs(grid.equipment) do
    if eq.type == "movement-bonus-equipment" then return true end
  end
  return false
end

-- Fatigue level (thumps taken recently), without counting a new one.
local function fatigue_level(un, tick)
  if not B.USE_FATIGUE then return 0 end
  local f = storage.fatigue[un]
  if not f or tick - f.last > B.FATIGUE_RESET then return 0 end
  return f.n
end

local function rough_sticker(pct)
  pct = math.floor(pct / B.ROUGH_STEP + 0.5) * B.ROUGH_STEP
  if pct <= 0 then return nil end
  return "wp-thumper-rough-" .. math.min(pct, 95)
end

local function slow(e, sticker, surface)
  local ok, stickers = pcall(function() return e.stickers end)
  if ok and stickers then
    for _, s in pairs(stickers) do
      if s.valid and s.name == sticker then
        pcall(function() s.time_to_live = B.ROUGH_STICKER_TICKS end)
        return
      end
    end
  end
  pcall(surface.create_entity, {name = sticker, position = e.position, target = e})
end

local function update_rough_ground()
  local base = settings.global["wp-thumper-rough-strength-pct"].value / 100 * B.ROUGH_MAX * 100  -- % slower
  if base <= 0 then return end
  local tick = game.tick
  local sticker = rough_sticker(base)
  local hard = settings.global["wp-thumper-rough-hard-mode"].value
  local forces_of = {}
  local done = {}
  -- only each player's newest cracks are rough ground; older patches are just scenery
  for owner, sc in pairs(storage.latest) do
    local force = sc.force
    if sc.dead or not sc.sectors then
      storage.latest[owner] = nil
    elseif force and force.valid then
      local surface = game.surfaces[sc.surface]
      local enemies = forces_of[force.index]
      if not enemies then enemies = enemy_forces(force); forces_of[force.index] = enemies end
      if surface then
        local center = {x = sc.x, y = sc.y}
        if #enemies > 0 then
          for _, e in pairs(surface.find_entities_filtered({position = center, radius = B.ROUGH_RADIUS, force = enemies, type = "unit"})) do
            local un = e.unit_number
            if not done[un] then
              done[un] = true
              -- each fatigue level keeps B.ROUGH_FATIGUE of the slowdown
              local s = rough_sticker(base * B.ROUGH_FATIGUE ^ fatigue_level(un, tick))
              if s then slow(e, s, surface) end
            end
          end
        end
        if hard then
          for _, ch in pairs(surface.find_entities_filtered({position = center, radius = B.ROUGH_RADIUS, type = "character"})) do
            local key = "c" .. ch.unit_number
            if not done[key] then
              done[key] = true
              if sticker and not has_exoskeleton(ch) and not airborne(ch) then slow(ch, sticker, surface) end
            end
          end
        end
      end
    end
  end
end

---------------------------------------------------------------------------
-- Wave
---------------------------------------------------------------------------

local function draw_front(w, f, tick, v)
  local x, y = w.x + f.dx, w.y + f.dy
  if water_at(w.surface, x, y) then return end
  local obj
  if f.kind == "brick" then
    obj = draw_layered(rendering.draw_animation, {
      animation = "wp-thumper-brick-" .. f.dir,
      target = {x = x, y = y},
      surface = w.surface,
      x_scale = 0.5 * f.scale,
      y_scale = 0.5 * f.scale,
      time_to_live = BRICK_LIFE,
      animation_speed = 1,
      animation_offset = (-tick) % B.BRICK_FRAMES,   -- start on frame 0
    }, B.BRICK_LAYERS, "brick")
  else
    obj = draw_layered(rendering.draw_animation, {
      animation = "wp-thumper-dust",
      target = {x = x, y = y},
      surface = w.surface,
      x_scale = 0.5 * f.scale,
      y_scale = 0.5 * f.scale,
      time_to_live = DUST_LIFE,
      animation_speed = DUST_SPEED,
      animation_offset = (-(tick * DUST_SPEED)) % B.DUST_FRAMES,
    }, B.DUST_LAYERS, "dust")
  end
  if obj and v.list and not v.all then
    obj.players = v.list
  end
end

local function hit(w, e, tick)
  if not (e and e.valid) then return end
  local p = e.position
  local dx, dy = p.x - w.x, p.y - w.y
  local d = math.sqrt(dx * dx + dy * dy)
  if d > B.REACH + 2 then return end

  local damage = B.DAMAGE * setting_fraction("wp-thumper-damage")
  if damage > 0 then
    local cause = (w.cause and w.cause.valid) and w.cause or nil
    pcall(e.damage, damage, w.force, B.DAMAGE_TYPE, cause, cause)
    if not e.valid then return end
  end
  if e.type ~= "unit" then return end  -- worms, nests and pentapods only take damage

  local knock = setting_fraction("wp-thumper-knockback")
  if knock <= 0 then return end
  local m = weight(e) * take_fatigue(e.unit_number, tick)
  local shove = B.SHOVE * m * knock
  if shove > 0.05 then
    if d < 0.05 then
      local a = math.random() * 2 * math.pi
      dx, dy, d = math.cos(a), math.sin(a), 1
    end
    storage.shoves[e.unit_number] = {entity = e, ux = dx / d, uy = dy / d, total = shove, step = 0, target = w.cause}
  else
    attack_order(e, w.cause)
  end
  local level = math.max(1, math.min(10, math.floor(m * math.min(knock, 1) * 10 + 0.5)))
  pcall(e.surface.create_entity, {name = "wp-thumper-stagger-" .. level, position = p, target = e})
end

local function update_waves(tick)
  local v = viewers()
  local i = 1
  while i <= #storage.waves do
    local w = storage.waves[i]
    if not (w.surface and w.surface.valid) then
      table.remove(storage.waves, i)
    else
      local age = tick - w.start
      if age == 0 and not w.boomed then
        w.boomed = true
        local pos = {x = w.x, y = w.y}
        play(w.surface, pos, "wp-thumper-shockwave")
        w.scar = place_scar(w.surface, pos, tick, w.force, w.owner)
        w.next_sector = 1
      end
      if age >= 0 then
        while w.next_front <= #FRONT and FRONT[w.next_front].delay <= age do
          if not v.none then draw_front(w, FRONT[w.next_front], tick, v) end
          w.next_front = w.next_front + 1
        end
        if w.scar then
          while w.next_sector <= #SECTORS and SECTORS[w.next_sector].ring / B.WAVE_SPEED + B.LAKEBED_LAG <= age do
            reveal_sector(w.scar, SECTORS[w.next_sector], w.surface)
            w.next_sector = w.next_sector + 1
          end
          if w.next_sector > #SECTORS then w.scar = nil end
        end
      end
      while w.next_hit <= #w.hits and w.hits[w.next_hit].at <= tick do
        hit(w, w.hits[w.next_hit].entity, tick)
        w.next_hit = w.next_hit + 1
      end
      if w.boomed and w.next_front > #FRONT and not w.scar and w.next_hit > #w.hits then
        table.remove(storage.waves, i)
      else
        i = i + 1
      end
    end
  end
end

local function update_shoves()
  for un, s in pairs(storage.shoves) do
    local e = s.entity
    if not (e and e.valid) then
      storage.shoves[un] = nil
    else
      s.step = s.step + 1
      local len = s.total * SHOVE_SHARE[s.step]
      local p = e.position
      local np = {x = p.x + s.ux * len, y = p.y + s.uy * len}
      if blocked(e, np) then
        storage.shoves[un] = nil
        attack_order(e, s.target)
      else
        e.teleport(np)
        if s.step >= B.SHOVE_TICKS then
          storage.shoves[un] = nil
          attack_order(e, s.target)
        end
      end
    end
  end
end

local function fire(player, eq, center, forces)
  local tick = game.tick
  eq.energy = eq.energy - B.THUMP_COST
  storage.ready[player.index] = tick + B.COOLDOWN
  local surface, pos = center.surface, center.position
  -- The piston's clang plays now; the boom, crater, wave and rumble follow B.BOOM_DELAY later.
  local start = tick + B.BOOM_DELAY
  local hits = {}
  for _, e in pairs(surface.find_entities_filtered({position = pos, radius = B.REACH + 0.5, force = forces, type = HIT_TYPES})) do
    hits[#hits + 1] = {entity = e, at = start + math.floor(dist(e.position, pos) / B.WAVE_SPEED)}
  end
  table.sort(hits, function(a, b) return a.at < b.at end)
  storage.waves[#storage.waves + 1] = {
    surface = surface, x = pos.x, y = pos.y, start = start,
    next_front = 1, hits = hits, next_hit = 1,
    force = center.force, cause = center, owner = player.index,
  }
  play(surface, pos, "wp-thumper-thump")
end

local function scan(tick)
  for _, player in pairs(game.connected_players) do
    local ready = storage.ready[player.index]
    if not ready or ready <= tick then
      local eq, center = find_source(player)
      if eq and eq.energy >= B.THUMP_COST and not airborne(center) then
        local forces = enemy_forces(center.force)
        if #forces > 0 and center.surface.count_entities_filtered({
          position = center.position, radius = B.TRIGGER_RADIUS,
          force = forces, type = TRIGGER_TYPES, limit = 1,
        }) > 0 then
          fire(player, eq, center, forces)
        end
      end
    end
  end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

script.on_init(init_storage)
script.on_load(function() view_cache = nil end)
script.on_configuration_changed(function()
  view_cache = nil
  init_storage()
  storage.weights = {}
  -- waves from an older version used a different layout; let them finish quietly
  for _, w in pairs(storage.waves) do
    w.next_front = w.next_front or (#FRONT + 1)
    w.boomed = true
  end
end)

script.on_event(defines.events.on_tick, function(event)
  local tick = event.tick
  if tick % B.SCAN_TICKS == 0 then scan(tick) end
  if #storage.waves > 0 then update_waves(tick) end
  if next(storage.shoves) then update_shoves() end
  if tick % 15 == 0 and #storage.scars > 0 then update_scars(tick) end
  if tick % B.ROUGH_TICKS == 0 and next(storage.latest) then update_rough_ground() end
  if tick % 3600 == 0 then
    for un, f in pairs(storage.fatigue) do
      if tick - f.last > B.FATIGUE_RESET then storage.fatigue[un] = nil end
    end
  end
end)

script.on_event(defines.events.on_player_placed_equipment, function(event)
  local eq, grid = event.equipment, event.grid
  if not (eq and eq.valid) then return end
  local player = game.get_player(event.player_index)

  -- One per grid: hand a second one straight back.
  if eq.name == EQUIPMENT and grid.count(EQUIPMENT) > 1 then
    local quality = eq.quality and eq.quality.name or "normal"
    grid.take({equipment = eq})
    if player then
      local stack = {name = EQUIPMENT, count = 1, quality = quality}
      if player.insert(stack) == 0 and player.character then
        player.surface.spill_item_stack({position = player.position, stack = stack})
      end
      player.create_local_flying_text({text = {"wp-thumper.one-per-grid"}, create_at_cursor = true})
    end
    return
  end
end)

local function refresh_view()
  view_cache = nil
  for _, sc in pairs(storage.scars) do
    for _, o in pairs(scar_objects(sc)) do apply_view(o, true) end
  end
end

script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
  if event.setting == "wp-thumper-graphics" then refresh_view() end
end)
script.on_event(defines.events.on_player_joined_game, refresh_view)
script.on_event(defines.events.on_player_left_game, function(event)
  storage.ready[event.player_index] = nil
  refresh_view()
end)
