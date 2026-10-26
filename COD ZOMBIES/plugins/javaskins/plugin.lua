-- javaskins: a Java Edition player's skin and cape on you, by their name - /skin <name> looks the name up at Mojang
-- (its public API: the name's id, the id's textures, the skin's and cape's PNGs) and puts them on you for everyone
-- to see; /skin off puts your own back. Kept per player and put on again each time you join. Staff: /skin <player>
-- <name|off>. The server's new_block must be 3.20 or later (p:set_skin); a hosting PS4 can't fetch (no web requests).
plugin.info{version = "1.0", author = "new_block", description = "Java Edition skins and capes by name (/skin)"}

plugin.setting("capes", {label = "Capes too", type = "bool", default = true, note = "A Java player's cape comes with their skin"})
plugin.permission("javaskins.others")

local on_linux = server.hosted_on() == "linux"
plugin.data.names = plugin.data.names or {}   -- player name (lower case) -> their Java name
local names = plugin.data.names
local cache = {}     -- Java name (lower case) -> {skin = png, cape = png or nil, at = seconds}
local busy = {}      -- player -> true while a look-up runs
local CACHE_SECONDS = 600

local B64 = {}
for i, c in ipairs({("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"):byte(1, 64)}) do B64[c] = i - 1 end
local function base64(s)
  local out, bits, n = {}, 0, 0
  for i = 1, #s do
    local v = B64[s:byte(i)]
    if v then
      bits, n = bits * 64 + v, n + 6
      if n >= 8 then
        n = n - 8
        out[#out + 1] = string.char(bits // (1 << n) % 256)
        bits = bits % (1 << n)
      end
    end
  end
  return table.concat(out)
end

local function key(name) return name:lower() end

local function apply(p, got)
  local ok, why = p:set_skin(got.skin, setting("capes") and got.cape or nil)
  if not ok then p:message("&cThe skin couldn't be put on: " .. tostring(why)) end
  return ok
end

-- Mojang: the name -> id -> textures (base64 JSON) -> the skin's PNG (and the cape's)
local function fetch(java, done)
  local k = key(java)
  local c = cache[k]
  if c and server.now() - c.at < CACHE_SECONDS then return done(c) end
  local function fail(why) done(nil, why) end
  local id, why = http.get("https://api.mojang.com/users/profiles/minecraft/" .. java, function(status, body)
    if status == 404 or status == 204 or status == 400 then return fail("no Java player called " .. java) end
    if status ~= 200 then return fail("Mojang didn't answer (" .. tostring(status) .. ")") end
    local t = json.decode(body)
    if type(t) ~= "table" or type(t.id) ~= "string" then return fail("Mojang's answer made no sense") end
    local real = type(t.name) == "string" and t.name or java
    http.get("https://sessionserver.mojang.com/session/minecraft/profile/" .. t.id, function(status, body)
      if status ~= 200 then return fail("Mojang didn't give the textures (" .. tostring(status) .. ")") end
      local prof = json.decode(body)
      local value
      for _, prop in ipairs(type(prof) == "table" and prof.properties or {}) do
        if prop.name == "textures" then value = prop.value end
      end
      if not value then return fail("that player has no textures") end
      local tex = json.decode(base64(value))
      local skin = type(tex) == "table" and type(tex.textures) == "table" and tex.textures.SKIN
      if type(skin) ~= "table" or type(skin.url) ~= "string" then return fail("that player has no skin set") end
      local cape = type(tex.textures.CAPE) == "table" and tex.textures.CAPE.url or nil
      local slim = type(skin.metadata) == "table" and skin.metadata.model == "slim"
      http.get(skin.url, function(status, png)
        if status ~= 200 or #png < 33 then return fail("the skin couldn't be fetched (" .. tostring(status) .. ")") end
        local got = {skin = png, at = server.now(), name = real, slim = slim}
        if not cape then cache[k] = got return done(got) end
        http.get(cape, function(status, cpng)
          if status == 200 and #cpng >= 33 then got.cape = cpng end
          cache[k] = got
          done(got)
        end)
      end)
    end)
  end)
  if not id then fail(why or "the server can't make web requests") end
end

local function put_on(p, java, say)
  local me = key(p.name)
  if busy[me] then return p:message("&eStill fetching the last one...") end
  busy[me] = true
  local who = p.name
  fetch(java, function(got, why)
    busy[me] = nil
    p = player(who)   -- (still here?)
    if not p then return end
    if not got then
      if say then p:message("&c" .. why) end
      return
    end
    if apply(p, got) and say then
      p:message("&aYou're wearing &f" .. got.name .. "&a's skin" .. (got.cape and " and cape" or "") ..
                (got.slim and " &7(a slim-arm skin: it shows on the classic arms)" or ""))
    end
  end)
end

local function take_off(p, say)
  p:set_skin(nil)
  if say then p:message("&aYour own skin's back") end
end

command("skin", {usage = "/skin <Java name|off>", description = "Wear a Java Edition player's skin and cape (off: your own)"},
  function(p, args)
    if not on_linux then return p:message("&cSkins can only be fetched by the Linux server") end
    local target, who = p, args[1]
    if args[2] and (p:is_staff() or p:has_permission("javaskins.others")) then
      target = player(args[1])
      if not target then return p:message("&cNo player online called " .. args[1]) end
      who = args[2]
    end
    if not who then return p:message("&e/skin <Java name> - or /skin off") end
    if who:lower() == "off" then
      names[key(target.name)] = nil
      take_off(target, true)
      if target ~= p then p:message("&a" .. target.name .. "'s own skin is back") end
      return
    end
    if not who:match("^[%w_]+$") or #who > 16 then return p:message("&cA Java name is up to 16 letters, digits and _") end
    names[key(target.name)] = who
    p:message("&eFetching " .. who .. "'s skin...")
    put_on(target, who, true)
  end)

on("join", function(p)
  local java = names[key(p.name)]
  if java and on_linux then
    local who = p.name
    after(40, function()
      local q = player(who)
      if q then put_on(q, java, false) end
    end)
  end
end)
