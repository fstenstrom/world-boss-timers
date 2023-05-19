local Util     = require("Util");
local TestUtil = require("TestUtil");

-- Test doubles and tests.

g_test_settings = {
    wbt_print = false;  -- If WBT:Print(...) should be print.
}

--------------------------------------------------------------------------------
-- Blizzard-like event framework
--------------------------------------------------------------------------------

local EventManager = {};
EventManager.frames = {};

function EventManager:Reset()
    frames = {};
end

function EventManager:FireEvent(event, ...)
    for _, frame in pairs(self.frames) do
        frame:HandleEvent(event, ...);
    end
end

function EventManager:RegisterFrame(f)
    if f.name then
        self.frames[f.name] = f;
    else
        table.insert(self.frames, f);
    end
end

local Frame = {};
function Frame:New(name)
    local f = {};
    f.name = name;  -- Can be nil.
    f.events = {};
    f.event_handler = nil;
    setmetatable(f, self);
    self.__index = self;  -- XXX: Should be f.__index = self ?
    return f;
end

function CreateFrame(_, name)
    local f = Frame:New(name);
    EventManager:RegisterFrame(f);
    return f;
end

function Frame:RegisterEvent(event)
    self.events[event] = true;
end

function Frame:UnregisterEvent(event)
    self.events[event] = nil;
end

function Frame:SetScript(triggerKind, eventHandler)
    self.trigger_kind = triggerKind;
    self.event_handler = eventHandler;
end

function Frame:HandleEvent(event, ...)
    if self.trigger_kind ~= "OnEvent" then
        -- print("Fake Frame: Only 'OnEvent' supported. My trigger kind: ", self.trigger_kind);
        return;
    end
    if self.events[event] then
        -- print(self.name)
        self:event_handler(event, ...);
        return;
    end
end

--------------------------------------------------------------------------------
-- Ace, LibStub and other 3rd party:
--------------------------------------------------------------------------------

local AceAddon = {};
function AceAddon:New()
    local o = {};
    setmetatable(o, self);
    self.__index = self;
    return o;
end
function AceAddon:RegisterChatCommand(...)
    return;
end
function AceAddon:Print(text)
    if g_test_settings.wbt_print then
        print("WBT:", text);
    end
end

function LibStub(addonName)
    local ls = {};
    function ls:NewAddon(addonName, aceModule)
        return AceAddon:New();
    end
    function ls:New(dbName, defaultDb)
        return defaultDb;
    end
    function ls:Embed(...)
        return;
    end
    function ls:AddToBlizOptions(...)
        return;
    end
    function ls:RegisterOptionsTable(addonName, optionsTable, ...)
        return;
    end
    function ls:Embed(comClass)
        function RegisterComm(...)
            return;
        end
        comClass.RegisterComm = RegisterComm;
    end
    return ls;
end

--------------------------------------------------------------------------------
-- WBT test doubles
--------------------------------------------------------------------------------

local GUI = {};
function GUI:New()
    local o = {};
    setmetatable(o, self);
    self.__index = self;
    return o;
end
function GUI.SetupAceGUI()       return; end
function GUI.Init()              return; end
function GUI:Update()            return; end
function GUI:UpdateWindowTitle() return; end


--------------------------------------------------------------------------------
-- WoW API
--------------------------------------------------------------------------------

-- Fake "world" object. Set fields as necessary before testing.
local g_game = {
    servertime = 1677434396,
    world = {
        shard_id = 44
    },
    player = {
        -- Static
        name = "Chainorth",
        realmname = "Stormreaver",
        connected_realms = {"Stormreaver", "Vashj"},
        -- Dynamic
        map_id = 507,  -- Isle of Giants
        coords = {     -- Oondasta spawn point.
            x = 0.50,
            y = 0.56
        },
    }
}

function GetUnitName(unit)
    if unit == "player" then
        return "Playerone"
    end
    return "Notplayer";
end

function UnitExists(unit)
    return unit == "mouseover";
end

function UnitGUID(unit)
    if unit == "mouseover" then
        return "Creature-field2-field3-field4-" .. tostring(g_game.world.shard_id)
    end
    error("NYI")
end

function GetRealmName()
    return g_game.player.realm_name;
end

function GetAutoCompleteRealms()
    return g_game.player.connected_realms;
end

-- XXX: Not correct, but doesn't matter right now.
function GetNormalizedRealmName()
    return g_game.player.realm_name;
end

function GetServerTime()
    return g_game.servertime;
end

local Coord = {};
function Coord:GetXY()
    return g_game.player.coords.x,
           g_game.player.coords.y;
end
C_Map = {};
function C_Map.GetPlayerMapPosition(mapId, unitname)
    return Coord;
end
function C_Map.GetBestMapForUnit(_)
    return g_game.player.map_id;
end

--------------------------------------------------------------------------------
-- WoW lua API
--------------------------------------------------------------------------------

function strsplit(sep, str)
    local t={}
    for match in string.gmatch(str, "([^"..sep.."]+)") do
        table.insert(t, match)
    end
    return table.unpack(t)
end

--------------------------------------------------------------------------------
-- Blizzard-like addon loader for WBT
--------------------------------------------------------------------------------

-- Returns an instance of WBT, and tries to perform loading in the same way
-- as Blizzard (probably) does it. (An option would be to change how module
-- imports are done, and instead import with 'require' instead of file varargs.)
local function LoadWBT()
    local addonName = "addonname_unused";
    local addonTable = {};

    -- Load in same order as in .toc file:
    assert(loadfile("Util.lua"))            (addonName, addonTable);
    assert(loadfile("Sound.lua"))           (addonName, addonTable);
    assert(loadfile("BossData.lua"))        (addonName, addonTable);
    assert(loadfile("Com.lua"))             (addonName, addonTable);
    assert(loadfile("NameplateTracker.lua"))(addonName, addonTable);
    addonTable.GUI = GUI;  -- GUI is a fake defined in this file.
    assert(loadfile("Options.lua"))         (addonName, addonTable);
    assert(loadfile("KillInfo.lua"))        (addonName, addonTable);
    local WBT = assert(loadfile("WorldBossTimers.lua"))(addonName, addonTable);
    return WBT;
end

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

function TestStrSplit()
    a, b, c = strsplit("-", "a-b1-c22");
    assert(a == "a",   a);
    assert(b == "b1",  b);
    assert(c == "c22", c);
end

local function FireDetectShard()
    EventManager:FireEvent("UPDATE_MOUSEOVER_UNIT", "mouseover");
end

local function TestSharingWithoutShardId()
    g_test_settings.wbt_print = false;
    local bossname = "Oondasta";
    EventManager:Reset();
    local WBT = LoadWBT();
    WBT.AceAddon:OnEnable();

    -- Detect current shard:
    local test_shard_id = 44;
    g_game.world.shard_id = test_shard_id;
    FireDetectShard();

    -- Get shared a timer without shard_id
    local event = "CHAT_MSG_SAY";
    local msg = TestUtil.CreateShareMsg(bossname, g_game.servertime, 9, nil);
    local sender = "Shareson";
    EventManager:FireEvent(event, msg, sender);
    local ki = WBT.GetPrimaryKillInfo();
    assert(ki:HasUnknownShard(), ki.shard_id)

    -- Get new KillInfo with shard ID. The new KillInfo should now be prioritized.
    -- Regardless of if the player's current shard id is known or not.
    local event = "CHAT_MSG_SAY";
    local msg = TestUtil.CreateShareMsg(bossname, g_game.servertime, 8, test_shard_id);
    local sender = "Sharesontwo";
    EventManager:FireEvent(event, msg, sender);
    local ki = WBT.GetPrimaryKillInfo();
    assert(ki.shard_id == 44, ki.shard_id)
end

local function TestShare(bossname, expectSuccess)
    EventManager:Reset();
    local WBT = LoadWBT();
    WBT.AceAddon:OnEnable();

    -- Detect current shard:
    g_game.world.shard_id = 44;
    FireDetectShard();

    -- Assert no timer:
    assert(Util.TableIsEmpty(WBT.db.global.kill_infos), "Incorrect setup.");

    -- Share the timer:
    local event = "CHAT_MSG_SAY";
    local msg = TestUtil.CreateShareMsg(bossname, g_game.servertime, 9, g_game.world.shard_id);
    local sender = "Shareson";
    EventManager:FireEvent(event, msg, sender);

    -- Assert parsed:
    local nTimers = Util.TableLength(WBT.db.global.kill_infos);
    local nTimersExp = expectSuccess and 1 or 0;
    assert(nTimers == nTimersExp, "Incorrect number of timers: " .. nTimers);
end

function main()
    TestStrSplit();
    TestSharingWithoutShardId();
    TestShare("Oondasta",     true);
    TestShare("Sha of Anger", true);
    TestShare("A. Harvester", true);
    TestShare("NotBoss",      false);
    TestShare("Sha of Rage",  false);
end

main()