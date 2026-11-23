-- AndoMaps travel network.
--
-- Flight master, innkeeper and dungeon entrance positions come from QuestieDB's
-- Forever data (Forever-adjusted coordinates, e.g. the reworked Stormwind).
-- Zone border crossings, docks and zeppelin towers are hand-placed estimates:
-- those are the lines to tune if a route walks you somewhere odd.
--
-- Node:  N(id, kind, uiMapID, x, y, name, opts)
--   kind  : flight | inn | dungeon | raid | border | dock | tram | portal | hub
--   opts  : faction "A"/"H" (nil = both), zones {extra uiMapIDs this point sits on},
--           noZone (never auto-walk-linked), area (isolated pocket inside a zone),
--           taxi (flight map name, first part before the comma), bind {hearth names},
--           dest (group key for multi-entrance destinations), aliases, level, note
-- Link:  L(a, b, kind, seconds, opts)   two-way unless opts.oneway
--   seconds nil = walking time from the distance.

local _, AM = ...

local nodes, links = {}, {}
AM.nodes, AM.links = nodes, links

local function N(id, kind, map, x, y, name, o)
    o = o or {}
    o.id, o.kind, o.map, o.x, o.y, o.name = id, kind, map, x, y, name
    nodes[#nodes + 1] = o
end
local function L(a, b, kind, seconds, o)
    o = o or {}
    o.a, o.b, o.kind, o.cost = a, b, kind, seconds
    links[#links + 1] = o
end

-- Eastern Kingdoms
local ELW, WF, RR, DW, STV, DP, SOS, BL = 1429, 1436, 1433, 1431, 1434, 1430, 1435, 1419
local BS, SG, LM, DM, WL, AH, HB, ALT = 1428, 1427, 1432, 1426, 1437, 1417, 1424, 1416
local HL, SP, TG, WPL, EPL, BAD = 1425, 1421, 1420, 1422, 1423, 1418
local SW, IF, UC = 1453, 1455, 1458
-- Kalimdor
local DUR, MUL, BAR, TEL, DS, ASH, TN, STM = 1411, 1412, 1413, 1438, 1439, 1440, 1441, 1442
local DES, FER, DWM, TAN, AZ, FW, UNG, MG = 1443, 1444, 1445, 1446, 1447, 1448, 1449, 1450
local SIL, WS, ORG, TB, DAR = 1451, 1452, 1454, 1456, 1457
-- Forever's new zones
local HYJ, ZEP, RVG, SHD = 2482, 2521, 2548, 2652

---------------------------------------------------------------------------
-- Flight masters (QuestieDB Forever)
---------------------------------------------------------------------------
-- Eastern Kingdoms, Alliance
N("fp_stormwind",   "flight", SW,  71.29, 72.23, "Stormwind",            {faction="A"})
N("fp_sentinel",    "flight", WF,  56.55, 52.64, "Sentinel Hill",        {faction="A"})
N("fp_lakeshire",   "flight", RR,  25.50, 59.41, "Lakeshire",            {faction="A"})
N("fp_menethil",    "flight", WL,   9.49, 59.69, "Menethil Harbor",      {faction="A"})
N("fp_thelsamar",   "flight", LM,  33.94, 50.95, "Thelsamar",            {faction="A"})
N("fp_ironforge",   "flight", IF,  55.50, 47.74, "Ironforge",            {faction="A"})
N("fp_morgans",     "flight", BS,  84.33, 68.33, "Morgan's Vigil",       {faction="A"})
N("fp_darkshire",   "flight", DW,  77.49, 44.29, "Darkshire",            {faction="A"})
N("fp_southshore",  "flight", HB,  49.34, 52.27, "Southshore",           {faction="A"})
N("fp_refuge",      "flight", AH,  45.73, 46.10, "Refuge Pointe",        {faction="A"})
N("fp_bootybay_a",  "flight", STV, 27.53, 77.79, "Booty Bay",            {faction="A"})
N("fp_thorium_a",   "flight", SG,  37.94, 30.86, "Thorium Point",        {faction="A"})
N("fp_aerie",       "flight", HL,  11.07, 46.15, "Aerie Peak",           {faction="A"})
N("fp_nethergarde", "flight", BL,  65.54, 24.34, "Nethergarde Keep",     {faction="A"})
N("fp_chillwind",   "flight", WPL, 42.92, 85.06, "Chillwind Camp",       {faction="A"})
N("fp_lightshope_a","flight", EPL, 71.81, 49.60, "Light's Hope Chapel",  {faction="A"})
-- Eastern Kingdoms, Horde
N("fp_undercity",   "flight", UC,  63.25, 48.56, "Undercity",            {faction="H"})
N("fp_sepulcher",   "flight", SP,  45.62, 42.60, "The Sepulcher",        {faction="H"})
N("fp_tarrenmill",  "flight", HB,  60.14, 18.62, "Tarren Mill",          {faction="H"})
N("fp_hammerfall",  "flight", AH,  73.02, 32.70, "Hammerfall",           {faction="H"})
N("fp_gromgol",     "flight", STV, 32.54, 29.35, "Grom'gol",             {faction="H", bind={"Grom'gol Base Camp"}})
N("fp_bootybay_h",  "flight", STV, 26.87, 77.10, "Booty Bay",            {faction="H"})
N("fp_kargath",     "flight", BAD,  3.99, 44.78, "Kargath",              {faction="H"})
N("fp_thorium_h",   "flight", SG,  34.84, 30.87, "Thorium Point",        {faction="H"})
N("fp_revantusk",   "flight", HL,  81.70, 81.76, "Revantusk Village",    {faction="H"})
N("fp_stonard",     "flight", SOS, 46.07, 54.83, "Stonard",              {faction="H"})
N("fp_flamecrest",  "flight", BS,  65.69, 24.22, "Flame Crest",          {faction="H"})
N("fp_lightshope_h","flight", EPL, 70.53, 47.55, "Light's Hope Chapel",  {faction="H"})
-- Kalimdor, Alliance
N("fp_rutheran",    "flight", TEL, 58.40, 94.02, "Rut'theran Village",   {faction="A", area="rutheran"})
N("fp_auberdine",   "flight", DS,  36.34, 45.58, "Auberdine",            {faction="A"})
N("fp_astranaar",   "flight", ASH, 34.41, 47.99, "Astranaar",            {faction="A"})
N("fp_stonetalon",  "flight", STM, 36.44,  7.18, "Stonetalon Peak",      {faction="A"})
N("fp_nijel",       "flight", DES, 64.66, 10.54, "Nijel's Point",        {faction="A"})
N("fp_thalanaar",   "flight", FER, 89.50, 45.85, "Thalanaar",            {faction="A"})
N("fp_feathermoon", "flight", FER, 30.24, 43.25, "Feathermoon",          {faction="A", area="feathermoon"})
N("fp_theramore",   "flight", DWM, 67.48, 51.30, "Theramore",            {faction="A"})
N("fp_gadgetzan_a", "flight", TAN, 51.01, 29.34, "Gadgetzan",            {faction="A"})
N("fp_talrendis",   "flight", AZ,  11.90, 77.59, "Talrendis Point",      {faction="A"})
N("fp_talonbranch", "flight", FW,  62.49, 24.24, "Talonbranch Glade",    {faction="A"})
N("fp_everlook_a",  "flight", WS,  62.33, 36.61, "Everlook",             {faction="A"})
N("fp_moonglade_a", "flight", MG,  48.10, 67.34, "Moonglade",            {faction="A"})
N("fp_cenarion_a",  "flight", SIL, 50.58, 34.45, "Cenarion Hold",        {faction="A"})
-- Kalimdor, Horde
N("fp_orgrimmar",   "flight", ORG, 45.12, 63.89, "Orgrimmar",            {faction="H"})
N("fp_thunderbluff","flight", TB,  47.00, 49.83, "Thunder Bluff",        {faction="H"})
N("fp_crossroads",  "flight", BAR, 51.50, 30.34, "Crossroads",           {faction="H", aliases={"xroads"}})
N("fp_taurajo",     "flight", BAR, 44.45, 59.15, "Camp Taurajo",         {faction="H"})
N("fp_sunrock",     "flight", STM, 45.12, 59.84, "Sun Rock Retreat",     {faction="H"})
N("fp_splintertree","flight", ASH, 73.18, 61.59, "Splintertree Post",    {faction="H"})
N("fp_zoramgar",    "flight", ASH, 12.24, 33.80, "Zoram'gar Outpost",    {faction="H"})
N("fp_shadowprey",  "flight", DES, 21.60, 74.13, "Shadowprey Village",   {faction="H"})
N("fp_mojache",     "flight", FER, 75.45, 44.36, "Camp Mojache",         {faction="H"})
N("fp_freewind",    "flight", TN,  45.14, 49.11, "Freewind Post",        {faction="H"})
N("fp_brackenwall", "flight", DWM, 35.56, 31.88, "Brackenwall Village",  {faction="H"})
N("fp_gadgetzan_h", "flight", TAN, 51.60, 25.44, "Gadgetzan",            {faction="H"})
N("fp_valormok",    "flight", AZ,  21.96, 49.62, "Valormok",             {faction="H"})
N("fp_bloodvenom",  "flight", FW,  34.44, 53.96, "Bloodvenom Post",      {faction="H"})
N("fp_everlook_h",  "flight", WS,  60.47, 36.30, "Everlook",             {faction="H"})
N("fp_moonglade_h", "flight", MG,  32.09, 66.61, "Moonglade",            {faction="H"})
N("fp_cenarion_h",  "flight", SIL, 48.68, 36.67, "Cenarion Hold",        {faction="H"})
-- Kalimdor, both factions
N("fp_ratchet",     "flight", BAR, 63.08, 37.16, "Ratchet")
N("fp_marshal",     "flight", UNG, 45.23,  5.83, "Marshal's Refuge")
-- Forever's new zones. Names are the flight map's own (OpenMap's Forever flight
-- table); Zephras, Shen'dralas and the Darkspear Islands have no flight masters.
N("fp_hyjal_n",     "flight", HYJ, 68.71, 46.80, "Summit of Eternity",   {aliases={"hyjal"}})
N("fp_hyjal_s",     "flight", HYJ, 55.01, 82.76, "Tainted Foothills",    {aliases={"hyjal"}})
N("fp_riverglades_a","flight", RVG, 60.61, 81.54, "Farholde Keep",       {faction="A", aliases={"riverglades"}})
N("fp_riverglades_h","flight", RVG, 59.59, 45.08, "Rog'mar",             {faction="H", aliases={"riverglades","rogmar"}})

---------------------------------------------------------------------------
-- Inns (hearthstone targets; QuestieDB Forever)
---------------------------------------------------------------------------
N("inn_stormwind",  "inn", SW,  60.39, 75.27, "Stormwind City",    {faction="A", bind={"Stormwind","Trade District","The Gilded Rose"}})
N("inn_goldshire",  "inn", ELW, 43.77, 65.80, "Goldshire",         {faction="A", bind={"Lion's Pride Inn"}})
N("inn_sentinel",   "inn", WF,  52.86, 53.71, "Sentinel Hill",     {faction="A"})
N("inn_lakeshire",  "inn", RR,  21.92, 44.82, "Lakeshire",         {faction="A"})
N("inn_darkshire",  "inn", DW,  73.87, 44.41, "Darkshire",         {faction="A"})
N("inn_kharanos",   "inn", DM,  47.38, 52.52, "Kharanos",          {faction="A"})
N("inn_ironforge",  "inn", IF,  18.15, 51.45, "Ironforge",         {faction="A", bind={"The Commons","Stonefire Tavern"}})
N("inn_thelsamar",  "inn", LM,  35.53, 48.40, "Thelsamar",         {faction="A"})
N("inn_menethil",   "inn", WL,  10.70, 60.95, "Menethil Harbor",   {faction="A"})
N("inn_southshore", "inn", HB,  51.17, 58.93, "Southshore",        {faction="A"})
N("inn_aerie",      "inn", HL,  14.15, 41.57, "Aerie Peak",        {faction="A"})
N("inn_dalaran",    "inn", ALT, 18.22, 66.63, "Dalaran",           {faction="A"})
N("inn_brill",      "inn", TG,  61.72, 52.05, "Brill",             {faction="H"})
N("inn_undercity",  "inn", UC,  67.74, 37.89, "Undercity",         {faction="H", bind={"The Trade Quarter"}})
N("inn_sepulcher",  "inn", SP,  43.18, 41.28, "The Sepulcher",     {faction="H"})
N("inn_tarrenmill", "inn", HB,  62.78, 19.03, "Tarren Mill",       {faction="H"})
N("inn_hammerfall", "inn", AH,  73.84, 32.46, "Hammerfall",        {faction="H"})
N("inn_kargath",    "inn", BAD,  2.82, 45.86, "Kargath",           {faction="H"})
N("inn_stonard",    "inn", SOS, 45.16, 56.66, "Stonard",           {faction="H"})
N("inn_gromgol",    "inn", STV, 31.49, 29.75, "Grom'gol Base Camp",{faction="H"})
N("inn_revantusk",  "inn", HL,  78.14, 81.38, "Revantusk Village", {faction="H"})
N("inn_bootybay",   "inn", STV, 27.04, 77.31, "Booty Bay")
N("inn_lightshope", "inn", EPL, 71.80, 48.52, "Light's Hope Chapel")
N("inn_darnassus",  "inn", DAR, 67.42, 15.65, "Darnassus",         {faction="A", bind={"Craftsmen's Terrace"}})
N("inn_dolanaar",   "inn", TEL, 55.62, 59.79, "Dolanaar",          {faction="A"})
N("inn_auberdine",  "inn", DS,  37.04, 44.13, "Auberdine",         {faction="A"})
N("inn_astranaar",  "inn", ASH, 36.99, 49.22, "Astranaar",         {faction="A"})
N("inn_stonetalon", "inn", STM, 35.79,  5.74, "Stonetalon Peak",   {faction="A"})
N("inn_nijel",      "inn", DES, 66.27,  6.55, "Nijel's Point",     {faction="A"})
N("inn_feathermoon","inn", FER, 30.97, 43.49, "Feathermoon Stronghold", {faction="A", area="feathermoon"})
N("inn_theramore",  "inn", DWM, 66.59, 45.22, "Theramore Isle",    {faction="A"})
N("inn_talrendis",  "inn", AZ,  12.60, 77.36, "Talrendis Point",   {faction="A"})
N("inn_orgrimmar",  "inn", ORG, 54.10, 68.41, "Orgrimmar",         {faction="H", bind={"Valley of Strength"}})
N("inn_razorhill",  "inn", DUR, 51.51, 41.64, "Razor Hill",        {faction="H"})
N("inn_crossroads", "inn", BAR, 51.99, 29.89, "The Crossroads",    {faction="H"})
N("inn_taurajo",    "inn", BAR, 45.58, 59.04, "Camp Taurajo",      {faction="H"})
N("inn_thunderbluff","inn", TB, 45.81, 64.71, "Thunder Bluff",     {faction="H", bind={"Lower Rise"}})
N("inn_bloodhoof",  "inn", MUL, 45.93, 64.16, "Bloodhoof Village", {faction="H"})
N("inn_sunrock",    "inn", STM, 47.47, 62.13, "Sun Rock Retreat",  {faction="H"})
N("inn_splintertree","inn", ASH, 73.99, 60.65, "Splintertree Post",{faction="H"})
N("inn_shadowprey", "inn", DES, 24.09, 68.21, "Shadowprey Village",{faction="H"})
N("inn_mojache",    "inn", FER, 74.80, 45.18, "Camp Mojache",      {faction="H"})
N("inn_freewind",   "inn", TN,  46.07, 51.52, "Freewind Post",     {faction="H"})
N("inn_ratchet",    "inn", BAR, 62.05, 39.41, "Ratchet")
N("inn_gadgetzan",  "inn", TAN, 52.51, 27.91, "Gadgetzan")
N("inn_everlook",   "inn", WS,  61.36, 38.83, "Everlook")
N("inn_cenarion",   "inn", SIL, 51.89, 39.16, "Cenarion Hold")
N("inn_hyjal",      "inn", HYJ, 70.87, 51.55, "Mount Hyjal")
N("inn_hyjal_a",    "inn", HYJ, 15.65, 50.45, "Mount Hyjal (Alliance camp)", {faction="A"})
N("inn_hyjal_h",    "inn", HYJ, 12.93, 52.85, "Mount Hyjal (Horde camp)",    {faction="H"})
N("inn_shendralas", "inn", SHD, 42.38, 69.73, "Shen'dralas")
N("inn_zephras_n",  "inn", ZEP, 43.01, 43.23, "Zephras Isle")
N("inn_zephras_s",  "inn", ZEP, 62.19, 72.61, "Zephras Isle (south)")
N("inn_riverglades","inn", RVG, 78.77, 53.98, "Riverglades")
N("inn_riverglades_h","inn", RVG, 58.00, 45.10, "Riverglades (Horde)", {faction="H"})

---------------------------------------------------------------------------
-- Dungeon and raid entrances (QuestieDB Forever)
---------------------------------------------------------------------------
N("d_rfc",    "dungeon", ORG, 52.60, 49.00, "Ragefire Chasm",     {level="13-18", aliases={"rfc"}})
N("d_wc",     "dungeon", BAR, 46.00, 36.50, "Wailing Caverns",    {level="17-24", aliases={"wc"}})
N("d_vc",     "dungeon", WF,  42.50, 71.70, "The Deadmines",      {level="17-26", aliases={"deadmines","vc"}})
N("d_sfk",    "dungeon", SP,  44.80, 67.80, "Shadowfang Keep",    {level="22-30", aliases={"sfk"}})
N("d_bfd",    "dungeon", ASH, 14.50, 14.20, "Blackfathom Deeps",  {level="24-32", aliases={"bfd"}})
N("d_stocks", "dungeon", SW,  52.41, 70.01, "The Stockade",       {level="24-32", aliases={"stocks","stockades"}})
N("d_gnomer", "dungeon", DM,  24.30, 39.80, "Gnomeregan",         {level="29-38", aliases={"gnomer"}})
N("d_rfk",    "dungeon", BAR, 42.90, 90.20, "Razorfen Kraul",     {level="30-40", aliases={"rfk"}})
N("d_sm",     "dungeon", TG,  82.60, 33.80, "Scarlet Monastery",  {level="34-45", aliases={"sm","scarlet","graveyard","library","armory","cathedral"}})
N("d_rfd",    "dungeon", BAR, 49.00, 93.90, "Razorfen Downs",     {level="40-50", aliases={"rfd"}})
N("d_ulda",   "dungeon", BAD, 44.60, 12.10, "Uldaman",            {level="42-52", dest="uldaman", aliases={"ulda"}})
N("d_ulda2",  "dungeon", BAD, 65.20, 43.50, "Uldaman (back entrance)", {level="42-52", dest="uldaman"})
N("d_zf",     "dungeon", TAN, 38.70, 20.10, "Zul'Farrak",         {level="44-54", aliases={"zf"}})
N("d_mara",   "dungeon", DES, 29.10, 62.50, "Maraudon",           {level="46-55", aliases={"mara"}})
N("d_st",     "dungeon", SOS, 69.90, 53.50, "Sunken Temple",      {level="50-60", aliases={"st","temple of atal'hakkar","atal'hakkar"}})
N("d_dm",     "dungeon", FER, 59.20, 45.10, "Dire Maul",          {level="55-60", aliases={"dire maul","dm east","dm west","dm north","tribute"}})
N("d_scholo", "dungeon", WPL, 69.70, 73.20, "Scholomance",        {level="58-60", aliases={"scholo"}})
N("d_strat",  "dungeon", EPL, 26.52, 10.36, "Stratholme",         {level="58-60", dest="strat", aliases={"strat","live side","stratholme live"}})
N("d_strat2", "dungeon", EPL, 41.45, 17.74, "Stratholme (service entrance)", {level="58-60", dest="strat", aliases={"ud strat","dead side","baron"}})
-- Forever's new dungeons (entrances from ForeverDungeonJournal / OpenMap)
N("d_hot",      "dungeon", IF,  27.70, 47.90, "The Hall of Thanes",        {level="13-20", aliases={"hall of thanes","thanes","hot"}})
N("d_rol",      "dungeon", UC,  72.50, 11.40, "Ruins of Lordaeron",        {level="15-22", aliases={"rol","lordaeron"}})
N("d_exwet",    "dungeon", WL,  47.80, 56.20, "Excavation Site: Wetlands", {level="26-33", aliases={"excavation site","excavation","wetlands dungeon"}})
N("d_dalaran",  "dungeon", ALT,  8.50, 59.30, "City of Dalaran",           {level="28-35", aliases={"dalaran"}})
N("d_drowned",  "dungeon", STV, 21.30, 27.80, "The Drowned City",          {level="35-42", aliases={"drowned city","drowned"}})
N("d_kroldok",  "dungeon", RVG, 37.50, 37.30, "Krol'dok Stronghold",       {level="40-47", aliases={"kroldok","krol'dok"}})
N("d_alcaz",    "dungeon", DWM, 75.30, 14.10, "Alcaz Prison",              {level="48-55", aliases={"alcaz"}})
N("r_blackmaw", "raid",    AZ,  38.60, 33.20, "Blackmaw Hold",             {level="55-60", aliases={"blackmaw"}})
N("r_shapers",  "raid",    UNG, 48.10,  6.10, "Shaper's Terrace",          {level="58-60", aliases={"shapers","shaper's","shapers terrace"}})
-- Blackrock Mountain: one hub per side, the instances hang off both.
N("brm_bs",   "hub",     BS,  29.40, 38.30, "Blackrock Mountain (Burning Steppes side)")
N("brm_sg",   "hub",     SG,  34.80, 85.30, "Blackrock Mountain (Searing Gorge side)")
N("d_brd",    "dungeon", BS,  29.40, 38.30, "Blackrock Depths",   {level="52-60", noZone=true, aliases={"brd"}})
N("d_lbrs",   "dungeon", BS,  29.40, 38.30, "Lower Blackrock Spire", {level="55-60", noZone=true, aliases={"lbrs","blackrock spire"}})
N("d_ubrs",   "raid",    BS,  29.40, 38.30, "Upper Blackrock Spire", {level="58-60", noZone=true, aliases={"ubrs"}})
N("r_mc",     "raid",    BS,  29.40, 38.30, "Molten Core",        {level="60", noZone=true, aliases={"mc"}})
N("r_bwl",    "raid",    BS,  29.40, 38.30, "Blackwing Lair",     {level="60", noZone=true, aliases={"bwl"}})
N("r_ony",    "raid",    DWM, 52.60, 76.80, "Onyxia's Lair",      {level="60", aliases={"ony","onyxia"}})
N("r_zg",     "raid",    STV, 53.89, 17.60, "Zul'Gurub",          {level="60", aliases={"zg"}})
N("r_aq20",   "raid",    SIL, 28.60, 92.30, "Ruins of Ahn'Qiraj", {level="60", aliases={"aq20","aq ruins"}})
N("r_aq40",   "raid",    SIL, 28.60, 92.30, "Temple of Ahn'Qiraj",{level="60", aliases={"aq40","aq temple","aq"}})
N("r_naxx",   "raid",    EPL, 34.25, 19.45, "Naxxramas",          {level="60", aliases={"naxx"}})

L("brm_bs", "brm_sg", "walk", 45, {text="Cross Blackrock Mountain"})
for _, id in ipairs({"d_brd", "d_lbrs", "d_ubrs"}) do
    L("brm_bs", id, "walk", 30)
    L("brm_sg", id, "walk", 30)
end
for _, id in ipairs({"r_mc", "r_bwl"}) do
    L("brm_bs", id, "walk", 60)
    L("brm_sg", id, "walk", 60)
end

---------------------------------------------------------------------------
-- Zone crossings (estimates). zones = every zone the point belongs to.
---------------------------------------------------------------------------
local function B(id, map, x, y, name, zones, o)
    o = o or {}
    o.zones = zones
    N(id, "border", map, x, y, name, o)
end
-- Eastern Kingdoms
B("b_sw_gate",   ELW, 32.40, 49.80, "Stormwind City gates",        {ELW, SW})
B("b_elw_wf",    ELW, 20.50, 80.50, "Elwynn / Westfall bridge",     {ELW, WF})
B("b_elw_rr",    ELW, 94.00, 72.00, "Elwynn / Redridge road",       {ELW, RR})
B("b_elw_dw",    ELW, 74.00, 88.00, "Elwynn / Duskwood bridge",     {ELW, DW})
B("b_wf_dw",     DW,   7.50, 51.00, "Westfall / Duskwood road",     {WF, DW})
B("b_dw_stv",    STV, 41.00,  2.00, "Duskwood / Stranglethorn road",{DW, STV})
B("b_dw_dp",     DW,  88.00, 70.00, "Duskwood / Deadwind Pass road",{DW, DP})
B("b_dp_sos",    SOS,  2.50, 60.00, "Deadwind Pass / Swamp of Sorrows road", {DP, SOS})
B("b_sos_bl",    BL,  48.00,  5.00, "Swamp of Sorrows / Blasted Lands road", {SOS, BL})
B("b_rr_bs",     BS,  80.50, 76.00, "Redridge / Burning Steppes pass", {RR, BS})
B("b_if_gate",   DM,  53.00, 34.80, "Ironforge gates",              {DM, IF})
B("b_dm_lm",     DM,  85.50, 51.00, "Dun Morogh / Loch Modan tunnel", {DM, LM})
B("b_lm_wl",     LM,  25.50, 10.00, "Dun Algaz (Loch Modan / Wetlands)", {LM, WL})
B("b_lm_bad",    LM,  47.00, 76.00, "Loch Modan / Badlands road",   {LM, BAD})
B("b_wl_ah",     WL,  50.50, 10.50, "Thandol Span (Wetlands / Arathi)", {WL, AH})
B("b_ah_hb",     AH,  19.00, 33.00, "Thoradin's Wall (Arathi / Hillsbrad)", {AH, HB})
B("b_hb_hl",     HB,  87.00, 31.00, "Hillsbrad / Hinterlands path", {HB, HL})
B("b_hb_sp",     SP,  66.50, 78.00, "Silverpine / Hillsbrad road",  {SP, HB})
B("b_hb_alt",    HB,  57.00,  9.00, "Hillsbrad / Alterac road",     {HB, ALT})
B("b_alt_wpl",   WPL, 46.00, 90.00, "Alterac / Western Plaguelands road", {ALT, WPL})
B("b_sp_tg",     TG,  55.00, 80.00, "Tirisfal / Silverpine road",   {TG, SP})
B("b_uc_gate",   TG,  61.80, 65.00, "Undercity entrance (Ruins of Lordaeron)", {TG, UC})
B("b_tg_wpl",    TG,  84.00, 69.00, "The Bulwark (Tirisfal / Plaguelands)", {TG, WPL})
B("b_wpl_epl",   EPL,  8.50, 63.00, "Thondroril River (Western / Eastern Plaguelands)", {WPL, EPL})
-- Kalimdor
B("b_org_gate",  DUR, 45.50, 12.00, "Orgrimmar gates",              {DUR, ORG})
B("b_dur_bar",   DUR, 34.50, 42.50, "Southfury bridge (Durotar / Barrens)", {DUR, BAR})
B("b_bar_mul",   MUL, 68.50, 60.00, "Mulgore / Barrens road",       {MUL, BAR})
B("b_tb_lift",   MUL, 38.00, 33.50, "Thunder Bluff elevators",      {MUL, TB})
B("b_bar_ash",   BAR, 48.00,  5.50, "Mor'shan Ramparts (Barrens / Ashenvale)", {BAR, ASH})
B("b_bar_stm",   BAR, 35.50, 27.50, "Barrens / Stonetalon road",    {BAR, STM})
B("b_bar_dwm",   DWM, 28.50, 47.00, "Barrens / Dustwallow road",    {BAR, DWM})
B("b_bar_tn",    TN,  31.50, 21.50, "The Great Lift (Barrens / Thousand Needles)", {BAR, TN})
B("b_tn_fer",    FER, 89.80, 46.50, "Thousand Needles / Feralas road", {TN, FER})
B("b_tn_tan",    TAN, 51.50, 12.00, "Thousand Needles / Tanaris road", {TN, TAN})
B("b_tan_ung",   TAN, 28.00, 57.00, "Tanaris / Un'Goro path",       {TAN, UNG})
B("b_ung_sil",   UNG, 29.00, 23.00, "Un'Goro / Silithus path",      {UNG, SIL})
B("b_fer_des",   DES, 47.00, 92.00, "Desolace / Feralas road",      {DES, FER})
B("b_des_stm",   DES, 54.00,  5.50, "Desolace / Stonetalon road",   {DES, STM})
B("b_stm_ash",   ASH, 42.00, 71.00, "Talondeep Path (Stonetalon / Ashenvale)", {STM, ASH})
B("b_ash_ds",    DS,  44.50, 93.00, "Ashenvale / Darkshore road",   {ASH, DS})
B("b_ash_fw",    FW,  55.00, 88.00, "Ashenvale / Felwood road",     {ASH, FW})
B("b_ash_az",    ASH, 94.00, 38.00, "Ashenvale / Azshara road",     {ASH, AZ})
B("b_timbermaw", FW,  64.60,  8.30, "Timbermaw Hold tunnel",        {FW, MG, WS}, {note="Needs Timbermaw Hold reputation or you'll be attacked"})
B("b_darn_gate", TEL, 40.50, 57.00, "Darnassus gates",              {TEL, DAR})


---------------------------------------------------------------------------
-- Mage teleports and portals. Arrival = the city's portal trainer
-- (QuestieDB Forever), which is where the spells drop you.
---------------------------------------------------------------------------
N("mage_stormwind", "mage", SW,  50.39, 85.99, "Stormwind City (Wizard's Sanctum)", {faction="A"})
N("mage_ironforge", "mage", IF,  25.50,  7.07, "Ironforge (Hall of Mysteries)",     {faction="A"})
N("mage_darnassus", "mage", DAR, 40.60, 82.13, "Darnassus (Temple Gardens)",        {faction="A"})
N("mage_orgrimmar", "mage", ORG, 38.68, 85.41, "Orgrimmar (Cleft of Shadow)",       {faction="H"})
N("mage_undercity", "mage", UC,  84.19, 15.58, "Undercity (Magic Quarter)",         {faction="H"})
N("mage_thunderbluff","mage", TB, 22.50, 16.91, "Thunder Bluff (Spirit Rise)",      {faction="H"})

-- teleport = self only; portal = opens a portal for the group (needs Rune of Portals)
AM.mageSpells = {
    { node = "mage_stormwind",   city = "Stormwind",     teleport = 3561, portal = 10059 },
    { node = "mage_ironforge",   city = "Ironforge",     teleport = 3562, portal = 11416 },
    { node = "mage_darnassus",   city = "Darnassus",     teleport = 3565, portal = 11419 },
    { node = "mage_orgrimmar",   city = "Orgrimmar",     teleport = 3567, portal = 11417 },
    { node = "mage_undercity",   city = "Undercity",     teleport = 3563, portal = 11418 },
    { node = "mage_thunderbluff",city = "Thunder Bluff", teleport = 3566, portal = 11420 },
}

-- Engineering transporters (Gnomish: Ultrasafe Transporter; Goblin: Dimensional
-- Ripper). Used when one is in your bags and usable. Arrival spots are estimates.
N("eng_gadgetzan", "mage", TAN, 52.00, 28.00, "Gadgetzan (Ultrasafe Transporter)")
N("eng_everlook",  "mage", WS,  61.00, 38.50, "Everlook (Dimensional Ripper)")
AM.teleportItems = {
    { node = "eng_gadgetzan", item = 18986, name = "Ultrasafe Transporter: Gadgetzan" },
    { node = "eng_everlook",  item = 18984, name = "Dimensional Ripper - Everlook" },
}

---------------------------------------------------------------------------
-- Banks and auction houses (QuestieDB Forever: banker / auctioneer NPCs).
-- "bank" and "ah" searches route to the nearest one of your faction.
---------------------------------------------------------------------------
N("bank_sw",   "bank", SW,  63.87, 81.10, "Stormwind Bank",            {faction="A"})
N("bank_if",   "bank", IF,  35.92, 60.14, "Ironforge Bank (The Vault)", {faction="A"})
N("bank_dar",  "bank", DAR, 39.60, 41.98, "Darnassus Bank",            {faction="A"})
N("bank_org",  "bank", ORG, 49.58, 69.12, "Orgrimmar Bank",            {faction="H"})
N("bank_uc",   "bank", UC,  65.97, 44.10, "Undercity Bank",            {faction="H"})
N("bank_tb",   "bank", TB,  47.63, 58.58, "Thunder Bluff Bank",        {faction="H"})
N("bank_bb",   "bank", STV, 26.54, 76.57, "Booty Bay Bank")
N("bank_rat",  "bank", BAR, 62.64, 37.42, "Ratchet Bank")
N("bank_gz",   "bank", TAN, 52.30, 28.91, "Gadgetzan Bank")
N("bank_ev",   "bank", WS,  61.45, 36.98, "Everlook Bank")
N("bank_zep",  "bank", ZEP, 57.63, 77.17, "Zephras Bank")
N("bank_rvg",  "bank", RVG, 76.75, 54.32, "Riverglades Bank")

N("ah_sw",     "ah", SW,  61.10, 71.20, "Stormwind Auction House",     {faction="A"})
N("ah_if",     "ah", IF,  24.16, 74.67, "Ironforge Auction House",     {faction="A"})
N("ah_dar",    "ah", DAR, 56.37, 52.90, "Darnassus Auction House",     {faction="A"})
N("ah_org",    "ah", ORG, 55.90, 62.71, "Orgrimmar Auction House",     {faction="H"})
N("ah_uc",     "ah", UC,  67.55, 52.42, "Undercity Auction House",     {faction="H"})
N("ah_tb",     "ah", TB,  40.41, 51.77, "Thunder Bluff Auction House", {faction="H"})
N("ah_bb",     "ah", STV, 26.59, 76.35, "Booty Bay Auction House")
N("ah_gz",     "ah", TAN, 51.96, 29.65, "Gadgetzan Auction House")
N("ah_ev",     "ah", WS,  61.45, 37.20, "Everlook Auction House")
N("ah_zep",    "ah", ZEP, 57.91, 77.12, "Zephras Auction House")

---------------------------------------------------------------------------
-- Boats, zeppelins, tram, portal (dock positions are estimates)
---------------------------------------------------------------------------
N("dock_men_ther", "dock", WL,   5.00, 63.50, "Menethil Harbor docks (boat to Theramore)")
N("dock_men_aub",  "dock", WL,   4.60, 57.00, "Menethil Harbor docks (boat to Auberdine)")
N("dock_ther",     "dock", DWM, 71.60, 56.40, "Theramore docks")
N("dock_aub_men",  "dock", DS,  32.40, 43.80, "Auberdine docks (boat to Menethil)")
N("dock_aub_rut",  "dock", DS,  33.20, 40.00, "Auberdine docks (boat to Rut'theran)")
N("dock_rut",      "dock", TEL, 55.00, 96.50, "Rut'theran Village docks", {area="rutheran"})
N("dock_bb",       "dock", STV, 25.90, 73.10, "Booty Bay docks")
N("dock_ratchet",  "dock", BAR, 63.70, 38.60, "Ratchet docks")
N("dock_fcoast",   "dock", FER, 43.30, 42.80, "Forgotten Coast dock (boat to Feathermoon)")
N("dock_feather",  "dock", FER, 31.00, 39.50, "Feathermoon Stronghold dock", {area="feathermoon"})
N("zep_org",       "dock", DUR, 50.80, 13.60, "Orgrimmar zeppelin tower", {faction="H"})
N("zep_uc",        "dock", TG,  60.80, 58.80, "Undercity zeppelin tower", {faction="H"})
N("zep_gg",        "dock", STV, 31.40, 30.00, "Grom'gol zeppelin tower",  {faction="H"})
N("tram_sw",       "tram", SW,  71.98, 27.61, "Deeprun Tram (Stormwind)")
N("tram_if",       "tram", IF,  84.10, 53.10, "Deeprun Tram (Ironforge)")
N("portal_rut",    "portal", TEL, 55.90, 89.60, "Portal to Darnassus (Rut'theran)", {area="rutheran"})
N("portal_darn",   "portal", DAR, 36.50, 50.00, "Portal to Rut'theran (Darnassus)")

L("dock_men_ther", "dock_ther",    "boat", 260, {faction="A"})
L("dock_men_aub",  "dock_aub_men", "boat", 260, {faction="A"})
L("dock_aub_rut",  "dock_rut",     "boat", 200, {faction="A"})
L("dock_bb",       "dock_ratchet", "boat", 260)
L("dock_fcoast",   "dock_feather", "boat", 100, {faction="A"})
L("zep_org",       "zep_uc",       "zeppelin", 240, {faction="H"})
L("zep_org",       "zep_gg",       "zeppelin", 240, {faction="H"})
L("zep_uc",        "zep_gg",       "zeppelin", 240, {faction="H"})
L("tram_sw",       "tram_if",      "tram", 80)
L("portal_rut",    "portal_darn",  "portal", 8)
