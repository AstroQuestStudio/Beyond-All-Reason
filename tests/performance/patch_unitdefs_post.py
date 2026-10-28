import os

file_path = r'C:\Users\trufa\Documents\BAR\Beyond-All-Reason\gamedata\unitdefs_post.lua'
with open(file_path, 'r', encoding='utf-8') as f:
    text = f.read()

target = """local function getFilePath(filename, path)
\tlocal files = VFS.DirList(path, "*.lua")
\tfor i = 1, #files do
\t\tif path .. filename == files[i] then
\t\t\treturn path
\t\tend
\tend
\tlocal subdirs = VFS.SubDirs(path)
\tfor i = 1, #subdirs do
\t\tlocal result = getFilePath(filename, subdirs[i])
\t\tif result then
\t\t\treturn result
\t\tend
\tend
\treturn false
end"""

replacement = """local unitPathIndex = nil

local function buildUnitPathIndex(basePath)
\tlocal index = {}
\tlocal function scanDir(path)
\t\tlocal files = VFS.DirList(path, "*.lua")
\t\tfor i = 1, #files do
\t\t\tlocal f = files[i]
\t\t\tlocal fname = f:match("([^/]+)$") or f
\t\t\tindex[fname] = path
\t\tend
\t\tlocal subdirs = VFS.SubDirs(path)
\t\tfor i = 1, #subdirs do
\t\t\tscanDir(subdirs[i])
\t\tend
\tend
\tscanDir(basePath)
\treturn index
end

local function getFilePath(filename, path)
\tif not unitPathIndex then
\t\tunitPathIndex = buildUnitPathIndex(path)
\tend
\treturn unitPathIndex[filename] or false
end"""

assert target in text, "target not found in unitdefs_post.lua"
text = text.replace(target, replacement, 1)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(text)

print("Successfully patched gamedata/unitdefs_post.lua")
