--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--
--  file:    unitdefs.lua
--  brief:   unitdef parser
--  author:  Dave Rodgers
--
--  Copyright (C) 2007.
--  Licensed under the terms of the GNU GPL, v2 or later.
--
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local unitDefs = {}
local shared = {} -- shared amongst the lua unitdef environments

local preProcFile = "gamedata/unitdefs_pre.lua"
local postProcFile = "gamedata/unitdefs_post.lua"

local system = VFS.Include("gamedata/system.lua")

local section = "unitdefs.lua"

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--
--  Run a pre-processing script if one exists
--

if VFS.FileExists(preProcFile) then
	Shared = shared -- make it global
	UnitDefs = unitDefs -- make it global
	VFS.Include(preProcFile)
	UnitDefs = nil
	Shared = nil
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--
--  Load the raw LUA format unitdef files
--  (these will override the SWU versions)
--

-- Fast-path: use pre-baked cache index if available, with safe fallback to VFS.DirList
local luaFiles
local bakedCacheFile = "cache/unitdefs_cache.lua"
if VFS.FileExists(bakedCacheFile) then
	local success, cache = pcall(VFS.Include, bakedCacheFile)
	if success and type(cache) == "table" then
		if type(cache.unitList) == "table" then
			luaFiles = cache.unitList
		elseif type(cache.unitPaths) == "table" then
			luaFiles = {}
			local c = 0
			for _, path in pairs(cache.unitPaths) do
				c = c + 1
				luaFiles[c] = path
			end
			table.sort(luaFiles)
		end
	end
end

if not luaFiles then
	luaFiles = VFS.DirList("units/", "*.lua", nil, true)
end

local legionEnabled = Spring.GetModOptions().experimentallegionfaction
local scavengersEnabled = BAR.Utilities.Gametype.IsScavengers()
local raptorsEnabled = BAR.Utilities.Gametype.IsRaptors()

if Spring.GetModOptions().ruins == "enabled" then
	legionEnabled = true
	scavengersEnabled = true
end

if scavengersEnabled then
	legionEnabled = true
end

if Spring.GetModOptions().zombies ~= "disabled" then
	scavengersEnabled = true
	legionEnabled = true
end

if Spring.GetModOptions().experimentalextraunits or Spring.GetModOptions().scavunitsforplayers then
	scavengersEnabled = true
	legionEnabled = true
end

if Spring.GetModOptions().forceallunits then
	raptorsEnabled = true
	scavengersEnabled = true
	legionEnabled = true
end

for _, filename in ipairs(luaFiles) do
	local loadFile = (legionEnabled or not filename:find("legion"))
		and (scavengersEnabled or not filename:find("scavengers"))
		and (raptorsEnabled or not filename:find("raptors"))

	if loadFile then
		local unitDefsEnv = {}
		unitDefsEnv._G = unitDefsEnv
		unitDefsEnv.Shared = shared
		unitDefsEnv.BAR = BAR
		unitDefsEnv.GetFilename = function()
			return filename
		end
		setmetatable(unitDefsEnv, { __index = system })
		local success, defs = pcall(VFS.Include, filename, unitDefsEnv, VFS_MODES)
		if not success then
			Spring.Log(section, LOG.ERROR, "Error parsing " .. filename .. ": " .. tostring(defs))
		elseif type(defs) ~= "table" then
			Spring.Log(section, LOG.ERROR, "Bad return table from: " .. filename)
		else
			for unitDefName, unitDef in pairs(defs) do
				if (type(unitDefName) == "string") and (type(unitDef) == "table") then
					unitDefs[unitDefName] = unitDef
				else
					Spring.Log(section, LOG.ERROR, "Bad return table entry from: " .. filename)
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--
--  Run a post-processing script if one exists
--

if VFS.FileExists(postProcFile) then
	Shared = shared -- make it global
	UnitDefs = unitDefs -- make it global
	VFS.Include(postProcFile)
	UnitDefs = nil
	Shared = nil
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--
--  Basic checks to kill unitDefs that will crash ".give all"
--

for name, def in pairs(unitDefs) do
	local model = def.objectname
	if model == nil then
		unitDefs[name] = nil
		Spring.Log(section, LOG.ERROR, "removed " .. name .. " unitDef, missing objectname param")
	else
		local objfile = "objects3d/" .. model
		if not VFS.FileExists(objfile) then
			unitDefs[name] = nil
			Spring.Log(section, LOG.ERROR, "removed " .. name .. " unitDef, missing model file  (" .. model .. ")")
		end
	end
end

-- Optimized O(N) in-place buildoptions filter (zero table allocations, no table.remove array shifting)
for name, def in pairs(unitDefs) do
	local buildOptions = def.buildoptions
	if buildOptions then
		local w = 1
		local n = #buildOptions
		for r = 1, n do
			local opt = buildOptions[r]
			if unitDefs[opt] ~= nil then
				if w ~= r then
					buildOptions[w] = opt
				end
				w = w + 1
			end
		end
		for i = w, n do
			buildOptions[i] = nil
		end
	end
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

return unitDefs
