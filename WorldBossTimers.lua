-- ----------------------------------------------------------------------------
--  A persistent timer for World Bosses.
-- ----------------------------------------------------------------------------

-- addonName, addonTable = ...;
local _, WBT = ...;
WBT.addon_name = "WorldBossTimers";

--@do-not-package@
wbt = WBT;
--@end-do-not-package@

local KillInfo = WBT.KillInfo;
local Util = WBT.Util;
local BossData = WBT.BossData;
local GUI = WBT.GUI;
local Options = WBT.Options;
local Com = WBT.Com;
local Sound = WBT.Sound;

-- Functions that will be created during startup.
WBT.Functions = {
    AnnounceTimerInChat = nil;
};


WBT.AceAddon = LibStub("AceAddon-3.0"):NewAddon("WBT", "AceConsole-3.0");

-- Workaround to keep the nice WBT:Print function.
WBT.Print = function(self, text) WBT.AceAddon:Print(text) end

-- Global logger. OK since WoW is single-threaded.
WBT.Logger = {};
local Logger = WBT.Logger;
Logger.LogLevels =  {
    Nothing = {
        value = 0;
        name  = "Nothing";
        color = Util.COLOR_DEFAULT;
    },
    Debug = {
        value = 10;
        name  = "Debug";
        color = Util.COLOR_BLUE;
    }
};


function Logger.PrintLogLevels()
    WBT:Print("Valid LogLevel values:");
    for k, _ in pairs(Logger.LogLevels) do
        WBT:Print(k);
    end
end

-- @param level_name    Log level given as string.
function Logger.SetLogLevel(level_name)
    if not level_name then
        Logger.PrintLogLevels();
        return;
    end

    -- Make sure input starts with uppercase and rest is lowercase to match
    -- table keys.
    level_name = level_name:sub(1,1):upper() .. level_name:sub(2,level_name:len()):lower();

    local log_level = Logger.LogLevels[level_name];
    if log_level then
        WBT:Print("Setting log level to: " .. log_level.name);
        WBT.db.char.log_level = log_level;
    else
        WBT:Print("Requested log level '" .. level_name .. "' doesn't exist.");
    end
end

-- @param varargs   A single table containing a list of strings, or varargs of
--                  strings.
function Logger.Log(log_level, ...)
    if WBT.db.char.log_level.value < log_level.value then
        return;
    end

    local prefix = "[" .. Util.ColoredString(log_level.color, log_level.name) .. "]: ";
    local arg1 = select(1, ...);
    if not arg1 then
        return;
    elseif Util.IsTable(arg1) then
        for _, msg in pairs(arg1) do
            WBT:Print(prefix .. msg)
        end
    else
        WBT:Print(prefix .. Util.MessageFromVarargs(...))
    end
end

function Logger.Debug(...)
    Logger.Log(Logger.LogLevels.Debug, ...);
end

local gui = {};
local boss_death_frame;
local boss_combat_frame;
local g_kill_infos = {};

local CHANNEL_ANNOUNCE = "SAY";
local ICON_SKULL = "{rt8}";
local SERVER_DEATH_TIME_PREFIX = "WorldBossTimers:";
local CHAT_MESSAGE_TIMER_REQUEST = "Could you please share WorldBossTimers kill data?";

local defaults = {
    global = {
        kill_infos = {},
        lock = false,
        sound_enabled = true,
        sound_type = WBT.Sound.SOUND_CLASSIC,
        cyclic = false,
        hide_gui = false,
        multi_realm = false,
        show_boss_zone_only = false,
    },
    char = {
        log_level = Logger.LogLevels.Nothing,
        boss = {},
    },
};

function WBT:PrintError(...)
    local text = "";
    for n=1, select('#', ...) do
      text = text .. " " .. select(n, ...);
    end
    text = Util.strtrim(text);
    text = Util.ColoredString(Util.COLOR_RED, text);
    WBT:Print(text);
end

function WBT.IsDead(guid, ignore_cyclic)
    local ki = g_kill_infos[guid];
    if ki and ki:IsValidVersion() then
        return ki:IsDead(ignore_cyclic);
    end

    return false;
end
local IsDead = WBT.IsDead;

function WBT.IsBoss(name)
    return Util.SetContainsKey(BossData.GetAll(), name);
end

function WBT.GetCurrentMapId()
    return C_Map.GetBestMapForUnit("player");
end

function WBT.IsInZoneOfBoss(name)
    return WBT.GetCurrentMapId() == BossData.Get(name).map_id;
end

function WBT.BossesInCurrentZone()
    local t = {};
    for name, boss in pairs(BossData.GetAll()) do
        if WBT.IsInZoneOfBoss(name) then
            table.insert(t, boss);
        end
    end

    if not Util.TableIsEmpty(t) then
        return t;
    end

    return nil;
end

function WBT.ThisServerAndWarmode(kill_info)
    return kill_info.realm_type == Util.WarmodeStatus()
            and kill_info.connected_realms_id == KillInfo.CreateConnectedRealmsID();
end

function WBT.InBossZone()
    local current_map_id = WBT.GetCurrentMapId();

    for name, boss in pairs(BossData.GetAll()) do
        if boss.map_id == current_map_id then
            return true;
        end
    end

    return false;
end

-- Returns the KillInfo in the current zone and shard that should be
-- used for announcements.
-- Returns nil if no matching entry found.
function WBT.KillInfoInCurrentZoneAndShard()
    if WBT.InBossZone() then
        -- Double hosting zones: Kun-Lai Summit hosts both ZWB and Sha
        -- Announce options:
        -- 1. Both
        -- 2. Base on X, Y coords
        -- 3. Only announce Sha <current implementation>

        -- Note: Only one boss per zone may have the 'announce' field set to true.
        for _, boss in pairs(WBT.BossesInCurrentZone()) do
            if boss.auto_announce then
                return g_kill_infos[KillInfo.CreateGUID(boss.name)];
            end
        end
    end

    return nil;
end

function WBT.GetSpawnTimeOutput(kill_info)
    local text = kill_info:GetSpawnTimeAsText();
    local color = Util.COLOR_DEFAULT;
    local highlight = Options.highlight.get()
            and WBT.IsInZoneOfBoss(kill_info.name)
            and tContains(Util.GetConnectedRealms(), kill_info.realm_name_normalized)
            and Util.WarmodeStatus() == kill_info.realm_type;
    if kill_info.cyclic then
        if highlight then
            color = Util.COLOR_YELLOW;
        else
            color = Util.COLOR_RED;
        end
    else
        if highlight then
            color = Util.COLOR_LIGHTGREEN;
        else
            -- Do nothing, default case.
        end
    end
    text = Util.ColoredString(color, text);

    if Options.show_saved.get() and BossData.IsSaved(kill_info.name) then
        text = text .. " " .. Util.ColoredString(Util.ReverseColor(color), "X");
    end

    return text;
end

local last_request_time = 0;
function WBT.RequestKillData()
    if GetServerTime() - last_request_time > 5 then
        SendChatMessage(CHAT_MESSAGE_TIMER_REQUEST, "SAY");
        last_request_time = GetServerTime();
    end
end
local RequestKillData = WBT.RequestKillData;

function WBT.GetColoredBossName(name)
    return BossData.Get(name).name_colored;
end
local GetColoredBossName = WBT.GetColoredBossName;

local function RegisterEvents()
    boss_death_frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED");
    boss_combat_frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED");
end

local function UnregisterEvents()
    boss_death_frame:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED");
    boss_combat_frame:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED");
end

function WBT.ResetBoss(guid)
    local kill_info = g_kill_infos[guid];
    local name = KillInfo.ParseGUID(guid).boss_name;

    if not kill_info.cyclic then
        local cyclic_mode = Util.COLOR_RED .. "Cyclic Mode" .. Util.COLOR_DEFAULT;
        WBT:Print("Clicking a world boss that is in " .. cyclic_mode .. " will reset it."
            .. " Try '/wbt cyclic' for more info.");
    else
        kill_info:Reset();
        gui:Update();
        WBT:Print(GetColoredBossName(name) .. " has been reset.");
    end
end

local function UpdateCyclicStates()
    for _, kill_info in pairs(g_kill_infos) do
        if kill_info:Expired() then
            kill_info.cyclic = true;
        end
    end
end

local function CreateServerDeathTimeParseable(kill_info, send_data_for_parsing)
    local t_death_parseable = "";
    if send_data_for_parsing then
        t_death_parseable = " (" .. SERVER_DEATH_TIME_PREFIX .. kill_info:GetServerDeathTime() .. ")";
    end

    return t_death_parseable;
end

local function CreateAnnounceMessage(kill_info, send_data_for_parsing)
    local spawn_time = kill_info:GetSpawnTimeAsText();
    local t_death_parseable = CreateServerDeathTimeParseable(kill_info, send_data_for_parsing);

    local msg = ICON_SKULL .. kill_info.name .. ICON_SKULL .. ": " .. spawn_time .. t_death_parseable;

    return msg;
end

function WBT.AnnounceSpawnTime(kill_info, send_data_for_parsing)
    local msg = CreateAnnounceMessage(kill_info, send_data_for_parsing);
    if Options.silent.get() then
        WBT:Print(msg);
    else
        SendChatMessage(msg, CHANNEL_ANNOUNCE, DEFAULT_CHAT_FRAME.editBox.languageID, nil);
    end
end

-- Callback for GUI share button
local function GetSafeSpawnAnnouncerWithCooldown()

    -- Create closure that uses t_last_announce as a persistent/static variable
    local t_last_announce = 0;
    function AnnounceSpawnTimeIfSafe()
        local kill_info = WBT.KillInfoInCurrentZoneAndShard();
        local announced = false;
        local t_now = GetServerTime();

        if not kill_info then
            Logger.Debug("No timer found for current zone.");
            return announced;
        end
        if not ((t_last_announce + 1) <= t_now) then
            Logger.Debug("Can only share once per second.");
            return announced;
        end

        local errors = {};
        if kill_info:IsSafeToShare(errors) then
            WBT.AnnounceSpawnTime(kill_info, true);
            t_last_announce = t_now;
            announced = true;
        else
            Logger.Debug("Cannot share timer for " .. GetColoredBossName(kill_info.name) .. ":");
            Logger.Debug(errors);
            return announced;
        end

        return announced;
    end

    return AnnounceSpawnTimeIfSafe;
end

function WBT.SetKillInfo(name, t_death)
    t_death = tonumber(t_death);
    local guid = KillInfo.CreateGUID(name);
    local ki = g_kill_infos[guid];
    if ki then
        ki:SetNewDeath(name, t_death);
    else
        ki = KillInfo:New(t_death, name);
    end

    g_kill_infos[guid] = ki;

    gui:Update();
end

local function InitDeathTrackerFrame()
    if boss_death_frame ~= nil then
        return
    end

    boss_death_frame = CreateFrame("Frame");
    boss_death_frame:SetScript("OnEvent", function(event, ...)
            local timestamp, eventType, hideCaster, sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID, destName = CombatLogGetCurrentEventInfo();

            -- Convert to English name from GUID, to make it work for
            -- localization.
            local name = BossData.NameFromNpcGuid(destGUID, WBT.GetCurrentMapId());
            if name == nil then
                return;
            end

            if eventType == "UNIT_DIED" then
                WBT.SetKillInfo(name, GetServerTime());
                RequestRaidInfo(); -- Updates which bosses are saved
                gui:Update();
            end
        end);
end

local function PlaySoundAlertSpawn()
    Util.PlaySoundAlert(Options.spawn_alert_sound:Value());
end

local function PlaySoundAlertBossCombat(name)
    local sound_type = WBT.db.global.sound_type;

    local soundfile = BossData.Get(name).soundfile;
    if sound_type:lower() == Sound.SOUND_CLASSIC:lower() then
        soundfile = Sound.SOUND_FILE_DEFAULT;
    end

    Util.PlaySoundAlert(soundfile);
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

        -- Convert to English name from GUID, to make it work for
        -- localization.
        local name = BossData.NameFromNpcGuid(destGUID, WBT.GetCurrentMapId());
        if name == nil then
            return;
        end

        local t = GetServerTime();
        if WBT.IsBoss(name) and t > self.t_next then
            WBT:Print(GetColoredBossName(name) .. " is now engaged in combat!");
            PlaySoundAlertBossCombat(name);
            FlashClientIcon();
            self.t_next = t + time_out;
        end
    end

    boss_combat_frame:SetScript("OnEvent", boss_combat_frame.DoScanWorldBossCombat);
end

function WBT.AceAddon:OnInitialize()
end

function WBT.PrintKilledBosses()
    WBT:Print("Tracked world bosses killed:");

    local none_killed = true;
    for _, boss in pairs(BossData.GetAll()) do
        if BossData.IsSaved(boss.name) then
            none_killed = false;
            WBT:Print(GetColoredBossName(boss.name));
        end
    end
    if none_killed then
        -- There might be other bosses that WBT doesn't track that
        -- have been killed.
        local none_killed_text = "None";
        WBT:Print(none_killed_text);
    end
end

function WBT.ResetKillInfo()
    WBT:Print("Resetting all kill info.");
    for _, kill_info in pairs(g_kill_infos) do
        kill_info:Reset();
    end

    gui:Update();
end

local function StartVisibilityHandler()
    local visibilty_handler_frame = CreateFrame("Frame");
    visibilty_handler_frame:RegisterEvent("ZONE_CHANGED_NEW_AREA");
    visibilty_handler_frame:SetScript("OnEvent",
        function(e, ...)
            gui:Update();
        end
    );
end

function WBT.AceAddon:InitChatParsing()

    local function PlayerSentMessage(sender)
        -- Since \b and alike doesnt exist: use "frontier pattern": %f[%A]
        return string.match(sender, GetUnitName("player") .. "%f[%A]") ~= nil;
    end

    local function InitRequestParsing()
        local request_parser = CreateFrame("Frame");
        local answered_requesters = {};
        request_parser:RegisterEvent("CHAT_MSG_SAY");
        request_parser:SetScript("OnEvent",
            function(self, event, msg, sender)
                if event == "CHAT_MSG_SAY" 
                        and msg == CHAT_MESSAGE_TIMER_REQUEST
                        and not Util.SetContainsKey(answered_requesters, sender)
                        and not PlayerSentMessage(sender) then

                    if WBT.InBossZone() then
                        local kill_info = WBT.KillInfoInCurrentZoneAndShard();
                        if kill_info and kill_info:IsSafeToShare({}) then
                            -- WBT.AnnounceSpawnTime(kill_info, true); DISABLED: broken by 8.2.5
                            -- TODO: Consider if this could trigger some optional sparkle
                            -- in the GUI instead
                            answered_requesters[sender] = sender;
                        end
                    end
                end
            end
        );
    end

    local function InitSharedTimersParsing()
        local timer_parser = CreateFrame("Frame");
        timer_parser:RegisterEvent("CHAT_MSG_SAY");
        timer_parser:SetScript("OnEvent",
            function(self, event, msg, sender)
                if event == "CHAT_MSG_SAY" then
                    if PlayerSentMessage(sender) then
                        return;
                    elseif string.match(msg, SERVER_DEATH_TIME_PREFIX) ~= nil then
                        local name, t_death = string.match(msg, ".*([A-Z][a-z]+).*" .. SERVER_DEATH_TIME_PREFIX .. "(%d+)");
                        local guid = KillInfo.CreateGUID(name);
                        local ignore_cyclic = true;
                        if WBT.IsBoss(name) and not IsDead(guid, ignore_cyclic) then
                            WBT.SetKillInfo(name, t_death);
                            WBT:Print("Received " .. GetColoredBossName(name) .. " timer from: " .. sender);
                        end
                    end
                end
            end
        );
    end

    InitRequestParsing();
    InitSharedTimersParsing();
end

local function LoadSerializedKillInfos()
    for name, serialized in pairs(WBT.db.global.kill_infos) do
        g_kill_infos[name] = KillInfo:Deserialize(serialized);
    end
end

-- Step1 is performed before deserialization and looks just at the GUID.
local function FilterValidKillInfosStep1()
    -- Perform filtering in two steps to avoid what I guess would
    -- be some kind of "ConcurrentModificationException".

    -- Find invalid.
    local invalid = {};
    for guid, ki in pairs(WBT.db.global.kill_infos) do
        if not KillInfo.ValidGUID(guid) then
            invalid[guid] = ki;
        end
    end

    -- Remove invalid.
    for guid, ki in pairs(invalid) do
        Logger.Debug("[PreDeserialize]: Removing invalid KI with GUID: " .. guid);
        WBT.db.global.kill_infos[guid] = nil;
    end
end

-- Step2 is performed after deserialization and checks the internal data.
local function FilterValidKillInfosStep2()
    -- Find invalid.
    local invalid = {};
    for guid, ki in pairs(g_kill_infos) do
        if not ki:IsValidVersion() or ki.reset then
            table.insert(invalid, guid);
        end
    end

    -- Remove invalid.
    for _, guid in pairs(invalid) do
        Logger.Debug("[PostDeserialize]: Removing invalid KI with GUID: " .. guid);
        WBT.db.global.kill_infos[guid] = nil;
    end
end

local function InitKillInfoManager()
    g_kill_infos = WBT.db.global.kill_infos; -- Everything in g_kill_infos is written to db.
    LoadSerializedKillInfos();
    FilterValidKillInfosStep2();

    kill_info_manager = CreateFrame("Frame");
    kill_info_manager.since_update = 0;
    local t_update = 1;
    kill_info_manager:SetScript("OnUpdate", function(self, elapsed)
            self.since_update = self.since_update + elapsed;
            if (self.since_update > t_update) then
                for _, kill_info in pairs(g_kill_infos) do
                    kill_info:Update();

                    if kill_info.reset then
                        -- Do nothing.
                    else
                        if kill_info:ShouldAnnounce() then
                            -- WBT.AnnounceSpawnTime(kill_info, true); DISABLED: broken in 8.2.5
                            -- TODO: Consider if here should be something else
                        end

                        if kill_info:RespawnTriggered(Options.spawn_alert_sec_before.get()) then
                            FlashClientIcon();
                            PlaySoundAlertSpawn();
                        end

                        if kill_info:Expired() and Options.cyclic.get() then
                            local t_death_new, t_spawn = kill_info:EstimationNextSpawn();
                            kill_info.t_death = t_death_new
                            self.until_time = t_spawn;
                            kill_info.cyclic = true;
                        end
                    end
                end

                gui:Update();

                self.since_update = 0;
            end
        end);
end

function WBT.AceAddon:OnEnable()
    GUI.Init();

	WBT.db = LibStub("AceDB-3.0"):New("WorldBossTimersDB", defaults);
    LibStub("AceComm-3.0"):Embed(Com);

    Com:Init(); -- Must init after db.
    if Com.ShouldRevertRequestMode() then
        Com.LeaveRequestMode();
    end

    -- Note that Com is currently not used, since it only works for
    -- connected realms...
    Com:RegisterComm(Com.PREF_SR, Com.OnCommReceivedSR);
    Com:RegisterComm(Com.PREF_RR, Com.OnCommReceivedRR);

    WBT.Functions.AnnounceTimerInChat = GetSafeSpawnAnnouncerWithCooldown();

    FilterValidKillInfosStep1();

    GUI.SetupAceGUI();

    local AceConfig = LibStub("AceConfig-3.0");

    AceConfig:RegisterOptionsTable(WBT.addon_name, Options.optionsTable, {});
    WBT.AceConfigDialog = LibStub("AceConfigDialog-3.0");
    WBT.AceConfigDialog:AddToBlizOptions(WBT.addon_name, WBT.addon_name, nil);

    gui = WBT.GUI:New();

    InitDeathTrackerFrame();
    InitCombatScannerFrame();

    UpdateCyclicStates();

    InitKillInfoManager();

    StartVisibilityHandler();

    self:RegisterChatCommand("wbt", Options.SlashHandler);
    self:RegisterChatCommand("worldbosstimers", Options.SlashHandler);

    self:InitChatParsing();

    RegisterEvents(); -- TODO: Update when this and unreg is called!
    -- UnregisterEvents();
end

function WBT.AceAddon:OnDisable()
end

--@do-not-package@
function RandomServerName()
	local res = ""
	for i = 1, 10 do
		res = res .. string.char(math.random(97, 122))
	end
	return res
end

local function StartSim(name, t)
    WBT.SetKillInfo(name, t);
end

local function SetKillInfo_Advanced(name, t_death, connected_realms_id, realm_type, optVersion)
    version = optVersion or KillInfo.CURRENT_VERSION;
    t_death = tonumber(t_death);
    local guid = KillInfo.CreateGUID(name, connected_realms_id, realm_type);
    local ki = g_kill_infos[guid];
    if ki then
        ki:SetNewDeath(name, t_death);
    else
        ki = KillInfo:New(t_death, name);
    end
    ki.connected_realms_id = connected_realms_id;
    ki.realm_type = realm_type;
    ki.version = version;

    g_kill_infos[guid] = ki;

    gui:Update();
end

local function SecToRespawn(name, t)
    return GetServerTime() - BossData.Get(name).max_respawn + t;
end

local function SimOutdatedVersionKill(name)
    SetKillInfo_Advanced(name, SecToRespawn(name, 4), "Firehammer", Util.Warmode.ENABLED, "v_unsupported");
end

local function SimWarmodeKill(name)
    SetKillInfo_Advanced(name, SecToRespawn(name, 4), "Doomhammer", Util.Warmode.ENABLED);
end

local function SimServerKill(name, server)
    SetKillInfo_Advanced(name, SecToRespawn(name, 4), server or "Majsbreaker", Util.Warmode.DISABLED);
end

local function SimKillSpecial()
    SimServerKill("Grellkin");
    SimWarmodeKill("Grellkin");
    SimOutdatedVersionKill("Grellkin");
end

local function SimKill(sec_to_respawn)
    for name, data in pairs(BossData.GetAll()) do
        StartSim(name, SecToRespawn(name, sec_to_respawn));
    end
    SimKillSpecial();
end

function dsim(n)
    if n == nil then
        SimKill(4);
    else
        for i = 1, n do
            SimServerKill("Grellkin", RandomServerName())
        end
    end
end

-- Relog, and make sure it works after.
function dsim2()
    SimKill(25);
end

function dsim3()
    SimKillSpecial();
end

function PrintAllKillInfos()
    Logger.Debug("Printing all KI:s");
    for guid, ki in pairs(g_kill_infos) do
        print(guid)
        ki:Print("  ");
    end
end

function stopgui()
    kill_info_manager:SetScript("OnUpdate", nil);
end

function SetLogLevel(level_name)
    Logger.SetLogLevel(level_name);
end
--@end-do-not-package@

