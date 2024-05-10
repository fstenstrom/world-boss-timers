--  KillInfo: The class with the data for showing a boss respawn timer.
-- Note that the timers themselves are GUI text labels.

local _, WBT = ...;

local Util = WBT.Util;
local Options = WBT.Options;

local KillInfo = {};
WBT.KillInfo = KillInfo;

KillInfo.CURRENT_VERSION = "v1.12";
KillInfo.UNKNOWN_SHARD = -1;

local RANDOM_DELIM = "-";

local ID_DELIM        = ";";
local ID_PART_UNKNOWN = "_";


function KillInfo.CompareTo(t, a, b)
    -- "if I'm comparing 'a' and 'b', return true when 'a' should come first"
    local k1 = t[a];
    local k2 = t[b];

    if k1:IsExpired() and not k2:IsExpired() then
        return false;
    elseif not k1:IsExpired() and k2:IsExpired() then
        return true;
    end

    return k1:GetSecondsUntilLatestRespawn() < k2:GetSecondsUntilLatestRespawn();
end

function KillInfo.IsValidID(id)
    return KillInfo.ParseID(id) and true;
end

-- Returns nil if the parsing fails.
function KillInfo.ParseID(id)
    local boss_name, shard_id, map_id = strsplit(ID_DELIM, id);

    if not boss_name then
        return nil;
    end

    return {
        boss_name = boss_name,
        shard_id = shard_id,
        map_id = map_id,
    };
end

function KillInfo.CreateID(boss_name, shard_id, map_id)
    -- Unique ID used as key in the global table of tracked KillInfos and GUI labels.
    --
    -- Note on map_id: It's necessary to make Zandalari Warbringers unique.

    if shard_id == nil or shard_id == KillInfo.UNKNOWN_SHARD then
        shard_id = ID_PART_UNKNOWN;
    end

    local map_id = map_id or WBT.GetCurrentMapId();

    return table.concat({boss_name, shard_id, map_id}, ID_DELIM);
end

function KillInfo:ID()
    return self.CreateID(self.boss_name, self.shard_id, self.map_id);
end

function KillInfo:HasShardID()
    return self.shard_id ~= nil;
end

-- Needed in order to verify that all fields are present.
function KillInfo:IsValidVersion()
    return self.version and self.version == KillInfo.CURRENT_VERSION;
end

function KillInfo:SetInitialValues()
    self.version               = KillInfo.CURRENT_VERSION;
    self.realm_name            = GetRealmName(); -- Only use for printing!
    self.realm_name_normalized = GetNormalizedRealmName();
    self.map_id                = WBT.GetCurrentMapId();
    self.announce_times        = {1, 2, 3, 10, 30, 1*60, 5*60, 10*60};
    self.has_triggered_respawn = false;
end

-- NOTE:
-- This function is a reminder that the design is to update KillInfo.CURRENT_VERSION (and thereby clear
-- all user KillInfos), rather than try to upgrade existing ones. The reason is that it makes the code simpler,
-- and should not impact users too much if it only happens once in a while.
function KillInfo:Upgrade()
    -- Don't implement this function.
end

function KillInfo:Print(indent)
    print(indent .. "boss_name: "             .. self.boss_name);
    print(indent .. "version: "               .. self.version);
    print(indent .. "realm_name: "            .. self.realm_name);
    print(indent .. "realm_name_normalized: " .. self.realm_name_normalized);
    print(indent .. "shard_id: "              .. self.shard_id);
    print(indent .. "map_id: "                .. self.map_id);
    print(indent .. "has_triggered_respawn: " .. tostring(self.has_triggered_respawn));
end

function KillInfo:SetNewDeath(t_death)
    -- FIXME: It doesn't make sense to call this function from here. I think it's
    -- a remnant from the time when the addon tried to upgrade KillInfos.
    self:SetInitialValues();

    self.t_death = t_death;
end

function KillInfo:New(boss_name, t_death, shard_id)
    local ki = {};

    setmetatable(ki, self);
    self.__index = self;

    ki.boss_name = boss_name;
    ki.db = WBT.BossData.Get(boss_name);  -- FIXME: Convert to fcn, and fix calls to WBT.BossData.Get(self.boss_name)
    ki.shard_id = shard_id or KillInfo.UNKNOWN_SHARD;

    ki:SetNewDeath(t_death);

    return ki;
end

function KillInfo:Deserialize(serialized)
    local ki = serialized;
    setmetatable(ki, self);
    self.__index = self;

    -- Workaround: Update old timers with new db object in case BossData has been updated in new addon version.
    -- FIXME: Don't save db object. See KillInfo.New.
    ki.db = WBT.BossData.Get(ki.boss_name);  

    return ki;
end

function KillInfo:HasRandomSpawnTime()
    return self.db.min_respawn ~= self.db.max_respawn;
end

function KillInfo:IsSafeToShare(error_msgs)

    if not self:IsValidVersion() then
        table.insert(error_msgs, "Timer was created with an old version of WBT and is now outdated.");
    end
    if self:IsExpired() then
        table.insert(error_msgs, "Timer has expired.");
    end
    if self:HasUnknownShard() then
        -- It's impossible to tell where it comes from. Player may have received it when server-jumping or
        -- what not. To avoid complexity, just don't allow sharing it.
        table.insert(error_msgs, "Timer doesn't have a shard ID. (This means that it was shared to you by a "
                              .. "player with an old version of WBT.)");  -- WBT v.1.9 or less.
    else
        local shard_id = WBT.GetCurrentShardID();
        if WBT.IsUnknownShard(shard_id) then
            table.insert(error_msgs, "Current shard ID is unknown. It will automatically be detected when "
                                  .. "mousing over an NPC.");
        elseif self.shard_id ~= shard_id then
            table.insert(error_msgs, "Kill was made on shard ID " .. self.shard_id
                                  .. ", but you are on " .. shard_id .. ".");
        end
    end

    if Util.TableIsEmpty(error_msgs) then
        return true;
    end
    return false;
end

function KillInfo:GetServerDeathTime()
    return self.t_death;
end

function KillInfo:GetSecondsSinceDeath()
    return GetServerTime() - self.t_death;
end

function KillInfo:GetEarliestRespawnTimePoint()
    return self.t_death + self.db.min_respawn;
end

function KillInfo:GetLatestRespawnTimePoint()
    return self.t_death + self.db.max_respawn;
end


function KillInfo:GetNumCycles()
    local t = self:GetLatestRespawnTimePoint() - GetServerTime();
    local n = 0;
    while t < 0 do
        t = t + self.db.max_respawn;
        n = n + 1;
    end
    return n;
end

function KillInfo:GetSecondsUntilEarliestRespawn(opt_cyclic)
    return self:GetSecondsUntilLatestRespawn(opt_cyclic) - (self.db.max_respawn - self.db.min_respawn);
end

function KillInfo:GetSecondsUntilLatestRespawn(opt_cyclic)
    local t = self:GetLatestRespawnTimePoint() - GetServerTime();
    if opt_cyclic and t < 0 then
        t = t + (self:GetNumCycles() * self.db.max_respawn);
    end
    return t;
end

function KillInfo:GetSpawnTimeAsText()
    if not self:IsValidVersion() then
        return "--outdated--";
    end

    if self:HasRandomSpawnTime() then
        local t_lower = self:GetSecondsUntilEarliestRespawn(true);
        local t_upper = self:GetSecondsUntilLatestRespawn(true);
        if t_lower == nil or t_upper == nil then
            return "--invalid--";
        elseif t_lower < 0 then
            -- Just display 0 instead of 00:00 to make it easier to read
            return "0" .. RANDOM_DELIM .. Util.FormatTimeSeconds(t_upper)
        else
            return Util.FormatTimeSeconds(t_lower) .. RANDOM_DELIM .. Util.FormatTimeSeconds(t_upper)
        end
    else
        return Util.FormatTimeSeconds(self:GetSecondsUntilEarliestRespawn(true));
    end
end

function KillInfo:ShouldAutoAnnounce()
    return WBT.db.global.auto_announce
            and Util.SetUtil.ContainsValue(self.announce_times, self:GetSecondsUntilLatestRespawn())
            and WBT.PlayerIsInBossPerimiter(self.boss_name)
            and WBT.BossData.Get(self.boss_name).auto_announce
            and self:IsSafeToShare({});
end

function KillInfo:InTimeWindow(from, to)
    local t_now = GetServerTime();
    return from <= t_now and t_now <= to;
end

function KillInfo:ShouldRespawnAlertPlayNow(offset)
    local t_before_respawn = self:GetLatestRespawnTimePoint() - offset;

    local trigger = self:InTimeWindow(t_before_respawn, t_before_respawn + 2)
            and WBT.InZoneAndShardForTimer(self)
            and WBT.PlayerIsInBossPerimiter(self.boss_name)
            and self:IsValidVersion()
            and not self:IsExpired()
            and not self.has_triggered_respawn;
    if trigger then
        self.has_triggered_respawn = true;
    end

    return trigger;
end

function KillInfo:IsExpired()
    return self:GetSecondsUntilLatestRespawn() < 0;
end

function KillInfo:IsCyclicExpired()
    if not Options.cyclic.get() then
        return self:IsExpired();
    elseif Options.num_cycles_to_show.get() == Options.NUM_CYCLES_TO_SHOW_MAX then
        -- Special case. Allows timers to always be shown.
        return false;
    end
    return Options.num_cycles_to_show.get() < self:GetNumCycles();
end

function KillInfo:HasUnknownShard()
    return self.shard_id == KillInfo.UNKNOWN_SHARD;
end

function KillInfo:IsOnCurrentShard()
    if self:HasUnknownShard() then
        return false;
    elseif Options.assume_realm_keeps_shard.get() and (self.shard_id == WBT.GetSavedShardID(WBT.GetCurrentMapId())) then
        return true;
    else
        return self.shard_id == WBT.GetCurrentShardID();
    end
end

-- Returns true if the KillInfo comes from the last known shard for the
-- zone its boss belongs to.
function KillInfo:IsOnSavedRealmShard()
    if self:HasUnknownShard() then
        return false;
    end

    local zone_id = WBT.BossData.Get(self.boss_name).map_id;
    return WBT.GetSavedShardID(zone_id) == self.shard_id;
end