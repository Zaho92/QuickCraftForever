local ADDON_NAME, ns = ...
local L = ns.L
-- The packager writes the release's version here; a copy straight from the repository says "dev".
local VERSION = "@project-version@"
if VERSION:find("@", 1, true) then
	VERSION = "dev"
end

local PREFIX = "|cffe3ab5cQuickCraft:|r "
local WHITE = "Interface\\Buttons\\WHITE8x8"

-- SavedVariables (QuickCraftForeverDB):
--   settings                       see DEFAULTS
--   pos = { point, x, y }          bar position
--   favs[char][professionName]     = { profID = n, list = { { id, name, icon, diff, reagents } } }
--                                    the fan's recipes, written while that profession is loaded
--   marked[char][recipeID]         own marks; only used when the client has no recipe favourites
--   log                            debug lines, last LOG_MAX
local DEFAULTS = {
	locked = true, -- off: a drag overlay covers the bar
	vertical = false, -- professions top to bottom instead of left to right
	style = "blizzard", -- "blizzard" or "ellesmere"
	frame = true, -- background and border around the bar
	scale = 1, -- whole bar, 0.5 to 2
	iconSize = 40, -- icon size in pixels
	spacing = 6, -- pixels between two profession icons
	fanSpacing = 3, -- pixels between two recipe icons
	showBar = true, -- skill progress bar under the icon
	barHeight = 6, -- its thickness in pixels
	barTexture = "style", -- "style", "forever", "blizzard", "flat" or "lsm:<name>"
	barColor = "style", -- "style" or a key of BAR_COLORS
	showText = true, -- skill number on the icon
	font = "auto", -- "auto", "game" or "lsm:<name>"
	fontSize = 11,
	animTime = 0.25, -- seconds the recipe icons take to fan out; 0 = no animation
	tooltips = true,
}

-- Look presets. The EllesmereUI one is modelled on that addon's default look (warm dark panel, thin
-- pale border, Forever's bronze accent) with values of its own; nothing is loaded from the addon.
local STYLES = {
	blizzard = {
		pad = 9,
		backdrop = {
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true,
			tileSize = 16,
			edgeSize = 14,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		},
		bg = { 0, 0, 0, 0.75 },
		edge = { 0.75, 0.75, 0.75, 1 },
		-- WoW Forever frames its bars with a bronze line round a dark body: the atlas its own action
		-- bars and micro menu wear (a 55-unit box, sliced 24 a side). The backdrop above is only the
		-- stand-in for a client without that atlas.
		frameAtlas = "UI-HUD-ActionBar-Frame",
		frameSlice = 24,
		texture = "forever",
		bar = { 0.89, 0.67, 0.36 },
		coords = { 0, 1, 0, 1 }, -- the icon art's own bevelled edge is the Blizzard look
		iconBorder = false,
	},
	ellesmere = {
		pad = 6,
		backdrop = { bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 },
		bg = { 0.069, 0.058, 0.047, 0.92 },
		edge = { 1, 1, 1, 0.1 },
		texture = "flat",
		bar = { 220 / 255, 167 / 255, 127 / 255 },
		coords = { 0.07, 0.93, 0.07, 0.93 },
		iconBorder = true,
	},
}

local function DB()
	QuickCraftForeverDB = QuickCraftForeverDB or {}
	return QuickCraftForeverDB
end

local function Cfg()
	local db = DB()
	db.settings = db.settings or {}
	local s = db.settings
	-- Settings of earlier versions.
	if s.ellesmereStyle ~= nil then
		s.style = s.ellesmereStyle and "ellesmere" or "blizzard"
		s.ellesmereStyle = nil
	end
	s.directCraft = nil
	for key, value in pairs(DEFAULTS) do
		if s[key] == nil then
			s[key] = value
		end
	end
	if not STYLES[s.style] then
		s.style = DEFAULTS.style
	end
	return s
end

local function Style()
	return STYLES[Cfg().style]
end

local function CharKey()
	return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

-- Secret values (the client's restricted reads, as in combat): comparing or calculating with one raises
-- an error. Every value read from the game goes through these; nil means "unknown".
local function Readable(value)
	if type(issecretvalue) == "function" then
		local ok, secret = pcall(issecretvalue, value)
		if not ok or secret then
			return nil
		end
	end
	return value
end

local function Number(value)
	value = Readable(value)
	return type(value) == "number" and value or nil
end

local function Text(value)
	value = Readable(value)
	return type(value) == "string" and value ~= "" and value or nil
end

local function PaintBox(frame, panel, edge)
	frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
	frame:SetBackdropColor(panel[1], panel[2], panel[3], panel[4])
	frame:SetBackdropBorderColor(edge[1], edge[2], edge[3], edge[4])
end

---------------------------------------------------------------------------
-- Debug log. /qc log shows it, /qc dump writes the addon's state into it. The lines are saved, so
-- they survive /reload. To copy: click into the text, Ctrl+A, Ctrl+C.
---------------------------------------------------------------------------
local LOG_MAX = 400
local logWin

local function LogLines()
	local db = DB()
	db.log = db.log or {}
	return db.log
end

local function RefreshLog()
	if logWin and logWin:IsShown() then
		logWin.edit:SetText(table.concat(LogLines(), "\n"))
	end
end

-- Lines are kept only while debugging is on (/qc debug); errors and /qc dump are always kept.
local forceLog = false

local function Log(fmt, ...)
	if not (forceLog or DB().debug) then
		return
	end
	local ok, msg = pcall(string.format, fmt, ...)
	if not ok then
		msg = tostring(fmt)
	end
	local lines = LogLines()
	lines[#lines + 1] = string.format("%s  %s", date("%H:%M:%S"), msg)
	while #lines > LOG_MAX do
		table.remove(lines, 1)
	end
	RefreshLog()
end

-- Runs fn; an error goes into the log (and once into chat) instead of repeating silently.
local reported = {}
local function Safe(where, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		err = tostring(err)
		forceLog = true
		Log("ERROR in %s: %s", where, err)
		forceLog = false
		if not reported[err] then
			reported[err] = true
			print(PREFIX .. string.format(L["Error in %s: %s  (/qc log)"], where, err))
		end
	end
	return ok
end

local function ToggleLog()
	if not logWin then
		local f = CreateFrame("Frame", "QuickCraftForeverLog", UIParent, "BackdropTemplate")
		f:SetSize(560, 360)
		f:SetPoint("CENTER")
		f:SetFrameStrata("FULLSCREEN_DIALOG")
		f:SetClampedToScreen(true)
		f:SetMovable(true)
		f:EnableMouse(true)
		f:RegisterForDrag("LeftButton")
		f:SetScript("OnDragStart", f.StartMoving)
		f:SetScript("OnDragStop", f.StopMovingOrSizing)
		PaintBox(f, { 0, 0, 0, 0.92 }, { 1, 1, 1, 0.2 })

		f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		f.title:SetPoint("TOPLEFT", 12, -10)
		f.title:SetText("QuickCraft Forever " .. VERSION .. " – " .. L["Log (click the text, Ctrl+A, Ctrl+C)"])

		f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
		f.close:SetPoint("TOPRIGHT", -2, -2)

		f.clear = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
		f.clear:SetSize(80, 22)
		f.clear:SetPoint("BOTTOMRIGHT", -10, 8)
		f.clear:SetText(L["Clear"])
		f.clear:SetScript("OnClick", function()
			wipe(LogLines())
			RefreshLog()
		end)

		f.scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
		f.scroll:SetPoint("TOPLEFT", 12, -34)
		f.scroll:SetPoint("BOTTOMRIGHT", -30, 36)

		f.edit = CreateFrame("EditBox", nil, f.scroll)
		f.edit:SetMultiLine(true)
		f.edit:SetAutoFocus(false)
		f.edit:SetFontObject(GameFontHighlightSmall)
		f.edit:SetWidth(510)
		f.edit:SetScript("OnEscapePressed", f.edit.ClearFocus)
		f.scroll:SetScrollChild(f.edit)
		f:Hide()
		logWin = f
	end
	logWin:SetShown(not logWin:IsShown())
	RefreshLog()
end

---------------------------------------------------------------------------
-- Fonts and bar textures. LibSharedMedia and EllesmereUI are used when they happen to be loaded; the
-- addon runs the same without either.
---------------------------------------------------------------------------
local function SharedMedia()
	return LibStub and LibStub("LibSharedMedia-3.0", true) or nil
end

local function GameFont()
	return (GameFontHighlightSmall:GetFont())
end

-- { { value, label } } for the options.
local function FontChoices()
	local list = { { "auto", L["Automatic (UI default)"] }, { "game", L["Game font"] } }
	local lsm = SharedMedia()
	if lsm then
		for _, name in ipairs(lsm:List("font")) do
			list[#list + 1] = { "lsm:" .. name, name }
		end
	end
	return list
end

local function BarChoices()
	local list = { { "style", L["Match the style"] }, { "forever", "WoW Forever" }, { "blizzard", L["Classic"] }, { "flat", L["Flat"] } }
	local lsm = SharedMedia()
	if lsm then
		for _, name in ipairs(lsm:List("statusbar")) do
			list[#list + 1] = { "lsm:" .. name, name }
		end
	end
	return list
end

-- The font file for a font setting's value (the current setting when none is given).
local function FontPath(key)
	key = key or Cfg().font
	local name = key:match("^lsm:(.+)$")
	local lsm = SharedMedia()
	if name and lsm then
		return lsm:Fetch("font", name, true) or GameFont()
	end
	-- "auto": the font EllesmereUI is set to, when that addon is there; the game's font otherwise.
	if key == "auto" and type(EllesmereUI) == "table" and type(EllesmereUI.GetFontPath) == "function" then
		local ok, path = pcall(EllesmereUI.GetFontPath)
		if ok and type(path) == "string" then
			return path
		end
	end
	return GameFont()
end

local function ApplyFont(fontString, sizeOffset)
	local size = Cfg().fontSize + (sizeOffset or 0)
	if not fontString:SetFont(FontPath(), size, "OUTLINE") then
		fontString:SetFont(GameFont(), size, "OUTLINE")
	end
end

local function AtlasExists(name)
	local ok, info = pcall(function()
		return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name)
	end)
	return ok and info ~= nil
end

-- WoW Forever's own bar fill (the one its cooldown bars use); the classic status bar where the client
-- has no such atlas.
local FOREVER_FILL = "UI-HUD-CoolDownManager-Bar"
local CLASSIC_FILL = "Interface\\TargetingFrame\\UI-StatusBar"

-- The texture (a file or an atlas name) for a bar texture setting's value.
local function BarTexture(key)
	key = key or Cfg().barTexture
	if key == "style" then
		key = Style().texture
	end
	local name = key:match("^lsm:(.+)$")
	local lsm = SharedMedia()
	if name and lsm then
		return lsm:Fetch("statusbar", name, true) or CLASSIC_FILL
	elseif key == "forever" then
		return AtlasExists(FOREVER_FILL) and FOREVER_FILL or CLASSIC_FILL
	elseif key == "flat" or key == WHITE then
		return WHITE
	end
	return CLASSIC_FILL
end

local BAR_COLORS = {
	gold = { 1, 0.82, 0 },
	bronze = { 0.89, 0.67, 0.36 },
	blue = { 0.2, 0.6, 1 },
	green = { 0.3, 0.85, 0.35 },
	red = { 0.9, 0.3, 0.25 },
	white = { 0.9, 0.9, 0.9 },
}

local function BarColor()
	local key = Cfg().barColor
	if key == "class" then
		local _, class = UnitClass("player")
		local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
		if color then
			return color.r, color.g, color.b
		end
	end
	local color = BAR_COLORS[key] or Style().bar
	return color[1], color[2], color[3]
end

local function BarColorChoices()
	return {
		{ "style", L["Match the style"] }, { "gold", L["Gold"] }, { "bronze", L["Bronze"] }, { "blue", L["Blue"] },
		{ "green", L["Green"] }, { "red", L["Red"] }, { "white", L["White"] }, { "class", L["Class color"] },
	}
end

---------------------------------------------------------------------------
-- Game data
---------------------------------------------------------------------------
local TS = C_TradeSkillUI

-- The character's professions, in the client's slot order. skill/max are nil while unreadable.
local function PlayerProfessions()
	local list = {}
	local function Add(...)
		for i = 1, select("#", ...) do
			local index = select(i, ...)
			if index then
				local name, icon, rank, maxRank, _, _, skillLine, modifier = GetProfessionInfo(index)
				skillLine = Number(skillLine)
				if skillLine then
					local base, cap = Number(rank), Number(maxRank)
					list[#list + 1] = {
						name = Text(name) or "?",
						icon = Readable(icon),
						skillLine = skillLine,
						skill = base and (base + (Number(modifier) or 0)) or nil,
						max = cap,
					}
				end
			end
		end
	end
	Add(GetProfessions())
	return list
end

local function ProfessionsOpen()
	return ProfessionsFrame ~= nil and ProfessionsFrame:IsShown()
end

-- A linked or guild window shows someone else's recipes.
local function ForeignWindow()
	return (TS.IsTradeSkillLinked and TS.IsTradeSkillLinked()) or (TS.IsTradeSkillGuild and TS.IsTradeSkillGuild()) or false
end

-- Name and ID of the profession the client has loaded. Blank while none is.
local function LoadedProfession()
	local base = TS.GetBaseProfessionInfo and TS.GetBaseProfessionInfo()
	if not base then
		return nil
	end
	return Text(base.professionName), Number(base.professionID)
end

-- The player's own profession shown in the open window, by name.
local function OpenProfession()
	if not ProfessionsOpen() or ForeignWindow() then
		return nil
	end
	return (LoadedProfession())
end

-- The recipe the crafting page shows. Reading it is harmless; it is never written from here.
local function ShownRecipeID()
	local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
	local form = page and page.SchematicForm
	local info = form and form.GetRecipeInfo and form:GetRecipeInfo()
	return info and Number(info.recipeID)
end

local function PlayerCasting()
	return (UnitCastingInfo and UnitCastingInfo("player") ~= nil) or (UnitChannelInfo and UnitChannelInfo("player") ~= nil) or false
end

---------------------------------------------------------------------------
-- Favourites: the client's own recipe favourites where it has them, own marks otherwise.
---------------------------------------------------------------------------
local function GameFavourites()
	return type(TS.SetRecipeFavorite) == "function"
end

local function OwnMarks()
	local db = DB()
	db.marked = db.marked or {}
	db.marked[CharKey()] = db.marked[CharKey()] or {}
	return db.marked[CharKey()]
end

local function IsFavourite(recipeID, info)
	if GameFavourites() then
		info = info or TS.GetRecipeInfo(recipeID)
		return info ~= nil and Readable(info.favorite) == true
	end
	return OwnMarks()[recipeID] ~= nil
end

local function FavCache()
	local db = DB()
	db.favs = db.favs or {}
	db.favs[CharKey()] = db.favs[CharKey()] or {}
	return db.favs[CharKey()]
end

-- Basic reagents of a recipe as { { itemID, quantity } }, so the fan can count crafts from the bags
-- while the profession is not loaded.
local function Reagents(recipeID)
	local out = {}
	local schematic = TS.GetRecipeSchematic and TS.GetRecipeSchematic(recipeID, false)
	local slots = schematic and schematic.reagentSlotSchematics
	if type(slots) ~= "table" then
		return out
	end
	local basic = Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic
	for _, slot in ipairs(slots) do
		local first = slot.reagents and slot.reagents[1]
		local itemID = first and Number(first.itemID)
		local quantity = Number(slot.quantityRequired)
		if itemID and itemID > 0 and quantity and quantity > 0 and (basic == nil or slot.reagentType == basic) then
			out[#out + 1] = { itemID, quantity }
		end
	end
	return out
end

local RefreshRows -- defined with the recipe list rows
local lastScan

-- Reads the loaded profession's favourites into the saved cache. Only the player's own profession, and
-- never an empty answer: the client reports no recipes while it is still loading them.
local function Scan()
	if ForeignWindow() then
		return
	end
	local profName, profID = LoadedProfession()
	local ids = profName and TS.GetAllRecipeIDs and TS.GetAllRecipeIDs()
	if type(ids) ~= "table" or #ids == 0 then
		return
	end
	local list, learned = {}, 0
	for _, recipeID in ipairs(ids) do
		local info = TS.GetRecipeInfo(recipeID)
		if info and Readable(info.learned) == true then
			learned = learned + 1
			if IsFavourite(recipeID, info) then
				list[#list + 1] = {
					id = recipeID,
					name = Text(info.name) or ("#" .. recipeID),
					icon = Readable(info.icon),
					diff = Number(info.relativeDifficulty),
					reagents = Reagents(recipeID),
				}
			end
		end
	end
	-- Orange first (most skill-ups), then yellow, green, grey; by name inside a colour.
	table.sort(list, function(a, b)
		local da, db = a.diff or 9, b.diff or 9
		if da ~= db then
			return da < db
		end
		return a.name < b.name
	end)
	FavCache()[profName] = { profID = profID, list = list }
	local summary = string.format("scan %s (ID %s): %d recipes, %d learned, %d favorites", profName, tostring(profID), #ids, learned, #list)
	if summary ~= lastScan then
		lastScan = summary
		Log(summary)
	end
	if RefreshRows then
		RefreshRows()
	end
end

local function ToggleFavourite(recipeID)
	if GameFavourites() then
		local now = IsFavourite(recipeID)
		TS.SetRecipeFavorite(recipeID, not now)
		Log("favorite %s: recipe %d (game favorite)", now and "removed" or "set", recipeID)
	else
		local marks = OwnMarks()
		marks[recipeID] = (not marks[recipeID]) and true or nil
		Log("mark %s: recipe %d (own list)", marks[recipeID] and "set" or "removed", recipeID)
	end
	Scan()
end

-- The cached favourites of a profession (anything with profName and skillLine): by name, else by ID.
local function FavouritesOf(who)
	local cache = FavCache()
	local entry = cache[who.profName]
	if not entry then
		for _, other in pairs(cache) do
			if other.profID == who.skillLine then
				entry = other
				break
			end
		end
	end
	return entry and entry.list or {}
end

local function BagCount(itemID)
	local count = (C_Item and C_Item.GetItemCount or GetItemCount)(itemID)
	return Number(count) or 0
end

-- How many crafts the bags allow. The client's own number while that profession is open, else counted
-- from the saved reagents; nil when neither is known.
local function CraftCount(entry, profName)
	if OpenProfession() == profName and TS.GetCraftableCount then
		local live = Number(TS.GetCraftableCount(entry.id))
		if live then
			return live
		end
	end
	if not entry.reagents or #entry.reagents == 0 then
		return nil
	end
	local count
	for _, reagent in ipairs(entry.reagents) do
		local crafts = math.floor(BagCount(reagent[1]) / reagent[2])
		count = count and math.min(count, crafts) or crafts
	end
	return count
end

---------------------------------------------------------------------------
-- Crafting. A click calls the client's CraftRecipe; the Professions window stays shut.
--
-- What the tests on this client showed:
--   * CraftRecipe works only while the profession is loaded, and the client unloads a profession when
--     the Professions window closes.
--   * The window is opened by whichever frames listen to TRADE_SKILL_SHOW. Taking them off that one
--     event for a moment loads the profession without the window ("silent load").
--   * OpenTradeSkill is accepted from a hover, so the profession is loaded before the click arrives.
--   * Using an item after such a craft works; the client blocked nothing.
-- A silently loaded profession is closed again once nothing is crafted and the fan is gone.
---------------------------------------------------------------------------
local fanOwner -- the bar button whose fan is out (set by the fan code below)
local silent = { waiting = false } -- .loaded = profession loaded without its window
local job -- a craft waiting for its profession to finish loading
local crafting -- the craft in progress: { id, amount, done, time, begun, last }
local hoverLoadFailed, silentBroken
local muted = {}
local watchUntil, watchSeen = 0, nil

-- One line of context for the log: what the client has open and loaded right now.
local function Context()
	local name, id = LoadedProfession()
	return string.format("window open=%s loaded=%s(%s) combat=%s", tostring(ProfessionsOpen()), tostring(name),
		tostring(id), tostring(InCombatLockdown()))
end

-- After a craft the log records what the client does for a while: casts, craft events, errors.
local function StartWatch(b, what, amount)
	watchUntil = GetTime() + 12
	watchSeen = {}
	Log("CRAFT [%s] recipe %d (%s) amount=%s count before=%s | %s", what, b.recipeID, tostring(b.name),
		tostring(amount), tostring(b.count), Context())
	C_Timer.After(1.5, function()
		local started = watchSeen and (watchSeen.UNIT_SPELLCAST_START or watchSeen.TRADE_SKILL_CRAFT_BEGIN)
		Log("  after 1.5 s: craft started=%s", tostring(started ~= nil))
	end)
end

local function CraftNow(b, amount, what)
	StartWatch(b, what, amount)
	crafting = { id = b.recipeID, amount = amount, done = 0, time = GetTime() }
	local ok, result = pcall(TS.CraftRecipe, b.recipeID, amount)
	if not ok then
		Log("  CraftRecipe(%d, %d): LUA ERROR %s", b.recipeID, amount, tostring(result))
		crafting = nil
	end
end

-- The frames that get TRADE_SKILL_SHOW, apart from this addon's own. One of them opens the window.
local function ShowListeners()
	local frames = {}
	if type(GetFramesRegisteredForEvent) == "function" then
		for _, frame in ipairs({ GetFramesRegisteredForEvent("TRADE_SKILL_SHOW") }) do
			if not (frame.IsForbidden and frame:IsForbidden()) and not frame.pbOwn then
				frames[#frames + 1] = frame
			end
		end
	end
	return frames
end

local function FrameNames(frames)
	local names = {}
	for i, frame in ipairs(frames) do
		names[i] = (frame.GetDebugName and frame:GetDebugName()) or (frame.GetName and frame:GetName()) or tostring(frame)
	end
	return #names > 0 and table.concat(names, ", ") or "none"
end

local function Unmute()
	if silent.waiting then
		silent.waiting = false
		for _, frame in ipairs(muted) do
			frame:RegisterEvent("TRADE_SKILL_SHOW")
		end
		wipe(muted)
	end
end

-- who: anything with profName and skillLine. Returns whether the client accepted the request.
local function SilentLoad(who, why)
	if InCombatLockdown() then
		return false
	end
	Unmute()
	silent.wasOpen = ProfessionsOpen()
	-- An open window keeps its event: it is visible anyway and has to follow the profession.
	if not silent.wasOpen then
		for _, frame in ipairs(ShowListeners()) do
			frame:UnregisterEvent("TRADE_SKILL_SHOW")
			muted[#muted + 1] = frame
		end
	end
	silent.waiting = true
	silent.prof = who.profName
	silent.token = (silent.token or 0) + 1
	local token = silent.token
	C_Timer.After(1.5, function()
		if silent.token == token then
			Unmute()
		end
	end)
	local ok, result = pcall(TS.OpenTradeSkill, who.skillLine)
	Log("LOAD [%s]: %s (ID %d), muted: %s -> %s | %s", why, who.profName, who.skillLine, FrameNames(muted),
		ok and tostring(result) or ("LUA ERROR " .. tostring(result)), Context())
	if not (ok and result) then
		Unmute()
		return false
	end
	return true
end

-- TRADE_SKILL_SHOW arrived while the window's listeners were muted.
local function OnSilentShow()
	if not silent.waiting then
		return
	end
	local wasOpen = silent.wasOpen
	if not wasOpen then
		silent.loaded = silent.prof
		silent.idle = nil
	end
	-- Next frame: this event is still being handed out, and the muted frames must not get it after all.
	C_Timer.After(0, Unmute)
	C_Timer.After(0.4, function()
		if not wasOpen and ProfessionsOpen() and not silentBroken then
			silentBroken = true
			Log("SILENT LOAD FAILED: the window opened anyway. No more loading on hover this session.")
		end
	end)
end

local function RunJob()
	if not job then
		return
	end
	if GetTime() - job.time > 3 then
		Log("  job recipe %d dropped: profession not loaded after 3 s | %s", job.b.recipeID, Context())
		print(PREFIX .. L["The profession could not be loaded. (/qc log)"])
		job = nil
	elseif LoadedProfession() == job.b.profName and TS.GetRecipeInfo(job.b.recipeID) then
		local ready = job
		job = nil
		CraftNow(ready.b, ready.amount, string.format("after load, %.2f s", GetTime() - ready.time))
	else
		C_Timer.After(0.1, function()
			Safe("job", RunJob)
		end)
	end
end

-- b: a fan button. all: craft as many as the bags allow.
local function Craft(b, all)
	if InCombatLockdown() then
		UIErrorsFrame:AddMessage(L["Nothing can be crafted in combat."], 1, 0.3, 0.3)
		return
	end
	local amount = all and math.max(b.count or 1, 1) or 1
	-- A copy: the fan's buttons are reused for other recipes while a job waits.
	local copy = { recipeID = b.recipeID, name = b.name, profName = b.profName, skillLine = b.skillLine, count = b.count }
	if LoadedProfession() == b.profName and not ForeignWindow() then
		CraftNow(copy, amount, "profession was loaded")
	else
		job = { b = copy, amount = amount, time = GetTime() }
		if SilentLoad(copy, "click") then
			RunJob()
		else
			job = nil
		end
	end
end

-- Closes a silently loaded profession once it is no longer needed. Never while a craft runs: closing
-- stops a "craft all" in the middle.
C_Timer.NewTicker(0.5, function()
	Safe("silent close", function()
		if crafting and GetTime() - (crafting.last or crafting.time) > (crafting.begun and 20 or 2) then
			crafting = nil
		end
		if not silent.loaded then
			return
		end
		if ProfessionsOpen() then
			silent.loaded = nil -- the visible window owns the profession now
		elseif crafting or job or fanOwner or InCombatLockdown() then
			silent.idle = nil
		else
			silent.idle = (silent.idle or 0) + 0.5
			if silent.idle >= 1.5 then
				silent.loaded, silent.idle = nil, nil
				if TS.CloseTradeSkill then
					TS.CloseTradeSkill()
				end
			end
		end
	end)
end)

---------------------------------------------------------------------------
-- Bar
---------------------------------------------------------------------------
-- Frame levels inside the MEDIUM strata, bottom to top: the bar's background and border, the recipe
-- icons (so they lie over the border), the profession icons (so the recipes come out from behind them),
-- the drag overlay.
local LEVEL_BAR, LEVEL_FAN, LEVEL_ICON, LEVEL_DRAG = 2, 6, 20, 60

local bar = CreateFrame("Frame", "QuickCraftForeverBar", UIParent, "BackdropTemplate")
bar:SetClampedToScreen(true)
bar:SetMovable(true)
bar:SetFrameStrata("MEDIUM")
bar:SetFrameLevel(LEVEL_BAR)
bar.art = bar:CreateTexture(nil, "BACKGROUND")
bar.art:SetAllPoints()
bar.art:Hide()

-- Drag overlay: covers the bar while it is unlocked. Locked, it is gone and the icons take the clicks.
local dragLayer = CreateFrame("Frame", nil, bar)
dragLayer:SetAllPoints(bar)
dragLayer:SetFrameLevel(LEVEL_DRAG)
dragLayer:EnableMouse(true)
dragLayer:RegisterForDrag("LeftButton")
dragLayer:Hide()
dragLayer.tint = dragLayer:CreateTexture(nil, "BACKGROUND")
dragLayer.tint:SetAllPoints()
dragLayer.tint:SetColorTexture(0.3, 0.7, 1, 0.3)
dragLayer:SetScript("OnDragStart", function()
	bar:StartMoving()
end)
dragLayer:SetScript("OnDragStop", function()
	bar:StopMovingOrSizing()
	local point, _, _, x, y = bar:GetPoint()
	DB().pos = { point, x, y }
end)
dragLayer:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
	GameTooltip:SetText(L["Drag to move"])
	GameTooltip:AddLine(L["Lock it with /qc lock or in the options"], 0.7, 0.7, 0.7)
	GameTooltip:Show()
end)
dragLayer:SetScript("OnLeave", GameTooltip_Hide)

local buttons = {}
local ShowFan, CloseFan, FanSide -- defined with the fan

local function BarRow()
	local s = Cfg()
	return s.showBar and (s.barHeight + 2) or 0
end

-- Where a tooltip for a profession icon goes: into the space its fan would take.
local function ProfessionTooltip(btn)
	local side = FanSide()
	GameTooltip:SetOwner(btn, "ANCHOR_NONE")
	GameTooltip:ClearAllPoints()
	if side == "RIGHT" then
		GameTooltip:SetPoint("TOPLEFT", btn, "TOPRIGHT", 6, 0)
	elseif side == "LEFT" then
		GameTooltip:SetPoint("TOPRIGHT", btn, "TOPLEFT", -6, 0)
	elseif side == "UP" then
		GameTooltip:SetPoint("BOTTOMLEFT", btn, "TOPLEFT", 0, 6)
	else
		GameTooltip:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -6 - BarRow())
	end
end

local function NewProfessionButton()
	local btn = CreateFrame("Button", nil, bar)
	btn:SetFrameLevel(LEVEL_ICON)
	btn:RegisterForClicks("LeftButtonUp")
	btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

	btn.border = btn:CreateTexture(nil, "BACKGROUND")
	btn.border:SetPoint("TOPLEFT", -1, 1)
	btn.border:SetPoint("BOTTOMRIGHT", 1, -1)
	btn.border:SetColorTexture(0, 0, 0, 1)

	btn.icon = btn:CreateTexture(nil, "ARTWORK")
	btn.icon:SetAllPoints()

	btn.text = btn:CreateFontString(nil, "OVERLAY")
	btn.text:SetPoint("BOTTOM", btn, "BOTTOM", 0, 2)

	btn.bar = CreateFrame("StatusBar", nil, btn)
	btn.bar:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
	btn.bar.bg = btn.bar:CreateTexture(nil, "BACKGROUND")
	btn.bar.bg:SetAllPoints()
	btn.bar.bg:SetColorTexture(0, 0, 0, 0.6)

	-- Click opens the profession; a second click on the open one closes it.
	btn:SetScript("OnClick", function(self)
		Safe("profession click", function()
			if OpenProfession() == self.profName and TS.CloseTradeSkill then
				TS.CloseTradeSkill()
				return
			end
			if silent.loaded and TS.CloseTradeSkill then
				-- Loaded without its window: close that first, or the client has nothing new to show.
				silent.loaded = nil
				TS.CloseTradeSkill()
			end
			local ok = TS.OpenTradeSkill(self.skillLine)
			Log("open profession: %s (ID %d) -> %s", self.profName, self.skillLine, tostring(ok))
		end)
	end)
	btn:SetScript("OnEnter", function(self)
		Safe("hover", ShowFan, self)
	end)
	btn:SetScript("OnLeave", GameTooltip_Hide)
	return btn
end

local function UpdateBar()
	local s, st = Cfg(), Style()
	local icon = s.iconSize
	local pad = s.frame and st.pad or 2
	local list = PlayerProfessions()
	bar:SetScale(s.scale)
	-- The frame: the client's own art where the style names one and the client has it, a backdrop otherwise.
	local art = s.frame and st.frameAtlas and bar.art.SetTextureSliceMargins and AtlasExists(st.frameAtlas)
	if art then
		bar:SetBackdrop(nil)
		bar.art:SetAtlas(st.frameAtlas)
		bar.art:SetTextureSliceMargins(st.frameSlice, st.frameSlice, st.frameSlice, st.frameSlice)
		bar.art:SetTextureSliceMode(Enum.UITextureSliceMode and Enum.UITextureSliceMode.Stretched or 0)
	elseif s.frame then
		bar:SetBackdrop(st.backdrop)
		bar:SetBackdropColor(st.bg[1], st.bg[2], st.bg[3], st.bg[4])
		bar:SetBackdropBorderColor(st.edge[1], st.edge[2], st.edge[3], st.edge[4])
	else
		bar:SetBackdrop(nil)
	end
	bar.art:SetShown(art and true or false)
	dragLayer:SetShown(not s.locked)

	local texture = BarTexture()
	local barR, barG, barB = BarColor()
	local prev
	for i, prof in ipairs(list) do
		local btn = buttons[i] or NewProfessionButton()
		buttons[i] = btn
		btn.skillLine = prof.skillLine
		btn.profName = prof.name
		btn:SetSize(icon, icon)
		btn.border:SetShown(st.iconBorder)
		btn.icon:SetTexture(prof.icon)
		btn.icon:SetTexCoord(st.coords[1], st.coords[2], st.coords[3], st.coords[4])
		btn.bar:SetSize(icon, s.barHeight)
		btn.bar:SetStatusBarTexture(texture)
		btn.bar:SetStatusBarColor(barR, barG, barB)
		btn.bar:SetShown(s.showBar)
		ApplyFont(btn.text)
		btn.text:SetShown(s.showText)
		if prof.skill and prof.max then
			btn.bar:SetMinMaxValues(0, math.max(prof.max, 1))
			btn.bar:SetValue(prof.skill)
			btn.text:SetText(string.format("%d/%d", prof.skill, prof.max))
		else
			btn.bar:SetMinMaxValues(0, 1)
			btn.bar:SetValue(0)
			btn.text:SetText("?")
		end
		btn:ClearAllPoints()
		if not prev then
			btn:SetPoint("TOPLEFT", bar, "TOPLEFT", pad, -pad)
		elseif s.vertical then
			btn:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -(s.spacing + BarRow()))
		else
			btn:SetPoint("TOPLEFT", prev, "TOPRIGHT", s.spacing, 0)
		end
		btn:Show()
		prev = btn
	end
	for i = #list + 1, #buttons do
		buttons[i]:Hide()
	end

	local n = math.max(#list, 1)
	if s.vertical then
		bar:SetSize(icon + 2 * pad, 2 * pad + n * (icon + BarRow()) + (n - 1) * s.spacing)
	else
		bar:SetSize(2 * pad + n * icon + (n - 1) * s.spacing, icon + BarRow() + 2 * pad)
	end
end

---------------------------------------------------------------------------
-- Fan: the profession's favourite recipes as icons that slide out from behind its icon.
--   Click an icon              craft one
--   Click the number on it     craft all (the number is how many the bags allow)
---------------------------------------------------------------------------
local fan = CreateFrame("Frame", "QuickCraftForeverFan", UIParent)
fan:SetFrameStrata("MEDIUM")
fan:SetFrameLevel(LEVEL_FAN)
fan:Hide()

local driver = CreateFrame("Frame")
driver:Hide()

local fanButtons = {}
local fanCount = 0
local fanSide
local fanProgress, fanTarget = 0, 0
local away, sinceCount = 0, 0

local function Hovered(frame)
	return frame:IsShown() and frame:IsMouseOver()
end

-- Vertical bar: left or right. Horizontal bar: up or down. Always toward the nearer screen middle.
function FanSide()
	if Cfg().vertical then
		local left = bar:GetLeft() or 0
		local right = UIParent:GetWidth() / bar:GetScale() - (bar:GetRight() or 0)
		return left <= right and "RIGHT" or "LEFT"
	end
	local bottom = bar:GetBottom() or 0
	local top = UIParent:GetHeight() / bar:GetScale() - (bar:GetTop() or 0)
	return bottom <= top and "UP" or "DOWN"
end

local function ItemName(itemID)
	local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
	return Text(name) or string.format(L["Item %d"], itemID)
end

-- The tooltip never lies on the fan or the bar: beside a column of recipes, above or below a row of
-- them, on the side with more screen, and growing away from the bar.
local function FanTooltip(b, overAll)
	if not Cfg().tooltips then
		return
	end
	GameTooltip:SetOwner(b, "ANCHOR_NONE")
	GameTooltip:ClearAllPoints()
	local scale = b:GetEffectiveScale() / UIParent:GetEffectiveScale()
	local x, y = b:GetCenter()
	if fanSide == "RIGHT" or fanSide == "LEFT" then
		local upper = y * scale > UIParent:GetHeight() / 2
		local h = fanSide == "RIGHT" and "LEFT" or "RIGHT"
		if upper then
			GameTooltip:SetPoint("TOP" .. h, b, "BOTTOM" .. h, 0, -6)
		else
			GameTooltip:SetPoint("BOTTOM" .. h, b, "TOP" .. h, 0, 6)
		end
	else
		local rightHalf = x * scale > UIParent:GetWidth() / 2
		local v = fanSide == "UP" and "BOTTOM" or "TOP"
		if rightHalf then
			GameTooltip:SetPoint(v .. "RIGHT", b, v .. "LEFT", -6, 0)
		else
			GameTooltip:SetPoint(v .. "LEFT", b, v .. "RIGHT", 6, 0)
		end
	end

	GameTooltip:SetText(b.name or "?", 1, 1, 1)
	if b.count == 0 then
		GameTooltip:AddLine(L["Missing materials"], 1, 0.3, 0.3)
		for _, reagent in ipairs(b.entry and b.entry.reagents or {}) do
			local have = BagCount(reagent[1])
			if have < reagent[2] then
				GameTooltip:AddDoubleLine(ItemName(reagent[1]), have .. "/" .. reagent[2], 0.7, 0.7, 0.7, 1, 0.3, 0.3)
			end
		end
	elseif overAll and b.count then
		GameTooltip:AddLine(string.format(L["Click: craft all %d"], b.count), 1, 0.82, 0)
	else
		GameTooltip:AddLine(L["Click: craft 1"], 1, 0.82, 0)
	end
	GameTooltip:Show()
end

local function PaintFanButton(b)
	local st = Style()
	local lacking = b.count == 0
	b.border:SetShown(st.iconBorder)
	b.icon:SetTexCoord(st.coords[1], st.coords[2], st.coords[3], st.coords[4])
	b.icon:SetDesaturated(lacking)
	b.icon:SetVertexColor(lacking and 0.55 or 1, lacking and 0.55 or 1, lacking and 0.55 or 1)
	local known = b.count ~= nil and b.count > 0
	b.all:SetShown(known)
	if known then
		b.all.text:SetText(b.count)
		-- The click area is as wide as its number, with a little room around it.
		b.all:SetSize(math.max((b.all.text:GetStringWidth() or 8) + 6, 16), Cfg().fontSize + 5)
	end
end

local function NewFanButton()
	local b = CreateFrame("Button", nil, fan)
	b:RegisterForClicks("LeftButtonUp")
	b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

	b.border = b:CreateTexture(nil, "BACKGROUND")
	b.border:SetPoint("TOPLEFT", -1, 1)
	b.border:SetPoint("BOTTOMRIGHT", 1, -1)
	b.border:SetColorTexture(0, 0, 0, 1)

	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()

	b.all = CreateFrame("Button", nil, b)
	b.all:RegisterForClicks("LeftButtonUp")
	b.all:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
	b.all.bg = b.all:CreateTexture(nil, "BACKGROUND")
	b.all.bg:SetAllPoints()
	b.all.bg:SetColorTexture(0, 0, 0, 0.6)
	b.all.hover = b.all:CreateTexture(nil, "HIGHLIGHT")
	b.all.hover:SetAllPoints()
	b.all.hover:SetColorTexture(1, 0.82, 0, 0.35)
	b.all.text = b.all:CreateFontString(nil, "OVERLAY")
	b.all.text:SetPoint("CENTER", 0, 0)

	b:SetScript("OnClick", function(self)
		Safe("recipe click", Craft, self, false)
	end)
	b.all:SetScript("OnClick", function(self)
		Safe("recipe click", Craft, self:GetParent(), true)
	end)
	b:SetScript("OnEnter", function(self)
		Safe("tooltip", FanTooltip, self, false)
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)
	b.all:SetScript("OnEnter", function(self)
		Safe("tooltip", FanTooltip, self:GetParent(), true)
	end)
	b.all:SetScript("OnLeave", function(self)
		-- Back onto the icon itself: its own tooltip returns.
		GameTooltip:Hide()
		local parent = self:GetParent()
		if parent:IsMouseOver() then
			Safe("tooltip", FanTooltip, parent, false)
		end
	end)
	return b
end

local function UpdateCounts()
	for i = 1, fanCount do
		local b = fanButtons[i]
		local count = b.entry and CraftCount(b.entry, b.profName)
		if count ~= b.count then
			b.count = count
			PaintFanButton(b)
		end
	end
end

-- Puts every icon at its place for the animation's progress (0 = behind the profession icon, 1 = out).
local function LayoutFan(progress)
	local s = Cfg()
	local size, gap = s.iconSize, s.fanSpacing
	local eased = 1 - (1 - progress) ^ 3
	for i = 1, fanCount do
		local b = fanButtons[i]
		local target = gap + (i - 1) * (size + gap)
		local offset = -size + (target + size) * eased
		b:ClearAllPoints()
		if fanSide == "RIGHT" then
			b:SetPoint("LEFT", fan, "LEFT", offset, 0)
		elseif fanSide == "LEFT" then
			b:SetPoint("RIGHT", fan, "RIGHT", -offset, 0)
		elseif fanSide == "UP" then
			b:SetPoint("BOTTOM", fan, "BOTTOM", 0, offset)
		else
			b:SetPoint("TOP", fan, "TOP", 0, -offset)
		end
		b:SetAlpha(math.min(1, progress * 2))
		-- An icon takes the mouse only once it has left the profession icon. Under it, its tooltip
		-- would flash up for a moment while the fan opens.
		local clear = offset >= 0
		if b.mouseOn ~= clear then
			b.mouseOn = clear
			b:EnableMouse(clear)
			b.all:EnableMouse(clear)
		end
	end
end

local function HideFanNow()
	for _, b in ipairs(fanButtons) do
		b:Hide()
	end
	fan:Hide()
	driver:Hide()
	fanOwner, fanCount, fanProgress, fanTarget = nil, 0, 0, 0
end

function CloseFan()
	if fanOwner and fanTarget ~= 0 then
		fanTarget = 0
	end
end

function ShowFan(anchor)
	-- Nothing can be crafted in combat, and loading a profession is not allowed there.
	if InCombatLockdown() then
		return
	end
	local s = Cfg()
	local list = FavouritesOf(anchor)
	if #list == 0 then
		CloseFan()
		if s.tooltips then
			ProfessionTooltip(anchor)
			GameTooltip:SetText(anchor.profName, 1, 1, 1)
			GameTooltip:AddLine(L["No favorites. Click the star next to a recipe in the profession window."], 0.7, 0.7, 0.7, true)
			GameTooltip:Show()
		end
		return
	end
	if fanOwner == anchor then
		fanTarget, away = 1, 0
		return
	end

	local size, gap = s.iconSize, s.fanSpacing
	HideFanNow()
	fanOwner, fanSide, fanCount = anchor, FanSide(), #list
	for i, entry in ipairs(list) do
		local b = fanButtons[i] or NewFanButton()
		fanButtons[i] = b
		b.entry, b.recipeID, b.name = entry, entry.id, entry.name
		b.profName, b.skillLine = anchor.profName, anchor.skillLine
		b.count = CraftCount(entry, anchor.profName)
		b:SetSize(size, size)
		b.icon:SetTexture(entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
		ApplyFont(b.all.text)
		PaintFanButton(b)
		b:Show()
	end

	-- The holder sits flush against the profession icon, in screen coordinates. Bar and holder have the
	-- same scale and the same parent, so the bar's coordinates are the holder's.
	local length = fanCount * (size + gap) + gap
	fan:SetScale(s.scale)
	fan:ClearAllPoints()
	if fanSide == "RIGHT" then
		fan:SetSize(length, size)
		fan:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", anchor:GetRight(), anchor:GetTop())
	elseif fanSide == "LEFT" then
		fan:SetSize(length, size)
		fan:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", anchor:GetLeft(), anchor:GetTop())
	elseif fanSide == "UP" then
		fan:SetSize(size, length)
		fan:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", anchor:GetLeft(), anchor:GetTop())
	else
		fan:SetSize(size, length)
		fan:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", anchor:GetLeft(), anchor:GetBottom() - BarRow())
	end

	fanProgress = s.animTime > 0 and 0 or 1
	fanTarget, away, sinceCount = 1, 0, 0
	LayoutFan(fanProgress)
	fan:Show()
	driver:Show()

	-- Have the profession loaded before the click. Not while a craft runs (changing the profession would
	-- stop it), not while the player casts anything (loading is a cast itself and would interrupt), and
	-- not with the window open (it would visibly jump to another profession on every hover).
	if not hoverLoadFailed and not silentBroken and not crafting and not job and not ProfessionsOpen()
		and LoadedProfession() ~= anchor.profName and not PlayerCasting() then
		if not SilentLoad(anchor, "hover") then
			hoverLoadFailed = true
			Log("loading on hover refused; from now on the click loads")
		end
	end
end

-- One loop while the fan is out: animation, closing when the mouse has left, counts.
driver:SetScript("OnUpdate", function(_, elapsed)
	local ok = Safe("fan", function()
		local duration = Cfg().animTime
		if fanProgress ~= fanTarget then
			local step = duration > 0 and elapsed / duration or 1
			if fanTarget > fanProgress then
				fanProgress = math.min(1, fanProgress + step)
			else
				fanProgress = math.max(0, fanProgress - step * 1.5)
			end
			LayoutFan(fanProgress)
		end
		if fanTarget == 0 and fanProgress <= 0 then
			HideFanNow()
			return
		end

		local over = Hovered(bar) or Hovered(fan)
		for i = 1, fanCount do
			over = over or Hovered(fanButtons[i])
		end
		if over then
			away = 0
			-- Coming back while it closes opens it again, unless the mouse is on another profession.
			if fanTarget == 0 and (Hovered(fan) or (fanOwner and Hovered(fanOwner))) then
				fanTarget = 1
			end
		else
			away = away + elapsed
			if away >= 0.25 and fanTarget == 1 then
				fanTarget = 0
			end
		end

		sinceCount = sinceCount + elapsed
		if sinceCount >= 0.5 then
			sinceCount = 0
			UpdateCounts()
		end
	end)
	if not ok then
		HideFanNow()
	end
end)

---------------------------------------------------------------------------
-- Stars in the Professions window's recipe list: click = favourite on/off.
---------------------------------------------------------------------------
local STAR_ATLAS = "auctionhouse-icon-favorite"
local starAtlas -- nil = not checked yet
local decorated = 0

local function GamepadUI()
	return InputUtil ~= nil and InputUtil.IsGamepadUIEnabled ~= nil and InputUtil.IsGamepadUIEnabled() == true
end

local function PaintStar(star)
	local on = star.recipeID ~= nil and IsFavourite(star.recipeID)
	star.on = on
	if starAtlas then
		star.tex:SetDesaturated(not on)
		star.tex:SetAlpha(on and 1 or (star:IsMouseOver() and 0.8 or 0.3))
	elseif on then
		star.tex:SetColorTexture(1, 0.82, 0, 1)
	else
		star.tex:SetColorTexture(1, 1, 1, star:IsMouseOver() and 0.5 or 0.15)
	end
end

local function DecorateRow(row, elementData)
	local data = elementData and elementData.GetData and elementData:GetData()
	local info = data and data.recipeInfo
	local recipeID = info and Number(info.recipeID)
	local star = row.pbStar
	-- Only the player's own, learned recipes can be favourites worth a craft button.
	if not recipeID or ForeignWindow() or Readable(info.learned) ~= true then
		if star then
			star:Hide()
		end
		return
	end
	if not star then
		if starAtlas == nil then
			local ok, atlas = pcall(function()
				return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(STAR_ATLAS)
			end)
			starAtlas = ok and atlas ~= nil
		end
		star = CreateFrame("Button", nil, row)
		star:SetSize(14, 14)
		star:SetFrameLevel(row:GetFrameLevel() + 5)
		star.tex = star:CreateTexture(nil, "OVERLAY")
		if starAtlas then
			star.tex:SetAllPoints()
			star.tex:SetAtlas(STAR_ATLAS)
		else
			star.tex:SetPoint("CENTER")
			star.tex:SetSize(8, 8)
		end
		star:SetScript("OnClick", function(self)
			if self.recipeID then
				Safe("star", ToggleFavourite, self.recipeID)
				PaintStar(self)
			end
		end)
		star:SetScript("OnEnter", function(self)
			PaintStar(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(self.on and L["Remove favorite"] or L["Mark as favorite"])
			GameTooltip:Show()
		end)
		star:SetScript("OnLeave", function(self)
			GameTooltip:Hide()
			PaintStar(self)
		end)
		row.pbStar = star
		decorated = decorated + 1
	end
	-- Behind the recipe name and its count. The space in front of the name is the client's own
	-- difficulty icon, and the row's right edge belongs to other addons' row text.
	local after = row.Count and row.Count:IsShown() and row.Count or row.Label
	star:ClearAllPoints()
	if after then
		star:SetPoint("LEFT", after, "RIGHT", 3, 0)
	else
		star:SetPoint("RIGHT", row, "RIGHT", -2, 0)
	end
	star.recipeID = recipeID
	star:Show()
	PaintStar(star)
end

function RefreshRows()
	local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
	local box = page and page.RecipeList and page.RecipeList.ScrollBox
	if box and box.ForEachFrame then
		box:ForEachFrame(function(row, elementData)
			DecorateRow(row, elementData)
		end)
	end
end

local attached
local function AttachRecipeList()
	if attached then
		return
	end
	attached = true
	-- Under the gamepad interface, addon scripts on the Professions window taint its gamepad focus
	-- (known from SkillUp Forever's changelog). No stars there; /qc mark still works.
	if GamepadUI() then
		Log("gamepad interface on: no stars in the recipe list")
		return
	end
	local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
	local box = page and page.RecipeList and page.RecipeList.ScrollBox
	if not (box and ScrollUtil and ScrollUtil.AddInitializedFrameCallback) then
		Log("recipe list not found: ProfessionsFrame=%s CraftingPage=%s ScrollBox=%s ScrollUtil=%s",
			tostring(ProfessionsFrame ~= nil), tostring(page ~= nil), tostring(box ~= nil), tostring(ScrollUtil ~= nil))
		return
	end
	ScrollUtil.AddInitializedFrameCallback(box, function(_, row, elementData)
		Safe("recipe row", DecorateRow, row, elementData)
	end, bar)
	RefreshRows()
end

---------------------------------------------------------------------------
-- Options. An own panel, shown inside the game's options (Options > AddOns > QuickCraft Forever) or, where
-- the client cannot host it, as a window of its own. Every number has a slider and a field to type in.
-- The controls are drawn from plain colours, so they do not depend on any texture file.
---------------------------------------------------------------------------
local function ApplySettings()
	HideFanNow()
	UpdateBar()
end

local panel = CreateFrame("Frame", "QuickCraftForeverOptions", UIParent, "BackdropTemplate")
panel:Hide()
panel.name = "QuickCraft Forever"
-- Asked for by the game's options frame on some client versions.
panel.OnCommit, panel.OnDefault, panel.OnRefresh = function() end, function() end, function() end

local settingsCategory
local widgets = {}
local ACCENT = { 1, 0.82, 0 }
local LABEL_W, ROW_H = 210, 28

local function SetOption(key, value)
	Cfg()[key] = value
	Safe("setting", ApplySettings)
end

local function RefreshOptions()
	for _, widget in ipairs(widgets) do
		widget.refresh()
	end
end

local function BuildOptions()
	local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 12, -44)
	scroll:SetPoint("BOTTOMRIGHT", -30, 12)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(540, 10)
	scroll:SetScrollChild(content)

	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 14, -14)
	title:SetText("QuickCraft Forever  |cff808080" .. VERSION .. "|r")

	local reset = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	reset:SetSize(130, 22)
	reset:SetPoint("TOPRIGHT", -34, -12)
	reset:SetText(L["Defaults"])
	reset:SetScript("OnClick", function()
		for key, value in pairs(DEFAULTS) do
			Cfg()[key] = value
		end
		Safe("setting", ApplySettings)
		RefreshOptions()
	end)

	local y = 0
	local function Row(label, tip)
		local row = CreateFrame("Frame", nil, content)
		row:SetSize(540, ROW_H)
		row:SetPoint("TOPLEFT", 0, -y)
		y = y + ROW_H
		row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		row.label:SetPoint("LEFT", 4, 0)
		row.label:SetWidth(LABEL_W)
		row.label:SetJustifyH("LEFT")
		row.label:SetText(label)
		if tip then
			row:EnableMouse(true)
			row:SetScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
				GameTooltip:SetText(label, 1, 1, 1)
				GameTooltip:AddLine(tip, 1, 0.82, 0, true)
				GameTooltip:Show()
			end)
			row:SetScript("OnLeave", GameTooltip_Hide)
		end
		return row
	end

	local function Header(text)
		y = y + 8
		local fs = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		fs:SetPoint("TOPLEFT", 4, -y)
		fs:SetText(text)
		local line = content:CreateTexture(nil, "ARTWORK")
		line:SetColorTexture(1, 1, 1, 0.15)
		line:SetPoint("TOPLEFT", 4, -y - 18)
		line:SetSize(520, 1)
		y = y + 26
	end

	local function Check(key, label, tip)
		local row = Row(label, tip)
		local box = CreateFrame("Button", nil, row)
		box:SetSize(18, 18)
		box:SetPoint("LEFT", LABEL_W + 10, 0)
		box.bg = box:CreateTexture(nil, "BACKGROUND")
		box.bg:SetAllPoints()
		box.bg:SetColorTexture(1, 1, 1, 0.14)
		box.tick = box:CreateTexture(nil, "ARTWORK")
		box.tick:SetPoint("TOPLEFT", 4, -4)
		box.tick:SetPoint("BOTTOMRIGHT", -4, 4)
		box.tick:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 1)
		box:SetScript("OnClick", function()
			SetOption(key, not Cfg()[key])
			box.tick:SetShown(Cfg()[key])
		end)
		widgets[#widgets + 1] = { refresh = function()
			box.tick:SetShown(Cfg()[key])
		end }
	end

	local function Slide(key, label, tip, min, max, step, format, unit)
		local row = Row(label, tip)
		local slider = CreateFrame("Slider", nil, row)
		slider:SetOrientation("HORIZONTAL")
		slider:SetSize(190, 16)
		slider:SetPoint("LEFT", LABEL_W + 10, 0)
		slider:SetMinMaxValues(min, max)
		slider:SetValueStep(step)
		slider:SetObeyStepOnDrag(true)
		slider.track = slider:CreateTexture(nil, "BACKGROUND")
		slider.track:SetColorTexture(1, 1, 1, 0.16)
		slider.track:SetPoint("LEFT")
		slider.track:SetPoint("RIGHT")
		slider.track:SetHeight(4)
		local thumb = slider:CreateTexture(nil, "ARTWORK")
		thumb:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 1)
		thumb:SetSize(8, 16)
		slider:SetThumbTexture(thumb)

		local edit = CreateFrame("EditBox", nil, row)
		edit:SetSize(56, 20)
		edit:SetPoint("LEFT", slider, "RIGHT", 12, 0)
		edit:SetAutoFocus(false)
		edit:SetFontObject(GameFontHighlightSmall)
		edit:SetJustifyH("CENTER")
		edit.bg = edit:CreateTexture(nil, "BACKGROUND")
		edit.bg:SetAllPoints()
		edit.bg:SetColorTexture(1, 1, 1, 0.1)
		if unit then
			local fs = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
			fs:SetPoint("LEFT", edit, "RIGHT", 6, 0)
			fs:SetText(unit)
		end

		local setting = false
		local function Show(value)
			setting = true
			slider:SetValue(value)
			setting = false
			edit:SetText(string.format(format, value))
			edit:SetCursorPosition(0)
		end
		local function Commit(value)
			value = math.max(min, math.min(max, value))
			-- Rounded to the step, without the float noise a slider leaves (0.95000004768).
			value = math.floor(value / step + 0.5) * step
			value = tonumber(string.format("%.4f", value))
			if value ~= Cfg()[key] then
				SetOption(key, value)
			end
			Show(value)
		end
		slider:SetScript("OnValueChanged", function(_, value)
			if not setting then
				Commit(value)
			end
		end)
		edit:SetScript("OnEnterPressed", function(self)
			local value = tonumber((self:GetText():gsub(",", ".")))
			Commit(value or Cfg()[key])
			self:ClearFocus()
		end)
		edit:SetScript("OnEscapePressed", function(self)
			Show(Cfg()[key])
			self:ClearFocus()
		end)
		edit:SetScript("OnEditFocusLost", function()
			Show(Cfg()[key])
		end)
		widgets[#widgets + 1] = { refresh = function()
			Show(Cfg()[key])
		end }
	end

	-- A dropdown of the addon's own. The client's dropdown menus are avoided: opened from addon code
	-- they are a known source of blocked actions on this client. One list frame serves every dropdown.
	local MENU_ROWS, MENU_ROW_H, MENU_W = 12, 20, 240
	local menu = CreateFrame("Frame", "QuickCraftForeverDropdown", UIParent, "BackdropTemplate")
	menu:SetFrameStrata("FULLSCREEN_DIALOG")
	menu:SetFrameLevel(100)
	menu:SetClampedToScreen(true)
	menu:EnableMouse(true)
	menu:EnableMouseWheel(true)
	menu:Hide()
	PaintBox(menu, { 0.06, 0.055, 0.05, 0.98 }, { 1, 1, 1, 0.25 })
	-- Behind the list, over everything else: a click beside the list closes it.
	local catcher = CreateFrame("Button", nil, UIParent)
	catcher:SetFrameStrata("FULLSCREEN_DIALOG")
	catcher:SetFrameLevel(90)
	catcher:SetAllPoints(UIParent)
	catcher:Hide()
	catcher:SetScript("OnClick", function() menu:Hide() end)
	menu:SetScript("OnHide", function() catcher:Hide() end)
	menu.thumb = menu:CreateTexture(nil, "OVERLAY")
	menu.thumb:SetColorTexture(1, 1, 1, 0.35)
	menu.thumb:SetWidth(3)
	menu.rows = {}

	local function MenuRedraw()
		local list, count = menu.list, #menu.list
		local visible = math.min(count, MENU_ROWS)
		menu.offset = math.max(0, math.min(menu.offset, count - visible))
		for i = 1, MENU_ROWS do
			local row = menu.rows[i]
			if not row then
				row = CreateFrame("Button", nil, menu)
				row:SetSize(MENU_W - 12, MENU_ROW_H)
				row:SetPoint("TOPLEFT", 4, -4 - (i - 1) * MENU_ROW_H)
				row.swatch = row:CreateTexture(nil, "BACKGROUND")
				row.swatch:SetPoint("TOPLEFT", 0, -2)
				row.swatch:SetPoint("BOTTOMRIGHT", 0, 2)
				row.hover = row:CreateTexture(nil, "HIGHLIGHT")
				row.hover:SetAllPoints()
				row.hover:SetColorTexture(1, 1, 1, 0.12)
				row.mark = row:CreateTexture(nil, "ARTWORK")
				row.mark:SetSize(4, MENU_ROW_H - 6)
				row.mark:SetPoint("LEFT", 0, 0)
				row.mark:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 1)
				row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
				row.text:SetPoint("LEFT", 10, 0)
				row.text:SetPoint("RIGHT", -4, 0)
				row.text:SetJustifyH("LEFT")
				row.text:SetWordWrap(false)
				row:SetScript("OnClick", function(self)
					local pick = menu.pick
					menu:Hide()
					pick(self.value)
				end)
				menu.rows[i] = row
			end
			local choice = list[menu.offset + i]
			if choice and i <= visible then
				row.value = choice[1]
				row.text:SetText(choice[2])
				row.mark:SetShown(choice[1] == menu.current)
				-- A font shows in its own face, a bar texture as a strip of itself.
				if menu.kind == "font" and not row.text:SetFont(FontPath(choice[1]), 12, "") then
					row.text:SetFontObject(GameFontHighlightSmall)
				elseif menu.kind ~= "font" then
					row.text:SetFontObject(GameFontHighlightSmall)
				end
				if menu.kind == "bar" then
					local texture = BarTexture(choice[1])
					if AtlasExists(texture) then
						row.swatch:SetAtlas(texture)
					else
						row.swatch:SetTexture(texture)
					end
					local r, g, b = BarColor()
					row.swatch:SetVertexColor(r, g, b, 0.75)
					row.swatch:Show()
				elseif menu.kind == "color" then
					local color = BAR_COLORS[choice[1]]
					row.swatch:SetTexture(WHITE)
					if color then
						row.swatch:SetVertexColor(color[1], color[2], color[3], 0.6)
					end
					row.swatch:SetShown(color ~= nil)
				else
					row.swatch:Hide()
				end
				row:Show()
			else
				row:Hide()
			end
		end
		menu:SetSize(MENU_W, visible * MENU_ROW_H + 8)
		-- A thin mark at the right edge shows where in a long list the view is.
		if count > visible then
			local track = visible * MENU_ROW_H
			menu.thumb:SetHeight(math.max(track * visible / count, 12))
			menu.thumb:ClearAllPoints()
			menu.thumb:SetPoint("TOPRIGHT", -2, -4 - (track - menu.thumb:GetHeight()) * menu.offset / (count - visible))
			menu.thumb:Show()
		else
			menu.thumb:Hide()
		end
	end
	menu:SetScript("OnMouseWheel", function(_, delta)
		menu.offset = menu.offset - delta * 3
		MenuRedraw()
	end)
	panel:HookScript("OnHide", function() menu:Hide() end)

	local function OpenMenu(button, list, current, kind, pick)
		if menu:IsShown() and menu.owner == button then
			menu:Hide()
			return
		end
		menu.owner, menu.list, menu.current, menu.kind, menu.pick = button, list, current, kind, pick
		menu.offset = 0
		for i, choice in ipairs(list) do
			if choice[1] == current then
				menu.offset = i - math.ceil(MENU_ROWS / 2)
			end
		end
		MenuRedraw()
		menu:SetScale(button:GetEffectiveScale() / UIParent:GetEffectiveScale())
		menu:ClearAllPoints()
		-- Below its button; above it where the screen ends first.
		if (button:GetBottom() or 0) * menu:GetScale() > menu:GetHeight() * menu:GetScale() + 20 then
			menu:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -2)
		else
			menu:SetPoint("BOTTOMLEFT", button, "TOPLEFT", 0, 2)
		end
		catcher:Show()
		menu:Show()
	end

	-- kind: "font", "bar" or "color" for a preview in the list; nil for plain text.
	local function Choice(key, label, tip, choices, kind)
		local row = Row(label, tip)
		local button = CreateFrame("Button", nil, row)
		button:SetSize(MENU_W, 20)
		button:SetPoint("LEFT", LABEL_W + 10, 0)
		button.bg = button:CreateTexture(nil, "BACKGROUND")
		button.bg:SetAllPoints()
		button.bg:SetColorTexture(1, 1, 1, 0.1)
		button.hover = button:CreateTexture(nil, "HIGHLIGHT")
		button.hover:SetAllPoints()
		button.hover:SetColorTexture(1, 1, 1, 0.08)
		button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		button.text:SetPoint("LEFT", 8, 0)
		button.text:SetPoint("RIGHT", -22, 0)
		button.text:SetJustifyH("LEFT")
		button.text:SetWordWrap(false)
		-- The arrow: two thin strokes, drawn rather than loaded.
		for _, side in ipairs({ -1, 1 }) do
			local stroke = button:CreateTexture(nil, "OVERLAY")
			stroke:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 1)
			stroke:SetSize(7, 2)
			stroke:SetPoint("CENTER", button, "RIGHT", -12 + side * 2.5, 0)
			stroke:SetRotation(side * -0.7)
		end

		local function Refresh()
			local name = tostring(Cfg()[key])
			for _, choice in ipairs(choices()) do
				if choice[1] == Cfg()[key] then
					name = choice[2]
				end
			end
			button.text:SetText(name)
		end
		button:SetScript("OnClick", function(self)
			OpenMenu(self, choices(), Cfg()[key], kind, function(value)
				SetOption(key, value)
				Refresh()
			end)
		end)
		widgets[#widgets + 1] = { refresh = Refresh }
	end

	Header(L["Bar"])
	Check("locked", L["Lock the bar"], L["Off: an overlay covers the bar, drag it to move the bar."])
	Check("vertical", L["Vertical layout"], L["Professions stacked top to bottom. The recipes then fan out to the left or right, otherwise up or down."])
	Slide("scale", L["Overall scale"], L["Scales the bar and the recipes together."], 0.5, 2, 0.05, "%.2f")
	Slide("iconSize", L["Icon size"], L["Edge length of the profession and recipe icons."], 16, 64, 1, "%d", "px")
	Slide("spacing", L["Profession spacing"], L["Gap between two profession icons."], 0, 30, 1, "%d", "px")
	Slide("fanSpacing", L["Recipe spacing"], L["Gap between two fanned-out recipe icons."], 0, 30, 1, "%d", "px")
	Slide("animTime", L["Fan-out duration"], L["Time the recipe icons take to slide out. 0 = no animation."], 0, 1, 0.05, "%.2f", "s")

	Header(L["Appearance"])
	Choice("style", L["Style"], L["WoW Forever: the bronze frame and bars of the default interface. EllesmereUI: dark panel, thin edges, cropped icons."], function()
		return { { "blizzard", "WoW Forever" }, { "ellesmere", "EllesmereUI" } }
	end)
	Check("frame", L["Frame and background"], L["Draws a frame with a background around the bar."])
	Check("tooltips", L["Show tooltips"], L["Tooltips on the recipe icons and on professions without favorites."])

	Header(L["Progress bar"])
	Check("showBar", L["Show the bar"], L["A bar under every profession icon."])
	Slide("barHeight", L["Bar thickness"], L["Height of the progress bar."], 1, 20, 1, "%d", "px")
	Choice("barTexture", L["Bar texture"], L["With LibSharedMedia, every texture registered there can be chosen."], BarChoices, "bar")
	Choice("barColor", L["Bar color"], L["Color of the progress bar."], BarColorChoices, "color")

	Header(L["Font"])
	Check("showText", L["Show the skill number"], L["A number like 312/375 on the profession icon."])
	Choice("font", L["Font face"], L["Automatic: EllesmereUI's font when that addon is present, otherwise the game's. With LibSharedMedia, every font registered there can be chosen."], FontChoices, "font")
	Slide("fontSize", L["Font size"], L["Size of the numbers on the icons."], 6, 24, 1, "%d", "pt")

	content:SetHeight(y + 10)
end

local built
panel:SetScript("OnShow", function()
	Safe("options", function()
		if not built then
			built = true
			BuildOptions()
		end
		RefreshOptions()
	end)
end)

local function RegisterOptions()
	if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
		local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, panel, "QuickCraft Forever")
		if ok and category then
			Settings.RegisterAddOnCategory(category)
			settingsCategory = category
			return
		end
		Log("options: registering with the game options failed (%s); own window", tostring(category))
	end
	-- A window of its own.
	panel:SetSize(600, 560)
	panel:SetPoint("CENTER")
	panel:SetFrameStrata("DIALOG")
	panel:SetMovable(true)
	panel:EnableMouse(true)
	panel:RegisterForDrag("LeftButton")
	panel:SetScript("OnDragStart", panel.StartMoving)
	panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
	PaintBox(panel, { 0.05, 0.05, 0.05, 0.95 }, { 1, 1, 1, 0.2 })
	local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -2, -2)
end

local function OpenOptions()
	if settingsCategory and Settings.OpenToCategory then
		Settings.OpenToCategory(settingsCategory:GetID())
	else
		panel:SetShown(not panel:IsShown())
	end
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local function Dump()
	forceLog = true
	Log("--- state (version %s) ---", VERSION)
	local version, build, _, interface = GetBuildInfo()
	Log("client %s build %s interface %s locale %s", tostring(version), tostring(build), tostring(interface), tostring(GetLocale()))
	local parts = {}
	for key in pairs(DEFAULTS) do
		parts[#parts + 1] = key .. "=" .. tostring(Cfg()[key])
	end
	table.sort(parts)
	Log("settings: %s", table.concat(parts, " "))
	Log("font: %s | bar texture: %s | LibSharedMedia=%s EllesmereUI=%s", tostring(FontPath()), tostring(BarTexture()),
		tostring(SharedMedia() ~= nil), tostring(type(EllesmereUI) == "table"))
	Log("options: in the game options=%s, built=%s", tostring(settingsCategory ~= nil), tostring(built))
	Log("API: SetRecipeFavorite=%s CraftRecipe=%s GetFramesRegisteredForEvent=%s", type(TS.SetRecipeFavorite),
		type(TS.CraftRecipe), type(GetFramesRegisteredForEvent))
	Log("load: waiting=%s silently loaded=%s failed=%s hover refused=%s job=%s crafting=%s | frames: %s",
		tostring(silent.waiting), tostring(silent.loaded), tostring(silentBroken), tostring(hoverLoadFailed),
		tostring(job and job.b.recipeID), tostring(crafting and crafting.id), FrameNames(ShowListeners()))
	Log("gamepad=%s | %s | shown recipe=%s", tostring(GamepadUI()), Context(), tostring(ShownRecipeID()))
	for _, prof in ipairs(PlayerProfessions()) do
		Log("bar profession: %s (ID %d) %s/%s", prof.name, prof.skillLine, tostring(prof.skill), tostring(prof.max))
	end
	for profName, entry in pairs(FavCache()) do
		Log("cache %s (ID %s): %d favorites", profName, tostring(entry.profID), #entry.list)
		for _, recipe in ipairs(entry.list) do
			Log("  %d %s, reagents: %d, craftable: %s", recipe.id, recipe.name, #(recipe.reagents or {}), tostring(CraftCount(recipe, profName)))
		end
	end
	Log("stars: attached=%s, rows with a star=%d", tostring(attached), decorated)
	Log("--- end ---")
	forceLog = false
end

SLASH_QUICKCRAFTFOREVER1 = "/qc"
SLASH_QUICKCRAFTFOREVER2 = "/quickcraft"
SlashCmdList["QUICKCRAFTFOREVER"] = function(msg)
	local cmd = (msg or ""):lower():match("^%s*(%S*)")
	if cmd == "" then
		Safe("options", OpenOptions)
	elseif cmd == "debug" then
		DB().debug = not DB().debug or nil
		print(PREFIX .. (DB().debug and L["Debug log on."] or L["Debug log off."]))
	elseif cmd == "log" then
		ToggleLog()
	elseif cmd == "dump" then
		Safe("dump", Dump)
		if not (logWin and logWin:IsShown()) then
			ToggleLog()
		end
	elseif cmd == "mark" then
		local recipeID = ShownRecipeID()
		if recipeID and OpenProfession() then
			Safe("mark", ToggleFavourite, recipeID)
			print(PREFIX .. string.format(IsFavourite(recipeID) and L["Recipe %d is now a favorite."] or L["Recipe %d is no longer a favorite."], recipeID))
		else
			print(PREFIX .. L["Open your own profession window and select a recipe first."])
		end
	elseif cmd == "reset" then
		DB().pos = nil
		bar:ClearAllPoints()
		bar:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 20, 200)
		print(PREFIX .. L["Position reset."])
	elseif cmd == "lock" or cmd == "unlock" then
		Cfg().locked = (cmd == "lock")
		ApplySettings()
		if built then
			RefreshOptions()
		end
		print(PREFIX .. (cmd == "lock" and L["Locked."] or L["Unlocked: drag the blue overlay."]))
	else
		print(PREFIX .. L["/qc (options) | lock | unlock | reset | mark | debug | log | dump"])
	end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local scanQueued

local function QueueScan()
	if not scanQueued then
		scanQueued = true
		C_Timer.After(0.2, function()
			scanQueued = nil
			Safe("scan", Scan)
		end)
	end
end

local TRADE_EVENTS = {
	TRADE_SKILL_SHOW = true,
	TRADE_SKILL_LIST_UPDATE = true,
	TRADE_SKILL_DATA_SOURCE_CHANGED = true,
	TRADE_SKILL_FAVORITES_CHANGED = true,
	NEW_RECIPE_LEARNED = true,
}

-- Follows the craft this addon started, so a silently loaded profession is not closed under it, and
-- writes what the client does after a craft into the log. Blocked actions are always logged.
local WATCH_ALWAYS = {
	ADDON_ACTION_BLOCKED = true,
	ADDON_ACTION_FORBIDDEN = true,
	MACRO_ACTION_BLOCKED = true,
	MACRO_ACTION_FORBIDDEN = true,
}
local WATCH_CRAFT = { "TRADE_SKILL_CRAFT_BEGIN", "UPDATE_TRADESKILL_CAST_STOPPED", "UI_ERROR_MESSAGE" }
local WATCH_CAST = { "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED" }

local watcher = CreateFrame("Frame")
watcher.pbOwn = true
for event in pairs(WATCH_ALWAYS) do
	pcall(watcher.RegisterEvent, watcher, event)
end
for _, event in ipairs(WATCH_CRAFT) do
	pcall(watcher.RegisterEvent, watcher, event)
end
for _, event in ipairs(WATCH_CAST) do
	pcall(watcher.RegisterUnitEvent, watcher, event, "player")
end
watcher:SetScript("OnEvent", function(_, event, ...)
	if crafting then
		local spell = Readable((select(3, ...)))
		if event == "TRADE_SKILL_CRAFT_BEGIN" then
			crafting.begun, crafting.last = true, GetTime()
		elseif event == "UNIT_SPELLCAST_START" then
			crafting.last = GetTime()
		elseif event == "UNIT_SPELLCAST_SUCCEEDED" and spell == crafting.id then
			crafting.done, crafting.last = crafting.done + 1, GetTime()
			if crafting.done >= crafting.amount then
				Log("  craft recipe %d done: %d of %d", crafting.id, crafting.done, crafting.amount)
				crafting = nil
			end
		elseif event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED" or event == "UPDATE_TRADESKILL_CAST_STOPPED" then
			Log("  craft recipe %d ended after %d of %d (%s)", crafting.id, crafting.done, crafting.amount, event)
			crafting = nil
		end
	end
	local always = WATCH_ALWAYS[event]
	if not always and GetTime() > watchUntil then
		return
	end
	if watchSeen and not always then
		watchSeen[event] = (watchSeen[event] or 0) + 1
	end
	if always or event == "UI_ERROR_MESSAGE" then
		local args = {}
		for i = 1, math.min(select("#", ...), 4) do
			local value = Readable((select(i, ...)))
			args[i] = value == nil and "?" or tostring(value)
		end
		Log("  %s%s: %s", always and "BLOCKED/FORBIDDEN " or "", event, table.concat(args, ", "))
	end
end)

local events = CreateFrame("Frame")
events.pbOwn = true -- never muted by SilentLoad
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("SKILL_LINES_CHANGED")
pcall(events.RegisterEvent, events, "TRADE_SKILL_CLOSE")
for event in pairs(TRADE_EVENTS) do
	-- An event this client does not know raises on registration; the others still register.
	pcall(events.RegisterEvent, events, event)
end

events:SetScript("OnEvent", function(_, event, arg1)
	Safe(event, function()
		if event == "ADDON_LOADED" then
			if arg1 == ADDON_NAME then
				Cfg()
				RegisterOptions()
				-- Runs at once when the Professions window's addon is already loaded, else when it loads.
				if EventUtil and EventUtil.ContinueOnAddOnLoaded then
					EventUtil.ContinueOnAddOnLoaded("Blizzard_Professions", function()
						Safe("recipe list", AttachRecipeList)
					end)
				end
			elseif arg1 == "Blizzard_Professions" and not (EventUtil and EventUtil.ContinueOnAddOnLoaded) then
				AttachRecipeList()
			end
		elseif event == "PLAYER_LOGIN" then
			local pos = DB().pos
			bar:ClearAllPoints()
			if pos then
				bar:SetPoint(pos[1], UIParent, pos[1], pos[2], pos[3])
			else
				bar:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 20, 200)
			end
			UpdateBar()
			-- Fonts and textures other addons register may not be there yet at login.
			C_Timer.After(2, function()
				Safe("appearance", UpdateBar)
			end)
			Log("=== version %s loaded: %d professions, favorites via %s ===", VERSION, #PlayerProfessions(),
				GameFavourites() and "the game" or "own list")
		elseif event == "PLAYER_REGEN_DISABLED" then
			HideFanNow()
		elseif event == "SKILL_LINES_CHANGED" then
			UpdateBar()
		elseif event == "TRADE_SKILL_CLOSE" then
			silent.loaded = nil
		elseif TRADE_EVENTS[event] then
			if event == "TRADE_SKILL_SHOW" then
				OnSilentShow()
			end
			QueueScan()
		end
	end)
end)

-- Named in the .toc: a click on the addon's entry in the minimap's addon list opens the options.
function QuickCraftForever_OnAddonCompartmentClick()
	Safe("options", OpenOptions)
end
