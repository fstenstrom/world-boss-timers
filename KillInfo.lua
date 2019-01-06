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
local Config = WBT.Config;

local KillInfo = {};
WBT.KillInfo = KillInfo;

local CURRENT_VERSION = "v1.2.8";

local RANDOM_DELIM = "-";

local GUID_DELIM = ";";

function KillInfo.ValidGUID(guid)
    return KillInfo.ParseGUID(guid) and true;
end

-- Returns nil if the parsing fails.
function KillInfo.ParseGUID(guid)
    local valid_word = "([^;]+)";
    local pattern = "^" .. valid_word .. GUID_DELIM .. valid_word .. GUID_DELIM .. valid_word .. GUID_DELIM .. valid_word .. "$";
    local boss_name, realmName, realm_type, map_id = guid:match(pattern);

    if not boss_name then
        return nil;
    end

    return {
        boss_name = boss_name,
        realmName = realmName,
        realm_type = realm_type,
        map_id = map_id,
    };
end

function KillInfo.CreateGUID(name, realmName, realm_type, map_id)
    local realmName = realmName or GetRealmName();
    local realm_type = realm_type or Util.WarmodeStatus();
    local map_id = map_id or WBT.GetCurrentMapId();
    return name .. GUID_DELIM .. realmName .. GUID_DELIM .. realm_type .. GUID_DELIM .. map_id;
end

function KillInfo:GUID()
    return self.CreateGUID(self.name, self.realmName, self.realm_type, self.map_id);
end

-- A KillInfo is no longer valid if its data was recorded before
-- the KillInfo class was introduced.
-- The field self.until_time did not exist then.
function KillInfo:IsValid()
    return self.version and self.version == CURRENT_VERSION;
end

function KillInfo:SetInitialValues(name)
    self.name = name;
    self.version = CURRENT_VERSION;
    self.cyclic = false;
    self.reset = false;
    self.safe = not IsInGroup();
    self.realmName = GetRealmName();
    self.realm_type = Util.WarmodeStatus();
    self.map_id = WBT.GetCurrentMapId();
    self.db = WBT.BossData.Get(self.name);
    self.announce_times = {1, 2, 3, 10, 30, 1*60, 5*60, 10*60};
end

function KillInfo:SetNewDeath(name, t_death)
    self:SetInitialValues(name);

    self.t_death = t_death;
    self.until_time = self.t_death + self.db.max_respawn;
    self.reset = false;

    return self.until_time < GetServerTime();
end

function KillInfo:New(t_death, name)
    local ki = {};

    setmetatable(ki, self);
    self.__index = self;

    ki:SetNewDeath(name, t_death);

    return ki;
end

function KillInfo:Deserialize(serialized)
    local ki = serialized;
    setmetatable(ki, self);
    self.__index = self;
    return ki;
end

function KillInfo:GetColoredBossName(name)
    return self.db.color .. name .. COLOR_DEFAULT;
end

function KillInfo:HasRandomSpawnTime(name)
    return self.db.min_respawn ~= self.db.max_respawn;
end

-- The data for the kill can be incorrect. This might happen
-- when a player records a kill and then appear on another
-- server shard.
-- If this happens, we don't want the data to propagate
-- to other players.
function KillInfo:IsCompletelySafe(error_msgs)

    -- It's possible to have one char with Warmode, and one
    -- without on the same server.
    local realm_type = Util.WarmodeStatus();
    local realmName = GetRealmName();

    if not self:IsValid() then
        table.insert(error_msgs, "The kill was recorded with an old version of the Addon and is now outdated.");
    end
    if not self.safe then
        table.insert(error_msgs, "Player was in a group during previous kill.");
    end
    if self.cyclic then
        table.insert(error_msgs, "Last kill wasn't recorded. This is just an estimate.");
    end
    if not (self.realm_type == realm_type) then
        table.insert(error_msgs, "Kill was made on a " .. self.realm_type .. " realm, but are now on a " .. realm_type .. " realm.");
    end
    if not (self.realmName == realmName) then
        table.insert(error_msgs, "Kill was made on " .. self.realmName .. ", but are now on " .. realmName .. ".");
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
    if not self:IsValid() then
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
    if self.reset or not self:IsValid() then
        return false;
    end
    if self.cyclic then
        if ignore_cyclic or not Config.cyclic.get() then
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

function KillInfo.StartWorldBossDeathTimer()
    if not(self:HasRespawned()) or (Config.CyclicEnabled() and not(self.reset)) then
        local timer_duration = self:GetSpawnTimeSec();
        local pretty_name = self.db.color .. name .. COLOR_DEFAULT .. ": ";
        self:StartTimer(timer_duration, 1, pretty_name);
    end
end

function KillInfo:IsOnValidShard()
    return self.realmName == GetRealmName() and self.realm_type == Util.WarmodeStatus();
end

function KillInfo:ShouldAnnounce()
    return WBT.db.global.auto_announce
            and Util.SetContainsValue(self.announce_times, self.remaining_time)
            and WBT.IsInZoneOfBoss(self.name)
            and WBT.BossData.Get(self.name).auto_announce
            and self:IsCompletelySafe({});
end

function KillInfo:ShouldFlash()
    local t_now = GetServerTime();
    return self.until_time <= t_now and t_now <= (self.until_time + 1) and WBT.IsInZoneOfBoss(self.name) and self:IsCompletelySafe({});
end

function KillInfo:Update()
    if self.reset then
        return;
    end
    self.remaining_time = self.until_time - GetServerTime();
end

-- For bosses with non-random spawn. Modify the result for other bosses.
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
