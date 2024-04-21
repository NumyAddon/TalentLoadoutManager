local addonName, ns = ...;

--- @type TalentLoadoutManager
local TLM = ns.TLM;

--- @class TalentLoadoutManagerConfig: CallbackRegistryMixin
local Config = {};
ns.Config = Config;

Config.version = C_AddOns.GetAddOnMetadata(addonName, "Version") or "";
Config.sideBarColorOptionKeys = {
    sideBarBackgroundColor = 'sideBarBackgroundColor',
    sideBarActiveElementTextColor = 'sideBarActiveElementTextColor',
    sideBarInactiveElementTextColor = 'sideBarInactiveElementTextColor',
    sideBarActiveElementBackgroundColor = 'sideBarActiveElementBackgroundColor',
    sideBarInactiveElementBackgroundColor = 'sideBarInactiveElementBackgroundColor',
    sideBarActiveElementHighlightBackgroundColor = 'sideBarActiveElementHighlightBackgroundColor',
    sideBarInactiveElementHighlightBackgroundColor = 'sideBarInactiveElementHighlightBackgroundColor',
};

function Config:Initialize()
    -- when adding options, remember to add them to types.lua (TLM_ConfigOptions) as well
    self.defaultConfig = {
        autoApplyOnLevelUp = true,
        autoScale = true,
        autoPosition = true,
        autoApply = true,
        integrateWithSimc = true,
        sideBarBackgroundColor = { r = 0, g = 0, b = 0, a = 0.8 },
        sideBarActiveElementTextColor = { r = 1, g = 1, b = 1, a = 1 },
        sideBarActiveElementBackgroundColor = { r = 0.2, g = 0.2, b = 0.2, a = 0.5 },
        sideBarActiveElementHighlightBackgroundColor = { r = 0.5, g = 0.5, b = 0.5, a = 0.5 },
        sideBarInactiveElementTextColor = { r = 1, g = 1, b = 1, a = 1 },
        sideBarInactiveElementBackgroundColor = { r = 0, g = 0, b = 0, a = 0.5 },
        sideBarInactiveElementHighlightBackgroundColor = { r = 0.5, g = 0.5, b = 0.5, a = 0.5 },
    };
    for key, value in pairs(self.defaultConfig) do
        if TLM.db.config[key] == nil then
            TLM.db.config[key] = value;
        end
    end

    Mixin(self, CallbackRegistryMixin);
    CallbackRegistryMixin.OnLoad(self);

    self:RegisterOptions();
    LibStub("AceConfigDialog-3.0"):AddToBlizOptions(addonName, addonName);
end

function Config:GetOptions()
    local function GetColor(info)
        local color = self:GetConfig(info[#info]);
        return color.r, color.g, color.b, color.a;
    end
    local function SetColor(info, r, g, b, a)
        self:SetConfig(info[#info], { r = r, g = g, b = b, a = a });
    end

    local orderCount = CreateCounter(1);
    local options = {
        type = 'group',
        get = function(info) return self:GetConfig(info[#info]) end,
        set = function(info, value) self:SetConfig(info[#info], value) end,
        disabled = function(info) return self:IsOptionDisabled(info[#info]) end,
        args = {
            version = {
                order = orderCount(),
                type = "description",
                name = "Version: " .. self.version,
            },
            levelingBuildDescription = {
                order = orderCount(),
                type = "description",
                name =
[[TalentLoadoutManager supports importing leveling builds, through any import string or ingame link that includes leveling info, or through Icy Veins calculator links.
You can create a leveling build yourself, either using the IcyVeins talent calculator, or ingame, using the Talent Tree Viewer addon
]],
            },
            autoApplyOnLevelUp = {
                order = orderCount(),
                type = "toggle",
                name = "Auto Re-Apply Loadout on Level Up",
                desc = "Automatically re-apply your current talent loadout when you level up.",
                descStyle = "inline",
                width = "full",
            },
            autoScale = {
                order = orderCount(),
                type = "toggle",
                name = "Auto Scale",
                desc = "Automatically scale the talent frame to fit the screen. (disabled if BlizzMove or TalentTreeTweaks is loaded)",
                descStyle = "inline",
                width = "full",
            },
            autoPosition = {
                order = orderCount(),
                type = "toggle",
                name = "Auto Position",
                desc = "Automatically reposition the talent frame to the center of the screen.",
                descStyle = "inline",
                width = "full",
            },
            autoApply = {
                order = orderCount(),
                type = "toggle",
                name = "Auto Apply",
                desc = "Automatically apply the talent loadout when you import or switch talents.",
                descStyle = "inline",
                width = "full",
            },
            integrateWithSimc = {
                order = orderCount(),
                type = "toggle",
                name = "Add to SimC",
                desc = "Automatically add custom talent loadouts to the SimulationCraft addon when /simc is used.",
                descStyle = "inline",
                width = "full",
            },
            sideBarColors = {
                order = orderCount(),
                type = "description",
                name = "Sidebar Colors",
                width = "full",
            },
            sideBarActiveElementTextColor = {
                order = orderCount(),
                type = 'color',
                name = 'Selected Loadout Text',
                desc = 'The text color of the selected loadout in the side bar.',
                set = SetColor,
                get = GetColor,
                hasAlpha = true,
            },
            sideBarActiveElementBackgroundColor = {
                order = orderCount(),
                type = 'color',
                name = 'Selected Loadout Background',
                desc = 'The background color of the selected loadout in the side bar.',
                set = SetColor,
                get = GetColor,
                hasAlpha = true,
            },
            sideBarActiveElementHighlightBackgroundColor = {
                order = orderCount(),
                type = 'color',
                name = 'Selected Loadout Highlight',
                desc = 'The background color of the selected loadout in the side bar when hovered.',
                set = SetColor,
                get = GetColor,
                hasAlpha = true,
            },
            sideBarInactiveElementTextColor = {
                order = orderCount(),
                type = 'color',
                name = 'Loadout Text',
                desc = 'The text color of loadouts in the side bar.',
                set = SetColor,
                get = GetColor,
                hasAlpha = true,
            },
            sideBarInactiveElementBackgroundColor = {
                order = orderCount(),
                type = 'color',
                name = 'Loadout Background',
                desc = 'The background color of loadouts in the side bar.',
                set = SetColor,
                get = GetColor,
                hasAlpha = true,
            },
            sideBarInactiveElementHighlightBackgroundColor = {
                order = orderCount(),
                type = 'color',
                name = 'Loadout Highlight Background',
                desc = 'The background color of loadouts in the side bar when hovered.',
                set = SetColor,
                get = GetColor,
                hasAlpha = true,
            },
            sideBarBackgroundColor = {
                order = orderCount(),
                type = 'color',
                name = 'Sidebar Background',
                desc = 'The background color of the side bar.',
                set = SetColor,
                get = GetColor,
                hasAlpha = true,
            },
            resetAllColors = {
                order = orderCount(),
                type = "execute",
                name = "Reset All Colors",
                desc = "Reset all side bar colors to their defaults.",
                func = function()
                    for _, key in pairs(self.sideBarColorOptionKeys) do
                        print(key, self.defaultConfig[key].r, self.defaultConfig[key].g, self.defaultConfig[key].b, self.defaultConfig[key].a);
                        self:SetConfig(key, self.defaultConfig[key]);
                    end
                end,
            },
        },
    };

    return options
end

Config.Event = { OptionValueChanged = 'OptionValueChanged' };

function Config:RegisterOptions()
    LibStub("AceConfig-3.0"):RegisterOptionsTable(addonName, self:GetOptions());
end

function Config:OpenConfig()
    Settings.OpenToCategory(addonName);
end

function Config:OpenConfigDialog()
    LibStub("AceConfigDialog-3.0"):Open(addonName);
end

--- @param option TLM_ConfigOptions
function Config:IsOptionDisabled(option)
    if 'autoScale' == option then
        return IsAddOnLoaded('BlizzMove') or IsAddOnLoaded('TalentTreeTweaks');
    end
    if 'integrateWithSimc' == option then
        return not IsAddOnLoaded('Simulationcraft');
    end

    return false;
end

--- @param option TLM_ConfigOptions
function Config:GetConfig(option, default)
    local value = not self:IsOptionDisabled(option) and TLM.db.config[option];
    if nil == value then
        value = default;
    end

    return value;
end

--- @param option TLM_ConfigOptions
function Config:SetConfig(option, value)
    TLM.db.config[option] = value;

    self:TriggerEvent(self.Event.OptionValueChanged, option, value);
end