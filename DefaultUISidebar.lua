local addonName, ns = ...;

--- @type TalentLoadoutManager
local TLM = ns.TLM;

--- @type TalentLoadoutManagerConfig
local Config = ns.Config;

--- @type TalentLoadoutManagerAPI
local API = TalentLoadoutManagerAPI;
local GlobalAPI = TalentLoadoutManagerAPI.GlobalAPI;
local CharacterAPI = TalentLoadoutManagerAPI.CharacterAPI;

local Module = TLM:NewModule("SideBar", "AceHook-3.0");
TLM.SideBarModule = Module;

local parentMixin = ns.SideBarMixin;
Mixin(Module, parentMixin);

Module.IntegrateWithBlizzMove = true;
Module.ImplementAutoApply = true;
Module.ShowAnimationOnImport = false;
Module.ImplementTTTMissingWarning = true;
Module.ShowLoadAndApply = true;
Module.ShowShowInTTV = true;

function Module:OnEnable()
    EventUtil.ContinueOnAddOnLoaded("Blizzard_ClassTalentUI", function()
        self:SetupHook();
    end);
end

function Module:OnDisable()
    parentMixin.OnDisable(self);

    API:UnregisterCallback(API.Event.CustomLoadoutApplied, self);
end

function Module:GetTalentsTab()
    return ClassTalentFrame.TalentsTab;
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

function Module:UpdateCustomLoadoutWithCurrentTalents(loadoutID)
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

function Module:GetBlizzMoveFrameTable()
    return {
        ["Blizzard_ClassTalentUI"] = {
            ["ClassTalentFrame"] =
            {
                MinVersion = 100000,
                SubFrames =
                {
                    ["ClassTalentFrame.TalentsTab.ButtonsParent"] =
                    {
                        MinVersion = 100000,
                    },
                    ["ClassTalentFrame.TalentsTab"] =
                    {
                        MinVersion = 100000,
                        SubFrames =
                        {
                            ["TLM-SideBar"] =
                            {
                                MinVersion = 100000,
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
