-- ----------------------------------------------------------------------------
--  KillInfo: Data structure for holding data about previous kills. (And update-timers.)
-- ----------------------------------------------------------------------------
--@do-not-package@
-- Meta table doesn't have to be the prototype's class, in can be any table.
-- The meta table is just a table that contains a method __index which points to the table.
-- where to look for missing functions (or fields?).
-- It doesn't look for the methods directly in the table. That is why we need to set self.__index = self.
--@end-do-not-package@

local _, WBT = ...;

local Util = WBT.Util;
local Options = WBT.Options;

local KillInfo = {};
WBT.KillInfo = KillInfo;

KillInfo.CURRENT_VERSION = "v1.11";
KillInfo.UNKNOWN_SHARD = -1;

local RANDOM_DELIM = "-";

local ID_DELIM        = ";";
local ID_PART_UNKNOWN = "_";


function KillInfo.CompareTo(t, a, b)
    -- "if I'm comparing 'a' and 'b', return true when 'a' should come first"
    local k1 = t[a];
    local k2 = t[b];

    k1:Update();
    k2:Update();

    if k1.reset then
        return false;
    elseif k2.reset then
        return true;
    end

    if k1:Expired() and not k2:Expired() then
        return false;
    elseif not k1:Expired() and k2:Expired() then
        return true;
    end

    return k1:GetSpawnTimeSec() < k2:GetSpawnTimeSec();
end

function KillInfo.IsValidID(id)
    return KillInfo.ParseID(id) and true;
end

-- Returns nil if the parsing fails.
function KillInfo.ParseID(id)
    local boss_name, shard_id, connected_realms_id, realm_type, map_id = strsplit(ID_DELIM, id);

    if not boss_name then
        return nil;
    end

    return {
        boss_name = boss_name,
        shard_id = shard_id,
        connected_realms_id = connected_realms_id,
        realm_type = realm_type,
        map_id = map_id,
    };
end

function KillInfo.CreateConnectedRealmsID()
    return table.concat(Util.GetConnectedRealms(), "_");
end

function KillInfo.CreateID(name, shard_id, connected_realms_id, realm_type, map_id)
    -- Unique ID used as key in the global table of tracked KillInfos and GUI labels.

    if shard_id == nil or shard_id == KillInfo.UNKNOWN_SHARD then
        shard_id = ID_PART_UNKNOWN;
    end

    local connected_realms_id = connected_realms_id or KillInfo.CreateConnectedRealmsID();
    local realm_type = realm_type or Util.WarmodeStatus();
    local map_id     = map_id     or WBT.GetCurrentMapId();

    return table.concat({name, shard_id, connected_realms_id, realm_type, map_id}, ID_DELIM);
end

function KillInfo:ID()
    return self.CreateID(self.name, self.shard_id, self.connected_realms_id, self.shard_id, self.realm_type, self.map_id);
end

function KillInfo:HasShardID()
    return self.shard_id ~= nil;
end

-- A KillInfo is no longer valid if its data was recorded before
-- the KillInfo class was introduced.
-- The field self.until_time did not exist then.
function KillInfo:IsValidVersion()
    return self.version and self.version == KillInfo.CURRENT_VERSION;
end

function KillInfo:SetInitialValues()
    self.version               = KillInfo.CURRENT_VERSION;
    self.cyclic                = false;
    self.reset                 = false;
    self.realm_name            = GetRealmName(); -- Only use for printing!
    self.realm_name_normalized = GetNormalizedRealmName();
    self.connected_realms_id   = KillInfo.CreateConnectedRealmsID();
    self.realm_type            = Util.WarmodeStatus();
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
    print(indent .. "name: "                  .. self.name);
    print(indent .. "version: "               .. self.version);
    print(indent .. "cyclic: "                .. tostring(self.cyclic));
    print(indent .. "reset: "                 .. tostring(self.reset));
    print(indent .. "realm_name: "            .. self.realm_name);
    print(indent .. "realm_name_normalized: " .. self.realm_name_normalized);
    print(indent .. "connected_realms_id: "   .. self.connected_realms_id);
    print(indent .. "shard_id: "              .. self.shard_id);
    print(indent .. "realm_type: "            .. self.realm_type);
    print(indent .. "map_id: "                .. self.map_id);
    print(indent .. "has_triggered_respawn: " .. tostring(self.has_triggered_respawn));
end

function KillInfo:SetNewDeath(t_death)
    -- FIXME: It doesn't make sense to this function from here. I think it's
    -- a remnant from the time when the addon tried to upgrade KillInfos.
    self:SetInitialValues();

    -- NOTE: self.t_death is later updated when the kill_info has expired.
    -- self.until_time is (currently) never updated though.
    self.t_death = t_death;
    self.until_time = self.t_death + self.db.max_respawn;
    self.reset = false;

    return self.until_time < GetServerTime();
end

function KillInfo:New(name, t_death, shard_id)
    local ki = {};

    setmetatable(ki, self);
    self.__index = self;

    ki.name = name;
    ki.db = WBT.BossData.Get(name);
    ki.shard_id = shard_id or KillInfo.UNKNOWN_SHARD;

    ki:SetNewDeath(t_death);

    return ki;
end

function KillInfo:Deserialize(serialized)
    local ki = serialized;
    setmetatable(ki, self);
    self.__index = self;
    return ki;
end

function KillInfo:HasRandomSpawnTime(name)
    return self.db.min_respawn ~= self.db.max_respawn;
end

function KillInfo:IsSafeToShare(error_msgs)

    if not self:IsValidVersion() then
        table.insert(error_msgs, "Timer was created with an old version of WBT and is now outdated.");
    end
    if self.cyclic then
        table.insert(error_msgs, "Timer has expired.");
    end
    if self.shard_id == KillInfo.UNKNOWN_SHARD then
        -- It's impossible to tell where it comes from. Player may have received it when server-jumping or
        -- what not. To avoid complexity, just don't allow sharing it.
        table.insert(error_msgs, "Timer doesn't have a shard ID. (This means that it was shared to you by a "
                              .. "player with an old version of WBT.)");  -- WBT v.1.9 or less.
    else
        local cur_shard_id = WBT.GetCurrentShardID();
        if not cur_shard_id then
            table.insert(error_msgs, "Current shard ID is unknown. It will automatically be detected when "
                                  .. "mousing over an NPC.");
        elseif self.shard_id ~= cur_shard_id then
            table.insert(error_msgs, "Kill was made on shard ID " .. self.shard_id ..
                                  .. ", but you are on " .. cur_shard_id .. ".");
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

function KillInfo:GetTimeSinceDeath()
    return GetServerTime() - self.t_death;
end

function KillInfo:GetSpawnTimesSecRandom()
    local t_since_death = self:GetTimeSinceDeath();
    local t_lower_bound = self.db.min_respawn - t_since_death;
    local t_upper_bound = self.db.max_respawn - t_since_death;

    return t_lower_bound, t_upper_bound;
end

function KillInfo:GetSpawnTimeSec(name)
    if self:HasRandomSpawnTime() then
        local _, t_upper = self:GetSpawnTimesSecRandom();
        return t_upper;
    else
        return self.db.min_respawn - self:GetTimeSinceDeath();
    end
end

function KillInfo:GetSpawnTimeAsText()
    local outdated =  "--outdated--";
    if not self:IsValidVersion() then
        return outdated;
    end

    if self:HasRandomSpawnTime() then
        local t_lower, t_upper = self:GetSpawnTimesSecRandom();
        if t_lower == nil or t_upper == nil then
            return outdated;
        elseif t_lower < 0 then
            return "0s" .. RANDOM_DELIM .. Util.FormatTimeSeconds(t_upper)
        else
            return Util.FormatTimeSeconds(t_lower) .. RANDOM_DELIM .. Util.FormatTimeSeconds(t_upper)
        end
    else
        local spawn_time_sec = self:GetSpawnTimeSec();
        if spawn_time_sec == nil or spawn_time_sec < 0 then
            return outdated;
        end

        return Util.FormatTimeSeconds(spawn_time_sec);
    end
end

function KillInfo:IsDead(ignore_cyclic)
    local ignore_cyclic = ignore_cyclic == true; -- Sending in nil shall result in false
    if self.reset or not self:IsValidVersion() then
        return false;
    end
    if self.cyclic then
        if ignore_cyclic or not Options.cyclic.get() then
            return false;
        end
        return true;
    end
    if self:HasRandomSpawnTime() then
        local _, t_upper = self:GetSpawnTimesSecRandom();
        return t_upper >= 0;
    else
        return self:GetSpawnTimeSec() >= 0;
    end
end

function KillInfo:HasRespawned()
    return not self:IsDead();
end

function KillInfo:ShouldAutoAnnounce()
    return WBT.db.global.auto_announce
            and Util.SetContainsValue(self.announce_times, self.remaining_time)
            and WBT.PlayerIsInBossPerimiter(self.name)
            and WBT.BossData.Get(self.name).auto_announce
            and self:IsSafeToShare({});
end

function KillInfo:InTimeWindow(from, to)
    local t_now = GetServerTime();
    return from <= t_now and t_now <= to;
end

function KillInfo:ShouldMakeRespawnAlertPlay(offset)
    local t_now = GetServerTime();
    local until_time_offset = self.until_time - offset;
    local trigger = self:InTimeWindow(until_time_offset, until_time_offset + 1)
            and WBT.InZoneAndShardForTimer(self)
            and WBT.PlayerIsInBossPerimiter(self.name)
            and self:IsSafeToShare({})
            and not self.has_triggered_respawn;
    if trigger then
        self.has_triggered_respawn = true;
    end

    return trigger;
end

function KillInfo:Update()
    if self.reset then
        return;
    end
    self.remaining_time = self.until_time - GetServerTime();
end

function KillInfo:EstimationNextSpawn()
    local t_spawn = self.t_death;
    local t_now = GetServerTime();
    local max_respawn = self.db.max_respawn;
    while t_spawn < t_now do
        t_spawn = t_spawn + max_respawn;
    end

    local t_death_new = t_spawn - max_respawn;
    return t_death_new, t_spawn;
end

function KillInfo:Reset()
    self.reset = true;
end

function KillInfo:Expired()
    return self.until_time < GetServerTime();
end

function KillInfo:IsOnCurrentShard(check_realm_on_missing_shard)
    local same_shard = self.shard_id and (self.shard_id == WBT.GetCurrentShardID());
    local same_realm = tContains(Util.GetConnectedRealms(), self.realm_name_normalized);
    local same_warmode = self.realm_type == Util.WarmodeStatus();
    local no_shard_but_otherwise_same = (self.shard_id == nil or WBT.GetCurrentShardID() == nil)
                                        and same_realm and same_warmode;
    return same_shard or (check_realm_on_missing_shard and no_shard_but_otherwise_same);
end
