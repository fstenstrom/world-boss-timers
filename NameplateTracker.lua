-- ----------------------------------------------------------------------------
--  A persistent timer for World Bosses.
-- ----------------------------------------------------------------------------

-- addonName, addonTable = ...;
local _, WBT = ...;

local NameplateTracker = {};
WBT.NameplateTracker = NameplateTracker;

local tracker = CreateFrame("Frame");
local COOLDOWN_OUTPUT = 120; -- Cooldown in seconds before outputting again (text/sound)

tracker.no_output_until = 0; -- Server time, 0 guarantees that it will always output the first time after Addon is loaded
local function TrackerCb(self, event, unit)
    if GetServerTime() < self.no_output_until then
        return;
    end
    self.no_output_until = GetServerTime() + COOLDOWN_OUTPUT;

    local unit = unit; -- Provided if (event == NAME_PLATE_UNIT_ADDED)
    if (event == "UPDATE_MOUSEOVER_UNIT") then
        unit = "mouseover";
    end

    local guid = UnitGUID(unit);
    if (guid == nil) then
        return;
    end

    local name = WBT.BossData.NameFromNpcGuid(guid, WBT.GetCurrentMapId());
    if name == nil then
        return;
    end

    local sound_tbl = WBT.Sound.sound_tbl;
    WBT.Util.PlaySoundAlert(
            sound_tbl.tbl:GetSubtbl(
                    sound_tbl.keys.option, WBT.Options.spawn_alert_sound:get()
            )[sound_tbl.keys.file_id]
    );
    FlashClientIcon();
    WBT:Print("Boss found: " .. WBT.GetColoredBossName(name));
end

--@do-not-package@
tracker:SetScript("OnEvent", TrackerCb);
tracker:RegisterEvent("NAME_PLATE_UNIT_ADDED");
tracker:RegisterEvent("UPDATE_MOUSEOVER_UNIT");
--@end-do-not-package@
