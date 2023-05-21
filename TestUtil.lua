local _, WBT = ...;

local TestUtil = {};

if type(WBT) == 'table' then  -- True when loaded via WoW, but not UnitTest.
    WBT.TestUtil = TestUtil;
end

function TestUtil.CreateShareMsg(bossname, servertime, t_since_death, shard_id)
    local t = servertime - t_since_death;
    local decorator
    local shard_id_part
    if shard_id then
        decorator = ""
        shard_id_part = "-" .. tostring(shard_id)
    else
        decorator = "{rt8}"
        shard_id_part = ""  -- Legacy. Can't happen any longer.
    end
    return decorator..bossname..decorator..": 6m 52s (WorldBossTimers:" .. tostring(t) .. shard_id_part .. ")";
end

return TestUtil;