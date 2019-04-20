-- ----------------------------------------------------------------------------
--  A persistent timer for World Bosses.
-- ----------------------------------------------------------------------------

-- addonName, addonTable = ...;
local _, WBT = ...;

local Com = {};
WBT.Com = Com;

local nameplate_tracker = CreateFrame("Frame");
local function nameplate_tracker_callback(some_table, event, unit, ...)
    if UnitIsPlayer(unit) then
        print(UnitName(unit));
    end
end
nameplate_tracker:SetScript("OnEvent", nameplate_tracker_callback);
nameplate_tracker:RegisterEvent("NAME_PLATE_UNIT_ADDED");

local friendly_frame_resetter = CreateFrame("frame");
friendly_frame_resetter.since_update = 0;

function Com.TriggerFriendlyNameplates()
    local onoff = GetCVar("nameplateShowFriends");
    local reverse = nil;
    if onoff == "0" then
        reverse = "1";
    else
        reverse = "0";
    end
    SetCVar("nameplateShowFriends", reverse);

    function friendly_frame_resetter:DoUpdate()
        SetCVar("nameplateShowFriends", onoff);
    end

    friendly_frame_resetter.cnt = 0;
    friendly_frame_resetter:SetScript("OnUpdate", function(self, elapsed)
            self.cnt = self.cnt + 1;
            -- From experimentation, I conclude that the "NAME_PLATE_UNIT_ADDED"
            -- event doesn't trigger unless the nameplate is shown at least 1 frame.
            if (self.cnt > 1) then
                self:DoUpdate();
                self:SetScript("OnUpdate", nil);
            end
        end);
end
