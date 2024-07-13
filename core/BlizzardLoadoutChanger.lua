local addonName, ns = ...;

--- @class TalentLoadoutManager
local TLM = ns.TLM;

--- @class TLM_BlizzardLoadoutChanger: AceModule, AceEvent-3.0
local Module = TLM:NewModule("BlizzardLoadoutChanger", "AceEvent-3.0");
TLM.BlizzardLoadoutChanger = Module;

local GetStagedChanges = C_Traits.GetStagedChanges or C_Traits.GetStagedPurchases;
local starterConfigID = Constants.TraitConsts.STARTER_BUILD_TRAIT_CONFIG_ID;

function Module:OnInitialize()
    self:RegisterEvent('SPELLS_CHANGED');

    self.ignoreHook = false;
    hooksecurefunc(C_ClassTalents, 'UpdateLastSelectedSavedConfigID', function()
        if self.ignoreHook then return; end
        self:UpdateCurrentConfigID();
    end)
end

function Module:UpdateCurrentConfigID()
    self.currentConfigID = C_ClassTalents.GetLastSelectedSavedConfigID(PlayerUtil.GetCurrentSpecID())
        or (C_ClassTalents.GetStarterBuildActive() and starterConfigID);
end

--- @return FRAME?
function Module:GetTalentFrame()
    return (ClassTalentFrame and ClassTalentFrame.TalentsTab) or (PlayerSpellsFrame and PlayerSpellsFrame.TalentsFrame);
end

function Module:TryRefreshTalentUI()
    local talentsTab = self:GetTalentFrame();
    if not InCombatLockdown() and talentsTab and talentsTab:IsVisible() then
        talentsTab:Hide();
        talentsTab:Show();
    end
end

local function secureSetNil(table, key)
    TextureLoadingGroupMixin.RemoveTexture({textures = table}, key);
end
function Module:UpdateLastSelectedSavedConfigID(configID)
    self.ignoreHook = true;
    C_ClassTalents.UpdateLastSelectedSavedConfigID(PlayerUtil.GetCurrentSpecID(), configID);
    self.ignoreHook = false;

    -- this horrible workaround should not be needed once blizzard actually fires SELECTED_LOADOUT_CHANGED event
    -- or you know.. realizes that it's possible for addons to change the loadout, but we can't do that without tainting all the things
    local talentsTab = self:GetTalentFrame();
    local dropdown = talentsTab.LoadoutDropDown or talentsTab.LoadSystem;
    local _ = dropdown and dropdown.SetSelectionID and dropdown:SetSelectionID(configID);

    if true then return end -- disable this for now, needs more testing
    -- this seems to reduce the amount of tainted values, but I didn't really dig into it
    local _ = dropdown and dropdown.DropDownControl and secureSetNil(dropdown.DropDownControl, 'selectedValue');
end

function Module:SPELLS_CHANGED()
    self:UnregisterEvent('SPELLS_CHANGED');

    self:UpdateCurrentConfigID();

    self:RegisterEvent('TRAIT_CONFIG_UPDATED');
    self:RegisterEvent('CONFIG_COMMIT_FAILED');
    self:RegisterEvent('ACTIVE_PLAYER_SPECIALIZATION_CHANGED');
end

function Module:ACTIVE_PLAYER_SPECIALIZATION_CHANGED()
    self:UpdateCurrentConfigID();
end

function Module:TRAIT_CONFIG_UPDATED(_, configID)
    if configID ~= C_ClassTalents.GetActiveConfigID() then return; end
    if self.updatePending then
        local pendingConfigID = self.pendingConfigID;
        local pendingDisableStarterBuild = self.pendingDisableStarterBuild;
        RunNextFrame(function()
            self.updatePending = false;
            if pendingDisableStarterBuild then
                C_ClassTalents.SetStarterBuildActive(false);
            end
            self:UpdateLastSelectedSavedConfigID(pendingConfigID);
            self.updatePending, self.pendingDisableStarterBuild, self.pendingConfigID = false, false, nil;

            self:UpdateCurrentConfigID();
            self:TryRefreshTalentUI();
            if self.onAfterChangeCallback then
                local onAfterChangeCallback = self.onAfterChangeCallback;
                RunNextFrame(function() securecall(onAfterChangeCallback); end);
                self.onAfterChangeCallback = nil;
            end
        end);
    else
        RunNextFrame(function()
            self:UpdateCurrentConfigID();
        end);
    end
end

function Module:CONFIG_COMMIT_FAILED(_, configID)
    if configID ~= C_ClassTalents.GetActiveConfigID() then return; end
    if self.updatePending then
        local currentConfigID = self.currentConfigID;
        RunNextFrame(function() -- next frame, because the default UI will overwrite anything we do here -.-
            self.updatePending = false;
            C_Traits.RollbackConfig(C_ClassTalents.GetActiveConfigID());
            if currentConfigID == starterConfigID then
                C_Timer.After(1, function()
                    C_ClassTalents.SetStarterBuildActive(true);
                    self:UpdateLastSelectedSavedConfigID(currentConfigID);
                end);
            end
            self:UpdateLastSelectedSavedConfigID(currentConfigID);
            self:TryRefreshTalentUI();
        end)
        self.updatePending, self.pendingDisableStarterBuild, self.pendingConfigID = false, false, nil;
    end
end

function Module:SelectLoadout(configID, autoApply, onAfterChangeCallback)
    self.updatePending, self.pendingDisableStarterBuild, self.pendingConfigID = false, false, nil;
    self.onAfterChangeCallback = nil;

    autoApply = not not autoApply;
    local loadResult;
    if configID == self.currentConfigID then
        return;
    elseif configID == starterConfigID then
        loadResult = C_ClassTalents.SetStarterBuildActive(true);
    else
        loadResult = C_ClassTalents.LoadConfig(configID, autoApply);
    end
    if loadResult ~= Enum.LoadConfigResult.Error then
        -- should we do something?
    end
    if
        loadResult == Enum.LoadConfigResult.NoChangesNecessary
        or loadResult == Enum.LoadConfigResult.Ready
    then
        if self.currentConfigID == starterConfigID then C_ClassTalents.SetStarterBuildActive(false); end
        self:UpdateLastSelectedSavedConfigID(configID);
        if onAfterChangeCallback then
            RunNextFrame(function() securecall(onAfterChangeCallback); end);
        end
    elseif loadResult == Enum.LoadConfigResult.LoadInProgress then
        local talentsTab = self:GetTalentFrame();
        local talentsTabIsVisible = talentsTab and talentsTab.IsVisible and talentsTab:IsVisible();
        if talentsTab and talentsTabIsVisible then
            local activeConfigID = C_ClassTalents.GetActiveConfigID();
            local stagedNodes = activeConfigID and GetStagedChanges(activeConfigID);
            if stagedNodes and next(stagedNodes) then
                talentsTab.stagedPurchaseNodes = stagedNodes;
                talentsTab:SetCommitVisualsActive(true, TalentFrameBaseMixin.VisualsUpdateReasons.CommitOngoing, true);
            end
        end
        if self.currentConfigID == starterConfigID then self.pendingDisableStarterBuild = true; end
        self.updatePending = true;
        self.pendingConfigID = configID;
        self.onAfterChangeCallback = onAfterChangeCallback;
    end
end
