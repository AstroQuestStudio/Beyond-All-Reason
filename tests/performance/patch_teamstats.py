import os

file_path = r'C:\Users\trufa\Documents\BAR\Beyond-All-Reason\luarules\gadgets\api_teamstats.lua'
with open(file_path, 'r', encoding='utf-8') as f:
    text = f.read()

target = """---@type { frame: integer, since: integer?, servedAt: integer?, heard: boolean }
local still = { frame = -1, since = nil, servedAt = nil, heard = false }

---@diagnostic disable-next-line: undefined-field
function gadget:Update()
\tlocal now = spGetTimer()
\tlocal frame = spGetGameFrame()"""

replacement = """---@type { frame: integer, since: integer?, servedAt: integer?, heard: boolean }
local still = { frame = -1, since = nil, servedAt = nil, heard = false }
local lastUpdateCheck = nil

---@diagnostic disable-next-line: undefined-field
function gadget:Update()
\tlocal now = spGetTimer()
\tif lastUpdateCheck and spDiffTimers(now, lastUpdateCheck) < 0.25 then
\t\treturn
\tend
\tlastUpdateCheck = now

\tlocal frame = spGetGameFrame()"""

assert target in text, "target not found in api_teamstats.lua"
text = text.replace(target, replacement, 1)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(text)

print("Successfully patched api_teamstats.lua")
