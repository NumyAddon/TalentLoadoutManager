local addonName, ns = ...;

--- @type TalentLoadoutManager
local TLM = ns.TLM;

local Module = TLM:NewModule("BlizzardLoadoutChanger", "AceEvent-3.0");
TLM.BlizzardLoadoutChanger = Module;

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

function Module:TryRefreshTalentUI()
    if not InCombatLockdown() and ClassTalentFrame and ClassTalentFrame.TalentsTab and ClassTalentFrame.TalentsTab:IsVisible() then
        ClassTalentFrame.TalentsTab:Hide();
        ClassTalentFrame.TalentsTab:Show();
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
    local _ = ClassTalentFrame
        and ClassTalentFrame.TalentsTab
        and ClassTalentFrame.TalentsTab.LoadoutDropDown
        and ClassTalentFrame.TalentsTab.LoadoutDropDown.SetSelectionID
        and ClassTalentFrame.TalentsTab.LoadoutDropDown:SetSelectionID(configID);
    -- this seems to reduce the amount of tainted values, but I didn't really dig into it
    local _ = ClassTalentFrame
        and ClassTalentFrame.TalentsTab
        and ClassTalentFrame.TalentsTab.LoadoutDropDown
        and ClassTalentFrame.TalentsTab.LoadoutDropDown.DropDownControl
        and secureSetNil(ClassTalentFrame.TalentsTab.LoadoutDropDown.DropDownControl, 'selectedValue');
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
        if self.currentConfigID == starterConfigID then self.pendingDisableStarterBuild = true; end
        self.updatePending = true;
        self.pendingConfigID = configID;
        self.onAfterChangeCallback = onAfterChangeCallback;
    end
end
