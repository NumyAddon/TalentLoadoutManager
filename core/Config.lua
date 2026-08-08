local addonName, ns = ...;

--- @type TalentLoadoutManager
local TLM = ns.TLM;
local L = ns.L;

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
    --- @class TLM_Config
    --- @enum (key) TLM_ConfigOptions
    self.defaultConfig = {
        autoApplyOnLevelUp = true,
        autoScale = true,
        autoPosition = true,
        autoApply = true,
        integrateWithSimc = true,
        characterVisibility = {},

        sideBarBackgroundColor = { r = 0, g = 0, b = 0, a = 0.8 },

        sideBarActiveElementTextColor = { r = 1, g = 1, b = 1, a = 1 },
        sideBarActiveElementBackgroundColor = { r = 0.08, g = 0.5, b = 0.17, a = 0.5 },
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
    if not TLM.db.config._changedActiveElementBackgroundToGreen then
        local color = TLM.db.config.sideBarActiveElementBackgroundColor;
        if color.r == 0.2 and color.g == 0.2 and color.b == 0.2 and color.a == 0.5 then
            TLM.db.config.sideBarActiveElementBackgroundColor = self.defaultConfig.sideBarActiveElementBackgroundColor;
        end
        TLM.db.config._changedActiveElementBackgroundToGreen = true;
    end

    Mixin(self, CallbackRegistryMixin);
    CallbackRegistryMixin.OnLoad(self);

    self:RegisterOptions();
    local _, categoryID = LibStub("AceConfigDialog-3.0"):AddToBlizOptions(addonName, addonName);
    self.categoryID = categoryID;
end

function Config:GetOptions()
    local function GetColor(info)
        --- @type ColorRGBAData
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
                name = L["Version: %s"]:format(self.version),
            },
            levelingBuildDescription = {
                order = orderCount(),
                type = "description",
                name = L["Leveling build description"],
            },
            autoApplyOnLevelUp = {
                order = orderCount(),
                type = "toggle",
                name = L["Auto Re-Apply Loadout on Level Up"],
                desc = L["Auto Re-Apply Loadout on Level Up desc"],
                descStyle = "inline",
                width = "full",
            },
            autoScale = {
                order = orderCount(),
                type = "toggle",
                name = L["Auto Scale"],
                desc = L["Auto Scale desc"],
                descStyle = "inline",
                width = "full",
            },
            autoPosition = {
                order = orderCount(),
                type = "toggle",
                name = L["Auto Position"],
                desc = L["Auto Position desc"],
                descStyle = "inline",
                width = "full",
            },
            autoApply = {
                order = orderCount(),
                type = "toggle",
                name = L["Auto Apply"],
                desc = L["Auto Apply desc"],
                descStyle = "inline",
                width = "full",
            },
            integrateWithSimc = {
                order = orderCount(),
                type = "toggle",
                name = L["Add to SimC"],
                desc = L["Add to SimC desc"],
                descStyle = "inline",
                width = "full",
            },
            resetCharacterVisibility = {
                order = orderCount(),
                type = "execute",
                name = L["Reset Hidden Characters"],
                desc = L["Reset Hidden Characters desc"],
                func = function() self:ClearCharacterVisibility(); end,
                width = "double",
            },
            sideBarColors = {
                order = orderCount(),
                type = "description",
                name = L["Sidebar Colors"],
                width = "full",
            },
            sideBarActiveElementTextColor = {
                order = orderCount(),
                type = 'color',
                name = L["Selected Loadout Text"],
                desc = L["Selected Loadout Text desc"],
                set = SetColor,
                get = GetColor,
                hasAlpha = true,
            },
            sideBarActiveElementBackgroundColor = {
                order = orderCount(),
                type = 'color',
                name = L["Selected Loadout Background"],
                desc = L["Selected Loadout Background desc"],
                set = SetColor,
                get = GetColor,
                hasAlpha = true,
            },
            sideBarActiveElementHighlightBackgroundColor = {
                order = orderCount(),
                type = 'color',
                name = L["Selected Loadout Highlight"],
                desc = L["Selected Loadout Highlight desc"],
                set = SetColor,
                get = GetColor,
                hasAlpha = true,
            },
            sideBarInactiveElementTextColor = {
                order = orderCount(),
                type = 'color',
                name = L["Loadout Text"],
                desc = L["Loadout Text desc"],
                set = SetColor,
                get = GetColor,
                hasAlpha = true,
            },
            sideBarInactiveElementBackgroundColor = {
                order = orderCount(),
                type = 'color',
                name = L["Loadout Background"],
                desc = L["Loadout Background desc"],
                set = SetColor,
                get = GetColor,
                hasAlpha = true,
            },
            sideBarInactiveElementHighlightBackgroundColor = {
                order = orderCount(),
                type = 'color',
                name = L["Loadout Highlight"],
                desc = L["Loadout Highlight desc"],
                set = SetColor,
                get = GetColor,
                hasAlpha = true,
            },
            sideBarBackgroundColor = {
                order = orderCount(),
                type = 'color',
                name = L["Sidebar Background"],
                desc = L["Sidebar Background desc"],
                set = SetColor,
                get = GetColor,
                hasAlpha = true,
            },
            resetAllColors = {
                order = orderCount(),
                type = "execute",
                name = L["Reset All Colors"],
                desc = L["Reset All Colors desc"],
                func = function()
                    for _, key in pairs(self.sideBarColorOptionKeys) do
                        print(key, self.defaultConfig[key].r, self.defaultConfig[key].g, self.defaultConfig[key].b, self.defaultConfig[key].a);
                        self:SetConfig(key, self.defaultConfig[key]);
                    end
                end,
            },
        },
    };

    return options;
end

Config.Event = {
    OptionValueChanged = 'OptionValueChanged',
    CharacterVisibilityChanged = 'CharacterVisibilityChanged',
};

function Config:RegisterOptions()
    LibStub("AceConfig-3.0"):RegisterOptionsTable(addonName, self:GetOptions());
end

function Config:OpenConfig()
    if C_SettingsUtil and C_SettingsUtil.OpenSettingsPanel and InCombatLockdown() then
        self:OpenConfigDialog();
        return;
    end
    Settings.OpenToCategory(self.categoryID);
end

function Config:OpenConfigDialog()
    LibStub("AceConfigDialog-3.0"):Open(addonName);
end

--- @param option TLM_ConfigOptions
function Config:IsOptionDisabled(option)
    if 'autoScale' == option then
        return C_AddOns.IsAddOnLoaded('BlizzMove') or C_AddOns.IsAddOnLoaded('TalentTreeTweaks');
    end
    if 'integrateWithSimc' == option then
        return not C_AddOns.IsAddOnLoaded('Simulationcraft');
    end

    return false;
end

function Config:ClearCharacterVisibility()
    TLM.db.config.characterVisibility = {};
    self:TriggerEvent(self.Event.CharacterVisibilityChanged);
end

function Config:SetCharacterShown(characterName, isShown)
    TLM.db.config.characterVisibility[characterName] = isShown;
    self:TriggerEvent(self.Event.CharacterVisibilityChanged);
end

function Config:IsCharacterShown(characterName)
    return TLM.db.config.characterVisibility[characterName] ~= false;
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