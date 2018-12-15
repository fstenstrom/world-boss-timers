-- ----------------------------------------------------------------------------
--  A persistent timer for World Bosses.
-- ----------------------------------------------------------------------------

-- addonName, addonTable = ...;
local _, WBT = ...;

local Util = WBT.Util;
local BossData = WBT.BossData;
local Config = {}; -- Must be initialized later.

-- Provides the GUI API and performs checks if the GUI is shown etc.
local GUI = {};
WBT.GUI = GUI;

WBT.G_window = {};

local WIDTH_DEFAULT = 200;
local HEIGHT_DEFAULT = 112;
local MAX_ENTRIES_DEFAULT = 7;

local WIDTH_EXTENDED = 230;

--------------------------------------------------------------------------------

function GUI.Init()
    Config = WBT.Config;
end

function GUI:CreateLabels()
    self.labels = {};
    --[[
    for name, data in pairs(BossData.GetAll()) do
        local label = self.AceGUI:Create("InteractiveLabel");
        label:SetWidth(180);
        label:SetCallback("OnClick", function(self)
                WBT.ResetBoss(name);
            end);
        self.labels[name] = label;
        self.window:AddChild(label);
    end
    ]]--
end

function GUI:Restart()
    self:New();
end

local function ShowBossZoneOnlyAndOutsideZone()
    return Config.show_boss_zone_only.get() and not WBT.IsBossZone();
end

function GUI:ShouldShow()
    -- cnd -> condition
    if (ShowBossZoneOnlyAndOutsideZone()) then
        return false;
    end
    local should_show =
            not self.visible
            and not WBT.db.global.hide_gui;

    --@do-not-package@
    -- print(WBT.IsBossZone(), WBT.AnyDead(), self.visible, WBT.db.global.hide_gui);
    -- print("Should show:", should_show);
    --@end-do-not-package@
    
    return should_show;
end

function GUI:ShouldHide()
    -- Should GUI only be shown in boss zone, but is not in one?
    -- Are no bosses considered dead (waiting for respawn)?
    local cnd_none_tracked = not WBT.AnyDead();

    local should_hide = (WBT.db.global.hide_gui or ShowBossZoneOnlyAndOutsideZone())
            and self.visible;

    --@end-do-not-package@
    -- print(ShowBossZoneOnlyAndOutsideZone(), cnd_none_tracked);
    -- print("Should hide:", should_hide);
    --@end-do-not-package@
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

-- Ensure that right clicking outside of the window
-- does not trigger the interactive label, or hide
-- other GUI components.
function GUI.LabelWidth(width)
    return width - 20;
end

function GUI:CreateNewLabel(guid)
    local label = self.AceGUI:Create("InteractiveLabel");
    label:SetWidth(GUI.LabelWidth(WIDTH_DEFAULT));
    label:SetCallback("OnClick", function(self)
            local text = self.label:GetText();
            if text and text ~= "" then
                WBT.ResetBoss(guid);
            end
        end);
    self.labels[guid] = label;
    self.window:AddChild(label);
    return label;
end

function GUI:UpdateHeight(n_entries)
    local new_height = n_entries <= MAX_ENTRIES_DEFAULT and HEIGHT_DEFAULT
            or (n_entries * (HEIGHT_DEFAULT / MAX_ENTRIES_DEFAULT));
    if self.height == new_height then
        return;
    end

    self.window:SetHeight(new_height);

    self.height = new_height;
end

function GUI:UpdateWidth()
    local new_width = Config.multi_realm.get() and WIDTH_EXTENDED or WIDTH_DEFAULT;
    if self.width == new_width then
        return;
    end

    self.window:SetWidth(new_width);
    self.btn:SetWidth(new_width);
    for _, label in pairs(self.labels) do
        label:SetWidth(GUI.LabelWidth(new_width));
    end

    self.width = new_width;
end

function GUI:GetLabelText(kill_info, all_info)
    local prefix = "";
    if all_info then
        prefix = Util.ColoredString(Util.COLOR_DARKGREEN, strsub(kill_info.realmName, 0, 3)) .. ":"
                .. Util.ColoredString(Util.WarmodeColor(kill_info.realm_type), strsub(kill_info.realm_type, 0, 3)) .. ":";
    end
    return prefix .. WBT.GetColoredBossName(kill_info.name) .. ": " .. WBT.GetSpawnTimeOutput(kill_info)
end

function GUI:UpdateContent()
    local n_shown_labels = 0;
    for guid, kill_info in pairs(WBT.db.global.kill_infos) do
        local label = self.labels[guid] or self:CreateNewLabel(guid);
        if getmetatable(kill_info) ~= WBT.KillInfo then
            -- Do nothing.
        elseif WBT.IsDead(guid)
                and (not(kill_info.cyclic) or Config.cyclic.get())
                and (WBT.ThisServerAndWarmode(kill_info) or Config.multi_realm.get()) then
            n_shown_labels = n_shown_labels + 1;
            label:SetText(self:GetLabelText(kill_info, Config.multi_realm.get()));
        else
            label:SetText("");
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

    self:UpdateContent();
end

function GUI:InitPosition()
    local gui_position = WBT.db.char.gui_position;
    local gp;
    if gui_position ~= nil then
        gp = gui_position;
    else
        gp = {
            point = "Center",
            relativeToName = "UIParrent",
            realtivePoint = nil,
            xOfs = 0,
            yOfs = 0,
        }
    end
    self.window:ClearAllPoints();
    self.window:SetPoint(gp.point, relativeTo, gp.xOfs, gp.yOfs);
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

function GUI:New()
    if self.gui_container then
        self.gui_container:Release();
    end

    self.released = false;

    self.width = WIDTH_DEFAULT;
    self.height = HEIGHT_DEFAULT;
    self.window = GUI:NewBasicWindow();
    WBT.G_window = self.window;

    self.btn = GUI.AceGUI:Create("Button");
    self.btn:SetWidth(self.width);
    self.btn:SetText("Request kill data");
    self.btn:SetCallback("OnClick", WBT.RequestKillData);

    self.gui_container = GUI.AceGUI:Create("SimpleGroup");
    self.gui_container.frame:SetFrameStrata("LOW");
    self.gui_container:AddChild(self.window);
    self.gui_container:AddChild(self.btn);

    -- I didn't notice any "OnClose" for the gui_container
    -- ("SimpleGroup") so it's handled through the
    -- Window class instead.
    self.window:SetCallback("OnClose", function()
        self:CleanUpWidgetsAndRelease();
    end);

    self:CreateLabels();
    self:InitPosition();
    self:RecordPositioning();

    self:Show();

    return self;
end

