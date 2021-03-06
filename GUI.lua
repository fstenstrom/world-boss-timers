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
    self.window.frame:SetMovable(not Options.lock.get());
end

-- Ensure that right clicking outside of the window
-- does not trigger the interactive label, or hide
-- other GUI components.
function GUI.LabelWidth(width)
    return width - 15;
end

function GUI:CreateNewLabel(guid)
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
    local new_width = Options.multi_realm.get() and WIDTH_EXTENDED or WIDTH_DEFAULT;
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

function GUI:GetLabelText(kill_info, all_info)
    local prefix = "";
    if all_info then
        prefix = Util.ColoredString(Util.COLOR_DARKGREEN, strsub(kill_info.realm_name_normalized, 0, 3)) .. ":"
                .. Util.ColoredString(Util.WarmodeColor(kill_info.realm_type), strsub(kill_info.realm_type, 0, 1)) .. ":";
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

    for guid, kill_info in pairs(WBT.db.global.kill_infos) do
        local label = self.labels[guid];
        if label == nil or getmetatable(kill_info) ~= WBT.KillInfo then
            -- Do nothing.
        else
            GUI:RemoveLabel(guid, label);
        end
    end
    self:Update();
end

function GUI:FreshKillTrigger(kill_info, label)
    -- Not setting t_death_window from outside, to be certain that it doesn't
    -- change between calls (saying this since the same variable name is used
    -- in some other function).
    local t_death_window = 3;  -- Arbitrarily chosen value.
    local tf = not kill_info:Expired()
            and kill_info:GetTimeSinceDeath() < t_death_window
            and label.userdata.fresh_kill_flag ~= true;
    if tf then
        label.userdata.fresh_kill_flag = true;
    end
    return tf;
end

function GUI:CyclicLabelResetTrigger(kill_info, label)
    -- Not setting t_death_window from outside, to be certain that it doesn't
    -- change between calls (saying this since the same variable name is used
    -- in some other function).
    local t_death_window = 3;  -- Arbitrarily chosen value.
    local tf = kill_info:Expired()
            and kill_info.db.max_respawn - kill_info:GetSpawnTimeSec() < t_death_window
            and (label.userdata.time_last_reset == nil
                or label.userdata.time_last_reset + t_death_window < GetServerTime());
    if tf then
        label.userdata.time_last_reset = GetServerTime();
    end
    return tf;
end

function GUI:UpdateContent()
    local n_shown_labels = 0;
    for guid, kill_info in Util.spairs(WBT.db.global.kill_infos, WBT.KillInfo.CompareTo) do
        local label = self.labels[guid] or self:CreateNewLabel(guid);
        if getmetatable(kill_info) ~= WBT.KillInfo then
            -- Do nothing.
        elseif WBT.IsDead(guid)
                and (not(kill_info.cyclic) or Options.cyclic.get())
                and (WBT.ThisServerAndWarmode(kill_info) or Options.multi_realm.get()) then
            n_shown_labels = n_shown_labels + 1;
            label:SetText(self:GetLabelText(kill_info, Options.multi_realm.get()));

            if not label.userdata.added then
                self.window:AddChild(label);
                label.userdata.added = true;
            else
                if self:FreshKillTrigger(kill_info, label) or self:CyclicLabelResetTrigger(kill_info, label) then
                    self:Rebuild(); -- Warning: recursive call!
                    return; -- Returning here, since above call is recursive.
                end
            end
        else
            if label.userdata.added then
                -- The label is apparently not automatically removed from the
                -- self.window.children table, so it has to be done manually...
                self:RemoveLabel(guid, label);
            end
        end
    end

    self:UpdateHeight(n_shown_labels);
    self:UpdateWidth();
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

    window:SetTitle("WorldBossTimers");
    window:SetLayout("List");
    window:EnableResize(false);

    self.visible = false;

    return window;
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

    self.window.title:SetScript("OnMouseDown", function(this)
        if self.window.frame:IsMovable() then
            this:GetParent():StartMoving();
        end
        GUI.AceGUI:ClearFocus();
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

