local _, WBT = ...;

local Config = {};
WBT.Config = Config;

local GUI = WBT.GUI;
local Util = WBT.Util;

Config.SOUND_CLASSIC = "classic";
Config.SOUND_FANCY = "fancy";

local CYCLIC_HELP_TEXT = "This mode will repeat the boss timers if you miss the kill. A timer in " ..
        Util.ColoredString(Util.COLOR_RED, "red text") ..
        " indicates cyclic mode. By clicking a boss's name in the timer window you can reset it permanently.";

----- Setters and Getters for options -----

local ConfigItem = {};

function ConfigItem.CreateDefaultGetter(var_name)
    local function getter()
        return WBT.db.global[var_name];
    end
    return getter;
end

function ConfigItem.CreateDefaultSetter(var_name)
    local function setter(state)
        WBT.db.global[var_name] = state;
        WBT.GUI:Update();
    end
    return setter;
end

function ConfigItem:New(var_name, status_msg)
    local ci = {
        get = ConfigItem.CreateDefaultGetter(var_name);
        set = ConfigItem.CreateDefaultSetter(var_name);
        msg = status_msg,
    };

    setmetatable(ci, self);
    self.__index = self;

    return ci;
end

function ConfigItem.GetColoredStatus(status_var)
    local color = Util.COLOR_RED;
    local status = "disabled";
    if status_var then
        color = Util.COLOR_GREEN;
        status = "enabled";
    end

    return color .. status .. Util.COLOR_DEFAULT;
end

function ConfigItem:PrintFormattedStatus(status_var)
    WBT:Print(self.msg .. " " .. self.GetColoredStatus(status_var) .. ".");
end

function ConfigItem:Toggle()
    local new_state = not self.get();
    self.set(new_state);
    self:PrintFormattedStatus(new_state);
end

Config.send_data = ConfigItem:New("send_data", "Data sending in auto announce is now");
Config.auto_announce = ConfigItem:New("auto_announce", "Automatic announcements are now");
Config.sound = ConfigItem:New("sound_enabled", "Sound is now");
Config.multi_realm = ConfigItem:New("multi_realm", "Multi-Realm/Warmode option is now");
Config.show_boss_zone_only = ConfigItem:New("show_boss_zone_only", "Only show GUI in boss zone mode is now");
Config.cyclic = ConfigItem:New("cyclic", "Cyclic mode is now");
 -- Wrapping in some help printing for cyclic mode.
local cyclic_set_temp = Config.cyclic.set;
Config.cyclic.set = function(state) cyclic_set_temp(state); WBT:Print(CYCLIC_HELP_TEXT); end


----- Slash commands -----

local function PrintHelp()
    WBT.AceConfigDialog:Open(WBT.addon_name);
    local indent = "   ";
    WBT:Print("WorldBossTimers slash commands:");
    WBT:Print("/wbt reset --> Reset all kill info.");
    WBT:Print("/wbt gui-reset --> Reset the position of the GUI.");
    WBT:Print("/wbt saved --> Print your saved bosses.");
    WBT:Print("/wbt say --> Announce timers for boss in zone.");
    WBT:Print("/wbt show --> Show the timers frame.");
    WBT:Print("/wbt hide --> Hide the timers frame.");
    WBT:Print("/wbt send --> Toggle send timer data in auto announce.");
    WBT:Print("/wbt sound --> Toggle sound alerts.");
    --WBT:Print("/wbt sound classic --> Sets sound to \'War Drums\'.");
    --WBT:Print("/wbt sound fancy --> Sets sound to \'fancy mode\'.");
    WBT:Print("/wbt ann --> Toggle automatic announcements.");
    WBT:Print("/wbt cyclic --> Toggle cyclic timers.");
    WBT:Print("/wbt multi --> Toggle multi-realm/warmode timers.");
    WBT:Print("/wbt zone --> Toggle show GUI in boss zones only.");
end

local function ShowGUI(show)
    local gui = GUI;
    if show then
        WBT.db.global.hide_gui = false;
        if gui:ShouldShow() then
            gui:Show();
        else
            WBT:Print("The GUI will show when next you enter a boss zone.");
        end
    else
        WBT.db.global.hide_gui = true;
        gui:Hide();
    end
    gui:Update();
end

function Config.SlashHandler(input)
    arg1, arg2 = strsplit(" ", input);

    if arg1 == "hide" then
        ShowGUI(false);
    elseif arg1 == "show" then
        ShowGUI(true);
    elseif arg1 == "say"
        or arg1 == "share"
        or arg1 == "a"
        or arg1 == "announce"
        or arg1 == "yell"
        or arg1 == "tell" then

        if not WBT.InBossZone() then
            WBT:Print("You can't announce outside of a boss zone.");
            return;
        end

        local ki = WBT.KillInfoInCurrentZoneAndShard();
        if not ki or not(ki:IsValid()) then
            local msg = "No spawn timer for ";
            for _, boss in pairs(WBT.BossesInCurrentZone()) do
                msg = msg .. WBT.GetColoredBossName(boss.name) .. ", "
            end
            msg = msg:sub(0, -3); -- Remove the trailing ', '.

            WBT:Print(msg);
            return;
        end

        local error_msgs = {};
        if ki:IsCompletelySafe(error_msgs) then
            WBT.AnnounceSpawnTime(ki, Config.send_data.get());
        else
            WBT:Print(Util.ColoredString(Util.COLOR_RED, "WARNING") .. ": Timer might be incorrect. Not announcing.", "SAY", nil, nil);
            for i, v in ipairs(error_msgs) do
                WBT:Print(Util.ColoredString(Util.COLOR_RED, i) .. ": " .. v, "SAY", nil, nil);
            end
        end
    elseif arg1 == "send" then
        Config.send_data:Toggle();
    elseif arg1 == "ann" then
        Config.auto_announce:Toggle();
    elseif arg1 == "r"
        or arg1 == "reset"
        or arg1 == "restart" then
        WBT.ResetKillInfo();
    elseif arg1 == "s"
        or arg1 == "saved"
        or arg1 == "save" then
        WBT.PrintKilledBosses();
    elseif arg1 == "request" then
        WBT.RequestKillData();
    elseif arg1 == "sound" then
        sound_type_args = {Config.SOUND_CLASSIC, Config.SOUND_FANCY};
        if Util.SetContainsValue(sound_type_args, arg2) then
            WBT.db.global.sound_type = arg2;
            WBT:Print("SoundType: " .. arg2);
        else
            Config.sound:Toggle();
        end
    elseif arg1 == "cyclic" then
        Config.cyclic:Toggle();
        WBT.GUI:Update();
    elseif arg1 == "multi" then
        Config.multi_realm:Toggle();
        WBT.GUI:Update();
    elseif arg1 == "zone" then
        Config.show_boss_zone_only:Toggle();
        WBT.GUI:Update();
    elseif arg1 == "gui-reset" then
        WBT.GUI:ResetPosition();
    else
        PrintHelp();
    end
end


----- Options table -----
desc_toggle = "Enable/Disable";
Config.optionsTable = {
  type = "group",
  args = {
    show = {
        name = "Show GUI",
        order = 1,
        desc = desc_toggle,
        type = "toggle",
        width = "full",
        set = function(info, val) ShowGUI(val) end,
        get = function(info) return not WBT.db.global.hide_gui; end
    },
    show_boss_zone_only = {
        name = "Only show the GUI when in a boss zone",
        order = 2,
        desc = desc_toggle,
        type = "toggle",
        width = "full",
        set = function(info, val) Config.show_boss_zone_only:Toggle(); end,
        get = function(info) return Config.show_boss_zone_only.get() end,
    },
    sound = {
        name = "Sound",
        order = 3,
        desc = desc_toggle,
        type = "toggle",
        width = "full",
        set = function(info, val) Config.sound:Toggle(); end,
        get = function(info) return Config.sound.get() end,
    },
    cyclic = {
        name = "Cyclic timers (show expired timers)",
        order = 4,
        desc = desc_toggle,
        type = "toggle",
        width = "full",
        set = function(info, val) Config.cyclic:Toggle(); end,
        get = function(info) return Config.cyclic.get(); end,
    },
    auto_send_data = {
        name = "Send timer info in auto announcements",
        order = 5,
        desc = desc_toggle,
        type = "toggle",
        width = "full",
        set = function(info, val) Config.send_data:Toggle(); end,
        get = function(info) return Config.send_data.get() end,
    },
    auto_announce = {
        name = "Auto announce at certain time intervals",
        order = 6,
        desc = desc_toggle,
        type = "toggle",
        width = "full",
        set = function(info, val) Config.auto_announce:Toggle(); end,
        get = function(info) return Config.auto_announce.get() end,
    },
    multi_realm = {
        name = "Allow tracking across multiple Realms (and multiple Warmode settings on the same Realm)",
        order = 7,
        desc = desc_toggle,
        type = "toggle",
        width = "full",
        set = function(info, val) Config.multi_realm:Toggle(); end,
        get = function(info) return Config.multi_realm.get() end,
    },
  }
}

