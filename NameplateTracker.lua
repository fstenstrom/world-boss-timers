-- ----------------------------------------------------------------------------
--  A persistent timer for World Bosses.
-- ----------------------------------------------------------------------------

-- addonName, addonTable = ...;
local _, WBT = ...;

local NameplateTracker = {};
WBT.NameplateTracker = NameplateTracker;

local tracker = CreateFrame("Frame");
local function TrackerCb(self, event, unit)
    local guid = UnitGUID(unit);
    local name = WBT.BossData.NameFromNpcGuid(guid, WBT.GetCurrentMapId());
    if name == nil then
        return;
    end

    local sound_tbl = WBT.Sound.sound_tbl;
    WBT.Util.PlaySoundAlert(
            sound_tbl.tbl:GetSubtbl(
                    sound_tbl.keys.option, WBT.Config.spawn_alert_sound:get()
            )[sound_tbl.keys.file_id]
    );
    WBT:Print("Boss found: " .. WBT.GetColoredBossName(name));
end

--@do-not-package@
tracker:SetScript("OnEvent", TrackerCb);
tracker:RegisterEvent("NAME_PLATE_UNIT_ADDED");
--@end-do-not-package@
