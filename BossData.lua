-- ----------------------------------------------------------------------------
--  A persistent timer for World Bosses.
-- ----------------------------------------------------------------------------

-- addonName, addonTable = ...;
local _, WBT = ...;

local Util = WBT.Util;
local Sound = WBT.Sound;

local BossData = {};
WBT.BossData = BossData;

local function MinToSec(min)
    return min * 60;
end

local MAX_RESPAWN = MinToSec(15) - 1; -- Minus 1, since they tend to spawn after 14:59.
-- Conservative guesses. Actual values are not known.
local MIN_RESPAWN_SHA = MinToSec(10);
local MAX_RESPAWN_SHA = MinToSec(20);
local MIN_RESPAWN_NALAK = MIN_RESPAWN_SHA;
local MAX_RESPAWN_NALAK = MAX_RESPAWN_SHA;
local MIN_RESPAWN_HUOLON = MinToSec(30);
local MAX_RESPAWN_HUOLON = MinToSec(60);
local MIN_RESPAWN_ZANDALARI_WARBRINGER = MinToSec(30);
local MAX_RESPAWN_ZANDALARI_WARBRINGER = MinToSec(60);

local SOUND_DIR = "Interface/AddOns/WorldBossTimers/resources/sound/";


local function IsSavedWorldBoss(id_wb)
    local n_saved = GetNumSavedWorldBosses();
    for i=1, n_saved do
        local _, id = GetSavedWorldBossInfo(i);
        if id == id_wb then
            return true;
        end
    end
    return false;
end

local function IsSavedDaily(questId)
    return C_QuestLog.IsQuestFlaggedCompleted(questId);
end

local function NeverSaved()
    return false;
end

local tracked_bosses = {
    ["Oondasta"] = {
        name = "Oondasta",
        color = "|cff21ffa3",
        map_id = 507,
        ids = {69161},
        is_saved_fcn = function() return IsSavedWorldBoss(4); end,
        soundfile = SOUND_DIR .. "oondasta3.mp3",
        min_respawn = MAX_RESPAWN,
        max_respawn = MAX_RESPAWN,
        random_spawn_time = false,
        auto_announce = true,
    },
    ["Rukhmar"] = {
        name = "Rukhmar",
        color = "|cfffa6e06",
        map_id = 542,
        ids = {83746},
        is_saved_fcn = function() return IsSavedWorldBoss(9); end,
        soundfile = SOUND_DIR .. "rukhmar1.mp3",
        min_respawn = MAX_RESPAWN,
        max_respawn = MAX_RESPAWN,
        random_spawn_time = false,
        auto_announce = true,
    },
    ["Galleon"] = {
        name = "Galleon",
        color = "|cffc1f973",
        map_id = 376,
        ids = {62346},
        is_saved_fcn = function() return IsSavedWorldBoss(2); end,
        soundfile = Sound.SOUND_FILE_DEFAULT,
        min_respawn = MAX_RESPAWN,
        max_respawn = MAX_RESPAWN,
        random_spawn_time = false,
        auto_announce = true,
    },
    ["Nalak"] = {
        name = "Nalak",
        color = "|cff0081cc",
        map_id = 504,
        ids = {69099},
        is_saved_fcn = function() return IsSavedWorldBoss(3); end,
        soundfile = Sound.SOUND_FILE_DEFAULT,
        min_respawn = MIN_RESPAWN_NALAK,
        max_respawn = MAX_RESPAWN_NALAK,
        random_spawn_time = true,
        auto_announce = true,
    },
    ["Sha of Anger"] = {
        name = "Sha of Anger",
        color = "|cff8a1a9f",
        map_id = 379,
        ids = {60491},
        is_saved_fcn = function() return IsSavedWorldBoss(1); end,
        soundfile = Sound.SOUND_FILE_DEFAULT,
        min_respawn = MIN_RESPAWN_SHA,
        max_respawn = MAX_RESPAWN_SHA,
        random_spawn_time = true,
        auto_announce = true,
    },
    ["Huolon"] = {
        name = "Huolon",
        color = "|cfff7f713",
        map_id = 554,
        ids = {73167},
        is_saved_fcn = NeverSaved,
        soundfile = Sound.SOUND_FILE_DEFAULT,
        min_respawn = MIN_RESPAWN_HUOLON,
        max_respawn = MAX_RESPAWN_HUOLON,
        random_spawn_time = true,
        auto_announce = true,
    },
    ["Rustfeather"] = {
        name = "Rustfeather",
        color = "|cffffe17d",
        map_id = 1462,
        ids = {152182},
        is_saved_fcn = function() return IsSavedDaily(55811); end,
        soundfile = Sound.SOUND_FILE_DEFAULT,
        min_respawn = MinToSec(15),
        max_respawn = MinToSec(45),
        random_spawn_time = true,
        auto_announce = true,
    },
    ["A. Harvester"] = {
        name = "A. Harvester", -- Shortened to keep GUI text one line.
        color = "|cffe08748",
        map_id = 1462,
        ids = {151934},
        is_saved_fcn = function() return IsSavedDaily(55512); end,
        soundfile = Sound.SOUND_FILE_DEFAULT,
        min_respawn = MinToSec(15),
        max_respawn = MinToSec(45),
        random_spawn_time = true,
        auto_announce = true,
    },
    --@do-not-package@
    --[[
    -- Dummy.
    ["Vale Moth"] = {
        name = "Vale Moth",
        color = "|cff1f3d4a",
        map_id = 97,
        ids = {16520},
        is_saved_fcn = NeverSaved,
        soundfile = SOUND_DIR .. "vale_moth1.mp3",
        min_respawn = MIN_RESPAWN_SHA,
        max_respawn = MAX_RESPAWN_SHA,
        random_spawn_time = false,
        auto_announce = true,
    },
    -- Dummy.
    ]]--
    ["Grellkin"] = {
        name = "Grellkin",
        color = "|cffffff00",
        map_id = 460,
        ids = {1989},
        is_saved_fcn = NeverSaved,
        soundfile = SOUND_DIR .. "grellkin2.mp3",
        min_respawn = MIN_RESPAWN_SHA,
        max_respawn = MAX_RESPAWN_SHA,
        random_spawn_time = true,
        auto_announce = true,
    },
    --[[
    -- Dummy.
    -- This entry won't work for everything since two mobs reside in same zone.
    ["Young Nightsaber"] = {
        name = "Young Nightsaber",
        color = "|cffff3d4a",
        zone =  "_Shadowglen",
        map_id = 460,
        ids = {2031},
        is_saved_fcn = NeverSaved,
        soundfile = SOUND_DIR .. "vale_moth1.mp3",
        min_respawn = MIN_RESPAWN_SHA,
        max_respawn = MIN_RESPAWN_SHA,
        random_spawn_time = false,
        auto_announce = true,
    },
    ]]--
    --@end-do-not-package@
}

local ZWB_STATIC_DATA = {
    {zone = "JF", map_id = 371, color = "|cff2bce7a"},
    {zone = "KW", map_id = 418, color = "|cff27b4d1"},
    {zone = "DW", map_id = 422, color = "|cff8a1a9f"},
    {zone = "KS", map_id = 379, color = "|cffeab01e"},
    {zone = "TS", map_id = 388, color = "|cff0cd370"},
};

local function ZWBName(zone)
    return "ZWB (" .. zone .. ")";
end

local function ZandalariWarbringerFromTemplate(zone, map_id, color)
    return {
        name = ZWBName(zone),
        color = color,
        map_id = map_id,
        ids = {69769, 69842, 69841},
        is_saved_fcn = NeverSaved,
        soundfile = Sound.SOUND_FILE_DEFAULT,
        min_respawn = MIN_RESPAWN_ZANDALARI_WARBRINGER,
        max_respawn = MAX_RESPAWN_ZANDALARI_WARBRINGER,
        random_spawn_time = true,
        auto_announce = false,
    };
end

local function AddZandalariWarbringers()
    for _, data in pairs(ZWB_STATIC_DATA) do
        tracked_bosses[ZWBName(data.zone)] = ZandalariWarbringerFromTemplate(data.zone, data.map_id, data.color);
    end
end

AddZandalariWarbringers();

-- END OF STATIC DATA --


function BossData.Get(name)
    return tracked_bosses[name];
end

local function GetNpcId(guid)
    local type, zero, server_id, instance_id, zone_uid, npc_id, spawn_uid = strsplit("-", guid);
    return npc_id;
end

-- Note that guid here is the GUID assigned by WoW, not from KillInfo.
function BossData.GetFromNpcGuid(guid, map_id)
    local npc_id = GetNpcId(guid);
    for _, data in pairs(tracked_bosses) do
        for _, id in pairs(data.ids) do
            if npc_id == tostring(id) and map_id == data.map_id then
                return data;
            end
        end
    end

    return nil;
end

function BossData.NameFromNpcGuid(guid, map_id)
    local data = BossData.GetFromNpcGuid(guid, map_id);
    if data then
        return data.name;
    end

    return nil;
end

function BossData.GetAll()
    return tracked_bosses;
end

function BossData.BossExists(name)
    for name2, _ in pairs(tracked_bosses) do
        if name == name2 then
            return true;
        end
    end

    return false;
end

function BossData.IsSaved(name)
    return BossData.Get(name).is_saved_fcn();
end

for name, data in pairs(tracked_bosses) do
    data.name_colored = data.color .. data.name .. Util.COLOR_DEFAULT;
end
