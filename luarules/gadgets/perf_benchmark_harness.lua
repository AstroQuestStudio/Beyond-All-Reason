local gadget = gadget ---@type Gadget

function gadget:GetInfo()
	return {
		name = "Performance Benchmark Harness",
		desc = "Automated deterministic benchmark harness for headless performance testing",
		author = "AstroQuestStudio",
		date = "2026",
		license = "GNU GPL, v2 or later",
		layer = 999999,
		enabled = true,
	}
end

local configPath = "tests/performance/bench_config.json"

--------------------------------------------------------------------------------
-- SYNCED CODE
--------------------------------------------------------------------------------
if gadgetHandler:IsSyncedCode() then
	local targetFrames = 3600
	local checkpointInterval = 200
	local isBenchActive = true

	if VFS.FileExists(configPath) then
		local content = VFS.LoadFile(configPath)
		if content then
			local tf = content:match('"target_frames"%s*:%s*(%d+)')
			if tf then targetFrames = tonumber(tf) end
		end
	end

	local function computeChecksum(frame)
		local allUnits = Spring.GetAllUnits()
		local count = #allUnits
		local sumX, sumZ, sumHp = 0, 0, 0
		for i = 1, count do
			local u = allUnits[i]
			local x, _, z = Spring.GetUnitPosition(u)
			local hp = Spring.GetUnitHealth(u) or 0
			sumX = (sumX + math.floor((x or 0) * 10)) % 1000000007
			sumZ = (sumZ + math.floor((z or 0) * 10)) % 1000000007
			sumHp = (sumHp + math.floor(hp * 10)) % 1000000007
		end
		return string.format("F:%d|U:%d|X:%d|Z:%d|H:%d", frame, count, sumX, sumZ, sumHp)
	end

	function gadget:GameFrame(frame)
		if not isBenchActive then return end

		if frame == 1 then
			Spring.SendCommands("setminspeed 100")
			Spring.SendCommands("speed 100")
			Spring.SendCommands("skip " .. targetFrames)
		end

		if frame > 0 and frame % checkpointInterval == 0 then
			local chk = computeChecksum(frame)
			SendToUnsynced("bench_chk", frame, chk)
		end

		if frame >= targetFrames then
			isBenchActive = false
			local chk = computeChecksum(frame)
			SendToUnsynced("bench_chk", frame, chk)
			SendToUnsynced("bench_done", frame)
		end
	end

	return
end

--------------------------------------------------------------------------------
-- UNSYNCED CODE
--------------------------------------------------------------------------------

local frameTimes = {}
local gcCounts = {}
local checkpoints = {}
local lastTimer = nil
local targetFrames = 3600
local tag = "default"
local startTime = 0
local isFinished = false

local function parseJsonSimple(str)
	local frames = str:match('"target_frames"%s*:%s*(%d+)')
	local t = str:match('"tag"%s*:%s*"([^"]+)"')
	return {
		target_frames = tonumber(frames) or 3600,
		tag = t or "default",
	}
end

function gadget:Initialize()
	if VFS.FileExists(configPath) then
		local content = VFS.LoadFile(configPath)
		if content then
			local cfg = parseJsonSimple(content)
			targetFrames = cfg.target_frames
			tag = cfg.tag
		end
	end

	gadgetHandler:AddSyncAction("bench_chk", function(_, frame, chk)
		checkpoints[#checkpoints + 1] = { frame = frame, checksum = chk }
		Spring.Echo(string.format("[BenchHarness] Checkpoint @ frame %d: %s", frame, chk))
	end)

	gadgetHandler:AddSyncAction("bench_done", function(_, totalFrames)
		if isFinished then return end
		isFinished = true

		local wallclockSec = Spring.DiffTimers(Spring.GetTimer(), startTime)
		table.sort(frameTimes)
		local n = #frameTimes
		local p50 = n > 0 and frameTimes[math.max(1, math.floor(n * 0.50))] or 0
		local p95 = n > 0 and frameTimes[math.max(1, math.floor(n * 0.95))] or 0
		local p99 = n > 0 and frameTimes[math.max(1, math.floor(n * 0.99))] or 0
		local maxMs = n > 0 and frameTimes[n] or 0
		local sum = 0
		for i = 1, n do sum = sum + frameTimes[i] end
		local avgMs = n > 0 and (sum / n) or 0

		local spikes = 0
		for i = 1, n do
			if frameTimes[i] > 33.33 then
				spikes = spikes + 1
			end
		end

		local minGc, maxGc = 99999999, 0
		for i = 1, #gcCounts do
			if gcCounts[i] < minGc then minGc = gcCounts[i] end
			if gcCounts[i] > maxGc then maxGc = gcCounts[i] end
		end

		local simFps = totalFrames / math.max(0.001, wallclockSec)
		local realTimeSpeedup = simFps / 30.0

		Spring.Echo("=======================================================")
		Spring.Echo("       BAR PERFORMANCE 2.0 BENCHMARK REPORT            ")
		Spring.Echo("=======================================================")
		Spring.Echo(string.format(" Tag                  : %s", tag))
		Spring.Echo(string.format(" Total Frames         : %d", totalFrames))
		Spring.Echo(string.format(" Wallclock Duration   : %.3f s", wallclockSec))
		Spring.Echo(string.format(" Effective Sim FPS    : %.1f FPS (%.2fx real-time)", simFps, realTimeSpeedup))
		Spring.Echo(string.format(" Sim Frame Time Avg   : %.3f ms", avgMs))
		Spring.Echo(string.format(" Sim Frame Time P50   : %.3f ms", p50))
		Spring.Echo(string.format(" Sim Frame Time P95   : %.3f ms", p95))
		Spring.Echo(string.format(" Sim Frame Time P99   : %.3f ms", p99))
		Spring.Echo(string.format(" Sim Frame Time Max   : %.3f ms", maxMs))
		Spring.Echo(string.format(" Spikes (>33.3ms)     : %d (%.2f%%)", spikes, (spikes / math.max(1, n)) * 100))
		Spring.Echo(string.format(" Lua Memory Min / Max : %.2f MB / %.2f MB", minGc / 1024, maxGc / 1024))
		Spring.Echo("=======================================================")

		local chkJson = {}
		for i = 1, #checkpoints do
			chkJson[#chkJson + 1] = string.format('{"frame": %d, "checksum": "%s"}', checkpoints[i].frame, checkpoints[i].checksum)
		end

		local jsonStr = string.format([[{
  "tag": "%s",
  "total_frames": %d,
  "wallclock_sec": %.4f,
  "sim_fps": %.2f,
  "sim_speedup": %.2f,
  "frame_time_avg_ms": %.4f,
  "frame_time_p50_ms": %.4f,
  "frame_time_p95_ms": %.4f,
  "frame_time_p99_ms": %.4f,
  "frame_time_max_ms": %.4f,
  "spikes_over_33ms": %d,
  "spikes_percent": %.2f,
  "lua_mem_min_kb": %d,
  "lua_mem_max_kb": %d,
  "checkpoints": [%s]
}]],
			tag,
			totalFrames,
			wallclockSec,
			simFps,
			realTimeSpeedup,
			avgMs,
			p50,
			p95,
			p99,
			maxMs,
			spikes,
			(spikes / math.max(1, n)) * 100,
			minGc,
			maxGc,
			table.concat(chkJson, ", ")
		)

		Spring.Echo("JSON_REPORT_START")
		Spring.Echo(jsonStr)
		Spring.Echo("JSON_REPORT_END")

		Spring.SendCommands("quitforce")
	end)
end

function gadget:GameFrame(frame)
	local now = Spring.GetTimer()
	if frame == 1 then
		startTime = now
		lastTimer = now
		return
	end

	if lastTimer then
		local dt = Spring.DiffTimers(now, lastTimer) * 1000.0 -- ms
		frameTimes[#frameTimes + 1] = dt
		gcCounts[#gcCounts + 1] = collectgarbage("count")
	end
	lastTimer = now
end
