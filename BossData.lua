-- The constant boss data, e.g. boss location and respawn time.

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
        ids = {69161},
        is_saved_fcn = function() return IsSavedWorldBoss(4); end,
        soundfile = SOUND_DIR .. "oondasta3.mp3",
        min_respawn = MAX_RESPAWN,
        max_respawn = MAX_RESPAWN,
        random_spawn_time = false,
        auto_announce = true,
        map_id = 507,
        perimiter = {
            origin = {
                x = 0.49706578,
                y = 0.56742978,
            },
            radius = 0.07,
        },
    },
    ["Rukhmar"] = {
        name = "Rukhmar",
        color = "|cfffa6e06",
        ids = {83746},
        is_saved_fcn = function() return IsSavedWorldBoss(9); end,
        soundfile = SOUND_DIR .. "rukhmar1.mp3",
        min_respawn = MAX_RESPAWN,
        max_respawn = MAX_RESPAWN,
        random_spawn_time = false,
        auto_announce = true,
        map_id = 542,
        perimiter = {
            origin = {
                x = 0.37155128,
                y = 0.38439554,
            },
            radius = 0.04,
        },
    },
    ["Galleon"] = {
        name = "Galleon",
        color = "|cffc1f973",
        ids = {62346},
        is_saved_fcn = function() return IsSavedWorldBoss(2); end,
        soundfile = Sound.SOUND_FILE_DEFAULT,
        min_respawn = MAX_RESPAWN,
        max_respawn = MAX_RESPAWN,
        random_spawn_time = false,
        auto_announce = true,
        map_id = 376,
        perimiter = {
            origin = {
                x = 0.71155238,
                y = 0.63839519,
            },
            radius = 0.04,
        },
    },
    ["Nalak"] = {
        name = "Nalak",
        color = "|cff0081cc",
        ids = {69099},
        is_saved_fcn = function() return IsSavedWorldBoss(3); end,
        soundfile = Sound.SOUND_FILE_DEFAULT,
        min_respawn = MIN_RESPAWN_NALAK,
        max_respawn = MAX_RESPAWN_NALAK,
        random_spawn_time = true,
        auto_announce = true,
        map_id = 504,
        perimiter = {
            origin = {
                x = 0.60369474,
                y = 0.37266934,
            },
            radius = 0.04,
        },
    },
    ["Sha of Anger"] = {
        name = "Sha of Anger",
        color = "|cff8a1a9f",
        ids = {60491},
        is_saved_fcn = function() return IsSavedWorldBoss(1); end,
        soundfile = Sound.SOUND_FILE_DEFAULT,
        min_respawn = MIN_RESPAWN_SHA,
        max_respawn = MAX_RESPAWN_SHA,
        random_spawn_time = true,
        auto_announce = true,
        map_id = 379,
        perimiter = {
            origin = {
                x = 0.53787065,
                y = 0.64697766,
            },
            radius = 0.03,
        },
    },
    ["Huolon"] = {
        name = "Huolon",
        color = "|cfff7f713",
        ids = {73167},
        is_saved_fcn = NeverSaved,
        soundfile = Sound.SOUND_FILE_DEFAULT,
        min_respawn = MIN_RESPAWN_HUOLON,
        max_respawn = MAX_RESPAWN_HUOLON,
        random_spawn_time = true,
        auto_announce = true,
        map_id = 554,
        perimiter = {
            origin = {
                x = 0.66583741,
                y = 0.58253992,
            },
            radius = 0.06,
        },
    },
    ["Rustfeather"] = {
        name = "Rustfeather",
        color = "|cffffe17d",
        ids = {152182},
        is_saved_fcn = function() return IsSavedDaily(55811); end,
        soundfile = Sound.SOUND_FILE_DEFAULT,
        min_respawn = MinToSec(15),
        max_respawn = MinToSec(30),
        random_spawn_time = true,
        auto_announce = true,
        map_id = 1462,
        perimiter = {
            origin = {
                x = 0.65564358234406,
                y = 0.78932404518127,
            },
            radius = 0.05,
        },
    },
    ["A. Harvester"] = {
        name = "A. Harvester", -- Shortened to keep GUI text to one line.
        color = "|cffe08748",
        ids = {151934},
        is_saved_fcn = function() return IsSavedDaily(55512); end,
        soundfile = Sound.SOUND_FILE_DEFAULT,
        min_respawn = MinToSec(15),
        max_respawn = MinToSec(40),
        random_spawn_time = true,
        auto_announce = true,
        map_id = 1462,
        perimiter = {
            origin = {
                x = 0.52341330,
                y = 0.40851349,
            },
            radius = 0.05,
        },
    },
--  ["Soundless"] = {
--      Won't add. Very long timer and prone to zone resets. Timers will not be reliable.
-- },
    ["Rei Lun"] = {
        name = "Rei Lun",
        color = "|cff23dcfc",
        ids = {157162},
        is_saved_fcn = function() return IsSavedDaily(57346); end,
        soundfile = Sound.SOUND_FILE_DEFAULT,
        min_respawn = MinToSec(30),
        max_respawn = MinToSec(60),
        random_spawn_time = true,
        auto_announce = true,
        map_id = 1530,  -- N'Zoth Assault. Old timeline zone has different.
        perimiter = {
            origin = {
                x = 0.21920382,
                y = 0.12227475,
            },
            radius = 0.03,
        },
    },
    ["Ha-Li"] = {
        name = "Ha-Li",
        color = "|cff0394fc",
        ids = {157153},
        is_saved_fcn = function() return IsSavedDaily(57344); end,
        soundfile = Sound.SOUND_FILE_DEFAULT,
        min_respawn = MinToSec(30),
        max_respawn = MinToSec(60),
        random_spawn_time = true,
        auto_announce = true,
        map_id = 1530,
        perimiter = {
            origin = {
                x = 0.3437,
                y = 0.3828,
            },
            radius = 0.08,
        },
    },
    ["Anh-De"] = {
        name = "Anh-De",
        color = "|cfffaea75",
        ids = {157466},
        is_saved_fcn = function() return IsSavedDaily(57363); end,
        soundfile = Sound.SOUND_FILE_DEFAULT,
        min_respawn = MinToSec(30),
        max_respawn = MinToSec(60),
        random_spawn_time = true,
        auto_announce = true,
        map_id = 1530,
        perimiter = {
            origin = {
                x = 0.3389,
                y = 0.6837,
            },
            radius = 0.02,
        },
    },
    ["Houndlord Ren"] = {
        name = "Houndlord Ren",
        color = "|cfffaab34",
        ids = {157160},
        is_saved_fcn = function() return IsSavedDaily(57345); end,
        soundfile = Sound.SOUND_FILE_DEFAULT,
        min_respawn = MinToSec(30),
        max_respawn = MinToSec(60),
        random_spawn_time = true,
        auto_announce = true,
        map_id = 1530,
        perimiter = {
            origin = {
                x = 0.1310,
                y = 0.2600,
            },
            radius = 0.02,
        },
    },
    ["Corpse Eater"] = {
        name = "Corpse Eater",
        color = "|cffa884ff",
        ids = {162147},
        is_saved_fcn = function() return IsSavedDaily(58696); end,
        soundfile = Sound.SOUND_FILE_DEFAULT,
        min_respawn = MinToSec(5),
        max_respawn = MinToSec(30),
        random_spawn_time = true,
        auto_announce = true,
        map_id = 1527,
        perimiter = {
            origin = {
                x = 0.3091,
                y = 0.4967,
            },
            radius = 0.02,
        },
    },
    ["Rotfeaster"] = {
        name = "Rotfeaster",
        color = "|cffffc489",
        ids = {157146},
        is_saved_fcn = function() return IsSavedDaily(57273); end,
        soundfile = Sound.SOUND_FILE_DEFAULT,
        min_respawn = MinToSec(30),
        max_respawn = MinToSec(90),
        random_spawn_time = true,
        auto_announce = true,
        map_id = 1527,
        perimiter = {
            origin = {
                x = 0.6831,
                y = 0.3188,
            },
            radius = 0.01,
        },
    },
    ["Ishak"] = {
        name = "Ishak",  -- Ishak of the Four Winds
        color = "|cff0394fc",
        ids = {157134},
        is_saved_fcn = function() return IsSavedDaily(57259); end,
        soundfile = Sound.SOUND_FILE_DEFAULT,
        min_respawn = MinToSec(135),  -- 2h 15m
        max_respawn = MinToSec(255),  -- 4h 45m
        random_spawn_time = true,
        auto_announce = true,
        map_id = 1527,
        perimiter = {
            origin = {
                x = 0.7390,
                y = 0.8355,
            },
            radius = 0.02,
        },
    },
    ["Mal'Korak"] = {
        name = "Mal'Korak",  -- Warbringer Mak'Korak
        color = "|cff99ba4e",
        ids = {162819},
        is_saved_fcn = function() return IsSavedDaily(58889); end,
        soundfile = Sound.SOUND_FILE_DEFAULT,
        min_respawn = MinToSec(45),
        max_respawn = MinToSec(90),
        random_spawn_time = true,
        auto_announce = true,
        map_id = 1536,
        perimiter = {
            origin = {
                x = 0.3372,
                y = 0.8009,
            },
            radius = 0.01,
        },
    },
    ["Nerissa"] = {
        name = "Nerissa",  -- Nerissa Heartless
        color = "|cffbec0c2",
        ids = {162819},
        is_saved_fcn = function() return IsSavedDaily(58851); end,
        soundfile = Sound.SOUND_FILE_DEFAULT,
        min_respawn = MinToSec(45),
        max_respawn = MinToSec(90),
        random_spawn_time = true,
        auto_announce = true,
        map_id = 1536,
        perimiter = {
            origin = {
                x = 0.6605,
                y = 0.3518,
            },
            radius = 0.01,
        },
    },
--  ["Violet Mistake"] = {
--      Won't add. Not limited by respawn time, but by the time and effort it takes to spawn it.
--  },
    ["Hopecrusher"] = {
        name = "Hopecrusher",
        color = "|cfffaab34",
        ids = {166679},
        is_saved_fcn = function() return IsSavedDaily(59900); end,
        soundfile = Sound.SOUND_FILE_DEFAULT,
        min_respawn = MinToSec(60),
        max_respawn = MinToSec(60),
        random_spawn_time = false,
        auto_announce = true,
        map_id = 1525,
        perimiter = {
            origin = {
                x = 0.5197,
                y = 0.5181,
            },
            radius = 0.01,
        },
    },
    ["Famu"] = {
        name = "Famu",  -- Famu the Infinite
        color = "|cff0394fc",
        ids = {166521},
        is_saved_fcn = function() return IsSavedDaily(59869); end,
        soundfile = Sound.SOUND_FILE_DEFAULT,
        min_respawn = MinToSec(25),
        max_respawn = MinToSec(35),
        random_spawn_time = true,
        auto_announce = true,
        map_id = 1525,
        perimiter = {
            origin = {
                x = 0.6257,
                y = 0.4723,
            },
            radius = 0.01,
        },
    },
--  ["Gorged Shadehound"] = {
--      Won't add (for now). Apparently the event is bugged.
--  },
--  ["Fallen Charger"] = {
--      Won't add. TLPD-like.
--  },
--  ["Konthrogz the Obliterator"] = {
--      Won't add. Apparently the spawn time is very buggy.
--  },
--  ["Malbog"] = {
--      Won't add. Apparently short respawn of about 5 min.
--  },
    ["Reliwik"] = {
        name = "Reliwik",  -- Reliwik the Defiant
        color = "|cffe147ff",
        ids = {180160},
        is_saved_fcn = function() return IsSavedDaily(64455); end,
        soundfile = Sound.SOUND_FILE_DEFAULT,
        min_respawn = MinToSec(15),
        max_respawn = MinToSec(60),  -- This spawn seems to be bugged. Timer probably inaccurate.
        random_spawn_time = true,
        auto_announce = true,
        map_id = 1961,
        perimiter = {
            origin = {
                x = 0.5620,
                y = 0.6630,
            },
            radius = 0.02,
        },
    },
--  ["Rhuv, Gorger of Ruin"] = {
--      Won't add. Not a fixed respawn time, and shares spawn with other mobs.
--  },
--  ["Hirukon"] = {
--      Won't add. Not limited by respawn time, but by the time and effort it takes to spawn it.
--  },
--@do-not-package@
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
        perimiter = {
            origin = {
                x = 0.50000000,
                y = 0.50000000,
            },
            radius = 1.00,
        },
    },
    --[[
    -- Dummy.
    -- TODO: Add missing fields. Should work after perimiter checks.
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
    {zone = "JF", map_id = 371, color = "|cff2bce7a", perimiter = {origin = {x = 0.52551341, y = 0.18841952}, radius = 0.03}},
    {zone = "KW", map_id = 418, color = "|cff27b4d1", perimiter = {origin = {x = 0.17448401, y = 0.52911037}, radius = 0.04}},
    {zone = "DW", map_id = 422, color = "|cff8a1a9f", perimiter = {origin = {x = 0.47365963, y = 0.62041634}, radius = 0.03}},
    {zone = "KS", map_id = 379, color = "|cffeab01e", perimiter = {origin = {x = 0.75076747, y = 0.67355406}, radius = 0.03}},
    {zone = "TS", map_id = 388, color = "|cff0cd370", perimiter = {origin = {x = 0.36536807, y = 0.85731047}, radius = 0.03}},
};

local function ZWBName(zone)
    return "ZWB (" .. zone .. ")";
end

local function ZandalariWarbringerFromTemplate(zone, map_id, color, perimiter)
    return {
        name = ZWBName(zone),
        color = color,
        ids = {69769, 69842, 69841},
        is_saved_fcn = NeverSaved,
        soundfile = Sound.SOUND_FILE_DEFAULT,
        min_respawn = MIN_RESPAWN_ZANDALARI_WARBRINGER,
        max_respawn = MAX_RESPAWN_ZANDALARI_WARBRINGER,
        random_spawn_time = true,
        auto_announce = false,
        map_id = map_id,
        perimiter = perimiter,
    };
end

local function AddZandalariWarbringers()
    for _, data in pairs(ZWB_STATIC_DATA) do
        tracked_bosses[ZWBName(data.zone)] = ZandalariWarbringerFromTemplate(data.zone, data.map_id, data.color, data.perimiter);
    end
end

AddZandalariWarbringers();

-- END OF STATIC DATA --


function BossData.Get(name)
    return tracked_bosses[name];
end

function BossData.GetFromUnitGuid(guid, map_id)
    local npc_id = select(6, strsplit("-", guid));
    for _, data in pairs(tracked_bosses) do
        for _, id in pairs(data.ids) do
            if npc_id == tostring(id) and map_id == data.map_id then
                return data;
            end
        end
    end

    return nil;
end

function BossData.BossNameFromUnitGuid(guid, map_id)
    local data = BossData.GetFromUnitGuid(guid, map_id);
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

-- FIXME: This looks strange.
for name, data in pairs(tracked_bosses) do
    data.name_colored = data.color .. data.name .. Util.COLOR_DEFAULT;
end
