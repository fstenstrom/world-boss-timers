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
local Config = WBT.Config;


WBT.AceAddon = LibStub("AceAddon-3.0"):NewAddon("WBT", "AceConsole-3.0");

-- Workaround to keep the nice WBT:Print function.
WBT.Print = function(self, text) WBT.AceAddon:Print(text) end

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
        sound_enabled = true,
        sound_type = Config.SOUND_CLASSIC,
        auto_announce = true,
        send_data = true,
        cyclic = false,
        hide_gui = false,
        multi_realm = false,
        show_boss_zone_only = false,
    },
    char = {
        boss = {},
    },
};

function WBT.DebugPrint(...)
    print("DEBUG:", Util.MessageFromVarargs(...));
end

function WBT.IsDead(guid, ignore_cyclic)
    local ki = g_kill_infos[guid];
    if ki and ki:IsValid() then
        return ki:IsDead(ignore_cyclic);
    end

    return false;
end
local IsDead = WBT.IsDead;

local function IsBoss(name)
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
            and kill_info.realmName == GetRealmName();
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
    if kill_info.cyclic then
        text = Util.COLOR_RED .. text .. Util.COLOR_DEFAULT;
    end

    return text;
end
local GetSpawnTimeOutput = WBT.GetSpawnTimeOutput;

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
    SendChatMessage(CreateAnnounceMessage(kill_info, send_data_for_parsing), CHANNEL_ANNOUNCE, nil, nil);
end
local AnnounceSpawnTime = WBT.AnnounceSpawnTime;

local function SetKillInfo(name, t_death)
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
                SetKillInfo(name, GetServerTime());
                gui:Update();
            end
        end);
end

local function PlayAlertSound(name)
    local sound_type = WBT.db.global.sound_type;
    local sound_enabled = WBT.db.global.sound_enabled;

    local soundfile = BossData.Get(name).soundfile;
    if sound_type:lower() == Config.SOUND_CLASSIC:lower() then
        soundfile = BossData.SOUND_FILE_DEFAULT;
    end

    if sound_enabled then
        PlaySoundFile(soundfile, "Master");
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

        -- Convert to English name from GUID, to make it work for
        -- localization.
        local name = BossData.NameFromNpcGuid(destGUID, WBT.GetCurrentMapId());
        if name == nil then
            return;
        end

        local t = GetServerTime();
        if IsBoss(name) and t > self.t_next then
            WBT:Print(GetColoredBossName(name) .. " is now engaged in combat!");
            PlayAlertSound(name);
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
local PrintKilledBosses = WBT.PrintKilledBosses;

function WBT.ResetKillInfo()
    WBT:Print("Resetting all kill info.");
    for _, kill_info in pairs(g_kill_infos) do
        kill_info:Reset();
    end

    gui:Update();
end
local ResetKillInfo = WBT.ResetKillInfo;

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
                        if kill_info and kill_info:IsCompletelySafe({}) then
                            AnnounceSpawnTime(kill_info, true);
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
                        if IsBoss(name) and not IsDead(guid, ignore_cyclic) then
                            SetKillInfo(name, t_death);
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
        WBT.db.global.kill_infos[guid] = nil;
    end
end

-- Step2 is performed after deserialization and checks the internal data.
local function FilterValidKillInfosStep2()
    -- Find invalid.
    local invalid = {};
    for _, ki in pairs(g_kill_infos) do
        if not ki:IsValid() or ki.reset then
            table.insert(invalid, ki:GUID());
        end
    end

    -- Remove invalid.
    for _, guid in pairs(invalid) do
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
                    if kill_info:IsValid() then

                        kill_info:Update();

                        if kill_info.reset then
                            -- Do nothing.
                        else
                            if kill_info:ShouldAnnounce() then
                                AnnounceSpawnTime(kill_info, Config.send_data.get());
                            end

                            if kill_info:ShouldFlash() then
                                FlashClientIcon();
                            end

                            if kill_info:Expired() and Config.cyclic.get() then
                                local t_death_new, t_spawn = kill_info:EstimationNextSpawn();
                                kill_info.t_death = t_death_new
                                self.until_time = t_spawn;
                                kill_info.cyclic = true;
                            end
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

    FilterValidKillInfosStep1();

    GUI.SetupAceGUI();

    local AceConfig = LibStub("AceConfig-3.0");

    AceConfig:RegisterOptionsTable(WBT.addon_name, Config.optionsTable, {});
    WBT.AceConfigDialog = LibStub("AceConfigDialog-3.0");
    WBT.AceConfigDialog:AddToBlizOptions(WBT.addon_name, WBT.addon_name, nil);


    InitDeathTrackerFrame();
    InitCombatScannerFrame();

    UpdateCyclicStates();

    InitKillInfoManager();

    gui = WBT.GUI:New();

    StartVisibilityHandler();

    self:RegisterChatCommand("wbt", Config.SlashHandler);
    self:RegisterChatCommand("worldbosstimers", Config.SlashHandler);

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
    SetKillInfo(name, t);
end

local function SetKillInfo_GUID(name, t_death, realmName, realm_type)
    t_death = tonumber(t_death);
    local guid = KillInfo.CreateGUID(name, realmName, realm_type);
    local ki = g_kill_infos[guid];
    if ki then
        ki:SetNewDeath(name, t_death);
    else
        ki = KillInfo:New(t_death, name);
    end
    ki.realmName = realmName;
    ki.realm_type = realm_type;

    g_kill_infos[guid] = ki;

    gui:Update();
end

local function SecToRespawn(name, t)
    return GetServerTime() - BossData.Get(name).max_respawn + t;
end

local function SimWarmodeKill(name)
    SetKillInfo_GUID(name, SecToRespawn(name, 4), "Doomhammer", Util.Warmode.ENABLED);
end

local function SimServerKill(name, server)
    SetKillInfo_GUID(name, SecToRespawn(name, 4), server or "Majsbreaker", Util.Warmode.DISABLED);
end

local function SimKill(sec_to_respawn)
    for name, data in pairs(BossData.GetAll()) do
        StartSim(name, SecToRespawn(name, sec_to_respawn));
    end
    SimServerKill("Grellkin");
    SimWarmodeKill("Grellkin");
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
--@end-do-not-package@

