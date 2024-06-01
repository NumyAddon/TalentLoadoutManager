local addonName, ns = ...;

--- @class TalentLoadoutManager_SideBarMixin
local SideBarMixin = {};
ns.SideBarMixin = SideBarMixin;

--- @type LibUIDropDownMenuNumy-4.0
local LibDD = LibStub("LibUIDropDownMenuNumy-4.0");

--- @type TalentLoadoutManagerConfig
local Config = ns.Config;

--- @type TalentLoadoutManagerAPI
local API = TalentLoadoutManagerAPI;
local GlobalAPI = TalentLoadoutManagerAPI.GlobalAPI;
local CharacterAPI = TalentLoadoutManagerAPI.CharacterAPI;

SideBarMixin.ImplementAutoApply = false;
SideBarMixin.ShowAnimationOnImport = false;
SideBarMixin.ImplementTTTMissingWarning = false;
SideBarMixin.ShowLoadAndApply = false;
SideBarMixin.ShowShowInTTV = false;

local LEVEL_CAP = 70;
local SETTING_SUFFIX_COLLAPSED = "_Collapsed";
local SETTING_SUFFIX_ANCHOR_LOCATION = "_AnchorLocation";
local ANCHOR_LEFT = 0;
local ANCHOR_RIGHT = 1;

function SideBarMixin:OnInitialize()
    local moduleName = self.name;
    self.renameDialogName = moduleName .. "_RenameLoadout";
    StaticPopupDialogs[self.renameDialogName] = {
        text = "Rename loadout (%s)",
        button1 = OKAY,
        button2 = CANCEL,
        hasEditBox = true,
        OnShow = function (dialog, data)
            dialog.editBox:SetText(data.name);
            dialog.editBox:HighlightText();
            dialog.editBox:SetScript("OnEscapePressed", function()
                dialog:Hide();
            end);
            dialog.editBox:SetScript("OnEnterPressed", function()
                dialog.button1:Click();
            end);
        end,
        OnAccept = function(dialog, data)
            local newName = dialog.editBox:GetText();
            GlobalAPI:RenameLoadout(data.id, newName);
            dialog:Hide();
        end,
        EditBoxOnTextChanged = function (self)
            if self:GetText() == "" then
                self:GetParent().button1:Disable();
            else
                self:GetParent().button1:Enable();
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    };

    self.createDialogName = moduleName .. "_CreateLoadout";
    StaticPopupDialogs[self.createDialogName] = {
        text = "Create custom loadout",
        button1 = OKAY,
        button2 = CANCEL,
        hasEditBox = true,
        OnShow = function (dialog)
            dialog.editBox:SetScript("OnEscapePressed", function()
                dialog:Hide();
            end);
            dialog.editBox:SetScript("OnEnterPressed", function()
                dialog.button1:Click();
            end);
        end,
        OnAccept = function(dialog)
            local name = dialog.editBox:GetText();
            self:DoCreate(name)
            dialog:Hide();
        end,
        EditBoxOnTextChanged = function (self)
            if self:GetText() == "" then
                self:GetParent().button1:Disable();
            else
                self:GetParent().button1:Enable();
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    };

    self.deleteDialogName = moduleName .. "_DeleteLoadout";
    StaticPopupDialogs[self.deleteDialogName] = {
        text = "Delete loadout (%s)?",
        button1 = OKAY,
        button2 = CANCEL,
        OnAccept = function(dialog, data)
            GlobalAPI:DeleteLoadout(data.id);
            dialog:Hide();
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    };

    self.removeFromListDialogName = moduleName .. "_RemoveLoadout";
    StaticPopupDialogs[self.removeFromListDialogName] = {
        text = "Remove loadout from list (%s)?",
        button1 = OKAY,
        button2 = CANCEL,
        OnAccept = function(dialog, data)
            GlobalAPI:RemoveLoadoutFromStorage(data.id);
            dialog:Hide();
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    };

    self.copyDialogName = moduleName .. "_CopyText";
    StaticPopupDialogs[self.copyDialogName] = {
        text = "CTRL-C to copy",
        button1 = CLOSE,
        OnShow = function(dialog, data)
            local function HidePopup()
                dialog:Hide();
            end
            dialog.editBox:SetScript("OnEscapePressed", HidePopup);
            dialog.editBox:SetScript("OnEnterPressed", HidePopup);
            dialog.editBox:SetScript("OnKeyUp", function(_, key)
                if IsControlKeyDown() and key == "C" then
                    HidePopup();
                end
            end);
            dialog.editBox:SetMaxLetters(0);
            dialog.editBox:SetText(data);
            dialog.editBox:HighlightText();
        end,
        hasEditBox = true,
        editBoxWidth = 240,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    };

    self.genericPopupDialogName = moduleName .. "_GenericPopup";
    StaticPopupDialogs[self.genericPopupDialogName] = {
        text = "%s",
        button1 = OKAY,
        button2 = nil,
        timeout = 0,
        OnAccept = function()
        end,
        OnCancel = function()
        end,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    };
end

function SideBarMixin:OnEnable()
    -- override in implementation: should SetupHook on relevant addonLoaded
end

function SideBarMixin:OnDisable()
    self:UnhookAll();

    API:UnregisterCallback(API.Event.LoadoutListUpdated, self);
end

function SideBarMixin:SetupHook()
    if not self.SideBar then
        self.SideBar, self.DataProvider = self:CreateSideBar();
        self.DropDown = self:InitDropDown(self.SideBar);
        self:SetCollapsed(Config:GetConfig(self.name .. SETTING_SUFFIX_COLLAPSED));
        self:UpdatePointsForAnchorLocation();
        self:TryIntegrateWithBlizzMove();
    end
    if not self.importDialog then
        self.importDialog = self:CreateImportDialog();
    end
    self:SecureHookScript(self:GetTalentsTab(), "OnShow", "OnTalentsTabShow");

    API:RegisterCallback(API.Event.LoadoutListUpdated, self.RefreshSideBarData, self);
end

--- @return Frame
function SideBarMixin:GetTalentsTab()
    -- override in implementation
end

function SideBarMixin:OnTalentsTabShow(frame)
    self:UpdateScaleForFit(frame:GetParent());
    self:UpdatePosition(frame:GetParent());
    self:RefreshSideBarData();
end

function SideBarMixin:UpdateScaleForFit(frame)
    if not Config:GetConfig('autoScale') then return end

    local extraHeight = 270;
    local extraWidth = 200 + (self.SideBar:GetWidth() * 1.5);

    local horizRatio = UIParent:GetWidth() / GetUIPanelWidth(frame, extraWidth);
    local vertRatio = UIParent:GetHeight() / GetUIPanelHeight(frame, extraHeight);

    frame:SetScale(min(horizRatio, vertRatio, 1));
end

function SideBarMixin:UpdatePosition(frame)
    if not Config:GetConfig('autoPosition') then return end

    local offsetDirection = self:GetAnchorLocation() == ANCHOR_LEFT and 1 or -1;
    local replacePoint = true;
    local xOffset = (self.SideBar:GetWidth() / 2) * offsetDirection;
    local yOffset = -41;
    if frame:GetNumPoints() > 0 then
        local point, relativeTo, relativePoint, foundXOffset;
        point, relativeTo, relativePoint, foundXOffset, yOffset = frame:GetPoint(1);
        replacePoint = false;
        if point == "TOP" and relativeTo == UIParent and relativePoint == "TOP"
                and (foundXOffset == 0 or ((foundXOffset - (xOffset * -1))) < 1) then
            replacePoint = true;
        end
    end

    if replacePoint then
        frame:ClearAllPoints();
        frame:SetPoint("TOP", UIParent, "TOP", xOffset, yOffset);
    end
end

function SideBarMixin:CreateImportDialog()
    --- main dialog
    local dialog = CreateFrame("Frame", nil, UIParent, "ClassTalentLoadoutDialogTemplate");
    dialog.titleText = "Import Custom Loadout";
    Mixin(dialog, ClassTalentLoadoutImportDialogMixin);
    dialog:SetSize(460, 300);
    dialog:Hide();

    --- import control
    dialog.ImportControl = CreateFrame("Frame", nil, dialog);
    local importControl = dialog.ImportControl;
    importControl.labelText = HUD_CLASS_TALENTS_IMPORT_DIALOG_EDIT_BOX_LABEL .. "(Icy-veins calculator links are also supported)";
    importControl:SetPoint("TOPLEFT", dialog.ContentArea);
    importControl:SetPoint("TOPRIGHT", dialog.ContentArea);
    importControl:SetHeight(100);
    importControl.Label = importControl:CreateFontString(nil, "ARTWORK", "GameFontNormal");
    importControl.Label:SetPoint("TOPLEFT");
    Mixin(importControl, ClassTalentLoadoutImportDialogImportControlMixin);

    importControl.InputContainer = CreateFrame("ScrollFrame", nil, importControl, "InputScrollFrameTemplate");
    importControl.InputContainer:SetPoint("TOPLEFT", importControl.Label, "BOTTOMLEFT", 0, -10);
    importControl.InputContainer:SetPoint("RIGHT");
    importControl.InputContainer:SetPoint("BOTTOM");
    importControl.InputContainer.maxLetters = 1000;
    importControl.InputContainer.instructions = HUD_CLASS_TALENTS_IMPORT_INSTRUCTIONS;
    importControl.InputContainer.hideCharCount = true;
    InputScrollFrame_OnLoad(importControl.InputContainer);

    importControl:OnLoad();
    importControl:SetScript("OnShow", importControl.OnShow);

    --- name control
    dialog.NameControl = CreateFrame("Frame", nil, dialog, "ClassTalentLoadoutDialogNameControlTemplate");
    local nameControl = dialog.NameControl;
    nameControl.labelText = HUD_CLASS_TALENTS_IMPORT_DIALOG_NAME_LABEL;
    nameControl:SetPoint("TOPLEFT", importControl, "BOTTOMLEFT", 0, -25);
    nameControl:SetPoint("TOPRIGHT", importControl, "BOTTOMRIGHT", 0, -25);
    Mixin(nameControl, ClassTalentLoadoutImportDialogNameControlMixin);

    nameControl:OnLoad();
    nameControl:SetScript("OnShow", nameControl.OnShow);

    local checkbox
    local addAutoApplyCheckbox = self.ImplementAutoApply
    if addAutoApplyCheckbox then
        --- autoApply checkbox
        dialog.AutoApplyCheckbox = CreateFrame('CheckButton', nil, dialog, 'UICheckButtonTemplate');
        checkbox = dialog.AutoApplyCheckbox;
        checkbox:SetPoint('TOPLEFT', dialog.NameControl, 'BOTTOMLEFT', 0, 5);
        checkbox:SetSize(24, 24);
        checkbox:SetScript('OnEnter', function(cb)
            GameTooltip:SetOwner(cb, 'ANCHOR_RIGHT');
            GameTooltip:SetText(cb.text:GetText());
            GameTooltip:AddLine('If checked, the loadout will automatically be applied to your character when you import it.', 1, 1, 1, true);
            GameTooltip:Show();
        end);
        checkbox:SetScript('OnLeave', function()
            GameTooltip:Hide();
        end);
        checkbox.text = checkbox:CreateFontString(nil, 'ARTWORK', 'GameFontNormal');
        checkbox.text:SetPoint('LEFT', checkbox, 'RIGHT', 0, 1);
        checkbox.text:SetText(string.format('Automatically Apply the loadout on import'));
        checkbox:SetHitRectInsets(-10, -checkbox.text:GetStringWidth(), -5, 0);
    end

    -- ImportIntoCurrentLoadout checkbox
    dialog.ImportIntoCurrentLoadoutCheckbox = CreateFrame('CheckButton', nil, dialog, 'UICheckButtonTemplate');
    checkbox = dialog.ImportIntoCurrentLoadoutCheckbox;
    checkbox:SetPoint('TOPLEFT', addAutoApplyCheckbox and dialog.AutoApplyCheckbox or dialog.NameControl, 'BOTTOMLEFT', 0, 5);
    checkbox:SetSize(24, 24);
    checkbox:SetScript('OnEnter', function(cb)
        GameTooltip:SetOwner(cb, 'ANCHOR_RIGHT');
        GameTooltip:SetText(cb.text:GetText());
        GameTooltip:AddLine('If checked, the imported build will be imported into the currently selected loadout.', 1, 1, 1);
        GameTooltip:Show();
    end);
    checkbox:SetScript('OnLeave', function()
        GameTooltip:Hide();
    end);
    checkbox:SetScript('OnClick', function(cb)
        local checked = cb:GetChecked();
        local dialog = cb:GetParent();
        dialog.NameControl:SetShown(not checked);
        dialog.NameControl:SetText(checked and '*importing into current loadout*' or '');
        dialog:UpdateAcceptButtonEnabledState();
    end);
    checkbox.text = checkbox:CreateFontString(nil, 'ARTWORK', 'GameFontNormal');
    checkbox.text:SetPoint('LEFT', checkbox, 'RIGHT', 0, 1);
    checkbox.text:SetText(string.format('Import into currently selected custom loadout'));
    checkbox:SetHitRectInsets(-10, -checkbox.text:GetStringWidth(), -5, 0);

    --- accept button
    dialog.AcceptButton = CreateFrame("Button", nil, dialog, "ClassTalentLoadoutDialogButtonTemplate");
    local acceptButton = dialog.AcceptButton;
    acceptButton:SetText(HUD_CLASS_TALENTS_IMPORT_LOADOUT_ACCEPT_BUTTON);
    acceptButton.disabledTooltip = HUD_CLASS_TALENTS_IMPORT_ERROR_IMPORT_STRING_AND_NAME;
    acceptButton:SetPoint("BOTTOMRIGHT", dialog.ContentArea, "BOTTOM", -5, 0);

    --- cancel button
    dialog.CancelButton = CreateFrame("Button", nil, dialog, "ClassTalentLoadoutDialogButtonTemplate");
    local cancelButton = dialog.CancelButton;
    cancelButton:SetText(CANCEL);
    cancelButton:SetPoint("BOTTOMLEFT", dialog.ContentArea, "BOTTOM", 5, 0);

    dialog.OnAccept = function(dialog)
        if dialog.AcceptButton:IsEnabled() then
            local importText = dialog.ImportControl:GetText();
            local loadoutName = dialog.NameControl:GetText();
            local autoApply = addAutoApplyCheckbox and dialog.AutoApplyCheckbox:GetChecked();
            local importIntoCurrentLoadout = dialog.ImportIntoCurrentLoadoutCheckbox:IsShown() and dialog.ImportIntoCurrentLoadoutCheckbox:GetChecked();

            local result, errorOrNil;
            if not importIntoCurrentLoadout then
                result, errorOrNil = self:DoImport(importText, loadoutName, autoApply);
            else
                result, errorOrNil = self:DoImportIntoCurrent(importText, autoApply);
            end

            if result then
                StaticPopupSpecial_Hide(dialog);
                if self.ShowAnimationOnImport then self:TryShowLoadoutCompleteAnimation(); end
            elseif errorOrNil then
                StaticPopup_Show(self.genericPopupDialogName, ERROR_COLOR:WrapTextInColorCode(errorOrNil));
            end
        end
    end

    dialog:OnLoad();
    dialog:SetScript("OnShow", function()
        local shouldShowImportIntoCurrent = self.activeLoadout and not self.activeLoadout.isBlizzardLoadout
        dialog.ImportIntoCurrentLoadoutCheckbox:SetShown(shouldShowImportIntoCurrent);
        if addAutoApplyCheckbox then dialog.AutoApplyCheckbox:SetChecked(Config:GetConfig('autoApply')); end
    end);
    dialog:SetScript("OnHide", dialog.OnHide);

    return dialog;
end

function SideBarMixin:OnToggleSideBarButtonClick()
    if IsShiftKeyDown() then
        self:ToggleAnchorLocation();
        return;
    end
    local collapsed = not self:GetCollapsed();
    Config:SetConfig(self.name .. SETTING_SUFFIX_COLLAPSED, collapsed);
    self:SetCollapsed(collapsed);
end

function SideBarMixin:ToggleAnchorLocation()
    local anchorLocation = self:GetAnchorLocation();
    local newAnchorLocation;
    if ANCHOR_LEFT == anchorLocation then
        newAnchorLocation = ANCHOR_RIGHT;
    else
        newAnchorLocation = ANCHOR_LEFT;
    end
    Config:SetConfig(self.name .. SETTING_SUFFIX_ANCHOR_LOCATION, newAnchorLocation);
    self:UpdatePointsForAnchorLocation();
end

function SideBarMixin:UpdatePointsForAnchorLocation()
    local talentsTab = self:GetTalentsTab();
    self.SideBar:ClearAllPoints();
    self.SideBar.ToggleSideBarButton:ClearAllPoints();
    if self:GetAnchorLocation() == ANCHOR_LEFT then
        self.SideBar:SetPoint('TOPRIGHT', talentsTab, 'TOPLEFT', 0, 0);
        self.SideBar.ToggleSideBarButton:SetPoint('RIGHT', talentsTab, 'TOPLEFT', 10, -52);
    else
        self.SideBar:SetPoint('TOPLEFT', self:GetTalentsTab(), 'TOPRIGHT', 0, 0);
        self.SideBar.ToggleSideBarButton:SetPoint('LEFT', talentsTab, 'TOPRIGHT', -10, -52);
    end
    self:SetCollapsed(self:GetCollapsed());

    self:UpdatePosition(talentsTab:GetParent());
end

function SideBarMixin:GetAnchorLocation()
    return Config:GetConfig(self.name .. SETTING_SUFFIX_ANCHOR_LOCATION, ANCHOR_LEFT);
end

function SideBarMixin:SetCollapsed(collapsed)
    local sideBar = self.SideBar;
    sideBar:SetShown(not collapsed);
    local anchorLocation = self:GetAnchorLocation();
    if (not collapsed and ANCHOR_LEFT == anchorLocation) or (collapsed and ANCHOR_RIGHT == anchorLocation) then
        -- arrow pointing right
        sideBar.ToggleSideBarButton:GetNormalTexture():SetTexCoord(0.15625, 0.5, 0.84375, 0.5, 0.15625, 0, 0.84375, 0);
        sideBar.ToggleSideBarButton:GetHighlightTexture():SetTexCoord(0.15625, 1, 0.84375, 1, 0.15625, 0.5, 0.84375, 0.5);
    else
        -- arrow pointing left
        sideBar.ToggleSideBarButton:GetNormalTexture():SetTexCoord(0.15625, 0, 0.84375, 0, 0.15625, 0.5, 0.84375, 0.5);
        sideBar.ToggleSideBarButton:GetHighlightTexture():SetTexCoord(0.15625, 0.5, 0.84375, 0.5, 0.15625, 1, 0.84375, 1);
    end
end

function SideBarMixin:GetCollapsed()
    return Config:GetConfig(self.name .. SETTING_SUFFIX_COLLAPSED, false);
end

function SideBarMixin:CreateSideBar()
    local talentsTab = self:GetTalentsTab();
    --- @class TLM_SideBar : Frame
    local sideBar = CreateFrame("Frame", nil, talentsTab);
    local width = 300;

    sideBar:SetHeight(talentsTab:GetHeight());
    sideBar:SetWidth(width);
    sideBar:SetPoint("TOPRIGHT", talentsTab, "TOPLEFT", 0, 0);

    -- add a background
    sideBar.Background = sideBar:CreateTexture(nil, "BACKGROUND");
    sideBar.Background:SetAllPoints();
    local function updateSideBarColor()
        local color = Config:GetConfig('sideBarBackgroundColor');
        sideBar.Background:SetColorTexture(color.r, color.g, color.b, color.a);
    end
    updateSideBarColor();
    Config:RegisterCallback(Config.Event.OptionValueChanged, function(_, option)
        if option == 'sideBarBackgroundColor' then updateSideBarColor(); end
    end, sideBar);

    -- add a title
    sideBar.Title = sideBar:CreateFontString(nil, "OVERLAY", "GameFontNormal");
    sideBar.Title:SetPoint("TOPLEFT", sideBar, "TOPLEFT", 10, -10);
    sideBar.Title:SetText("Talent Loadout Manager");

    -- add Create button
    sideBar.CreateButton = CreateFrame("Button", nil, sideBar, "UIPanelButtonTemplate, UIButtonTemplate");
    sideBar.CreateButton:SetSize((width / 2) - 10, 20);
    sideBar.CreateButton:SetText("Create");
    sideBar.CreateButton:SetPoint("TOPLEFT", sideBar.Title, "BOTTOMLEFT", 0, -10);
    sideBar.CreateButton:SetScript("OnClick", function()
        StaticPopup_Show(self.createDialogName);
    end);
    sideBar.CreateButton.tooltipText = "Create a new custom loadout";

    -- add Import button
    sideBar.ImportButton = CreateFrame("Button", nil, sideBar, "UIPanelButtonTemplate, UIButtonTemplate");
    sideBar.ImportButton:SetSize((width / 2) - 10, 20);
    sideBar.ImportButton:SetText("Import");
    sideBar.ImportButton:SetPoint("TOPLEFT", sideBar.CreateButton, "TOPRIGHT", 0, 0);
    sideBar.ImportButton:SetScript("OnClick", function()
        self.importDialog:ShowDialog();
    end);
    sideBar.ImportButton.tooltipText = "Import a custom loadout from a string";

    -- add a Save button
    sideBar.SaveButton = CreateFrame("Button", nil, sideBar, "UIPanelButtonTemplate, UIButtonTemplate");
    sideBar.SaveButton:SetSize((width / 2) - 10, 20);
    sideBar.SaveButton:SetText("Save");
    sideBar.SaveButton:SetPoint("TOPLEFT", sideBar.CreateButton, "BOTTOMLEFT", 0, 0);
    sideBar.SaveButton:SetScript("OnClick", function()
        local activeLoadout = self:GetActiveLoadout();
        if not activeLoadout or not activeLoadout.id then return; end

        self:UpdateCustomLoadoutWithCurrentTalents(activeLoadout.id);
    end);
    sideBar.SaveButton.tooltipText = "Save the current talents into the currently selected loadout";

    -- add a Config button
    sideBar.ConfigButton = CreateFrame("Button", nil, sideBar, "UIPanelButtonTemplate, UIButtonTemplate");
    sideBar.ConfigButton:SetSize((width / 2) - 10, 20);
    sideBar.ConfigButton:SetText("Config");
    sideBar.ConfigButton:SetPoint("TOPLEFT", sideBar.SaveButton, "TOPRIGHT", 0, 0);
    sideBar.ConfigButton:SetScript("OnClick", function()
        self:ShowConfigDialog();
    end);
    sideBar.ConfigButton.tooltipText = "Open the configuration UI";

    -- add a expand button
    sideBar.ToggleSideBarButton = CreateFrame("Button", nil, talentsTab, "UIPanelButtonTemplate, UIButtonTemplate");
    sideBar.ToggleSideBarButton:SetSize(24, 38);
    sideBar.ToggleSideBarButton:SetFrameStrata("HIGH");
    sideBar.ToggleSideBarButton:SetNormalTexture("Interface\\PaperDollInfoFrame\\UI-GearManager-FlyoutButton");
    sideBar.ToggleSideBarButton:SetHighlightTexture("Interface\\PaperDollInfoFrame\\UI-GearManager-FlyoutButton");
    sideBar.ToggleSideBarButton:GetNormalTexture():SetTexCoord(0.15625, 0.5, 0.84375, 0.5, 0.15625, 0, 0.84375, 0);
    sideBar.ToggleSideBarButton:GetHighlightTexture():SetTexCoord(0.15625, 1, 0.84375, 1, 0.15625, 0.5, 0.84375, 0.5);
    sideBar.ToggleSideBarButton:SetPoint("RIGHT", talentsTab, "TOPLEFT", 10, -52);
    sideBar.ToggleSideBarButton:SetScript("OnEnter", function()
        GameTooltip:SetOwner(sideBar.ToggleSideBarButton, "ANCHOR_RIGHT");
        GameTooltip:SetText("Toggle Sidebar");
        GameTooltip:AddLine("|cffeda55fShift + Click|r to move the side bar to the other side of the UI.", 1, 1, 1, true);
        GameTooltip:Show();
    end);
    sideBar.ToggleSideBarButton:SetScript("OnClick", function()
        self:OnToggleSideBarButtonClick();
    end);

    -- add a scrollbox frame
    local dataProvider
    sideBar.ScrollBoxContainer, dataProvider = self:CreateScrollBox(sideBar);
    sideBar.ScrollBoxContainer:SetPoint("TOPLEFT", sideBar.SaveButton, "BOTTOMLEFT", 0, -10);
    sideBar.ScrollBoxContainer:SetPoint("BOTTOMRIGHT", sideBar, "BOTTOMRIGHT", -10, 10);

    if self.ImplementTTTMissingWarning and not C_AddOns.IsAddOnLoaded('TalentTreeTweaks') then
        -- add a link to the addon
        sideBar.WarningLink = CreateFrame("Button", nil, sideBar, "UIPanelButtonTemplate, UIButtonTemplate");
        sideBar.WarningLink:SetSize(width - 50, 20);
        sideBar.WarningLink:SetText("Download TalentTreeTweaks");
        sideBar.WarningLink:SetPoint("BOTTOMLEFT", sideBar, "BOTTOMLEFT", 10, 10);
        sideBar.WarningLink:SetScript("OnClick", function()
            local url = "https://www.curseforge.com/wow/addons/talent-tree-tweaks";
            StaticPopup_Show(self.copyDialogName, nil, nil, url);
        end);

        -- add a warning on the bottom of the sideBar
        sideBar.Warning = sideBar:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge");
        sideBar.Warning:SetPoint("BOTTOMLEFT", sideBar.WarningLink, "TOPLEFT", 0, 0);
        sideBar.Warning:SetWidth(width - 50);
        sideBar.Warning:SetText("TalentTreeTweaks is not loaded. You might encounter serious bugs without it.");
        sideBar.Warning:SetTextColor(1, 0.5, 0.5);

        local function onOptionChange(_, option, value)
            if option == 'disableTTTWarning' then
                sideBar.Warning:SetShown(not value);
                sideBar.WarningLink:SetShown(not value);
            end
        end
        Config:RegisterCallback(Config.Event.OptionValueChanged, onOptionChange);
        onOptionChange(nil, 'disableTTTWarning', Config:GetConfig('disableTTTWarning'));
    end

    return sideBar, dataProvider;
end

function SideBarMixin:CreateScrollBox(parentContainer)
    --- @class TLM_SideBarContainerFrame : Frame
    local ContainerFrame = CreateFrame("Frame", nil, parentContainer);

    ContainerFrame.ScrollBar = CreateFrame("EventFrame", nil, ContainerFrame, "WowTrimScrollBar");
    ContainerFrame.ScrollBar:SetPoint("TOPRIGHT");
    ContainerFrame.ScrollBar:SetPoint("BOTTOMRIGHT");

    ContainerFrame.ScrollBox = CreateFrame("Frame", nil, ContainerFrame, "WowScrollBoxList");
    ContainerFrame.ScrollBox:SetPoint("TOPLEFT");
    ContainerFrame.ScrollBox:SetPoint("BOTTOMRIGHT", ContainerFrame.ScrollBar, "BOTTOMLEFT");
    --- @param frame TLM_ElementFrame
    local function elementFrameApplyColors(frame)
        local isSelected = (frame == self.activeLoadoutFrame);
        local textColor = isSelected
            and Config:GetConfig('sideBarActiveElementTextColor')
            or Config:GetConfig('sideBarInactiveElementTextColor');
        local backgroundColor = isSelected
            and Config:GetConfig('sideBarActiveElementBackgroundColor')
            or Config:GetConfig('sideBarInactiveElementBackgroundColor');
        local highlightBackgroundColor = isSelected
            and Config:GetConfig('sideBarActiveElementHighlightBackgroundColor')
            or Config:GetConfig('sideBarInactiveElementHighlightBackgroundColor');

        frame.Text:SetTextColor(textColor.r, textColor.g, textColor.b, textColor.a);
        frame.Background:SetColorTexture(backgroundColor.r, backgroundColor.g, backgroundColor.b, backgroundColor.a);
        frame.HighlightBackground:SetColorTexture(highlightBackgroundColor.r, highlightBackgroundColor.g, highlightBackgroundColor.b, highlightBackgroundColor.a);
    end

    --- @param frame TLM_ElementFrame
    local function OnListElementInitialized(frame, elementData)
        --- @class TLM_ElementFrame
        local frame = frame;
        if not frame.Background then
            frame.Background = frame:CreateTexture(nil, "BACKGROUND");
            frame.Background:SetAllPoints(frame);
        end

        if not frame.Text then
            frame.Text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight");
            frame.Text:SetJustifyH("LEFT");
            frame.Text:SetAllPoints(frame);
        end

        if not frame.HighlightBackground then
            frame.HighlightBackground = frame:CreateTexture(nil, "BACKGROUND");
            frame.HighlightBackground:SetAllPoints(frame);
            frame.HighlightBackground:Hide();
        end

        if elementData.isActive then
            self.activeLoadoutFrame = frame;
        end
        local text = elementData.text;
        if elementData.parentID then
            text = "  ||  " .. text;
        end
        frame.Text:SetText(text);

        frame.ApplyColors = elementFrameApplyColors;
        frame:ApplyColors();

        Config:RegisterCallback(Config.Event.OptionValueChanged, function(_, option)
            if Config.sideBarColorOptionKeys[option] then
                frame:ApplyColors();
            end
        end, frame);
        frame:SetScript("OnClick", function(_, button)
            if button == "LeftButton" then
                self:OnElementClick(frame, elementData.data);
            elseif button == "RightButton" then
                self:OnElementRightClick(frame, elementData.data);
            end
        end);
        frame:SetScript("OnEnter", function()
            frame.TalentBuildExportString = nil;
            GameTooltip:SetOwner(frame, "ANCHOR_RIGHT");
            GameTooltip:SetText(elementData.text);
            local defaultAction = self:GetDefaultActionText(elementData);
            GameTooltip:AddLine(string.format("Left-Click to %s this loadout", defaultAction), 1, 1, 1);
            GameTooltip:AddLine("Shift-Click to link to chat", 1, 1, 1);
            GameTooltip:AddLine("Right-Click for options", 1, 1, 1);

            -- Allows other addons, like TalentTreeTweaks to safely hook into GameTooltip:Show
            frame.TalentBuildExportString = GlobalAPI:GetExportString(elementData.data.id);

            GameTooltip:Show();

            frame.HighlightBackground:Show();
        end);
        frame:SetScript("OnLeave", function()
            GameTooltip:Hide();

            frame.HighlightBackground:Hide();
        end);
        frame:RegisterForClicks("AnyUp");
    end

    ContainerFrame.ScrollView = CreateScrollBoxListLinearView();
    ContainerFrame.ScrollView:SetElementExtent(20);  -- Fixed height for each row; required as we"re not using XML.
    ContainerFrame.ScrollView:SetElementInitializer("Button", OnListElementInitialized);

    ScrollUtil.InitScrollBoxWithScrollBar(ContainerFrame.ScrollBox, ContainerFrame.ScrollBar, ContainerFrame.ScrollView)

    local dataProvider = CreateDataProvider();
    ContainerFrame.ScrollBox:SetDataProvider(dataProvider);

    return ContainerFrame, dataProvider;
end

function SideBarMixin:InitDropDown(parentFrame)
    local dropDown = LibDD:Create_UIDropDownMenu(self.name .. "_DropDown", parentFrame);
    return dropDown;
end

function SideBarMixin:OpenDropDownMenu(dropDown, frame, elementData)
    local talentsTab = self:GetTalentsTab();
    local classID = talentsTab:GetClassID();
    local playerClassID = select(3, UnitClass("player"));

    local items = {
        title = {
            text = elementData.displayName,
            isTitle = true,
            notCheckable = true,
        },
        load = {
            text = "Load",
            notCheckable = true,
            func = function()
                local forceApply = false;
                self:OnElementClick(frame, elementData, forceApply);
            end,
        },
        loadAndApply = {
            text = "Load & Apply",
            notCheckable = true,
            func = function()
                local forceApply = true;
                self:OnElementClick(frame, elementData, forceApply);
            end,
            hidden = not self.ShowLoadAndApply,
        },
        saveCurrentIntoLoadout = {
            text = "Save current talents into loadout",
            notCheckable = true,
            disabled = elementData.isBlizzardLoadout,
            func = function()
                self:UpdateCustomLoadoutWithCurrentTalents(elementData.id);
            end,
        },
        rename = {
            text = "Rename",
            notCheckable = true,
            disabled = not elementData.playerIsOwner,
            func = function()
                StaticPopup_Show(self.renameDialogName, elementData.displayName, nil, elementData);
            end,
        },
        setParentLoadout = {
            text = "Set Blizzard base loadout",
            notCheckable = true,
            hidden = classID ~= playerClassID or elementData.isBlizzardLoadout,
            hasArrow = true,
            menuList = function()
                return self:MakeBlizzardLoadoutsMenuList(elementData);
            end,
        },
        export = {
            text = "Export",
            notCheckable = true,
            func = function()
                self:ExportLoadout(elementData);
            end,
        },
        linkToChat = {
            text = "Link to chat",
            notCheckable = true,
            func = function()
                self:LinkToChat(elementData.id);
            end,
        },
        openInTTV = {
            text = "Open in TalentTreeViewer",
            notCheckable = true,
            disabled = not (C_AddOns.GetAddOnEnableState('TalentTreeViewer', UnitName('player')) == 2),
            func = function()
                self:OpenInTalentTreeViewer(elementData);
            end,
            hidden = not self.ShowShowInTTV,
        },
        delete = {
            text = "Delete",
            notCheckable = true,
            func = function()
                StaticPopup_Show(self.deleteDialogName, elementData.displayName, nil, elementData);
            end,
            hidden = not elementData.playerIsOwner,
        },
        removeFromList = {
            text = "Remove from list",
            notCheckable = true,
            func = function()
                StaticPopup_Show(self.removeFromListDialogName, elementData.displayName, nil, elementData);
            end,
            hidden = elementData.playerIsOwner,
        },
    };

    local order = {
        items.title,
        items.setParentLoadout,
        items.load,
        items.loadAndApply,
        items.saveCurrentIntoLoadout,
        items.rename,
        items.export,
        items.linkToChat,
        items.openInTTV,
        items.delete,
        items.removeFromList,
    };

    self.menuList = {};
    for _, v in ipairs(order) do
        if not v.hidden then
            v.hidden = nil;
            if v.menuList and type(v.menuList) == "function" then
                v.menuList = v.menuList();
            end
            table.insert(self.menuList, v);
        end
    end

    LibDD:EasyMenu(self.menuList, dropDown, frame, 80, 0);
end

function SideBarMixin:MakeBlizzardLoadoutsMenuList(elementData)
    local dataProvider = self.DataProvider;
    local elements = dataProvider:GetCollection();
    local menuList = {};
    for _, v in ipairs(elements) do
        if v.data.isBlizzardLoadout and v.data.playerIsOwner then
            table.insert(menuList, {
                text = v.data.displayName,
                func = function()
                    CharacterAPI:SetParentLoadout(elementData.id, v.data.id);
                end,
                checked = v.data.id == elementData.parentID,
            });
        end
    end

    return menuList;
end

function SideBarMixin:SetElementAsActive(frame, elementData)
    self.activeLoadout = elementData;
    local previouslyActiveLoadoutFrame = self.activeLoadoutFrame;
    self.activeLoadoutFrame = frame;
    if previouslyActiveLoadoutFrame then
        previouslyActiveLoadoutFrame:ApplyColors();
    end
    frame:ApplyColors();
    self.SideBar.SaveButton:SetEnabled(self.activeLoadout and not self.activeLoadout.isBlizzardLoadout);
end

function SideBarMixin:OnElementClick(frame, elementData, forceApply)
    if IsShiftKeyDown() then
        self:LinkToChat(elementData.id);
        return;
    end
    self:SetElementAsActive(frame, elementData);
    if forceApply == nil then forceApply = Config:GetConfig('autoApply') end
    local autoApply = forceApply;

    self:DoLoad(elementData.id, autoApply);
end

function SideBarMixin:OnElementRightClick(frame, elementData)
    local dropDown = self.DropDown;
    if dropDown.currentElement ~= elementData.id then
        LibDD:CloseDropDownMenus();
    end
    dropDown.currentElement = elementData.id;
    self:OpenDropDownMenu(dropDown, frame, elementData);
end

function SideBarMixin:LinkToChat(loadoutId)
    local exportString = GlobalAPI:GetExportString(loadoutId);
    if not exportString then
        return;
    end

    if not TALENT_BUILD_CHAT_LINK_TEXT then
        if not ChatEdit_InsertLink(exportString) then
            ChatFrame_OpenChat(exportString);
        end
        return;
    end

    local talentsTab = self:GetTalentsTab();

    local specName = talentsTab:GetSpecName();
    local className = talentsTab:GetClassName();
    local specID = talentsTab:GetSpecID();
    local classColor = RAID_CLASS_COLORS[select(2, GetClassInfo(talentsTab:GetClassID()))];
    local level = LEVEL_CAP;

    local linkDisplayText = ("[%s]"):format(TALENT_BUILD_CHAT_LINK_TEXT:format(specName, className));
    local linkText = LinkUtil.FormatLink("talentbuild", linkDisplayText, specID, level, exportString);
    local chatLink = classColor:WrapTextInColorCode(linkText);
    if not ChatEdit_InsertLink(chatLink) then
        ChatFrame_OpenChat(chatLink);
    end
end

function SideBarMixin:ExportLoadout(elementData)
    local exportString = GlobalAPI:GetExportString(elementData.id);
    if not exportString then
        return;
    end

    StaticPopup_Show(self.copyDialogName, nil, nil, exportString);
end

function SideBarMixin:OpenInTalentTreeViewer(elementData)
    local exportString = GlobalAPI:GetExportString(elementData.id);
    if not exportString then
        return;
    end
    C_AddOns.LoadAddOn('TalentTreeViewer');
    if not TalentViewer or not TalentViewer.ImportLoadout then
        return;
    end
    TalentViewer:ImportLoadout(exportString);
end

function SideBarMixin:SortElements(dataProviderEntries)
    --- order by:
    --- 1. playerIsOwner
    --- 2. isBlizzardLoadout
    --- 3. name (todo: make this optional?)
    --- 4. id (basically, the order they were created?)
    ---
    --- custom loadouts are listed underneath their parent, if any

    local function compare(a, b)
        if not b then
            return false;
        end

        if a.data.playerIsOwner and not b.data.playerIsOwner then
            return true;
        elseif not a.data.playerIsOwner and b.data.playerIsOwner then
            return false;
        end

        if a.data.isBlizzardLoadout and not b.data.isBlizzardLoadout then
            return true;
        elseif not a.data.isBlizzardLoadout and b.data.isBlizzardLoadout then
            return false;
        end

        if a.data.displayName < b.data.displayName then
            return true;
        elseif a.data.displayName > b.data.displayName then
            return false;
        end

        if a.data.id < b.data.id then
            return true;
        elseif a.data.id > b.data.id then
            return false;
        end

        return false;
    end

    local elements = CopyTable(dataProviderEntries);

    table.sort(elements, compare);
    local lookup = {};
    for index, element in ipairs(elements) do
        element.order = index;
        element.subOrder = 0;
        lookup[element.data.id] = element;
    end

    for index, element in ipairs(elements) do
        local parentIndex = element.parentID and lookup[element.parentID] and lookup[element.parentID].order;
        if parentIndex then
            element.order = parentIndex;
            element.subOrder = index;
        end
    end

    table.sort(dataProviderEntries, function(a, b)
        if not b then
            return false;
        end
        a = lookup[a.data.id];
        b = lookup[b.data.id];

        if a.order == b.order then
            return a.subOrder < b.subOrder;
        end
        return a.order < b.order;
    end);
end

function SideBarMixin:GetLoadouts()
    -- override in implementation
end

function SideBarMixin:GetActiveLoadout(forceRefresh)
    -- override in implementation
end

function SideBarMixin:RefreshSideBarData()
    local loadouts = self:GetLoadouts();

    local previouslyActiveLoadoutFrame = self.activeLoadoutFrame;
    self.activeLoadoutFrame = nil;
    if previouslyActiveLoadoutFrame then
        previouslyActiveLoadoutFrame:ApplyColors();
    end

    self.activeLoadout = self:GetActiveLoadout(true);
    local foundActiveLoadout = false;
    local activeLoadoutID = self.activeLoadout and self.activeLoadout.id or nil;
    local dataProviderEntries = {}
    for _, loadout in pairs(loadouts) do
        loadout.parentID = loadout.parentMapping and loadout.parentMapping[0];
        table.insert(dataProviderEntries, {
            text = loadout.displayName,
            data = loadout,
            isActive = loadout.id == activeLoadoutID,
            parentID = loadout.parentID,
        });
        if loadout.id == activeLoadoutID then
            foundActiveLoadout = true;
        end
    end
    if not foundActiveLoadout then
        self.activeLoadout = nil;
    end
    self:SortElements(dataProviderEntries);
    self.DataProvider = CreateDataProvider(dataProviderEntries);
    self.SideBar.ScrollBoxContainer.ScrollBox:SetDataProvider(self.DataProvider);

    self.SideBar.SaveButton:SetEnabled(self.activeLoadout and not self.activeLoadout.isBlizzardLoadout);
end

function SideBarMixin:ShowConfigDialog()
    ns.Config:OpenConfigDialog();
end

function SideBarMixin:TryIntegrateWithBlizzMove()
    if not self.IntegrateWithBlizzMove or not C_AddOns.IsAddOnLoaded('BlizzMove') then return; end

    local compatible = false;
    if(BlizzMoveAPI and BlizzMoveAPI.GetVersion and BlizzMoveAPI.RegisterAddOnFrames) then
        local _, _, _, _, versionInt = BlizzMoveAPI:GetVersion()
        if (versionInt == nil or versionInt >= 30200) then
            compatible = true;
        end
    end

    if(not compatible) then
        print(addonName .. ' is not compatible with the current version of BlizzMove, please update.')
        return;
    end
    if not BlizzMoveAPI then return end

    local frameTable = self:GetBlizzMoveFrameTable();
    BlizzMoveAPI:RegisterAddOnFrames(frameTable);
end

function SideBarMixin:TryShowLoadoutCompleteAnimation()
    local talentsTab = self:GetTalentsTab();
    if talentsTab:IsShown() and talentsTab.SetCommitCompleteVisualsActive then
        talentsTab:SetCommitCompleteVisualsActive(true);
    end
end
