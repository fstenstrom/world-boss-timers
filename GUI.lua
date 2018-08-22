-- ----------------------------------------------------------------------------
--  A persistent timer for World Bosses.
-- ----------------------------------------------------------------------------

-- addonName, addonTable = ...;
local _, WBT = ...;

local Util = WBT.Util;
local BossData = WBT.BossData;

local GUI = {};
WBT.GUI = GUI;


function GUI:CreateLabels()
    self.labels = {};
    for name, data in pairs(BossData.GetAll()) do
        local label = GUI.AceGUI:Create("InteractiveLabel");
        label:SetWidth(180);
        label:SetCallback("OnClick", function(self)
                WBT.ResetBoss(name)
            end);
        self.labels[name] = label;
        self:AddChild(label);
    end
end

function GUI:Restart()
    self = GUI:New();
end

function GUI:ShouldShow()
    return (WBT.IsBossZone() or WBT.AnyDead()) and not(self.visible);
end

function GUI:ShouldHide()
    return not(WBT.IsBossZone() or WBT.AnyDead()) and self.visible;
end

function GUI:UpdateGUIVisibility()
    if self:ShouldShow() then
        self:Restart();
    elseif self:ShouldHide() then
        self:Hide();
    end
end

function GUI:Update()
    for name, kill_info in pairs(WBT.db.global.kill_infos) do
        local label = self.labels[name];
        if WBT.IsDead(name) and (not(kill_info.cyclic) or WBT.CyclicEnabled()) then
            label:SetText(WBT.GetColoredBossName(name) .. ": " .. WBT.GetSpawnTimeOutput(kill_info));
        else
            label:SetText("");
        end
    end

    self:UpdateGUIVisibility();
end

function GUI:InitPosition()
    gui_position = WBT.db.char.gui_position;
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
    self:ClearAllPoints();
    self:SetPoint(gp.point, relativeTo, gp.xOfs, gp.yOfs);
end

function GUI:SaveGuiPoint()
    point, relativeTo, relativePoint, xOfs, yOfs = self:GetPoint();
    WBT.db.char.gui_position = {
        point = point,
        relativeToName = "UIParrent",
        relativePoint = relativePoint,
        xOfs = xOfs,
        yOfs = yOfs,
    };
end

function GUI:RecordPositioning()
    hooksecurefunc(self.frame, "StopMovingOrSizing", self.SaveGuiPoint);
end

function GUI.SetupAceGUI()
    GUI.AceGUI = LibStub("AceGUI-3.0"); -- Need to create AceGUI during/after 'OnInit' or 'OnEnabled'
end

function GUI:NewBasicWindow(width, height)
    local gui = GUI.AceGUI:Create("Window");
    gui.frame:SetFrameStrata("LOW");
    gui:SetWidth(width);
    gui:SetHeight(height);
    gui:SetCallback("OnClose", function(widget) GUI.AceGUI:Release(widget) end); -- Keep watch on this line.
    gui:SetTitle("World Boss Timers");
    gui:SetLayout("List");
    gui:EnableResize(false);

    local index_old = getmetatable(gui).__index;
    setmetatable(gui, self);
    self.__index = function(t, k)
            if type(index_old) == "table" then
                return self[k] or index_old[k];
            else
                return self[k] or index_old(t, k);
            end
        end


    return gui;
end

function GUI:New()
    local width = 200;
    local height = 110;
    local gui = GUI:NewBasicWindow(width, height);

    local btn = GUI.AceGUI:Create("Button");
    btn:SetWidth(width);
    btn:SetText("Request kill data");
    btn:SetCallback("OnClick", RequestKillData);

    local gui_container = GUI.AceGUI:Create("SimpleGroup");
    gui_container.frame:SetFrameStrata("LOW");
    gui_container:AddChild(gui);
    gui_container:AddChild(btn);

    hooksecurefunc(gui, "Show", function()
        if not gui.visible then
            gui.visible = true;
            btn.frame:Show();
        end
    end);
    hooksecurefunc(gui, "Hide", function() 
        gui.visible = false;
        btn.frame:Hide();
    end);

    gui:CreateLabels();
    gui:InitPosition();
    gui:Show();
    gui:RecordPositioning();

    gui:Update();

    gc = gui_container; -- DEBUG
    return gui;
end

local function ShowGUI()
    if not gui.visible then
        gui:Restart();
    end
end
