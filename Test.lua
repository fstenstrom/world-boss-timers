-- This file is intended for in-game testing. The file provides functions
-- for quickly populating the addon instance with test data, which then
-- can be used to manually verify mainly the behavior of the GUI, but also
-- the system in its real environment.
--
-- When possible, tests should instead be automated in UnitTest.lua.


--[[

# Release tests:
1. Perform all other tests.

# Before push to master tests:
1. Unit tests must pass: UnitTests.lua
2. For any changed module, perform relevant tests.
3. Manually check that happy path and most edge cases work. If necessary also write down a test for it here.

#--------------------------------------------------------------------------------

# Communication tests:
1. Request timer via GUI. Check that chat message appears.
2. Share timer with other player via button. Check that they receive it.

# GUI tests:
1. Go to non-boss zone and run StartTimers25. Check that GUI looks OK and that you don't get any alerts. Change options arbitrarily and check that GUI looks OK.
    a. Repeat in boss zone. Check that you get alerts.
2. After (1.):
    a. /reload and check that everything looks OK.
    b. Relog and check that everything looks OK.
3. Spam all buttons exploratorily. Check that nothing breaks.

# Backend tests
1. Run StartTimers25. Check that GUI behaves as expected. 

# Logger tests
1. Clear all timers. Enter the perimiter of some boss and try to share. Check that Info message looks OK.
2. Run StartTimers4 and let it expire. Enter the perimiter of some boss and try to share. Check that Info message looks OK.

# CLI tests
1. Set log level to 'Nothing' via CLI. Check that GUI options shows correct value. Repeat Logger tests and verify that nothing is printed.
2. Set log level to 'Info' via CLI. Repeat (1.) but now check that the logger tests actually pass.

]]--

local _, WBT = ...;

WBT.Test = {};

local BossData = WBT.BossData;
local KillInfo = WBT.KillInfo;
local Util     = WBT.Util;
local TestUtil = WBT.TestUtil;
local Test     = WBT.Test;


local function RandomServerName()
    local res = "";
    for i = 1, 10 do
        res = res .. string.char(math.random(97, 122));
    end
    return res;
end

-- Returns a time point such that if this time point were set for a KillInfo, it
-- would expire in dt_expire.
local function AdjustedDeathTime(name, dt_expire)
    return GetServerTime() - BossData.Get(name).max_respawn + dt_expire;
end

local function CurrentShardID()
    local shard_id = WBT.GetCurrentShardID();
    if WBT.IsUnknownShard(shard_id) then
        print("WARNING: WBT test function running with unknown shard_id");
    end
    return shard_id;
end

local function StartSim(name, dt_expire)
    WBT.PutOrUpdateKillInfo(name, CurrentShardID(), AdjustedDeathTime(name, dt_expire));
end

local function PutOrUpdateKillInfo_Advanced(name, dt_expire, realm_name, opt_version, opt_shard_id)
    local version = opt_version or KillInfo.CURRENT_VERSION;
    local t_death = AdjustedDeathTime(name, dt_expire);
    local shard_id = opt_shard_id or CurrentShardID();
    local ki_id = KillInfo.CreateID(name, shard_id);
    local ki = WBT.db.global.kill_infos[ki_id];
    if ki then
        ki:SetNewDeath(t_death);
    else
        ki = KillInfo:New(name, t_death, shard_id);
    end
    ki.realm_name            = realm_name;
    ki.realm_name_normalized = realm_name;
    ki.version = version;

    WBT.db.global.kill_infos[ki_id] = ki;
end

local function SimOutdatedVersionKill(name, dt_expire)
    PutOrUpdateKillInfo_Advanced(name, dt_expire, "Firehammer", "v_unsupported");
end

local function SimServerKill(name, dt_expire, server)
    PutOrUpdateKillInfo_Advanced(name, dt_expire, server or "Majsbreaker");
end

local function SimNoShardKill(name, dt_expire, server)
    local shard_id = nil;
    PutOrUpdateKillInfo_Advanced(name, dt_expire, "SHD", KillInfo.CURRENT_VERSION, shard_id);
end

local function SimNoShardKillRustfeather()
    PutOrUpdateKillInfo_Advanced("Rustfeather", 25, "SHD", KillInfo.CURRENT_VERSION, KillInfo.UNKNOWN_SHARD);
end
dnoshard = SimNoShardKillRustfeather;

local function SimKillSpecial(dt_expire)
    SimServerKill("Grellkin", dt_expire);
    SimOutdatedVersionKill("Grellkin", dt_expire);
    SimNoShardKill("Grellkin", dt_expire);
    SimServerKill("Grellkin", dt_expire);
    PutOrUpdateKillInfo_Advanced("Rustfeather", dt_expire, "Dbg", KillInfo.CURRENT_VERSION, 12);
    PutOrUpdateKillInfo_Advanced("Rustfeather", dt_expire, "Dbg", KillInfo.CURRENT_VERSION, 1234);
end

local function SimKillEverything(dt_expire)
    for name, data in pairs(BossData.GetAll()) do
        StartSim(name, dt_expire);
    end
    SimKillSpecial(dt_expire);
end

-- Starts timers 300 seconds before they expire. This gives time to /reload and still keep
-- timers before expiration.
function Test.StartTimers300()
    SimKillEverything(300);
end
dsim300 = Test.StartTimers300; -- Lazy command for running from command line without access to macros.

-- Starts timers 25 seconds before they expire. This gives time to check that
-- alerts/sharing is performed.
function Test.StartTimers25()
    SimKillEverything(25);
end
dsim25 = Test.StartTimers25; -- Lazy command for running from command line without access to macros.

-- Starts timer 4 seconds before sharing. This allows to check what happens when
-- timers expire.
function Test.StartTimers4(n)
    SimKillEverything(4);
end
dsim4 = Test.StartTimers4; -- Lazy command for running from command line without access to macros.

-- Starts timers for random servers. It's very probable that this won't be on
-- the same server as the player.
function Test.StartTimersRandomServer()
    for i = 1, 5 do
        SimServerKill("Grellkin", RandomServerName())
    end
end

function Test.ShareLegacyTimer(shard_id_or_nil)
    local msg = TestUtil.CreateShareMsg("Grellkin", GetServerTime(), 9, shard_id_or_nil)
    SendChatMessage(msg, "SAY");
end
dshare = Test.ShareLegacyTimer;

function Test.ResetOpts()
    for k, v in pairs(WBT.defaults.global) do
        if k ~= "kill_infos" then
            WBT.db.global[k] = v;
        end
    end
    WBT.g_gui:Update();
end
resetopts = Test.ResetOpts