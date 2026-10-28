--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local gadget = gadget ---@type Gadget

function gadget:GetInfo()
	return {
		name = "Minesweeper Detection",
		desc = "Shows mines around minesweepers",
		author = "Hornet, robert the pie",
		date = "May 25th, 2024",
		license = "GNU GPL, v2 or later",
		layer = 0,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return false
end

local spSetUnitLosState = Spring.SetUnitLosState
local spSetUnitLosMask = Spring.SetUnitLosMask
local spGetUnitPosition = Spring.GetUnitPosition
local spGetUnitsInCylinder = Spring.GetUnitsInCylinder
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitTeam = Spring.GetUnitTeam

local minesweeperRanges = {}
local minesweepers = {}

local mineDefIDs = {}
local revealedMines = {}

for unitDefID, unitDef in pairs(UnitDefs) do
	if unitDef.customParams.minesweeper then
		minesweeperRanges[unitDefID] = unitDef.customParams.minesweeper
	elseif unitDef.customParams.mine then
		mineDefIDs[unitDefID] = true
	end
end
if table.count(minesweeperRanges) == 0 or table.count(mineDefIDs) == 0 then
	return false
end

local teamIDs = {}
for _, teamID in pairs(Spring.GetTeamList()) do
	local _, _, _, _, _, allyTeam = Spring.GetTeamInfo(teamID, false)
	teamIDs[teamID] = allyTeam
	revealedMines[teamID] = {}
	minesweepers[teamID] = {}
end

local totalMinesweepers = 0
local gameFrameActive = true

local function checkMinesweeperCallin()
	local active = totalMinesweepers > 0
	if active and not gameFrameActive then
		gadgetHandler:UpdateCallIn("GameFrame")
		gameFrameActive = true
	elseif not active and gameFrameActive then
		gadgetHandler:RemoveCallIn("GameFrame")
		gameFrameActive = false
	end
end

function gadget:MetaUnitAdded(unitID, unitDefID, unitTeam)
	if minesweeperRanges[unitDefID] then
		if not minesweepers[unitTeam][unitID] then
			totalMinesweepers = totalMinesweepers + 1
		end
		minesweepers[unitTeam][unitID] = unitDefID
		checkMinesweeperCallin()
	end
end

function gadget:MetaUnitRemoved(unitID, unitDefID, unitTeam)
	if minesweeperRanges[unitDefID] and minesweepers[unitTeam][unitID] then
		minesweepers[unitTeam][unitID] = nil
		totalMinesweepers = totalMinesweepers - 1
		if totalMinesweepers <= 0 then
			totalMinesweepers = 0
			for tID in pairs(teamIDs) do
				processRevealedMines(tID)
			end
			checkMinesweeperCallin()
		end
	end
end

local function processTeamsSweepers(teamID)
	local minesToReveal = {}

	for sweeper, sweeperDef in pairs(minesweepers[teamID]) do
		local x, y, z = spGetUnitPosition(sweeper)
		if x and z then
			local nearUnits = spGetUnitsInCylinder(x, z, minesweeperRanges[sweeperDef])
			for _, nearUnit in ipairs(nearUnits) do
				local nearUnitDefID = spGetUnitDefID(nearUnit)
				if mineDefIDs[nearUnitDefID] and teamID ~= spGetUnitTeam(nearUnit) then
					minesToReveal[nearUnit] = true
				end
			end
		end
	end

	for mineToReveal, _ in pairs(minesToReveal) do
		if revealedMines[teamID][mineToReveal] == nil then
			revealedMines[teamID][mineToReveal] = true
			--show in vision and radar, and prevent engine from immediately resseting that state
			spSetUnitLosState(mineToReveal, teamIDs[teamID], 3)
			spSetUnitLosMask(mineToReveal, teamIDs[teamID], 3)
		end
	end
end

local function processRevealedMines(teamID)
	for revealedMine, _ in pairs(revealedMines[teamID]) do
		spSetUnitLosMask(revealedMine, teamIDs[teamID], 0)
		revealedMines[teamID][revealedMine] = nil
	end
end

local processingInterval = Game.gameSpeed
function gadget:GameFrame(n)
	local loopedFrame = n % processingInterval
	for teamID in pairs(teamIDs) do
		if teamID % processingInterval == loopedFrame then
			processRevealedMines(teamID)
			processTeamsSweepers(teamID)
		end
	end
end

function gadget:Initialize()
	totalMinesweepers = 0
	for _, unitID in pairs(Spring.GetAllUnits()) do
		local unitDefID = Spring.GetUnitDefID(unitID)
		local unitTeam = Spring.GetUnitTeam(unitID)
		if minesweeperRanges[unitDefID] then
			minesweepers[unitTeam][unitID] = unitDefID
			totalMinesweepers = totalMinesweepers + 1
		end
	end
	checkMinesweeperCallin()
end
