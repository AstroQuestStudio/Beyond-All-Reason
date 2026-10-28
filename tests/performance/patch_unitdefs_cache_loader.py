import os

file_path = r'C:\Users\trufa\Documents\BAR\Beyond-All-Reason\gamedata\unitdefs.lua'
with open(file_path, 'r', encoding='utf-8') as f:
    text = f.read()

target = """local luaFiles = VFS.DirList("units/", "*.lua", nil, true)"""

replacement = """-- Fast-path: use pre-baked cache index if available, with safe fallback to VFS.DirList
local luaFiles
local bakedCacheFile = "cache/unitdefs_cache.lua"
if VFS.FileExists(bakedCacheFile) then
\tlocal success, cache = pcall(VFS.Include, bakedCacheFile)
\tif success and type(cache) == "table" and type(cache.unitPaths) == "table" then
\t\tluaFiles = {}
\t\tlocal c = 0
\t\tfor _, path in pairs(cache.unitPaths) do
\t\t\tc = c + 1
\t\t\tluaFiles[c] = path
\t\tend
\t\ttable.sort(luaFiles)
\tend
end

if not luaFiles then
\tluaFiles = VFS.DirList("units/", "*.lua", nil, true)
end"""

assert target in text, "target not found in unitdefs.lua"
text = text.replace(target, replacement, 1)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(text)

print("Successfully updated gamedata/unitdefs.lua with pre-baked cache fast-path")
