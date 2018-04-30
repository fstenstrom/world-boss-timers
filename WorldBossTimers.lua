-- ----------------------------------------------------------------------------
--  A persistent timer for World Bosses.
-- ----------------------------------------------------------------------------

local _, L = ...;

WBT = LibStub("AceAddon-3.0"):NewAddon("WBT", "AceConsole-3.0");

local gui;

local defaults = {
    global = {
        boss = {},
        gui = nil,
    },
    char = {
        boss = {},
    },
};


local BASE_COLOR = "|cffffffff";
local INDENT = "--";
local MAX_RESPAWN_TIME = 15*60 - 1; -- Minus 1, since they tend to spawn after 14:58.
--local MAX_RESPAWN_TIME = 50 - 1; -- Minus 1, since they tend to spawn after 14:58.
local SOUND_DIR = "Interface\\AddOns\\!WorldBossTimer\\resources\\sound\\"

local bosses = {
    ["Oondasta"] = {
        name = "Oondasta",
        color = "|cff21ffa3",
        zone = "Isle of Giants",
        soundfile = SOUND_DIR .. "oondasta3.mp3",
    },
    ["Rukhmar"] = {
        name = "Rukhmar",
        color = "|cfffa6e06",
        zone = "Spires of Arak",
        soundfile = SOUND_DIR .. "rukhmar1.mp3",
    },
    ["Vale Moth"] = {
        name = "Vale Moth",
        color = "|cff1f3d4a",
        zone = "Azuremyst Isle",
        soundfile = SOUND_DIR .. "vale_moth1.mp3",
    },
    ["Grellkin"] = {
        name = "Grellkin",
        color = "|cffffff00",
        zone = "Shadowglen",
        soundfile = SOUND_DIR .. "grellkin2.mp3",
    },
    ["Young Nightsaber"] = {
        name = "Young Nightsaber",
        color = "|cffff3d4a",
        zone =  "Shadowglen",
        soundfile = SOUND_DIR .. "vale_moth1.mp3",
    },
}

local function getColoredBossName(name)
    return bosses[name].color .. bosses[name].name .. BASE_COLOR;
end

local function setContainsKey(set, key)
    return set[key] ~= nil;
end

local function isBoss(name)
    return setContainsKey(bosses, name);
end

local function setDeathTime(time, name)
    if WBT.db.global.boss[name] == nil then
        local boss = {};
        WBT.db.global.boss[name] = boss;
    end
    WBT.db.global.boss[name].t_death = time;
end

local function killUpdateFrame(frame)
    frame:SetScript("OnUpdate", nil);
end

local function formatTimeSeconds(seconds)
    local mins = math.floor(seconds / 60);
    local secs = math.floor(seconds % 60);
    if mins > 0 then
        return mins .. "m " .. secs .. "s";
    else
        return secs .. "s";
    end
end

local function getSpawnTimeSec(name)
    boss = WBT.db.global.boss[name]
    if boss ~= nil then
        return boss.t_death + MAX_RESPAWN_TIME - GetServerTime();
    end
end

local function getSpawnTime(name)
    local spawnTimeSec = getSpawnTimeSec(name);
    if spawnTimeSec == nil or spawnTimeSec < 0 then
        return -1;
    end
    return formatTimeSeconds(spawnTimeSec);
end

local function isDead(name)
    if WBT.db.global.boss[name] == nil then
        return false;
    end
    return getSpawnTimeSec(name) >= 0;
end

local function startWorldBossDeathTimer(...)

    local function hasRespawned(name)
        local t_death = WBT.db.global.boss[name].t_death;
        local t_now = GetServerTime();
        return (t_now - t_death > MAX_RESPAWN_TIME);
    end

    local function startTimer(boss, time, freq, text)
        -- Always kill the previous frame and start a new one.
        if boss.timer ~= nil then
            boss.timer.kill = true;
        end
        boss.timer = CreateFrame("Frame");
        boss.timer.kill = false;

        local until_time = GetServerTime() + time;
        local UpdateInterval = freq;
        boss.timer:SetScript("OnUpdate", function(self, elapsed)
                if self.TimeSinceLastUpdate == nil then 
                    self.TimeSinceLastUpdate = 0;
                end
                self.TimeSinceLastUpdate = self.TimeSinceLastUpdate + elapsed; 	

                if (self.TimeSinceLastUpdate > UpdateInterval) then
                    self.remaining_time = until_time - GetServerTime();
                    if self.remaining_time < 0 or self.kill then
                        FlashClientIcon();
                        killUpdateFrame(self);
                    end

                    if gui ~= nil then
                        gui:update();
                    end
                    self.TimeSinceLastUpdate = 0;
                end
            end);
        return timer;
    end

    for _, name in ipairs({...}) do -- To iterate varargs, note that they have to be in a table. They will be expanded otherwise.
        if WBT.db.global.boss[name] and not hasRespawned(name) then
            local timer_duration = getSpawnTimeSec(name);
            startTimer(WBT.db.global.boss[name], timer_duration, 1, bosses[name].color .. name .. BASE_COLOR .. ": ");
        end
    end
end
    
local function registerWorldBossDeaths()
    local boss_death_frame = CreateFrame("Frame");
    boss_death_frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED");
    boss_death_frame:SetScript("OnEvent", function(event, ...)
             local timestamp, type, hideCaster, sourceGUID, sourceName, sourceFlags, sourceFlags2, destGUID, destName, destFlags, destFlags2 = select(2, ...);
             if type == "UNIT_DIED" and isBoss(destName) then 
                 setDeathTime(GetServerTime(), destName); -- Don't use timestamp from varags. It's not synchronized with server time.
                 startWorldBossDeathTimer(destName);
             end
        end); 
end

local function scanWorldBossCombat() 
    local boss_combat_frame = CreateFrame("Frame");
    boss_combat_frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED");

    local time_out = 60*2; -- Legacy world bosses SHOULD die in this time.
    boss_combat_frame.t_next = 0;

    function boss_combat_frame:doScanWorldBossCombat(event, ...) 
        -- NOTE: I don't know why registerWorldBossDeaths gets one extra input arg in varags. Seems to be 'event'.
        local timestamp, type, hideCaster, sourceGUID, sourceName, sourceFlags, sourceFlags2, destGUID, destName, destFlags, destFlags2 = select(1, ...);

        local t = GetServerTime();

        if isBoss(destName) and t > self.t_next then
            WBT:Print(getColoredBossName(destName) .. " is now engaged in combat!"); 
            local soundfile = bosses[destName].soundfile;
            PlaySoundFile(soundfile, "Master");
            FlashClientIcon();
            self.t_next = t + time_out;
        end
    end

    boss_combat_frame:SetScript("OnEvent", boss_combat_frame.doScanWorldBossCombat);
end

function WBT:OnInitialize()
end

local function getBossNames()
    local boss_names = {};
    local i = 1; -- Don't start on index = 0... >-<
    for name, _ in pairs(bosses) do
        boss_names[i] = name;
        i = i + 1;
    end
    
    return boss_names;
end

local function printKilledBosses()
    WBT:Print("Tracked world bosses killed:");

    local none_killed_text = "None";
    local num_saved_world_bosses = GetNumSavedWorldBosses();
    if num_saved_world_bosses == 0 then
        WBT:Print(none_killed_text);
    else
        local none_killed = true;
        for i=1, num_saved_world_bosses do
            local name = GetSavedWorldBossInfo(i);
            if isBoss(name) then
                none_killed = false;
                WBT:Print(getColoredBossName(name))
            end
        end
        if none_killed then
            WBT:Print(none_killed_text);
        end
    end
end

local function announceSpawnTime(currentZoneOnly)

    currentZoneOnly = string.lower(currentZoneOnly);

    if currentZoneOnly == "0" or currentZoneOnly == "false" or currentZoneOnly == "all" then
        currentZoneOnly = false;
    end

    local current_zone = GetZoneText();
    local spawn_timers = {};
    local entries = 0; -- No way to get size of table :(
    for name, boss in pairs(bosses) do
        if (not currentZoneOnly) or current_zone == boss.zone then
            if isDead(name) then
                spawn_timers[name] = getSpawnTime(name);
                entries = entries + 1;
            end
        end
    end

    if entries > 0 then
        local channel = "SAY";
        SendChatMessage("Bosses spawn in ...", channel, nil, nil);
        local SKULL = "{skull}";
        for name, spawn_time in pairs(spawn_timers) do
            local msg = SKULL .. name .. SKULL .. ": " .. spawn_time;
            SendChatMessage(msg, channel, nil, nil);
        end
    else
        WBT:Print("No spawn timers registered");
    end
end


local function initGUI()

    local AceGUI = LibStub("AceGUI-3.0"); -- Need to create AceGUI 'OnInit or OnEnabled' 
    gui = AceGUI:Create("Window");

    gui:SetWidth(200);
    gui:SetHeight(100);
    gui:SetCallback("OnClose",function(widget) AceGUI:Release(widget) end);
    gui:SetTitle("World Boss Timer");
    gui:SetLayout("List");
    gui:EnableResize(false);
    gui.frame:SetFrameStrata("LOW");

    function gui:update()
        self:ReleaseChildren();

        for name, boss in pairs(WBT.db.global.boss) do
            if isDead(name) then
                local label = AceGUI:Create("InteractiveLabel");
                label:SetWidth(170);
                label:SetText(getColoredBossName(name) .. ": " .. getSpawnTime(name));
                label:SetCallback("OnClick", function() WBT:Print(name) end);
                -- Add the button to the container
                self:AddChild(label);
                --WBT:Print(label:IsShown());
            end
        end
    end

    function gui:initPosition()
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

    local function recordGUIPositioning()
        local function saveGuiPoint()
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
        hooksecurefunc(gui.frame, "StopMovingOrSizing", saveGuiPoint);
    end

    gui:update();
    
    gui:initPosition();

    gui:Show();

    recordGUIPositioning();
end

local function reset()
    WBT:Print("Reseting all kill info.");
    for k, v in pairs(WBT.db.global.boss) do
        WBT.db.global.boss[k].timer.kill = true;
        WBT.db.global.boss[k] = nil;
    end
end

local function ShowGUI()
    if gui ~= nil then
        gui:Hide();
        gui = nil;
    end
    initGUI();
end

local function HideGUI()
    gui:Hide();
    gui = nil;
end

local function slashHandler(input)

    -- print(input);
    -- input = input:trim();
    arg1, arg2 = strsplit(" ", input);
    -- print(arg1, arg2);
    
    if arg1 == "hide" then
        HideGUI();
    elseif arg1 == "show" then
        ShowGUI();
    elseif arg1 == "ann" or arg1 == "a" or arg1 == "announce" or arg1 == "yell" or arg1 == "tell" then
        if arg2 == nil then
            input = "true";
        end
        announceSpawnTime(input);
    elseif arg1 == "r" or arg1 == "reset" then
        reset();
    elseif arg1 == "s" or arg1 == "saved" or arg1 == "save" then
        printKilledBosses();
    else
        WBT:Print("How to use: /wbt <arg1> <arg2>");
        WBT:Print("arg1: \'r\' --> resets all kill info.");
        WBT:Print("arg1: \'s\' --> prints your saved bosses.");
        WBT:Print("arg1: \'a\' --> announces timers for boss in zone (and all if arg2 == \'all\').");
        WBT:Print("arg1: \'show\' --> shows the timers frame.");
        WBT:Print("arg1: \'hide\' --> hides the timers frame.");
    end

end

function WBT:OnEnable()
	WBT.db = LibStub("AceDB-3.0"):New("WorldBossTimersDB", defaults);
    -- self.db.global = defaults.global; -- Resets the global profile in case I mess up the table
    -- /run for k, v in pairs(WBT.db.global) do WBT.db.global[k] = nil end -- Also resets global profile, but from in-game

    registerWorldBossDeaths(); -- Todo: make sure this can't be called twice in same session
    startWorldBossDeathTimer(unpack(getBossNames()));
    scanWorldBossCombat();

    initGUI();

    self:RegisterChatCommand("wbt", slashHandler);
    self:RegisterChatCommand("worldbosstimers", slashHandler);

end

function WBT:OnDisable()
end

