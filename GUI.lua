-- The code for the GUI, i.e. the window with the timers.

local _, WBT = ...;

local Util = WBT.Util;
local Options = {}; -- Must be initialized later.

-- Provides the GUI API and performs checks if the GUI is shown etc.
local GUI = {};
WBT.GUI = GUI;

WBT.G_window = {};

local WIDTH_DEFAULT = 200;
local HEIGHT_BASE = 30;
local HEIGHT_DEFAULT = 106;
local MAX_ENTRIES_DEFAULT = 7;

-- The sum of the relatives is not 1, because I've had issues with "Flow"
-- elements sometimes overflowing to next line then.
local BTN_OPTS_REL_WIDTH  = 30/100;
local BTN_REQ_REL_WIDTH   = 30/100;
local BTN_SHARE_REL_WIDTH = 39/100; -- Needs the extra width or name might not show.


function GUI:Init()
    Options = WBT.Options;
end

function GUI:CreateLabels()
    self.labels = {};
end

function GUI:Restart()
    self:New();
end

local function ShowBossZoneOnlyAndOutsideZone()
    return Options.show_boss_zone_only.get() and not WBT.InBossZone();
end

function GUI:ShouldShow()
    if ShowBossZoneOnlyAndOutsideZone() then
        return false;
    end
    local should_show =
            not self.visible
            and not WBT.db.global.hide_gui;
    
    return should_show;
end

function GUI:ShouldHide()
    -- Should GUI only be shown in boss zone, but is not in one?
    -- Are no bosses considered dead (waiting for respawn)?

    local should_hide = (WBT.db.global.hide_gui or ShowBossZoneOnlyAndOutsideZone())
            and self.visible;

    return should_hide;
end

function GUI:Show()
    if self.released then
        self:Restart();
    end

    self.gui_container.frame:Show();
    self.visible = true;

    -- It's possible that options that affect the GUI position have changed
    -- while the GUI has been hidden, e.g. toggling between char/global position.
    -- In that case the position must be updated.
    self:InitPosition();
end

function GUI:Hide()
    if self.released then
        return;
    end

    self.gui_container.frame:Hide();
    self.visible = false;
end

function GUI:UpdateGUIVisibility()
    if self:ShouldShow() then
        self:Show();
    elseif self:ShouldHide() then
        self:Hide();
    end
end

function GUI:LockOrUnlock()
    if not self.window then
        -- The window is freed when hidden.
        return;
    end
    -- BUG:
    -- If the window is locked, and then a user tries to move it, an error will be thrown
    -- because "StartMoving" is not allowed to be called on non-movable frames.
    -- However, there doesn't seem to exist any API that allows an AceGUI frame to be
    -- locked.
    -- The error should be harmless tho, unless a user shows lua errors, in which case it will
    -- at worst be annoying.
    self.window.frame:SetMovable(not Options.lock.get());
end

-- Ensure that right clicking outside of the window
-- does not trigger the interactive label, or hide
-- other GUI components.
function GUI.LabelWidth(width)
    return width - 15;
end

function GUI:CreateNewLabel(guid, kill_info)
    local gui = self;
    local label = GUI.AceGUI:Create("InteractiveLabel");
    label:SetWidth(GUI.LabelWidth(self.width));
    label:SetCallback("OnClick", function(self)
            local text = self.label:GetText();
            if text and text ~= "" then
                WBT.ResetBoss(guid);
            end
            gui:Update();
        end);
    label.userdata.t_death = kill_info.t_death;
    label.userdata.time_next_spawn = kill_info:GetSecondsUntilLatestRespawn();
    return label;
end

function GUI:UpdateHeight(n_entries)
    local new_height = n_entries <= MAX_ENTRIES_DEFAULT and HEIGHT_DEFAULT + n_entries
            or (self.window.content:GetNumChildren() * 11 + HEIGHT_BASE);
    if self.height == new_height then
        return;
    end

    self.window:SetHeight(new_height);
    self.height = new_height;
end

function GUI:UpdateWidth()
    local new_width = WIDTH_DEFAULT +
            (Options.multi_realm.get() and 40 or 0) +
            (Options.show_realm.get() and 20 or 0);
    if self.width == new_width then
        return;
    end

    self.width = new_width;
    self.window:SetWidth(new_width);
    self.btn_container:SetWidth(new_width);
    for _, label in pairs(self.labels) do
        label:SetWidth(GUI.LabelWidth(new_width));
    end
end

-- Before this function can be used, labels must be created! I.e. there must be
-- a mapping mapping to which KillInfos will be displayed.
function GUI:FindMaxDisplayedShardId()
    -- Find longest shard ID for padding.
    local max_shard_id = 0;
    for guid, label in pairs(self.labels) do
        local shard_id = WBT.db.global.kill_infos[guid].shard_id;
        if shard_id > max_shard_id then
            max_shard_id = shard_id;
        end
    end
    return max_shard_id;
end

function GUI.CreatePaddedShardIdString(shard_id, max_shard_id)
    local shard_str;
    local pad_char;
    if WBT.IsUnknownShard(shard_id) then
        shard_str = "?";
        pad_char = "?";  -- Alignment won't work because font isn't monospace. But it's an improvement.
    else
        shard_str = shard_id;
        pad_char = "0";
    end
    local pad_len = string.len(max_shard_id) - string.len(shard_str);
    shard_str = string.rep(pad_char, pad_len) .. shard_str;
    return shard_str;
end

function GUI.CreateLabelText(kill_info, max_shard_id)
    local prefix = "";
    local color = WBT.GetHighlightColor(kill_info);
    local prefix = "";
    if Options.multi_realm.get() then
        local shard = GUI.CreatePaddedShardIdString(kill_info.shard_id, max_shard_id)
        shard = Util.ColoredString(color, shard);
        prefix = prefix .. shard .. ":";
    end
    if Options.show_realm.get() then
        local realm = Util.ColoredString(Util.COLOR_YELLOW, strsub(kill_info.realm_name_normalized, 0, 3));
        prefix = prefix .. realm .. ":";
    end
    return prefix .. WBT.GetColoredBossName(kill_info.boss_name) .. ": " .. WBT.GetSpawnTimeOutput(kill_info);
end

function GUI:AddNewLabel(guid, kill_info)
    local label = self:CreateNewLabel(guid, kill_info);
    self.labels[guid] = label;
    self.window:AddChild(label);
end

function GUI:Rebuild()
    if self.labels == nil then
        return; -- GUI hasn't been built, so nothing to rebuild.
    end

    -- Clear all labels.
    for guid, _ in pairs(self.labels) do
        -- NOTE: Don't try to remove specific children. That's too Ace internal.
        table.remove(self.window.children);
        self.labels[guid]:Release();
        self.labels[guid] = nil;
    end

    self:Update();
end

-- Returns true when a kill_info has a fresh kill that needs to be updated for the label.
function GUI.KillInfoHasFreshKill(kill_info, label)
    local t_death = kill_info:GetServerDeathTime();
    if label.userdata.t_death ~= t_death then
        label.userdata.t_death = t_death;
        return true;
    else
        return false;
    end
end

-- True when the timer for a cyclic label restarted (i.e. made a lap).
-- This includes the event that a kill info goes from non-expired to expired.
function GUI.CyclicKillInfoRestarted(kill_info, label)
    local t_next_spawn = kill_info:GetSecondsUntilLatestRespawn();
    if label.userdata.time_next_spawn < t_next_spawn then
        label.userdata.time_next_spawn = t_next_spawn;
        return true;
    else
        return false;
    end
end

function GUI.ShouldShowKillInfo(kill_info)
    if kill_info:IsCyclicExpired() then
        return false;
    end
    local shard_ok = Options.assume_realm_keeps_shard.get()
            and kill_info:IsOnSavedRealmShard()
            or kill_info:IsOnCurrentShard();
    return shard_ok or Options.multi_realm.get();
end

-- Builds and/or updates what labels as necessary.
function GUI:UpdateContent()
    local nlabels = 0;
    local needs_rebuild = false;

    -- Note that labels are added in a certain order, which corresponds to the order they will
    -- be displayed in the Window. If there is a need to re-order a label, then the solution
    -- is to call GUI.Rebuild().
    -- The reason for a rebuild instead of sorting is that the labels are bound to internal AceGUI objects
    -- and I don't want to try to sort them.
    for guid, kill_info in Util.spairs(WBT.db.global.kill_infos, WBT.KillInfo.CompareTo) do
        local label = self.labels[guid];
        local show_label = GUI.ShouldShowKillInfo(kill_info);
        if show_label then
            nlabels = nlabels + 1;
            if label == nil then
                self:AddNewLabel(guid, kill_info)
            else
                -- FIXME: Use self.update_event instead.
                if GUI.KillInfoHasFreshKill(kill_info, label) or GUI.CyclicKillInfoRestarted(kill_info, label) then
                    -- The order of the labels needs to be updated, so rebuild.
                    needs_rebuild = true;
                end
            end
        else
            -- Remove label:
            if label then
                -- XXX:
                -- Just removing the label seems to cause issues with other labels not showing
                -- if they are added after this label is removed. (Probably something wrong with
                -- the assumption on how the window children are stored.)
                -- Workaround: Just rebuild.
                needs_rebuild = true;
                if self.update_event == WBT.UpdateEvents.SHARD_DETECTED then
                    local boss_name = WBT.GetColoredBossName(WBT.db.global.kill_infos[guid].boss_name);
                    WBT.Logger.Info("Timer for " .. boss_name .. " was hidden because it's not for the current shard.")
                end
            end
        end
    end

    if needs_rebuild then
        self:Rebuild(); -- Warning: recursive call!
    else
        self:UpdateHeight(nlabels);
        self:UpdateWidth();

        -- Set the label texts.
        local max_shard_id = self:FindMaxDisplayedShardId();
        for guid, label in pairs(self.labels) do
            label:SetText(GUI.CreateLabelText(WBT.db.global.kill_infos[guid], max_shard_id));
        end

        self:UpdateWindowTitle();
    end
end

-- @param event: Optional event specifier.
function GUI:Update(event)
    self.update_event = event or WBT.UpdateEvents.UNSPECIFIED;

    self:UpdateGUIVisibility();

    if not self.visible then
        return;
    end

    self:LockOrUnlock();
    self:UpdateContent();

    self.update_event = WBT.UpdateEvents.UNSPECIFIED;
end

function GUI:SetPosition(pos)
    if self.released then
        -- It's possible to get here when toggling GUI options while the GUI is hidden (i.e. released).
        return;
    end
    local relativeTo = nil;
    self.window:ClearAllPoints();
    self.window:SetPoint(pos.point, relativeTo, pos.xOfs, pos.yOfs);
end

local function GetDefaultGUIPosition()
    return {
        point = "Center",
        relativeToName = "UIParrent",
        realtivePoint = nil,
        xOfs = 0,
        yOfs = 0,
    };
end

local function GetGUIPosition()
    local pos = Options.global_gui_position.get()
            and WBT.db.global.gui_position
            or WBT.db.char.gui_position;
    if pos == nil then
        return GetDefaultGUIPosition();
    elseif pos.point == nil or pos.xOfs == nil or pos.yOfs == nil then
        -- Corrupted point. Could happen due to issue #109. This will restore the
        -- default position without users needing to reset all WBT settings.
        WBT.Logger.Debug("Restoring corrupted GUI position.");
        return GetDefaultGUIPosition();
    else
        return pos;
    end
end

function GUI:InitPosition()
    local pos = GetGUIPosition();
    self:SetPosition(pos);
end

-- Function is on class since this can be called from hooksecurefunc. The GUI is singleton right now either way.
function GUI.SaveGUIPosition()
    if not GUI.visible then
        -- If the GUI is not visible the position will not contain e.g. coordinates.
        -- Trying to save it will corrupt the position.
        return;
    end

    local point, _, relativePoint, xOfs, yOfs = WBT.G_window:GetPoint();

    if xOfs == nil or yOfs == nil then
        -- Extra check for case mentioned above.
        WBT.Logger.Debug("WARNING: Tried to save GUI position without coordinates");
        return;
    end

    local pos = {
        point = point,
        relativeToName = "UIParrent",
        relativePoint = relativePoint,
        xOfs = xOfs,
        yOfs = yOfs,
    };
    if Options.global_gui_position.get() then
        WBT.db.global.gui_position = pos;
    else
        WBT.db.char.gui_position = pos;
    end
end

function GUI:SaveGUIPositionOnMove()
    hooksecurefunc(self.window.frame, "StopMovingOrSizing", self.SaveGUIPosition);
end

function GUI:ResetPosition()
    local pos = GetDefaultGUIPosition();
    self:SetPosition(pos);
end

function GUI.SetupAceGUI()
    GUI.AceGUI = LibStub("AceGUI-3.0"); -- Need to create AceGUI during/after 'OnInit' or 'OnEnabled'
end

function GUI:CleanUpWidgetsAndRelease()
    GUI.AceGUI:Release(self.gui_container);

    -- Remove references to fields. Hopefully the widget is
    self.labels = nil;
    self.visible = nil;
    self.gui_container = nil;
    self.window = nil;

    self.released = true;
end

function GUI:NewBasicWindow()
    local window = GUI.AceGUI:Create("Window");

    window.frame:SetFrameStrata("LOW");
    window:SetWidth(self.width);
    window:SetHeight(self.height);

    window:SetLayout("List");
    window:EnableResize(false);

    self.visible = false;

    return window;
end

function GUI:UpdateWindowTitle()
    if not self.window then
        -- The window is freed when hidden.
        return;
    end
    local prefix = "";
    if Options.multi_realm:get() then
        if WBT.IsUnknownShard(WBT.GetCurrentShardID()) then
            prefix = "??? - ";
        else
            local cur_shard_id = WBT.GetCurrentShardID();
            local max_shard_id = self:FindMaxDisplayedShardId();
            prefix = GUI.CreatePaddedShardIdString(cur_shard_id, max_shard_id) .. " - ";
        end
    end
    self.window:SetTitle(prefix .. "WorldBossTimers")
end

-- "Decorator" of default closeOnClick, see AceGUIContainer-Window.lua.
local function closeOnClick(this)
    PlaySound(799);
    this.obj:Hide();
    WBT.db.global.hide_gui = true;
end

-- FIXME: Essentially this class is a singleton, but it's being accessed via
-- something that looks like an instance (g_gui) at some places, and directly via
-- the class (GUI) at other places.
function GUI:New()
    if self.gui_container then
        self.gui_container:Release();
    end

    self.update_event = WBT.UpdateEvents.UNSPECIFIED;

    self.released = false;

    self.width = WIDTH_DEFAULT;
    self.height = HEIGHT_DEFAULT;
    self.window = GUI:NewBasicWindow();
    self.window.closebutton:SetScript("OnClick", closeOnClick);
    WBT.G_window = self.window;  -- FIXME: Remove this variable.
    self.window:SetTitle("WorldBossTimers");

    self.btn_req = GUI.AceGUI:Create("Button");
    self.btn_req:SetRelativeWidth(BTN_REQ_REL_WIDTH);
    self.btn_req:SetText("Req.");
    self.btn_req:SetCallback("OnClick", WBT.RequestKillData);

    self.btn_opts = GUI.AceGUI:Create("Button");
    self.btn_opts:SetText("/wbt");
    self.btn_opts:SetRelativeWidth(BTN_OPTS_REL_WIDTH);
    self.btn_opts:SetCallback("OnClick", function() WBT.AceConfigDialog:Open(WBT.addon_name); end);

    self.btn_share = GUI.AceGUI:Create("Button");
    self.btn_share:SetRelativeWidth(BTN_SHARE_REL_WIDTH);
    self.btn_share:SetText("Share");
    self.btn_share:SetCallback("OnClick", WBT.Functions.AnnounceTimerInChat);

    self.btn_container = GUI.AceGUI:Create("SimpleGroup");
    self.btn_container.frame:SetFrameStrata("LOW");
    self.btn_container:SetLayout("Flow");
    self.btn_container:SetWidth(self.width);
    self.btn_container:AddChild(self.btn_opts);
    self.btn_container:AddChild(self.btn_req);
    self.btn_container:AddChild(self.btn_share);

    self.gui_container = GUI.AceGUI:Create("SimpleGroup");
    self.gui_container.frame:SetFrameStrata("LOW");
    self.gui_container:SetLayout("List");
    self.gui_container:AddChild(self.window);
    self.gui_container:AddChild(self.btn_container);

    -- I didn't notice any "OnClose" for the gui_container
    -- ("SimpleGroup") so it's handled through the
    -- Window class instead.
    self.window:SetCallback("OnClose", function()
        self:CleanUpWidgetsAndRelease();
    end);

    self:CreateLabels();
    self:InitPosition();
    self:SaveGUIPositionOnMove();

    self:Show();                -- Initialize visibility (arbitrarily chosen as shown) ...
    self:UpdateGUIVisibility(); -- ... and then set correct visibility from options and so on.

    return self;
end
