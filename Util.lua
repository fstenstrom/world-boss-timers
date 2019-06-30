-- ----------------------------------------------------------------------------
--  A persistent timer for World Bosses.
-- ----------------------------------------------------------------------------

-- addonName, addonTable = ...;
local _, WBT = ...;

local Util = {};
WBT.Util = Util;

Util.COLOR_DEFAULT = "|cffffffff";
Util.COLOR_RED = "|cffff0000";
Util.COLOR_GREEN = "|cff00ff00";
Util.COLOR_ORANGE = "|cffffdd1e";
Util.COLOR_LIGHTGREEN = "|cff35e059";
Util.COLOR_DARKGREEN = "|cff50c41f";
Util.COLOR_YELLOW = "|cfff2e532";

Util.Warmode = {
    DISABLED = "Normal",
    ENABLED = "Warmode",
}

function Util.WarmodeColor(realm_type)
    local color = Util.COLOR_RED;
    if realm_type == Util.Warmode.DISABLED then
        color = Util.COLOR_YELLOW;
    end
    return color;
end

-- Lua 5.2 "import" from table.pack:
function TablePack(...)
  return { n = select("#", ...), ... }
end

function Util.StringTrim(s)
return s:match("^%s*(.-)%s*$"); -- Note: '-' is lazy '*' matching.
end

function Util.MessageFromVarargs(...)
    local args = TablePack(...);
    local msg = "";
    for i=1, args.n do
        local arg = args[i];
        if arg == nil then
            msg = msg .. "nil" .. " ";
        else
            msg = msg .. args[i] .. " ";
        end
    end
    msg = Util.StringTrim(msg);
    return msg;
end

function Util.ReverseColor(color)
    local t_color_rev = { };
    t_color_rev[Util.COLOR_DEFAULT] = Util.COLOR_RED;
    t_color_rev[Util.COLOR_GREEN] = Util.COLOR_RED;
    t_color_rev[Util.COLOR_LIGHTGREEN] = Util.COLOR_RED;
    t_color_rev[Util.COLOR_DARKGREEN] = Util.COLOR_RED;
    t_color_rev[Util.COLOR_YELLOW] = Util.COLOR_LIGHTGREEN;
    t_color_rev[Util.COLOR_RED] = Util.COLOR_LIGHTGREEN;
    return t_color_rev[color] or Util.COLOR_DEFAULT;
end

function Util.ColoredString(color, ...)
    return color .. Util.MessageFromVarargs(...) .. Util.COLOR_DEFAULT;
end

function Util.TableIsEmpty(tbl)
    return next(tbl) == nil
end

function Util.SetContainsKey(set, key)
    return set[key] ~= nil;
end

-- The sets contain very few values, so for now I won't implement
-- any better algorithms here.
function Util.SetElementKey(set, value)
    for k, v in pairs(set) do
        if v == value then
            return k;
        end
    end
    return nil;
end

function Util.SetContainsValue(set, value)
    return Util.SetElementKey(set, value) and true;
end

function Util.RemoveFromSet(set, value)
    local k = Util.SetElementKey(set, value);
    if k then
        table.remove(set, k, value);
        return true;
    end
    return false;
end

function Util.FormatTimeSeconds(seconds)
    local mins = math.floor(seconds / 60);
    local secs = math.floor(seconds % 60);
    if mins > 0 then
        return mins .. "m " .. secs .. "s";
    else
        return secs .. "s";
    end
end

function Util.WarmodeStatus()
    return C_PvP.IsWarModeDesired() and Util.Warmode.ENABLED or Util.Warmode.DISABLED;
end

function Util.PlaySoundAlert(soundfile)
    if soundfile == nil or not WBT.db.global.sound_enabled then
        return;
    end

    PlaySoundFile(soundfile, "Master");
end

-- Credits: The spairs function is copied from:
-- https://stackoverflow.com/questions/15706270/sort-a-table-in-lua
-- by user "Michael Kottman"
--
-- Note: I really should use a better data structure instead,
-- such as ordered map, but this is a fast solution, and the computational
-- overhead will be small since the table is small.
function Util.spairs(t, order)
    -- collect the keys
    local keys = {}
    for k in pairs(t) do keys[#keys+1] = k end

    -- if order function given, sort by it by passing the table and keys a, b,
    -- otherwise just sort the keys
    if order then
        table.sort(keys, function(a,b) return order(t, a, b) end)
    else
        table.sort(keys)
    end

    -- return the iterator function
    local i = 0
    return function()
        i = i + 1
        if keys[i] then
            return keys[i], t[keys[i]]
        end
    end
end

-- Function content is copied from first entry at 'http://lua-users.org/wiki/StringTrim'
function Util.strtrim(s)
   return (s:gsub("^%s*(.-)%s*$", "%1"));
end

--[[
    Table with the following structure: unnamed entries, where each entry is a table.
    This table's key-value relation must be unique in respect to all other entries
    in the MultiKeyTable. Ex:
    local t = {
        { k = 1, v = 2 },
        { k = 2, v = 3 },
        { k = 1, v = 4 }, -- Invalid, because 'k = 1' is already used,
    };
]]--
Util.MultiKeyTable = {};

function Util.MultiKeyTable:New(tbl)
    local obj = {};
    obj.tbl = tbl;

    setmetatable(obj, self);
    self.__index = self;

    return obj;
end

--[[
    Returns the subtable for which 'k = v' is true.
]]--
function Util.MultiKeyTable:GetSubtbl(k, v)
    for _, subtbl in ipairs(self.tbl) do
        for k_subtbl, v_subtbl in pairs(subtbl) do
            if k_subtbl == k and v_subtbl == v then
                return subtbl;
            end
        end
    end

    return nil;
end


--[[
    Returns the values for each subtable with a key 'k' as a named table.
    The table's key and value are the same. For example: ret_val[x] = x
]]--
function Util.MultiKeyTable:GetAllSubVals(k)
    local subvals = {};
    for _, subtbl in ipairs(self.tbl) do
        local val = subtbl[k];
        if val then
            subvals[val] = val;
        end
    end

    return subvals;
end

