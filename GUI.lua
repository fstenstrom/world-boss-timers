-- ----------------------------------------------------------------------------
--  A persistent timer for World Bosses.
-- ----------------------------------------------------------------------------

-- addonName, addonTable = ...;
local _, WBT = ...;

local Util = WBT.Util;
local BossData = WBT.BossData;

local GUI = {};
WBT.GUI = GUI;


local EmptyGUI = {};
function EmptyGUI:New()
    egui = {};
    setmetatable(egui, self);
    self.__index = self;

    return egui;
end

function EmptyGUI:UpdateGUIVisibility()
    if WBT.db.global.hide_gui == false then
        WBT.gui = GUI:New();
    end
end

function EmptyGUI:Update() return end
function EmptyGUI:SaveGuiPoint() return end
function EmptyGUI:RecordPositioning() return end
function EmptyGUI.SetupAceGUI() return end
function EmptyGUI:NewBasicWindow(width, height) print("bad"); return end

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
    return (WBT.IsBossZone() or WBT.AnyDead()) and not(self.visible) and not(WBT.db.global.hide_gui);
end

function GUI:ShouldHide()
    return (not(WBT.IsBossZone() or WBT.AnyDead()) or WBT.db.global.hide_gui) and self.visible;
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

-- Make sure that the AceGUI widgets are restored before
-- they are returned to the widget pool.
function GUI:CleanUpWidgetAndRelease()
    print ("CLEANING");
    -- Restore metatable:
    setmetatable(self, self.metatable_window);

    -- Release container and children as well (btn, gui, labels).
    GUI.AceGUI:Release(self.gui_container); 

    -- Remove references to fields. Hopefully the widget is
    -- not reassigned from the pool before this method
    -- finishes.
    self.labels = nil;
    self.visible = nil;
    self.metatable_window = nil;
    self.gui_container = nil;

    WBT.gui = EmptyGUI:New();
end

function GUI:NewBasicWindow(width, height)
    local gui = GUI.AceGUI:Create("Window");
    gui.metatable_window = getmetatable(gui);

    gui.frame:SetFrameStrata("LOW");
    gui:SetWidth(width);
    gui:SetHeight(height);

    gui:SetCallback("OnClose", function(widget)
        print ("ONCLOSE");
        widget:CleanUpWidgetAndRelease();
        WBT.db.global.hide_gui = true;
    end);

    gui:SetTitle("World Boss Timers");
    gui:SetLayout("List");
    gui:EnableResize(false);

    gui.visible = false;

    local index_old = getmetatable(gui).__index;
    if index_old then
        print("ind: ", index_old);
    end
    setmetatable(gui, self);
    self.__index = function(t, k)
            if type(index_old) == "table" then
                return self[k] or index_old[k];
            else
                return self[k] or index_old(t, k);
            end
        end

    print ("func: ", gui.CreateLabels);

    return gui;
end

function GUI:New()
    if self and self.gui_container then
        self:CleanUpWidgetAndRelease();
    end
    
    local width = 200;
    local height = 110;
    print ("b");
    local gui = GUI:NewBasicWindow(width, height);
    print ("a");
    print ("New: createlabels: ", gui.CreateLabels);

    local btn = GUI.AceGUI:Create("Button");
    btn:SetWidth(width);
    btn:SetText("Request kill data");
    btn:SetCallback("OnClick", WBT.RequestKillData);

    print ("New: createlabels: ", gui.CreateLabels);
    local gui_container = GUI.AceGUI:Create("SimpleGroup");
    print ("New: createlabels: ", gui.CreateLabels);
    gui_container.frame:SetFrameStrata("LOW");
    print ("New: createlabels: ", gui.CreateLabels);
    gui_container:AddChild(gui);
    print ("New: createlabels: ", gui.CreateLabels);
    gui_container:AddChild(btn);

    print ("New: createlabels: ", gui.CreateLabels);
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

    print ("New: createlabels: ", gui.CreateLabels);
    gui:CreateLabels();
    gui:InitPosition();
    gui:Show();
    gui:RecordPositioning();

    gui:Update();

    gui.gui_container = gui_container; -- Need a pointer to the container so it can be released.
    return gui;
end

local function ShowGUI()
    if not gui.visible then
        gui:Restart();
    end
end
