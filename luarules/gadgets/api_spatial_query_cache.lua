local gadget = gadget ---@type Gadget

function gadget:GetInfo()
	return {
		name = "Spatial Query Cache API",
		desc = "Deterministic frame-scoped cache for spatial queries (GetUnitsInCylinder, GetUnitsInSphere) to eliminate redundant C++ bridge traversals",
		author = "AstroQuestStudio",
		date = "2026",
		license = "GNU GPL, v2 or later",
		layer = -999998,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return
end

local spGetGameFrame = Spring.GetGameFrame
local spGetUnitsInCylinder = Spring.GetUnitsInCylinder
local spGetUnitsInSphere = Spring.GetUnitsInSphere

local lastFrame = -1
local generation = 0

local cylinderCache = {}
local sphereCache = {}

local function invalidateIfNewFrame()
	local currentFrame = spGetGameFrame()
	if currentFrame ~= lastFrame then
		lastFrame = currentFrame
		generation = generation + 1
		for k in pairs(cylinderCache) do
			cylinderCache[k] = nil
		end
		for k in pairs(sphereCache) do
			sphereCache[k] = nil
		end
	end
end

local function cachedGetUnitsInCylinder(x, z, radius, teamID)
	invalidateIfNewFrame()
	local key = string.format("%.1f:%.1f:%.1f:%d:%d", x, z, radius, teamID or -999, generation)
	local res = cylinderCache[key]
	if res then
		return res
	end
	res = spGetUnitsInCylinder(x, z, radius, teamID)
	cylinderCache[key] = res
	return res
end

local function cachedGetUnitsInSphere(x, y, z, radius, teamID)
	invalidateIfNewFrame()
	local key = string.format("%.1f:%.1f:%.1f:%.1f:%d:%d", x, y, z, radius, teamID or -999, generation)
	local res = sphereCache[key]
	if res then
		return res
	end
	res = spGetUnitsInSphere(x, y, z, radius, teamID)
	sphereCache[key] = res
	return res
end

function gadget:UnitCreated(unitID, unitDefID, unitTeam)
	generation = generation + 1
end

function gadget:UnitDestroyed(unitID, unitDefID, unitTeam)
	generation = generation + 1
end

function gadget:Initialize()
	GG.SpatialQueryCache = {
		GetUnitsInCylinder = cachedGetUnitsInCylinder,
		GetUnitsInSphere = cachedGetUnitsInSphere,
		Invalidate = function()
			generation = generation + 1
		end,
	}
end

function gadget:Shutdown()
	if GG.SpatialQueryCache then
		GG.SpatialQueryCache = nil
	end
end
