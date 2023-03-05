-- ----------------------------------------------------------------------------
--  A persistent timer for World Bosses.
-- ----------------------------------------------------------------------------

-- addonName, addonTable = ...;
local _, WBT = ...;

local Util = WBT.Util;
local Com = WBT.Com;
local Options = {}; -- Must be initialized later.

-- Provides the GUI API and performs checks if the GUI is shown etc.
local GUI = {};
WBT.GUI = GUI;

WBT.G_window = {};

local WIDTH_DEFAULT = 200;
local HEIGHT_BASE = 30;
local HEIGHT_DEFAULT = 106;
local MAX_ENTRIES_DEFAULT = 7;

local WIDTH_EXTENDED = 240;

-- The sum of the relatives is not 1, because I've had issues with "Flow"
-- elements sometimes overflowing to next line then.
local BTN_OPTS_REL_WIDTH  = 30/100;
local BTN_REQ_REL_WIDTH   = 30/100;
local BTN_SHARE_REL_WIDTH = 39/100; -- Needs the extra width or name might not show.


--------------------------------------------------------------------------------


--@do-not-package@
local function PrintAllFunctionsRec(o)
    print("Starting recursion for:", o);
    if o == nil then
        return;
    end

    for k, v in pairs(o) do
        --if type(v) == "function" then
            print(k);
        --end
    end

    local mt = getmetatable(o);
    if mt == nil then
        return;
    end

    PrintAllFunctionsRec(mt.__index);
end
--@end-do-not-package@


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
    if (ShowBossZoneOnlyAndOutsideZone()) then
        return false;
    end
    local should_show =
            not self.visible
            and not WBT.db.global.hide_gui;

    --@do-not-package@
    -- print(WBT.InBossZone(), WBT.AnyDead(), self.visible, WBT.db.global.hide_gui);
    -- print("Should show:", should_show);
    --@end-do-not-package@
    
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
    label.userdata.added = false;
    label.userdata.time_next_spawn = kill_info:GetSpawnTimeSec();
    self.labels[guid] = label;
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

function GUI.CreateLabelText(kill_info, max_shard_id)
    local prefix = "";
    local color = WBT.GetHighlightColor(kill_info);
    local prefix = "";
    if Options.multi_realm.get() then
        local shard;
        local pad_char;
        if kill_info:HasUnknownShard() then
            shard = "?";
            pad_char = "?";  -- Alignment wont' work because font isn't monospace. But it's an improvement.
        else
            shard = kill_info.shard_id;
            pad_char = "0";
        end
        shard = string.rep(pad_char, string.len(max_shard_id) - string.len(shard)) .. shard;
        shard = Util.ColoredString(color, shard);
        prefix = prefix .. shard .. ":";
    end
    if Options.show_realm.get() then
        local realm = Util.ColoredString(Util.COLOR_YELLOW, strsub(kill_info.realm_name_normalized, 0, 3));
        prefix = prefix .. realm .. ":";
    end
    return prefix .. WBT.GetColoredBossName(kill_info.name) .. ": " .. WBT.GetSpawnTimeOutput(kill_info);
end

function GUI:RemoveLabel(guid, label)
    -- This table is always a set, and can therefore be treated as such.
    Util.RemoveFromSet(self.window.children, label);
    label:Release();
    self.labels[guid] = nil;
end

function GUI:Rebuild()
    if not self.labels then
        return; -- GUI hasn't been built, so nothing to rebuild.
    end

    for guid, label in pairs(self.labels) do
        if not WBT.db.global.kill_infos[guid] then
            self:RemoveLabel(guid, label);
        end
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
    local t_next_spawn = kill_info:GetSpawnTimeSec();
    if label.userdata.time_next_spawn < t_next_spawn then
        label.userdata.time_next_spawn = t_next_spawn;
        return true;
    else
        return false;
    end
end

-- Builds and/or updates what labels as necessary.
function GUI:UpdateContent()
    local n_shown_labels = 0;
    local needs_rebuild = false;

    -- Note that labels are added in a certain order, which corresponds to the order they will
    -- be displayed in the Window. If there is a need to re-order a label, then the solution
    -- is to call GUI.Rebuild().
    -- The reason for a rebuild instead of sorting is that the labels are bound to internal AceGUI objects
    -- and I don't want to try to sort them.
    for guid, kill_info in Util.spairs(WBT.db.global.kill_infos, WBT.KillInfo.CompareTo) do
        local label = self.labels[guid] or self:CreateNewLabel(guid, kill_info);
        if getmetatable(kill_info) ~= WBT.KillInfo then
            -- Do nothing.
        elseif WBT.IsDead(guid)
                and (not(kill_info.cyclic) or Options.cyclic.get())
                and (kill_info:IsOnCurrentShard() or Options.multi_realm.get()) then
            n_shown_labels = n_shown_labels + 1;

            if not label.userdata.added then
                self.window:AddChild(label);
                label.userdata.added = true;
            else
                if GUI.KillInfoHasFreshKill(kill_info, label) or GUI.CyclicKillInfoRestarted(kill_info, label) then
                    -- The order of the labels needs to be updated, so rebuild.
                    needs_rebuild = true;
                end
            end
        else
            if label.userdata.added then
                -- The label is apparently not automatically removed from the
                -- self.window.children table, so it has to be done manually.
                self:RemoveLabel(guid, label);
            end
        end
    end

    -- Find longest shard ID for padding.
    local max_shard_id = 0;
    for guid, label in pairs(self.labels) do
        local shard_id = WBT.db.global.kill_infos[guid].shard_id;
        if shard_id > max_shard_id then
            max_shard_id = shard_id;
        end
    end

    -- Set the label texts.
    for guid, label in pairs(self.labels) do
        label:SetText(GUI.CreateLabelText(WBT.db.global.kill_infos[guid], max_shard_id));
    end

    if needs_rebuild then
        self:Rebuild(); -- Warning: recursive call!
    else
        self:UpdateHeight(n_shown_labels);
        self:UpdateWidth();
    end
end

function GUI:Update()
    self:UpdateGUIVisibility();

    if not(self.visible) then
        return;
    end

    self:LockOrUnlock();
    self:UpdateContent();
end

function GUI:UpdatePosition(gp)
    local relativeTo = nil;
    self.window:ClearAllPoints();
    self.window:SetPoint(gp.point, relativeTo, gp.xOfs, gp.yOfs);
end

local function GetDefaultPosition()
    return {
        point = "Center",
        relativeToName = "UIParrent",
        realtivePoint = nil,
        xOfs = 0,
        yOfs = 0,
    };
end

function GUI:InitPosition()
    local gui_position = WBT.db.char.gui_position;
    local gp;
    if gui_position ~= nil then
        gp = gui_position;
    else
        gp = GetDefaultPosition();
    end
    self:UpdatePosition(gp);
end

function GUI:SaveGuiPoint()
    local point, relativeTo, relativePoint, xOfs, yOfs = WBT.G_window:GetPoint();
    WBT.db.char.gui_position = {
        point = point,
        relativeToName = "UIParrent",
        relativePoint = relativePoint,
        xOfs = xOfs,
        yOfs = yOfs,
    };
end

function GUI:RecordPositioning()
    hooksecurefunc(self.window.frame, "StopMovingOrSizing", self.SaveGuiPoint);
end

function GUI:ResetPosition()
    local gp = GetDefaultPosition();
    self:UpdatePosition(gp);
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
    local prefix = "";
    if Options.multi_realm:get() then
        local shard_id = WBT.GetCurrentShardID();
        if shard_id then
            prefix = tostring(shard_id) .. " - ";
        else
            prefix = "??? - ";
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

function GUI:New()
    if self.gui_container then
        self.gui_container:Release();
    end

    self.released = false;

    self.width = WIDTH_DEFAULT;
    self.height = HEIGHT_DEFAULT;
    self.window = GUI:NewBasicWindow();
    self.window.closebutton:SetScript("OnClick", closeOnClick);
    WBT.G_window = self.window;
    self:UpdateWindowTitle();

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
    self:RecordPositioning();

    self:Show();                -- Just sets a well defined state of visibility...
    self:UpdateGUIVisibility(); -- ... that will be updated here.

    return self;
end

--@do-not-package@
function GUI:PrintWindowFunctions()
    PrintAllFunctionsRec(self.window);
end
--@end-do-not-package@

