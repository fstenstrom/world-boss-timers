-- ----------------------------------------------------------------------------
--  A persistent timer for World Bosses.
-- ----------------------------------------------------------------------------

-- addonName, addonTable = ...;
local _, WBT = ...;
WBT.addon_name = "WorldBossTimers";

local KillInfo = WBT.KillInfo;
local BossData = WBT.BossData;
local Options  = WBT.Options;
local Sound    = WBT.Sound;
local Util     = WBT.Util;
local GUI      = WBT.GUI;
local Com      = WBT.Com;

-- Functions that will be created during startup.
WBT.Functions = {
    AnnounceTimerInChat = nil;
};

WBT.AceAddon = LibStub("AceAddon-3.0"):NewAddon("WBT", "AceConsole-3.0");

-- Workaround to keep the nice WBT:Print function.
WBT.Print = function(self, text) WBT.AceAddon:Print(text) end


-- Enum that describes why the GUI was requested to update.
WBT.UpdateEvents = {
    UNSPECIFIED    = 0,
    SHARD_DETECTED = 1,
}

--------------------------------------------------------------------------------
-- Logger
--------------------------------------------------------------------------------

-- Global logger. OK since WoW is single-threaded.
WBT.Logger = {
    options_tbl = nil; -- Used to show options in GUI.
};
local Logger = WBT.Logger;
Logger.LogLevels =  {
    Nothing = {
        value = 0;
        name  = "Nothing";
        color = Util.COLOR_DEFAULT;
    },
    Info = {
        value = 1;
        name  = "Info";
        color = Util.COLOR_BLUE;
    },
    Debug = {
        value = 10;
        name  = "Debug";
        color = Util.COLOR_PURPLE;
    }
};

function Logger.InitializeOptionsTable()
    local tmp = {};
    for _, v in pairs(Logger.LogLevels) do
        table.insert(tmp, {option = v.name, log_level = v.name});
    end
    Logger.options_tbl = {
        keys = {
            option = "option",
            log_level = "log_level",
        },
        tbl = WBT.Util.MultiKeyTable:New(tmp),
    };
end

function Logger.Initialize()
    Logger.InitializeOptionsTable();
end

function Logger.PrintLogLevelHelp()
    WBT:Print("Valid <level> values:");
    for k in pairs(Logger.LogLevels) do
        WBT:Print("  " .. k:lower());
    end
end

-- @param level_name    Log level given as string.
function Logger.SetLogLevel(level_name)
    if not level_name then
        Logger.PrintLogLevelHelp();
        return;
    end

    -- Make sure input starts with uppercase and rest is lowercase to match
    -- table keys.
    level_name = level_name:sub(1,1):upper() .. level_name:sub(2,level_name:len()):lower();

    local log_level = Logger.LogLevels[level_name];
    if log_level then
        WBT:Print("Setting log level to: " .. Util.ColoredString(log_level.color, log_level.name));
        WBT.db.global.log_level = level_name;
    else
        WBT:Print("Requested log level '" .. level_name .. "' doesn't exist.");
    end
end

-- @param varargs   A single table containing a list of strings, or varargs of
--                  strings.
function Logger.Log(log_level, ...)
    if Logger.LogLevels[WBT.db.global.log_level].value < log_level.value then
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

function Logger.Info(...)
    Logger.Log(Logger.LogLevels.Info, ...);
end

--------------------------------------------------------------------------------

-- The frames that handle events. Used as an access point for testing.
WBT.EventHandlerFrames = {
    boss_death_frame                = nil,
    boss_combat_frame               = nil,
    request_parser                  = nil,
    timer_parser                    = nil,
    shard_detection_frame           = nil,
    shard_detection_restarter_frame = nil,
    gui_visibility_frame            = nil,
}


local g_gui = {};
local g_kill_infos = {};

-- The shard id that the player currently is at. Intended only for highlighting
-- of timers in GUI.
local g_current_shard_id;

local CHANNEL_ANNOUNCE = "SAY";
local SERVER_DEATH_TIME_PREFIX = "WorldBossTimers:";
local CHAT_MESSAGE_TIMER_REQUEST = "Could you please share WorldBossTimers kill data?";

WBT.defaults = {
    global = {
        kill_infos = {},
        sound_type = Sound.SOUND_CLASSIC,
        connected_realms_data = {},
        -- Options:
        lock = false,
        global_gui_position = false,
        sound_enabled = true,
        assume_realm_keeps_shard = true,
        multi_realm = false,
        show_boss_zone_only = false,
        highlight = false,
        show_saved = false,
        show_realm = false,
        dev_silent = false,
        cyclic = false,
        max_num_cycles = 1,
        log_level = "Info",
        spawn_alert_sound = Sound.SOUND_KEY_BATTLE_BEGINS,
        spawn_alert_sec_before = 5,
        -- Options without matching OptionsItem:
        hide_gui = false,
    },
    char = {
        boss = {},
    },
};

--------------------------------------------------------------------------------
-- ConnectedRealmsData
--------------------------------------------------------------------------------
local ConnectedRealmsData = {};

-- Data about the connected realms that needs to be saved to DB.
function ConnectedRealmsData:New()
    local crd = {};
    crd.shard_id_per_zone = {};
    return crd;
end

function WBT.GetRealmKey()
    return table.concat(Util.GetConnectedRealms(), "_");
end
--------------------------------------------------------------------------------

function WBT.IsUnknownShard(shard_id)
    return shard_id == nil or shard_id == KillInfo.UNKNOWN_SHARD;
end

-- Getter for access via other modules.
function WBT.GetCurrentShardID()
    return g_current_shard_id or KillInfo.UNKNOWN_SHARD;
end

-- Returns the last known shard id for the current realm and the given zone.
function WBT.GetSavedShardID(zone_id)
    local crd = WBT.db.global.connected_realms_data[WBT.GetRealmKey()];
    if crd == nil then
        return KillInfo.UNKNOWN_SHARD;
    end
    local shard_id = crd.shard_id_per_zone[zone_id];
    return shard_id or KillInfo.UNKNOWN_SHARD;
end

function WBT.PutSavedShardIDForZone(zone_id, shard_id)
    local crd = WBT.db.global.connected_realms_data[WBT.GetRealmKey()];
    if crd == nil then 
        crd = ConnectedRealmsData:New();
        WBT.db.global.connected_realms_data[WBT.GetRealmKey()] = crd;
    end
    crd.shard_id_per_zone[zone_id] = shard_id;
end

function WBT.PutSavedShardID(shard_id)
    WBT.PutSavedShardIDForZone(WBT.GetCurrentMapId(), shard_id)
end

function WBT.ParseShardID(unit_guid)
    local unit_type = strsplit("-", unit_guid);
    if unit_type == "Creature" or unit_type == "Vehicle" then
        local shard_id_str = select(5, strsplit("-", unit_guid));
        return tonumber(shard_id_str);
    else
        return nil;
    end
end

function WBT.HasKillInfoExpired(ki_id)
    local ki = g_kill_infos[ki_id];
    if ki and ki:IsValidVersion() then
        return ki:IsExpired();
    end

    return false;
end

function WBT.IsBoss(name)
    return Util.SetUtil.ContainsKey(BossData.GetAll(), name);
end

-- Warning: This can different result, at least during addon loading / player enter world events.
-- For example it returns the map ID for Kalimdor instead of Tanaris.
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
    return t;
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

-- Returns all the KillInfos on the current zone and current shard.
--
-- An empty table is returned if no matching KillInfo is found.
--
-- KillInfos without a known shard (i.e. acquired via another player sharing them from an
-- old version of WBT without shard data) are always included.
function WBT.KillInfosInCurrentZoneAndShard()
    local res = {};
    for _, boss in pairs(WBT.BossesInCurrentZone()) do
        -- Add KillInfo without shard, i.e. old-version-WBT:
        local ki_no_shard = g_kill_infos[KillInfo.CreateID(boss.name)];
        if ki_no_shard then
            table.insert(res, ki_no_shard);
        end

        -- Add KillInfo for current shard (or assumed current shard):
        local curr_shard_id = Options.assume_realm_keeps_shard.get()
                and WBT.GetSavedShardID(WBT.GetCurrentMapId())
                or g_current_shard_id;
        if not WBT.IsUnknownShard(curr_shard_id) then
            local ki_shard = g_kill_infos[KillInfo.CreateID(boss.name, curr_shard_id)];
            if ki_shard then
                table.insert(res, ki_shard);
            end
        end
    end
    return res;
end

function WBT.GetPlayerCoords()
    return C_Map.GetPlayerMapPosition(WBT.GetCurrentMapId(), "PLAYER"):GetXY();
end

function WBT.PlayerDistanceToBoss(boss_name)
    local x, y = WBT.GetPlayerCoords();
    local boss = BossData.Get(boss_name);
    return math.sqrt((x - boss.perimiter.origin.x)^2 + (y - boss.perimiter.origin.y)^2);
end

-- Returns true if player is within boss perimiter, which is defined as a circle
-- around spawn location.
function WBT.PlayerIsInBossPerimiter(boss_name)
    return WBT.PlayerDistanceToBoss(boss_name) < BossData.Get(boss_name).perimiter.radius;
end

-- Returns ta KillInfo for the dead boss which the player is waiting for at the current
-- position and shard, if any. Else nil.
function WBT.GetPrimaryKillInfo()
    local found = {};
    for _, ki in pairs(WBT.KillInfosInCurrentZoneAndShard()) do
        if WBT.PlayerIsInBossPerimiter(ki.boss_name) then
            table.insert(found, ki);
        end
    end
    if Util.TableLength(found) > 1 then
        Logger.Debug("More than one boss found at current position. Only using first.");
    end
    for _, ki in pairs(found) do
        if not ki:HasUnknownShard() then
            return ki;
        end
    end
    return found[1];  -- Unknown shard.
end

function WBT.InZoneAndShardForTimer(kill_info)
    return WBT.IsInZoneOfBoss(kill_info.boss_name) and kill_info:IsOnCurrentShard();
end

function WBT.GetHighlightColor(kill_info)
    local highlight = Options.highlight.get() and WBT.InZoneAndShardForTimer(kill_info);
    local color;
    if kill_info:IsExpired() then
        if highlight then
            color = Util.COLOR_YELLOW;
        else
            color = Util.COLOR_RED;
        end
    else
        if highlight then
            color = Util.COLOR_LIGHTGREEN;
        else
            color = Util.COLOR_DEFAULT;
        end
    end
    return color;
end

function WBT.GetSpawnTimeOutput(kill_info)
    local color = WBT.GetHighlightColor(kill_info);

    local text = kill_info:GetSpawnTimeAsText();
    text = Util.ColoredString(color, text);

    if Options.show_saved.get() and BossData.IsSaved(kill_info.boss_name) then
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

-- Intended to be called from clicking an interactive label.
function WBT.ResetBoss(ki_id)
    local kill_info = g_kill_infos[ki_id];

    if IsControlKeyDown() and (IsShiftKeyDown() or kill_info:IsExpired()) then
        g_kill_infos[ki_id] = nil;
        g_gui:Rebuild();
        local name = KillInfo.ParseID(ki_id).boss_name;
        Logger.Info(GetColoredBossName(name) .. " has been reset.");
    else
        local cyclic = Util.ColoredString(Util.COLOR_RED, "cyclic");
        WBT:Print("Ctrl-clicking a timer that is " .. cyclic .. " will reset it."
              .. " Ctrl-shift-clicking will reset any timer. For more info about " .. cyclic .. " mode: /wbt cyclic");
    end
end

-- TODO: Rename. Also creates some structural texts and not just the payload.
-- (The name is also parsed, but it's not conevient to be part of payload.)
local function CreatePayload(kill_info, send_data_for_parsing)
    local payload = "";
    if send_data_for_parsing then
        local shard_id_part = "";
        if kill_info:HasShardID() then
            shard_id_part = "-" .. kill_info.shard_id;
        end
        payload = " (" .. SERVER_DEATH_TIME_PREFIX .. kill_info:GetServerDeathTime() .. shard_id_part .. ")";
    end

    return payload;
end

local function CreateAnnounceMessage(kill_info, send_data_for_parsing)
    local spawn_time = kill_info:GetSpawnTimeAsText();
    local payload = CreatePayload(kill_info, send_data_for_parsing);
    local msg = kill_info.boss_name .. ": " .. spawn_time .. payload;
    return msg;
end

function WBT.AnnounceSpawnTime(kill_info, send_data_for_parsing)
    local msg = CreateAnnounceMessage(kill_info, send_data_for_parsing);
    if Options.dev_silent.get() then
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
        local ki = WBT.GetPrimaryKillInfo();
        local announced = false;
        local t_now = GetServerTime();

        if WBT.IsUnknownShard(WBT.GetCurrentShardID()) then
            Logger.Info("Can't share timers when the shard ID is unknown. Mouse over an NPC to detect it.");
            return announced;
        end
        if not ki then
            Logger.Info("No fresh timer found for current location and shard ID.");
            return announced;
        end
        if not ((t_last_announce + 1) <= t_now) then
            Logger.Info("Can only share once per second.");
            return announced;
        end

        local errors = {};
        if ki:IsSafeToShare(errors) then
            WBT.AnnounceSpawnTime(ki, true);
            t_last_announce = t_now;
            announced = true;
        else
            Logger.Info("Cannot share timer for " .. GetColoredBossName(ki.boss_name) .. ":");
            Logger.Info(errors);
            return announced;
        end

        return announced;
    end

    return AnnounceSpawnTimeIfSafe;
end

function WBT.PutOrUpdateKillInfo(name, shard_id, t_death)
    t_death = tonumber(t_death);
    local ki_id = KillInfo.CreateID(name, shard_id);
    local ki = g_kill_infos[ki_id];
    if ki then
        ki:SetNewDeath(t_death);
    else
        ki = KillInfo:New(name, t_death, shard_id);
    end

    g_kill_infos[ki_id] = ki;

    g_gui:Update();
end

local function StartDeathTrackerFrame()
    local boss_death_frame = CreateFrame("Frame", "WBT_BOSS_DEATH_FRAME");
    WBT.EventHandlerFrames.boss_death_frame = boss_death_frame;

    boss_death_frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED");
    boss_death_frame:SetScript("OnEvent", function(...)
            local _, eventType, _, _, _, _, _, dest_unit_guid, _ = CombatLogGetCurrentEventInfo();

            -- Convert to English name from GUID, to make it work for
            -- localization.
            local name = BossData.NameFromUnitGuid(dest_unit_guid, WBT.GetCurrentMapId());
            if name == nil then
                return;
            end

            if eventType == "UNIT_DIED" then
                local shard_id = WBT.ParseShardID(dest_unit_guid);
                WBT.PutOrUpdateKillInfo(name, shard_id, GetServerTime());
                RequestRaidInfo(); -- Updates which bosses are saved
                g_gui:Update();
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

local function StartCombatScannerFrame()
    local boss_combat_frame = CreateFrame("Frame", "WBT_BOSS_COMBAT_FRAME");
    WBT.EventHandlerFrames.boss_combat_frame = boss_combat_frame;

    local time_out = 60*2; -- Old expansion world bosses SHOULD die in this time.
    boss_combat_frame.t_next = 0;

    function ScanWorldBossCombat(...)
		local dest_unit_guid = select(8, CombatLogGetCurrentEventInfo());

        -- Convert to English name from GUID, to make it work for
        -- localization.
        local name = BossData.NameFromUnitGuid(dest_unit_guid, WBT.GetCurrentMapId());
        if name == nil then
            return;
        end

        local t = GetServerTime();
        if WBT.IsBoss(name) and t > boss_combat_frame.t_next then
            WBT:Print(GetColoredBossName(name) .. " is now engaged in combat!");
            PlaySoundAlertBossCombat(name);
            FlashClientIcon();
            boss_combat_frame.t_next = t + time_out;
        end
    end

    boss_combat_frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED");
    boss_combat_frame:SetScript("OnEvent", ScanWorldBossCombat);
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
    WBT:Print("Resetting all timers.");
    for k, _ in pairs(g_kill_infos) do
        g_kill_infos[k] = nil;
    end
    g_gui:Rebuild();
end

local function StartShardDetectionHandler()
    WBT.EventHandlerFrames.shard_detection_frame = CreateFrame("Frame", "WBT_SHARD_DETECTION_FRAME");
    local f_detect_shard = WBT.EventHandlerFrames.shard_detection_frame;
    function f_detect_shard:RegisterEvents()
        -- NOTE: This could be improved to also look in combat log, but
        -- doesn't really feel worth adding right now.
        self:RegisterEvent("PLAYER_TARGET_CHANGED");
        self:RegisterEvent("UPDATE_MOUSEOVER_UNIT");
    end
    function f_detect_shard:UnregisterEvents()
        self:UnregisterEvent("PLAYER_TARGET_CHANGED");
        self:UnregisterEvent("UPDATE_MOUSEOVER_UNIT");
    end

    -- Handler for detecting the current shard id.
    function f_detect_shard:Handler(event, ...)
        local unit = "target";
        if event == "UPDATE_MOUSEOVER_UNIT" then
            unit = "mouseover";
        end
        if not UnitExists(unit) then
            return;
        end
        local guid = UnitGUID(unit);
        local unit_type = strsplit("-", guid);
        if unit_type == "Creature" or unit_type == "Vehicle" then
            g_current_shard_id = WBT.ParseShardID(guid);
            WBT.PutSavedShardID(g_current_shard_id);
            Logger.Debug("[ShardDetection]: New shard ID detected:", g_current_shard_id);
            g_gui:Update(WBT.UpdateEvents.SHARD_DETECTED);
            self:UnregisterEvents();
        end
    end
    f_detect_shard:RegisterEvents();
    f_detect_shard:SetScript("OnEvent", f_detect_shard.Handler);

    -- Handler for refreshing the shard id.
    local f_restart = CreateFrame("Frame", "WBT_SHARD_DETECTION_RESTARTER_FRAME");
    WBT.EventHandlerFrames.shard_detection_restarter_frame = f_restart;
    f_restart.delay = 3;  -- Having it as a var allows changing it while testing.
    function f_restart:Handler(...)
        g_current_shard_id = nil;
        g_gui:Update();
        Logger.Debug("[ShardDetection]: Possibly shard change. Shard ID invalidated.");

        -- Wait a while before starting to detect the new shard. When phasing to a new shard it will still
        -- take a while for mobs to despawn in the old shard. These will still give the (incorrect) old shard
        -- id.
        C_Timer.After(self.delay, function(...)  -- Phasing time seems to be like ~1 sec, so 3 sec should often be OK.
            f_detect_shard:RegisterEvents();
        end);
    end
    f_restart:RegisterEvent("ZONE_CHANGED_NEW_AREA");
    f_restart:RegisterEvent("SCENARIO_UPDATE");  -- Seems to fire when you swap shard due to joining a group.
    f_restart:SetScript("OnEvent", f_restart.Handler);
end

local function StartVisibilityHandler()
    local f = CreateFrame("Frame", "WBT_GUI_VISIBILITY_FRAME");
    WBT.EventHandlerFrames.gui_visibility_frame = f;
    f:RegisterEvent("ZONE_CHANGED_NEW_AREA");
    f:SetScript("OnEvent",
        function(...)
            g_gui:Update();
        end
    );
end

local function StartChatParser()

    local function PlayerSentMessage(sender)
        -- Since \b and alike doesnt exist: use "frontier pattern": %f[%A]
        return string.match(sender, GetUnitName("player") .. "%f[%A]") ~= nil;
    end

    local function InitRequestParser()
        local request_parser = CreateFrame("Frame", "WBT_REQUEST_PARSER_FRAME");
        WBT.EventHandlerFrames.request_parser = request_parser;
        local answered_requesters = {};
        request_parser:RegisterEvent("CHAT_MSG_SAY");
        request_parser:SetScript("OnEvent",
            function(self, event, msg, sender)
                if event == "CHAT_MSG_SAY" 
                        and msg == CHAT_MESSAGE_TIMER_REQUEST
                        and not Util.SetUtil.ContainsKey(answered_requesters, sender)
                        and not PlayerSentMessage(sender) then

                    if WBT.InBossZone() then
                        local ki = WBT.GetPrimaryKillInfo();
                        if ki and ki:IsSafeToShare({}) then
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

    local function InitSharedTimersParser()
        local timer_parser = CreateFrame("Frame", "WBT_TIMER_PARSER_FRAME");
        WBT.EventHandlerFrames.timer_parser = timer_parser;

        timer_parser:RegisterEvent("CHAT_MSG_SAY");
        timer_parser:SetScript("OnEvent",
            function(self, event, msg, sender)
                if event == "CHAT_MSG_SAY" then
                    if PlayerSentMessage(sender) then
                        return;
                    elseif string.match(msg, SERVER_DEATH_TIME_PREFIX) ~= nil then
                        -- NOTE: The name may contain dots and spaces, e.g. 'A. Harvester'.
                        local name, data = string.match(msg,
                                "[^A-Z]*([A-Z][A-Za-z%s\\.]+)[^\\(]*" ..  -- The name and any potential {rt8} from old versions.
                                "%(" .. SERVER_DEATH_TIME_PREFIX .. "([%w-\\-]+)" .. "%)");  -- The data/payload.
                        if not data then
                            Logger.Debug("[Parser]: Failed to parse timer. Unknown format.");
                            return;
                        end

                        -- Missing shard_id (as a result of sharing from old versions of WBT) is OK. This will
                        -- result in 'nil', which KillInfo must handle.
                        local t_death, shard_id = strsplit("-", data);
                        t_death  = tonumber(t_death)
                        shard_id = tonumber(shard_id)
                        local ki_id = KillInfo.CreateID(name, shard_id);

                        if not WBT.IsBoss(name) then
                            Logger.Debug("[Parser]: Failed to parse timer. Unknown boss name:", name);
                            return;
                        elseif WBT.HasKillInfoExpired(ki_id) then
                            Logger.Debug("[Parser]: Ignoring shared timer. Player already has fresh timer.");
                            return;
                        else
                            WBT.PutOrUpdateKillInfo(name, shard_id, t_death);
                            WBT:Print("Received " .. GetColoredBossName(name) .. " timer from: " .. sender);
                        end
                    end
                end
            end
        );
    end

    InitRequestParser();
    InitSharedTimersParser();
end

local function DeserializeKillInfos()
    for name, serialized in pairs(WBT.db.global.kill_infos) do
        g_kill_infos[name] = KillInfo:Deserialize(serialized);
    end
end

-- Step1 is performed before deserialization and looks just at the ID.
local function FilterValidKillInfosStep1()
    -- Perform filtering in two steps to avoid what I guess would
    -- be some kind of "ConcurrentModificationException".

    -- Find invalid:
    local invalid = {};
    for id, ki in pairs(WBT.db.global.kill_infos) do
        if not KillInfo.IsValidID(id) then
            invalid[id] = ki;
        end
    end

    -- Remove invalid:
    for id, ki in pairs(invalid) do
        Logger.Debug("[PreDeserialize]: Removing invalid KI with ID: " .. id);
        WBT.db.global.kill_infos[id] = nil;
    end
end

-- Step2 is performed after deserialization and checks the internal data.
local function FilterValidKillInfosStep2()
    -- Find invalid.
    local invalid = {};
    for id, ki in pairs(g_kill_infos) do
        if not ki:IsValidVersion() then
            table.insert(invalid, id);
        end
    end

    -- Remove invalid.
    for _, id in pairs(invalid) do
        Logger.Debug("[PostDeserialize]: Removing invalid KI with ID: " .. id);
        WBT.db.global.kill_infos[id] = nil;
    end
end

local function StartKillInfoManager()
    WBT.kill_info_manager = CreateFrame("Frame", "WBT_KILL_INFO_MANAGER_FRAME");
    WBT.kill_info_manager.since_update = 0;
    local t_update = 1;
    WBT.kill_info_manager:SetScript("OnUpdate", function(self, elapsed)
            self.since_update = self.since_update + elapsed;
            if (self.since_update > t_update) then
                for _, kill_info in pairs(g_kill_infos) do
                    if kill_info:ShouldAutoAnnounce() then
                        -- WBT.AnnounceSpawnTime(kill_info, true); DISABLED: broken in 8.2.5
                        -- TODO: Consider if here should be something else
                    end

                    if kill_info:ShouldRespawnAlertPlayNow(Options.spawn_alert_sec_before.get()) then
                        FlashClientIcon();
                        PlaySoundAlertSpawn();
                    end
                end

                g_gui:Update();

                self.since_update = 0;
            end
        end);
end

function WBT.AceAddon:OnEnable()
    GUI.Init();

	WBT.db = LibStub("AceDB-3.0"):New("WorldBossTimersDB", WBT.defaults);

    -- FIXME:
    -- What is the Com code doing here if it's not used? I can't tell from the code here whether
    -- it's actually disabled or not.
    --
    LibStub("AceComm-3.0"):Embed(Com);
    Com:Init(); -- Must init after db.
    if Com.ShouldRevertRequestMode() then
        Com.LeaveRequestMode();
    end
    -- Note that Com is currently not used, since it only works for
    -- connected realms.
    Com:RegisterComm(Com.PREF_SR, Com.OnCommReceivedSR);
    Com:RegisterComm(Com.PREF_RR, Com.OnCommReceivedRR);

    WBT.Functions.AnnounceTimerInChat = GetSafeSpawnAnnouncerWithCooldown();

    GUI.SetupAceGUI();

    local AceConfig = LibStub("AceConfig-3.0");

    Logger.Initialize();
    Options.Initialize();
    AceConfig:RegisterOptionsTable(WBT.addon_name, Options.optionsTable, {});
    WBT.AceConfigDialog = LibStub("AceConfigDialog-3.0");
    WBT.AceConfigDialog:AddToBlizOptions(WBT.addon_name, WBT.addon_name, nil);

    g_gui = GUI:New();

    -- Initialize g_kill_infos:
    g_kill_infos = WBT.db.global.kill_infos;  -- Alias to make code more readable.
    FilterValidKillInfosStep1();
    DeserializeKillInfos();
    FilterValidKillInfosStep2();

    StartShardDetectionHandler();
    StartDeathTrackerFrame();
    StartCombatScannerFrame();
    StartKillInfoManager();
    StartVisibilityHandler();
    StartChatParser();

    self:RegisterChatCommand("wbt", Options.SlashHandler);
    self:RegisterChatCommand("worldbosstimers", Options.SlashHandler);
end

function WBT.AceAddon:OnDisable()
end

--@do-not-package@

--------------------------------------------------------------------------------
-- Dev
--------------------------------------------------------------------------------

WBT = WBT;  -- Make global when developing

WBT.Dev = {};
local Dev = WBT.Dev;

function Dev.PrintError(...)
    local text = "";
    for n=1, select('#', ...) do
      text = text .. " " .. select(n, ...);
    end
    text = Util.strtrim(text);
    text = Util.ColoredString(Util.COLOR_RED, text);
    WBT:Print(text);
end

-- Run this when standing at boss location to get a dump of what needs to be put
-- in BossData.
function Dev.PrettyPrintLocation()
   local map_id = WBT.GetCurrentMapId();
   local x, y = WBT.GetPlayerCoords();
   -- Number of decimals is arbitrarily chosen.
   print(string.format([[
        map_id = %d,
        perimiter = {
            origin = {
                x = %.8f,
                y = %.8f,
            },
            radius = TODO_MANUALLY,
        },
   ]], map_id, x, y));
end

-- Run this to check how far the player is from a boss location as defined in
-- BossData.
function Dev.PrintPlayerDistanceToBoss(boss_name)
    if not boss_name then
        Dev.PrintError("Invalid argument: nil");
        return;
    end
    if not WBT.IsBoss(boss_name) then
        Dev.PrintError("Invalid argument. Not a boss: " .. boss_name);
        return;
    end
    if not WBT.IsInZoneOfBoss(boss_name) then
        Dev.PrintError("Not in correct zone for " .. boss_name);
        return;
    end
    print(WBT.PlayerDistanceToBoss(boss_name));
end

-- Useful for examining current state of backend.
function Dev.PrintAllKillInfos()
    Logger.Debug("Printing all KI:s");
    for id, ki in pairs(g_kill_infos) do
        print(id);
        ki:Print("  ");
    end
end

-- Useful to stop getting lua errors so the stack trace can be examined without
-- getting refreshed all the time.
function Dev.StopGUI()
    WBT.kill_info_manager:SetScript("OnUpdate", nil);
end

--------------------------------------------------------------------------------

--@end-do-not-package@

return WBT;