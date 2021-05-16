--[[

# Release tests:
1. Perform all other tests.
2. Kill Rukhmar twice.
    a. 1st time: Check that you get timer.
    b. 2nd time: Check that you get alerts and that she spawns as expected.

# Before push to master tests:
1. For any changed module, perform relevant tests.
2. Manually check that happy path and most edge cases work. If necessary also write down a test for it here.

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

local function StartSim(name, dt_expire)
    WBT.SetKillInfo(name, AdjustedDeathTime(name, dt_expire));
end

local function SetKillInfo_Advanced(name, dt_expire, connected_realms_id, realm_type, optVersion)
    local version = optVersion or KillInfo.CURRENT_VERSION;
    local t_death = AdjustedDeathTime(name, dt_expire);
    local guid = KillInfo.CreateGUID(name, connected_realms_id, realm_type);
    local ki = WBT.db.global.kill_infos[guid];
    if ki then
        ki:SetNewDeath(name, t_death);
    else
        ki = KillInfo:New(t_death, name);
    end
    ki.connected_realms_id = connected_realms_id;
    ki.realm_type = realm_type;
    ki.version = version;

    WBT.db.global.kill_infos[guid] = ki;
end

local function SimOutdatedVersionKill(name, dt_expire)
    SetKillInfo_Advanced(name, dt_expire, "Firehammer", Util.Warmode.ENABLED, "v_unsupported");
end

local function SimWarmodeKill(name, dt_expire)
    SetKillInfo_Advanced(name, dt_expire, "Doomhammer", Util.Warmode.ENABLED);
end

local function SimServerKill(name, dt_expire, server)
    SetKillInfo_Advanced(name, dt_expire, server or "Majsbreaker", Util.Warmode.DISABLED);
end

local function SimKillSpecial(dt_expire)
    SimServerKill("Grellkin", dt_expire);
    SimWarmodeKill("Grellkin", dt_expire);
    SimOutdatedVersionKill("Grellkin", dt_expire);
end

local function SimKillEverything(dt_expire)
    for name, data in pairs(BossData.GetAll()) do
        StartSim(name, dt_expire);
    end
    SimKillSpecial(dt_expire);
end

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
