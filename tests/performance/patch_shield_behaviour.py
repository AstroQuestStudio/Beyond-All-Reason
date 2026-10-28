import os

file_path = r'C:\Users\trufa\Documents\BAR\Beyond-All-Reason\luarules\gadgets\unit_shield_behaviour.lua'
with open(file_path, 'r', encoding='utf-8') as f:
    text = f.read()

# 1. Add shieldSetPool and isShieldHooked state
target1 = """local function removeCoveredUnits(shieldUnitID)"""
replacement1 = """local isShieldHooked = true

local shieldSetPool = {}
local shieldSetPoolCount = 0

local function allocShieldSet()
\tif shieldSetPoolCount > 0 then
\t\tlocal s = shieldSetPool[shieldSetPoolCount]
\t\tshieldSetPool[shieldSetPoolCount] = nil
\t\tshieldSetPoolCount = shieldSetPoolCount - 1
\t\treturn s
\tend
\treturn {}
end

local function freeShieldSet(s)
\tshieldSetPoolCount = shieldSetPoolCount + 1
\tshieldSetPool[shieldSetPoolCount] = s
end

local function removeCoveredUnits(shieldUnitID)"""

assert target1 in text, "target1 not found"
text = text.replace(target1, replacement1, 1)

# 2. Recycle shieldSet in removeCoveredUnits
target2 = """\t\t\tlocal shieldSet = unitCoverages[unitID]
\t\t\tif shieldSet then
\t\t\t\tshieldSet[shieldUnitID] = nil
\t\t\t\tif not next(shieldSet) then
\t\t\t\t\tunitCoverages[unitID] = nil
\t\t\t\tend
\t\t\tend"""

replacement2 = """\t\t\tlocal shieldSet = unitCoverages[unitID]
\t\t\tif shieldSet then
\t\t\t\tshieldSet[shieldUnitID] = nil
\t\t\t\tif not next(shieldSet) then
\t\t\t\t\tunitCoverages[unitID] = nil
\t\t\t\t\tfreeShieldSet(shieldSet)
\t\t\t\tend
\t\t\tend"""

assert target2 in text, "target2 not found"
text = text.replace(target2, replacement2, 1)

# 3. Use allocShieldSet in setCoveredUnits
target3 = """\t\tlocal shieldSet = unitCoverages[unitID]
\t\tif not shieldSet then
\t\t\tshieldSet = {}
\t\t\tunitCoverages[unitID] = shieldSet
\t\tend"""

replacement3 = """\t\tlocal shieldSet = unitCoverages[unitID]
\t\tif not shieldSet then
\t\t\tshieldSet = allocShieldSet()
\t\t\tunitCoverages[unitID] = shieldSet
\t\tend"""

assert target3 in text, "target3 not found"
text = text.replace(target3, replacement3, 1)

# 4. In UnitFinished, hook callins if not hooked
target4 = """function gadget:UnitFinished(unitID, unitDefID, unitTeam)
\tlocal data = shieldUnitDefs[unitDefID]
\tif data then"""

replacement4 = """function gadget:UnitFinished(unitID, unitDefID, unitTeam)
\tlocal data = shieldUnitDefs[unitDefID]
\tif data then
\t\tif not isShieldHooked then
\t\t\tgadgetHandler:UpdateCallIn("UnitPreDamaged")
\t\t\tgadgetHandler:UpdateCallIn("ShieldPreDamaged")
\t\t\tisShieldHooked = true
\t\tend"""

assert target4 in text, "target4 not found"
text = text.replace(target4, replacement4, 1)

# 5. In UnitDestroyed, unhook if no shields remain
target5 = """\t-- Clean up coverage tracking for any destroyed unit (shield or not)
\tunitCoverages[unitID] = nil
\tunitDefIDCache[unitID] = nil
end"""

replacement5 = """\t-- Clean up coverage tracking for any destroyed unit (shield or not)
\tif unitCoverages[unitID] then
\t\tfreeShieldSet(unitCoverages[unitID])
\t\tunitCoverages[unitID] = nil
\tend
\tunitDefIDCache[unitID] = nil

\tif isShieldHooked and not next(shieldUnitsData) and not next(unitCoverages) then
\t\tgadgetHandler:RemoveCallIn("UnitPreDamaged")
\t\tgadgetHandler:RemoveCallIn("ShieldPreDamaged")
\t\tisShieldHooked = false
\tend
end"""

assert target5 in text, "target5 not found"
text = text.replace(target5, replacement5, 1)

# 6. In Initialize, unhook initially if no shields exist
target6 = """\tfor _, unitID in ipairs(Spring.GetAllUnits()) do
\t\tlocal unitDefID = Spring.GetUnitDefID(unitID)
\t\tlocal unitTeam = Spring.GetUnitTeam(unitID)
\t\tgadget:UnitFinished(unitID, unitDefID, unitTeam)
\tend
end"""

replacement6 = """\tfor _, unitID in ipairs(Spring.GetAllUnits()) do
\t\tlocal unitDefID = Spring.GetUnitDefID(unitID)
\t\tlocal unitTeam = Spring.GetUnitTeam(unitID)
\t\tgadget:UnitFinished(unitID, unitDefID, unitTeam)
\tend

\tif not next(shieldUnitsData) and not next(unitCoverages) then
\t\tgadgetHandler:RemoveCallIn("UnitPreDamaged")
\t\tgadgetHandler:RemoveCallIn("ShieldPreDamaged")
\t\tisShieldHooked = false
\tend
end"""

assert target6 in text, "target6 not found"
text = text.replace(target6, replacement6, 1)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(text)

print("Successfully patched unit_shield_behaviour.lua")
