local addonName, ns = ...;

--- @type TalentLoadoutManager
local TLM = ns.TLM;

--- @class TalentLoadoutManagerConfig
local Config = {};
ns.Config = Config;


Config.version = C_AddOns.GetAddOnMetadata(addonName, "Version") or ""

function Config:GetOptions()
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
        },
    }

    --if not IsAddOnLoaded('TalentTreeTweaks') then
    --    options.args.disableTTTWarning = {
    --        order = orderCount(),
    --        type = "toggle",
    --        name = "Disable TTT is missing warning",
    --        desc = "Disable the warning that appears when TalentTreeTweaks is not installed.",
    --    };
    --end

    return options
end

Config.Event = { OptionValueChanged = 'OptionValueChanged' };

function Config:Initialize()
    Mixin(self, CallbackRegistryMixin);
    CallbackRegistryMixin.OnLoad(self);

    self:RegisterOptions();
    LibStub("AceConfigDialog-3.0"):AddToBlizOptions(addonName, addonName);
end

function Config:RegisterOptions()
    LibStub("AceConfig-3.0"):RegisterOptionsTable(addonName, self:GetOptions());
end

function Config:OpenConfig()
    Settings.OpenToCategory(addonName);
end

function Config:OpenConfigDialog()
    LibStub("AceConfigDialog-3.0"):Open(addonName);
end

function Config:IsOptionDisabled(option)
    if 'autoScale' == option then
        return IsAddOnLoaded('BlizzMove') or IsAddOnLoaded('TalentTreeTweaks');
    end
    if 'integrateWithSimc' == option then
        return not IsAddOnLoaded('Simulationcraft');
    end

    return false;
end

function Config:GetConfig(option, default)
    local value = not self:IsOptionDisabled(option) and TLM.db.config[option];
    if nil == value then
        value = default;
    end

    return value;
end

function Config:SetConfig(option, value)
    TLM.db.config[option] = value;

    self:TriggerEvent(self.Event.OptionValueChanged, option, value);
end