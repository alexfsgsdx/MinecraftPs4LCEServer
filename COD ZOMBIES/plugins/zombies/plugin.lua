-- zombies: Call of Duty-style Zombies - the COD ZOMBIES server's game. Players meet in the lobby (the world's spawn) and
-- play alone or in parties of up to 4. Every game is in the same map (the Bunker - zombies/map.lua), each in a phase of
-- its own (new_block's phases): a party sees, hears and hits only its own players and zombies, and sees its own doors,
-- boards, mystery box and power (blocks shown to its players only, over the world's) - and its shut doors, boards and box
-- stop its own zombies and players only (phase walls). One map's chunks for any number of games. Chat in a game goes to its players only; in the lobby, to the lobby.
-- Rounds of zombies, more, tougher and faster each round. Points for every hit (10) and kill (60, a headshot 100, a knife
-- 130) buy guns off the walls (again: ammo, half price), doors and debris into the other rooms, the mystery box (950: a
-- random gun - it moves now and then), perks once the power's on (Juggernog, Quick Revive, Double Tap, Stamin-Up) and the
-- Pack-a-Punch (5000: the gun in your hand, much stronger). Zombies tear the boards off the windows to get in - click a
-- window to put them back (10 points a board). Power-ups drop: Max Ammo, Insta-Kill, Double Points, Nuke, Carpenter.
-- Down, a teammate standing by you revives you (Quick Revive: faster; alone with it, you get up by yourself); 30 seconds
-- and you bleed out, back next round. When everyone's down it's over.
-- In the lobby hit (or use) the gold block to play - your party with you - and the blue one for your party; /z does it too:
--   /z play | invite <player> | accept | leave | quit (a game, back to the lobby) | top
-- Needs new_block 3.65 on the server (the shot and kill events, loaded guns, phases, blocks shown to one player). The
-- map's blocks: superflat world, made the first time it's needed.
plugin.info{version = "2.0", author = "new_block", description = "COD-style Zombies: parties, rounds, wall buys, the box, perks"}

local MAP = require("map")

plugin.setting("max-games", {label = "Games at once", type = "number", default = 8, min = 1, max = 24, step = 1,
  note = "All in the same map - each party sees only its own players and zombies"})
plugin.setting("party-size", {label = "Players a party", type = "number", default = 4, min = 1, max = 8, step = 1})
plugin.setting("start-points", {label = "Points to start with", type = "number", default = 500, min = 0, max = 100000, step = 100})
plugin.setting("max-zombies", {label = "Zombies at once (alone)", type = "number", default = 24, min = 4, max = 60, step = 2,
  note = "6 more for each player past the first"})

local W = 0                   -- the server's own world (superflat)
local ORIGIN = {x = 300, z = -700}   -- the map's corner (where the first of 1.0's maps was)
local LOBBY_V = 2
local BUILD_PER_TICK = 400
local ZOMBIE_DAMAGE = 8       -- a zombie's hit (half hearts): two put you down, four with Juggernog
local DOWN_AT = 8.5           -- (health left after a hit at or under this: down - so a hit never kills)
local DOWN_AT_JUGG = 5
local BLEED_TICKS = 600       -- 30 s down before you bleed out
local REVIVE_TICKS = 80       -- 4 s (Quick Revive: 2 s)
local TEAR_TICKS = 30         -- a zombie at a window takes off a board this often
local BREAK_TICKS = 200       -- between rounds
local KNIFE, BOWIE = 15, 90   -- the knife's hit, the Bowie knife's
local SHOW_AGAIN = 200        -- a game's blocks shown to its players again this often (anything that showed the world's)
local LABEL_RANGE = 12        -- the box's spin text seen only this close (blocks; new_block 3.65's spawn_text range)
local POWERUP_RANGE = 32
local LOOK = 4.5              -- a prompt for what a player looks at this close (COD's "Press ... to buy ...")
local tick = 0
-- the guns: their COD-style names, what they fire, a magazine
local GUNS = {
  semi_automatic_pistol = {"M1911", "pistol_bullet", 10}, revolver = {"Revolver", "pistol_bullet", 8},
  custom_smg = {"MP40", "pistol_bullet", 24}, thompson = {"Thompson", "pistol_bullet", 20},
  assault_rifle = {"STG-44", "rifle_ammo", 30}, semi_automatic_rifle = {"M14", "rifle_ammo", 16},
  bolt_action_rifle = {"Kar98k", "rifle_ammo", 4}, pump_shotgun = {"Trench Gun", "shotgun_shell", 6},
  double_barrel_shotgun = {"Olympia", "shotgun_shell", 2}, magnum = {".44 Magnum", "pistol_bullet", 6},
  aa12 = {"AA-12", "shotgun_shell", 20}, ak47 = {"AK-47", "rifle_ammo", 30}, ak74u = {"AK-74u", "rifle_ammo", 30},
  aks74 = {"AKS-74", "rifle_ammo", 30}, ar15 = {"AR-15", "rifle_ammo", 20}, bar = {"BAR", "rifle_ammo", 20},
  barrett = {"Barrett .50", "rifle_ammo", 5}, bolt_sniper = {"L96", "rifle_ammo", 5}, dragunov = {"Dragunov", "rifle_ammo", 10},
  hunting_rifle = {"Hunting Rifle", "rifle_ammo", 5}, m16 = {"M16", "rifle_ammo", 30}, m60 = {"M60", "rifle_ammo", 100},
  p90 = {"P90", "pistol_bullet", 50}, pp90 = {"PP-90", "pistol_bullet", 30}, rpk = {"RPK", "rifle_ammo", 75},
  scar = {"SCAR", "rifle_ammo", 20}, spas12 = {"SPAS-12", "shotgun_shell", 8}, tec9 = {"TEC-9", "pistol_bullet", 32},
  type98 = {"Type 100", "rifle_ammo", 30}, vector = {"Vector", "pistol_bullet", 25},
}
local BOX_POOL = {}
for k in pairs(GUNS) do if k ~= "semi_automatic_pistol" then BOX_POOL[#BOX_POOL + 1] = k end end
table.sort(BOX_POOL)

local PERKS = {}
for _, p in ipairs(MAP.perks) do PERKS[p.perk] = p end
local POWERUPS = {
  max_ammo = "&a&lMAX AMMO", insta_kill = "&c&lINSTA-KILL", double_points = "&e&lDOUBLE POINTS", nuke = "&6&lKA-BOOM",
  carpenter = "&b&lCARPENTER",
}
local POWERUP_KINDS = {"max_ammo", "insta_kill", "double_points", "nuke", "carpenter"}


-- --- state
local games = {}      -- game id -> its game
local game_of = {}    -- player name -> their game
local parties = {}    -- leader -> {names}
local party_of = {}   -- name -> leader
local invites = {}    -- name -> {from = leader, at = tick}
local jobs = {}       -- blocks being put: {ops, i, later, done}
local lobby = nil     -- {x, y, z} its corner
local map = nil       -- {x, y, z} the map's corner, once it's there
local map_waiting = {}   -- what waits for the map
local map_making = false
local ours = {}       -- uuid -> true: the entities in the map that are ours (labels, zombies, power-ups)
local next_id = 0     -- games' ids (each also its phase)
local hits = {}       -- knife hits to do next tick
local lobby_cd = {}   -- name -> tick: the lobby's blocks answer again from then
local t5 = 0          -- (the 5-tick loop's count)

plugin.data.stats = plugin.data.stats or {}

-- --- little things
local function rnd(a, b) return math.random(a, b) end
local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
local function dist2(x1, z1, x2, z2) return (x1 - x2) ^ 2 + (z1 - z2) ^ 2 end
local function in_phase(g, fn, ...)   -- fn(...) as the game's phase (its sounds, particles, what it spawns: its own)
  if g then return server.in_phase(g.phase, fn, ...) end
  return fn(...)
end
local function sound(g, name, x, y, z, vol, pitch) pcall(in_phase, g, server.sound, name, x, y, z, W, vol or 1, pitch or 1) end
local function particles(g, name, x, y, z, ...) pcall(in_phase, g, server.particles, name, x, y, z, W, ...) end
local function members(g)   -- its players still here: name, player, their state
  local out = {}
  for _, name in ipairs(g.order) do
    local pl = g.pl[name]
    local p = pl and not pl.left and player(name)
    if p then out[#out + 1] = {name = name, p = p, pl = pl} end
  end
  return out
end
local function tell(g, text, notice)
  for _, m in ipairs(members(g)) do
    if notice then pcall(m.p.notice, m.p, text) else m.p:message(text) end
  end
end
local function gsound(g, name, vol, pitch)   -- heard all over the map (by its game)
  sound(g, name, map.x + 16, map.y + 3, map.z + 16, vol or 3, pitch)
end
local function standing(pl) return pl and not pl.left and not pl.downed and not pl.dead end
local STAT_KEYS = {"best", "kills", "headshots", "downs", "deaths", "revives", "games"}
local stats_dirty = false
local function stats(name)   -- a player's record (data.lua: kept through restarts) - counted as things happen
  local s = plugin.data.stats[name]
  if not s then s = {} plugin.data.stats[name] = s end
  for _, k in ipairs(STAT_KEYS) do s[k] = s[k] or 0 end
  stats_dirty = true
  return s
end

-- --- putting blocks down: a queue, BUILD_PER_TICK a tick, each block's chunk loaded first (4 a tick at most)
local function queue(ops, done) jobs[#jobs + 1] = {ops = ops, i = 1, later = {}, held = {}, done = done} end

every(1, function()
  tick = tick + 1
  local job = jobs[1]
  if not job then return end
  local budget, loaded, loads = BUILD_PER_TICK, {}, 0
  while budget > 0 do
    local o = job.ops[job.i]
    if not o then
      if #job.later > 0 then job.ops, job.later, job.i, job.held = job.later, {}, 1, {} end
      break
    end
    job.i = job.i + 1
    local cx, cz = o[1] // 16, o[3] // 16
    local ck = cx * 65536 + cz
    if job.held[ck] then loaded[ck] = false end   -- (a chunk with blocks waiting: all its blocks wait, in their order)
    if loaded[ck] == nil then
      loaded[ck] = server.loaded(o[1], o[3], W)
      if not loaded[ck] and loads < 4 then
        server.top_block(cx * 16 + 8, cz * 16 + 8)
        loads = loads + 1
        loaded[ck] = server.loaded(o[1], o[3], W)
      end
    end
    if loaded[ck] then
      server.set_block(o[1], o[2], o[3], W, o[4], o[5] or 0)
      budget = budget - 1
    else
      job.later[#job.later + 1] = o
      job.held[ck] = true
    end
  end
  if not job.ops[job.i] and #job.later == 0 then
    table.remove(jobs, 1)
    if job.done then job.done() end
  end
end)

-- --- the lobby (at the world's spawn: a room of its own, made once)
local LOBBY = {play = {8, 1, 14}, party = {4, 1, 14}, top = {12, 1, 14}}
local function lobby_spawn()
  return lobby.x + 8.5, lobby.y + 1, lobby.z + 6.5
end

local function leaderboard()   -- the lobby's billboards (new_block's): the best rounds on its west wall, the most kills east
  if not lobby then return end
  local list = {}
  for name, st in pairs(plugin.data.stats) do
    if st.best > 0 or st.kills > 0 then list[#list + 1] = {name:sub(1, 16), st.best, st.kills} end
  end
  local function board(key, title, by, what, yaw, dx)
    table.sort(list, function(a, b) return a[by] > b[by] or (a[by] == b[by] and a[1] < b[1]) end)
    local lines = {title}
    for i = 1, math.min(7, #list) do
      if list[i][by] > 0 then lines[#lines + 1] = string.format("&e%d. &f%s &7- &c%s", i, list[i][1], what(list[i][by])) end
    end
    if #lines == 1 then lines[2] = "&7Nobody yet - be the first!" end
    pcall(server.billboard, key, {x = lobby.x + dx, y = lobby.y + 3.3, z = lobby.z + 8.5, dim = W, yaw = yaw, lines = lines,
                                  scale = 2.2})
  end
  board("leaderboard", "&6&lBEST ROUNDS", 2, function(n) return "Round " .. n end, 90, 1.08)
  board("killboard", "&4&lMOST KILLS", 3, function(n) return n .. " kills" end, 90, 15.92)
end

local function lobby_texts()   -- (the old holograms gone: the title's a billboard, the blocks have prompts)
  local x, y, z = lobby.x, lobby.y, lobby.z
  for _, e in ipairs(server.entities(x + 8, y + 3, z + 8, W, 16, "area_effect_cloud")) do e:remove() end
  pcall(server.billboard, "title", {x = x + 8.5, y = y + 4, z = z + 15.9, dim = W, yaw = 180, scale = 2.6,
                                    lines = {"&c&lCOD ZOMBIES", "&7Survive as long as you can"}})
  leaderboard()
end

local LOBBY_PROMPTS = {{"play", "Press R2 to play"}, {"party", "Press R2 for a party (play with friends)"},   -- (empty
                       {"top", "Press R2 for the best rounds"}}                                           --  hands: a hit)
local function lobby_prompt(p)   -- what they look at in the lobby (its blocks) within LOOK blocks
  local x, y, z, _, yaw, pitch = p:position()
  if not yaw or not lobby then return nil end
  local ry, rp = math.rad(yaw), math.rad(pitch or 0)
  local dx, dy, dz = -math.sin(ry) * math.cos(rp), -math.sin(rp), math.cos(ry) * math.cos(rp)
  local ex, ey, ez = x - lobby.x, y + 1.62 - lobby.y, z - lobby.z
  for t = 0.2, LOOK, 0.15 do
    local cx, cy, cz = math.floor(ex + dx * t), math.floor(ey + dy * t), math.floor(ez + dz * t)
    for _, lp in ipairs(LOBBY_PROMPTS) do
      local c = LOBBY[lp[1]]
      if cx == c[1] and cy == c[2] and cz == c[3] then return lp[2] end
    end
    if cy <= 0 or cy >= 6 or cx <= 0 or cx >= 16 or cz <= 0 or cz >= 16 then return nil end
  end
end

local function lobby_ops()
  local ops = {}
  local function put(x, y, z, b, d) ops[#ops + 1] = {lobby.x + x, lobby.y + y, lobby.z + z, b, d or 0} end
  for x = 0, 16 do
    for z = 0, 16 do
      put(x, 0, z, (x + z) % 2 == 0 and "quartz_block" or "concrete", (x + z) % 2 == 0 and 0 or 15)
      put(x, 6, z, (x % 3 == 1 and z % 3 == 1) and "sea_lantern" or "quartz_block")
      local edge = x == 0 or x == 16 or z == 0 or z == 16
      for y = 1, 5 do
        local b, d = "air", 0
        if edge then
          if y == 1 or y == 5 then b, d = "concrete", 14
          elseif y == 3 and (x + z) % 4 == 0 then b = "glowstone"
          else b = "quartz_block" end
        end
        put(x, y, z, b, d)
      end
    end
  end
  put(LOBBY.play[1], 1, LOBBY.play[3], "gold_block")
  put(LOBBY.party[1], 1, LOBBY.party[3], "lapis_block")
  put(LOBBY.top[1], 1, LOBBY.top[3], "diamond_block")
  for _, c in ipairs({{2, 2}, {14, 2}, {2, 14}, {14, 14}}) do put(c[1], 1, c[2], "redstone_block") put(c[1], 2, c[2], "sea_lantern") end
  return ops
end

local function ensure_lobby()
  local sx, sy, sz = server.spawn()
  local d = plugin.data.lobby
  if d and d.v == LOBBY_V then
    lobby = {x = d.x, y = d.y, z = d.z}
    server.top_block(lobby.x + LOBBY.play[1], lobby.z + LOBBY.play[3])   -- (its chunk loaded)
    local _, _, name = server.block(lobby.x + LOBBY.play[1], lobby.y + LOBBY.play[2], lobby.z + LOBBY.play[3], W)
    if name == "gold_block" then
      lobby_texts()
      return
    end
    log("the lobby's blocks aren't there (the world not saved after it was made?) - made again")
  end
  if d then   -- (an older lobby: made again where it is)
    lobby = {x = d.x, y = d.y, z = d.z}
  else
    local gy = server.top_block(math.floor(sx), math.floor(sz)) or math.floor(sy) - 1
    lobby = {x = math.floor(sx) - 8, y = gy, z = math.floor(sz) - 8}
  end
  queue(lobby_ops(), function()
    plugin.data.lobby = {v = LOBBY_V, x = lobby.x, y = lobby.y, z = lobby.z}
    plugin.save()
    local x, y, z = lobby_spawn()
    pcall(server.set_spawn, math.floor(x), math.floor(y), math.floor(z))
    lobby_texts()
    log("the lobby's made at " .. lobby.x .. ", " .. lobby.y .. ", " .. lobby.z)
  end)
end

local function lobby_sidebar(p)
  local leader = party_of[p.name]
  local lines = {}
  if leader then
    lines[#lines + 1] = "&7Party (" .. #parties[leader] .. "):"
    for _, n in ipairs(parties[leader]) do lines[#lines + 1] = "&f " .. n .. (n == leader and " &e*" or "") end
  else
    lines[#lines + 1] = "&7Playing alone"
  end
  lines[#lines + 1] = "&7Games running: &f" .. count(games)
  lines[#lines + 1] = "&6Gold block&7: play"
  lines[#lines + 1] = "&9Blue block&7: party"
  local s = plugin.data.stats[p.name]
  if s and (s.games or 0) > 0 then
    lines[#lines + 1] = "&7Best round: &f" .. (s.best or 0)
    lines[#lines + 1] = "&7Kills: &f" .. (s.kills or 0) .. "  &7Deaths: &f" .. (s.deaths or 0)
  end
  pcall(p.sidebar, p, "&c&lCOD ZOMBIES", lines)
end

local function clear_inventory(p)
  local inv = p:inventory()
  for slot in pairs(inv) do p:set_item(slot, nil) end
end

local function to_lobby(p)
  if not lobby then return end
  local x, y, z = lobby_spawn()
  pcall(p.set_phase, p, 0)
  if p:gamemode() ~= "survival" then p:set_gamemode("survival") end
  p:teleport(x, y, z, 0, 0)   -- (facing the play and party blocks)
  clear_inventory(p)
  for _, fx in ipairs({"slowness", "resistance", "speed", "jump_boost"}) do pcall(p.remove_effect, p, fx) end
  pcall(p.heal, p)
  pcall(p.countdown, p, 0)
  pcall(p.hud_icons, p, nil)
  lobby_sidebar(p)
end

-- --- the map: one, for every game
local function label(g, x, y, z, text)   -- a hologram in the map (g: that game's only; nil: every game's), seen close up
  local e = in_phase(g, server.spawn_text, map.x + x, map.y + y, map.z + z, W, text, LABEL_RANGE)
  if e then
    ours[e:uuid()] = true
    if g then g.texts[#g.texts + 1] = e end
  end
  return e
end

-- the wall guns: each in an item frame on its wall (every game's - no phase), bought with L2 on it (on "interact"). The
-- frames are the world's (saved with the map's chunks, which unload while nobody plays - back with new ids): found by
-- where they hang, never kept by handle.
local FACING = {["1,0"] = "east", ["-1,0"] = "west", ["0,1"] = "south", ["0,-1"] = "north"}
local function frame_spot(b) return map.x + b.x + b.nx, map.y + 2, map.z + b.z + b.nz end
local function frame_wall(e)   -- the wall buy an item frame hangs for, or nil
  if not map then return nil end
  local x, y, z = e:position()
  for _, b in ipairs(MAP.wallbuys) do
    local fx, fy, fz = frame_spot(b)
    if math.abs(x - fx - 0.5) < 0.9 and math.abs(y - fy - 0.5) < 0.9 and math.abs(z - fz - 0.5) < 0.9 then return b end
  end
end
local function wall_frames()   -- every wall gun in its frame: the one there kept (and ours), a missing one put up
  if not map then return end
  local put = 0
  for _, b in ipairs(MAP.wallbuys) do
    local fx, fy, fz = frame_spot(b)
    if server.loaded(fx, fz, W) then
      local e = server.entities(fx + 0.5, fy + 0.5, fz + 0.5, W, 1.2, "item_frame")[1]
      if not e then   -- (no name on the item: the screen's prompt says what it is)
        local ok, f, why = pcall(server.item_frame, fx, fy, fz, W, FACING[b.nx .. "," .. b.nz],
                                 {name = b.knife and "diamond_sword" or b.gun})
        if ok and f then e, put = f, put + 1 else log("the " .. b.name .. "'s frame: " .. tostring(ok and why or f)) end
      end
      if e then ours[e:uuid()] = true end
    end
  end
  if put > 0 then log(put .. " wall gun frame" .. (put > 1 and "s" or "") .. " put up") end
end

local function map_chunks_loaded()
  for cx = (ORIGIN.x - 6) // 16, (ORIGIN.x + 38) // 16 do
    for cz = (ORIGIN.z - 6) // 16, (ORIGIN.z + 38) // 16 do
      if not server.loaded(cx * 16 + 8, cz * 16 + 8, W) then server.top_block(cx * 16 + 8, cz * 16 + 8) end
    end
  end
end

local function map_intact(y)   -- (its blocks there: a crash before the world was saved loses them)
  local ox, oz = ORIGIN.x, ORIGIN.z
  map_chunks_loaded()
  local _, _, mid = server.block(ox + 16, y + 1, oz + 16, W)
  local _, _, c1 = server.block(ox, y + 6, oz, W)
  local _, _, c2 = server.block(ox + 32, y + 6, oz + 32, W)
  return mid == "cobblestone" and c1 == "planks" and c2 == "planks"
end

local function map_done(y)
  map = {x = ORIGIN.x, y = y, z = ORIGIN.z}
  map_making = false
  map_chunks_loaded()
  -- (what a restart left there - labels, zombies, items: none of it a game's any more) gone, then every game's labels
  for _, e in ipairs(server.entities(map.x + 16, map.y + 3, map.z + 16, W, 40)) do if not e:is_player() then e:remove() end end
  for _, kind in ipairs({"area_effect_cloud", "item", "experience_orb"}) do
    for _, e in ipairs(server.entities(map.x + 16, map.y + 3, map.z + 16, W, 40, kind)) do e:remove() end
  end
  ours = {}
  wall_frames()
  local waiting = map_waiting
  map_waiting = {}
  for _, f in ipairs(waiting) do f() end
end

local function ensure_map(done)   -- the map made (if it isn't) - then done()
  if map then return done and done() end
  if done then map_waiting[#map_waiting + 1] = done end
  if map_making then return end
  map_making = true
  local old = plugin.data.arenas and plugin.data.arenas[1]   -- (1.0's first map: made again where it was)
  local d = plugin.data.map or (old and {y = old.y})
  if d and d.v == MAP.VERSION then
    if map_intact(d.y) then return map_done(d.y) end
    log("the map's blocks aren't there (the world not saved after it was made?) - made again")
  end
  local ox, oz = ORIGIN.x, ORIGIN.z
  local gy = d and d.y or server.top_block(ox + 16, oz + 16) or 3   -- (made again: where it was - its roof's on top now)
  local ops = {}
  for x = -5, 37 do for z = -5, 37 do for y = 1, 7 do ops[#ops + 1] = {ox + x, gy + y, oz + z, "air", 0} end end end
  for _, o in ipairs(MAP.ops()) do ops[#ops + 1] = {ox + o[1], gy + o[2], oz + o[3], o[4], o[5]} end
  log(string.format("the map: making it at %d, %d, %d (%d blocks)", ox, gy, oz, #ops))
  queue(ops, function()
    plugin.data.map = {v = MAP.VERSION, y = gy}
    plugin.data.arenas = nil
    plugin.save()
    map_done(gy)
  end)
end

-- --- a game's own blocks, shown to its players over the world's (which has doors open, windows bare, no box, the power
-- off): {x, y, z, block, data} - block nil: the world's
local function fake_list(g)
  local out = {}
  local function put(x, y, z, b, d) out[#out + 1] = {map.x + x, map.y + y, map.z + z, b, d or 0} end
  for di, d in ipairs(MAP.doors) do
    if not g.doors[di] then for _, b in ipairs(MAP.door_blocks(d)) do put(b[1], b[2], b[3], b[4], b[5]) end end
  end
  for wi, w in ipairs(MAP.windows) do
    local lb, ld, ub, ud = MAP.board_blocks(g.boards[wi])
    if lb ~= "air" then put(w.x, 1, w.z, lb, ld) end
    if ub ~= "air" then put(w.x, 2, w.z, ub, ud) end
  end
  local b = MAP.boxes[g.box]
  if not g.box_moving then put(b.x, 1, b.z, "chest", b.facing) put(b.x2, 1, b.z, "chest", b.facing) end
  if g.power then for _, o in ipairs(MAP.power_ops(true)) do put(o[1], o[2], o[3], o[4], o[5]) end end
  return out
end

local shown, show_failed = 0, 0
local function show(p, list)
  for _, b in ipairs(list) do
    local ok, done, why = pcall(p.show_block, p, b[1], b[2], b[3], b[4], b[5])
    if ok and done then shown = shown + 1
    else
      show_failed = show_failed + 1
      if show_failed <= 3 then log("a block not shown to " .. p.name .. ": " .. tostring(ok and why or done)) end
    end
  end
end

local function show_game(g, list)   -- (map-relative {x, y, z, block, data}) to all its players
  local abs = {}
  for i, b in ipairs(list) do abs[i] = {map.x + b[1], map.y + b[2], map.z + b[3], b[4], b[5]} end
  for _, m in ipairs(members(g)) do show(m.p, abs) end
end

local function show_near(g, p, x, y, z)   -- (after a click: the server sent them the world's blocks round it)
  local near = {}
  for _, b in ipairs(fake_list(g)) do
    if math.abs(b[1] - x) <= 2 and math.abs(b[2] - y) <= 2 and math.abs(b[3] - z) <= 2 then near[#near + 1] = b end
  end
  show(p, near)
end

-- a game's walls: its shut doors, boarded windows and box are solid for its own zombies and players only (the world has
-- air there) - so its zombies stop at them as at the blocks its players are shown
local function walls(g, cells, on)   -- (map-relative {x, y, z, ...})
  for _, c in ipairs(cells) do pcall(server.phase_wall, g.phase, map.x + c[1], map.y + c[2], map.z + c[3], W, on) end
end

local function window_cells(w) return {{w.x, 1, w.z}, {w.x, 2, w.z}} end

local function arrived(pl)   -- in the map from afar: its chunks come first, then the game's blocks over them
  pl.shows = {tick + 30, tick + 60, tick + 100, tick + 160}
  pl.show_next = tick + SHOW_AGAIN
end
-- --- guns, ammo, the knife
local function gun_item(key, pap)
  local g = GUNS[key]
  return {name = key, count = 1, rounds = g[3], label = pap and ("&d" .. g[1] .. " &5Upgraded") or ("&f" .. g[1]),
          enchants = pap and {[34] = 1} or nil}
end

local function reserve(key, pap)   -- the most of its ammo a gun comes with (Max Ammo fills to it)
  local g = GUNS[key]
  return math.min(320, math.max(24, g[3] * 6)) * (pap and 2 or 1)
end

local function owned_guns(p)   -- {[key] = slot}
  local out = {}
  for slot, it in pairs(p:inventory()) do if GUNS[it.name] and slot < 9 then out[it.name] = slot end end
  return out
end

local function ammo_of(p, name)
  local n = 0
  for _, it in pairs(p:inventory()) do if it.name == name then n = n + it.count end end
  return n
end

local function top_up(p, name, want)   -- that much of an ammo, at least
  local have = ammo_of(p, name)
  local more = want - have
  while more > 0 do
    local c = math.min(64, more)
    p:give_item({name = name, count = c})
    more = more - c
  end
end

local function fill_ammo(p, pl)   -- every gun's ammo to the full (Max Ammo), magazines too
  local want = {}
  for key, slot in pairs(owned_guns(p)) do
    local a = GUNS[key][2]
    want[a] = (want[a] or 0) + reserve(key, pl.pap[key])
    p:set_item(slot, gun_item(key, pl.pap[key]))
  end
  for a, n in pairs(want) do top_up(p, a, n) end
end

local function give_gun(p, pl, key, pap)
  local inv, held = p:inventory(), p:held_slot()
  local slot
  if not inv[1] then slot = 1 elseif not inv[2] then slot = 2
  elseif held == 1 or held == 2 then slot = held else slot = 2 end
  local old = inv[slot]
  if old and GUNS[old.name] then pl.pap[old.name] = nil end
  pl.pap[key] = pap or nil
  p:set_item(slot, gun_item(key, pap))
  top_up(p, GUNS[key][2], reserve(key, pap))
end

local function loadout(p, pl)
  clear_inventory(p)
  pl.pap, pl.bowie = {}, false
  p:set_item(0, {name = "iron_sword", label = "&fKnife"})
  give_gun(p, pl, "semi_automatic_pistol")
end


-- --- points
local function add_points(g, pl, n)
  if n > 0 and tick < (g.double_until or 0) then n = n * 2 end
  pl.points = pl.points + n
  pl.earned = (pl.earned or 0) + math.max(0, n)
end

local function spend(g, p, pl, cost, what)
  if pl.points < cost then
    pcall(p.notice, p, "&cNot enough points &7(" .. cost .. " for " .. what .. ")")
    local x, y, z = p:position()
    sound(g, "zombies.denied", x, y, z, 0.6)
    return false
  end
  pl.points = pl.points - cost
  local x, y, z = p:position()
  sound(g, "zombies.buy", x, y, z, 0.7)
  log(string.format("game %d: %s bought %s (%d, %d left)", g.id, p.name, what, cost, pl.points))
  return true
end

-- --- a game's labels: none now (the on-screen prompts say what things are) - only the box's text while it spins
local function box_label(g)   -- (the box's spin text gone)
  if g.box_text and g.box_text:valid() then ours[g.box_text:uuid()] = nil g.box_text:remove() end
  g.box_text = nil
end

local function labels(g)
  g.door_text = {}
  box_label(g)
end

local function remove_texts(g)
  for _, e in ipairs(g.texts) do
    if e:valid() then ours[e:uuid()] = nil e:remove() end
  end
  g.texts = {}
end

local function box_cells(g, bi, on)   -- (map-relative) a box place's blocks for the game: its chest, or none
  local b = MAP.boxes[bi]
  return {{b.x, 1, b.z, on and "chest" or nil, on and b.facing or 0}, {b.x2, 1, b.z, on and "chest" or nil, on and b.facing or 0}}
end

local function place_box(g, bi, on)   -- (its players shown it, and it's in their and its zombies' way)
  local cells = box_cells(g, bi, on)
  show_game(g, cells)
  walls(g, cells, on)
end

-- --- a game
local function sidebar(g)
  local title = g.round > 0 and ("&c&lROUND " .. g.round) or "&7&lGET READY"
  local lines = {}
  for _, m in ipairs(members(g)) do
    local pl = m.pl
    local col = pl.dead and "&8" or pl.downed and "&c" or "&f"
    lines[#lines + 1] = {text = col .. m.name .. (pl.downed and " (down)" or pl.dead and " (dead)" or ""), score = pl.points}
  end
  if g.state == "round" then lines[#lines + 1] = "&7Zombies left: &f" .. math.max(0, g.to_spawn - g.killed) end
  if tick < (g.insta_until or 0) then lines[#lines + 1] = "&cInsta-Kill &f" .. (g.insta_until - tick) // 20 .. "s" end
  if tick < (g.double_until or 0) then lines[#lines + 1] = "&eDouble Points &f" .. (g.double_until - tick) // 20 .. "s" end
  if g.power then lines[#lines + 1] = "&ePower on" end
  for _, m in ipairs(members(g)) do pcall(m.p.sidebar, m.p, title, lines) end
end
local function zombie_count(r, n)
  local base = r <= 5 and ({6, 8, 13, 18, 24})[r] or math.floor(24 + 0.15 * r * r)
  return math.min(250, math.floor(base * (1 + 0.6 * (n - 1))))
end

local function zombie_health(r)   -- COD's, a tenth (half hearts)
  local h = r < 10 and (150 + 100 * (r - 1)) or 950 * 1.1 ^ (r - 9)
  return math.min(100000, math.floor(h / 10))
end

local function zombie_speed(r)
  local run = r <= 3 and 0 or math.min(0.9, (r - 3) * 0.15)
  local sprint = r < 10 and 0 or math.min(0.7, (r - 9) * 0.1)
  local x = math.random()
  if x < sprint then return 0.36 elseif x < run then return 0.3 end
  return 0.2 + math.random() * 0.03
end

local function spawn_spot()
  local s = MAP.spawns[rnd(1, #MAP.spawns)]
  return map.x + s[1], map.y + 1, map.z + s[2]
end

local function start_round(g)
  g.round = g.round + 1
  g.state = "round"
  local n = #members(g)
  g.to_spawn, g.spawned, g.killed = zombie_count(g.round, math.max(1, n)), 0, 0
  g.zhp = zombie_health(g.round)
  g.next_spawn = tick + 60
  g.powerups_round = 0
  for _, m in ipairs(members(g)) do
    m.pl.repaired = 0
    local st = stats(m.name)
    if g.round > st.best then st.best = g.round end
  end
  gsound(g, "zombies.round_start", 4)
  tell(g, "&c&lROUND " .. g.round, true)
  log(string.format("game %d: round %d - %d zombies, %d health", g.id, g.round, g.to_spawn, g.zhp))
  sidebar(g)
end

local function revive_dead(g)   -- the dead are back (between rounds), with the pistol
  for _, m in ipairs(members(g)) do
    local pl, p = m.pl, m.p
    if pl.dead then
      pl.dead = false
      p:set_gamemode("survival")
      local x, y, z = spawn_spot()
      p:teleport(x, y, z)
      pcall(p.heal, p)
      loadout(p, pl)
      tell(g, "&a" .. m.name .. " is back")
    end
  end
end

local function end_round(g)
  g.state = "break"
  g.next_round = tick + BREAK_TICKS
  gsound(g, "zombies.round_end", 4)
  revive_dead(g)
  for _, m in ipairs(members(g)) do pcall(m.p.countdown, m.p, BREAK_TICKS // 20, "&cRound " .. (g.round + 1) .. " in {s}") end
  sidebar(g)
end

local function remove_zombies(g)
  for uuid, z in pairs(g.zombies) do
    if z.e:valid() then z.e:remove() end
    ours[uuid] = nil
  end
  g.zombies = {}
end

local function finish(g, why)
  if g.state == "over" then return end
  g.state = "over"
  remove_zombies(g)
  for _, pu in ipairs(g.powerups or {}) do if pu.text and pu.text:valid() then pu.text:remove() end end
  g.powerups = {}
  gsound(g, "zombies.game_over", 4)
  local rounds = math.max(0, g.round - (why == "down" and 1 or 0))
  for _, m in ipairs(members(g)) do
    local pl, p = m.pl, m.p
    local s = stats(m.name)
    s.games = s.games + 1
    if pl.downed then s.deaths = s.deaths + 1 end   -- (down as it ended: that's how they died)
    if g.round > s.best then s.best = g.round end
    p:message("&c&lGAME OVER &7- you survived &f" .. rounds .. " round" .. (rounds == 1 and "" or "s"))
    p:message(string.format("&7Kills &f%d &7(headshots %d), downs &f%d&7, revives &f%d&7, points earned &f%d",
                            pl.kills, pl.headshots, pl.downs, pl.revives, pl.earned or 0))
    pcall(p.countdown, p, 0)
    pcall(p.sidebar, p, "&c&lGAME OVER", {"&7Round &f" .. g.round, "&7Kills &f" .. pl.kills})
  end
  plugin.save()
  stats_dirty = false
  leaderboard()
  log(string.format("game %d over (%s) at round %d", g.id, why or "?", g.round))
  after(160, function()
    for _, m in ipairs(members(g)) do
      game_of[m.name] = nil
      to_lobby(m.p)
    end
    for name in pairs(g.pl) do if game_of[name] == g then game_of[name] = nil end end
    remove_texts(g)
    pcall(server.phase_walls_clear, g.phase)
    games[g.id] = nil
  end)
end

local function start_game(names)
  local ps = {}
  for _, n in ipairs(names) do local p = player(n) if p and not game_of[n] then ps[#ps + 1] = p end end
  if #ps == 0 or not lobby then return end
  if count(games) >= setting("max-games") then
    for _, p in ipairs(ps) do p:message("&cThe most games at once are being played - try again in a moment") end
    return
  end
  next_id = next_id + 1
  local id = next_id
  local g = {id = id, phase = id, order = {}, pl = {}, state = "making", round = 0, zombies = {}, texts = {}, door_text = {},
             boards = {}, doors = {}, zones = {A = true}, power = false, box = rnd(1, #MAP.boxes), box_uses = 0,
             powerups = {}, to_spawn = 0, spawned = 0, killed = 0}
  games[id] = g
  local solo = #ps == 1
  for _, p in ipairs(ps) do
    g.order[#g.order + 1] = p.name
    g.pl[p.name] = {points = setting("start-points"), kills = 0, headshots = 0, downs = 0, revives = 0, perks = {},
                    pap = {}, last_hurt = 0, self_revives = solo and 3 or 0, earned = 0, cd = 0}
    game_of[p.name] = g
  end
  g.solo = solo
  for w = 1, #MAP.windows do g.boards[w] = MAP.BOARDS end
  if not map then for _, p in ipairs(ps) do pcall(p.notice, p, "&7Getting the map ready...") end end
  ensure_map(function()
    if g.state ~= "making" then return end
    g.ox, g.oy, g.oz = map.x, map.y, map.z
    for _, d in ipairs(MAP.doors) do walls(g, MAP.door_blocks(d), true) end
    for _, w in ipairs(MAP.windows) do walls(g, window_cells(w), true) end
    walls(g, box_cells(g, g.box, true), true)
    local k = 0
    for _, m in ipairs(members(g)) do
      k = k + 1
      local s = MAP.spawns[(k - 1) % #MAP.spawns + 1]
      local ok, err = pcall(m.p.set_phase, m.p, g.phase)   -- (first: they're in the game's phase as they get there)
      if not ok then log("game " .. id .. ": no phases (" .. tostring(err) .. ") - every game would see the others") end
      m.p:set_gamemode("survival")
      m.p:teleport(map.x + s[1], map.y + 1, map.z + s[2], 0, 0)
      arrived(m.pl)
      pcall(m.p.heal, m.p)
      loadout(m.p, m.pl)
      pcall(m.p.countdown, m.p, 5, "&cRound 1 in {s}")
      m.p:message("&c&lCOD ZOMBIES &7- the Bunker. &fShoot the zombies, buy guns off the walls, open the doors, find the power.")
      m.p:message("&7L2: board up a window, open a door, buy a gun off the wall - the screen says what and the cost.")
    end
    g.state = "break"
    g.next_round = tick + 100
    sidebar(g)
    -- its labels once they're there: the map's chunks unloaded with nobody in it (what's put in one isn't kept) - and
    -- kept loaded by its players (a chunk unloaded saves its entities: back as others, without their phase)
    after(10, function()
      if g.state == "over" then return end
      map_chunks_loaded()
      labels(g)
    end)
    log(string.format("game %d: %s (phase %d) - %d game%s in the map", id, table.concat(g.order, ", "), g.phase,
                      count(games), count(games) == 1 and "" or "s"))
  end)
end

local function leave_game(name, quiet)
  local g = game_of[name]
  if not g then return end
  game_of[name] = nil
  local pl = g.pl[name]
  if pl and not pl.left and g.state ~= "making" and g.state ~= "over" then   -- (game over counted it already)
    local st = stats(name)
    st.games = st.games + 1
    if pl.downed then st.deaths = st.deaths + 1 end
    plugin.save()
    stats_dirty = false
  end
  if pl then pl.left = true end
  if not quiet then tell(g, "&7" .. name .. " left the game") end
  if #members(g) == 0 then
    if g.state == "making" then
      g.state = "over"
      games[g.id] = nil
    else
      finish(g, "empty")
    end
  end
end
-- --- going down, getting up
local PERK_ICONS = {juggernog = "shield:C81E1E", quick_revive = "cross:3CA0FF", double_tap = "bullets:E07818",
                    stamin_up = "bolt:E8C020"}
local function perk_icons(p, pl)   -- their perks on their HUD (bottom left)
  local list = {}
  for _, k in ipairs(pl.perk_order or {}) do if pl.perks[k] and PERK_ICONS[k] then list[#list + 1] = PERK_ICONS[k] end end
  pcall(p.hud_icons, p, #list > 0 and list or nil)
end

local function lose_perks(p, pl)
  for k in pairs(pl.perks) do
    if k == "juggernog" then pcall(p.remove_effect, p, "resistance") end
    if k == "stamin_up" then pcall(p.remove_effect, p, "speed") end
  end
  pl.perks, pl.perk_order = {}, {}
  perk_icons(p, pl)
end

local function go_down(g, p, pl)
  pl.downed, pl.down_at, pl.revive = true, tick, 0
  pl.downs = pl.downs + 1
  local st = stats(p.name)
  st.downs = st.downs + 1
  local had_qr = pl.perks.quick_revive
  lose_perks(p, pl)
  pcall(p.set_health, p, p:max_health())
  pcall(p.add_effect, p, "slowness", 9999, 5)
  pcall(p.add_effect, p, "resistance", 9999, 5)   -- (down: nothing hurts them - a zombie still swinging at them)
  local x, y, z = p:position()
  sound(g, "zombies.downed", x, y, z, 2)
  tell(g, "&c" .. p.name .. " is down! &7Stand by them to revive them", true)
  log(string.format("game %d: %s is down (round %d)", g.id, p.name, g.round))
  if g.solo and had_qr and pl.self_revives > 0 then
    pl.self_revives = pl.self_revives - 1
    pl.self_at = tick + 200
    pcall(p.notice, p, "&bQuick Revive: you'll get up in 10 seconds")
  else
    pcall(p.countdown, p, BLEED_TICKS // 20, "&cBleeding out: {s}", "&7a teammate can revive you")
  end
end

local function get_up(g, p, pl, by)
  pl.downed, pl.self_at = false, nil
  pcall(p.remove_effect, p, "slowness")
  pcall(p.remove_effect, p, "resistance")
  pcall(p.add_effect, p, "resistance", 2, 5)   -- (2 s to get clear of the ones that put them down)
  pcall(p.set_health, p, p:max_health())
  pl.last_hurt = tick
  pcall(p.countdown, p, 0)
  local x, y, z = p:position()
  sound(g, "zombies.revive", x, y, z, 1.5)
  tell(g, "&a" .. p.name .. " is back up" .. (by and (" &7(" .. by .. ")") or ""))
  log(string.format("game %d: %s is back up (%s)", g.id, p.name, by or "?"))
end

local function bleed_out(g, p, pl)
  pl.downed, pl.dead = false, true
  local st = stats(p.name)
  st.deaths = st.deaths + 1
  pcall(p.remove_effect, p, "slowness")
  pcall(p.remove_effect, p, "resistance")
  pcall(p.countdown, p, 0)
  clear_inventory(p)
  pl.pap, pl.bowie = {}, false
  pl.points = math.floor(pl.points * 0.9)
  p:set_gamemode("spectator")
  tell(g, "&4" .. p.name .. " bled out &7- back next round")
  log(string.format("game %d: %s bled out", g.id, p.name))
end


-- --- zombies: each comes at a window (in its closet, at the boards) and tears them off - its game's boards and shut doors
-- are walls for it (phase walls) - then walks in, after its game's players. One that's been stuck 15 s with nobody near
-- (or got out of the map) comes again from a window.
local function nearest_standing(g, x, z)
  local best, bd
  for _, m in ipairs(members(g)) do
    if standing(m.pl) then
      local px, _, pz = m.p:position()
      local d = dist2(x, z, px, pz)
      if not bd or d < bd then best, bd = m, d end
    end
  end
  return best, bd
end

local function pick_window(g)
  local list, total = {}, 0
  for i, w in ipairs(MAP.windows) do
    if g.zones[w.zone] then
      local m, d = nearest_standing(g, map.x + w.x, map.z + w.z)
      local weight = 1 / (1 + math.sqrt(d or 400) / 8)
      list[#list + 1] = {i, weight}
      total = total + weight
    end
  end
  local r = math.random() * total
  for _, e in ipairs(list) do
    r = r - e[2]
    if r <= 0 then return e[1] end
  end
  return list[#list] and list[#list][1]
end

local function window_yaw(w) return math.deg(math.atan(w.dx, -w.dz)) end   -- (facing in)

local function at_window(g, z, wi)   -- (a stuck zombie) to a window's outside, as if it came again
  local w = MAP.windows[wi]
  local _, out = MAP.window_spots(w)
  z.win, z.phase, z.tear = wi, "window", nil
  z.e:teleport(map.x + out[1], map.y + out[2], map.z + out[3], window_yaw(w), 0)
  z.moved = tick
end

local function spawn_zombie(g)
  local wi = pick_window(g)
  if not wi then return false end
  local w = MAP.windows[wi]
  local _, out = MAP.window_spots(w)
  local x, y, z = map.x + out[1], map.y + out[2], map.z + out[3]
  local e = in_phase(g, server.spawn_entity, "zombie", x, y, z, W, window_yaw(w))
  if not e then return false end
  local okb, baby = pcall(e.is_baby, e)   -- (spawning makes a baby now and then - fast and small: not here)
  if okb and baby then
    for _, c in ipairs(server.entities(x, y, z, W, 3, "chicken")) do c:remove() end   -- (a jockey's mount)
    e:remove()
    return false
  end
  pcall(e.merge_nbt, e, {IsBaby = 0, CanPickUpLoot = 0, CanBreakDoors = 0})
  for _, s in ipairs({"mainhand", "offhand", "head", "chest", "legs", "feet"}) do pcall(e.set_item, e, s, nil) end
  e:set_persistent(true)
  pcall(e.set_fireproof, e, true)
  e:set_max_health(g.zhp)
  pcall(e.set_speed, e, zombie_speed(g.round))
  pcall(e.set_attack_damage, e, ZOMBIE_DAMAGE)
  local uuid = e:uuid()
  ours[uuid] = true
  g.zombies[uuid] = {e = e, win = wi, phase = "window", lx = x, lz = z, moved = tick, born = tick}
  g.spawned = g.spawned + 1
  return true
end

local function set_boards(g, wi)   -- (its players shown them; a wall while there's a board)
  local w = MAP.windows[wi]
  local lb, ld, ub, ud = MAP.board_blocks(g.boards[wi])
  show_game(g, {{w.x, 1, w.z, lb, ld}, {w.x, 2, w.z, ub, ud}})
  walls(g, window_cells(w), g.boards[wi] > 0)
end

local function zombies_tick(g)
  for uuid, z in pairs(g.zombies) do
    local e = z.e
    if not e:valid() or e:health() <= 0 then
      g.zombies[uuid] = nil
      ours[uuid] = nil
      if not z.counted then g.spawned = g.spawned - 1 end   -- (gone without being killed: it comes again)
    else
      local x, _, zz = e:position()
      local rx, rz = x - map.x, zz - map.z
      if (x - z.lx) ^ 2 + (zz - z.lz) ^ 2 > 2 then z.lx, z.lz, z.moved = x, zz, tick end
      if z.phase == "window" then
        local w = MAP.windows[z.win]
        local inside, outside = MAP.window_spots(w)
        if rx > 0.3 and rx < 32.7 and rz > 0.3 and rz < 32.7 then
          z.phase = "in"
        elseif g.boards[z.win] > 0 then
          local ox, oz = map.x + outside[1], map.z + outside[3]
          if dist2(x, zz, ox, oz) > 1.6 then   -- (at the boards to tear them)
            if tick >= (z.walk or 0) then z.walk = tick + 20 pcall(e.walk_to, e, ox, map.y + 1, oz, 1.0) end
          elseif tick >= (z.tear or 0) then
            if z.tear then
              g.boards[z.win] = g.boards[z.win] - 1
              set_boards(g, z.win)
              sound(g, "zombies.board_break", map.x + w.x + 0.5, map.y + 1.5, map.z + w.z + 0.5, 1.2)
            end
            z.tear = tick + TEAR_TICKS
          end
          z.moved = tick
        else
          if tick - z.moved > 200 then   -- (not getting in: another window)
            at_window(g, z, pick_window(g) or z.win)
          elseif tick >= (z.walk or 0) then
            z.walk = tick + 15
            pcall(e.walk_to, e, map.x + inside[1], map.y + 1, map.z + inside[3], 1.0)
          end
        end
      else
        if tick >= (z.aim or 0) then
          z.aim = tick + 10
          local m = nearest_standing(g, x, zz)
          if m then pcall(e.set_target, e, m.p:entity()) else pcall(e.set_target, e, nil) end
        end
        -- stuck (15 s without getting anywhere, nobody near) or out of the map: back to a window
        local _, d = nearest_standing(g, x, zz)
        if (tick - z.moved > 300 and (not d or d > 9)) or rx < -6 or rx > 38 or rz < -6 or rz > 38 then
          local wi = pick_window(g)
          if wi then
            at_window(g, z, wi)
            g.respawned = (g.respawned or 0) + 1
          end
        end
      end
    end
  end
end

-- --- power-ups
local function drop_powerup(g, x, y, z)
  if g.powerups_round >= 4 or math.random() > 0.03 then return end
  g.powerups_round = g.powerups_round + 1
  local kind = POWERUP_KINDS[rnd(1, #POWERUP_KINDS)]
  local t = in_phase(g, server.spawn_text, x, y + 0.8, z, W, POWERUPS[kind], POWERUP_RANGE)
  if t then ours[t:uuid()] = true g.texts[#g.texts + 1] = t end
  g.powerups[#g.powerups + 1] = {kind = kind, x = x, y = y, z = z, text = t, gone = tick + 600}
  sound(g, "zombies.powerup_spawn", x, y, z, 1)
end

local function apply_powerup(g, kind, by)
  gsound(g, "zombies.powerup_grab", 4)
  tell(g, POWERUPS[kind] .. (by and (" &7(" .. by .. ")") or ""), true)
  log(string.format("game %d: %s%s", g.id, kind, by and (" (" .. by .. ")") or ""))
  if kind == "max_ammo" then
    for _, m in ipairs(members(g)) do if not m.pl.dead then fill_ammo(m.p, m.pl) end end
  elseif kind == "insta_kill" then
    g.insta_until = tick + 600
  elseif kind == "double_points" then
    g.double_until = tick + 600
  elseif kind == "nuke" then
    gsound(g, "zombies.nuke", 4)
    local n = 0
    for uuid, z in pairs(g.zombies) do
      if z.e:valid() then
        local x, y, zz = z.e:position()
        particles(g, "explosion", x, y + 1, zz, 1, 0, 0, 0, 0)
        z.e:remove()
      end
      ours[uuid] = nil
      if not z.counted then z.counted = true n = n + 1 end
      g.zombies[uuid] = nil
    end
    g.killed = g.killed + n
    for _, m in ipairs(members(g)) do add_points(g, m.pl, 400) end
  elseif kind == "carpenter" then
    for wi = 1, #MAP.windows do g.boards[wi] = MAP.BOARDS set_boards(g, wi) end
    for _, m in ipairs(members(g)) do add_points(g, m.pl, 200) end
  end
end

local function powerups_tick(g)
  for i = #g.powerups, 1, -1 do
    local pu = g.powerups[i]
    local taken
    for _, m in ipairs(members(g)) do
      if standing(m.pl) then
        local x, y, z = m.p:position()
        if dist2(x, z, pu.x, pu.z) < 2.6 and math.abs(y - pu.y) < 2.5 then taken = m.name break end
      end
    end
    if taken or tick >= pu.gone then
      if pu.text and pu.text:valid() then ours[pu.text:uuid()] = nil pu.text:remove() end
      table.remove(g.powerups, i)
      if taken then apply_powerup(g, pu.kind, taken) end
    elseif t5 % 2 == 0 then
      particles(g, "happy_villager", pu.x, pu.y + 0.5, pu.z, 4, 0.3, 0.4, 0.3, 0)
      if pu.gone - tick < 100 and pu.text and pu.text:valid() then
        pcall(pu.text.set_name, pu.text, t5 % 4 == 0 and POWERUPS[pu.kind] or "&7...", true)
      end
    end
  end
end

-- --- buying and the map's things (each game's own: shown to its players over the world's blocks)
local function open_door(g, p, pl, di)
  local d = MAP.doors[di]
  if not spend(g, p, pl, d.cost, "the door") then return end
  g.doors[di] = true
  g.zones[d.a], g.zones[d.b] = true, true
  local cells = {}
  for _, b in ipairs(MAP.door_blocks(d)) do cells[#cells + 1] = {b[1], b[2], b[3], nil, 0} end   -- (the world's: air)
  show_game(g, cells)
  walls(g, cells, false)
  for _, t in ipairs(g.door_text[di] or {}) do if t:valid() then ours[t:uuid()] = nil t:remove() end end
  sound(g, "zombies.door", map.x + (d.x1 + d.x2) / 2 + 0.5, map.y + 2, map.z + (d.z1 + d.z2) / 2 + 0.5, 2)
  tell(g, "&e" .. p.name .. " opened the way to the " .. MAP.zones[g.zones[d.a] and d.b or d.a].name)
end

local function repair(g, p, pl, wi)
  if g.boards[wi] >= MAP.BOARDS then return end
  local w = MAP.windows[wi]
  local cx, cz = map.x + w.x + 0.5, map.z + w.z + 0.5
  for _, z in pairs(g.zombies) do   -- (not on top of a zombie climbing through)
    if z.e:valid() then
      local x, _, zz = z.e:position()
      if dist2(x, zz, cx, cz) < 0.8 then return end
    end
  end
  g.boards[wi] = g.boards[wi] + 1
  set_boards(g, wi)
  sound(g, "zombies.repair", cx, map.y + 1.5, cz, 1)
  if (pl.repaired or 0) < 500 then
    pl.repaired = (pl.repaired or 0) + 10
    add_points(g, pl, 10)
  end
end

local function buy_wall(g, p, pl, b)
  if b.knife then
    if pl.bowie then return pcall(p.notice, p, "&7You have the Bowie Knife") end
    if not spend(g, p, pl, b.cost, b.name) then return end
    pl.bowie = true
    p:set_item(0, {name = "diamond_sword", label = "&fBowie Knife"})
    return pcall(p.notice, p, "&aBowie Knife")
  end
  local owned = owned_guns(p)
  if owned[b.gun] then
    local pap = pl.pap[b.gun]
    local cost = pap and 4500 or b.cost // 2
    if ammo_of(p, GUNS[b.gun][2]) >= reserve(b.gun, pap) then return pcall(p.notice, p, "&7Your ammo's full") end
    if not spend(g, p, pl, cost, "ammo") then return end
    top_up(p, GUNS[b.gun][2], reserve(b.gun, pap))
    return pcall(p.notice, p, "&aAmmo")
  end
  if not spend(g, p, pl, b.cost, b.name) then return end
  give_gun(p, pl, b.gun)
  pcall(p.notice, p, "&a" .. b.name)
end

local function buy_perk(g, p, pl, pk)
  if pl.perks[pk.perk] then return pcall(p.notice, p, "&7You have " .. pk.name) end
  if not g.power and not (pk.perk == "quick_revive" and g.solo) then return pcall(p.notice, p, "&cThe power's off") end
  if count(pl.perks) >= 4 then return pcall(p.notice, p, "&cYou can't drink any more") end
  local cost = (pk.solo and g.solo) and pk.solo or pk.cost
  if not spend(g, p, pl, cost, pk.name) then return end
  pl.perks[pk.perk] = true
  pl.perk_order = pl.perk_order or {}
  pl.perk_order[#pl.perk_order + 1] = pk.perk
  perk_icons(p, pl)
  if pk.perk == "juggernog" then pcall(p.add_effect, p, "resistance", 9999, 2) end
  if pk.perk == "stamin_up" then pcall(p.add_effect, p, "speed", 9999, 1) end
  local x, y, z = p:position()
  sound(g, "zombies.perk", x, y, z, 1)
  pcall(p.notice, p, "&b" .. pk.name)
end

local function pack_a_punch(g, p, pl)
  if not g.power then return pcall(p.notice, p, "&cThe power's off") end
  if pl.packing then return end
  local slot = p:held_slot()
  local it = p:item(slot)
  if not it or not GUNS[it.name] then return pcall(p.notice, p, "&7Hold the gun you want upgraded") end
  if pl.pap[it.name] then return pcall(p.notice, p, "&7That one's upgraded already") end
  if not spend(g, p, pl, MAP.pap.cost, "the Pack-a-Punch") then return end
  local key = it.name
  pl.packing = true
  p:set_item(slot, nil)
  sound(g, "zombies.pap", map.x + MAP.pap.x + 0.5, map.y + 2, map.z + MAP.pap.z + 0.5, 1.5)
  pcall(p.notice, p, "&dUpgrading the " .. GUNS[key][1] .. "...")
  after(64, function()
    pl.packing = false
    if game_of[p.name] ~= g or not p:online() then return end
    particles(g, "enchant", map.x + MAP.pap.x + 0.5, map.y + 2.5, map.z + MAP.pap.z + 0.5, 30, 0.4, 0.4, 0.4, 0.5)
    pl.pap[key] = true
    if not p:item(slot) then p:set_item(slot, gun_item(key, true)) else give_gun(p, pl, key, true) end
    top_up(p, GUNS[key][2], reserve(key, true))
    pcall(p.notice, p, "&d" .. GUNS[key][1] .. " &5Upgraded")
    log(string.format("game %d: %s's %s upgraded", g.id, p.name, GUNS[key][1]))
  end)
end

local function power_on(g, p)
  if g.power then return end
  g.power = true
  show_game(g, MAP.power_ops(true))
  if g.power_text and g.power_text:valid() then pcall(g.power_text.set_name, g.power_text, "&aPower On", true) end
  gsound(g, "zombies.power", 4)
  tell(g, "&e&lThe power is on! &7(" .. p.name .. ") - the perks and the Pack-a-Punch work now", true)
  log(string.format("game %d: the power's on (%s)", g.id, p.name))
end

local function use_box(g, p, pl)
  if g.box_busy then return end
  if g.box_moving then return pcall(p.notice, p, "&7The box is gone - find it") end
  local owned = owned_guns(p)
  if not spend(g, p, pl, 950, "the box") then return end
  g.box_busy = true
  g.box_uses = g.box_uses + 1
  local b = MAP.boxes[g.box]
  local bx, by, bz = map.x + (b.x + b.x2) / 2 + 0.5, map.y + 1.5, map.z + b.z + 0.5
  sound(g, "zombies.box", bx, by, bz, 1.5)
  local bear = g.box_uses > 3 and #MAP.boxes > 1 and math.random(6) == 1
  local pool = {}
  for _, k in ipairs(BOX_POOL) do if not owned[k] then pool[#pool + 1] = k end end
  local pick = pool[rnd(1, #pool)]
  local spins = 0
  box_label(g)
  g.box_text = label(g, (b.x + b.x2) / 2 + 0.5, 2.3, b.z + 0.5, "&f...")
  local function spin()
    spins = spins + 1
    if not g.box_text or not g.box_text:valid() or g.state == "over" then box_label(g) g.box_busy = false return end
    if spins < 14 then
      pcall(g.box_text.set_name, g.box_text, "&f" .. GUNS[BOX_POOL[rnd(1, #BOX_POOL)]][1], true)
      return after(4 + spins // 3, spin)
    end
    if bear then
      pcall(g.box_text.set_name, g.box_text, "&c&lBye bye!", true)
      sound(g, "zombies.box_bear", bx, by, bz, 3)
      pl.points = pl.points + 950
      g.box_moving = true
      tell(g, "&dThe mystery box is moving...", true)
      log(string.format("game %d: the box moves (after %d uses)", g.id, g.box_uses))
      after(80, function()
        box_label(g)
        if g.state == "over" then return end
        place_box(g, g.box, false)
        local old = g.box
        repeat g.box = rnd(1, #MAP.boxes) until g.box ~= old
        g.box_moving = false
        place_box(g, g.box, true)
        box_label(g)
        g.box_busy, g.box_uses = false, 0
        tell(g, "&dThe box is in the " .. MAP.zones[MAP.boxes[g.box].zone].name .. " now")
      end)
      return
    end
    pcall(g.box_text.set_name, g.box_text, "&a" .. GUNS[pick][1], true)
    log(string.format("game %d: the box gave %s a %s", g.id, p.name, GUNS[pick][1]))
    if game_of[p.name] == g and standing(pl) then
      give_gun(p, pl, pick)
      pcall(p.notice, p, "&a" .. GUNS[pick][1])
    end
    after(60, function()
      box_label(g)
      g.box_busy = false
    end)
  end
  after(4, spin)
end

-- --- prompts (COD's): what a player looks at within LOOK blocks, and what it does - under their crosshair
local function prompt_at(g, p, pl, cx, cy, cz, px, pz)   -- (map-relative cells) -> text, or nil and whether it stops there
  if cy < 1 or cy > 4 then return nil, true end   -- (the floor, the ceiling)
  local di, d = MAP.door_at(cx, cz)
  if di and cy <= 3 then
    if g.doors[di] then return nil, false end
    return (d.style == "door" and "Press L2 to open the door" or "Press L2 to clear the debris") .. " [Cost: " .. d.cost .. "]"
  end
  for wi, w in ipairs(MAP.windows) do
    if cx == w.x and cz == w.z and cy <= 2 then
      local inside = px > 0.3 and px < 32.7 and pz > 0.3 and pz < 32.7
      if inside and g.boards[wi] < MAP.BOARDS then return "Hold L2 to rebuild the barrier" end
      return nil, g.boards[wi] > 0
    end
  end
  for _, b in ipairs(MAP.wallbuys) do
    local on_wall = b.nx ~= 0 and cx == b.x and math.abs(cz - b.z) <= 1 or b.nz ~= 0 and cz == b.z and math.abs(cx - b.x) <= 1
    if on_wall and cy <= 3 then
      if (px - b.x - 0.5) * b.nx + (pz - b.z - 0.5) * b.nz <= 0 then return nil, true end   -- (its back)
      if b.knife then
        if pl.bowie then return nil, true end
        return "Press L2 for the Bowie Knife [Cost: " .. b.cost .. "]"
      end
      local name = GUNS[b.gun][1]
      if owned_guns(p)[b.gun] then
        return "Press L2 for " .. name .. " ammo [Cost: " .. (pl.pap[b.gun] and 4500 or b.cost // 2) .. "]"
      end
      return "Press L2 to buy " .. name .. " [Cost: " .. b.cost .. "]"
    end
  end
  for _, pk in ipairs(MAP.perks) do
    if cx == pk.x and cz == pk.z and cy <= 3 then
      if pl.perks[pk.perk] then return nil, true end
      if not g.power and not (pk.perk == "quick_revive" and g.solo) then return "You must turn on the power first!" end
      return "Press L2 to buy " .. pk.name .. " [Cost: " .. ((pk.solo and g.solo) and pk.solo or pk.cost) .. "]"
    end
  end
  if math.abs(cx - MAP.pap.x) <= 1 and cz == MAP.pap.z and cy <= 2 then
    if not g.power then return "You must turn on the power first!" end
    local it = p:item(p:held_slot())
    if not it or not GUNS[it.name] then return "Hold a gun to Pack-a-Punch it [Cost: " .. MAP.pap.cost .. "]" end
    if pl.pap[it.name] then return nil, true end
    return "Press L2 to Pack-a-Punch the " .. GUNS[it.name][1] .. " [Cost: " .. MAP.pap.cost .. "]"
  end
  if math.abs(cx - MAP.power.x) <= 1 and cz >= 31 and cz <= 32 and cy <= 3 then
    if g.power then return nil, true end
    return "Press L2 to turn on the power"
  end
  local b = MAP.boxes[g.box]
  if not g.box_moving and (cx == b.x or cx == b.x2) and cz == b.z and cy == 1 then
    if g.box_busy then return nil, true end
    return "Press L2 for a random weapon [Cost: 950]"
  end
  local wall = cx == 0 or cx == 16 or cx == 32 or cz == 0 or cz == 16 or cz == 32
  return nil, wall and cx >= 0 and cx <= 32 and cz >= 0 and cz <= 32
end

local function look_prompt(g, p, pl)
  local x, y, z, _, yaw, pitch = p:position()
  if not yaw then return nil end
  local ry, rp = math.rad(yaw), math.rad(pitch or 0)
  local dx, dy, dz = -math.sin(ry) * math.cos(rp), -math.sin(rp), math.cos(ry) * math.cos(rp)
  local ex, ey, ez = x - map.x, y + 1.62 - map.y, z - map.z
  local last
  for t = 0.2, LOOK, 0.15 do
    local cx, cy, cz = math.floor(ex + dx * t), math.floor(ey + dy * t), math.floor(ez + dz * t)
    local key = cx * 4096 + cy * 64 + cz
    if key ~= last then
      last = key
      local text, stop = prompt_at(g, p, pl, cx, cy, cz, ex, ez)
      if text then return text end
      if stop then return nil end
    end
  end
end

local function game_click(g, p, x, y, z)
  local pl = g.pl[p.name]
  if not standing(pl) or g.state == "making" or g.state == "over" then return end
  if tick < (pl.cd or 0) then return end
  pl.cd = tick + 6
  local rx, ry, rz = x - map.x, y - map.y, z - map.z
  local di = MAP.door_at(rx, rz)
  if di and ry >= 1 and ry <= 3 and not g.doors[di] then return open_door(g, p, pl, di) end
  for wi, w in ipairs(MAP.windows) do
    local along = w.dx ~= 0 and math.abs(rz - w.z) or math.abs(rx - w.x)
    local across = w.dx ~= 0 and (rx == w.x) or (rz == w.z)
    if across and along <= 1 and ry >= 1 and ry <= 3 then return repair(g, p, pl, wi) end
  end
  for _, b in ipairs(MAP.wallbuys) do
    local on_wall = b.nx ~= 0 and rx == b.x and math.abs(rz - b.z) <= 1 or b.nz ~= 0 and rz == b.z and math.abs(rx - b.x) <= 1
    if on_wall and ry >= 1 and ry <= 3 then return buy_wall(g, p, pl, b) end
  end
  for _, pk in ipairs(MAP.perks) do
    if rx == pk.x and rz == pk.z and ry >= 1 and ry <= 3 then return buy_perk(g, p, pl, pk) end
  end
  if math.abs(rx - MAP.pap.x) <= 1 and rz == MAP.pap.z and ry >= 1 and ry <= 2 then return pack_a_punch(g, p, pl) end
  if math.abs(rx - MAP.power.x) <= 1 and rz >= 31 and rz <= 32 and ry >= 1 and ry <= 3 then return power_on(g, p) end
  local b = MAP.boxes[g.box]
  if not g.box_moving and (rx == b.x or rx == b.x2) and rz == b.z and ry == 1 then return use_box(g, p, pl) end
end
-- --- parties and the lobby's blocks
local function party_list(name)
  local leader = party_of[name]
  return leader and parties[leader] or {name}
end

local function leave_party(name)
  local leader = party_of[name]
  if not leader then return end
  local list = parties[leader]
  for i, n in ipairs(list) do if n == name then table.remove(list, i) break end end
  party_of[name] = nil
  if #list <= 1 then
    for _, n in ipairs(list) do party_of[n] = nil end
    parties[leader] = nil
  elseif leader == name then
    local new = list[1]
    parties[new], parties[leader] = list, nil
    for _, n in ipairs(list) do party_of[n] = new end
  end
  for _, n in ipairs(list) do local q = player(n) if q then q:message("&7" .. name .. " left the party") lobby_sidebar(q) end end
end

local function invite(p, name)
  local q = player(name or "")
  if game_of[p.name] then return p:message("&cNot while you're playing") end
  if not q or q.name == p.name then return p:message("&cNobody called " .. tostring(name) .. " is on") end
  if game_of[q.name] then return p:message("&c" .. q.name .. " is in a game") end
  if party_of[q.name] then return p:message("&c" .. q.name .. " is in a party already") end
  local leader = party_of[p.name] or p.name
  local list = parties[leader] or {p.name}
  if #list >= setting("party-size") then return p:message("&cYour party's full") end
  invites[q.name] = {from = leader, at = tick}
  p:message("&aInvited " .. q.name)
  q:message("&a" .. p.name .. " invites you to their party &7- /z accept")
  pcall(q.menu, q, {title = p.name .. "'s party", rows = {{key = "accept", label = "Join " .. p.name .. "'s party"},
                                                          {key = "no", label = "No thanks"}},
                    pick = function(who, key) if key == "accept" then who:run("z accept") end end})
end

local function accept(p)
  local inv = invites[p.name]
  invites[p.name] = nil
  if not inv or tick - inv.at > 20 * 120 then return p:message("&cNo invite (they last 2 minutes)") end
  local leader = player(inv.from)
  if not leader or game_of[inv.from] then return p:message("&cThat party's gone or playing") end
  leave_party(p.name)
  local list = parties[inv.from]
  if not list then list = {inv.from} parties[inv.from] = list party_of[inv.from] = inv.from end
  if #list >= setting("party-size") then return p:message("&cThat party's full") end
  list[#list + 1] = p.name
  party_of[p.name] = inv.from
  for _, n in ipairs(list) do local q = player(n) if q then q:message("&a" .. p.name .. " joined the party") lobby_sidebar(q) end end
end

local function play(p)
  if game_of[p.name] then return end
  local leader = party_of[p.name]
  if leader and leader ~= p.name then return pcall(p.notice, p, "&7Only the party's leader (" .. leader .. ") can start") end
  local names = {}
  for _, n in ipairs(party_list(p.name)) do if player(n) and not game_of[n] then names[#names + 1] = n end end
  start_game(names)
end

local function top(p)
  local list = {}
  for name, s in pairs(plugin.data.stats) do
    if (s.best or 0) > 0 then list[#list + 1] = {name, s.best, s.kills or 0, s.deaths or 0} end
  end
  table.sort(list, function(a, b) return a[2] > b[2] or (a[2] == b[2] and a[3] > b[3]) end)
  p:message("&b&lBest rounds")
  for i = 1, math.min(8, #list) do
    p:message(string.format("&7%d. &f%s &7- round &e%d &7(%d kills, %d deaths)", i, list[i][1], list[i][2], list[i][3], list[i][4]))
  end
  if #list == 0 then p:message("&7Nobody yet - be the first") end
end

local function show_stats(p, name)   -- /z stats [player]
  local s = plugin.data.stats[name]
  if not s then return p:message("&7No games yet for " .. name) end
  p:message("&b&l" .. name .. "'s stats")
  p:message(string.format("&7Highest round &e%d&7, games &f%d", s.best or 0, s.games or 0))
  p:message(string.format("&7Kills &f%d &7(headshots %d), deaths &f%d&7, downs &f%d&7, revives &f%d", s.kills or 0,
                          s.headshots or 0, s.deaths or 0, s.downs or 0, s.revives or 0))
end

local function party_menu(p)
  local rows = {}
  local leader = party_of[p.name]
  local lobby_players = {}
  for _, q in ipairs(players()) do if q.name ~= p.name and not game_of[q.name] and not party_of[q.name] then lobby_players[#lobby_players + 1] = q.name end end
  if leader then
    rows[#rows + 1] = {key = "x", label = "Party: " .. table.concat(parties[leader], ", "), enabled = false}
    rows[#rows + 1] = {key = "leave", label = "Leave the party"}
  end
  for i = 1, math.min(10, #lobby_players) do rows[#rows + 1] = {key = "inv:" .. lobby_players[i], label = "Invite " .. lobby_players[i]} end
  if #lobby_players == 0 then rows[#rows + 1] = {key = "x", label = "Nobody else in the lobby to invite", enabled = false} end
  local shown = pcall(p.menu, p, {title = "Party", rows = rows, pick = function(who, key)
    if key == "leave" then leave_party(who.name) lobby_sidebar(who)
    elseif key:sub(1, 4) == "inv:" then invite(who, key:sub(5)) end
  end})
  if not shown then p:message("&7/z invite <player>, /z accept, /z leave") end
end

local function lobby_click(p, x, y, z)
  if not lobby then return end
  local rx, ry, rz = x - lobby.x, y - lobby.y, z - lobby.z
  local function at(c) return rx == c[1] and ry == c[2] and rz == c[3] end
  if tick < (lobby_cd[p.name] or 0) then return end
  lobby_cd[p.name] = tick + 10
  if at(LOBBY.play) then play(p) elseif at(LOBBY.party) then party_menu(p) elseif at(LOBBY.top) then top(p) end
end


-- --- events
local function pressed(p, x, y, z)   -- a block clicked or hit: the lobby's blocks, a game's doors, windows, guns, box...
  local g = game_of[p.name]
  if g then
    game_click(g, p, x, y, z)
    -- (the server sends them the world's blocks there once it's said no: their game's shown again after)
    if map then after(1, function() if game_of[p.name] == g and p:online() then show_near(g, p, x, y, z) end end) end
  else
    lobby_click(p, x, y, z)
  end
end

local function builder(p) return p:gamemode() == "creative" and p:is_op() and not game_of[p.name] end   -- (operators)

on("build", function(p, x, y, z, dim, kind)
  if builder(p) then return true end
  if kind == "click" or kind == "break" then pressed(p, x, y, z) end
  return false
end)
on("hit", function(p, x, y, z)   -- (new_block 3.65) the first hit - mining's slow: a gold block takes 15 s by hand
  if builder(p) then return true end
  pressed(p, x, y, z)
  return false
end)
on("use", function(p) return p:gamemode() == "creative" and p:is_op() and not game_of[p.name] end)
on("pvp", function() return false end)
on("spawn", function() return false end)

on("shot", function(p, e, damage, head, gun)
  local g = game_of[p.name]
  if not g then return false end
  if e:is_player() then return false end
  local z = g.zombies[e:uuid()]
  if not z then return end
  local pl = g.pl[p.name]
  if not pl or pl.dead then return false end
  z.head = head
  if not z.counted then add_points(g, pl, 10) end
  if tick < (g.insta_until or 0) then return 100000 end
  local mult = (pl.pap[gun] and 2.5 or 1) * (pl.perks.double_tap and 1.33 or 1) * (head and 1.4 or 1)
  return damage * mult
end)

on("attack", function(p, e)
  local g = game_of[p.name]
  if not g then return false end
  if e:is_player() then return false end
  local z = g.zombies[e:uuid()]
  local pl = g.pl[p.name]
  if not z or not standing(pl) then return false end
  z.head = false
  add_points(g, pl, 10)
  hits[#hits + 1] = {e = e, p = p, dmg = tick < (g.insta_until or 0) and 100000 or (pl.bowie and BOWIE or KNIFE)}
  return false
end)

on("interact", function(p, e)
  if e:type() ~= "item_frame" then return end
  local b = frame_wall(e)
  if not b then return builder(p) end
  local g = game_of[p.name]
  local pl = g and g.pl[p.name]
  if pl and standing(pl) and g.state ~= "making" and g.state ~= "over" and tick >= (pl.cd or 0) then
    pl.cd = tick + 6
    buy_wall(g, p, pl, b)
  end
  return false
end)

on("kill", function(p, e, cause)
  local g = game_of[p.name]
  if not g then return end
  local z = g.zombies[e:uuid()]
  if not z or z.counted then return end
  z.counted = true
  g.killed = g.killed + 1
  local pl = g.pl[p.name]
  if pl then
    pl.kills = pl.kills + 1
    local st = stats(p.name)
    st.kills = st.kills + 1
    if cause == "attack" then add_points(g, pl, 120)
    elseif z.head then pl.headshots = pl.headshots + 1 st.headshots = st.headshots + 1 add_points(g, pl, 90)
    else add_points(g, pl, 50) end
  end
  local x, y, zz = e:position()
  drop_powerup(g, x, y, zz)
end)

on("hurt", function(victim, amount, attacker)
  local g = game_of[victim.name]
  if not g then return end
  local pl = g.pl[victim.name]
  if not standing(pl) then return end
  pl.last_hurt = tick
  if victim:health() <= (pl.perks.juggernog and DOWN_AT_JUGG or DOWN_AT) then go_down(g, victim, pl) end
end)

on("death", function(p)   -- (not from a zombie: something else) - out till the next round
  local g = game_of[p.name]
  if not g then return end
  local pl = g.pl[p.name]
  if pl and not pl.dead then
    pl.downed, pl.dead = false, true
    local st = stats(p.name)
    st.deaths = st.deaths + 1
    tell(g, "&4" .. p.name .. " died &7- back next round")
  end
end)

on("chat", function(p, text)
  local g = game_of[p.name]
  if g then
    for _, m in ipairs(members(g)) do m.p:message("&a[Game] &f" .. p.name .. "&7: &f" .. text) end
  else
    for _, q in ipairs(players()) do if not game_of[q.name] then q:message("&7[Lobby] &f" .. p.name .. "&7: &f" .. text) end end
  end
  log("chat " .. (g and ("game " .. g.id) or "lobby") .. " <" .. p.name .. "> " .. text)
  return false
end)

on("join", function(p)
  after(10, function()
    if p:online() and not game_of[p.name] then
      to_lobby(p)
      p:message("&c&lCOD ZOMBIES &7- hit the &6gold block &7to play, the &9blue one &7to make a party (/z)")
    end
  end)
end)

on("quit", function(name)
  leave_game(name, false)
  leave_party(name)
  invites[name] = nil
end)

-- --- commands
command("z", {usage = "[play | invite <player> | accept | leave | quit | top | stats [player]]", description = "COD Zombies"}, function(p, args)
  if p.console then
    if args[1] == "games" then
      for i, g in pairs(games) do
        log(string.format("game %d: %s, round %d, %s, %d zombies (%d of %d killed), box at %d%s, %d stuck zombies back at a window",
                          i, table.concat(g.order, ", "), g.round, g.state, count(g.zombies), g.killed, g.to_spawn, g.box,
                          g.box_moving and " (moving)" or "", g.respawned or 0))
      end
      if not next(games) then log("no games") end
      return
    elseif args[1] == "end" and games[tonumber(args[2] or "") or -1] then
      return finish(games[tonumber(args[2])], "ended")
    elseif args[1] == "start" and args[2] then   -- z start <player> [player...]: a game for them (from the lobby)
      local names = {}
      for k = 2, #args do names[#names + 1] = args[k] end
      return start_game(names)
    elseif args[1] == "points" and game_of[args[2] or ""] then   -- (tests) z points <player> <n>
      local g = game_of[args[2]]
      g.pl[args[2]].points = tonumber(args[3] or "0") or 0
      return log(args[2] .. " has " .. g.pl[args[2]].points .. " points")
    elseif args[1] == "powerup" and game_of[args[2] or ""] and POWERUPS[args[3] or ""] then   -- z powerup <player> <kind>
      return apply_powerup(game_of[args[2]], args[3], "console")
    elseif args[1] == "skip" and game_of[args[2] or ""] then   -- z skip <player>: their round's zombies all gone (the next round)
      local g = game_of[args[2]]
      remove_zombies(g)
      g.killed = g.to_spawn
      return log("game " .. g.id .. ": round " .. g.round .. " skipped")
    elseif args[1] == "god" and player(args[2] or "") then   -- (tests) z god <player>: nothing hurts them for 10 minutes
      return pcall(player(args[2]).add_effect, player(args[2]), "resistance", 600, 5)
    elseif args[1] == "round" and game_of[args[2] or ""] then   -- (tests) z round <player> <n>: the next round's that
      local g = game_of[args[2]]
      g.round = (tonumber(args[3] or "1") or 1) - 1
      return log("game " .. g.id .. ": next round " .. (g.round + 1))
    elseif args[1] == "power" and game_of[args[2] or ""] then   -- (tests) z power <player>: their game's power on
      return power_on(game_of[args[2]], player(args[2]))
    elseif args[1] == "door" and game_of[args[2] or ""] and MAP.doors[tonumber(args[3] or "") or 0] then   -- z door <player> <n>
      local g, di = game_of[args[2]], tonumber(args[3])
      local pl = g.pl[args[2]]
      pl.points = pl.points + MAP.doors[di].cost
      return open_door(g, player(args[2]), pl, di)
    elseif args[1] == "killall" and game_of[args[2] or ""] and player(args[2]) then   -- (tests) z killall <player>: their
      local g, q = game_of[args[2]], player(args[2])                                  -- game's zombies, killed by them
      local n = 0
      for _, z in pairs(g.zombies) do
        if z.e:valid() then pcall(z.e.damage, z.e, 100000, q:entity()) n = n + 1 end
      end
      return log(string.format("game %d: %d zombies hit by %s - %d of %d killed, %s has %d points", g.id, n, q.name, g.killed,
                               g.to_spawn, q.name, g.pl[q.name].points))
    elseif args[1] == "box" and game_of[args[2] or ""] and MAP.boxes[tonumber(args[3] or "") or 0] then   -- (tests) z box
      local g = game_of[args[2]]   -- <player> <n>: their game's box to place n
      place_box(g, g.box, false)
      g.box, g.box_moving = tonumber(args[3]), false
      place_box(g, g.box, true)
      box_label(g)
      return log("game " .. g.id .. ": the box is at place " .. g.box .. " (" .. MAP.zones[MAP.boxes[g.box].zone].name .. ")")
    elseif args[1] == "tp" and player(args[2] or "") and map and tonumber(args[3] or "") and tonumber(args[4] or "") then
      local q = player(args[2])   -- (tests) z tp <player> <x> <z>: to that place in the map (its corner's 0 0)
      q:teleport(map.x + tonumber(args[3]), map.y + 1, map.z + tonumber(args[4]))
      local g = game_of[q.name]
      if g then show(q, fake_list(g)) end
      return
    elseif args[1] == "face" and player(args[2] or "") then   -- (tests) z face <player> <yaw> [pitch]: turned that way
      local q = player(args[2])
      local x, y, z = q:position()
      return q:teleport(x, y, z, tonumber(args[3] or "0") or 0, tonumber(args[4] or "0") or 0)
    elseif args[1] == "see" and player(args[2] or "") then   -- (tests) z see <player>: what's near them, and its phase
      local q = player(args[2])
      local x, y, z = q:position()
      log(string.format("%s: phase %s at %.1f %.1f %.1f", q.name, tostring(select(2, pcall(q.phase, q))), x, y, z))
      for _, e in ipairs(server.entities(x, y, z, W, 40)) do
        local ex, ey, ez = e:position()
        local okt, t = pcall(e.target, e)
        log(string.format("  %s %d phase %s at %.1f %.1f %.1f%s", e:type(), e:id(), tostring(select(2, pcall(e.phase, e))),
                          ex, ey, ez, okt and t and (" -> " .. t:type() .. " " .. t:id()) or ""))
      end
      log(string.format("  (game blocks shown: %d, not: %d)", shown, show_failed))
      return
    end
    return log("z games | z start <player...> | z end <game> | z points <player> <n> | z round <player> <n> | z god <player> | z powerup <player> <kind> | z skip <player> | z power <player> | z door <player> <n> | z box <player> <n> | z killall <player> | z see <player> | z face <player> <yaw> [pitch] | z tp <player> <x> <z>")
  end
  local a = args[1]
  if a == "play" then play(p)
  elseif a == "invite" then invite(p, args[2])
  elseif a == "accept" then accept(p)
  elseif a == "leave" then leave_party(p.name) lobby_sidebar(p)
  elseif a == "quit" then
    if game_of[p.name] then leave_game(p.name) to_lobby(p) end
  elseif a == "top" then top(p)
  elseif a == "stats" then
    local q = args[2] and player(args[2])
    show_stats(p, q and q.name or args[2] or p.name)
  else
    local shown = not game_of[p.name] and pcall(p.menu, p, {title = "COD Zombies", rows = {
      {key = "play", label = party_of[p.name] and "Play (your party)" or "Play"}, {key = "party", label = "Party"},
      {key = "top", label = "Best rounds"}}, pick = function(who, key)
        if key == "play" then play(who) elseif key == "party" then party_menu(who) else top(who) end
      end})
    if not shown then p:message("&7/z play | invite <player> | accept | leave | quit | top | stats [player]") end
  end
end)

-- --- the ticks
local lobby_prompting = {}
every(5, function()
  t5 = t5 + 1
  for _, p in ipairs(players()) do   -- (the lobby's prompts)
    if not game_of[p.name] then
      local ok, prompt = pcall(lobby_prompt, p)
      prompt = ok and prompt or nil
      if prompt then pcall(p.prompt, p, prompt) lobby_prompting[p.name] = true
      elseif lobby_prompting[p.name] then pcall(p.prompt, p, nil) lobby_prompting[p.name] = nil end
    elseif lobby_prompting[p.name] then
      lobby_prompting[p.name] = nil
    end
  end
  for _, h in ipairs(hits) do
    if h.e:valid() and h.p:online() then pcall(h.e.damage, h.e, h.dmg, h.p:entity()) end
  end
  hits = {}
  for _, g in pairs(games) do
    if g.state == "round" or g.state == "break" then
      -- spawning
      if g.state == "round" then
        local n = #members(g)
        local alive = count(g.zombies)
        local cap = math.min(60, setting("max-zombies") + 6 * (n - 1))
        if g.spawned < g.to_spawn and alive < cap and tick >= g.next_spawn then
          if spawn_zombie(g) then g.next_spawn = tick + math.max(6, 40 - g.round * 2) end
        end
        if g.killed >= g.to_spawn then end_round(g) end
      elseif tick >= g.next_round then
        start_round(g)
      end
      zombies_tick(g)
      powerups_tick(g)
      -- the players: their phase and their game's blocks, regenerating, going down, bleeding out, revives
      local up = 0
      for _, m in ipairs(members(g)) do
        local pl, p = m.pl, m.p
        local okp, ph = pcall(p.phase, p)
        if okp and ph ~= g.phase then pcall(p.set_phase, p, g.phase) end   -- (a respawned player's a new one)
        local okt, prompt = pcall(look_prompt, g, p, pl)
        prompt = okt and standing(pl) and prompt or nil
        if prompt then pcall(p.prompt, p, prompt) pl.prompting = true
        elseif pl.prompting then pcall(p.prompt, p, nil) pl.prompting = false end
        if (pl.shows and pl.shows[1] and tick >= pl.shows[1]) or tick >= (pl.show_next or 0) then
          if pl.shows and pl.shows[1] and tick >= pl.shows[1] then table.remove(pl.shows, 1) end
          pl.show_next = tick + SHOW_AGAIN
          show(p, fake_list(g))
        end
        if standing(pl) then
          up = up + 1
          if tick - pl.last_hurt > 60 and p:health() < p:max_health() then
            pcall(p.set_health, p, math.min(p:max_health(), p:health() + 2))
          end
        elseif pl.downed then
          if pl.self_at then
            up = up + 1
            if tick >= pl.self_at then get_up(g, p, pl, "Quick Revive") end
          elseif tick - pl.down_at >= BLEED_TICKS then
            bleed_out(g, p, pl)
          else
            local px, py, pz = p:position()
            local helper
            for _, o in ipairs(members(g)) do
              if o.name ~= m.name and standing(o.pl) then
                local x, y, z = o.p:position()
                if dist2(x, z, px, pz) < 4.5 and math.abs(y - py) < 2 then helper = o break end
              end
            end
            if helper then
              pl.revive = pl.revive + (helper.pl.perks.quick_revive and 10 or 5)
              local pct = math.min(100, math.floor(pl.revive * 100 / REVIVE_TICKS))
              pcall(helper.p.notice, helper.p, "&aReviving " .. m.name .. " &f" .. pct .. "%")
              if pl.revive >= REVIVE_TICKS then
                helper.pl.revives = helper.pl.revives + 1
                local st = stats(helper.name)
                st.revives = st.revives + 1
                get_up(g, p, pl, helper.name)
              end
            else
              pl.revive = 0
            end
          end
        elseif pl.dead then
          -- spectating: kept round the map (one who really died comes back from the lobby as a spectator)
          if p:gamemode() ~= "spectator" then p:set_gamemode("spectator") end
          local x, _, z = p:position()
          if x < map.x - 20 or x > map.x + 52 or z < map.z - 20 or z > map.z + 52 then
            p:teleport(map.x + 16, map.y + 8, map.z + 16)
            arrived(pl)
          end
        end
      end
      if up == 0 and #members(g) > 0 then finish(g, "down") end
    end
    if t5 % 2 == 0 and g.state ~= "over" and g.state ~= "making" then
      sidebar(g)
      if g.state ~= "over" and not g.box_moving then
        local b = MAP.boxes[g.box]
        particles(g, "end_rod", map.x + (b.x + b.x2) / 2 + 0.5, map.y + 2, map.z + b.z + 0.5, 2, 0.3, 0.8, 0.3, 0.02)
      end
    end
  end
end)

every(20, function()   -- the map: no items or XP (drops), nothing that isn't a game's (from before a restart)
  if not map then return end
  for _, kind in ipairs({"item", "experience_orb"}) do
    for _, e in ipairs(server.entities(map.x + 16, map.y + 3, map.z + 16, W, 40, kind)) do e:remove() end
  end
  if tick % 100 < 20 then
    for _, e in ipairs(server.entities(map.x + 16, map.y + 3, map.z + 16, W, 40)) do
      if not e:is_player() and not ours[e:uuid()] then e:remove() end
    end
    for _, e in ipairs(server.entities(map.x + 16, map.y + 3, map.z + 16, W, 40, "area_effect_cloud")) do
      if not ours[e:uuid()] then e:remove() end
    end
  end
end)

every(20 * 30, function()   -- nobody starves; always night (set only when it isn't: the game tells everyone); stats saved
  if stats_dirty then
    stats_dirty = false
    plugin.save()
  end
  if map and next(games) then wall_frames() end   -- (a frame knocked off: put back - while games keep the map loaded)
  for _, p in ipairs(players()) do pcall(p.feed, p) end
  if math.abs((server.time() or 18000) % 24000 - 18000) > 600 then pcall(server.set_time, 18000) end
end)

every(40, function()   -- the lobby's sidebars
  for _, p in ipairs(players()) do if not game_of[p.name] then lobby_sidebar(p) end end
  for name, inv in pairs(invites) do if tick - inv.at > 20 * 120 then invites[name] = nil end end
end)

on("enable", function()
  if server.no_spawns then pcall(server.no_spawns, W, true) end
  if math.abs((server.time() or 0) % 24000 - 18000) > 600 then pcall(server.set_time, 18000) end
  local ok, err = pcall(server.in_phase, 1, function() end)
  if not ok then log("PHASES DON'T WORK HERE (" .. tostring(err) .. ") - games would see each other: new_block 3.65 on the Linux server") end
  ensure_lobby()
  ensure_map()
  for _, p in ipairs(players()) do to_lobby(p) end
end)

on("disable", function()
  for _, g in pairs(games) do
    remove_zombies(g)
    remove_texts(g)
    pcall(server.phase_walls_clear, g.phase)
    for _, m in ipairs(members(g)) do to_lobby(m.p) end
  end
  plugin.save()
end)
