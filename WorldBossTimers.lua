-- ----------------------------------------------------------------------------
--  A persistent timer for World Bosses.
-- ----------------------------------------------------------------------------

local _, L = ...;

WBT = LibStub("AceAddon-3.0"):NewAddon("WBT", "AceConsole-3.0");

local gui;
local boss_death_frame;
local boss_combat_frame;

local SOUND_CLASSIC = "CLASSIC"
local SOUND_FANCY = "FANCY";

local defaults = {
    global = {
        boss = {},
        gui = nil,
        sound_enabled = true,
        sound_type = SOUND_CLASSIC,
        auto_announce = true,
        send_data = true,
        cyclic = false,
    },
    char = {
        boss = {},
    },
};

local REALM_TYPE_PVE = "PvE";
local REALM_TYPE_PVP = "PvP";

local COLOR_DEFAULT = "|cffffffff";
local COLOR_RED = "|cffff0000";
local COLOR_GREEN = "|cff00ff00";

local CHANNEL_ANNOUNCE = "SAY";
local ICON_SKULL = "{skull}";
local INDENT = "--";
local RANDOM_DELIM = " - ";

local CHAT_MSG_TIMER_REQUEST = "Could you please share WorldBossTimers kill data?";
local SERVER_DEATH_TIME_PREFIX = "WorldBossTimers:"; -- Free advertising.

local MAX_RESPAWN_TIME = 15*60 - 1; -- Minus 1, since they tend to spawn after 14:59.
local MIN_RESPAWN_TIME_RANDOM = 12*60; -- Conservative guesses. Actual values are not known.
local MAX_RESPAWN_TIME_RANDOM = 18*60; -- Conservative guesses. Actual values are not known.
--@do-not-package@
--[[
local MAX_RESPAWN_TIME = 4; -- Minus 1, since they tend to spawn after 14:59.
local MIN_RESPAWN_TIME_RANDOM = 5; -- Conservative guesses. Actual values are not known.
local MAX_RESPAWN_TIME_RANDOM = 10; -- Conservative guesses. Actual values are not known.
]]--
--@end-do-not-package@

local SOUND_DIR = "Interface\\AddOns\\WorldBossTimers\\resources\\sound\\";
local SOUND_FILE_DEFAULT = "Sound\\Event Sounds\\Event_wardrum_ogre.ogg";
local SOUND_FILE_PREPARE = "Sound\\creature\\EadricThePure\\AC_Eadric_Aggro01.ogg";


local REGISTERED_BOSSES = {
    ["Oondasta"] = {
        name = "Oondasta",
        color = "|cff21ffa3",
        zone = "Isle of Giants",
        soundfile = SOUND_DIR .. "oondasta3.mp3",
        random_spawn_time = false,
    },
    ["Rukhmar"] = {
        name = "Rukhmar",
        color = "|cfffa6e06",
        zone = "Spires of Arak",
        soundfile = SOUND_DIR .. "rukhmar1.mp3",
        random_spawn_time = false,
    },
    ["Galleon"] = {
        name = "Galleon",
        color = "|cffc1f973",
        zone = "Valley of the Four Winds",
        soundfile = SOUND_FILE_DEFAULT,
        random_spawn_time = false,
    },
    ["Nalak"] = {
        name = "Nalak",
        color = "|cff0081cc",
        zone = "Isle of Thunder",
        soundfile = SOUND_FILE_DEFAULT,
        random_spawn_time = true,
    },
    ["Sha of Anger"] = {
        name = "Sha of Anger",
        color = "|cff8a1a9f",
        zone = "Kun-Lai Summit",
        soundfile = SOUND_FILE_DEFAULT,
        random_spawn_time = true,
    },
    --@do-not-package@
    --[[
    -- Dummy.
    ["Vale Moth"] = {
        name = "Vale Moth",
        color = "|cff1f3d4a",
        zone = "Azuremyst Isle",
        soundfile = SOUND_DIR .. "vale_moth1.mp3",
        random_spawn_time = false,
    },
    ]]--
    -- Dummy.
    ["Grellkin"] = {
        name = "Grellkin",
        color = "|cffffff00",
        zone = "Shadowglen",
        soundfile = SOUND_DIR .. "grellkin2.mp3",
        random_spawn_time = true,
    },
    --[[
    -- Dummy.
    -- This entry won't work for everything since two mobs reside in same zone.
    ["Young Nightsaber"] = {
        name = "Young Nightsaber",
        color = "|cffff3d4a",
        zone =  "_Shadowglen",
        soundfile = SOUND_DIR .. "vale_moth1.mp3",
        random_spawn_time = false,
    },
    ]]--
    --@end-do-not-package@
}

local function CyclicEnabled()
    return WBT.db.global.cyclic;
end

local function SetCyclic(state)
    WBT.db.global.cyclic = state;
end

local function SendDataEnabled()
    return WBT.db.global.send_data;
end

local function SetSendData(state)
    WBT.db.global.send_data = state;
end

local function AutoAnnounceEnabled()
    return WBT.db.global.auto_announce;
end

local function SetAutoAnnounce(state)
    WBT.db.global.auto_announce = state;
end

local function SoundEnabled()
    return WBT.db.global.sound_enabled;
end

local function SetSound(state)
    WBT.db.global.sound_enabled = state;
end

local function GetColoredBossName(name)
    return REGISTERED_BOSSES[name].color .. REGISTERED_BOSSES[name].name .. COLOR_DEFAULT;
end

local function SetContainsKey(set, key)
    return set[key] ~= nil;
end

local function TableIsEmpty(tbl)
    return next(tbl) == nil
end

local function SetContainsValue(set, value)
    for k, v in pairs(set) do
        if v == value then
            return true;
        end
    end

    return false;
end

local function IsBoss(name)
    return SetContainsKey(REGISTERED_BOSSES, name);
end

local function IsInZoneOfBoss(name)
    return GetZoneText() == REGISTERED_BOSSES[name].zone;
end

local function BossesInCurrentZone()
    local bosses_in_zone = {}
    for name, boss in pairs(REGISTERED_BOSSES) do
        if IsInZoneOfBoss(name) then
            bosses_in_zone[name] = name;
        end
    end

    return bosses_in_zone;
end

local function IsInBossZone()
    return not TableIsEmpty(BossesInCurrentZone());
end

local function GetRealmType()
    local pvpStyle = GetZonePVPInfo();
    if pvpStyle == nil then
        return REALM_TYPE_PVE;
    end

    return REALM_TYPE_PVP;
end

local function HasRandomSpawnTime(name)
    return REGISTERED_BOSSES[name].random_spawn_time;
end

local function GetKillInfoFromZone()
    local current_zone = GetZoneText();
    for name, boss_info in pairs(REGISTERED_BOSSES) do
        if boss_info.zone == current_zone then
            return WBT.db.global.boss[boss_info.name];
        end
    end

    return nil;
end

-- The data for the kill can be incorrect. This might happen
-- when a player records a kill and then appear on another
-- server shard.
-- If this happens, we don't want the data to propagate
-- to other players.
local function IsKillInfoSafe(error_msgs)

    local kill_info = GetKillInfoFromZone();

    -- It's possible to have one char with war mode, and one
    -- without on the same server.
    local realm_type = GetRealmType();
    local realmName = GetRealmName();

    if not kill_info.safe then
        table.insert(error_msgs, "Player was in a group during previous kill.");
    end
    if kill_info.cyclic then
        table.insert(error_msgs, "Last kill wasn't recorded. This is just an estimate.");
    end
    if not (kill_info.realm_type == realm_type) then
        table.insert(error_msgs, "Kill was made on a " .. kill_info.realm_type .. " realm, but are now on a " .. realm_type .. " realm.");
    end
    if not (kill_info.realmName == realmName) then
        table.insert(error_msgs, "Kill was made on " .. kill_info.realmName .. ", but are now on " .. realmName .. ".");
    end

    if TableIsEmpty(error_msgs) then
        return true;
    end

    return false;
end

local function SetDeathTime(time, name)
    if WBT.db.global.boss[name] == nil then
        local boss = {};
        WBT.db.global.boss[name] = boss;
    end
    WBT.db.global.boss[name].t_death = time;
    WBT.db.global.boss[name].name = name;
    WBT.db.global.boss[name].realmName = GetRealmName();
    WBT.db.global.boss[name].realm_type = GetRealmType();
    WBT.db.global.boss[name].safe = not IsInGroup();
    WBT.db.global.boss[name].cyclic = false;
end

local function GetServerDeathTime(name)
    return WBT.db.global.boss[name].t_death;
end

local function KillUpdateFrame(frame)
    frame:SetScript("OnUpdate", nil);
end

local function FormatTimeSeconds(seconds)
    local mins = math.floor(seconds / 60);
    local secs = math.floor(seconds % 60);
    if mins > 0 then
        return mins .. "m " .. secs .. "s";
    else
        return secs .. "s";
    end
end

local function GetTimeSinceDeath(name)
    local boss = WBT.db.global.boss[name]
    if boss ~= nil then
        return GetServerTime() - boss.t_death;
    end

    return nil;
end

local function GetSpawnTimesRandom(name)
    local t_since_death = GetTimeSinceDeath(name);
    local t_lower_bound = MIN_RESPAWN_TIME_RANDOM - t_since_death;
    local t_upper_bound = MAX_RESPAWN_TIME_RANDOM - t_since_death;

    return t_lower_bound, t_upper_bound;
end

local function GetSpawnTimeSec(name)
    if HasRandomSpawnTime(name) then
        local _, t_upper = GetSpawnTimesRandom(name);
        return t_upper;
    else
        return MAX_RESPAWN_TIME - GetTimeSinceDeath(name);
    end
end

local function GetSpawnTime(name)
    if HasRandomSpawnTime(name) then
        local t_lower, t_upper = GetSpawnTimesRandom(name);
        if t_lower == nil or t_upper == nil then
            return -1;
        elseif t_lower < 0 then
            return "0s" .. RANDOM_DELIM .. FormatTimeSeconds(t_upper)
        else
            return  FormatTimeSeconds(t_lower) .. RANDOM_DELIM .. FormatTimeSeconds(t_upper)
        end
    else
        local spawn_time_sec = GetSpawnTimeSec(name);
        if spawn_time_sec == nil or spawn_time_sec < 0 then
            return -1;
        end

        return FormatTimeSeconds(spawn_time_sec);
    end
end

local function GetSpawnTimeOutput(name)
    local text = GetSpawnTime(name);
    if WBT.db.global.boss[name].cyclic then
        text = COLOR_RED .. text .. COLOR_DEFAULT;
    end

    return text;
end

local function IsBossZone()
    local current_zone = GetZoneText();

    local is_boss_zone = false;
    for name, boss in pairs(REGISTERED_BOSSES) do
        if boss.zone == current_zone then
            is_boss_zone = true;
        end
    end

    return is_boss_zone;
end

local function IsDead(name)
    local kill_info = WBT.db.global.boss[name];
    if not kill_info then
        return false;
    end
    if kill_info.cyclic then
        if CyclicEnabled() then
            return true;
        else
            return false;
        end
    end
    if HasRandomSpawnTime(name) then
        local _, t_upper = GetSpawnTimesRandom(name);
        return t_upper >= 0;
    else
        return GetSpawnTimeSec(name) >= 0;
    end
end

local function AnyDead()
    for name, boss in pairs(REGISTERED_BOSSES) do
        if IsDead(name) then
            return true;
        end
    end
    return false;
end

local function ShouldShowGUI()
    return IsBossZone() or AnyDead();
end

local function GetBossNames()
    local boss_names = {};
    local i = 1; -- Don't start on index = 0... >-<
    for name, _ in pairs(REGISTERED_BOSSES) do
        boss_names[i] = name;
        i = i + 1;
    end

    return boss_names;
end

local last_request_time = 0;
local function RequestKillData()
    if GetServerTime() - last_request_time > 5 then
        SendChatMessage(CHAT_MSG_TIMER_REQUEST, "SAY");
        last_request_time = GetServerTime();
    end
end

local function InitGUI()

    local AceGUI = LibStub("AceGUI-3.0"); -- Need to create AceGUI 'OnInit or OnEnabled'
    local gui_container = AceGUI:Create("SimpleGroup");
    gui = AceGUI:Create("Window");

    local width = 204; -- Longest possible name is "Sha of Anger: XXm YYs - MMm SSs", make sure it doesn't wrap over.
    local height = 100;
    gui:SetWidth(width);
    gui:SetHeight(height);
    gui:SetCallback("OnClose", function(widget) AceGUI:Release(widget) end);
    gui:SetTitle("World Boss Timers");
    gui:SetLayout("List");
    gui:EnableResize(false);
    gui.frame:SetFrameStrata("LOW");

    local btn = AceGUI:Create("Button");
    btn:SetWidth(width);
    btn:SetText("Request kill data");
    btn:SetCallback("OnClick", RequestKillData);

    hooksecurefunc(gui, "Hide", function() btn.frame:Hide() end);

    gui_container:AddChild(gui);
    gui_container:AddChild(btn);

    gui_container.frame:SetFrameStrata("LOW");

    function gui:Update()
        self:ReleaseChildren();

        for name, boss in pairs(WBT.db.global.boss) do
            if IsDead(name) and (not(boss.cyclic) or CyclicEnabled()) then
                local label = AceGUI:Create("InteractiveLabel");
                label:SetWidth(170);
                label:SetText(GetColoredBossName(name) .. ": " .. GetSpawnTimeOutput(name));
                label:SetCallback("OnClick", function() WBT:Print(name) end); -- TODO: change/disable this.
                -- Add the button to the container
                self:AddChild(label);
                --WBT:Print(label:IsShown());
            end
        end
    end

    function gui:InitPosition()
        gui_position = WBT.db.char.gui_position;
        local gp;
        if gui_position ~= nil then
            gp = gui_position;
        else
            gp = {
                point = "Center",
                relativeToName = "UIParrent",
                realtivePoint = nil,
                xOfs = 0,
                yOfs = 0,
            }
        end
        self:ClearAllPoints();
        self:SetPoint(gp.point, relativeTo, gp.xOfs, gp.yOfs);
    end

    local function RecordGUIPositioning()
        local function SaveGuiPoint()
            point, relativeTo, relativePoint, xOfs, yOfs = gui:GetPoint();
            WBT.db.char.gui_position = {
                point = point,
                relativeToName = "UIParrent",
                relativePoint = relativePoint,
                xOfs = xOfs,
                yOfs = yOfs,
            };
            -- print(WBT.db.char.gui_position.point, WBT.db.char.gui_position.relativeToName, WBT.db.char.gui_position.relativePoint, WBT.db.char.gui_position.xOfs, WBT.db.char.gui_position.yOfs);
        end
        hooksecurefunc(gui.frame, "StopMovingOrSizing", SaveGuiPoint);
    end

    gui:Update();

    gui:InitPosition();

    gui:Show();

    RecordGUIPositioning();
end

local function RegisterEvents()
    boss_death_frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED");
    boss_combat_frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED");
end

local function UnregisterEvents()
    boss_death_frame:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED");
    boss_combat_frame:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED");
end

local function ShowGUI()
    if gui ~= nil then
        gui:Hide();
        gui = nil;
    end
    InitGUI();
end

local function HideGUI()
    if gui ~= nil then
        gui:Hide();
        gui = nil;
    end
end

local function RestartGUI()
    HideGUI();
    ShowGUI();
end

local function UpdateGUIVisibility()
    if ShouldShowGUI() then
        RegisterEvents();
        RestartGUI();
    else
        UnregisterEvents();
        HideGUI();
    end
end

local function GetBossesToAnnounceInCurrentZone(current_zone_only)
    local current_zone = GetZoneText();
    local bosses = {};
    local num_entries = 0; -- No way to get size of table :(
    for name, boss in pairs(REGISTERED_BOSSES) do
        if (not current_zone_only) or current_zone == boss.zone then
            if IsDead(name) then
                bosses[name] = name;
                num_entries = num_entries + 1;
            end
        end
    end

    return bosses, num_entries;
end

local function CreateServerDeathTimeParseable(name, send_data_for_parsing)
    local server_death_time = "";
    if send_data_for_parsing then
        server_death_time = " (" .. SERVER_DEATH_TIME_PREFIX .. GetServerDeathTime(name) .. ")";
    end

    return server_death_time;
end

local function CreateAnnounceMessage(name, timer, send_data_for_parsing)
    local spawn_time = GetSpawnTime(name);
    local server_death_time = CreateServerDeathTimeParseable(name, send_data_for_parsing);

    local msg = ICON_SKULL .. name .. ICON_SKULL .. ": " .. spawn_time .. server_death_time;

    return msg;
end

local function AnnounceSpawnTimers(spawn_timers, num_entries, send_data_for_parsing)
    if num_entries > 0 then
        for name, timer in pairs(spawn_timers) do
            SendChatMessage(CreateAnnounceMessage(name, timer, send_data_for_parsing), CHANNEL_ANNOUNCE, nil, nil);
        end
    else
        WBT:Print("No spawn timers registered");
    end
end

local function AnnounceSpawnTime(current_zone_only, send_data_for_parsing)
    bosses, num_entries = GetBossesToAnnounceInCurrentZone(current_zone_only);
    AnnounceSpawnTimers(bosses, num_entries, send_data_for_parsing);
end

local function KillTag(timer, state)
    timer.kill = state;
end

-- For bosses with non-random spawn. Modify the result for other bosses.
local function EstimationNextSpawn(name)
    local t_spawn = WBT.db.global.boss[name].t_death;
    local t_now = GetServerTime();
    while t_spawn < t_now do
        t_spawn = t_spawn + MAX_RESPAWN_TIME;
    end

    local t_death_new = t_spawn - MAX_RESPAWN_TIME;
    return t_death_new, t_spawn;
end

local function StartWorldBossDeathTimer(...)

    local function MaybeAnnounceSpawnTimer(remaining_time, boss_name)
        --@do-not-package@
        -- Debug
        --local announce_times = {1 , 10, 19, 28, 37, 46, 55, 64, 73, 82, 91, 100, 109, 118, 127, 136, 145, 154, 163, 172, 181, 190, 199, 208, 217, 226, 235, 244, 253, 262, 271, 280, 289, 298, 307, 316, 325, 334, 343, 352, 361, 370, 379, 388, 397, 406, 415, 424, 433, 442, 451, 460, 469, 478, 487, 496, 505, 514, 523, 532, 541, 550, 559, 568, 577, 586, 595, 604, 613, 622, 631, 640, 649, 658, 667, 676, 685, 694, 703, 712, 721, 730, 739, 748, 757, 766, 775, 784, 793, 802, 811, 820, 829, 838, 847, 856, 865, 874, 883, 892}
        --@end-do-not-package@
        local announce_times = {1, 2, 3, 10, 30, 1*60, 5*60, 10*60};
        if WBT.db.global.auto_announce
                and SetContainsValue(announce_times, remaining_time)
                and IsInZoneOfBoss(boss_name)
                and IsKillInfoSafe({}) then
            AnnounceSpawnTime(true, SendDataEnabled());
        end
    end

    local function HasRespawned(name)
        return not IsDead(name);
    end

    local function StartTimer(boss, duration, freq, text)
        -- Always kill the previous frame and start a new one.
        if boss.timer ~= nil then
            KillTag(boss.timer, true);
        end

        -- Create new frame.
        boss.timer = CreateFrame("Frame");
        KillTag(boss.timer, false);

        local until_time = GetServerTime() + duration;
        local UpdateInterval = freq;
        boss.timer:SetScript("OnUpdate", function(self, elapsed)
                if self.TimeSinceLastUpdate == nil then
                    self.TimeSinceLastUpdate = 0;
                end
                self.TimeSinceLastUpdate = self.TimeSinceLastUpdate + elapsed;

                if (self.TimeSinceLastUpdate > UpdateInterval) then

                    if self.kill then
                        --KillUpdateFrame(self);
                        UpdateGUIVisibility();
                        return;
                    end

                    self.remaining_time = until_time - GetServerTime();

                    MaybeAnnounceSpawnTimer(self.remaining_time, boss.name);

                    if self.remaining_time < 0 then
                        if IsInZoneOfBoss(boss.name) then
                            FlashClientIcon();
                        end

                        if CyclicEnabled() then
                            local t_death_new, t_spawn = EstimationNextSpawn(boss.name);
                            boss.t_death = t_death_new
                            if REGISTERED_BOSSES[boss.name].random_spawn_time then
                                until_time = t_spawn - MAX_RESPAWN_TIME + MAX_RESPAWN_TIME_RANDOM;
                            else
                                until_time = t_spawn;
                            end

                            boss.cyclic = true;
                        else
                            --KillUpdateFrame(self);
                        end

                        UpdateGUIVisibility();
                    end

                    if gui ~= nil then
                        gui:Update();
                    end
                    self.TimeSinceLastUpdate = 0;
                end
            end);
        return timer;
    end

    for _, name in ipairs({...}) do -- To iterate varargs, note that they have to be in a table. They will be expanded otherwise.
        if WBT.db.global.boss[name] and (not(HasRespawned(name)) or CyclicEnabled()) then
            local timer_duration = GetSpawnTimeSec(name);
            StartTimer(WBT.db.global.boss[name], timer_duration, 1, REGISTERED_BOSSES[name].color .. name .. COLOR_DEFAULT .. ": ");
        end
    end
end

local function InitDeathTrackerFrame()
    if boss_death_frame ~= nil then
        return
    end

    boss_death_frame = CreateFrame("Frame");
    boss_death_frame:SetScript("OnEvent", function(event, ...)
		--local timestamp, eventType, hideCaster, sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID, destName, destFlags, destRaidFlags, extraArg1, extraArg2, extraArg3, extraArg4, extraArg5, extraArg6, extraArg7, extraArg8, extraArg9, extraArg10 = CombatLogGetCurrentEventInfo()
		local timestamp, eventType, hideCaster, sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID, destName = CombatLogGetCurrentEventInfo()

             if eventType == "UNIT_DIED" and IsBoss(destName) then
                 SetDeathTime(GetServerTime(), destName); -- Don't use timestamp from varags. It's not synchronized with server time.
                 StartWorldBossDeathTimer(destName);
             end
        end);
end

local function PlayAlertSound(boss_name)
    local sound_type = WBT.db.global.sound_type;
    local sound_enabled = WBT.db.global.sound_enabled;

    local soundfile = REGISTERED_BOSSES[boss_name].soundfile;
    if sound_type == SOUND_CLASSIC then
        soundfile = SOUND_FILE_DEFAULT;
    end

    if sound_enabled then
        PlaySoundFile(soundfile, "Master");
    else
        WBT:Print("Sound is off: enable with /WBT sound enable");
    end
end

local function InitCombatScannerFrame()
    if boss_combat_frame ~= nil then
        return
    end

    boss_combat_frame = CreateFrame("Frame");

    local time_out = 60*2; -- Legacy world bosses SHOULD die in this time.
    boss_combat_frame.t_next = 0;

    function boss_combat_frame:DoScanWorldBossCombat(event, ...)
		local timestamp, eventType, hideCaster, sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID, destName = CombatLogGetCurrentEventInfo()

        local t = GetServerTime();

        if IsBoss(destName) and t > self.t_next then
            WBT:Print(GetColoredBossName(destName) .. " is now engaged in combat!");
            PlayAlertSound(destName);
            FlashClientIcon();
            self.t_next = t + time_out;
        end
    end

    boss_combat_frame:SetScript("OnEvent", boss_combat_frame.DoScanWorldBossCombat);
end

function WBT:OnInitialize()
end

local function PrintKilledBosses()
    WBT:Print("Tracked world bosses killed:");

    local none_killed_text = "None";
    local num_saved_world_bosses = GetNumSavedWorldBosses();
    if num_saved_world_bosses == 0 then
        WBT:Print(none_killed_text);
    else
        local none_killed = true;
        for i=1, num_saved_world_bosses do
            local name = GetSavedWorldBossInfo(i);
            if IsBoss(name) then
                none_killed = false;
                WBT:Print(GetColoredBossName(name))
            end
        end
        if none_killed then
            WBT:Print(none_killed_text);
        end
    end
end

local function ResetKillInfo()
    WBT:Print("Resetting all kill info.");
    for k, v in pairs(WBT.db.global.boss) do
        KillTag(WBT.db.global.boss[k].timer, true);
        WBT.db.global.boss[k] = nil;
    end
end

local function SlashHandler(input)

    -- print(input);
    -- input = input:trim();
    arg1, arg2 = strsplit(" ", input);
    -- print(arg1, arg2);

    local function PrintHelp()
        local indent = "   ";
        WBT:Print("WorldBossTimers slash commands:");
        WBT:Print("/wbt reset --> Reset all kill info.");
        WBT:Print("/wbt saved --> Print your saved bosses.");
        WBT:Print("/wbt say --> Announce timers for boss in zone.");
        WBT:Print("/wbt say all --> Announce timers for all bosses.");
        WBT:Print("/wbt show --> Show the timers frame.");
        WBT:Print("/wbt hide --> Hide the timers frame.");
        WBT:Print("/wbt send --> Toggle send timer data in auto announce.");
        WBT:Print("/wbt sound --> Toggle sound alerts.");
        --WBT:Print("/wbt sound classic --> Sets sound to \'War Drums\'.");
        --WBT:Print("/wbt sound fancy --> Sets sound to \'fancy mode\'.");
        WBT:Print("/wbt ann --> Toggle automatic announcements.");
        WBT:Print("/wbt cyclic --> Toggle cyclic timers.");
    end

    local function GetColoredStatus(status_var)
        local color = COLOR_RED;
        local status = "disabled";
        if status_var then
            color = COLOR_GREEN;
            status = "enabled";
        end

        return color .. status .. COLOR_DEFAULT;
    end

    local function PrintFormattedStatus(output, status_var)
        WBT:Print(output .. " " .. GetColoredStatus(status_var) .. ".");
    end

    local new_state = nil;
    if arg1 == "hide" then
        HideGUI();
    elseif arg1 == "show" then
        ShowGUI();
    elseif arg1 == "say"
        or arg1 == "a"
        or arg1 == "announce"
        or arg1 == "yell"
        or arg1 == "tell" then

        local current_zone_only = arg2 ~= "all";
        if current_zone_only then
            local error_msgs = {};
            if IsInBossZone() and not IsKillInfoSafe(error_msgs) then
                SendChatMessage("{cross}Warning{cross}: Timer might be incorrect!", "SAY", nil, nil);
                for i, v in ipairs(error_msgs) do
                    SendChatMessage("{cross}" .. v .. "{cross}", "SAY", nil, nil);
                end
            end
            AnnounceSpawnTime(true, true);
        else
            AnnounceSpawnTime(false, true);
        end
    elseif arg1 == "send" then
        new_state = not SendDataEnabled();
        SetSendData(new_state);
        PrintFormattedStatus("Data sending in auto announce is now", new_state);
    elseif arg1 == "ann" then
        new_state = not AutoAnnounceEnabled();
        SetAutoAnnounce(new_state);
        PrintFormattedStatus("Automatic announcements are now", new_state);
    elseif arg1 == "r"
        or arg1 == "reset"
        or arg1 == "restart" then
        ResetKillInfo();
    elseif arg1 == "s"
        or arg1 == "saved"
        or arg1 == "save" then
        PrintKilledBosses();
    elseif arg1 == "request" then
        RequestKillData();
    elseif arg1 == "sound" then
        sound_type_args = {"classic", "fancy"};
        if SetContainsValue(sound_type_args, arg2) then
            WBT.db.global.sound_type = arg2;
            WBT:Print("SoundType: " .. arg2);
        else
            new_state = not SoundEnabled();
            SetSound(new_state);
            PrintFormattedStatus("Sound is now", new_state);
        end
    elseif arg1 == "cycle"
        or arg1 == "cyclic" then

        new_state = not CyclicEnabled()
        SetCyclic(new_state);
        UpdateGUIVisibility();
        PrintFormattedStatus("Cyclic mode is now", new_state);
    else
        PrintHelp();
    end

end

local function StartVisibilityHandler()
    local visibilty_handler_frame = CreateFrame("Frame");
    visibilty_handler_frame:RegisterEvent("ZONE_CHANGED_NEW_AREA");
    visibilty_handler_frame:SetScript("OnEvent",
        function(e, ...)
            UpdateGUIVisibility();
        end
    );
end

local function ShareTimers()
    AnnounceSpawnTime(true, true);
end

function WBT:GetGui()
    return gui;
end

function WBT:InitChatParsing()

    local function InitRequestParsing()
        local function PlayerSentRequest(sender)
            -- Since \b and alike doesnt exist: use "frontier pattern": %f[%A]
            return string.match(sender, GetUnitName("player") .. "%f[%A]") ~= nil;
        end

        local request_parser = CreateFrame("Frame");
        local answered_requesters = {};
        request_parser:RegisterEvent("CHAT_MSG_SAY");
        request_parser:SetScript("OnEvent",
            function(self, event, msg, sender)
                if event == "CHAT_MSG_SAY"
                        and msg == CHAT_MSG_TIMER_REQUEST
                        and not SetContainsKey(answered_requesters, sender)
                        and not PlayerSentRequest(sender)
                        and IsKillInfoSafe({}) then

                    ShareTimers();
                    answered_requesters[sender] = sender;
                end
            end
        );
    end

    local function InitSharedTimersParsing()
        local timer_parser = CreateFrame("Frame");
        timer_parser:RegisterEvent("CHAT_MSG_SAY");
        timer_parser:SetScript("OnEvent",
            function(self, event, msg, sender)
                if event == "CHAT_MSG_SAY" and string.match(msg, SERVER_DEATH_TIME_PREFIX) ~= nil then
                    local boss_name, server_death_time = string.match(msg, ".*([A-Z][a-z]+).*" .. SERVER_DEATH_TIME_PREFIX .. "(%d+)");
                    if IsBoss(boss_name) and not IsDead(boss_name) then
                        WBT:Print("Received " .. GetColoredBossName(boss_name) .. " timer from: " .. sender);
                        SetDeathTime(server_death_time, boss_name);
                        StartWorldBossDeathTimer(boss_name);
                    end
                end
            end
        );
    end

    InitRequestParsing();
    InitSharedTimersParsing();

end

function WBT:OnEnable()
	WBT.db = LibStub("AceDB-3.0"):New("WorldBossTimersDB", defaults);
    -- self.db.global = defaults.global; -- Resets the global profile in case I mess up the table
    -- /run for k, v in pairs(WBT.db.global) do WBT.db.global[k] = nil end -- Also resets global profile, but from in-game

    InitDeathTrackerFrame(); -- Todo: make sure this can't be called twice in same session
    InitCombatScannerFrame();
    InitGUI();

    if AnyDead() or IsBossZone() then
        RegisterEvents();
        StartWorldBossDeathTimer(unpack(GetBossNames()));
        ShowGUI();
    else
        HideGUI();
    end

    StartVisibilityHandler();

    self:RegisterChatCommand("wbt", SlashHandler);
    self:RegisterChatCommand("worldbosstimers", SlashHandler);

    self:InitChatParsing();

end

function WBT:OnDisable()
end

