local addonName, ns = ...;

--- @class TalentLoadoutManager
local TLM = ns.TLM;

--- @type TalentLoadoutManagerConfig
local Config = ns.Config;

--- @type TalentLoadoutManagerAPI
local API = TalentLoadoutManagerAPI;
local GlobalAPI = TalentLoadoutManagerAPI.GlobalAPI;
local CharacterAPI = TalentLoadoutManagerAPI.CharacterAPI;

--- @class TLM_DefaultUISideBarModule: TLM_SideBarMixin, AceModule, AceHook-3.0
local Module = TLM:NewModule("SideBar", "AceHook-3.0");
TLM.SideBarModule = Module;

local parentMixin = ns.SideBarMixin;
Mixin(Module, parentMixin);

Module.IntegrateWithBlizzMove = true;
Module.ImplementAutoApply = true;
Module.ShowAnimationOnImport = false;
Module.ImplementTTTMissingWarning = false;
Module.ShowLoadAndApply = true;
Module.ShowShowInTTV = true;

function Module:OnEnable()
    EventUtil.ContinueOnAddOnLoaded("Blizzard_ClassTalentUI", function()
        self:SetupHook();
    end);
    EventUtil.ContinueOnAddOnLoaded("Blizzard_PlayerSpells", function()
        self:SetupHook();
    end);
end

function Module:OnDisable()
    parentMixin.OnDisable(self);

    API:UnregisterCallback(API.Event.CustomLoadoutApplied, self);
end

--- @return PlayerSpellsFrame_TalentsFrame
function Module:GetTalentsTab()
    return PlayerSpellsFrame.TalentsFrame;
end

function Module:SetupHook()
    parentMixin.SetupHook(self);

    API:RegisterCallback(API.Event.CustomLoadoutApplied, self.RefreshSideBarData, self);
end

function Module:GetDefaultActionText(elementData)
    return (elementData.data.playerIsOwner and elementData.data.isBlizzardLoadout) and "Load & Apply"
        or Config:GetConfig('autoApply') and "Load & Apply"
        or "Load";
end

function Module:GetExportString()
    return C_Traits.GenerateImportString(C_ClassTalents.GetActiveConfigID());
end

function Module:UpdateCustomLoadoutWithCurrentTalents(loadoutID)
    -- todo: add warning if the loadout has leveling information, as that'll get lost
    CharacterAPI:UpdateCustomLoadoutWithCurrentTalents(loadoutID);
    self:TryShowLoadoutCompleteAnimation();
end

function Module:GetLoadouts()
    return GlobalAPI:GetLoadouts();
end

function Module:GetActiveLoadout(forceRefresh)
    if forceRefresh then
        self.activeLoadout = CharacterAPI:GetActiveLoadoutInfo();
    end

    return self.activeLoadout;
end

function Module:DoLoad(loadoutID, autoApply)
    CharacterAPI:LoadLoadout(loadoutID, autoApply);
end

function Module:DoCreate(name)
    CharacterAPI:CreateCustomLoadoutFromCurrentTalents(name);
end

function Module:DoImport(importText, loadoutName, autoApply)
    return CharacterAPI:ImportCustomLoadout(importText, loadoutName, autoApply);
end

function Module:DoImportIntoCurrent(importText, autoApply)
    local result, errorOrNil = GlobalAPI:UpdateCustomLoadoutWithImportString(self.activeLoadout.id, importText);
    if autoApply and result and not errorOrNil then
        CharacterAPI:LoadLoadout(self.activeLoadout.id, autoApply);
    end

    return result, errorOrNil;
end

--- @return BlizzMoveAPI_AddonFrameTable
function Module:GetBlizzMoveFrameTable()
    --- @type BlizzMoveAPI_AddonFrameTable
    return {
        ["Blizzard_PlayerSpells"] = {
            ["PlayerSpellsFrame"] = {
                MinVersion = 110000,
                SubFrames = {
                    ["PlayerSpellsFrame.TalentsFrame.ButtonsParent"] = {
                        MinVersion = 110000,
                    },
                    ["PlayerSpellsFrame.TalentsFrame"] = {
                        MinVersion = 110000,
                        SubFrames = {
                            ["TLM-SideBar"] = {
                                FrameReference = self.SideBar,
                                Detachable = true,
                            },
                        },
                    },
                },
            },
        },
    };
end
