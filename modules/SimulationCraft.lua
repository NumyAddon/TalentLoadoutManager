local addonName, ns = ...;

--- @type TalentLoadoutManager
local TLM = ns.TLM;

--- @type TalentLoadoutManagerConfig
local Config = ns.Config;

--- @type TalentLoadoutManagerAPI
local API = TalentLoadoutManagerAPI;
local GlobalAPI = TalentLoadoutManagerAPI.GlobalAPI;
local CharacterAPI = TalentLoadoutManagerAPI.CharacterAPI;

local Module = TLM:NewModule("SimulationCraftPlugin", "AceHook-3.0");

function Module:OnInitialize()
    EventUtil.ContinueOnAddOnLoaded("SimulationCraft", function()
        self:OnSimulationCraftLoaded();
    end);
end

function Module:OnSimulationCraftLoaded()
    self.simc = LibStub("AceAddon-3.0"):GetAddon("Simulationcraft");
    if not self.simc then
        return;
    end

    self:SecureHook(self.simc, "PrintSimcProfile");
end

-- Adapted from https://github.com/philanc/plc/blob/master/plc/checksum.lua
local function adler32(s)
    -- return adler32 checksum  (uint32)
    -- adler32 is a checksum defined by Mark Adler for zlib
    -- (based on the Fletcher checksum used in ITU X.224)
    -- implementation based on RFC 1950 (zlib format spec), 1996
    local prime = 65521 --largest prime smaller than 2^16
    local s1, s2 = 1, 0

    -- limit s size to ensure that modulo prime can be done only at end
    -- 2^40 is too large for WoW Lua so limit to 2^30
    if #s > (bit.lshift(1, 30)) then error("adler32: string too large") end

    for i = 1,#s do
        local b = string.byte(s, i)
        s1 = s1 + b
        s2 = s2 + s1
        -- no need to test or compute mod prime every turn.
    end

    s1 = s1 % prime
    s2 = s2 % prime

    return (bit.lshift(s2, 16)) + s1
end

function Module:PrintSimcProfile()
    if not self.simc then return; end
    if not Config:GetConfig('integrateWithSimc') then return; end

    --- @type EditBox|nil
    local SimcEditBox = SimcEditBox;
    local text = SimcEditBox and SimcEditBox.GetText and SimcEditBox:GetText();
    if not SimcEditBox or not text then return; end

    -- strip out the final '# Checksum: {hash}' line
    local hash = text:match("# Checksum: (%x+)$");
    if not hash then return; end

    text = text:gsub("# Checksum: %x+$", "");

    local customLoadoutsString = "";
    local customLoadoutsChecksumString = "";
    for _, loadout in ipairs(GlobalAPI:GetLoadouts()) do
        if not loadout.isBlizzardLoadout or not loadout.playerIsOwner then
            local importString = GlobalAPI:GetExportString(loadout.id, true);
            customLoadoutsString = string.format(
                "%s# Saved Loadout: %s\n# talents=%s\n",
                customLoadoutsString,
                loadout.name,
                importString
            );
            customLoadoutsChecksumString = string.format(
                "%s# Saved Loadout: %s\n# talents=%s\n",
                customLoadoutsChecksumString,
                loadout.name:gsub("||", "|"),
                importString
            );
        end
    end

    if customLoadoutsString == "" then return; end

    -- calculate the new checksum
    local checksum = adler32(text .. customLoadoutsChecksumString .. "\n");
    text = text .. customLoadoutsString .. "\n" .. "# Checksum: " .. string.format('%x', checksum);

    -- update the simc edit box
    SimcEditBox:SetText(text);
    SimcEditBox:HighlightText();
end
