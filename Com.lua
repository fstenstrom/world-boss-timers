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

Com.REQUEST_MESSAGE = "request_timer"; -- Content of message currently is not used.

Com.ENTER_REQUEST_MODE = "Enter request mode";
Com.LEAVE_REQUEST_MODE = "Leave request mode";

Com.DELIM1 = ";";
Com.DELIM2 = "_";

local CVAR_NAMEPLATE_SHOW_FRIENDS = "nameplateShowFriends";
local EVENT_NAME_PLATE_UNIT_ADDED = "NAME_PLATE_UNIT_ADDED";
local EVENT_UPDATE_MOUSEOVER_UNIT = "UPDATE_MOUSEOVER_UNIT";

local com_event_tracker = CreateFrame("Frame");
function com_event_tracker:ComEventTrackerCallback(event, unit, ...)
    if event == EVENT_UPDATE_MOUSEOVER_UNIT then
        unit = 'mouseover';
    end

    if not UnitExists(unit)
            or not UnitIsVisible(unit)
            or not UnitIsPlayer(unit)
            or not UnitIsFriend("player", unit) then
        return;
    end

    local name, realm = UnitName(unit);
    if realm then
        name = name .. "-" .. realm;
    end
    Com:SendCommMessage(Com.PREF_SR, Com.REQUEST_MESSAGE, "WHISPER", name);
end
com_event_tracker:SetScript("OnEvent", com_event_tracker.ComEventTrackerCallback);

function com_event_tracker:RegisterEvents()
    self:RegisterEvent(EVENT_NAME_PLATE_UNIT_ADDED);
    self:RegisterEvent(EVENT_UPDATE_MOUSEOVER_UNIT);
end

function com_event_tracker:UnregisterEvents()
    self:UnregisterEvent(EVENT_NAME_PLATE_UNIT_ADDED);
    self:UnregisterEvent(EVENT_UPDATE_MOUSEOVER_UNIT);
end

function Com:Init()
    KillInfo = WBT.KillInfo;
    if WBT.db.char.start_request_tracking_at_startup then
        com_event_tracker:RegisterEvents();
    end

end

function Com.EnterRequestMode()
    WBT.db.char.restore_nameplates_show_always = InterfaceOptionsNamesPanelUnitNameplatesShowAll.value
    if WBT.db.char.restore_nameplates_show_always == "0" then
        InterfaceOptionsNamesPanelUnitNameplatesShowAll:Click();
    end

    WBT.db.char.restore_nameplates_friendly = GetCVar(CVAR_NAMEPLATE_SHOW_FRIENDS);
    if WBT.db.char.restore_nameplates_friendly == "0" then
        SetCVar(CVAR_NAMEPLATE_SHOW_FRIENDS, "1");
    end

    com_event_tracker:RegisterEvents();

    WBT.db.char.start_request_tracking_at_startup = true;

    return Com.LeaveRequestMode, Com.LEAVE_REQUEST_MODE; -- Return value is used by the button which calls it.
end

function Com.LeaveRequestMode()
    if WBT.db.char.restore_nameplates_show_always ~= InterfaceOptionsNamesPanelUnitNameplatesShowAll.value then -- User might have changed back manually.
        InterfaceOptionsNamesPanelUnitNameplatesShowAll:Click();
    end
    SetCVar("nameplateShowFriends", WBT.db.char.restore_nameplates_friendly);

    WBT.db.char.restore_nameplates_show_always = nil;
    WBT.db.char.restore_nameplates_friendly = nil;
    WBT.db.char.start_request_tracking_at_startup = false;

    com_event_tracker:UnregisterEvents();

    return Com.EnterRequestMode, Com.ENTER_REQUEST_MODE; -- Return value is used by the button which calls it.
end

function Com.ActiveRequestMethod()
    if WBT.db.char.restore_nameplates_show_always ~= nil then
        return Com.LeaveRequestMode, Com.LEAVE_REQUEST_MODE;
    else
        return Com.EnterRequestMode, Com.ENTER_REQUEST_MODE;
    end
end

-- Since "RequestMode" is disabled, characters that were in Request mode
-- when they logged out during addon update (to no longer support this mode)
-- should be reverted.
function Com.ShouldRevertRequestMode()
    return WBT.db.char.restore_nameplates_show_always ~= nil;
end

function Com.CreateKillMessage(kill_info)
    return kill_info.name .. Com.DELIM2 .. tostring(kill_info:GetServerDeathTime());
end

function Com.ParseKillMessage(message)
    return string.match(message, "([A-Z][a-z]+).*" .. Com.DELIM2 .. "(%d+)");
end

function Com.OnCommReceivedSR(prefix, message, distribution, sender)
    -- No error checking for sender here, since using the player's name is not valid for
    -- UnitXXX calls, unless the sender is in the same party or raid as player.
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
