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

local KillInfo = {}
WBT.KillInfo = KillInfo;

local RANDOM_DELIM = "-"

function KillInfo:SetInitialValues()
    self.cyclic = false;
    self.reset = false;
    self.safe = not IsInGroup();
end

function KillInfo:SetNewDeath(t_death)
    self:SetInitialValues();

    self.t_death = t_death;
    self.until_time = self.t_death + self.db.max_respawn;
    self.reset = false;

    return self.until_time < GetServerTime();
end

function KillInfo:New(t_death, name)
    local ki = {
        name = name,
        realmName = GetRealmName(),
        realm_type = Util.GetRealmType(),
        db = WBT.BossData.Get(name),
        announce_times = {1, 2, 3, 10, 30, 1*60, 5*60, 10*60};
    }

    setmetatable(ki, self);
    self.__index = self;

    ki:SetNewDeath(t_death);

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

    --local kill_info = GetKillInfoFromZone();

    -- It's possible to have one char with war mode, and one
    -- without on the same server.
    local realm_type = Util.GetRealmType();
    local realmName = GetRealmName();

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
    if self:HasRandomSpawnTime() then
        local t_lower, t_upper = self:GetSpawnTimesSecRandom();
        if t_lower == nil or t_upper == nil then
            return -1;
        elseif t_lower < 0 then
            return "0s" .. RANDOM_DELIM .. Util.FormatTimeSeconds(t_upper)
        else
            return Util.FormatTimeSeconds(t_lower) .. RANDOM_DELIM .. Util.FormatTimeSeconds(t_upper)
        end
    else
        local spawn_time_sec = self:GetSpawnTimeSec();
        if spawn_time_sec == nil or spawn_time_sec < 0 then
            return -1;
        end

        return Util.FormatTimeSeconds(spawn_time_sec);
    end
end

function KillInfo:IsDead()
    if self.reset then
        return false;
    end
    if self.cyclic then
        if WBT.CyclicEnabled() then
            return true;
        else
            return false;
        end
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
    if not(self:HasRespawned()) or (CyclicEnabled() and not(self.reset)) then
        local timer_duration = self:GetSpawnTimeSec();
        local pretty_name = self.db.color .. name .. COLOR_DEFAULT .. ": ";
        self:StartTimer(timer_duration, 1, pretty_name);
    end
end

function KillInfo:ShouldAnnounce()
    return WBT.db.global.auto_announce
            and Util.SetContainsValue(self.announce_times, self.remaining_time)
            and WBT.IsInZoneOfBoss(self.name)
            and self:IsCompletelySafe({});
end

function KillInfo:ShouldFlash()
    local t_now = GetServerTime();
    return self.until_time <= t_now and t_now <= (self.until_time + 1) and WBT.IsInZoneOfBoss(self.name);
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
