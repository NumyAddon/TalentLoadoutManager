local addonName, ns = ...;

--- @class TalentLoadoutManager
local TLM = ns.TLM;

--- @type TalentLoadoutManagerAPI_GlobalAPI
local GlobalAPI = TalentLoadoutManagerAPI.GlobalAPI;

--- @class TLM_TTVSideBarModule: TLM_SideBarMixin, AceModule, AceHook-3.0
local Module = TLM:NewModule("TTVSideBar", "AceHook-3.0");
TLM.TTVSideBarModule = Module;

--- @type TLM_SideBarMixin
local parentMixin = ns.SideBarMixin;
Mixin(Module, parentMixin);

Module.IntegrateWithBlizzMove = true;
Module.ImplementAutoApply = false;
Module.ShowAnimationOnImport = true;
Module.ImplementTTTMissingWarning = false;
Module.ShowLoadAndApply = false;
Module.ShowShowInTTV = false;

function Module:OnEnable()
    EventUtil.ContinueOnAddOnLoaded(TalentViewerLoader and TalentViewerLoader:GetLodAddonName() or 'TalentTreeViewer', function()
        self:SetupHook();
    end);
end

--- @return TalentViewerTWW
function Module:GetTalentTreeViewer()
    return TalentViewerLoader:GetTalentViewer();
end

---@return TalentViewer_ClassTalentsFrameTemplate
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

function Module:GetExportString()
    return self:GetTalentTreeViewer():ExportLoadout();
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
    if forceRefresh and self.activeLoadout and self.activeLoadout.id then
        return GlobalAPI:GetLoadoutInfoByID(self.activeLoadout.id);
    end
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

--- @return BlizzMoveAPI_AddonFrameTable
function Module:GetBlizzMoveFrameTable()
    --- @type BlizzMoveAPI_AddonFrameTable
    return {
        [TalentViewerLoader and TalentViewerLoader:GetLodAddonName() or 'TalentTreeViewer'] = {
            ['TalentViewer_DF'] = {
                SubFrames = {
                    ['TalentViewer_DF.Talents.ButtonsParent'] = {},
                    ["TLM-TTVSideBar"] = {
                        FrameReference = self.SideBar,
                        Detachable = true,
                    },
                },
            },
        },
    };
end
