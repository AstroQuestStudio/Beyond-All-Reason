import os

file_path = r'C:\Users\trufa\Documents\BAR\Beyond-All-Reason\gamedata\unitdefs.lua'
with open(file_path, 'r', encoding='utf-8') as f:
    text = f.read()

# Replace O(N^2) table.remove and badOptions table allocation with in-place O(N) compaction
target = """for name, def in pairs(unitDefs) do
\tlocal badOptions = {}
\tlocal buildOptions = def.buildoptions
\tfor i, option in ipairs(buildOptions) do
\t\tif unitDefs[option] == nil then
\t\t\ttable.insert(badOptions, i)
\t\tend
\tend
\tif #badOptions > 0 then
\t\tlocal removed = 0
\t\tfor _, badIndex in ipairs(badOptions) do
\t\t\ttable.remove(buildOptions, badIndex - removed)
\t\t\tremoved = removed + 1
\t\tend
\tend
end"""

replacement = """-- Optimized O(N) in-place buildoptions filter (zero table allocations, no table.remove array shifting)
for name, def in pairs(unitDefs) do
\tlocal buildOptions = def.buildoptions
\tif buildOptions then
\t\tlocal w = 1
\t\tlocal n = #buildOptions
\t\tfor r = 1, n do
\t\t\tlocal opt = buildOptions[r]
\t\t\tif unitDefs[opt] ~= nil then
\t\t\t\tif w ~= r then
\t\t\t\t\tbuildOptions[w] = opt
\t\t\t\tend
\t\t\t\tw = w + 1
\t\t\tend
\t\tend
\t\tfor i = w, n do
\t\t\tbuildOptions[i] = nil
\t\tend
\tend
end"""

assert target in text, "target not found in unitdefs.lua"
text = text.replace(target, replacement, 1)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(text)

print("Successfully patched gamedata/unitdefs.lua")
