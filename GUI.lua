-- ----------------------------------------------------------------------------
--  A persistent timer for World Bosses.
-- ----------------------------------------------------------------------------

-- addonName, addonTable = ...;
local _, WBT = ...;

local Util = WBT.Util;
local BossData = WBT.BossData;

-- Provides the GUI API and performs checks if the GUI is shown etc.
local GUI = {};
WBT.GUI = GUI;

WBT.G_window = {};

--------------------------------------------------------------------------------

function GUI:CreateLabels()
    self.labels = {};
    for name, data in pairs(BossData.GetAll()) do
        local label = self.AceGUI:Create("InteractiveLabel");
        label:SetWidth(180);
        label:SetCallback("OnClick", function(self)
                WBT.ResetBoss(name);
            end);
        self.labels[name] = label;
        self.window:AddChild(label);
    end
end

function GUI:Restart()
    self:New();
end

function GUI:ShouldShow()
    return (WBT.IsBossZone() or WBT.AnyDead()) and not(self.visible) and not(WBT.db.global.hide_gui);
end

function GUI:ShouldHide()
    return (not(WBT.IsBossZone() or WBT.AnyDead()) or WBT.db.global.hide_gui) and self.visible;
end

function GUI:Show()
    if self.released then
        self:Restart();
    end

    self:Update();
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

function GUI:Update()
    if not(self.visible) then
        return;
    end

    for name, kill_info in pairs(WBT.db.global.kill_infos) do
        local label = self.labels[name];
        if not BossData.BossExists(name) or getmetatable(kill_info) ~= WBT.KillInfo then
            -- Do nothing.
        elseif WBT.IsDead(name) and (not(kill_info.cyclic) or WBT.CyclicEnabled()) then
            label:SetText(WBT.GetColoredBossName(name) .. ": " .. WBT.GetSpawnTimeOutput(kill_info));
        else
            label:SetText("");
        end
    end

    self:UpdateGUIVisibility();
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

function GUI:NewBasicWindow(width, height)
    local window = GUI.AceGUI:Create("Window");

    window.frame:SetFrameStrata("LOW");
    window:SetWidth(width);
    window:SetHeight(height);


    window:SetTitle("World Boss Timers");
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

    local width = 200;
    local height = 110;
    self.window = GUI:NewBasicWindow(width, height);
    WBT.G_window = self.window;

    local btn = GUI.AceGUI:Create("Button");
    btn:SetWidth(width);
    btn:SetText("Request kill data");
    btn:SetCallback("OnClick", WBT.RequestKillData);

    self.gui_container = GUI.AceGUI:Create("SimpleGroup");
    self.gui_container.frame:SetFrameStrata("LOW");
    self.gui_container:AddChild(self.window);
    self.gui_container:AddChild(btn);

    -- I didn't notice any "OnClose" for the gui_container
    -- ("SimpleGroup") so it's handled through the
    -- Window class instead.
    self.window:SetCallback("OnClose", function()
        self:CleanUpWidgetsAndRelease();
        WBT.db.global.hide_gui = true;
    end);

    self:CreateLabels();
    self:InitPosition();
    self:RecordPositioning();

    self:Show();

    return self;
end

