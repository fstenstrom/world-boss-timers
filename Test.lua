-- This file is intended for in-game testing. The file provides functions
-- for quickly populating the addon instance with test data, which then
-- can be used to manually verify mainly the behavior of the GUI, but also
-- the system in its real environment.
--
-- When possible, tests should instead be automated in UnitTest.lua.


--[[

# Release tests:
1. Perform all other tests.

# Before push to master:
1. Unit tests must pass: UnitTests.lua
2. For any changed module, perform relevant tests.
3. Manually check that happy path and relevant edge cases work.

#--------------------------------------------------------------------------------

# Communication tests:
1. Request timer via GUI. Check that chat message appears.
2. Share timer with other player via button. Check that they receive it.

# GUI tests:
1. Go to non-boss zone and run StartTimers25. Check that GUI looks OK and that
   you don't get any alerts. Change options arbitrarily and check that GUI
   looks OK.
      a. Repeat in boss zone. Check that you get alerts.
2. After (1.):
      a. /reload and check that everything looks OK.
      b. Relog and check that everything looks OK.
3. Spam all buttons exploratorily. Check that nothing breaks.

# Backend tests
1. Run StartTimers25. Check that GUI behaves as expected. 

# Logger tests
1. Clear all timers. Enter the perimiter of some boss and try to share. Check
   that Info message looks OK.
2. Run StartTimers4 and let it expire. Enter the perimiter of some boss and try
   to share. Check that Info message looks OK.

# CLI tests
1. Set log level to 'Nothing' via CLI. Check that GUI options shows correct
   value. Repeat Logger tests and verify that nothing is printed.
2. Set log level to 'Info' via CLI. Repeat (1.) but now check that the logger
   tests actually pass.

]]--

local _, WBT = ...;

WBT.Test = {};

local BossData = WBT.BossData;
local KillInfo = WBT.KillInfo;
local Util     = WBT.Util;
local TestUtil = WBT.TestUtil;
local Test     = WBT.Test;

local ShardIds = {
    NON_SAVED_ZONE   = 0,  -- No saved zone should have this ID.
    ISLE_OF_GIANTS_1 = 1,
    ISLE_OF_GIANTS_2 = 2,
}

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

local function PutOrUpdateKillInfo_Advanced(name, dt_expire, opt_realm_name, opt_version, opt_shard_id)
    local boss_in_curr_zone = BossData.Get(name).map_id == WBT.GetCurrentMapId();

    local version = opt_version or KillInfo.CURRENT_VERSION;
    local t_death = AdjustedDeathTime(name, dt_expire);
    local shard_id = opt_shard_id or (boss_in_curr_zone and CurrentShardID()) or ShardIds.NON_SAVED_ZONE;
    local ki_id = KillInfo.CreateID(name, shard_id);
    local ki = WBT.db.global.kill_infos[ki_id];
    if ki then
        ki:SetNewDeath(t_death);
    else
        ki = KillInfo:New(name, t_death, shard_id);
    end
    if opt_realm_name then
        ki.realm_name            = opt_realm_name;
        ki.realm_name_normalized = opt_realm_name;
    end
    ki.version = version;

    WBT.db.global.kill_infos[ki_id] = ki;
end

local function StartSim(name, dt_expire)
    PutOrUpdateKillInfo_Advanced(name, dt_expire);
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

local function SimKillSpecial(dt_expire)
    SimServerKill("Grellkin", dt_expire);
    SimOutdatedVersionKill("Grellkin", dt_expire);
    SimNoShardKill("Grellkin", dt_expire);
    SimServerKill("Grellkin", dt_expire);
    PutOrUpdateKillInfo_Advanced("Oondasta", dt_expire,   "Dbg", KillInfo.CURRENT_VERSION, ShardIds.ISLE_OF_GIANTS_1);
    PutOrUpdateKillInfo_Advanced("Oondasta", dt_expire+3, "Dbg", KillInfo.CURRENT_VERSION, ShardIds.ISLE_OF_GIANTS_2);
end

local function SimKillEverything(dt_expire)
    for name, data in pairs(BossData.GetAll()) do
        StartSim(name, dt_expire);
    end
    SimKillSpecial(dt_expire);
    WBT.GUI:Update();
end

-- Starts timers 300 seconds before they expire. This gives time to /reload and still keep
-- timers before expiration.
function Test.StartTimers300()
    SimKillEverything(300);
end

-- Starts timers 25 seconds before they expire. This gives time to check that
-- alerts/sharing is performed.
function Test.StartTimers25()
    SimKillEverything(25);
end

-- Starts timer 4 seconds before sharing. This allows to check what happens when
-- timers expire.
function Test.StartTimers4(n)
    SimKillEverything(4);
end

function Test.ShareLegacyTimer(shard_id_or_nil)
    local msg = TestUtil.CreateShareMsg("Grellkin", GetServerTime(), 9, shard_id_or_nil)
    SendChatMessage(msg, "SAY");
end

function Test.ResetOpts()
    for k, v in pairs(WBT.defaults.global) do
        if k ~= "kill_infos" then
            WBT.db.global[k] = v;
        end
    end
    WBT.g_gui:Update();
end

function Test.RestartShardDetection()
    local f = WBT.EventHandlerFrames.shard_detection_restarter_frame;
    local delay_old = f.delay;
    f.delay = 0;
    f:Handler();
    f.delay = delay_old;
end

function Test.SetIsleOfGiantsSavedShardId_1()
    WBT.PutSavedShardIDForZone(WBT.BossData.Get("Oondasta").map_id, ShardIds.ISLE_OF_GIANTS_1);
    WBT.GUI:Update();
end

function Test.SetIsleOfGiantsSavedShardId_2()
    WBT.PutSavedShardIDForZone(WBT.BossData.Get("Oondasta").map_id, ShardIds.ISLE_OF_GIANTS_2);
    WBT.GUI:Update();
end

function Test.ToggleDevSilent()
    WBT.Options.dev_silent:Toggle();
end

function Test.PrintShards()
    print("Current:", WBT.GetCurrentShardID());
    print("Saved:", WBT.GetSavedShardID(WBT.GetCurrentMapId()));
end

--------------------------------------------------------------------------------

function Test:CreateButton(text, fcn)
    local btn = self.AceGUI:Create("Button");
    btn:SetText(text);
    btn:SetCallback("OnClick", fcn);
    return btn;
end

function Test:BuildTestGUI()
    if self.AceGUI == nil then
        self.AceGUI = LibStub("AceGUI-3.0");
    end

    self.grp = self.AceGUI:Create("SimpleGroup");
    self.grp.frame:SetFrameStrata("LOW");
    self.grp:SetLayout("Flow");
    self.grp:SetWidth(120);
    self.grp:AddChild(self:CreateButton("dsim300",        Test.StartTimers300));
    self.grp:AddChild(self:CreateButton("dsim25",         Test.StartTimers25));
    self.grp:AddChild(self:CreateButton("dsim4",          Test.StartTimers4));
    self.grp:AddChild(self:CreateButton("Reset",          WBT.ResetKillInfo));
    self.grp:AddChild(self:CreateButton("Set isle id 1",  Test.SetIsleOfGiantsSavedShardId_1));
    self.grp:AddChild(self:CreateButton("Set isle id 2",  Test.SetIsleOfGiantsSavedShardId_2));
    self.grp:AddChild(self:CreateButton("Restart shard",  Test.RestartShardDetection));
    self.grp:AddChild(self:CreateButton("Show shards",    Test.PrintShards));
    self.grp:AddChild(self:CreateButton("Silent +-",      Test.ToggleDevSilent));
    self.grp:AddChild(self:CreateButton("Reset opts",     Test.ResetOpts));

    -- Keep at bottom:
    self.grp:AddChild(self:CreateButton("Reload", ReloadUI));
    
    self.grp:ClearAllPoints();
    self.grp:SetPoint("TopLeft", nil, 100, -200);

    self.grp.frame:Show();
end

hooksecurefunc(WBT.AceAddon, "OnEnable", function(...)
    if WBT.db.global.build_test_gui then
        Test:BuildTestGUI();
    end
end);