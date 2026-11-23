-- AndoMaps UI: main window, destination search, route list, arrow, minimap button.

local _, AM = ...
local format, floor, abs, pi, cos, sin, deg, atan2 = string.format, math.floor, math.abs, math.pi, math.cos, math.sin, math.deg, math.atan2

local GOLD  = { 0.86, 0.76, 0.50 }
local SAGE  = { 0.56, 0.74, 0.58 }
local BRICK = { 0.78, 0.42, 0.38 }
local GREY  = { 0.62, 0.62, 0.62 }

local ICON = {
    walk = "Interface\\Icons\\Ability_Rogue_Sprint",
    fly = "Interface\\Icons\\Ability_Hunter_Pet_WindSerpent", -- replaced by a gryphon below when the client has one
    hearth = "Interface\\Icons\\INV_Misc_Rune_01",
    boat = "Interface\\Icons\\INV_Misc_Spyglass_03",
    zeppelin = "Interface\\Icons\\INV_Misc_Spyglass_03",
    tram = "Interface\\Icons\\INV_Gizmo_02",
    portal = "Interface\\Icons\\Spell_Arcane_PortalDarnassus",
    dungeon = "Interface\\Icons\\INV_Misc_Key_03",
    raid = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
    zone = "Interface\\Icons\\INV_Misc_Map_01",
    point = "Interface\\Icons\\INV_Misc_Map_01",
    bank = "Interface\\Icons\\INV_Misc_Bag_10",
    ah = "Interface\\Icons\\INV_Misc_Coin_01",
}
-- Flights get a gryphon and boats a ship: the first of each list the client
-- actually ships (otherwise the default above stays).
local function FirstIcon(key, paths)
    if not GetFileIDFromPath then return end
    for _, path in ipairs(paths) do
        if GetFileIDFromPath(path) then ICON[key] = path; return end
    end
end
FirstIcon("fly", {
    "Interface\\Icons\\Ability_Mount_Gryphon_01",
    "Interface\\Icons\\Ability_Mount_GoldenGryphon",
    "Interface\\Icons\\Ability_Mount_EbonGryphon",
    "Interface\\Icons\\Ability_Mount_SnowyGryphon",
    "Interface\\Icons\\Ability_Mount_SwiftRedGryphon",
    "Interface\\Icons\\INV_Misc_Head_Gryphon_01",
})
FirstIcon("boat", {
    "Interface\\Icons\\INV_Garrison_CargoShip",
    "Interface\\Icons\\Achievement_GarrisonShipyard",
    "Interface\\Icons\\Ability_Vehicle_ShipBoarding",
    "Interface\\Icons\\INV_Misc_Ship_01",
    "Interface\\Icons\\INV_Mount_Boat",
    "Interface\\Icons\\INV_Misc_Anchor",
    "Interface\\Icons\\INV_Misc_ShipWheel",
})
FirstIcon("zeppelin", {
    "Interface\\Icons\\INV_Misc_Zeppelin",
    "Interface\\Icons\\INV_Misc_Zeppelin_01",
    "Interface\\Icons\\Achievement_Zone_Zeppelin",
    "Interface\\Icons\\INV_Pet_MiniZep",
    "Interface\\Icons\\INV_Mount_GoblinZeppelin",
    "Interface\\Icons\\Ability_Vehicle_Zeppelin",
    "Interface\\Icons\\INV_Misc_Toy_Zeppelin",
})
AM.ICON = ICON
local LOGO = "Interface\\AddOns\\AndoMaps\\Media\\AndoMaps" -- the emblem, 64x64 TGA
local COMPASS = "Interface\\AddOns\\AndoMaps\\Media\\AndoMapsCompass" -- minimap icon: just the compass
local DEST_ICON = { dungeon = true, raid = true, bank = true, ah = true }
local function LegIcon(leg)
    if leg.kind == "teleport" then return leg.link and leg.link.icon or "Interface\\Icons\\Spell_Arcane_TeleportStormWind" end
    if leg.kind == "walk" and DEST_ICON[leg.to.kind] then return ICON[leg.to.kind] end
    return ICON[leg.kind] or ICON.walk
end

local UI = {}
AM.UI = UI

local function Text(parent, template, size)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
    if size then local font, _, flags = fs:GetFont(); fs:SetFont(font, size, flags) end
    return fs
end

local function Button(parent, label, w, h)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, h or 22)
    b:SetText(label)
    return b
end

---------------------------------------------------------------------------
-- Main window
---------------------------------------------------------------------------
local f = CreateFrame("Frame", "AndoMapsFrame", UIParent, "BasicFrameTemplateWithInset")
f:SetSize(390, 500)
f:SetPoint("CENTER")
f:SetFrameStrata("MEDIUM")   -- same layer as bags and character windows
f:SetToplevel(true)          -- clicking it raises it over windows in its layer
f:SetMovable(true)
f:SetClampedToScreen(true)
f:EnableMouse(true)
f:RegisterForDrag("LeftButton")
f:SetScript("OnDragStart", f.StartMoving)
f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, rel, x, y = self:GetPoint()
    AM.db.framePos = { point, rel, x, y }
end)
f:Hide()
tinsert(UISpecialFrames, "AndoMapsFrame")

-- Click-to-front with windows in other layers too. The world map sits a layer
-- above normal windows (and moves layers when OpenMap goes full screen). Clicking
-- AndoMaps lifts it to the map's layer and on top. Clicking any other window
-- drops it back to the normal layer and underneath.
local STRATA_ORDER = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5,
                       FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }

function UI.BringToFront()
    local strata = "MEDIUM"
    local wm = WorldMapFrame
    if wm and wm:IsShown() then
        local ms = wm:GetFrameStrata()
        if (STRATA_ORDER[ms] or 0) > STRATA_ORDER[strata] and ms ~= "TOOLTIP" then strata = ms end
    end
    if f:GetFrameStrata() ~= strata then f:SetFrameStrata(strata) end
    f:Raise()
end

function UI.SendToBack()
    if f:GetFrameStrata() ~= "MEDIUM" then f:SetFrameStrata("MEDIUM") end
    f:Lower()
end

local function MouseFocus()
    if GetMouseFoci then local t = GetMouseFoci(); return t and t[1] end
    return GetMouseFocus and GetMouseFocus()
end

-- Is the clicked frame AndoMaps or one of its parts? (Checks what was clicked, not
-- where: a window covering AndoMaps must not count as a click on it.)
local function IsOurs(frame)
    for _ = 1, 30 do
        if not frame then return false end
        if frame == f then return true end
        local ok, parent = pcall(frame.GetParent, frame)
        if not ok then return false end
        frame = parent
    end
    return false
end

local layering = CreateFrame("Frame")
pcall(layering.RegisterEvent, layering, "GLOBAL_MOUSE_DOWN")
layering:SetScript("OnEvent", function()
    if not f:IsShown() then return end
    local focus = MouseFocus()
    if not focus or focus == WorldFrame then return end
    if IsOurs(focus) then UI.BringToFront() else UI.SendToBack() end
end)
UI.frame = f

local title = Text(f, "GameFontHighlight")
title:SetPoint("TOP", 0, -6)
title:SetText("AndoMaps")

local input = CreateFrame("EditBox", "AndoMapsInput", f, "InputBoxTemplate")
input:SetHeight(22)
input:SetPoint("TOPLEFT", 22, -38)
input:SetPoint("TOPRIGHT", f, "TOPRIGHT", -98, -38)
input:SetAutoFocus(false)
input:SetMaxLetters(60)
local placeholder = Text(input, "GameFontDisable")
placeholder:SetPoint("LEFT", 2, 0)
placeholder:SetText("Where to? A town, zone or dungeon")

local go = Button(f, "Go", 70)
go:SetPoint("LEFT", input, "RIGHT", 8, 0)

local dungeonsBtn = Button(f, "Dungeons", 80)
dungeonsBtn:SetPoint("TOPLEFT", 16, -66)
local raidsBtn = Button(f, "Raids", 60)
raidsBtn:SetPoint("LEFT", dungeonsBtn, "RIGHT", 6, 0)
local bankBtn = Button(f, "Bank", 54)
bankBtn:SetPoint("LEFT", raidsBtn, "RIGHT", 6, 0)
local ahBtn = Button(f, "AH", 44)
ahBtn:SetPoint("LEFT", bankBtn, "RIGHT", 6, 0)
local pinBtn = Button(f, "Map pin", 72)
pinBtn:SetPoint("LEFT", ahBtn, "RIGHT", 6, 0)
local recalcBtn = Button(f, "Recalculate", 90) -- placed by Prev/Next below

local header = Text(f, "GameFontNormal")
header:SetPoint("TOPLEFT", 18, -98)
header:SetPoint("RIGHT", -18, 0)
header:SetJustifyH("LEFT")

-- Route / dungeon list
local scroll = CreateFrame("ScrollFrame", "AndoMapsScroll", f, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 12, -116)
scroll:SetPoint("BOTTOMRIGHT", -32, 128)
local child = CreateFrame("Frame", nil, scroll)
child:SetSize(scroll:GetWidth() > 0 and scroll:GetWidth() or 340, 10)
scroll:SetScrollChild(child)

local empty = Text(child, "GameFontHighlightSmall")
empty:SetPoint("TOPLEFT", 6, -6)
empty:SetPoint("RIGHT", child, "RIGHT", -6, 0)
empty:SetJustifyH("LEFT")
empty:SetSpacing(3)

local rows = {}
local function Row(i)
    local r = rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, child)
    r:SetHeight(36)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * 37)
    r:SetPoint("RIGHT", child, "RIGHT", 0, 0)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.bg:SetColorTexture(1, 1, 1, 0)
    r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(24, 24)
    r.icon:SetPoint("LEFT", 4, 0)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.num = Text(r, "GameFontNormalSmall")
    r.num:SetPoint("LEFT", r.icon, "RIGHT", 4, 0)
    r.num:SetWidth(18)
    r.time = Text(r, "GameFontHighlightSmall")
    r.time:SetPoint("RIGHT", -4, 0)
    r.time:SetJustifyH("RIGHT")
    r.text = Text(r, "GameFontHighlightSmall")
    r.text:SetPoint("LEFT", r.num, "RIGHT", 2, 0)
    r.text:SetPoint("RIGHT", r.time, "LEFT", -6, 0)
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(true)
    r.text:SetMaxLines(2)
    rows[i] = r
    return r
end

-- Footer
local prevBtn = Button(f, "< Prev", 80)
prevBtn:SetPoint("BOTTOMLEFT", 16, 96)
local nextBtn = Button(f, "Next >", 80)
nextBtn:SetPoint("LEFT", prevBtn, "RIGHT", 6, 0)
recalcBtn:SetPoint("LEFT", nextBtn, "RIGHT", 6, 0)
local clearBtn = Button(f, "Clear", 80)
clearBtn:SetPoint("BOTTOMRIGHT", -16, 96)

local status = Text(f, "GameFontHighlightSmall")
status:SetPoint("BOTTOMLEFT", 18, 76)
status:SetPoint("RIGHT", -18, 0)
status:SetJustifyH("LEFT")
status:SetTextColor(unpack(GREY))

local checks = {}
local function Check(key, label, x, y, tip)
    local cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("BOTTOMLEFT", x, y)
    local t = Text(cb, "GameFontHighlightSmall")
    t:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    t:SetText(label)
    cb:SetScript("OnClick", function(self)
        AM.db[key] = self:GetChecked() and true or false
        if key == "mapPin" and not AM.db.mapPin then AM.ClearPins() end
        if key == "mapPin" or key == "tomtom" then AM.OnStepChanged() end
        AM.Fire("settings")
        if key == "onlyKnown" or key == "useHearth" or key == "useMage" then AM.Recalculate() end
    end)
    cb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(label, 1, 1, 1)
        GameTooltip:AddLine(tip, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    cb:SetScript("OnLeave", GameTooltip_Hide)
    checks[key] = cb
end
Check("onlyKnown", "Only my flight paths", 14, 46,
      "Plan flights only between flight paths this character has discovered. Open any flight master's map once so AndoMaps can read them.")
Check("useHearth", "Hearthstone", 160, 46, "Consider hearthing home when it's faster, including waiting for the cooldown.")
Check("useMage", "Teleports", 262, 46,
      "Mages: use your city teleports (or portals) when they're faster. Needs a Rune of Teleportation in your bags.")
checks.useMage:Hide() -- shown for mages once the character has loaded
Check("arrow", "Arrow", 14, 20, "Show the on-screen arrow pointing at the next stop.")
Check("mapPin", "Map pin", 90, 20, "Put the game's map pin on the next stop. This replaces any pin you placed yourself.")
Check("autoFly", "Auto-fly", 176, 20,
      "When the next step is a flight, talking to a flight master takes that flight for you. Hold Shift while talking to skip it.")

local speedBtn = Button(f, "", 112)
speedBtn:SetPoint("BOTTOMRIGHT", -16, 20)
local SPEEDS = { "auto", "walk", "mount60", "mount100" }
speedBtn:SetScript("OnClick", function()
    local i = 1
    for k, v in ipairs(SPEEDS) do if v == AM.db.speed then i = k end end
    AM.db.speed = SPEEDS[i % #SPEEDS + 1]
    AM.Fire("settings")
    AM.Recalculate()
end)
speedBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Ground speed", 1, 1, 1)
    GameTooltip:AddLine("Used to time the walking parts. Auto uses the fastest mount speed it has seen you ride.", nil, nil, nil, true)
    GameTooltip:Show()
end)
speedBtn:SetScript("OnLeave", GameTooltip_Hide)

---------------------------------------------------------------------------
-- Suggestions dropdown
---------------------------------------------------------------------------
local suggest = CreateFrame("Frame", nil, f, "BackdropTemplate")
suggest:SetPoint("TOPLEFT", input, "BOTTOMLEFT", -8, -2)
suggest:SetPoint("TOPRIGHT", go, "BOTTOMRIGHT", 4, -2)
suggest:SetFrameStrata("FULLSCREEN_DIALOG")
suggest:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
                      insets = { left = 3, right = 3, top = 3, bottom = 3 } })
suggest:SetBackdropColor(0.06, 0.06, 0.07, 0.96)
suggest:Hide()

local sButtons, sItems, sSel = {}, {}, 1
for i = 1, 8 do
    local b = CreateFrame("Button", nil, suggest)
    b:SetHeight(20)
    b:SetPoint("TOPLEFT", 6, -5 - (i - 1) * 20)
    b:SetPoint("RIGHT", suggest, "RIGHT", -6, 0)
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    b.sel = b:CreateTexture(nil, "BACKGROUND")
    b.sel:SetAllPoints()
    b.sel:SetColorTexture(0.86, 0.76, 0.5, 0.18)
    b.label = Text(b, "GameFontHighlightSmall")
    b.label:SetPoint("LEFT", 4, 0)
    b.sub = Text(b, "GameFontDisableSmall")
    b.sub:SetPoint("RIGHT", -4, 0)
    b.label:SetPoint("RIGHT", b.sub, "LEFT", -6, 0)
    b.label:SetJustifyH("LEFT")
    b:SetScript("OnClick", function(self) UI.Choose(sItems[self.index]) end)
    b.index = i
    sButtons[i] = b
end

local function ShowSuggestions(items)
    sItems, sSel = items, 1
    if #items == 0 then suggest:Hide() return end
    for i, b in ipairs(sButtons) do
        local d = items[i]
        if d then
            b.label:SetText(d.label)
            b.sub:SetText(d.sub or "")
            b.sel:SetShown(i == sSel)
            b:Show()
        else
            b:Hide()
        end
    end
    suggest:SetHeight(10 + 20 * math.min(#items, #sButtons))
    suggest:Show()
end

function UI.UpdateSuggest(text)
    placeholder:SetShown(text == "")
    ShowSuggestions(AM.Search(text, 8))
end

function UI.Choose(d)
    if not d then return end
    suggest:Hide()
    input:SetText(d.label)
    input:ClearFocus()
    placeholder:Hide()
    UI.mode = "route"
    AM.RouteTo(d)
    UI.Refresh()
end

input:SetScript("OnTextChanged", function(self, user)
    placeholder:SetShown(self:GetText() == "")
    if user then UI.UpdateSuggest(self:GetText()) end
end)
input:SetScript("OnEditFocusGained", function(self) placeholder:Hide() end)
input:SetScript("OnEditFocusLost", function(self)
    placeholder:SetShown(self:GetText() == "")
    C_Timer.After(0.2, function() if not input:HasFocus() then suggest:Hide() end end)
end)
input:SetScript("OnEscapePressed", function(self) self:ClearFocus(); suggest:Hide() end)
input:SetScript("OnArrowPressed", function(_, key)
    if not suggest:IsShown() then return end
    if key == "DOWN" then sSel = math.min(#sItems, sSel + 1) elseif key == "UP" then sSel = math.max(1, sSel - 1) end
    for i, b in ipairs(sButtons) do b.sel:SetShown(i == sSel) end
end)
input:SetScript("OnEnterPressed", function(self)
    local text = self:GetText()
    if suggest:IsShown() and sItems[sSel] then UI.Choose(sItems[sSel]) return end
    self:ClearFocus()
    if text ~= "" then AM.Slash(text); UI.mode = "route"; UI.Refresh() end
end)
go:SetScript("OnClick", function()
    local text = input:GetText()
    if suggest:IsShown() and sItems[sSel] then UI.Choose(sItems[sSel]) return end
    if text ~= "" then AM.Slash(text); UI.mode = "route"; UI.Refresh() end
end)

local function ListMode(mode)
    UI.mode = UI.mode == mode and "route" or mode
    suggest:Hide()
    UI.Refresh()
end
dungeonsBtn:SetScript("OnClick", function() ListMode("dungeons") end)
raidsBtn:SetScript("OnClick", function() ListMode("raids") end)

local function GoNearest(kind)
    local d = AM.NearestDest(kind)
    if not d then return end
    UI.mode = "route"
    suggest:Hide()
    input:SetText("")
    placeholder:Show()
    AM.RouteTo(d)
    UI.Refresh()
end
bankBtn:SetScript("OnClick", function() GoNearest("bank") end)
ahBtn:SetScript("OnClick", function() GoNearest("ah") end)
local function Tip(btn, text)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(text, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", GameTooltip_Hide)
end
Tip(bankBtn, "Route to the nearest bank of your faction (or a neutral one).")
Tip(ahBtn, "Route to the nearest auction house of your faction (or a neutral one).")
Tip(pinBtn, "Route to your world-map pin.")
pinBtn:SetScript("OnClick", function()
    local d, err = AM.MapPinDest()
    if not d then AM.Print(err) return end
    UI.mode = "route"
    input:SetText("")
    placeholder:Show()
    AM.RouteTo(d)
    UI.Refresh()
end)
recalcBtn:SetScript("OnClick", function()
    if not AM.Recalculate() then AM.Print("Pick a destination first.") end
end)
prevBtn:SetScript("OnClick", function() AM.SetStep(AM.step - 1) end)
nextBtn:SetScript("OnClick", function() AM.SetStep(AM.step + 1) end)
clearBtn:SetScript("OnClick", function()
    AM.Clear()
    input:SetText("")
    placeholder:Show()
end)

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------
local function HearthStatus()
    if not AM.db.useHearth then return "Hearthstone: not used" end
    local node, wait = AM.HearthInfo()
    if not node then
        local _, why = AM.HearthInfo()
        return "Hearthstone: " .. (why or "unavailable")
    end
    return format("Hearthstone: %s (%s)", node.name, wait > 0 and AM.FormatTime(wait) .. " cooldown" or "ready")
end

local function FlightStatus()
    local n = 0
    for _ in pairs(AM.cdb.known) do n = n + 1 end
    if not AM.db.onlyKnown then return "all flight paths assumed" end
    if n == 0 then return "flight paths not read yet" end
    local missing = #AM.MissingFlights()
    if missing > 0 then return format("%d flight paths known, %d to get (/am missing)", n, missing) end
    return n .. " flight paths known"
end

---------------------------------------------------------------------------
-- "Get this flight path?" popup: shown when a route would be noticeably
-- quicker with a flight path you don't have yet.
---------------------------------------------------------------------------
StaticPopupDialogs["ANDOMAPS_GET_FLIGHT_PATH"] = {
    text = "|cffdcc280AndoMaps|r\n\n%s",
    button1 = "Go get it",
    button2 = "Not now",
    button3 = "Don't ask again",
    OnAccept = function(_, data)
        local n = data and data.nodes[1]
        if not n then return end
        AM.RouteTo({ label = n.name, kind = "flight", nodes = { n } })
        if f:IsShown() then UI.Refresh() end
    end,
    OnAlt = function(_, data)
        if not data then return end
        AM.db.fpIgnore = AM.db.fpIgnore or {}
        for _, n in ipairs(data.nodes) do AM.db.fpIgnore[n.id] = true end
        AM.Print("Won't suggest %s again. /am fptips reset brings these suggestions back.", data.names)
    end,
    timeout = 0,
    whileDead = false,
    hideOnEscape = true,
    preferredIndex = 3,
}

function AM.ShowFlightTip(r)
    if not StaticPopup_Show then return false end
    local tip = r.tip
    local text = format("You don't have the %s flight path%s yet.\n\nWith %s, this trip would take %s instead of %s.\n\nDo you want to go get %s now so your next trips are faster?",
        tip.names, #tip.nodes == 1 and "" or "s", #tip.nodes == 1 and "it" or "them",
        AM.FormatTime(tip.total), AM.FormatTime(r.total), #tip.nodes == 1 and "it" or "them")
    local dialog = StaticPopup_Show("ANDOMAPS_GET_FLIGHT_PATH", text)
    if not dialog then return false end
    dialog.data = tip
    return true
end

function UI.Refresh()
    if not AM.db then return end
    for key, cb in pairs(checks) do cb:SetChecked(AM.db[key] and true or false) end
    speedBtn:SetText(AM.SpeedLabel())
    checks.useMage:SetShown(AM.HasTeleports())
    local s = HearthStatus() .. "  -  " .. FlightStatus()
    if AM.db.useMage and AM.HasTeleports() then s = s .. "  -  " .. #AM.MageTeleports() .. " teleports ready" end
    status:SetText(s)
    dungeonsBtn:SetText(UI.mode == "dungeons" and "Route" or "Dungeons")
    raidsBtn:SetText(UI.mode == "raids" and "Route" or "Raids")
    for _, r in ipairs(rows) do r:Hide() end
    empty:Hide()

    local route = AM.route
    prevBtn:SetEnabled(route and AM.step > 1 or false)
    nextBtn:SetEnabled(route and AM.step < #route.legs or false)
    clearBtn:SetEnabled(route and true or false)
    recalcBtn:SetEnabled(AM.dest and true or false)

    if UI.mode == "dungeons" or UI.mode == "raids" then
        local raids = UI.mode == "raids"
        header:SetText(raids and "Raids" or "Dungeons")
        header:SetTextColor(unpack(GOLD))
        local list = AM.Dungeons(raids and "raid" or "dungeon")
        for i, d in ipairs(list) do
            local r = Row(i)
            r.icon:SetTexture(ICON[d.kind])
            r.num:SetText("")
            r.text:SetText(d.label .. "\n|cff9a9a9a" .. AM.ZoneName(d.map) .. "|r")
            r.time:SetText(d.level or "")
            r.time:SetTextColor(unpack(GREY))
            r.text:SetTextColor(1, 1, 1)
            r.bg:SetColorTexture(1, 1, 1, 0)
            r:SetScript("OnClick", function() input:SetText(d.label); placeholder:Hide(); UI.Choose(d) end)
            r:Show()
        end
        child:SetHeight(#list * 37)
        return
    end

    if not route then
        header:SetText("No route")
        header:SetTextColor(unpack(GREY))
        local tips = "Type a town, zone, flight path or dungeon above (\"Gadgetzan\", \"BRD\", \"Duskwood\"), or press Dungeons or Raids.\n\nBank and AH route to the nearest bank or auction house (or type \"bank\" / \"ah\").\n\n" ..
                     "Coordinates work too: /am 45 60 Tanaris. /am pin routes to your world-map pin.\n\n" ..
                     "Follow the arrow; steps tick off as you reach them."
        if AM.db.onlyKnown and not next(AM.cdb.known) then
            tips = tips .. "\n\n|cffdcc280Open a flight master's map once so AndoMaps knows which flight paths you have. Until then it assumes you have them all.|r"
        end
        empty:SetText(tips)
        empty:Show()
        child:SetHeight(200)
        return
    end

    header:SetText(format("To %s - %s", route.name, AM.FormatTime(AM.RemainingTime())))
    header:SetTextColor(unpack(GOLD))
    for i, leg in ipairs(route.legs) do
        local r = Row(i)
        r.icon:SetTexture(LegIcon(leg))
        r.num:SetText(i .. ".")
        r.text:SetText(leg.text)
        r.time:SetText(AM.FormatTime(leg.cost))
        if i < AM.step then
            r.text:SetTextColor(unpack(GREY)); r.time:SetTextColor(unpack(GREY)); r.icon:SetDesaturated(true)
            r.bg:SetColorTexture(1, 1, 1, 0)
        elseif i == AM.step then
            r.text:SetTextColor(unpack(GOLD)); r.time:SetTextColor(unpack(GOLD)); r.icon:SetDesaturated(false)
            r.bg:SetColorTexture(0.86, 0.76, 0.5, 0.12)
        else
            r.text:SetTextColor(0.92, 0.92, 0.92); r.time:SetTextColor(0.8, 0.8, 0.8); r.icon:SetDesaturated(false)
            r.bg:SetColorTexture(1, 1, 1, 0)
        end
        r:SetScript("OnClick", function() AM.SetStep(i) end)
        r:Show()
    end
    local rowsShown = #route.legs
    if route.tip then
        -- "Get this flight path": the trip would be quicker with it. Click to go there.
        rowsShown = rowsShown + 1
        local tip, r = route.tip, Row(rowsShown)
        r.icon:SetTexture(ICON.fly)
        r.icon:SetDesaturated(false)
        r.num:SetText("")
        r.text:SetText(format("Get the %s flight path for faster routes next time", tip.names))
        r.text:SetTextColor(0.86, 0.76, 0.5)
        r.time:SetText("-" .. AM.FormatTime(tip.saved))
        r.time:SetTextColor(0.6, 0.75, 0.55)
        r.bg:SetColorTexture(0.86, 0.76, 0.5, 0.06)
        r:SetScript("OnClick", function()
            local n = tip.nodes[1]
            AM.RouteTo({ label = n.name, kind = "flight", nodes = { n } })
        end)
        r:Show()
    end
    child:SetHeight(rowsShown * 37)
end

f:SetScript("OnShow", function() UI.BringToFront(); UI.Refresh() end)

-- Resizing: drag the grip in the bottom-right corner.
f:SetResizable(true)
if f.SetResizeBounds then
    f:SetResizeBounds(380, 440, 900, 1100)
elseif f.SetMinResize then
    f:SetMinResize(380, 440); f:SetMaxResize(900, 1100)
end
local grip = CreateFrame("Button", nil, f)
grip:SetSize(16, 16)
grip:SetPoint("BOTTOMRIGHT", -3, 3)
grip:SetFrameLevel(f:GetFrameLevel() + 10)
grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
grip:SetScript("OnMouseDown", function(_, button)
    if button == "LeftButton" then f:StartSizing("BOTTOMRIGHT") end
end)
grip:SetScript("OnMouseUp", function()
    f:StopMovingOrSizing()
    AM.db.frameSize = { f:GetWidth(), f:GetHeight() }
    local point, _, rel, x, y = f:GetPoint()
    AM.db.framePos = { point, rel, x, y }
end)
grip:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Drag to resize", 1, 1, 1)
    GameTooltip:Show()
end)
grip:SetScript("OnLeave", GameTooltip_Hide)
-- the scroll child has no anchors of its own: keep it as wide as the scroll area
scroll:SetScript("OnSizeChanged", function(self, w) if w and w > 0 then child:SetWidth(w) end end)

function AM.ToggleUI()
    if f:IsShown() then f:Hide() else f:Show(); input:SetFocus() end
end

---------------------------------------------------------------------------
-- Arrow
---------------------------------------------------------------------------
local A = CreateFrame("Button", "AndoMapsArrow", UIParent)
A:SetSize(220, 96)
A:SetPoint("TOP", 0, -140)
A:SetMovable(true)
A:SetClampedToScreen(true)
A:RegisterForDrag("LeftButton")
A:RegisterForClicks("RightButtonUp", "LeftButtonUp")
A:SetScript("OnDragStart", A.StartMoving)
A:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, rel, x, y = self:GetPoint()
    AM.db.arrowPos = { point, rel, x, y }
end)
A:SetScript("OnClick", function(_, button) if button == "RightButton" then AM.ToggleUI() end end)
A:Hide()

A.arrow = A:CreateTexture(nil, "ARTWORK")
A.arrow:SetSize(52, 52)
A.arrow:SetPoint("TOP", 0, 0)
A.arrow:SetTexture("Interface\\Minimap\\MinimapArrow")
A.icon = A:CreateTexture(nil, "ARTWORK")
A.icon:SetSize(34, 34)
A.icon:SetPoint("TOP", 0, -8)
A.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
A.text = Text(A, "GameFontHighlight", 13)
A.text:SetPoint("TOP", 0, -56)
A.text:SetWidth(260)
A.text:SetShadowOffset(1, -1)
A.sub = Text(A, "GameFontHighlightSmall")
A.sub:SetPoint("TOP", A.text, "BOTTOM", 0, -2)
A.sub:SetTextColor(0.8, 0.8, 0.8)
A.sub:SetShadowOffset(1, -1)

A:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText("AndoMaps", 1, 1, 1)
    GameTooltip:AddLine("Drag to move. Right-click to open the route.", nil, nil, nil, true)
    GameTooltip:Show()
end)
A:SetScript("OnLeave", GameTooltip_Hide)

local acc, refreshAcc = 0, 0
A:SetScript("OnUpdate", function(self, elapsed)
    acc = acc + elapsed
    if acc < 0.05 then return end
    refreshAcc = refreshAcc + acc
    acc = 0
    local leg = AM.CurrentLeg()
    if not leg then return end
    local n, i = #AM.route.legs, AM.step
    local remaining = AM.FormatTime(AM.RemainingTime())
    if UnitOnTaxi and UnitOnTaxi("player") then
        self.arrow:Hide(); self.icon:Show(); self.icon:SetTexture(ICON.fly)
        self.text:SetText(leg.kind == "fly" and ("In flight to " .. leg.to.name) or "In flight")
        self.text:SetTextColor(unpack(GOLD))
        self.sub:SetText(format("Step %d/%d - %s left", i, n, remaining))
    elseif leg.kind ~= "walk" then
        self.arrow:Hide(); self.icon:Show(); self.icon:SetTexture(LegIcon(leg))
        self.text:SetText(leg.text)
        self.text:SetTextColor(unpack(GOLD))
        self.sub:SetText(format("Step %d/%d - %s left", i, n, remaining))
    else
        self.icon:Hide()
        local rel, d, why = AM.Bearing()
        if rel then
            self.arrow:Show()
            self.arrow:SetRotation(rel)
            local off = rel > pi and (2 * pi - rel) or rel
            if off < 0.35 then self.arrow:SetVertexColor(unpack(SAGE))
            elseif off < 2.2 then self.arrow:SetVertexColor(unpack(GOLD))
            else self.arrow:SetVertexColor(unpack(BRICK)) end
        else
            self.arrow:Hide()
        end
        self.text:SetText(leg.text)
        self.text:SetTextColor(1, 1, 1)
        if d then
            self.sub:SetText(format("%d yd - step %d/%d - %s left", floor(d), i, n, remaining))
        else
            self.sub:SetText(format("%s - step %d/%d", why == "other continent" and "On another continent" or "Position unavailable", i, n))
        end
    end
    if refreshAcc > 1 then
        refreshAcc = 0
        if f:IsShown() and AM.route then
            header:SetText(format("To %s - %s", AM.route.name, AM.FormatTime(AM.RemainingTime())))
        end
    end
end)

-- Arrival checks run whether or not the arrow is shown.
C_Timer.NewTicker(0.25, function()
    if AM.route then AM.Tick() end
end)

local function UpdateArrowVisibility()
    A:SetShown(AM.db and AM.db.arrow and AM.route and true or false)
end


---------------------------------------------------------------------------
-- Minimap button: LibDBIcon when another addon ships it (Details does), so it
-- follows the minimap's shape and any button collector; otherwise our own.
---------------------------------------------------------------------------
local function ShowTooltip(tt)
    tt:AddLine("AndoMaps", 1, 1, 1)
    if AM.route then
        local leg = AM.CurrentLeg()
        tt:AddLine(format("To %s - %s left", AM.route.name, AM.FormatTime(AM.RemainingTime())), unpack(GOLD))
        if leg then tt:AddLine(leg.text, 1, 1, 1, true) end
    end
    tt:AddLine("Left-click: open. Right-click: toggle arrow.", 0.7, 0.7, 0.7, true)
end

local function LauncherClick(button)
    if button == "RightButton" then
        AM.db.arrow = not AM.db.arrow
        AM.Fire("settings")
        AM.Print("Arrow %s.", AM.db.arrow and "on" or "off")
    else
        AM.ToggleUI()
    end
end

-- Addon compartment (the addons menu button by the minimap)
function AndoMaps_OnAddonCompartmentClick(_, button) LauncherClick(button) end
function AndoMaps_OnAddonCompartmentEnter(_, frame)
    GameTooltip:SetOwner(frame, "ANCHOR_LEFT")
    ShowTooltip(GameTooltip)
    GameTooltip:Show()
end
function AndoMaps_OnAddonCompartmentLeave() GameTooltip:Hide() end

local mb = CreateFrame("Button", "AndoMapsMinimapButton", Minimap)
mb:SetSize(31, 31)
mb:SetFrameStrata("MEDIUM")
mb:SetFrameLevel(8)
mb:RegisterForClicks("LeftButtonUp", "RightButtonUp")
mb:RegisterForDrag("LeftButton")
mb:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
local mbIcon = mb:CreateTexture(nil, "BACKGROUND")
mbIcon:SetTexture(COMPASS)
mbIcon:SetSize(20, 20)
mbIcon:SetPoint("TOPLEFT", 7, -5)
local mbBorder = mb:CreateTexture(nil, "OVERLAY")
mbBorder:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
mbBorder:SetSize(53, 53)
mbBorder:SetPoint("TOPLEFT")
mb:Hide()

local function PlaceOwnButton()
    local a = math.rad(AM.db.minimapAngle or 215)
    local r = (Minimap:GetWidth() or 140) / 2 + 10   -- just outside the rim, whatever the minimap's size
    mb:ClearAllPoints()
    mb:SetPoint("CENTER", Minimap, "CENTER", cos(a) * r, sin(a) * r)
    mb:SetShown(AM.db.minimap)
end

mb:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
        local mx, my = Minimap:GetCenter()
        local cx, cy = GetCursorPosition()
        local s = Minimap:GetEffectiveScale()
        AM.db.minimapAngle = deg(atan2(cy / s - my, cx / s - mx))
        PlaceOwnButton()
    end)
end)
mb:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
mb:SetScript("OnClick", function(_, button) LauncherClick(button) end)
mb:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    ShowTooltip(GameTooltip)
    GameTooltip:Show()
end)
mb:SetScript("OnLeave", GameTooltip_Hide)

local dbi
local function SetupMinimap()
    local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
    dbi = dbi or (LibStub and LibStub("LibDBIcon-1.0", true))
    if LDB and dbi then
        local obj = LDB:GetDataObjectByName("AndoMaps") or LDB:NewDataObject("AndoMaps", {
            type = "launcher", text = "AndoMaps", icon = COMPASS,
            OnClick = function(_, button) LauncherClick(button) end,
            OnTooltipShow = ShowTooltip,
        })
        AM.db.minimapIcon = AM.db.minimapIcon or { minimapPos = AM.db.minimapAngle or 215 }
        AM.db.minimapIcon.hide = not AM.db.minimap
        if not dbi:IsRegistered("AndoMaps") then dbi:Register("AndoMaps", obj, AM.db.minimapIcon) end
        if AM.db.minimap then dbi:Show("AndoMaps") else dbi:Hide("AndoMaps") end
        mb:Hide()
    else
        PlaceOwnButton()
    end
end

function AM.SetMinimapShown(show)
    AM.db.minimap = show and true or false
    SetupMinimap()
end

---------------------------------------------------------------------------
-- World map: a button in the map's bottom-right corner, and Alt+click on the
-- map to route to that spot. Works with OpenMap's stitched map too.
---------------------------------------------------------------------------
local mapBtn

-- A map point (0..1) as a destination, narrowed down to the zone under it.
function AM.SpotDest(mapID, x, y)
    local cont, wx, wy = AM.WorldPos(mapID, x, y)
    if not cont then return nil, "That spot has no world position." end
    local m, mx, my = mapID, x, y
    for _ = 1, 4 do
        local info = C_Map.GetMapInfo(m)
        if info and info.mapType and info.mapType >= 3 then break end -- already a zone or city
        local sub = C_Map.GetMapInfoAtPosition and C_Map.GetMapInfoAtPosition(m, mx, my)
        if not sub or not sub.mapID or sub.mapID == m then break end
        local ok, _, pos = pcall(C_Map.GetMapPosFromWorldPos, cont, CreateVector2D(wx, wy), sub.mapID)
        if not ok or not pos then break end
        m, mx, my = sub.mapID, pos.x, pos.y
    end
    return { goal = { pos = { map = m, x = mx * 100, y = my * 100 },
                      name = format("%s %.1f, %.1f", AM.ZoneName(m), mx * 100, my * 100) },
             label = "Map spot", kind = "point" }
end

local function CursorSpot()
    local wm = WorldMapFrame
    local api = OpenMapAPI
    if api and api.IsStitched and api.IsStitched() then
        local u, v = api.CursorPosition()
        local zone = u and api.MapAt(u, v)
        local x, y
        if zone then x, y = api.MapFromWorld(zone, u, v) end
        if x then return AM.SpotDest(zone, x, y) end
    end
    local id = wm:GetMapID()
    local x, y = wm.ScrollContainer:GetNormalizedCursorPosition()
    if id and x and x >= 0 and x <= 1 and y >= 0 and y <= 1 then return AM.SpotDest(id, x, y) end
    return nil, "Could not read that spot on the map."
end

local function CreateMapButton()
    local wm = WorldMapFrame
    if mapBtn or not wm or not wm.ScrollContainer then return end
    local sc = wm.ScrollContainer
    mapBtn = CreateFrame("Button", "AndoMapsWorldMapButton", sc)
    mapBtn:SetSize(36, 36)
    -- Top-right corner, tucked under any of Blizzard's own map buttons that sit there.
    local function PlaceMapButton()
        local y = -10
        local scTop = sc:GetTop()
        local scRight = sc:GetRight()
        if scTop and scRight then
            for _, of in ipairs(wm.overlayFrames or {}) do
                local r, b = of:IsShown() and of:GetRight(), of:GetBottom()
                if r and b and scRight - r < 90 and scTop - b < 120 and scTop - b > 0 then
                    y = math.min(y, -(scTop - b) - 4)
                end
            end
        end
        mapBtn:ClearAllPoints()
        mapBtn:SetPoint("TOPRIGHT", sc, "TOPRIGHT", -10, y)
    end
    PlaceMapButton()
    wm:HookScript("OnShow", function() C_Timer.After(0, PlaceMapButton) end)
    local top = OpenMapAPI and OpenMapAPI.ArtTopLevel and OpenMapAPI.ArtTopLevel()
    mapBtn:SetFrameLevel(math.max((top or 0) + 20, sc:GetFrameLevel() + 50))
    mapBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local icon = mapBtn:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(LOGO)
    icon:SetSize(26, 26)
    icon:SetPoint("CENTER")
    local ring = mapBtn:CreateTexture(nil, "OVERLAY")
    ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    ring:SetSize(60, 60)
    ring:SetPoint("TOPLEFT", -2, 1)
    mapBtn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    -- "Route here" picker: a see-through layer over the map that catches one click.
    -- The mouse wheel still reaches the map, so you can zoom while picking.
    local pick = CreateFrame("Frame", "AndoMapsPickLayer", sc)
    pick:SetAllPoints(sc)
    pick:SetFrameLevel(mapBtn:GetFrameLevel() - 1)
    pick:EnableMouse(true)
    pick:EnableMouseWheel(false)
    pick:Hide()
    local tint = pick:CreateTexture(nil, "BACKGROUND")
    tint:SetAllPoints()
    tint:SetColorTexture(0.86, 0.76, 0.5, 0.06)
    local banner = CreateFrame("Frame", nil, pick, "BackdropTemplate")
    banner:SetPoint("TOP", 0, -12)
    banner:SetSize(360, 30)
    banner:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                         edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
                         insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    banner:SetBackdropColor(0.06, 0.06, 0.07, 0.92)
    local bannerText = Text(banner, "GameFontHighlight")
    bannerText:SetPoint("CENTER")
    bannerText:SetText("Click where you want to go  -  right-click to cancel")
    bannerText:SetTextColor(unpack(GOLD))

    local function StopPicking()
        pick:Hide()
        UI.picking = false
        pcall(ResetCursor)
    end
    local function StartPicking()
        UI.picking = true
        pick:Show()
    end
    UI.StopPicking = StopPicking

    pick:SetScript("OnUpdate", function(self)
        if self:IsMouseOver() then pcall(SetCursor, "CAST_CURSOR") end
    end)
    pick:SetScript("OnMouseUp", function(_, button)
        if button ~= "LeftButton" then StopPicking() return end
        local d, err = CursorSpot()
        StopPicking()
        if not d then AM.Print(err) return end
        AM.RouteTo(d)
    end)
    pick:SetScript("OnHide", function() UI.picking = false; pcall(ResetCursor) end)
    wm:HookScript("OnHide", StopPicking)

    mapBtn:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            StopPicking()
            AM.ToggleUI()
        elseif UI.picking then
            StopPicking()
        else
            StartPicking()
        end
    end)
    mapBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("AndoMaps", 1, 1, 1)
        if AM.route then
            GameTooltip:AddLine(format("To %s - %s left", AM.route.name, AM.FormatTime(AM.RemainingTime())), unpack(GOLD))
        end
        GameTooltip:AddLine("Left-click, then click the map: route there.", 0.85, 0.85, 0.85, true)
        GameTooltip:AddLine("Or Alt+click anywhere on the map.", 0.85, 0.85, 0.85, true)
        GameTooltip:AddLine("Right-click: open the AndoMaps window.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    mapBtn:SetScript("OnLeave", GameTooltip_Hide)
end

local clicker = CreateFrame("Frame")
pcall(clicker.RegisterEvent, clicker, "GLOBAL_MOUSE_UP")
clicker:RegisterEvent("ADDON_LOADED")
clicker:SetScript("OnEvent", function(_, event, arg)
    if event == "ADDON_LOADED" then
        if arg == "Blizzard_WorldMap" and AM.db then CreateMapButton() end
        return
    end
    if arg ~= "LeftButton" or not IsAltKeyDown() or not AM.db or UI.picking then return end
    local wm = WorldMapFrame
    if not (wm and wm:IsShown() and wm.ScrollContainer and wm.ScrollContainer:IsMouseOver()) then return end
    if mapBtn and mapBtn:IsMouseOver() then return end
    local d, err = CursorSpot()
    if not d then AM.Print(err) return end
    AM.RouteTo(d)
end)

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------
table.insert(AM.callbacks, function(event)
    if event == "login" then
        if AM.db.frameSize then
            f:SetSize(math.max(380, AM.db.frameSize[1]), math.max(440, AM.db.frameSize[2]))
        end
        if AM.db.framePos then
            local p = AM.db.framePos
            f:ClearAllPoints(); f:SetPoint(p[1], UIParent, p[2] or p[1], p[3], p[4])
        end
        if AM.db.arrowPos then
            local p = AM.db.arrowPos
            A:ClearAllPoints(); A:SetPoint(p[1], UIParent, p[2] or p[1], p[3], p[4])
        end
        SetupMinimap()
        CreateMapButton()
    end
    UpdateArrowVisibility()
    if f:IsShown() then UI.Refresh() end
end)
