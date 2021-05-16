--@do-not-package@
--[[

# Release tests:
1. Kill Rukhmar twice.
    a. 1st time: Check that you get timer.
    b. 2nd time: Check that you get alerts and that she spawns as expected.
2. Perform all other tests.

# Before push to master tests:
1. For any module touched, relevant tests.
2. Manually check that happy path and most edge cases work. If necessary also write down a test for it here.

#--------------------------------------------------------------------------------

# Communication tests:
1. Request timer via GUI. Check chat message appears.
2. Share timer with other via button. Check they receive it.

# GUI tests:
1. Go to non-boss zone and start CheckTimer25. Check that GUI looks OK and that you don't get any alerts. Change options arbitrarily and check that GUI looks OK.
    a. Repeat in boss zone. Check that you get alerts.
2. After (1.):
    a. /reload and check that everything looks OK.
    b. Relog and check that everything looks OK.
3. Spam all buttons exploratorily. Check that nothing breaks.

# Backend tests
1. Start CheckTimer25. Check that GUI behaves as expected. 

# Logger tests
1. Clear all timers. Enter the perimiter of some boss and try to share. Check that Info message looks OK.
2. Start CheckTimer4 and let it expire. Enter the perimiter of some boss and try to share. Check that Info message looks OK.

# CLI tests
1. Set log level to 'Nothing' via CLI. Check that GUI options shows correct value. Repeat Logger tests and verify that nothing is printed.
2. Set log level to 'Info' via CLI. Repeat (1.) but now check that the logger tests actually pass.

]]--

local _, WBT = ...;

local function RandomServerName()
    local res = "";
    for i = 1, 10 do
        res = res .. string.char(math.random(97, 122));
    end
    return res;
end

local function StartSim(name, t)
    WBT.SetKillInfo(name, t);
end

local function SetKillInfo_Advanced(name, t_death, connected_realms_id, realm_type, optVersion)
    version = optVersion or KillInfo.CURRENT_VERSION;
    t_death = tonumber(t_death);
    local guid = KillInfo.CreateGUID(name, connected_realms_id, realm_type);
    local ki = g_kill_infos[guid];
    if ki then
        ki:SetNewDeath(name, t_death);
    else
        ki = KillInfo:New(t_death, name);
    end
    ki.connected_realms_id = connected_realms_id;
    ki.realm_type = realm_type;
    ki.version = version;

    g_kill_infos[guid] = ki;

    gui:Update();
end

local function SecToRespawn(name, t)
    return GetServerTime() - BossData.Get(name).max_respawn + t;
end

local function SimOutdatedVersionKill(name)
    SetKillInfo_Advanced(name, SecToRespawn(name, 4), "Firehammer", Util.Warmode.ENABLED, "v_unsupported");
end

local function SimWarmodeKill(name)
    SetKillInfo_Advanced(name, SecToRespawn(name, 4), "Doomhammer", Util.Warmode.ENABLED);
end

local function SimServerKill(name, server)
    SetKillInfo_Advanced(name, SecToRespawn(name, 4), server or "Majsbreaker", Util.Warmode.DISABLED);
end

local function SimKillSpecial()
    SimServerKill("Grellkin");
    SimWarmodeKill("Grellkin");
    SimOutdatedVersionKill("Grellkin");
end

local function SimKill(sec_to_respawn)
    for name, data in pairs(BossData.GetAll()) do
        StartSim(name, SecToRespawn(name, sec_to_respawn));
    end
    SimKillSpecial();
end

function dsim(n)
    if n == nil then
        SimKill(4);
    else
        for i = 1, n do
            SimServerKill("Grellkin", RandomServerName())
        end
    end
end

-- Relog, and make sure it works after.
function dsim2()
    SimKill(25);
end

function dsim3()
    SimKillSpecial();
end

function stopgui()
    kill_info_manager:SetScript("OnUpdate", nil);
end
--@end-do-not-package@

