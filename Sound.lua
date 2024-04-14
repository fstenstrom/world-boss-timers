-- Sound related constant data.

local _, WBT = ...;

local Sound = {};
WBT.Sound = Sound;

Sound.SOUND_CLASSIC = "classic";
Sound.SOUND_FANCY = "fancy";

Sound.SOUND_FILE_DEFAULT = 567275; -- Wardrums

Sound.SOUND_KEY_BATTLE_BEGINS = "battle-begins";

--[[
    How to find IDs given the filename: use 'https://wow.tools/files' to search, either with filename or fileID

    k:
        the string which is displayed in GUI
    v:
        the fileID, needed in PlaySoundFile
]]--

Sound.sound_tbl = {
    keys = {
        option = "option",
        file_id = "file_id",
    },
    tbl = WBT.Util.MultiKeyTable:New({
        { option = "DISABLED",                    file_id = nil,     },
        { option = "you-are-not-prepared",        file_id = 552503,  },
        { option = "prepare-yourselves",          file_id = 547915,  },
        { option = "alliance-bell",               file_id = 566564,  },
        { option = "alarm-clock",                 file_id = 567399,  },
        { option = Sound.SOUND_KEY_BATTLE_BEGINS, file_id = 2128648, },
        { option = "pvp-warning",                 file_id = 567505,  },
        { option = "drum-hit",                    file_id = 1487139, },
    }),
};
