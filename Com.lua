-- ----------------------------------------------------------------------------
--  A persistent timer for World Bosses.
-- ----------------------------------------------------------------------------

-- addonName, addonTable = ...;
local _, WBT = ...;

local Com = {
    locked = false,
};
WBT.Com = Com;

local KillInfo = nil; -- Will be set in 'Init'.

local PREF_BASE = "WBT_";
Com.PREF_SR = PREF_BASE .. "SR"; -- SendRequest
Com.PREF_RR = PREF_BASE .. "RR"; -- ReplyRequest

Com.DELIM1 = ";";
Com.DELIM2 = "_";

function Com:Init()
    KillInfo = WBT.KillInfo;
end

local nameplate_tracker = CreateFrame("Frame");
local function nameplate_tracker_callback(some_table, event, unit, ...)
    if UnitIsPlayer(unit) then
        local name, realm = UnitName(unit);
        if realm then
            name = name .. "-" .. realm;
        end
        Com:SendCommMessage(Com.PREF_SR, "texty", "WHISPER", name);
    end
end
nameplate_tracker:SetScript("OnEvent", nameplate_tracker_callback);
nameplate_tracker:RegisterEvent("NAME_PLATE_UNIT_ADDED");

local friendly_frame_resetter = CreateFrame("frame");
friendly_frame_resetter.since_update = 0;

function Com.TriggerFriendlyNameplates()
    if Com.locked then
        return;
    end
    Com.locked = true;

    local setShowAlways = InterfaceOptionsNamesPanelUnitNameplatesShowAll.value == "0";
    if setShowAlways then
        InterfaceOptionsNamesPanelUnitNameplatesShowAll:Click();
    end

    local restoreShowFriends = GetCVar("nameplateShowFriends");
    local reverse = nil;
    if restoreShowFriends == "0" then
        reverse = "1";
    else
        reverse = "0";
    end
    SetCVar("nameplateShowFriends", reverse);

    function friendly_frame_resetter:DoUpdate()
        SetCVar("nameplateShowFriends", restoreShowFriends);
        if setShowAlways then
            -- Needs to be restored.
            InterfaceOptionsNamesPanelUnitNameplatesShowAll:Click();
        end
    end

    friendly_frame_resetter.cnt = 0;
    friendly_frame_resetter:SetScript("OnUpdate", function(self, elapsed)
            self.cnt = self.cnt + 1;
            -- From experimentation, I conclude that the "NAME_PLATE_UNIT_ADDED"
            -- event doesn't trigger unless the nameplate is shown at least 1 frame.
            if (self.cnt > 300) then
                self:DoUpdate();
                Com.locked = false;
                self:SetScript("OnUpdate", nil);
            end
        end);
end

function Com.CreateKillMessage(kill_info)
    return kill_info.name .. Com.DELIM2 .. tostring(kill_info:GetServerDeathTime());
end

function Com.ParseKillMessage(message)
    return string.match(message, "([A-Z][a-z]+).*" .. Com.DELIM2 .. "(%d+)");
end

function Com.OnCommReceivedSR(prefix, message, distribution, sender)
    if WBT.InBossZone() then
        local kill_info = WBT.KillInfoInCurrentZoneAndShard();
        if kill_info and kill_info:IsCompletelySafe({}) then
            local reply = Com.CreateKillMessage(kill_info);
            Com:SendCommMessage(Com.PREF_RR, reply, "WHISPER", sender);
        end
    end
end

function Com.OnCommReceivedRR(prefix, message, distribution, sender)
    local name, t_death = Com.ParseKillMessage(message);
    local guid = KillInfo.CreateGUID(name);
    local ignore_cyclic = true;
    if WBT.IsBoss(name) and not WBT.IsDead(guid, ignore_cyclic) then
        WBT.SetKillInfo(name, t_death);
        WBT:Print("Received " .. WBT.GetColoredBossName(name) .. " timer from: " .. sender);
    end
end
