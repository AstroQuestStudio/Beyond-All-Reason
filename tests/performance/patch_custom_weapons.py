import os

file_path = r'C:\Users\trufa\Documents\BAR\Beyond-All-Reason\luarules\gadgets\unit_custom_weapons_behaviours.lua'
with open(file_path, 'r', encoding='utf-8') as f:
    text = f.read()

# 1. Add guidance tuple pool before getGuidanceLost
target1 = """local function getGuidanceLost(projectileID, radius, targetID)"""
replacement1 = """local guidanceTuplePool = {}
local guidanceTuplePoolCount = 0

local function allocGuidanceTuple(a, b, c)
\tif guidanceTuplePoolCount > 0 then
\t\tlocal t = guidanceTuplePool[guidanceTuplePoolCount]
\t\tguidanceTuplePool[guidanceTuplePoolCount] = nil
\t\tguidanceTuplePoolCount = guidanceTuplePoolCount - 1
\t\tt[1], t[2], t[3] = a, b, c
\t\treturn t
\tend
\treturn { a, b, c }
end

local function getGuidanceLost(projectileID, radius, targetID)"""

assert target1 in text, "target1 not found"
text = text.replace(target1, replacement1, 1)

# 2. Use allocGuidanceTuple in getGuidanceLost
target2 = """\tlocal result = { ux, uy, uz }
\tguidanceResults[-targetID - 1] = result
\treturn result"""

replacement2 = """\tlocal result = allocGuidanceTuple(ux, uy, uz)
\tguidanceResults[-targetID - 1] = result
\treturn result"""

assert target2 in text, "target2 not found"
text = text.replace(target2, replacement2, 1)

# 3. In Initialize, unhook GameFrame initially since no projectiles exist yet
target3 = """\t\tfor weaponDefID in pairs(weaponDefEffect) do
\t\t\tgadgetHandler:RegisterProjectile(weaponDefID)
\t\tend
\t\tgameFrame = Spring.GetGameFrame()
\telse"""

replacement3 = """\t\tfor weaponDefID in pairs(weaponDefEffect) do
\t\t\tgadgetHandler:RegisterProjectile(weaponDefID)
\t\tend
\t\tgameFrame = Spring.GetGameFrame()
\t\tgadgetHandler:RemoveCallIn("GameFrame")
\telse"""

assert target3 in text, "target3 not found"
text = text.replace(target3, replacement3, 1)

# 4. In ProjectileCreated, hook GameFrame if this is the first active projectile
target4 = """function gadget:ProjectileCreated(projectileID, proOwnerID, weaponDefID)
\tprojectiles[projectileID] = weaponDefEffect[weaponDefID]
end"""

replacement4 = """function gadget:ProjectileCreated(projectileID, proOwnerID, weaponDefID)
\tlocal effect = weaponDefEffect[weaponDefID]
\tif effect then
\t\tif not next(projectiles) then
\t\t\tgadgetHandler:UpdateCallIn("GameFrame")
\t\tend
\t\tprojectiles[projectileID] = effect
\tend
end"""

assert target4 in text, "target4 not found"
text = text.replace(target4, replacement4, 1)

# 5. In ProjectileDestroyed, unhook GameFrame if no projectiles remain
target5 = """function gadget:ProjectileDestroyed(projectileID)
\tprojectiles[projectileID] = nil
end"""

replacement5 = """function gadget:ProjectileDestroyed(projectileID)
\tprojectiles[projectileID] = nil
\tif not next(projectiles) then
\t\tgadgetHandler:RemoveCallIn("GameFrame")
\tend
end"""

assert target5 in text, "target5 not found"
text = text.replace(target5, replacement5, 1)

# 6. In GameFrame, recycle guidanceResults in-place into the pool and unhook if empty
target6 = """function gadget:GameFrame(frame)
\tgameFrame = frame
\tguidanceResults = {}

\tfor projectileID, effect in pairs(projectiles) do
\t\tif effect(projectileID) then
\t\t\tprojectiles[projectileID] = nil
\t\tend
\tend
end"""

replacement6 = """function gadget:GameFrame(frame)
\tgameFrame = frame
\tfor k, v in pairs(guidanceResults) do
\t\tif type(v) == "table" and v ~= noGuidance then
\t\t\tguidanceTuplePoolCount = guidanceTuplePoolCount + 1
\t\t\tguidanceTuplePool[guidanceTuplePoolCount] = v
\t\tend
\t\tguidanceResults[k] = nil
\tend

\tfor projectileID, effect in pairs(projectiles) do
\t\tif effect(projectileID) then
\t\t\tprojectiles[projectileID] = nil
\t\tend
\tend

\tif not next(projectiles) then
\t\tgadgetHandler:RemoveCallIn("GameFrame")
\tend
end"""

assert target6 in text, "target6 not found"
text = text.replace(target6, replacement6, 1)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(text)

print("Successfully patched unit_custom_weapons_behaviours.lua")
