local TC2, C, L, _ = unpack(select(2, ...))

-----------------------------
-- VARIABLES
-----------------------------
-- upvalues
local _G = _G
local select = _G.select
local unpack = _G.unpack
local tonumber = _G.tonumber
local tostring = _G.tostring
local type = _G.type
local floor = _G.math.floor
local strbyte = _G.string.byte
local format = _G.string.format
local strlen = _G.string.len
local strsub = _G.string.sub
local time = _G.time

local ipairs = _G.ipairs
local pairs = _G.pairs
local tinsert = _G.table.insert
local tremove = _G.table.remove
local sort = _G.table.sort
local wipe = _G.table.wipe

local GetNumGroupMembers = _G.GetNumGroupMembers
local GetNumSubgroupMembers = _G.GetNumSubgroupMembers
local GetInstanceInfo = _G.GetInstanceInfo
local InCombatLockdown = _G.InCombatLockdown
local IsInRaid = _G.IsInRaid
local UnitAffectingCombat = _G.UnitAffectingCombat
local UnitClass = _G.UnitClass
local UnitExists = _G.UnitExists
local UnitIsFriend = _G.UnitIsFriend
local UnitIsEnemy = _G.UnitIsEnemy
local UnitIsDead = _G.UnitIsDead
local UnitIsPlayer = _G.UnitIsPlayer
local UnitName = _G.UnitName
local UnitReaction = _G.UnitReaction
local UnitIsUnit = _G.UnitIsUnit
local UnitHealth = _G.UnitHealth

-- other
TC2.threatData = {}
TC2.numGroupMembers = 0
TC2.playerName = ""
TC2.playerTarget = ""
TC2.loggingEnabled = false
TC2.debug = false

-----------------------------
-- WOW CLASSIC
-----------------------------
-- TC2.classic = _G.WOW_PROJECT_ID ~= _G.WOW_PROJECT_CLASSIC -- for testing in retail
TC2.classic = _G.WOW_PROJECT_ID == _G.WOW_PROJECT_CLASSIC

local ThreatLib = TC2.classic and LibStub:GetLibrary("LibThreatClassic2")
assert(ThreatLib, "ThreatClassic2 requires LibThreatClassic2")

local UnitThreatSituation = TC2.classic and function(unit, mob)
		return ThreatLib:UnitThreatSituation(unit, mob)
	end or _G.UnitThreatSituation

local UnitDetailedThreatSituation = TC2.classic and function(unit, mob)
		return ThreatLib:UnitDetailedThreatSituation(unit, mob)
	end or _G.UnitDetailedThreatSituation



-----------------------------
-- ThreatLib Copy Pasta to avoid constant GUID lookups / target of target calls
-- 	Original Source from LibThreatClassic2:UnitDetailedThreatSituation
-----------------------------
------------------------------------------------------------------------
-- :UnitGUIDDetailedThreatSituation("unit", "mob")
-- Arguments: 
--  string - unitGUID of the unit to get threat information for.
--  string - unitGUID of the target unit to reference.
--  string - unitGUID of the target unit target to reference.
-- Returns:
--  integer - returns 1 if the unit is primary threat target of the mob (is tanking), or nil otherwise.
--  integer - returns the threat status for the unit on the mob, or nil if unit is not on mob's threat table. (3 = securely tanking, 2 = insecurely tanking, 1 = not tanking but higher threat than tank, 0 = not tanking and lower threat than tank)
--  float - returns the unit's threat on the mob as a percentage of the amount required to pull aggro, scaled according to the unit's range from the mob. At 100 the unit will pull aggro. Returns 100 if the unit is tanking and nil if the unit is not on the mob's threat list.
--  float - returns the unit's threat as a percentage of the tank's current threat. Returns nil if the unit is not on the mob's threat list.
--  float - returns the unit's total threat on the mob.
------------------------------------------------------------------------
local function UnitGUIDDetailedThreatSituation(unitGUID, targetGUID, targetTargetGUID)
	local isTanking, threatStatus, threatPercent, rawThreatPercent, threatValue = nil, 0, nil, nil, 0

	if not unitGUID or not targetGUID then
		return isTanking, threatStatus, threatPercent, rawThreatPercent, threatValue
	end

	threatValue = ThreatLib:GetThreat(unitGUID, targetGUID) or 0 -- self

	if threatValue <= 0 then
		return isTanking, threatStatus, threatPercent, rawThreatPercent, threatValue
	end

	-- maxThreatValue can never be 0 as unit's threatValue is already greater than 0
	local maxThreatValue, maxGUID = ThreatLib:GetMaxThreatOnTarget(targetGUID) -- self
	local unitPullAggroRangeMod = ThreatLib:GetPullAggroRangeModifier(unitGUID, targetGUID) -- self

	-- if we have no targetTarget, the current tank can only be guessed based on max threat
	-- threatStatus 1 and 2 can't be determined without targetTarget
	if not targetTargetGUID then
		rawThreatPercent = threatValue / maxThreatValue * 100
		if threatValue < maxThreatValue then
			isTanking = false
			threatStatus = 0
			threatPercent = rawThreatPercent / unitPullAggroRangeMod
		else
			isTanking = true
			threatStatus = 3
			threatPercent = 100
		end
		return isTanking, threatStatus, threatPercent, rawThreatPercent, floor(threatValue)
	end

	-- targetTarget is exactly then the current tank, iff no other unit has more threat than required to overaggro targetTarget
	-- As the threat required to pull aggro is influenced by the pullAggroRangeModifier of a unit, this is not
	-- necessarily the unit with the most threat.
	--
	-- Imagine targetTarget has 1000 threat, a meele player has 1200 threat and a range player has 1250 threat
	-- In this case, targetTarget is clearly not the tank as the meele player has enough threat to gain aggro.
	-- Meanwhile the range player has more threat than the meele player, but not enough to gain aggro from targetTarget
	-- In this case, the meele player needs to be considered the tank.
	--
	-- Now imagine targetTarget has 1000 threat, a meele player has 1200 threat and a range player has 1400 threat
	-- Both range and meele have more threat than required to overaggro targetTarget. However, we can't correctly
	-- determine the currentTank, because the range player does not have enough threat to overaggro the meele player,
	-- who might be actively tanking.
	--
	-- As considering all other units only solves the edge case, some range players have more than 110% but less
	-- than 130% threat and some meeles have more than 110% threat of targetTarget, we simplify this function
	-- and save some CPU by only checking against the target with the highest threat.

	local targetTargetThreatValue = ThreatLib:GetThreat(targetTargetGUID, targetGUID) or 0 --self
	local maxPullAggroRangeMod = ThreatLib:GetPullAggroRangeModifier(maxGUID, targetGUID) --self

	local currentTankThreatValue
	local currentTankGUID

	if maxThreatValue > targetTargetThreatValue * maxPullAggroRangeMod then
		currentTankThreatValue = maxThreatValue
		currentTankGUID = maxGUID
	else
		currentTankThreatValue = targetTargetThreatValue
		currentTankGUID = targetTargetGUID
	end

	rawThreatPercent = threatValue / currentTankThreatValue * 100

	if threatValue >= currentTankThreatValue then
		if unitGUID == currentTankGUID then
			isTanking = 1

			if unitGUID == maxGUID then
				threatStatus = 3
			else
				threatStatus = 2
			end
		else
			threatStatus = 1
		end
	end

	if isTanking then
		threatPercent = 100
	else
		threatPercent = rawThreatPercent / unitPullAggroRangeMod
	end

	return isTanking, threatStatus, threatPercent, rawThreatPercent, floor(threatValue)
end

-----------------------------
-- FUNCTIONS
-----------------------------
local function CopyDefaults(t1, t2)
	if type(t1) ~= "table" then
		return {}
	end
	if type(t2) ~= "table" then
		t2 = {}
	end

	for k, v in pairs(t1) do
		if type(v) == "table" then
			t2[k] = CopyDefaults(v, t2[k])
		elseif type(v) ~= type(t2[k]) then
			t2[k] = v
		end
	end

	return t2
end

local function Compare(a, b)
	return a.scaledPercent > b.scaledPercent
end

local function NumFormat(v)
	if v > 1e10 then
		return (floor(v / 1e9)) .. "b"
	elseif v > 1e9 then
		return (floor((v / 1e9) * 10) / 10) .. "b"
	elseif v > 1e7 then
		return (floor(v / 1e6)) .. "m"
	elseif v > 1e6 then
		return (floor((v / 1e6) * 10) / 10) .. "m"
	elseif v > 1e4 then
		return (floor(v / 1e3)) .. "k"
	elseif v > 1e3 then
		return (floor((v / 1e3) * 10) / 10) .. "k"
	else
		return v
	end
end

local function TruncateString(str, i, ellipsis)
	if not str then
		return
	end
	local bytes = strlen(str)
	if bytes <= i then
		return str
	else
		local length, pos = 0, 1
		while (pos <= bytes) do
			length = length + 1
			local c = strbyte(str, pos)
			if c > 0 and c <= 127 then
				pos = pos + 1
			elseif c >= 192 and c <= 223 then
				pos = pos + 2
			elseif c >= 224 and c <= 239 then
				pos = pos + 3
			elseif c >= 240 and c <= 247 then
				pos = pos + 4
			end
			if length == i then
				break
			end
		end
		if length == i and pos <= bytes then
			return strsub(str, 1, pos - 1) .. (ellipsis and "..." or "")
		else
			return str
		end
	end
end

local function DebugPrint(message)
	if TC2.debug then
		print(message)
	end
end

local function tdump(o, tabs)
	if type(o) == "table" then
		local s = "{ \n"
		local newtabs = tabs .. "\t"
		for k, v in pairs(o) do
			if type(k) ~= "number" then
				k = '"' .. k .. '"'
			end
			s = s .. newtabs .. "[" .. k .. "] = " .. tdump(v, newtabs) .. ",\n"
		end
		return s .. tabs .. "} "
	else
		return tostring(o)
	end
end

local function UpdatePlayerTarget()
	if UnitExists("target") and not UnitIsFriend("player", "target") then
		TC2.playerTarget = "target"
	elseif UnitExists("targettarget") and not UnitIsFriend("player", "targettarget") then
		TC2.playerTarget = "targettarget"
	else
		TC2.playerTarget = "target"
	end
end

-- Checks if given target is alive and an enemy, if so it adds
-- the target to targets table
local function AddTargetIfAliveAndEnemy(toCheck, targets)
	-- DebugPrint("AddTargetIfAliveAndEnemy: " .. toCheck )
	-- DebugPrint("\tIsDead? " .. tostring(UnitIsDead(toCheck)))
	-- DebugPrint("\tIsEnemy? " .. tostring(UnitIsEnemy("player", toCheck)))
	if not UnitIsDead(toCheck) and UnitIsEnemy("player", toCheck) then
		local tarGUID = UnitGUID(toCheck)
		-- DebugPrint("Target GUID: " .. tarGUID)
		if tarGUID ~= nil then
			targets[tarGUID] = toCheck
		end
	end
end

local function CheckUnitTarget(unit, pet, unitTarget, petTarget, players, targets)
	players[unit] = UnitName(unit)
	AddTargetIfAliveAndEnemy(unitTarget, targets)
	if UnitExists(pet) then
		players[pet] = format("%s-%s", players[unit], UnitName(pet))
		AddTargetIfAliveAndEnemy(petTarget, targets)
	end
end

local function BuildTargets()
	local targets = {}
	local players = {}

	CheckUnitTarget("player", "pet", "target", "pettarget", players, targets)

  -- TODO build in smarts in the Roster Update event to build the list of players
  -- Add global flag to check pets, not super userful in raids
	if IsInRaid() then
		for i = 1, TC2.numGroupMembers do
			CheckUnitTarget(
				TC2.raidUnits[i],
				TC2.raidPetUnits[i],
				TC2.raidUnitsTarget[i],
				TC2.raidPetUnitsTarget[i],
				players,
				targets
			)
		end
	else
		if TC2.numGroupMembers > 0 then
			for i = 1, TC2.numGroupMembers do
				CheckUnitTarget(
					TC2.partyUnits[i],
					TC2.partyPetUnits[i],
					TC2.partyUnitsTarget[i],
					TC2.partyPetUnitsTarget[i],
					players,
					targets
				)
			end
		end
	end
	-- DebugPrint("Targets: " .. tdump(targets, ""))
	-- DebugPrint("Players: " .. tdump(players, ""))
	return targets, players
end

local function InitializeTarget(guid, target)
	-- DebugPrint("InitTarget: " .. guid .. ", " .. target)
	local tstamp = tostring(time())
	local tot = target .. "target"
	local einfo = TC2_Log[guid]

	if einfo == nil then
		TC2_Log["_count"] = TC2_Log["_count"] + 1
		TC2_Log[guid] = {}
		einfo = TC2_Log[guid]
		einfo["name"] = UnitName(target)
		einfo["start"] = tstamp
	-- DebugPrint("\tNew Target: " .. einfo["name"])
  end
  
  -- use counter to offset time() resolution of 1 second
  local offset = 1
	if (einfo[tstamp] ~= nil) then
		offset = einfo[tstamp]["offset"]
		tstamp = tstamp .. "." .. tostring(offset)
		offset = offset + 1
	end
	einfo[tstamp] = {}
	timeslice = einfo[tstamp]
	timeslice["offset"] = offset
	timeslice["target"] = UnitName(tot)
	timeslice["targetGUID"] = UnitGUID(tot)
	return timeslice
end

local function GetPlayerThreat(unitGUID, targetGUID, targetTargetGUID)
	-- ThreatLib:UnitGUIDDetailedThreatSituation(unitGUID, targetGUID, targetTargetGUID)
	local _, _, scaledPercent, _, threatValue = UnitGUIDDetailedThreatSituation(unitGUID, targetGUID, targetTargetGUID)
	if threatValue and threatValue < 0 then
		threatValue = threatValue + 410065408
	end
	return {
		["percent"] = scaledPercent,
		["absolute"] = threatValue
	}
end

local function CheckStatus()
	if TC2.loggingEnabled == false then
		return
	end
	local alltargets, allplayers = BuildTargets()
	for guid, target in pairs(alltargets) do
		-- Initialize mob record and create new record for time period
		local timeslice = InitializeTarget(guid, target)

    -- TODO only add timeslice to table if total threat > 0
		for player, name in pairs(allplayers) do
			timeslice[name] = GetPlayerThreat(UnitGUID(player), guid, timeslice["targetGUID"])
		end
	end
end

-----------------------------
-- NAMEPLATES
-----------------------------
local function UpdateNameplateThreat(self)
	if not InCombatLockdown() then
		return
	end
	UnitThreatSituation("player", unit)
end

if TC2.classic then
	-- since UNIT_THREAT_LIST_UPDATE isn't a thing in Classic, health color doesn't update nearly as frequently
	-- we'll instead hook the range check since it is OnUpdate - gross, but it works for now
	hooksecurefunc("CompactUnitFrame_UpdateInRange", UpdateNameplateThreat)
else
	hooksecurefunc("CompactUnitFrame_UpdateHealthColor", UpdateNameplateThreat)
	hooksecurefunc("CompactUnitFrame_UpdateAggroFlash", UpdateNameplateThreat)
end

-----------------------------
-- EVENTS
-----------------------------

TC2.frame = CreateFrame("Frame", TC2.addonName .. "BarFrame", UIParent)

TC2.frame:RegisterEvent("PLAYER_LOGIN")
TC2.frame:SetScript(
	"OnEvent",
	function(self, event, ...)
		return TC2[event] and TC2[event](TC2, event, ...)
	end
)

function TC2:PLAYER_ENTERING_WORLD(...)
	self.playerName = UnitName("player")
	self.numGroupMembers = IsInRaid() and GetNumGroupMembers() or GetNumSubgroupMembers()
	CheckStatus()
end

function TC2:PLAYER_TARGET_CHANGED(...)
	UpdatePlayerTarget()
	CheckStatus()
end

function TC2:GROUP_ROSTER_UPDATE(...)
	self.numGroupMembers = IsInRaid() and GetNumGroupMembers() or GetNumSubgroupMembers()
	CheckStatus()
end

function TC2:PLAYER_REGEN_DISABLED(...)
	UpdatePlayerTarget() -- for friendly mobs that turn hostile like vaelastrasz
	ThreatLib.RegisterCallback(self, "ThreatUpdated", CheckStatus)
	CheckStatus()
end

function TC2:PLAYER_REGEN_ENABLED(...)
	ThreatLib.UnregisterCallback(self, "ThreatUpdated", CheckStatus)
	CheckStatus()
end

function TC2:UNIT_THREAT_LIST_UPDATE(...)
	CheckStatus()
end

function TC2:PLAYER_LOGIN()
	TC2_Log = {}
	TC2_Log["_count"] = 0

	print("|c00FFAA00" .. self.addonName .. " v" .. self.version .. " - " .. "Type /tlog for options." .. "|r")

	self:SetupUnits()

	self.frame:RegisterEvent("PLAYER_ENTERING_WORLD")
	self.frame:RegisterEvent("GROUP_ROSTER_UPDATE")
	self.frame:RegisterEvent("PLAYER_TARGET_CHANGED")
	self.frame:RegisterEvent("PLAYER_REGEN_DISABLED")
	self.frame:RegisterEvent("PLAYER_REGEN_ENABLED")

	if self.classic then
		ThreatLib.RegisterCallback(self, "Activate", CheckStatus)
		ThreatLib.RegisterCallback(self, "Deactivate", CheckStatus)
		ThreatLib.RegisterCallback(self, "ThreatUpdated", CheckStatus)
		ThreatLib:RequestActiveOnSolo(true)
	end

	self.frame:UnregisterEvent("PLAYER_LOGIN")
	self.PLAYER_LOGIN = nil
end

-----------------------------
-- SETUP
-----------------------------
function TC2:SetupUnits()
	self.partyUnits = {}
	self.partyPetUnits = {}
	self.partyUnitsTarget = {}
	self.partyPetUnitsTarget = {}
	self.raidUnits = {}
	self.raidPetUnits = {}
	self.raidUnitsTarget = {}
	self.raidPetUnitsTarget = {}

	for i = 1, 4 do
		self.partyUnits[i] = format("party%d", i)
		self.partyPetUnits[i] = format("partypet%d", i)
		self.partyUnitsTarget[i] = format("party%dtarget", i)
		self.partyPetUnitsTarget[i] = format("partypet%dtarget", i)
	end
	for i = 1, 40 do
		self.raidUnits[i] = format("raid%d", i)
		self.raidPetUnits[i] = format("raidpet%d", i)
		self.raidUnitsTarget[i] = format("raid%dtarget", i)
		self.raidPetUnitsTarget[i] = format("raidpet%dtarget", i)
	end
end

-----------------------------
-- CONFIG
-----------------------------
function TC2:SetupConfig()
end

SLASH_TLOG_SLASHCMD1 = "/tlog"
SlashCmdList["TLOG_SLASHCMD"] = function(arg)
	if arg == "start" then
		print("Threat Logging Enabled")
		TC2.loggingEnabled = true
	elseif arg == "stop" then
		print("Threat Logging Disabled")
		TC2.loggingEnabled = false
	elseif arg == "reset" then
		print("Threat Log Reset")
		TC2_Log = {}
		TC2_Log["_count"] = 0
	elseif arg == "status" then
		print("Threat Logging Status: " .. tostring(TC2.loggingEnabled))
		print("Total Targets: " .. tostring(TC2_Log["_count"]))
	elseif arg == "debug" then
		TC2.debug = not TC2.debug
		print("Threat Debugging Status: " .. tostring(TC2.debug))
	else
		print("/tlog start -- start threat logging")
		print("/tlog stop  -- stop threat logging")
		print("/tlog reset -- clear current threat log")
	end
end
