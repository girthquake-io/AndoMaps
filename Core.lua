-- AndoMaps core: positions, travel graph, route search, navigation, slash commands.

local ADDON, AM = ...
_G.AndoMaps = AM

local GetMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
AM.version = GetMeta and GetMeta(ADDON, "Version") or "?"

local sqrt, floor, max, min, atan2, pi = math.sqrt, math.floor, math.max, math.min, math.atan2, math.pi
local lower, format = string.lower, string.format

local HEARTHSTONE = 6948
local WALK_FACTOR = 1.3     -- roads wind; straight lines are optimistic
local FLY_SPEED   = 30      -- yards per second on a flight path
local FLY_FACTOR  = 1.2
local FLY_OVERHEAD = 15     -- talk, take off, land
local HEARTH_COST = 25      -- 10 s cast plus a loading screen
local TELEPORT_COST = 22    -- 10 s cast plus a loading screen
local RUN_SPEED   = 7

local DEFAULTS = {
    onlyKnown = true, useHearth = true, useMage = true, speed = "auto", arrow = true, mapPin = false,
    tomtom = true, minimap = true, autoFly = true, fpTips = true, minimapAngle = 215, taxiAlias = {}, bindAlias = {},
}

AM.callbacks = {}
function AM.Fire(event) for _, fn in ipairs(AM.callbacks) do pcall(fn, event) end end

local function issecret(v) return issecretvalue and issecretvalue(v) end

function AM.Print(msg, ...)
    if select("#", ...) > 0 then msg = format(msg, ...) end
    DEFAULT_CHAT_FRAME:AddMessage("|cff8fb3a8AndoMaps|r: " .. tostring(msg))
end

function AM.FormatTime(s)
    s = floor((s or 0) + 0.5)
    if s < 60 then return s .. "s" end
    if s < 3600 then return format("%dm %02ds", floor(s / 60), s % 60) end
    return format("%dh %02dm", floor(s / 3600), floor(s % 3600 / 60))
end

---------------------------------------------------------------------------
-- Positions
---------------------------------------------------------------------------
function AM.WorldPos(map, x, y)
    if not map or not CreateVector2D then return end
    local ok, cont, pos = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(x, y))
    if not ok or not cont or not pos or issecret(cont) or issecret(pos.x) then return end
    return cont, pos.x, pos.y
end

local function Dist(a, b)
    if not a.cont or a.cont ~= b.cont then return nil end
    local dx, dy = a.wx - b.wx, a.wy - b.wy
    return sqrt(dx * dx + dy * dy)
end
AM.Dist = Dist

function AM.ZoneName(map)
    local info = map and C_Map.GetMapInfo(map)
    return info and info.name or ("map " .. tostring(map))
end

-- Climb the map tree until we hit a zone the network knows about.
function AM.ResolveZone(map)
    local m = map
    for _ = 1, 10 do
        if not m or m == 0 then break end
        if AM.zoneNodes[m] then return m end
        local info = C_Map.GetMapInfo(m)
        if not info or (info.mapType and info.mapType <= 2) then break end
        m = info.parentMapID
    end
    return map
end

function AM.PlayerPos()
    local map = C_Map.GetBestMapForUnit("player")
    if not map or issecret(map) then return end
    local ok, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
    if not ok or not pos then return end
    local px, py = pos:GetXY()
    if not px or issecret(px) or issecret(py) or (px == 0 and py == 0) then return end
    local cont, wx, wy = AM.WorldPos(map, px, py)
    if not cont then return end
    return { map = map, x = px * 100, y = py * 100, cont = cont, wx = wx, wy = wy, zone = AM.ResolveZone(map) }
end

---------------------------------------------------------------------------
-- Network setup
---------------------------------------------------------------------------
AM.byId, AM.zoneNodes, AM.flights, AM.linkIndex = {}, {}, {}, {}

function AM.InitNetwork()
    local missing = 0
    for _, n in ipairs(AM.nodes) do
        AM.byId[n.id] = n
        n.cont, n.wx, n.wy = AM.WorldPos(n.map, n.x / 100, n.y / 100)
        if not n.cont then missing = missing + 1 end
        if n.noZone then
            n.zones = {}
        elseif not n.zones then
            n.zones = { n.map }
        end
        if n.cont then
            for _, z in ipairs(n.zones) do
                AM.zoneNodes[z] = AM.zoneNodes[z] or {}
                table.insert(AM.zoneNodes[z], n)
            end
            if n.kind == "flight" then table.insert(AM.flights, n) end
        end
    end
    for _, l in ipairs(AM.links) do
        local a, b = AM.byId[l.a], AM.byId[l.b]
        if a and b then
            AM.linkIndex[a.id] = AM.linkIndex[a.id] or {}
            table.insert(AM.linkIndex[a.id], { to = b, link = l })
            if not l.oneway then
                AM.linkIndex[b.id] = AM.linkIndex[b.id] or {}
                table.insert(AM.linkIndex[b.id], { to = a, link = l })
            end
        end
    end
    AM.missing = missing
end

local function FactionOK(f) return not f or f == AM.faction end
local function Usable(n) return FactionOK(n.faction) end

---------------------------------------------------------------------------
-- Speed, flights, hearthstone
---------------------------------------------------------------------------
function AM.GroundSpeed()
    local s = AM.db.speed
    if s == "walk" then return RUN_SPEED end
    if s == "mount60" then return RUN_SPEED * 1.6 end
    if s == "mount100" then return RUN_SPEED * 2 end
    if AM.cdb.mountSpeed then return AM.cdb.mountSpeed end
    if (UnitLevel("player") or 1) >= 40 then return RUN_SPEED * 1.6 end
    return RUN_SPEED
end

function AM.SpeedLabel()
    local s = AM.db.speed
    if s == "walk" then return "On foot" end
    if s == "mount60" then return "60% mount" end
    if s == "mount100" then return "100% mount" end
    return format("Auto (%d%%)", floor(AM.GroundSpeed() / RUN_SPEED * 100 + 0.5))
end

function AM.FlightKnown(n)
    if AM.assumeAllFlights or not AM.db.onlyKnown then return true end
    if not (AM.cdb.taxiSeen and AM.cdb.taxiSeen[n.cont or 0]) then return true end
    return AM.cdb.known[n.id] and true or false
end

local function TaxiKey(name)
    local seg = lower(name:match("^([^,]+)") or name)
    return (seg:gsub("^%s+", ""):gsub("%s+$", ""))
end

function AM.MatchTaxi(name)
    local alias = AM.db.taxiAlias[AM.faction .. ":" .. name]
    if alias and AM.byId[alias] then return AM.byId[alias] end
    local seg = TaxiKey(name)
    local loose
    for _, n in ipairs(AM.flights) do
        if Usable(n) and n.taxi ~= false then
            local key = lower(n.taxi or n.name)
            if key == seg then return n end
            if not loose and (key:find(seg, 1, true) == 1 or seg:find(key, 1, true) == 1) then loose = n end
        end
    end
    return loose
end

local function Nearest(p, filter, radius)
    local best, bd
    for _, n in ipairs(AM.nodes) do
        if filter(n) then
            local d = Dist(p, n)
            if d and d <= radius and (not bd or d < bd) then best, bd = n, d end
        end
    end
    return best
end

function AM.LearnTaxiMap()
    if not NumTaxiNodes then return end
    local p = AM.PlayerPos()
    local count, learned, cont = NumTaxiNodes(), 0, p and p.cont
    for i = 1, count do
        local name, typ = TaxiNodeName(i), TaxiNodeGetType(i)
        if name and typ == "CURRENT" and p then
            local here = Nearest(p, function(n) return n.kind == "flight" and Usable(n) end, 150)
            if here then AM.db.taxiAlias[AM.faction .. ":" .. name] = here.id end
        end
    end
    for i = 1, count do
        local name, typ = TaxiNodeName(i), TaxiNodeGetType(i)
        if name and (typ == "CURRENT" or typ == "REACHABLE") then
            local n = AM.MatchTaxi(name)
            if n then
                if not AM.cdb.known[n.id] then learned = learned + 1 end
                AM.cdb.known[n.id] = true
                cont = cont or n.cont
            end
        end
    end
    if cont then AM.cdb.taxiSeen[cont] = true end
    if learned > 0 then AM.Fire("known") end
end

function AM.MatchBind(bind)
    if not bind or bind == "" then return end
    local id = AM.db.bindAlias[AM.faction .. ":" .. bind]
    if id and AM.byId[id] then return AM.byId[id] end
    local b, loose = lower(bind), nil
    for _, n in ipairs(AM.nodes) do
        if (n.kind == "inn" or n.kind == "flight") and Usable(n) then
            local names = { n.name }
            for _, a in ipairs(n.bind or {}) do names[#names + 1] = a end
            for _, nm in ipairs(names) do
                local k = lower(nm)
                if k == b and n.kind == "inn" then return n end
                if not loose and (k == b or k:find(b, 1, true) or b:find(k, 1, true)) then loose = n end
            end
        end
    end
    return loose
end

function AM.LearnBind()
    local p, bind = AM.PlayerPos(), GetBindLocation and GetBindLocation()
    if not p or not bind then return end
    local inn = Nearest(p, function(n) return n.kind == "inn" and Usable(n) end, 250)
    if inn then AM.db.bindAlias[AM.faction .. ":" .. bind] = inn.id end
end

local function ItemCount(id)
    if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(id) or 0 end
    return GetItemCount and GetItemCount(id) or 0
end

local function ItemCooldown(id)
    local fn = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
    if not fn then return 0 end
    local ok, start, dur = pcall(fn, id)
    if not ok or not start or issecret(start) or start == 0 or (dur or 0) <= 1.5 then return 0 end
    return max(0, start + dur - GetTime())
end

-- Returns bind node, seconds until usable, bind name (or nil + reason)
function AM.HearthInfo()
    if not AM.db.useHearth then return nil, "off" end
    if ItemCount(HEARTHSTONE) == 0 then return nil, "no Hearthstone in your bags" end
    local bind = GetBindLocation and GetBindLocation()
    local node = AM.MatchBind(bind)
    if not node then return nil, "don't know where " .. tostring(bind) .. " is" end
    return node, ItemCooldown(HEARTHSTONE), bind
end

---------------------------------------------------------------------------
-- Mage teleports and portals
---------------------------------------------------------------------------
local function SpellKnown(id)
    if IsPlayerSpell and IsPlayerSpell(id) then return true end
    return IsSpellKnown and IsSpellKnown(id) or false
end

-- false only when the game says you can't cast it for a reason other than mana
-- (no Rune of Teleportation, wrong form, ...). Out of mana still counts: it comes back.
local function SpellUsable(id)
    local fn = (C_Spell and C_Spell.IsSpellUsable) or IsUsableSpell
    if not fn then return true end
    local ok, usable, noMana = pcall(fn, id)
    if not ok or issecret(usable) then return true end
    return usable or noMana or false
end

local function SpellCooldown(id)
    if C_Spell and C_Spell.GetSpellCooldown then
        local ok, info = pcall(C_Spell.GetSpellCooldown, id)
        if ok and info and info.startTime and not issecret(info.startTime) and info.startTime > 0 and (info.duration or 0) > 1.5 then
            return max(0, info.startTime + info.duration - GetTime())
        end
        return 0
    end
    if GetSpellCooldown then
        local ok, start, dur = pcall(GetSpellCooldown, id)
        if ok and start and not issecret(start) and start > 0 and (dur or 0) > 1.5 then
            return max(0, start + dur - GetTime())
        end
    end
    return 0
end

function AM.SpellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    return GetSpellInfo and (GetSpellInfo(id)) or nil
end

function AM.SpellIcon(id)
    if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(id) end
    return GetSpellTexture and GetSpellTexture(id) or nil
end

function AM.IsMage() return select(2, UnitClass("player")) == "MAGE" end

-- Engineering transporters (and any other teleport item): in your bags and usable.
local function ItemCount(id)
    local fn = (C_Item and C_Item.GetItemCount) or GetItemCount
    if not fn then return 0 end
    local ok, n = pcall(fn, id)
    return ok and not issecret(n) and n or 0
end

local function ItemUsable(id)
    local fn = (C_Item and C_Item.IsUsableItem) or IsUsableItem
    if not fn then return true end
    local ok, usable = pcall(fn, id)
    if not ok or issecret(usable) then return true end
    return usable and true or false
end

local function ItemCooldown(id)
    local fn = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
    if not fn then return 0 end
    local ok, start, dur = pcall(fn, id)
    if ok and start and not issecret(start) and start > 0 and (dur or 0) > 1.5 then
        return max(0, start + dur - GetTime())
    end
    return 0
end

function AM.ItemName(id)
    local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
    if not name and GetItemInfo then name = GetItemInfo(id) end
    return name
end

function AM.ItemIcon(id)
    if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(id) end
    return GetItemIcon and GetItemIcon(id) or nil
end

function AM.ItemTeleports()
    local out = {}
    for _, t in ipairs(AM.teleportItems or {}) do
        local node = AM.byId[t.node]
        if node and node.cont and Usable(node) and ItemCount(t.item) > 0 and ItemUsable(t.item) then
            out[#out + 1] = { node = node, item = t.item, wait = ItemCooldown(t.item),
                              name = AM.ItemName(t.item) or t.name, icon = AM.ItemIcon(t.item) }
        end
    end
    return out
end

-- Whether the Teleports checkbox means anything for this character.
function AM.HasTeleports()
    return AM.IsMage() or #AM.ItemTeleports() > 0
end

-- Everything that can teleport you right now: mage teleports (or, failing
-- that, portals), one per city, plus teleport items such as the engineering
-- transporters. All of it follows the Teleports checkbox.
function AM.MageTeleports()
    local out = {}
    if not AM.db.useMage then return out end
    for _, t in ipairs(AM.ItemTeleports()) do out[#out + 1] = t end
    if not AM.IsMage() or not AM.mageSpells then return out end
    for _, m in ipairs(AM.mageSpells) do
        local node = AM.byId[m.node]
        if node and node.cont and Usable(node) then
            for _, id in ipairs({ m.teleport, m.portal }) do
                if SpellKnown(id) and SpellUsable(id) then
                    out[#out + 1] = { node = node, spell = id, wait = SpellCooldown(id), city = m.city,
                                      portal = id == m.portal, name = AM.SpellName(id), icon = AM.SpellIcon(id) }
                    break
                end
            end
        end
    end
    return out
end

---------------------------------------------------------------------------
-- Route search (Dijkstra over the network plus a start and goal vertex)
---------------------------------------------------------------------------
local function InferArea(p, zone)
    local best, bd
    for _, n in ipairs(AM.zoneNodes[zone] or {}) do
        local d = Dist(p, n)
        if d and (not bd or d < bd) then best, bd = n, d end
    end
    if best and best.area and bd < 600 then return best.area end
end

-- goal: { nodes = {...}, name = "..."} or { pos = {map,x,y}, name = "..." } or { zone = id, name = "..." }
function AM.FindRoute(goal)
    local p = AM.PlayerPos()
    if not p then return nil, "Can't read your position here (instances and some indoor spots hide it)." end
    local speed = AM.GroundSpeed()
    local function walk(d) return d * WALK_FACTOR / speed end

    local S = { id = "start", name = "Your location", kind = "start", cont = p.cont, wx = p.wx, wy = p.wy,
                map = p.map, x = p.x, y = p.y, zones = { p.zone }, area = InferArea(p, p.zone) }
    local G = { id = "goal", name = goal.name or "Destination", kind = "goal" }

    local goalSet = {}
    if goal.nodes then
        for _, n in ipairs(goal.nodes) do goalSet[n] = true end
    elseif goal.zone then
        if p.zone == goal.zone then return nil, "You're already in " .. AM.ZoneName(goal.zone) .. "." end
        for _, n in ipairs(AM.zoneNodes[goal.zone] or {}) do goalSet[n] = true end
        if not next(goalSet) then return nil, "No known way into " .. AM.ZoneName(goal.zone) .. " yet." end
    elseif goal.pos then
        local cont, wx, wy = AM.WorldPos(goal.pos.map, goal.pos.x / 100, goal.pos.y / 100)
        if not cont then return nil, "That map position has no world location." end
        G.cont, G.wx, G.wy, G.map, G.x, G.y = cont, wx, wy, goal.pos.map, goal.pos.x, goal.pos.y
        G.zone = AM.ResolveZone(goal.pos.map)
        G.area = InferArea(G, G.zone)
    end

    local hearthNode, hearthWait = AM.HearthInfo()
    local mageTeleports = AM.MageTeleports()

    local function edges(u)
        local out = {}
        local function add(v, cost, kind, link)
            if cost then out[#out + 1] = { v = v, cost = cost, kind = kind, link = link } end
        end
        local function walkable(v) return v ~= u and (Usable(v) or goalSet[v]) and v.area == u.area end
        local zoneHits = 0
        for _, z in ipairs(u.zones or {}) do
            for _, v in ipairs(AM.zoneNodes[z] or {}) do
                if walkable(v) then
                    local d = Dist(u, v)
                    if d then add(v, walk(d), "walk"); zoneHits = zoneHits + 1 end
                end
            end
        end
        if u == S then
            if zoneHits == 0 then -- unknown pocket of the world: walk to the closest few nodes
                local near = {}
                for _, v in ipairs(AM.nodes) do
                    local d = Usable(v) and Dist(S, v)
                    if d then near[#near + 1] = { v = v, d = d } end
                end
                table.sort(near, function(a, b) return a.d < b.d end)
                for i = 1, min(4, #near) do add(near[i].v, walk(near[i].d) * 1.5, "walk") end
            end
            if hearthNode and hearthNode.cont then
                add(hearthNode, hearthWait + HEARTH_COST, "hearth")
            end
            for _, tp in ipairs(mageTeleports) do
                add(tp.node, tp.wait + TELEPORT_COST, "teleport", tp)
            end
        end
        if u.kind == "flight" and Usable(u) and AM.FlightKnown(u) then
            for _, v in ipairs(AM.flights) do
                if v ~= u and v.cont == u.cont and Usable(v) and AM.FlightKnown(v) then
                    add(v, Dist(u, v) * FLY_FACTOR / FLY_SPEED + FLY_OVERHEAD, "fly")
                end
            end
        end
        if u.id then
            for _, e in ipairs(AM.linkIndex[u.id] or {}) do
                if FactionOK(e.link.faction) then
                    local cost = e.link.cost
                    if not cost then local d = Dist(u, e.to); cost = d and walk(d) end
                    add(e.to, cost, e.link.kind, e.link)
                end
            end
        end
        if goalSet[u] then add(G, 0, "arrive") end
        if G.cont and u.area == G.area then
            local inZone = false
            for _, z in ipairs(u.zones or {}) do if z == G.zone then inZone = true end end
            if inZone then local d = Dist(u, G); if d then add(G, walk(d), "walk") end end
        end
        return out
    end

    -- Dijkstra
    local dist, prev, done = { [S] = 0 }, {}, {}
    local frontier = { S }
    while #frontier > 0 do
        local bi, bu = 1, frontier[1]
        for i = 2, #frontier do
            if dist[frontier[i]] < dist[bu] then bi, bu = i, frontier[i] end
        end
        table.remove(frontier, bi)
        if bu == G then break end
        if not done[bu] then
            done[bu] = true
            for _, e in ipairs(edges(bu)) do
                local nd = dist[bu] + e.cost
                if not done[e.v] and (not dist[e.v] or nd < dist[e.v]) then
                    if not dist[e.v] then frontier[#frontier + 1] = e.v end
                    dist[e.v] = nd
                    prev[e.v] = { from = bu, kind = e.kind, link = e.link, cost = e.cost }
                end
            end
        end
    end
    if not dist[G] then return nil, "No route found. Some areas only connect through paths AndoMaps doesn't know yet." end

    local legs, v = {}, G
    while prev[v] do
        local pr = prev[v]
        table.insert(legs, 1, { from = pr.from, to = v, kind = pr.kind, link = pr.link, cost = pr.cost })
        v = pr.from
    end
    -- "arrive" is a bookkeeping hop: the real destination is the node before it.
    if legs[#legs] and legs[#legs].kind == "arrive" then
        G.name = legs[#legs].from.name
        table.remove(legs)
    end
    -- Merge back-to-back walks that stay inside one zone with no named stop in between? Keep them:
    -- each border is a useful waypoint.
    for _, leg in ipairs(legs) do leg.text = AM.LegText(leg, legs[#legs] == leg) end
    return { legs = legs, total = dist[G], name = goal.name or G.name, goal = goal, start = S }
end

local VERB = { boat = "Take the boat to ", zeppelin = "Take the zeppelin to ", tram = "Ride the Deeprun Tram to ",
               portal = "Step through the portal to " }

function AM.LegText(leg, last)
    local to = leg.to
    local where = to.map and to.kind ~= "goal" and AM.ZoneName(to.map) or nil
    if leg.kind == "fly" then return "Fly to " .. to.name end
    if leg.kind == "teleport" then
        local tp = leg.link
        local s = (tp.item and "Use " or "Cast ") .. (tp.name or ((tp.portal and "Portal: " or "Teleport: ") .. tp.city))
        if leg.cost > TELEPORT_COST + 1 then s = s .. " (after the cooldown)" end
        return s
    end
    if leg.kind == "hearth" then
        return "Hearth to " .. to.name .. (leg.cost > HEARTH_COST + 1 and " (after the cooldown)" or "")
    end
    if VERB[leg.kind] then
        local place = to.name:match("%((.-)%)")
        if leg.kind == "boat" or leg.kind == "zeppelin" or not place then
            place = to.name:gsub(" docks?.*", ""):gsub(" zeppelin tower", "")
        end
        return VERB[leg.kind] .. place
    end
    if leg.link and leg.link.text then return leg.link.text end
    local verb = "Go to "
    if to.kind == "dungeon" or to.kind == "raid" then verb = "Enter " end
    if to.kind == "flight" then verb = "Go to the flight master at " end
    if to.kind == "goal" then return "Walk to the destination" end
    local s = verb .. to.name
    if where and to.kind ~= "border" and not to.name:find(where, 1, true) then s = s .. " (" .. where .. ")" end
    if to.note then s = s .. " - " .. to.note end
    return s
end

---------------------------------------------------------------------------
-- Destinations and search
---------------------------------------------------------------------------
AM.destinations = {}

local KIND_LABEL = { flight = "Flight path", inn = "Inn", dungeon = "Dungeon", raid = "Raid",
                     dock = "Transport", tram = "Transport", portal = "Transport", zone = "Zone", hub = "Landmark", mage = "Landmark",
                     bank = "Bank", ah = "Auction House" }

-- "Nearest bank" / "Nearest auction house": every one of your faction is a goal,
-- so the router ends at whichever is quickest to reach from here.
local NEAREST = {
    { kind = "bank", label = "Nearest bank", keys = { "bank", "banker", "nearest bank" } },
    { kind = "ah", label = "Nearest auction house",
      keys = { "ah", "auction house", "auction", "auctioneer", "nearest ah", "nearest auction house" } },
}

function AM.NearestDest(kind)
    for _, d in ipairs(AM.destinations) do
        if d.nearest == kind then return d end
    end
end
AM.KIND_LABEL = KIND_LABEL

function AM.BuildDestinations()
    local list, groups, seenZone = {}, {}, {}
    for _, n in ipairs(AM.nodes) do
        if n.cont and n.kind ~= "border" then
            if n.dest then
                local g = groups[n.dest]
                if not g then
                    g = { label = n.name, kind = n.kind, nodes = {}, keys = {}, level = n.level, map = n.map }
                    groups[n.dest] = g
                    list[#list + 1] = g
                end
                table.insert(g.nodes, n)
                for _, a in ipairs(n.aliases or {}) do g.keys[#g.keys + 1] = lower(a) end
            else
                local d = { label = n.name, kind = n.kind, nodes = { n }, keys = {}, level = n.level, map = n.map, faction = n.faction }
                for _, a in ipairs(n.aliases or {}) do d.keys[#d.keys + 1] = lower(a) end
                list[#list + 1] = d
            end
        end
        if n.cont then
            for _, z in ipairs(n.zones) do
                if not seenZone[z] then
                    seenZone[z] = true
                    list[#list + 1] = { label = AM.ZoneName(z), kind = "zone", zone = z, keys = {} }
                end
            end
        end
    end
    for _, n in ipairs(NEAREST) do
        local keys = {}
        for i, k in ipairs(n.keys) do keys[i] = k end
        list[#list + 1] = { label = n.label, kind = n.kind, nearest = n.kind, keys = keys }
    end
    for _, d in ipairs(list) do
        table.insert(d.keys, 1, lower(d.label))
        if d.nearest then
            d.sub = "The quickest one to reach from here"
        else
            d.sub = d.kind == "zone" and "Zone" or (KIND_LABEL[d.kind] or d.kind) .. " - " .. AM.ZoneName(d.map)
            if d.level then d.sub = d.sub .. " - " .. d.level end
        end
    end
    AM.destinations = list
end

local function Score(d, q)
    local best
    for i, k in ipairs(d.keys) do
        local s
        if k == q then s = 0
        elseif k:find(q, 1, true) == 1 then s = 1
        elseif k:find(" " .. q, 1, true) or k:find("'" .. q, 1, true) then s = 2
        elseif #q >= 3 and k:find(q, 1, true) then s = 3 end
        if s and i > 1 then s = s + 0.5 end
        if s and (not best or s < best) then best = s end
    end
    return best
end

function AM.Search(query, limit)
    local q = lower((query or ""):gsub("^%s+", ""):gsub("%s+$", ""))
    if q == "" then return {} end
    local hits = {}
    for _, d in ipairs(AM.destinations) do
        local s = Score(d, q)
        -- hide the other faction's flight masters and inns unless typed exactly
        if s and d.faction and d.faction ~= AM.faction and s > 0 then s = nil end
        if s then hits[#hits + 1] = { d = d, s = s } end
    end
    table.sort(hits, function(a, b)
        if a.s ~= b.s then return a.s < b.s end
        return a.d.label < b.d.label
    end)
    local out = {}
    for i = 1, min(limit or 8, #hits) do out[i] = hits[i].d end
    return out
end

-- kind: "dungeon" or "raid" for just those; nil for both
function AM.Dungeons(kind)
    local out = {}
    for _, d in ipairs(AM.destinations) do
        if (d.kind == "dungeon" or d.kind == "raid") and (not kind or d.kind == kind) then out[#out + 1] = d end
    end
    local function lvl(d) return tonumber((d.level or "99"):match("^(%d+)")) or 99 end
    table.sort(out, function(a, b)
        if (a.kind == "raid") ~= (b.kind == "raid") then return b.kind == "raid" end
        if lvl(a) ~= lvl(b) then return lvl(a) < lvl(b) end
        return a.label < b.label
    end)
    return out
end

---------------------------------------------------------------------------
-- Navigation state
---------------------------------------------------------------------------
AM.route, AM.step = nil, 1

local function GoalFor(d)
    if d.zone then return { zone = d.zone, name = d.label } end
    if d.nearest then
        local nodes = {}
        for _, n in ipairs(AM.nodes) do
            if n.kind == d.nearest and n.cont and Usable(n) then nodes[#nodes + 1] = n end
        end
        return { nodes = nodes } -- no name: the route is named after the one it reaches
    end
    return { nodes = d.nodes, name = d.label }
end

-- Would this trip be quicker with flight paths you don't have yet? Route again
-- as if you knew them all; if that saves a real amount of time, name the
-- missing flight paths that faster route flies through.
local TIP_MIN_SAVING, TIP_MIN_SHARE = 60, 0.10
function AM.FlightTip(r, goal)
    if not (AM.db.fpTips and AM.db.onlyKnown) then return nil end
    AM.assumeAllFlights = true
    local ok, r2 = pcall(AM.FindRoute, goal)
    AM.assumeAllFlights = nil
    if not ok or not r2 then return nil end
    local saved = r.total - r2.total
    if saved < TIP_MIN_SAVING or saved < r.total * TIP_MIN_SHARE then return nil end
    local nodes, seen = {}, {}
    for _, leg in ipairs(r2.legs) do
        if leg.kind == "fly" then
            for _, n in ipairs({ leg.from, leg.to }) do
                if not seen[n] and not AM.FlightKnown(n) then seen[n] = true; nodes[#nodes + 1] = n end
            end
        end
    end
    if #nodes == 0 then return nil end
    for _, n in ipairs(nodes) do
        if AM.db.fpIgnore and AM.db.fpIgnore[n.id] then return nil end -- "don't ask about this one again"
    end
    local names = {}
    for i, n in ipairs(nodes) do names[i] = n.name .. " (" .. AM.ZoneName(n.map) .. ")" end
    return { nodes = nodes, names = table.concat(names, " and "), total = r2.total, saved = saved }
end

-- Flight paths of your faction you haven't picked up, on continents whose flight map you've opened.
function AM.MissingFlights()
    local out = {}
    for _, n in ipairs(AM.flights) do
        if Usable(n) and n.cont and AM.cdb.taxiSeen[n.cont] and not AM.cdb.known[n.id] then out[#out + 1] = n end
    end
    table.sort(out, function(a, b)
        local za, zb = AM.ZoneName(a.map), AM.ZoneName(b.map)
        if za ~= zb then return za < zb end
        return a.name < b.name
    end)
    return out
end

function AM.RouteTo(d)
    local goal = d.goal or GoalFor(d)
    local r, err = AM.FindRoute(goal)
    if not r then AM.Print(err); AM.Fire("error"); return nil, err end
    AM.route, AM.step = r, 1
    AM.dest = d
    AM.Print("Route to %s: %s, %d step%s.", r.name, AM.FormatTime(r.total), #r.legs, #r.legs == 1 and "" or "s")
    r.tip = AM.FlightTip(r, goal)
    if r.tip then
        local key = r.name .. ":" .. r.tip.names
        if key ~= AM.lastTipKey then
            AM.lastTipKey = key
            if not (AM.ShowFlightTip and AM.ShowFlightTip(r)) then
                AM.Print("|cffdcc280Get the %s flight path%s for faster routes next time:|r this trip would take %s instead of %s.",
                    r.tip.names, #r.tip.nodes == 1 and "" or "s", AM.FormatTime(r.tip.total), AM.FormatTime(r.total))
            end
        end
    end
    AM.OnStepChanged()
    AM.Fire("route")
    return r
end

function AM.Recalculate()
    if AM.dest then return AM.RouteTo(AM.dest) end
end

function AM.Clear()
    AM.route, AM.dest, AM.step = nil, nil, 1
    AM.ClearPins()
    AM.Fire("route")
end

function AM.CurrentLeg() return AM.route and AM.route.legs[AM.step] end

function AM.SetStep(i)
    if not AM.route then return end
    AM.step = max(1, min(i, #AM.route.legs))
    AM.OnStepChanged()
    AM.Fire("step")
end

local tomtomUID
function AM.ClearPins()
    if tomtomUID and TomTom and TomTom.RemoveWaypoint then pcall(TomTom.RemoveWaypoint, TomTom, tomtomUID) end
    tomtomUID = nil
    if AM.pinSet and C_Map.ClearUserWaypoint then pcall(C_Map.ClearUserWaypoint) end
    AM.pinSet = nil
end

function AM.OnStepChanged()
    AM.ClearPins()
    local leg = AM.CurrentLeg()
    if not leg or not leg.to.map then return end
    local t = leg.to
    if AM.db.tomtom and TomTom and TomTom.AddWaypoint then
        local ok, uid = pcall(TomTom.AddWaypoint, TomTom, t.map, t.x / 100, t.y / 100,
            { title = "AndoMaps: " .. leg.text, persistent = false, minimap = true, world = true })
        if ok then tomtomUID = uid end
    end
    if AM.db.mapPin and C_Map.SetUserWaypoint and UiMapPoint and C_Map.CanSetUserWaypointOnMap
        and C_Map.CanSetUserWaypointOnMap(t.map) then
        if pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(t.map, t.x / 100, t.y / 100)) then
            AM.pinSet = true
            if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
                pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
            end
        end
    end
end

local ARRIVE = { walk = 25, fly = 90, boat = 120, zeppelin = 120, tram = 120, portal = 60, hearth = 150, teleport = 150 }

-- Called a few times a second by the arrow frame. Advances steps as you arrive.
function AM.Tick()
    if not AM.route then return end
    local p = AM.PlayerPos()
    if not p then return end
    local legs = AM.route.legs
    for i = #legs, AM.step, -1 do
        local t = legs[i].to
        local d = Dist(p, t)
        local r = ARRIVE[legs[i].kind] or 25
        if t.kind == "dungeon" or t.kind == "raid" or t.kind == "hub" then r = max(r, 40) end
        if d and d <= r and not (UnitOnTaxi and UnitOnTaxi("player")) then
            if i == #legs then
                AM.Print("You have arrived at %s.", AM.route.name)
                pcall(PlaySound, (SOUNDKIT and SOUNDKIT.MAP_PING) or 3175)
                AM.Clear()
                return
            end
            if i + 1 ~= AM.step then AM.SetStep(i + 1) end
            return
        end
    end
end

-- Direction to the current target relative to where the player faces (radians, CCW), and distance.
local axesCache = {}
local function Axes(map)
    local a = axesCache[map]
    if a ~= nil then return a or nil end
    local c1, nx1, ny1 = AM.WorldPos(map, 0.5, 0.25)
    local c2, nx2, ny2 = AM.WorldPos(map, 0.5, 0.75)
    local c3, ex1, ey1 = AM.WorldPos(map, 0.75, 0.5)
    local c4, ex2, ey2 = AM.WorldPos(map, 0.25, 0.5)
    if not (c1 and c2 and c3 and c4) then axesCache[map] = false; return end
    local nx, ny = nx1 - nx2, ny1 - ny2
    local ln = sqrt(nx * nx + ny * ny)
    local ex, ey = ex1 - ex2, ey1 - ey2
    local le = sqrt(ex * ex + ey * ey)
    if ln == 0 or le == 0 then axesCache[map] = false; return end
    a = { nx = nx / ln, ny = ny / ln, ex = ex / le, ey = ey / le }
    axesCache[map] = a
    return a
end

function AM.Bearing()
    local leg = AM.CurrentLeg()
    if not leg then return end
    local p = AM.PlayerPos()
    if not p then return nil, nil, "no position" end
    local t = leg.to
    local d = Dist(p, t)
    if not d then return nil, nil, "other continent" end
    local ax = Axes(p.map)
    local facing = GetPlayerFacing and GetPlayerFacing()
    if not ax or not facing or issecret(facing) then return nil, d, "no facing" end
    local dx, dy = t.wx - p.wx, t.wy - p.wy
    local north = dx * ax.nx + dy * ax.ny
    local east = dx * ax.ex + dy * ax.ey
    local bearing = atan2(-east, north) -- 0 = north, counter-clockwise like GetPlayerFacing
    local rel = (bearing - facing) % (2 * pi)
    return rel, d
end

function AM.RemainingTime()
    if not AM.route then return 0 end
    local s, legs = 0, AM.route.legs
    for i = AM.step, #legs do s = s + legs[i].cost end
    local leg, p = legs[AM.step], AM.PlayerPos()
    if leg and leg.kind == "walk" and p then
        local d = Dist(p, leg.to)
        if d then s = s - leg.cost + d * WALK_FACTOR / AM.GroundSpeed() end
    end
    return max(0, s)
end

---------------------------------------------------------------------------
-- Auto-fly (like RestedXP): when the route's next step is a flight, talking to
-- a flight master opens the flight map and takes the flight. Hold Shift to skip.
---------------------------------------------------------------------------
-- The flight leg you're about to take: the current step, or the next one if
-- you're still walking up to its flight master.
function AM.PendingFlight()
    if not AM.route then return end
    local legs, i = AM.route.legs, AM.step
    local leg, nxt = legs[i], legs[i + 1]
    if leg and leg.kind == "fly" then return leg, i end
    if leg and nxt and nxt.kind == "fly" and leg.to == nxt.from then return nxt, i + 1 end
end

local TAXI_ICON = 132057

function AM.AutoGossipTaxi()
    if not AM.db.autoFly or IsShiftKeyDown() or not AM.PendingFlight() then return end
    if not (C_GossipInfo and C_GossipInfo.GetOptions) then return end
    for _, opt in ipairs(C_GossipInfo.GetOptions() or {}) do
        if opt.type == "taxi" or opt.icon == TAXI_ICON then
            if opt.gossipOptionID and C_GossipInfo.SelectOption then
                C_GossipInfo.SelectOption(opt.gossipOptionID, "", true)
            elseif opt.orderIndex and C_GossipInfo.SelectOptionByIndex then
                C_GossipInfo.SelectOptionByIndex(opt.orderIndex, "", true)
            end
            return
        end
    end
end

function AM.AutoFly()
    if not AM.db.autoFly or IsShiftKeyDown() then return end
    local leg, index = AM.PendingFlight()
    if not leg or not NumTaxiNodes or not TakeTaxiNode then return end
    for i = 1, NumTaxiNodes() do
        local name, typ = TaxiNodeName(i), TaxiNodeGetType(i)
        if name and AM.MatchTaxi(name) == leg.to then
            if typ ~= "REACHABLE" then
                AM.Print("%s isn't reachable from this flight master.", leg.to.name)
                return
            end
            if AM.step ~= index then AM.SetStep(index) end
            local button = _G["TaxiButton" .. i]
            if button and TaxiNodeOnButtonEnter then pcall(TaxiNodeOnButtonEnter, button) end
            AM.Print("Flying to %s (hold Shift when talking to the flight master to skip).", leg.to.name)
            TakeTaxiNode(i)
            if GameTooltip and not GameTooltip:IsForbidden() then GameTooltip:Hide() end
            return
        end
    end
    AM.Print("%s isn't on this flight map. Pick a flight yourself, then press Recalculate.", leg.to.name)
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local function ParseCoords(msg)
    local x, y, rest = msg:match("^%s*(%d+%.?%d*)[%s,]+(%d+%.?%d*)%s*(.*)$")
    if not x then return end
    x, y = tonumber(x), tonumber(y)
    if not x or not y or x > 100 or y > 100 then return end
    local map
    if rest and rest ~= "" then
        for _, d in ipairs(AM.Search(rest, 20)) do
            if d.kind == "zone" then map = d.zone; break end
        end
        if not map then return nil, "Unknown zone: " .. rest end
    else
        map = C_Map.GetBestMapForUnit("player")
    end
    if not map then return end
    return { goal = { pos = { map = map, x = x, y = y }, name = format("%.1f, %.1f %s", x, y, AM.ZoneName(map)) },
             label = format("%.1f, %.1f", x, y), kind = "point" }
end

function AM.MapPinDest()
    local wp = C_Map.GetUserWaypoint and C_Map.GetUserWaypoint()
    if not wp or not wp.uiMapID or not wp.position then return nil, "Place a pin on the world map first (Ctrl-click the map)." end
    local x, y = wp.position:GetXY()
    return { goal = { pos = { map = wp.uiMapID, x = x * 100, y = y * 100 }, name = "Map pin (" .. AM.ZoneName(wp.uiMapID) .. ")" },
             label = "Map pin", kind = "point" }
end

function AM.Slash(msg)
    msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local cmd = lower(msg)
    if cmd == "" then if AM.ToggleUI then AM.ToggleUI() end return end
    if cmd == "help" then
        AM.Print("/am - open the window. /am <place or dungeon> - route there. /am 45 60 [zone] - route to coordinates.")
        AM.Print("/am pin - route to your map pin. Alt+click the world map - route to that spot.")
        AM.Print("/am bank | /am ah - route to the nearest bank or auction house.")
        AM.Print("/am missing - flight paths you haven't got. /am fptips - toggle the 'get this flight path' tips.")
        AM.Print("/am next | prev | clear | steps | recalc | arrow | minimap | known | forget")
        return
    end
    if cmd == "clear" then AM.Clear(); AM.Print("Route cleared.") return end
    if cmd == "next" then AM.SetStep(AM.step + 1) return end
    if cmd == "prev" then AM.SetStep(AM.step - 1) return end
    if cmd == "recalc" or cmd == "recalculate" then if not AM.Recalculate() then AM.Print("No route to recalculate.") end return end
    if cmd == "arrow" then AM.db.arrow = not AM.db.arrow; AM.Fire("settings"); AM.Print("Arrow %s.", AM.db.arrow and "on" or "off") return end
    if cmd == "steps" or cmd == "list" then
        if not AM.route then AM.Print("No route.") return end
        for i, leg in ipairs(AM.route.legs) do
            AM.Print("%s%d. %s (%s)", i == AM.step and "> " or "", i, leg.text, AM.FormatTime(leg.cost))
        end
        return
    end
    if cmd == "minimap" then
        if AM.SetMinimapShown then AM.SetMinimapShown(not AM.db.minimap) end
        AM.Print("Minimap button %s.", AM.db.minimap and "shown" or "hidden")
        return
    end
    if cmd == "known" then
        local names = {}
        for id in pairs(AM.cdb.known) do if AM.byId[id] then names[#names + 1] = AM.byId[id].name end end
        table.sort(names)
        AM.Print("%d flight paths recorded: %s", #names, #names > 0 and table.concat(names, ", ") or "none yet. Open any flight master's map.")
        return
    end
    if cmd == "icons" then
        for _, k in ipairs({ "fly", "boat", "zeppelin" }) do
            local path = AM.ICON and AM.ICON[k] or "?"
            AM.Print("%s: |T%s:16|t %s", k, path, path:match("[^\\]+$") or path)
        end
        return
    end
    if cmd == "missing" then
        local list = AM.MissingFlights()
        if not next(AM.cdb.taxiSeen) then AM.Print("Open a flight master's map first, so AndoMaps knows which flight paths you have.") return end
        if #list == 0 then AM.Print("You have every flight path on the continents you've opened a flight map on.") return end
        local names = {}
        for i, n in ipairs(list) do names[i] = n.name .. " (" .. AM.ZoneName(n.map) .. ")" end
        AM.Print("%d flight path%s still to get: %s", #list, #list == 1 and "" or "s", table.concat(names, ", "))
        return
    end
    if cmd == "fptips reset" then
        AM.db.fpIgnore = {}
        AM.Print("Flight paths you said not to ask about will be suggested again.")
        return
    end
    if cmd == "fptips" then
        AM.db.fpTips = not AM.db.fpTips
        AM.Fire("settings")
        AM.Print("Flight path tips %s.", AM.db.fpTips and "on" or "off")
        return
    end
    if cmd == "forget" then
        AM.cdb.known, AM.cdb.taxiSeen = {}, {}
        AM.Print("Forgot recorded flight paths; all are assumed known until you open a flight map.")
        return
    end
    if cmd == "pin" then
        local d, err = AM.MapPinDest()
        if not d then AM.Print(err) return end
        AM.RouteTo(d) return
    end
    local pt, perr = ParseCoords(msg)
    if pt then AM.RouteTo(pt) return end
    if perr then AM.Print(perr) return end
    local hits = AM.Search(msg, 5)
    if #hits == 0 then AM.Print("No place or dungeon matches \"%s\".", msg) return end
    AM.RouteTo(hits[1])
    if #hits > 1 and hits[1].keys[1] ~= cmd then
        local others = {}
        for i = 2, #hits do others[#others + 1] = hits[i].label end
        AM.Print("Also matched: %s", table.concat(others, ", "))
    end
end

SLASH_ANDOMAPS1, SLASH_ANDOMAPS2 = "/am", "/andomaps"
SlashCmdList.ANDOMAPS = function(msg) AM.Slash(msg) end
if not (hash_SlashCmdList and hash_SlashCmdList["/ROUTE"]) then
    SLASH_ANDOMAPSROUTE1 = "/route"
    SlashCmdList.ANDOMAPSROUTE = function(msg) AM.Slash(msg) end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("TAXIMAP_OPENED")
ev:RegisterEvent("HEARTHSTONE_BOUND")
ev:RegisterEvent("GOSSIP_SHOW")
ev:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        AndoMapsDB = AndoMapsDB or {}
        for k, v in pairs(DEFAULTS) do if AndoMapsDB[k] == nil then AndoMapsDB[k] = v end end
        AndoMapsCharDB = AndoMapsCharDB or {}
        AndoMapsCharDB.known = AndoMapsCharDB.known or {}
        AndoMapsCharDB.taxiSeen = AndoMapsCharDB.taxiSeen or {}
        AM.db, AM.cdb = AndoMapsDB, AndoMapsCharDB
    elseif event == "PLAYER_LOGIN" then
        AM.faction = UnitFactionGroup("player") == "Horde" and "H" or "A"
        AM.InitNetwork()
        AM.BuildDestinations()
        if AM.missing > 0 then
            AM.Print("%d places have no world position on this client and were skipped.", AM.missing)
        end
        AM.Fire("login")
    elseif event == "TAXIMAP_OPENED" then
        AM.LearnTaxiMap()
        AM.AutoFly()
    elseif event == "GOSSIP_SHOW" then
        AM.AutoGossipTaxi()
    elseif event == "HEARTHSTONE_BOUND" then
        C_Timer.After(1, AM.LearnBind)
    end
end)

-- Remember the fastest ground mount speed seen, so "Auto" matches your real mount.
C_Timer.NewTicker(2, function()
    if not AM.cdb or not IsMounted or not IsMounted() then return end
    if UnitOnTaxi and UnitOnTaxi("player") then return end
    local s = GetUnitSpeed and GetUnitSpeed("player")
    if s and not issecret(s) and s > RUN_SPEED * 1.3 and s <= RUN_SPEED * 2.2 then
        if not AM.cdb.mountSpeed or s > AM.cdb.mountSpeed + 0.1 then
            AM.cdb.mountSpeed = s
            AM.Fire("settings")
        end
    end
end)
