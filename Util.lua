-- Utils.

-- addonName, addonTable = ...;
local _, WBT = ...;

local Util = {};

if type(WBT) == "table" then
    WBT.Util = Util;
end

Util.COLOR_DEFAULT    = "|cffffffff";
Util.COLOR_RED        = "|cffff0000";
Util.COLOR_GREEN      = "|cff00ff00";
Util.COLOR_ORANGE     = "|cffffdd1e";
Util.COLOR_LIGHTGREEN = "|cff35e059";
Util.COLOR_DARKGREEN  = "|cff50c41f";
Util.COLOR_YELLOW     = "|cfff2e532";
Util.COLOR_BLUE       = "|cff0394fc";
Util.COLOR_PURPLE     = "|cffbf00ff";


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

function Util.TableLength(tbl)
    local cnt = 0;
    for _ in pairs(tbl) do
        cnt = cnt + 1;
    end
    return cnt;
end

function Util.IsTable(obj)
    return type(obj) == "table";
end

--------------------------------------------------------------------------------
-- SetUtil
--------------------------------------------------------------------------------
Util.SetUtil = {};
local SetUtil = Util.SetUtil;

function SetUtil.ContainsKey(set, key)
    return set[key] ~= nil;
end

function SetUtil.FindKey(set, value)
    -- The WBT sets are small, so linear search is good enough.
    for k, v in pairs(set) do
        if v == value then
            return k;
        end
    end
    return nil;
end

function SetUtil.ContainsValue(set, value)
    return SetUtil.FindKey(set, value) and true;
end

--------------------------------------------------------------------------------
-- String utils
--------------------------------------------------------------------------------

-- Source: http://lua-users.org/wiki/StringRecipes
function Util.StrEndsWith(str, ending)
    return ending == "" or str:sub(-#ending) == ending;
end

--------------------------------------------------------------------------------

function Util.FormatTimeSeconds(seconds)
    local min = math.floor(seconds / 60);
    local sec = math.floor(seconds % 60);

    local min_text;
    if min < 10 then
        min_text = "0" .. min;
    else
        min_text = min;
    end

    local sec_text
    if sec < 10 then
        sec_text = "0" .. sec;
    else
        sec_text = sec;
    end
    
    return min_text .. ":" .. sec_text;
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

-- Always includes the original main realm.
function Util.GetConnectedRealms()
    local realms = GetAutoCompleteRealms();
    if next(realms) == nil then
        -- Empty table -> not a connected realm.
        realms = { GetNormalizedRealmName() };
    end

    return realms;
end

return Util;