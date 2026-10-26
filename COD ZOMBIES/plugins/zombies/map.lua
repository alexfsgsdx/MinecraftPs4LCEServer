-- zombies/map.lua - the Bunker: four rooms (15 x 15, 5 high) under one roof, 33 x 33 blocks with its walls, nine boarded
-- windows each with a closet outside that zombies come from. Everything here is relative to the map's corner: x and z
-- 0..32, y 0 the floor (its blocks), 1-5 the rooms' air, 6 the ceiling. Every game plays in this one map (each party sees
-- only its own players and zombies): the world's blocks are the same for all - doors open, windows empty, no box, the
-- power off - and each game's own doors, boards, box and power are shown to its players only.
--   A Bunker (the start: x 1-15, z 1-15)    B Barracks (x 1-15, z 17-31)
--   C Armory (x 17-31, z 1-15)              D Generator Room (x 17-31, z 17-31): the power, the Pack-a-Punch
local M = {}
M.VERSION = 7          -- (the built map made again when this changes; 5: one map for every game; 6: no chests;
                       --  7: no chalk - the wall guns in item frames)
M.SIZE = 33
M.HEIGHT = 6

M.zones = {
  A = {x1 = 1, z1 = 1, x2 = 15, z2 = 15, name = "Bunker", floor = {"stonebrick", 0}},
  B = {x1 = 1, z1 = 17, x2 = 15, z2 = 31, name = "Barracks", floor = {"planks", 1}},
  C = {x1 = 17, z1 = 1, x2 = 31, z2 = 15, name = "Armory", floor = {"stone", 6}},
  D = {x1 = 17, z1 = 17, x2 = 31, z2 = 31, name = "Generator Room", floor = {"concrete", 7}},
}

-- doors: 3 wide, 3 tall (y 1-3), between two zones; "door" planks or a heap of "debris"
M.doors = {
  {cost = 750, a = "A", b = "B", x1 = 7, x2 = 9, z1 = 16, z2 = 16, style = "door"},
  {cost = 750, a = "A", b = "C", x1 = 16, x2 = 16, z1 = 7, z2 = 9, style = "debris"},
  {cost = 1000, a = "B", b = "D", x1 = 16, x2 = 16, z1 = 23, z2 = 25, style = "door"},
  {cost = 1000, a = "C", b = "D", x1 = 23, x2 = 25, z1 = 16, z2 = 16, style = "debris"},
}

-- windows: a hole 1 wide, 2 tall (y 1-2) in an outside wall, boarded; dx, dz: outwards. The closet outside: 3 wide, 3
-- deep, 3 high; zombies come in at its back (d = 3).
M.windows = {
  {zone = "A", x = 0, z = 8, dx = -1, dz = 0},
  {zone = "A", x = 4, z = 0, dx = 0, dz = -1},
  {zone = "A", x = 12, z = 0, dx = 0, dz = -1},
  {zone = "B", x = 0, z = 24, dx = -1, dz = 0},
  {zone = "B", x = 8, z = 32, dx = 0, dz = 1},
  {zone = "C", x = 24, z = 0, dx = 0, dz = -1},
  {zone = "C", x = 32, z = 8, dx = 1, dz = 0},
  {zone = "D", x = 24, z = 32, dx = 0, dz = 1},
  {zone = "D", x = 32, z = 24, dx = 1, dz = 0},
}
M.BOARDS = 6

-- guns on the walls (in an item frame at y 2, the plugin's - L2 on it, or the wall a block either side, buys it): x, z
-- the wall block it hangs on; nx, nz: the way the wall faces (into the room)
M.wallbuys = {
  {gun = "double_barrel_shotgun", name = "Olympia", cost = 500, x = 0, z = 3, nx = 1, nz = 0},
  {gun = "semi_automatic_rifle", name = "M14", cost = 500, x = 16, z = 3, nx = -1, nz = 0},
  {gun = "bolt_action_rifle", name = "Kar98k", cost = 200, x = 0, z = 29, nx = 1, nz = 0},
  {gun = "custom_smg", name = "MP40", cost = 1000, x = 4, z = 32, nx = 0, nz = -1},
  {gun = "pump_shotgun", name = "Trench Gun", cost = 1500, x = 29, z = 0, nx = 0, nz = 1},
  {gun = "thompson", name = "Thompson", cost = 1200, x = 20, z = 16, nx = 0, nz = -1},
  {gun = "bar", name = "BAR", cost = 1800, x = 32, z = 29, nx = -1, nz = 0},
  {knife = true, name = "Bowie Knife", cost = 3000, x = 16, z = 29, nx = 1, nz = 0},
}

-- perk machines: two blocks of its colour, a glass top (lit with the power), standing against a wall
M.perks = {
  {perk = "quick_revive", name = "Quick Revive", cost = 1500, solo = 500, x = 13, z = 31, colour = 3},
  {perk = "juggernog", name = "Juggernog", cost = 2500, x = 31, z = 13, colour = 14},
  {perk = "double_tap", name = "Double Tap", cost = 2000, x = 18, z = 31, colour = 1},
  {perk = "stamin_up", name = "Stamin-Up", cost = 2000, x = 31, z = 18, colour = 4},
}
M.pap = {x = 24, z = 27, cost = 5000}
M.power = {x = 28, z = 31}          -- a lever on the north wall (facing south)
-- the mystery box's places: a double chest (x, z and x2, z), facing (chest data: 2 north, 3 south)
M.boxes = {
  {zone = "A", x = 12, x2 = 13, z = 15, facing = 2},
  {zone = "B", x = 11, x2 = 12, z = 17, facing = 3},
  {zone = "C", x = 28, x2 = 29, z = 15, facing = 2},
  {zone = "D", x = 26, x2 = 27, z = 17, facing = 3},
}
M.spawns = {{6.5, 8.5}, {10.5, 8.5}, {8.5, 6.5}, {8.5, 10.5}}   -- the players' (zone A)

-- (a block's random look, the same each time a map's made)
local function hash(x, y, z, k) return ((x * 73856093) ~ (y * 19349663) ~ (z * 83492791) ~ (k * 2654435761)) & 0x7fffffff end

local function in_box(x, z, a) return x >= a.x1 and x <= a.x2 and z >= a.z1 and z <= a.z2 end

function M.door_at(x, z)
  for i, d in ipairs(M.doors) do if x >= d.x1 and x <= d.x2 and z >= d.z1 and z <= d.z2 then return i, d end end
end

function M.window_at(x, z)
  for i, w in ipairs(M.windows) do if w.x == x and w.z == z then return i, w end end
end

function M.zone_at(x, z)
  for k, a in pairs(M.zones) do if in_box(x, z, a) then return k end end
end

-- a closet's blocks: d from the wall (1..4), w across (-2..2)
local function closet_xz(w, d, across)
  if w.dx ~= 0 then return w.x + w.dx * d, w.z + across end
  return w.x + across, w.z + w.dz * d
end
M.closet_xz = closet_xz

function M.window_spots(w)   -- inside (in front of it), outside (in the closet, at it), the closet's back
  return {w.x - w.dx + 0.5, 1, w.z - w.dz + 0.5}, {w.x + w.dx + 0.5, 1, w.z + w.dz + 0.5},
         {w.x + w.dx * 3 + 0.5, 1, w.z + w.dz * 3 + 0.5}
end

function M.board_blocks(boards)   -- the window's lower and upper block for that many boards
  local function part(n) if n >= 3 then return "planks", 0 elseif n >= 1 then return "wooden_slab", 0 end return "air", 0 end
  local lb, ld = part(math.min(boards, 3))
  local ub, ud = part(math.max(0, boards - 3))
  return lb, ld, ub, ud
end

function M.debris(x, y, z)
  local pick = hash(x, y, z, 7) % 6
  if pick == 0 then return "cobblestone", 0 elseif pick == 1 then return "mossy_cobblestone", 0
  elseif pick == 2 then return "log", hash(x, y, z, 8) % 4 elseif pick == 3 then return "hay_block", 0
  elseif pick == 4 then return "stonebrick", 2 end
  return "planks", 1
end

function M.lamps(always)   -- ceiling lights (y 6), three by three in each room: the corners' always lit (always), the
  local out = {}            --   rest only with the power on
  for _, a in pairs(M.zones) do
    for _, ox in ipairs({3, 7, 11}) do
      for _, oz in ipairs({3, 7, 11}) do
        if (ox ~= 7 and oz ~= 7) == (always == true) then out[#out + 1] = {a.x1 + ox, 6, a.z1 + oz} end
      end
    end
  end
  return out
end

-- the whole map's blocks: {x, y, z, block, data} - floor, walls, ceiling, closets, then what stands in the rooms
function M.ops()
  local ops = {}
  local function put(x, y, z, b, d) ops[#ops + 1] = {x, y, z, b, d or 0} end
  local wall_cell = {}   -- walls' cells: x * 100 + z
  for x = 0, 32 do
    for z = 0, 32 do
      if x == 0 or x == 16 or x == 32 or z == 0 or z == 16 or z == 32 then wall_cell[x * 100 + z] = true end
    end
  end
  -- floor and ceiling
  for x = 0, 32 do
    for z = 0, 32 do
      local zone = M.zone_at(x, z)
      local f = zone and M.zones[zone].floor or {"stonebrick", 0}
      local fd = f[2]
      if f[1] == "stonebrick" and hash(x, 0, z, 1) % 6 == 0 then fd = 2 end
      put(x, 0, z, f[1], fd)
      put(x, 6, z, "planks", 5)
    end
  end
  -- walls: stone bricks (some mossy, some cracked), a cobblestone row along the bottom
  for key in pairs(wall_cell) do
    local x, z = key // 100, key % 100
    for y = 1, 5 do
      local b, d = "stonebrick", 0
      local r = hash(x, y, z, 2) % 10
      if y == 1 then b = "cobblestone" elseif r < 2 then d = 1 elseif r < 3 then d = 2 end
      put(x, y, z, b, d)
    end
  end
  -- the lights: the corners' always on, the rest unlit until the power's on (M.power_ops)
  for _, l in ipairs(M.lamps(true)) do put(l[1], l[2], l[3], "glowstone") end
  for _, l in ipairs(M.lamps(false)) do put(l[1], l[2], l[3], "redstone_lamp") end
  -- windows' holes and closets
  for _, w in ipairs(M.windows) do
    for d = 1, 4 do
      for across = -2, 2 do
        local x, z = closet_xz(w, d, across)
        local edge = d == 4 or across == -2 or across == 2
        put(x, 0, z, "cobblestone")
        put(x, 4, z, "cobblestone")
        for y = 1, 3 do put(x, y, z, edge and "cobblestone" or "air") end
      end
    end
    put(w.x, 3, w.z, "stonebrick", 0)
  end
  -- perk machines
  for _, p in ipairs(M.perks) do
    put(p.x, 1, p.z, "concrete", p.colour)
    put(p.x, 2, p.z, "concrete", p.colour)
    put(p.x, 3, p.z, "stained_glass", p.colour)
  end
  -- the Pack-a-Punch: obsidian under an enchanting table, iron at its sides
  put(M.pap.x, 1, M.pap.z, "obsidian")
  put(M.pap.x, 2, M.pap.z, "enchanting_table")
  put(M.pap.x - 1, 1, M.pap.z, "iron_block")
  put(M.pap.x + 1, 1, M.pap.z, "iron_block")
  -- the power: an iron panel round the lever
  for dx = -1, 1 do for y = 1, 3 do put(M.power.x + dx, y, 32, "iron_block") end end
  -- torches on the walls (two a room, always lit) and a little clutter
  local torches = {{1, 4, 5, 1}, {15, 4, 11, 2}, {1, 4, 20, 1}, {15, 4, 20, 2}, {17, 4, 5, 1}, {31, 4, 4, 2},
                   {17, 4, 26, 1}, {31, 4, 20, 2}}   -- x, y, z, data (1: on a wall to its west, 2: to its east)
  for _, t in ipairs(torches) do put(t[1], t[2], t[3], "torch", t[4]) end
  local clutter = {{2, 1, 14, "log", 0}, {3, 1, 14, "log", 0}, {2, 2, 14, "log", 0}, {14, 1, 2, "crafting_table", 0},
                   {2, 1, 18, "bookshelf", 0}, {2, 2, 18, "bookshelf", 0}, {14, 1, 18, "log", 1}, {30, 1, 2, "anvil", 0},
                   {20, 1, 2, "log", 2}, {21, 1, 2, "log", 2}, {18, 1, 20, "iron_block", 0}, {30, 1, 28, "coal_block", 0}}
  for _, c in ipairs(clutter) do put(c[1], c[2], c[3], c[4], c[5]) end
  for _, o in ipairs(M.shared_ops()) do ops[#ops + 1] = o end
  return ops
end

-- the blocks a game changes, as the world has them (every game's players see their own over them): doors open, windows
-- without boards, no box (a chest the world had where a game's box isn't would stop its players walking there), the power
-- off (lamps unlit, the lever up, the perks' tops dark)
function M.shared_ops()
  local ops = {}
  local function put(x, y, z, b, d) ops[#ops + 1] = {x, y, z, b, d or 0} end
  for _, d in ipairs(M.doors) do
    for x = d.x1, d.x2 do for z = d.z1, d.z2 do for y = 1, 3 do put(x, y, z, "air") end end end
  end
  for _, w in ipairs(M.windows) do put(w.x, 1, w.z, "air") put(w.x, 2, w.z, "air") end
  for _, b in ipairs(M.boxes) do put(b.x, 1, b.z, "air") put(b.x2, 1, b.z, "air") end
  for _, o in ipairs(M.power_ops(false)) do ops[#ops + 1] = o end
  return ops
end

function M.door_blocks(d)   -- a shut door's blocks: {x, y, z, block, data}
  local out = {}
  for x = d.x1, d.x2 do
    for z = d.z1, d.z2 do
      for y = 1, 3 do
        if d.style == "door" then out[#out + 1] = {x, y, z, "planks", 1}
        else local b, bd = M.debris(x, y, z) out[#out + 1] = {x, y, z, b, bd} end
      end
    end
  end
  return out
end

function M.power_ops(on)
  local ops = {}
  for _, l in ipairs(M.lamps(false)) do ops[#ops + 1] = {l[1], l[2], l[3], on and "glowstone" or "redstone_lamp", 0} end
  for _, p in ipairs(M.perks) do ops[#ops + 1] = {p.x, 3, p.z, on and "sea_lantern" or "stained_glass", on and 0 or p.colour} end
  ops[#ops + 1] = {M.power.x, 2, 31, "lever", on and 11 or 3}   -- (on a wall to its north, facing south; 8: on)
  return ops
end

return M
