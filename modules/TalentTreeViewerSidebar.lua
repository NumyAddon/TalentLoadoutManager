local addonName, ns = ...;

--- @class TalentLoadoutManager
local TLM = ns.TLM;

--- @type TalentLoadoutManagerAPI_GlobalAPI
local GlobalAPI = TalentLoadoutManagerAPI.GlobalAPI;

--- @class TalentLoadoutManager_TTVSideBarModule: TalentLoadoutManager_SideBarMixin, AceModule, AceHook-3.0
local Module = TLM:NewModule("TTVSideBar", "AceHook-3.0");
TLM.TTVSideBarModule = Module;

local parentMixin = ns.SideBarMixin;
Mixin(Module, parentMixin);

Module.IntegrateWithBlizzMove = true;
Module.ImplementAutoApply = false;
Module.ShowAnimationOnImport = true;
Module.ImplementTTTMissingWarning = false;
Module.ShowLoadAndApply = false;
Module.ShowShowInTTV = false;

function Module:OnEnable()
    EventUtil.ContinueOnAddOnLoaded("TalentTreeViewer", function()
        self:SetupHook();
    end);
end

--- @return TalentViewer
function Module:GetTalentTreeViewer()
    if not TalentViewer then
        C_AddOns.LoadAddOn("TalentTreeViewer")
        if not TalentViewer then
            error("TalentTreeViewer failed to load")
        end
    end
    return TalentViewer;
end

---@return TalentViewerUIMixin
function Module:GetTalentsTab()
    return self:GetTalentTreeViewer():GetTalentFrame();
end

function Module:SetupHook()
    parentMixin.SetupHook(self);

    self:SecureHook(self:GetTalentTreeViewer(), "SelectSpec", "RefreshSideBarData");
end

function Module:GetDefaultActionText(elementData)
    return "Load";
end

function Module:UpdateCustomLoadoutWithCurrentTalents(loadoutID)
    local importString = self:GetTalentTreeViewer():ExportLoadout();
    -- todo: check if importString contains lvling info, if it doesn't, and current loadout does, show warning
    local result, errorOrNil = GlobalAPI:UpdateCustomLoadoutWithImportString(loadoutID, importString);
    if result then
        self:TryShowLoadoutCompleteAnimation();
    elseif errorOrNil then
        StaticPopup_Show(self.genericPopupDialogName, ERROR_COLOR:WrapTextInColorCode(errorOrNil));
    end
end

function Module:GetLoadouts()
    local specID = self:GetTalentTreeViewer().selectedSpecId;
    local classID = self:GetTalentTreeViewer().selectedClassId;

    return GlobalAPI:GetLoadouts(specID, classID);
end

function Module:GetActiveLoadout(forceRefresh)
    return self.activeLoadout;
end

function Module:DoLoad(loadoutID, autoApply)
    local exportString = GlobalAPI:GetExportString(loadoutID);
    self:GetTalentTreeViewer():ImportLoadout(exportString);
end

function Module:DoCreate(name)
    local importString = self:GetTalentTreeViewer():ExportLoadout();
    GlobalAPI:ImportCustomLoadout(importString, name);
end

function Module:DoImport(importText, loadoutName, autoApply)
    local loadoutInfo, errorOrNil = GlobalAPI:ImportCustomLoadout(importText, loadoutName);
    if loadoutInfo.specID ~= self:GetTalentsTab():GetSpecID() then
        self:GetTalentTreeViewer():SelectSpec(loadoutInfo.classID, loadoutInfo.specID);
    end

    return loadoutInfo, errorOrNil;
end

function Module:DoImportIntoCurrent(importText, autoApply)
    local loadoutInfo, errorOrNil =  GlobalAPI:UpdateCustomLoadoutWithImportString(self.activeLoadout.id, importText);
    if loadoutInfo.specID ~= self:GetTalentsTab():GetSpecID() then
        self:GetTalentTreeViewer():SelectSpec(loadoutInfo.classID, loadoutInfo.specID);
    end

    return loadoutInfo, errorOrNil;
end

function Module:GetBlizzMoveFrameTable()
    return {
        ['TalentTreeViewer'] = {
            ['TalentViewer_DF'] = {
                MinVersion = 100000,
                SubFrames = {
                    ['TalentViewer_DF.Talents.ButtonsParent'] = {
                        MinVersion = 100000,
                    },
                    ["TLM-TTVSideBar"] = {
                        MinVersion = 100000,
                        FrameReference = self.SideBar,
                        Detachable = true,
                    },
                },
            },
        },
    };
end
