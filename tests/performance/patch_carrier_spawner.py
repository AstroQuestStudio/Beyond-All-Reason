import os

file_path = r'C:\Users\trufa\Documents\BAR\Beyond-All-Reason\luarules\gadgets\unit_carrier_spawner.lua'
with open(file_path, 'r', encoding='utf-8') as f:
    text = f.read()

# Add checkCarrierCallins helper
helper = """local areCarrierCallinsActive = true

local function checkCarrierCallins()
\tlocal shouldBeActive = (next(carrierMetaList) ~= nil) or (next(droneMetaList) ~= nil)
\tif shouldBeActive and not areCarrierCallinsActive then
\t\tgadgetHandler:UpdateCallIn("GameFrame")
\t\tgadgetHandler:UpdateCallIn("GameFramePost")
\t\tgadgetHandler:UpdateCallIn("AllowCommand")
\t\tgadgetHandler:UpdateCallIn("UnitCommand")
\t\tgadgetHandler:UpdateCallIn("UnitStunned")
\t\tareCarrierCallinsActive = true
\telseif not shouldBeActive and areCarrierCallinsActive then
\t\tgadgetHandler:RemoveCallIn("GameFrame")
\t\tgadgetHandler:RemoveCallIn("GameFramePost")
\t\tgadgetHandler:RemoveCallIn("AllowCommand")
\t\tgadgetHandler:RemoveCallIn("UnitCommand")
\t\tgadgetHandler:RemoveCallIn("UnitStunned")
\t\tareCarrierCallinsActive = false
\tend
end
"""

target_init = """function gadget:Initialize()"""
assert target_init in text, "target_init not found"
text = text.replace(target_init, helper + "\n" + target_init, 1)

# In Initialize, call checkCarrierCallins() at the end
target_init_end = """\tgadgetHandler:RegisterGlobal("CobUndockSequenceFinished", CobUndockSequenceFinished)
\tgadgetHandler:RegisterGlobal("CobDroneSpawnSequenceFinished", CobDroneSpawnSequenceFinished)
end"""

replacement_init_end = """\tgadgetHandler:RegisterGlobal("CobUndockSequenceFinished", CobUndockSequenceFinished)
\tgadgetHandler:RegisterGlobal("CobDroneSpawnSequenceFinished", CobDroneSpawnSequenceFinished)
\tcheckCarrierCallins()
end"""

assert target_init_end in text, "target_init_end not found"
text = text.replace(target_init_end, replacement_init_end, 1)

# In UnitCreated, checkCarrierCallins() after carrier registered
target_unit_created = """\tlocal f = spGetGameFrame()"""
replacement_unit_created = """\tcheckCarrierCallins()
\tlocal f = spGetGameFrame()"""

assert target_unit_created in text, "target_unit_created not found"
text = text.replace(target_unit_created, replacement_unit_created, 1)

# In UnitDestroyed, call checkCarrierCallins() at end
target_unit_destroyed_end = """\tinUnitDestroyed = false
end"""

replacement_unit_destroyed_end = """\tinUnitDestroyed = false
\tcheckCarrierCallins()
end"""

assert target_unit_destroyed_end in text, "target_unit_destroyed_end not found"
text = text.replace(target_unit_destroyed_end, replacement_unit_destroyed_end, 1)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(text)

print("Successfully patched unit_carrier_spawner.lua")
