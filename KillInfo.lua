-- ----------------------------------------------------------------------------
--  KillInfo: Data structure for holding data about previous kills. (And update-timers.)
-- ----------------------------------------------------------------------------

local _, WBT = ...;

local KillInfo = {}
WBT.KillInfo = KillInfo;

function KillInfo:New(o)
    local o = o or {};
    --@do-not-package@
    -- Meta table doesn't have to be the prototype's class, in can be any table.
    -- The meta table is just a table that contains a method __index which points to the table
    -- where to look for missing functions (or fields?).
    -- It doesn't look for the methods directly in the table. That is why we need to set self.__index = self.
    --@end-do-not-package@
    setmetatable(o, self);
    self.__index = self;
    return o;
end

function KillInfo:Print()
    print("|cffff0000" .. self.name .. "|cffffffff");
end

