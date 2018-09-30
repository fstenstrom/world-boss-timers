-- ----------------------------------------------------------------------------
--  A persistent timer for World Bosses.
-- ----------------------------------------------------------------------------

-- addonName, addonTable = ...;
local _, WBT = ...;

--@do-not-package@
wbt_addon = WBT;
--@end-do-not-package@

local KillInfo = WBT.KillInfo;
local Util = WBT.Util;
local BossData = WBT.BossData;
local GUI = WBT.GUI;


WBT.AceAddon = LibStub("AceAddon-3.0"):NewAddon("WBT", "AceConsole-3.0");

-- Workaround to keep the nice WBT:Print function.
WBT.Print = function(self, text) WBT.AceAddon:Print(text) end

local gui = {};
local boss_death_frame;
local boss_combat_frame;
local g_kill_infos = {};

local SOUND_CLASSIC = "CLASSIC";
local SOUND_FANCY = "FANCY";

local CHANNEL_ANNOUNCE = "SAY";
local ICON_SKULL = "{skull}";
local SERVER_DEATH_TIME_PREFIX = "WorldBossTimers:";
local CHAT_MESSAGE_TIMER_REQUEST = "Could you please share WorldBossTimers kill data?";

local defaults = {
    global = {
        kill_infos = {},
        sound_enabled = true,
        sound_type = SOUND_CLASSIC,
        auto_announce = true,
        send_data = true,
        cyclic = false,
        hide_gui = false,
    },
    char = {
        boss = {},
    },
};

function WBT.CyclicEnabled()
    return WBT.db.global.cyclic;
end

local CyclicEnabled = WBT.CyclicEnabled;

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

function WBT.IsDead(name)
    local ki = g_kill_infos[name];
    if ki and ki:IsValid() then
        return ki:IsDead();
    end
end
local IsDead = WBT.IsDead;

function WBT.IsBoss(name)
    return Util.SetContainsKey(BossData.GetAll(), name);
end
local IsBoss = WBT.IsBoss;

function WBT.IsInZoneOfBoss(name)
    return GetZoneText() == BossData.Get(name).zone;
end

local function BossInCurrentZone()
    for name, boss in pairs(BossData.GetAll()) do
        if WBT.IsInZoneOfBoss(name) then
            return boss;
        end
    end

    return nil;
end

local function IsInBossZone()
    return not not BossInCurrentZone();
end

local function GetKillInfoFromZone()
    local current_zone = GetZoneText();
    for name, boss_info in pairs(BossData.GetAll()) do
        if boss_info.zone == current_zone then
            return g_kill_infos[boss_info.name];
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

function WBT.IsBossZone()
    local current_zone = GetZoneText();

    local is_boss_zone = false;
    for name, boss in pairs(BossData.GetAll()) do
        if boss.zone == current_zone then
            is_boss_zone = true;
        end
    end

    return is_boss_zone;
end
local IsBossZone = WBT.IsBossZone;

function WBT.AnyDead()
    for name, boss in pairs(BossData.GetAll()) do
        if IsDead(name) then
            return true;
        end
    end
    return false;
end
local AnyDead = WBT.AnyDead;

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

function WBT.ResetBoss(name)
    local kill_info = g_kill_infos[name];

    if not kill_info.cyclic then
        local cyclic_mode = Util.COLOR_RED .. "Cyclid Mode" .. Util.COLOR_DEFAULT;
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

local function AnnounceSpawnTime(kill_info, send_data_for_parsing)
    SendChatMessage(CreateAnnounceMessage(kill_info, send_data_for_parsing), CHANNEL_ANNOUNCE, nil, nil);
end

local function SetKillInfo(name, t_death)
    t_death = tonumber(t_death);
    local ki = g_kill_infos[name];
    if ki then
        ki:SetNewDeath(name, t_death);
    else
        ki = KillInfo:New(t_death, name);
    end

    g_kill_infos[name] = ki;

    gui:Update();
end

local function InitDeathTrackerFrame()
    if boss_death_frame ~= nil then
        return
    end

    boss_death_frame = CreateFrame("Frame");
    boss_death_frame:SetScript("OnEvent", function(event, ...)
		local timestamp, eventType, hideCaster, sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID, destName = CombatLogGetCurrentEventInfo()

             if eventType == "UNIT_DIED" and IsBoss(destName) then
                 SetKillInfo(destName, GetServerTime());
                 gui:Update();
             end
        end);
end

local function PlayAlertSound(name)
    local sound_type = WBT.db.global.sound_type;
    local sound_enabled = WBT.db.global.sound_enabled;

    local soundfile = BossData.Get(name).soundfile;
    if sound_type == SOUND_CLASSIC then
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

function WBT.AceAddon:OnInitialize()
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
    for _, kill_info in pairs(g_kill_infos) do
        kill_info:Reset();
    end

    gui:Update();
end

local function SlashHandler(input)
    arg1, arg2 = strsplit(" ", input);

    local function PrintHelp()
        local indent = "   ";
        WBT:Print("WorldBossTimers slash commands:");
        WBT:Print("/wbt reset --> Reset all kill info.");
        WBT:Print("/wbt saved --> Print your saved bosses.");
        WBT:Print("/wbt say --> Announce timers for boss in zone.");
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
        local color = Util.COLOR_RED;
        local status = "disabled";
        if status_var then
            color = Util.COLOR_GREEN;
            status = "enabled";
        end

        return color .. status .. Util.COLOR_DEFAULT;
    end

    local function PrintFormattedStatus(output, status_var)
        WBT:Print(output .. " " .. GetColoredStatus(status_var) .. ".");
    end

    local new_state = nil;
    if arg1 == "hide" then
        WBT.db.global.hide_gui = true;
        gui:Hide();
    elseif arg1 == "show" then
        WBT.db.global.hide_gui = false;
        if gui:ShouldShow() then
            gui:Show();
        else
            WBT:Print("Timer window will show when next you enter a boss zone.");
        end
    elseif arg1 == "say"
        or arg1 == "a"
        or arg1 == "announce"
        or arg1 == "yell"
        or arg1 == "tell" then

        local boss = BossInCurrentZone();
        if not boss then
            WBT:Print("You can't announce outside of boss zone.");
            return;
        end

        local kill_info = g_kill_infos[boss.name];
        if not kill_info or not(kill_info:IsValid()) then
            WBT:Print("No spawn timer for " .. GetColoredBossName(boss.name) .. ".");
            return;
        end

        local error_msgs = {};
        if not kill_info:IsCompletelySafe(error_msgs) then
            SendChatMessage("{cross}Warning{cross}: Timer might be incorrect!", "SAY", nil, nil);
            for i, v in ipairs(error_msgs) do
                SendChatMessage("{cross}" .. v .. "{cross}", "SAY", nil, nil);
            end
        end
        AnnounceSpawnTime(kill_info, SendDataEnabled());
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
        if Util.SetContainsValue(sound_type_args, arg2) then
            WBT.db.global.sound_type = arg2;
            WBT:Print("SoundType: " .. arg2);
        else
            new_state = not SoundEnabled();
            SetSound(new_state);
            PrintFormattedStatus("Sound is now", new_state);
        end
    elseif arg1 == "cycle"
        or arg1 == "cyclic" then

        new_state = not CyclicEnabled();
        SetCyclic(new_state);
        gui:Update();

        PrintFormattedStatus("Cyclic mode is now", new_state);
        local red_text = Util.COLOR_RED .. "red text" .. Util.COLOR_DEFAULT;
        WBT:Print("This mode will repeat the boss timers if you miss the kill. A timer in " .. red_text
            .. " indicates cyclic mode. By clicking a boss's name in the timer window you can reset it permanently.");
    else
        PrintHelp();
    end
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
                        and msg == CHAT_MESSAGE_TIMER_REQUEST
                        and not Util.SetContainsKey(answered_requesters, sender)
                        and not PlayerSentRequest(sender) then

                    local boss = BossInCurrentZone();
                    if boss then
                        local kill_info = g_kill_infos[boss.name]
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
                if event == "CHAT_MSG_SAY" and string.match(msg, SERVER_DEATH_TIME_PREFIX) ~= nil then
                    local name, t_death = string.match(msg, ".*([A-Z][a-z]+).*" .. SERVER_DEATH_TIME_PREFIX .. "(%d+)");
                    if IsBoss(name) and not IsDead(name) then
                        SetKillInfo(name, t_death);
                        WBT:Print("Received " .. GetColoredBossName(name) .. " timer from: " .. sender);
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

local function InitKillInfoManager()
    g_kill_infos = WBT.db.global.kill_infos;
    LoadSerializedKillInfos();

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
                                AnnounceSpawnTime(kill_info, SendDataEnabled());
                            end

                            if kill_info:ShouldFlash() then
                                FlashClientIcon();
                            end

                            if kill_info:Expired() and CyclicEnabled() then
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
	WBT.db = LibStub("AceDB-3.0"):New("WorldBossTimersDB", defaults);
    GUI.SetupAceGUI();

    InitDeathTrackerFrame();
    InitCombatScannerFrame();
    if AnyDead() or IsBossZone() then
        RegisterEvents();
    end

    UpdateCyclicStates();

    InitKillInfoManager();

    gui = WBT.GUI:New();

    StartVisibilityHandler();

    self:RegisterChatCommand("wbt", SlashHandler);
    self:RegisterChatCommand("worldbosstimers", SlashHandler);

    self:InitChatParsing();

    RegisterEvents(); -- TODO: Update when this and unreg is called!
    -- UnregisterEvents();
end

function WBT.AceAddon:OnDisable()
end

--@do-not-package@
function d(min, sec)
    if not min then
        min = 17;
        sec = 55;
    end
    local decr = (60 * min + sec)
    local kill_info = g_kill_infos["Grellkin"];
    kill_info.t_death = kill_info.t_death - decr;
    kill_info.timer.until_time = kill_info.timer.until_time - decr;
end

local function start_sim(name, t)
    SetKillInfo(name, t);
end

function dsim()
    local function death_in_sec(name, t)
        return GetServerTime() - BossData.Get(name).max_respawn + t;
    end

    for name, data in pairs(BossData.GetAll()) do
        start_sim(name, death_in_sec(name, 4));
    end

end

-- Relog, and make sure it works after.
function dsim2()
    local function death_in_sec(name, t)
        return GetServerTime() - BossData.Get(name).max_respawn + t;
    end

    for name, data in pairs(BossData.GetAll()) do
        start_sim(name, death_in_sec(name, 25));
    end
end

function sim()
    start_sim(sha);
    start_sim(galleon);
end

function killsim()
    KillTag(g_kill_infos[galleon].timer, true);
    KillTag(g_kill_infos[sha].timer, true);
end

function reset()
    ResetKillInfo();
end

function test_KillInfo()
    local ki = WBT.KillInfo:New({name = "Testy",})
    ki:Print()
end
--@end-do-not-package@

