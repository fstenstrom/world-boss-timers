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

function Util.ColoredString(color, ...)
    return color .. Util.MessageFromVarargs(...) .. Util.COLOR_DEFAULT;
end

function Util.TableIsEmpty(tbl)
    return next(tbl) == nil
end

function Util.SetContainsKey(set, key)
    return set[key] ~= nil;
end

function Util.SetContainsValue(set, value)
    for k, v in pairs(set) do
        if v == value then
            return true;
        end
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

function Util.GetRealmType()
    local pvpStyle = GetZonePVPInfo();
    if pvpStyle == nil then
        return REALM_TYPE_PVE;
    end

    return REALM_TYPE_PVP;
end
