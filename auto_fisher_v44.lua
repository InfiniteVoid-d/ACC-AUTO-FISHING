-- =============================================
-- CLEANUP OLD RUNNING THREADS / GLOBAL STATE
-- =============================================
if _G.StopAutoFisher then
    pcall(_G.StopAutoFisher)
    _G.StopAutoFisher = nil
end

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedFirst = game:GetService("ReplicatedFirst")

local player = Players.LocalPlayer
local PlayerGui = player.PlayerGui
local Fish = ReplicatedStorage.Remotes.Fish

local getinfo = getinfo or (debug and debug.getinfo)
local getupvalues = getupvalues or (debug and debug.getupvalues)
local setupvalue = setupvalue or (debug and debug.setupvalue)

local CardConfig = require(ReplicatedStorage.Modules.Config.Core.CardConfig)
local ReplicatedData = require(ReplicatedFirst:WaitForChild("ReplicatedData"))

-- =============================================
-- CONFIG
-- =============================================
local Config = {
    Mode = "Blatant",

    -- Blatant strategy: "instant" | "turbo" | "hybrid" | "blatant"
    BlatantStrategy = "instant", -- Default to instant for PC users

    -- Legit
    LegitClickDelay = 0.05,
    LegitRecastDelay = 1,
    LegitCastValue = 1.0,        -- Perfect cast

    -- Blatant
    BlatantClickDelay = 0.05,
    BlatantHybridDelay = 3.5,
    
    -- Instant/Blatant Catch Delay settings:
    InstantCatchDelay = 2.2,     -- Default delay before catch (e.g. 2.2s struggle)
    SlowReelThreshold = 0.91,     -- Target struggle percentage (default 91% or 0.91)
    
    BlatantRecastDelay = 0.05,   -- Recast delay between catches (default 0.05s)
    BlatantCastValue = 1.0,      -- Perfect cast
    
    -- Auto Sell Duplicate Fish
    AutoSellDupes = false,

    -- Auto Collect drops & card display wall cash
    AutoCollect = false,

    -- Auto Collect spawned tokens (Grade & Travel tokens)
    AutoCollectTokens = true,

    -- Auto Buy card packs as they spawn on conveyor
    AutoBuyPacks = false,

    -- Double Belt Speed Spoof (Locally doubles conveyor speed animation)
    BeltSpeedSpoof = false,

    -- Auto Craft Relics
    AutoRelics = false,

    -- Dynamic Pack-Mutation Selection Map (Key: "PackName-MutationName" -> boolean)
    SelectedItems = {},

    -- GPU Saver
    GPUSaver = false,

    -- Shared
    SafetyRecastTime = 8.0,
    EscapeRecastDelay = 0.1,
}

-- Initialize all pack-mutation combinations to true by default
local mutationsList = {"Regular", "Gold", "Emerald", "Void", "Diamond", "Rainbow"}
for _, p in ipairs(CardConfig.List.Packs) do
    for _, m in ipairs(mutationsList) do
        Config.SelectedItems[p .. "-" .. m] = true
    end
end

-- =============================================
-- STATE
-- =============================================
local autoFishing = false
local clicking = false
local connection = nil
local clickThread = nil
local safetyThread = nil
local instantThread = nil
local autoSellThread = nil
local collectThread = nil
local collectTokensThread = nil
local autoBuyPacksThread = nil
local autoRelicsThread = nil
local collectedTokens = {}
local uiConnection = nil
local fishCaught = 0
local fishSold = 0
local sessionStart = 0
local waitingForCatch = false
local UICollapsed = false
local originalWidth = 460
local originalHeight = 320
local strategies = {"instant", "turbo", "hybrid", "blatant"}

local gpuActive = false
local whiteScreen = nil

local FishUI = PlayerGui:FindFirstChild("FishUI")

-- =============================================
-- STUB DEFINITIONS FOR GUI INITIALIZATION
-- =============================================
local modeLabel, stratLabel, statusLabel, statsLabel, modeBtn, stratBtn, toggleBtn
local inputContainer, thresholdContainer, inputLabel, thresholdLabel, delayInputBox, thresholdInputBox, debugLabel
local buyPacksBtn, beltSpeedBtn, sidebar, mainPanel, divider, frame, titleBar, minimizedBtn, frameCorner

_G.StopAutoFisher = function()
    autoFishing = false
    clicking = false
    if connection then pcall(function() connection:Disconnect() end) end
    if clickThread then pcall(task.cancel, clickThread) end
    if safetyThread then pcall(task.cancel, safetyThread) end
    if instantThread then pcall(task.cancel, instantThread) end
    if autoSellThread then pcall(task.cancel, autoSellThread) end
    if collectThread then pcall(task.cancel, collectThread) end
    if collectTokensThread then pcall(task.cancel, collectTokensThread) end
    if autoBuyPacksThread then pcall(task.cancel, autoBuyPacksThread) end
    if autoRelicsThread then pcall(task.cancel, autoRelicsThread) end
    collectedTokens = {}
    if uiConnection then pcall(function() uiConnection:Disconnect() end) end
    pcall(function() player:SetAttribute("BeltSpeed", nil) end)
    pcall(function()
        if FishUI then FishUI.Enabled = true end
    end)
    pcall(function()
        if gpuActive then
            gpuActive = false
            settings().Rendering.QualityLevel = Enum.QualityLevel.Automatic
            game.Lighting.GlobalShadows = true
            game.Lighting.FogEnd = 100000
            setfpscap(0)
            if whiteScreen then whiteScreen:Destroy() end
        end
    end)
end

-- =============================================
-- CLEANUP OLD UI
-- =============================================
for _, g in PlayerGui:GetChildren() do
    if g.Name:match("^AutoFishUI") then
        g:Destroy()
    end
end

-- =============================================
-- UI SYSTEM CREATION
-- =============================================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AutoFishUI_v44"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.DisplayOrder = 1000000
screenGui.Parent = PlayerGui

frame = Instance.new("Frame")
frame.Size = UDim2.new(0, originalWidth, 0, originalHeight)
frame.Position = UDim2.new(0.5, -230, 0.5, -160)
frame.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
frame.BorderSizePixel = 0
frame.Active = true
frame.ClipsDescendants = true
frame.Parent = screenGui
frameCorner = Instance.new("UICorner", frame)
frameCorner.CornerRadius = UDim.new(0, 10)

local stroke = Instance.new("UIStroke", frame)
stroke.Thickness = 1.5
stroke.Color = Color3.fromRGB(35, 35, 40)

-- Minimized Emblems (Oval capsule layout button)
minimizedBtn = Instance.new("TextLabel")
minimizedBtn.Size = UDim2.new(1, 0, 1, 0)
minimizedBtn.BackgroundTransparency = 1
minimizedBtn.Text = "🎣"
minimizedBtn.TextSize = 14
minimizedBtn.Font = Enum.Font.GothamBold
minimizedBtn.TextColor3 = Color3.fromRGB(0, 220, 120)
minimizedBtn.Visible = false
minimizedBtn.Parent = frame

-- Title Bar
titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 26)
titleBar.Position = UDim2.new(0, 0, 0, 0)
titleBar.BackgroundTransparency = 1
titleBar.Parent = frame

local titleText = Instance.new("TextLabel")
titleText.Size = UDim2.new(0.5, 0, 1, 0)
titleText.Position = UDim2.new(0, 10, 0, 0)
titleText.BackgroundTransparency = 1
titleText.Text = "Antigravity Hub | Anime Card"
titleText.TextColor3 = Color3.fromRGB(230, 230, 235)
titleText.TextSize = 12
titleText.Font = Enum.Font.GothamBold
titleText.TextXAlignment = Enum.TextXAlignment.Left
titleText.Parent = titleBar

-- Title Minimize Button
local minimizeBtn = Instance.new("TextButton")
minimizeBtn.Size = UDim2.new(0, 16, 0, 16)
minimizeBtn.Position = UDim2.new(1, -25, 0.5, -8)
minimizeBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
minimizeBtn.TextColor3 = Color3.fromRGB(220, 220, 220)
minimizeBtn.Text = "-"
minimizeBtn.TextSize = 12
minimizeBtn.Font = Enum.Font.GothamBold
minimizeBtn.ZIndex = 3
minimizeBtn.Parent = titleBar
Instance.new("UICorner", minimizeBtn).CornerRadius = UDim.new(0, 4)

-- Sidebar Frame (Left)
sidebar = Instance.new("Frame")
sidebar.Size = UDim2.new(0, 130, 1, -26)
sidebar.Position = UDim2.new(0, 0, 0, 26)
sidebar.BackgroundColor3 = Color3.fromRGB(13, 13, 16)
sidebar.BorderSizePixel = 0
sidebar.Parent = frame
Instance.new("UICorner", sidebar).CornerRadius = UDim.new(0, 10)

-- Divider Line
divider = Instance.new("Frame")
divider.Size = UDim2.new(0, 1, 1, -26)
divider.Position = UDim2.new(0, 130, 0, 26)
divider.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
divider.BorderSizePixel = 0
divider.Parent = frame

-- Main Content Panel (Right)
mainPanel = Instance.new("Frame")
mainPanel.Size = UDim2.new(1, -131, 1, -26)
mainPanel.Position = UDim2.new(0, 131, 0, 26)
mainPanel.BackgroundTransparency = 1
mainPanel.Parent = frame

-- Tab Navigation Tables
local currentTab = "Fishing"
local tabButtons = {}
local tabFrames = {}

-- Dynamic Tab Display Handler
local function showTab(tabName)
    currentTab = tabName
    for name, tabFrame in pairs(tabFrames) do
        tabFrame.Visible = (name == tabName)
    end
    for name, btn in pairs(tabButtons) do
        if name == tabName then
            btn.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
            btn.nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
            btn.icon.TextColor3 = Color3.fromRGB(0, 220, 120)
        else
            btn.BackgroundColor3 = Color3.fromRGB(13, 13, 16)
            btn.nameLabel.TextColor3 = Color3.fromRGB(140, 140, 150)
            btn.icon.TextColor3 = Color3.fromRGB(140, 140, 150)
        end
    end
end

-- Helper to generate Sidebar Tab buttons
local function createTabButton(name, iconChar, order)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, -10, 0, 28)
    btn.Position = UDim2.new(0, 5, 0, (order - 1) * 32 + 10)
    btn.BackgroundColor3 = Color3.fromRGB(13, 13, 16)
    btn.BorderSizePixel = 0
    btn.Text = ""
    btn.Parent = sidebar
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
    
    local icon = Instance.new("TextLabel")
    icon.Size = UDim2.new(0, 20, 1, 0)
    icon.Position = UDim2.new(0, 8, 0, 0)
    icon.BackgroundTransparency = 1
    icon.Text = iconChar
    icon.TextSize = 13
    icon.TextColor3 = Color3.fromRGB(140, 140, 150)
    icon.Name = "icon"
    icon.Parent = btn
    
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -35, 1, 0)
    label.Position = UDim2.new(0, 30, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = name
    label.TextColor3 = Color3.fromRGB(140, 140, 150)
    label.TextSize = 11
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Font = Enum.Font.GothamBold
    label.Name = "nameLabel"
    label.Parent = btn
    
    btn.MouseButton1Click:Connect(function()
        showTab(name)
    end)
    
    tabButtons[name] = btn
end

-- Create Tab Buttons
createTabButton("Fishing", "🎣", 1)
createTabButton("Conveyor", "📦", 2)
createTabButton("Automation", "🏺", 3)

-- Create Tab Panel Frames
local fishingTab = Instance.new("Frame")
fishingTab.Size = UDim2.new(1, -20, 1, -20)
fishingTab.Position = UDim2.new(0, 10, 0, 10)
fishingTab.BackgroundTransparency = 1
fishingTab.Parent = mainPanel
tabFrames["Fishing"] = fishingTab

local conveyorTab = Instance.new("Frame")
conveyorTab.Size = UDim2.new(1, -20, 1, -20)
conveyorTab.Position = UDim2.new(0, 10, 0, 10)
conveyorTab.BackgroundTransparency = 1
conveyorTab.Visible = false
conveyorTab.Parent = mainPanel
tabFrames["Conveyor"] = conveyorTab

local automationTab = Instance.new("Frame")
automationTab.Size = UDim2.new(1, -20, 1, -20)
automationTab.Position = UDim2.new(0, 10, 0, 10)
automationTab.BackgroundTransparency = 1
automationTab.Visible = false
automationTab.Parent = mainPanel
tabFrames["Automation"] = automationTab

-- Helper to create Cards
local function createCard(parent, titleTextText, size, position)
    local card = Instance.new("Frame")
    card.Size = size
    card.Position = position
    card.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
    card.BorderSizePixel = 0
    card.Parent = parent
    Instance.new("UICorner", card).CornerRadius = UDim.new(0, 8)
    
    local cStroke = Instance.new("UIStroke", card)
    cStroke.Thickness = 1
    cStroke.Color = Color3.fromRGB(35, 35, 40)
    
    local header = Instance.new("TextLabel")
    header.Size = UDim2.new(1, -10, 0, 20)
    header.Position = UDim2.new(0, 8, 0, 4)
    header.BackgroundTransparency = 1
    header.Text = titleTextText
    header.TextColor3 = Color3.fromRGB(160, 160, 170)
    header.TextSize = 10
    header.Font = Enum.Font.GothamBold
    header.TextXAlignment = Enum.TextXAlignment.Left
    header.Parent = card
    
    return card
end

-- =============================================
-- TAB 1: FISHING PANEL IMPLEMENTATION
-- =============================================

-- Status & Statistics Card
local statsCard = createCard(fishingTab, "STATISTICS", UDim2.new(1, 0, 0, 85), UDim2.new(0, 0, 0, 0))

modeLabel = Instance.new("TextLabel")
modeLabel.Size = UDim2.new(1, -16, 0, 13)
modeLabel.Position = UDim2.new(0, 8, 0, 24)
modeLabel.BackgroundTransparency = 1
modeLabel.TextScaled = true
modeLabel.Font = Enum.Font.GothamBold
modeLabel.Parent = statsCard

stratLabel = Instance.new("TextLabel")
stratLabel.Size = UDim2.new(1, -16, 0, 13)
stratLabel.Position = UDim2.new(0, 8, 0, 38)
stratLabel.BackgroundTransparency = 1
stratLabel.TextScaled = true
stratLabel.Font = Enum.Font.Gotham
stratLabel.Parent = statsCard

statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, -16, 0, 13)
statusLabel.Position = UDim2.new(0, 8, 0, 52)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = "Status: Idle"
statusLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
statusLabel.TextScaled = true
statusLabel.Font = Enum.Font.Gotham
statusLabel.Parent = statsCard

statsLabel = Instance.new("TextLabel")
statsLabel.Size = UDim2.new(1, -16, 0, 13)
statsLabel.Position = UDim2.new(0, 8, 0, 66)
statsLabel.BackgroundTransparency = 1
statsLabel.Text = "Caught: 0 | Sold: 0 | Time: 0m"
statsLabel.TextColor3 = Color3.fromRGB(120, 120, 140)
statsLabel.TextScaled = true
statsLabel.Font = Enum.Font.Gotham
statsLabel.Parent = statsCard

-- Controls Card
local controlsCard = createCard(fishingTab, "CONTROLS", UDim2.new(1, 0, 0, 180), UDim2.new(0, 0, 0, 95))

modeBtn = Instance.new("TextButton")
modeBtn.Size = UDim2.new(0.33, -5, 0, 24)
modeBtn.Position = UDim2.new(0, 8, 0, 25)
modeBtn.BorderSizePixel = 0
modeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
modeBtn.TextScaled = true
modeBtn.Font = Enum.Font.GothamBold
modeBtn.Parent = controlsCard
Instance.new("UICorner", modeBtn).CornerRadius = UDim.new(0, 6)

stratBtn = Instance.new("TextButton")
stratBtn.Size = UDim2.new(0.33, -5, 0, 24)
stratBtn.Position = UDim2.new(0.33, 8, 0, 25)
stratBtn.BorderSizePixel = 0
stratBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
stratBtn.TextScaled = true
stratBtn.Font = Enum.Font.GothamBold
stratBtn.Parent = controlsCard
Instance.new("UICorner", stratBtn).CornerRadius = UDim.new(0, 6)

toggleBtn = Instance.new("TextButton")
toggleBtn.Size = UDim2.new(0.33, -6, 0, 24)
toggleBtn.Position = UDim2.new(0.66, 6, 0, 25)
toggleBtn.BackgroundColor3 = Color3.fromRGB(0, 180, 90)
toggleBtn.BorderSizePixel = 0
toggleBtn.Text = "▶ Start"
toggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleBtn.TextScaled = true
toggleBtn.Font = Enum.Font.GothamBold
toggleBtn.Parent = controlsCard
Instance.new("UICorner", toggleBtn).CornerRadius = UDim.new(0, 6)

-- Instant Catch Delay row
inputContainer = Instance.new("Frame")
inputContainer.Size = UDim2.new(1, -16, 0, 25)
inputContainer.Position = UDim2.new(0, 8, 0, 60)
inputContainer.BackgroundTransparency = 1
inputContainer.Parent = controlsCard

inputLabel = Instance.new("TextLabel")
inputLabel.Size = UDim2.new(1, -60, 0, 20)
inputLabel.Position = UDim2.new(0, 0, 0, 0)
inputLabel.BackgroundTransparency = 1
inputLabel.Text = "Instant Catch Delay (s):"
inputLabel.TextColor3 = Color3.fromRGB(200, 200, 210)
inputLabel.TextScaled = true
inputLabel.TextXAlignment = Enum.TextXAlignment.Left
inputLabel.Font = Enum.Font.Gotham
inputLabel.Parent = inputContainer

delayInputBox = Instance.new("TextBox")
delayInputBox.Size = UDim2.new(0, 50, 0, 20)
delayInputBox.Position = UDim2.new(1, -50, 0, 0)
delayInputBox.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
delayInputBox.TextColor3 = Color3.fromRGB(255, 255, 255)
delayInputBox.Text = tostring(Config.InstantCatchDelay)
delayInputBox.PlaceholderText = "2.2"
delayInputBox.TextScaled = true
delayInputBox.Font = Enum.Font.GothamBold
delayInputBox.ClearTextOnFocus = false
delayInputBox.Parent = inputContainer
Instance.new("UICorner", delayInputBox).CornerRadius = UDim.new(0, 4)

-- Slow Reel Threshold row
thresholdContainer = Instance.new("Frame")
thresholdContainer.Size = UDim2.new(1, -16, 0, 25)
thresholdContainer.Position = UDim2.new(0, 8, 0, 90)
thresholdContainer.BackgroundTransparency = 1
thresholdContainer.Parent = controlsCard

thresholdLabel = Instance.new("TextLabel")
thresholdLabel.Size = UDim2.new(1, -60, 0, 20)
thresholdLabel.Position = UDim2.new(0, 0, 0, 0)
thresholdLabel.BackgroundTransparency = 1
thresholdLabel.Text = "Slow Reel Threshold:"
thresholdLabel.TextColor3 = Color3.fromRGB(200, 200, 210)
thresholdLabel.TextScaled = true
thresholdLabel.TextXAlignment = Enum.TextXAlignment.Left
thresholdLabel.Font = Enum.Font.Gotham
thresholdLabel.Parent = thresholdContainer

thresholdInputBox = Instance.new("TextBox")
thresholdInputBox.Size = UDim2.new(0, 50, 0, 20)
thresholdInputBox.Position = UDim2.new(1, -50, 0, 0)
thresholdInputBox.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
thresholdInputBox.TextColor3 = Color3.fromRGB(255, 255, 255)
thresholdInputBox.Text = tostring(Config.SlowReelThreshold)
thresholdInputBox.PlaceholderText = "0.91"
thresholdInputBox.TextScaled = true
thresholdInputBox.Font = Enum.Font.GothamBold
thresholdInputBox.ClearTextOnFocus = false
thresholdInputBox.Parent = thresholdContainer
Instance.new("UICorner", thresholdInputBox).CornerRadius = UDim.new(0, 4)

debugLabel = Instance.new("TextLabel")
debugLabel.Size = UDim2.new(1, -16, 0, 13)
debugLabel.Position = UDim2.new(0, 8, 0, 125)
debugLabel.BackgroundTransparency = 1
debugLabel.Text = ""
debugLabel.TextColor3 = Color3.fromRGB(80, 80, 90)
debugLabel.TextScaled = true
debugLabel.Font = Enum.Font.Gotham
debugLabel.Parent = controlsCard


-- =============================================
-- TAB 2: CONVEYOR FILTER PANEL IMPLEMENTATION
-- =============================================

-- Toggle control bar
local toggleBar = Instance.new("Frame")
toggleBar.Size = UDim2.new(1, 0, 0, 24)
toggleBar.Position = UDim2.new(0, 0, 0, 0)
toggleBar.BackgroundTransparency = 1
toggleBar.Parent = conveyorTab

buyPacksBtn = Instance.new("TextButton")
buyPacksBtn.Size = UDim2.new(0.5, -5, 1, 0)
buyPacksBtn.Position = UDim2.new(0, 0, 0, 0)
buyPacksBtn.BorderSizePixel = 0
buyPacksBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
buyPacksBtn.TextScaled = true
buyPacksBtn.Font = Enum.Font.Gotham
buyPacksBtn.Parent = toggleBar
Instance.new("UICorner", buyPacksBtn).CornerRadius = UDim.new(0, 6)

beltSpeedBtn = Instance.new("TextButton")
beltSpeedBtn.Size = UDim2.new(0.5, -5, 1, 0)
beltSpeedBtn.Position = UDim2.new(0.5, 5, 0, 0)
beltSpeedBtn.BorderSizePixel = 0
beltSpeedBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
beltSpeedBtn.TextScaled = true
beltSpeedBtn.Font = Enum.Font.Gotham
beltSpeedBtn.Parent = toggleBar
Instance.new("UICorner", beltSpeedBtn).CornerRadius = UDim.new(0, 6)

-- Search Container (Y = 30)
local searchContainer = Instance.new("Frame")
searchContainer.Size = UDim2.new(1, 0, 0, 24)
searchContainer.Position = UDim2.new(0, 0, 0, 30)
searchContainer.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
searchContainer.BorderSizePixel = 0
searchContainer.Parent = conveyorTab
Instance.new("UICorner", searchContainer).CornerRadius = UDim.new(0, 6)

local searchIcon = Instance.new("TextLabel")
searchIcon.Size = UDim2.new(0, 20, 1, 0)
searchIcon.Position = UDim2.new(0, 5, 0, 0)
searchIcon.BackgroundTransparency = 1
searchIcon.Text = "🔍"
searchIcon.TextSize = 12
searchIcon.Parent = searchContainer

local searchBox = Instance.new("TextBox")
searchBox.Size = UDim2.new(1, -30, 1, 0)
searchBox.Position = UDim2.new(0, 25, 0, 0)
searchBox.BackgroundTransparency = 1
searchBox.Text = ""
searchBox.PlaceholderText = "Search..."
searchBox.TextColor3 = Color3.fromRGB(240, 240, 240)
searchBox.PlaceholderColor3 = Color3.fromRGB(120, 120, 130)
searchBox.TextSize = 12
searchBox.Font = Enum.Font.Gotham
searchBox.TextXAlignment = Enum.TextXAlignment.Left
searchBox.ClearTextOnFocus = false
searchBox.Parent = searchContainer

-- Utility Buttons Container (Y = 60)
local utilityContainer = Instance.new("Frame")
utilityContainer.Size = UDim2.new(1, 0, 0, 20)
utilityContainer.Position = UDim2.new(0, 0, 0, 60)
utilityContainer.BackgroundTransparency = 1
utilityContainer.Parent = conveyorTab

-- Filter Scroll Panel
local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, 0, 1, -88)
scroll.Position = UDim2.new(0, 0, 0, 88)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 4
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.Parent = conveyorTab

local listLayout = Instance.new("UIListLayout", scroll)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, 8)

listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    scroll.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y + 15)
end)

-- Helper to create Hina-style checklist row inside scrolls
local function createFilterRow(parent, itemKey, displayName, initialValue, onToggle)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, -10, 0, 20)
    row.BackgroundTransparency = 1
    row.BorderSizePixel = 0
    row.Name = displayName
    row.Parent = parent
    
    local checkLabel = Instance.new("TextLabel")
    checkLabel.Size = UDim2.new(0, 16, 1, 0)
    checkLabel.Position = UDim2.new(0, 5, 0, 0)
    checkLabel.BackgroundTransparency = 1
    checkLabel.Text = initialValue and "✓" or "•"
    checkLabel.TextColor3 = initialValue and Color3.fromRGB(0, 220, 120) or Color3.fromRGB(100, 100, 105)
    checkLabel.TextSize = 13
    checkLabel.Font = Enum.Font.GothamBold
    checkLabel.Name = "checkLabel"
    checkLabel.Parent = row
    
    local nameLabel = Instance.new("TextLabel")
    nameLabel.Size = UDim2.new(1, -30, 1, 0)
    nameLabel.Position = UDim2.new(0, 25, 0, 0)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text = displayName
    nameLabel.TextColor3 = initialValue and Color3.fromRGB(230, 230, 235) or Color3.fromRGB(130, 130, 140)
    nameLabel.TextSize = 12
    nameLabel.TextXAlignment = Enum.TextXAlignment.Left
    nameLabel.Font = Enum.Font.Gotham
    nameLabel.Name = "nameLabel"
    nameLabel.Parent = row
    
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 1, 0)
    btn.BackgroundTransparency = 1
    btn.Text = ""
    btn.Parent = row
    
    btn.MouseButton1Click:Connect(function()
        initialValue = not initialValue
        checkLabel.Text = initialValue and "✓" or "•"
        checkLabel.TextColor3 = initialValue and Color3.fromRGB(0, 220, 120) or Color3.fromRGB(100, 100, 105)
        nameLabel.TextColor3 = initialValue and Color3.fromRGB(230, 230, 235) or Color3.fromRGB(130, 130, 140)
        onToggle(initialValue)
    end)
end

-- Alphabetically sort packs
local sortedPacks = {}
for _, p in ipairs(CardConfig.List.Packs) do
    table.insert(sortedPacks, p)
end
table.sort(sortedPacks)

local packFrames = {}

-- Populate Conveyor list
for _, p in ipairs(sortedPacks) do
    local packContainer = Instance.new("Frame")
    packContainer.Size = UDim2.new(1, 0, 0, 0)
    packContainer.AutomaticSize = Enum.AutomaticSize.Y
    packContainer.BackgroundTransparency = 1
    packContainer.BorderSizePixel = 0
    packContainer.Name = p
    packContainer.Parent = scroll
    
    local containerLayout = Instance.new("UIListLayout", packContainer)
    containerLayout.SortOrder = Enum.SortOrder.LayoutOrder
    containerLayout.Padding = UDim.new(0, 3)
    
    local header = Instance.new("TextLabel")
    header.Size = UDim2.new(1, 0, 0, 20)
    header.BackgroundTransparency = 1
    header.Text = p .. " Pack"
    header.TextColor3 = Color3.fromRGB(160, 160, 170)
    header.TextSize = 12
    header.Font = Enum.Font.GothamBold
    header.TextXAlignment = Enum.TextXAlignment.Left
    header.Name = "Header"
    header.Parent = packContainer
    
    for _, m in ipairs(mutationsList) do
        local key = p .. "-" .. m
        local rowName = p .. " Pack " .. m
        createFilterRow(packContainer, key, rowName, Config.SelectedItems[key], function(val)
            Config.SelectedItems[key] = val
        end)
    end
    
    table.insert(packFrames, packContainer)
end

-- =============================================
-- FILTER UTILITIES & MACROS (All, Clear, Rainbow, etc.)
-- =============================================
local function updateAllSelections(checkState, filterMutation)
    for key, _ in pairs(Config.SelectedItems) do
        local parts = key:split("-")
        local m = parts[2]
        if not filterMutation or m == filterMutation then
            Config.SelectedItems[key] = checkState
        end
    end
    -- Update visual styles instantly
    for _, pf in ipairs(packFrames) do
        for _, row in ipairs(pf:GetChildren()) do
            if row:IsA("Frame") and row.Name ~= "Header" then
                local pName = pf.Name
                local mName = row.Name:match("Pack%s+(%w+)$")
                if mName then
                    local key = pName .. "-" .. mName
                    local isChecked = Config.SelectedItems[key]
                    local check = row:FindFirstChild("checkLabel")
                    local name = row:FindFirstChild("nameLabel")
                    if check and name then
                        check.Text = isChecked and "✓" or "•"
                        check.TextColor3 = isChecked and Color3.fromRGB(0, 220, 120) or Color3.fromRGB(100, 100, 105)
                        name.TextColor3 = isChecked and Color3.fromRGB(230, 230, 235) or Color3.fromRGB(130, 130, 140)
                    end
                end
            end
        end
    end
end

local function createUtilityBtn(text, position, size, onClick)
    local btn = Instance.new("TextButton")
    btn.Size = size
    btn.Position = position
    btn.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
    btn.Text = text
    btn.TextColor3 = Color3.fromRGB(200, 200, 210)
    btn.TextSize = 10
    btn.Font = Enum.Font.GothamBold
    btn.Parent = utilityContainer
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
    btn.MouseButton1Click:Connect(onClick)
    return btn
end

-- Align utility macro buttons to the Conveyor Tab width
createUtilityBtn("All", UDim2.new(0, 0, 0, 0), UDim2.new(0, 45, 1, 0), function()
    updateAllSelections(true)
end)
createUtilityBtn("Clear", UDim2.new(0, 50, 0, 0), UDim2.new(0, 45, 1, 0), function()
    updateAllSelections(false)
end)
createUtilityBtn("Rainbow", UDim2.new(0, 100, 0, 0), UDim2.new(0, 60, 1, 0), function()
    updateAllSelections(false)
    updateAllSelections(true, "Rainbow")
end)
createUtilityBtn("Void", UDim2.new(0, 165, 0, 0), UDim2.new(0, 45, 1, 0), function()
    updateAllSelections(false)
    updateAllSelections(true, "Void")
end)
createUtilityBtn("Gold", UDim2.new(0, 215, 0, 0), UDim2.new(0, 45, 1, 0), function()
    updateAllSelections(false)
    updateAllSelections(true, "Gold")
end)

-- =============================================
-- INSTANT SEARCH FILTER IMPLEMENTATION
-- =============================================
searchBox:GetPropertyChangedSignal("Text"):Connect(function()
    local query = searchBox.Text:lower():gsub("%s+", "")
    for _, pf in ipairs(packFrames) do
        local anyVisible = false
        for _, row in ipairs(pf:GetChildren()) do
            if row:IsA("Frame") and row.Name ~= "Header" then
                local labelText = row.Name:lower():gsub("%s+", "")
                if query == "" or labelText:find(query) then
                    row.Visible = true
                    anyVisible = true
                else
                    row.Visible = false
                end
            end
        end
        pf.Visible = (query == "" or anyVisible)
    end
end)


-- =============================================
-- TAB 3: AUTOMATION PANEL IMPLEMENTATION
-- =============================================

-- Card Container for Toggles
local autoCard = createCard(automationTab, "AUTOMATION MODULES", UDim2.new(1, 0, 0, 180), UDim2.new(0, 0, 0, 0))

local function createGridToggle(labelText, position, size, initialValue, onToggle)
    local row = Instance.new("Frame")
    row.Size = size
    row.Position = position
    row.BackgroundTransparency = 1
    row.Parent = autoCard
    
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -55, 1, 0)
    label.Position = UDim2.new(0, 8, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = labelText
    label.TextColor3 = Color3.fromRGB(200, 200, 210)
    label.TextSize = 11
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Font = Enum.Font.Gotham
    label.Parent = row
    
    local toggle = Instance.new("TextButton")
    toggle.Size = UDim2.new(0, 45, 0, 18)
    toggle.Position = UDim2.new(1, -50, 0.5, -9)
    toggle.BackgroundColor3 = initialValue and Color3.fromRGB(0, 180, 90) or Color3.fromRGB(45, 45, 50)
    toggle.Text = initialValue and "ON" or "OFF"
    toggle.TextColor3 = Color3.fromRGB(255, 255, 255)
    toggle.TextSize = 9
    toggle.Font = Enum.Font.GothamBold
    toggle.Parent = row
    Instance.new("UICorner", toggle).CornerRadius = UDim.new(0, 4)
    
    toggle.MouseButton1Click:Connect(function()
        initialValue = not initialValue
        toggle.BackgroundColor3 = initialValue and Color3.fromRGB(0, 180, 90) or Color3.fromRGB(45, 45, 50)
        toggle.Text = initialValue and "ON" or "OFF"
        onToggle(initialValue)
    end)
    
    return toggle
end

-- Add toggles inside the grid card
local gpuBtnToggle = createGridToggle("🖥️ GPU Saver", UDim2.new(0, 0, 0, 25), UDim2.new(1, 0, 0, 20), Config.GPUSaver, function(val)
    Config.GPUSaver = val
    if val then enableGPU() else disableGPU() end
end)

local collectBtnToggle = createGridToggle("🪙 Collect Cash", UDim2.new(0, 0, 0, 50), UDim2.new(1, 0, 0, 20), Config.AutoCollect, function(val)
    Config.AutoCollect = val
    if val then startAutoCollectLoop() else stopAutoCollectLoop() end
end)

local autoSellBtnToggle = createGridToggle("💰 Sell Duplicate Fish", UDim2.new(0, 0, 0, 75), UDim2.new(1, 0, 0, 20), Config.AutoSellDupes, function(val)
    Config.AutoSellDupes = val
    if autoFishing then
        if val then startAutoSellLoop() else cancelAutoSellThread() end
    end
end)

local tokensBtnToggle = createGridToggle("🪙 Collect Map Tokens", UDim2.new(0, 0, 0, 100), UDim2.new(1, 0, 0, 20), Config.AutoCollectTokens, function(val)
    Config.AutoCollectTokens = val
    if autoFishing then
        if val then startAutoCollectTokensLoop() else cancelCollectTokensThread() end
    end
end)

local autoRelicBtnToggle = createGridToggle("🏺 Auto Craft Relics", UDim2.new(0, 0, 0, 125), UDim2.new(1, 0, 0, 20), Config.AutoRelics, function(val)
    Config.AutoRelics = val
    if val then startAutoRelicsLoop() else cancelAutoRelicsThread() end
end)

-- Promo Code Redeemer Button
local codesBtn = Instance.new("TextButton")
codesBtn.Size = UDim2.new(1, 0, 0, 26)
codesBtn.Position = UDim2.new(0, 0, 0, 195)
codesBtn.Text = "🎁 Redeem All Promo Codes"
codesBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
codesBtn.BackgroundColor3 = Color3.fromRGB(70, 30, 120)
codesBtn.TextSize = 12
codesBtn.Font = Enum.Font.GothamBold
codesBtn.Parent = automationTab
Instance.new("UICorner", codesBtn).CornerRadius = UDim.new(0, 6)

local codesBtnStroke = Instance.new("UIStroke", codesBtn)
codesBtnStroke.Thickness = 1
codesBtnStroke.Color = Color3.fromRGB(100, 50, 180)


-- =============================================
-- CORE FUNCTION DEFINITIONS
-- =============================================
local function isPC()
    return UserInputService.KeyboardEnabled and UserInputService.MouseEnabled
end

local function findMyPlot()
    local plotsFolder = workspace:FindFirstChild("Plots")
    if not plotsFolder then return nil end
    for _, p in ipairs(plotsFolder:GetChildren()) do
        local timer = p:FindFirstChild("Timer", true)
        if timer and timer:GetAttribute("Owner") == player.Name then
            return p
        end
        if p:GetAttribute("Owner") == player.Name or p:GetAttribute("Player") == player.Name then
            return p
        end
        for _, descendant in ipairs(p:GetDescendants()) do
            if descendant.Name == "Owner" then
                local isMatch = false
                pcall(function()
                    if descendant:IsA("StringValue") and descendant.Value == player.Name then
                        isMatch = true
                    end
                end)
                if descendant:GetAttribute("Owner") == player.Name then
                    isMatch = true
                end
                if isMatch then
                    return p
                end
            end
        end
    end
    return nil
end

local function shouldBuyPack(packType, mutation)
    local mut = (mutation == "nil" or mutation == nil) and "Regular" or mutation
    return Config.SelectedItems[packType .. "-" .. mut] == true
end

-- =============================================
-- UPDATE MODE UI CORE FUNCTION
-- =============================================
local function updateModeUI()
    local isBlatant = Config.Mode == "Blatant"

    modeLabel.Text = "Mode: " .. Config.Mode
    modeLabel.TextColor3 = isBlatant and Color3.fromRGB(255, 60, 60) or Color3.fromRGB(0, 200, 120)
    modeBtn.Text = isBlatant and "⚡BLT" or "🎣LEG"
    modeBtn.BackgroundColor3 = isBlatant and Color3.fromRGB(180, 30, 30) or Color3.fromRGB(30, 130, 70)
    
    stratBtn.Visible = isBlatant
    stratLabel.Visible = isBlatant
    
    local showDelay = isBlatant and (Config.BlatantStrategy == "instant" or Config.BlatantStrategy == "hybrid" or Config.BlatantStrategy == "blatant")
    local showThreshold = isBlatant and (Config.BlatantStrategy == "instant" or Config.BlatantStrategy == "blatant")
    
    if not UICollapsed then
        inputContainer.Visible = showDelay
        thresholdContainer.Visible = showThreshold
    end

    if isBlatant then
        local s = Config.BlatantStrategy
        stratBtn.Text = s == "instant" and "🚀INS" or s == "turbo" and "🏎️TRB" or s == "hybrid" and "🔀HYB" or "🔥BLT"
        stratBtn.BackgroundColor3 = s == "instant" and Color3.fromRGB(0, 150, 100)
            or s == "turbo" and Color3.fromRGB(0, 120, 180) 
            or s == "hybrid" and Color3.fromRGB(120, 50, 180)
            or Color3.fromRGB(200, 0, 50)
        stratLabel.Text = "Strategy: " .. s
        stratLabel.TextColor3 = Color3.fromRGB(200, 200, 210)
        
        if s == "instant" then
            inputLabel.Text = "Instant Catch Delay (s):"
            delayInputBox.Text = tostring(Config.InstantCatchDelay)
            thresholdLabel.Text = "Slow Reel Threshold:"
            thresholdInputBox.Text = tostring(Config.SlowReelThreshold)
        elseif s == "blatant" then
            inputLabel.Text = "Catch Delay (s):"
            delayInputBox.Text = tostring(Config.InstantCatchDelay)
            thresholdLabel.Text = "Recast Delay (s):"
            thresholdInputBox.Text = tostring(Config.BlatantRecastDelay)
        elseif s == "hybrid" then
            inputLabel.Text = "Hybrid Catch Delay (s):"
            delayInputBox.Text = tostring(Config.BlatantHybridDelay)
        end
    end

    buyPacksBtn.Text = Config.AutoBuyPacks and "📦 AutoBuy: ON" or "📦 AutoBuy: OFF"
    buyPacksBtn.BackgroundColor3 = Config.AutoBuyPacks and Color3.fromRGB(180, 100, 0) or Color3.fromRGB(50, 50, 55)

    beltSpeedBtn.Text = Config.BeltSpeedSpoof and "⚡ Beltx2: ON" or "⚡ Beltx2: OFF"
    beltSpeedBtn.BackgroundColor3 = Config.BeltSpeedSpoof and Color3.fromRGB(180, 100, 0) or Color3.fromRGB(50, 50, 55)
end

local function setStatus(text, color)
    statusLabel.Text = "Status: " .. text
    statusLabel.TextColor3 = color or Color3.fromRGB(180, 180, 180)
end

local function setDebug(text)
    debugLabel.Text = text
end

local function updateStats()
    local elapsed = math.floor((tick() - sessionStart) / 60)
    statsLabel.Text = string.format("Caught: %d | Sold: %d | Time: %dm", fishCaught, fishSold, elapsed)
end

-- =============================================
-- CONVEYOR SPEED SPOOF ENGINE
-- =============================================
local function updateBeltSpeedSpoof()
    pcall(function()
        player:SetAttribute("BeltSpeed", Config.BeltSpeedSpoof and true or nil)
        local plotsFolder = workspace:FindFirstChild("Plots")
        if plotsFolder then
            for _, p in ipairs(plotsFolder:GetChildren()) do
                local timer = p:FindFirstChild("Timer", true)
                if (timer and timer:GetAttribute("Owner") == player.Name) or p:GetAttribute("Owner") == player.Name then
                    local CardHandler = nil
                    pcall(function() CardHandler = require(ReplicatedStorage.Client.UI.CardHandler) end)
                    if CardHandler and type(CardHandler.ConveyorSpeed) == "function" then
                        pcall(CardHandler.ConveyorSpeed, p.Name, Config.BeltSpeedSpoof)
                    end
                    break
                end
            end
        end
    end)
end

-- =============================================
-- AUTO COLLECT MONEY ENGINE
-- =============================================
local function cancelCollectThread()
    if collectThread then
        pcall(task.cancel, collectThread)
        collectThread = nil
    end
end

local function startAutoCollectLoop()
    cancelCollectThread()
    -- The game uses a server-side toggle via Card:FireServer("ToggleAutoCollect")
    -- We just need to fire it once to enable, and once to disable
    local CardRemote = nil
    pcall(function() CardRemote = ReplicatedStorage.Remotes:FindFirstChild("Card") end)
    if CardRemote then
        -- Check if auto collect is already enabled
        local currentState = false
        pcall(function() currentState = ReplicatedData.GetData("AutoCollect") end)
        
        if not currentState then
            -- Fire the toggle to enable it
            pcall(function() CardRemote:FireServer("ToggleAutoCollect") end)
            setDebug("Auto Collect: Enabled via server toggle")
        else
            setDebug("Auto Collect: Already enabled")
        end
    else
        setDebug("Card remote not found!")
    end
end

local function stopAutoCollectLoop()
    cancelCollectThread()
    -- Disable the server-side auto collect
    local currentState = false
    pcall(function() currentState = ReplicatedData.GetData("AutoCollect") end)
    
    if currentState then
        local CardRemote = nil
        pcall(function() CardRemote = ReplicatedStorage.Remotes:FindFirstChild("Card") end)
        if CardRemote then
            pcall(function() CardRemote:FireServer("ToggleAutoCollect") end)
            setDebug("Auto Collect: Disabled via server toggle")
        end
    end
end

-- =============================================
-- AUTO COLLECT TOKENS & POTIONS ENGINE
-- =============================================
local function cancelCollectTokensThread()
    if collectTokensThread then
        pcall(task.cancel, collectTokensThread)
        collectTokensThread = nil
    end
end

local function startAutoCollectTokensLoop()
    cancelCollectTokensThread()
    collectTokensThread = task.spawn(function()
        while Config.AutoCollectTokens do
            local tag = player.Name .. "Token"
            local clientTokens = workspace:FindFirstChild("Items")
                and workspace.Items:FindFirstChild("Tokens")
                and workspace.Items.Tokens:FindFirstChild("Client")

            local activeNames = {}
            for _, child in ipairs(game:GetService("CollectionService"):GetTagged(tag)) do
                if not Config.AutoCollectTokens then break end
                activeNames[child.Name] = true
                if not collectedTokens[child.Name] then
                    collectedTokens[child.Name] = true
                    
                    local visual = clientTokens and clientTokens:FindFirstChild(child.Name)
                    if visual and visual:IsA("BasePart") then
                        visual.Transparency = 1
                    end
                    
                    pcall(function() ReplicatedStorage.Remotes.Card:FireServer("CollectToken", child.Name) end)
                end
            end
            
            for name in pairs(collectedTokens) do
                if not activeNames[name] then
                    collectedTokens[name] = nil
                end
            end
            
            for _, item in ipairs(game:GetService("CollectionService"):GetTagged("Potions")) do
                if not Config.AutoCollectTokens then break end
                if item:IsA("BasePart") and item.Transparency < 1 then
                    item.Transparency = 1
                    pcall(function() ReplicatedStorage.Remotes.Potion:FireServer("Collect", item.Name) end)
                end
            end
            
            task.wait(1.0)
        end
    end)
end

-- =============================================
-- AUTO BUY PACKS ENGINE
-- =============================================
local function cancelAutoBuyPacksThread()
    if autoBuyPacksThread then
        pcall(task.cancel, autoBuyPacksThread)
        autoBuyPacksThread = nil
    end
end

local function startAutoBuyPacksLoop()
    cancelAutoBuyPacksThread()
    autoBuyPacksThread = task.spawn(function()
        local packFolder = workspace:FindFirstChild("Client")
            and workspace.Client:FindFirstChild("Packs")
        if not packFolder then 
            setDebug("Packs folder missing!")
            return 
        end
        
        local conn = packFolder.ChildAdded:Connect(function(child)
            if not Config.AutoBuyPacks then return end
            local myPlot = findMyPlot()
            if not myPlot then return end
            
            local parts = child.Name:split("-")
            local plotNum = parts[2]
            
            if plotNum == myPlot.Name then
                task.wait(0.08)
                
                local packType = child.PrimaryPart and child.PrimaryPart.Name or "Unknown"
                local mutation = "nil"
                
                local display = child.PrimaryPart and child.PrimaryPart:FindFirstChild("ConveyorDisplay")
                if display and display:FindFirstChild("Mutation") and display.Mutation.Visible then
                    mutation = display.Mutation.Text
                end
                
                if shouldBuyPack(packType, mutation) then
                    pcall(function()
                        ReplicatedStorage.Remotes.Card:FireServer("BuyPack", child.Name)
                    end)
                end
            end
        end)
        
        while Config.AutoBuyPacks do
            task.wait(1.0)
        end
        conn:Disconnect()
    end)
end

-- =============================================
-- AUTO CRAFT RELICS ENGINE
-- =============================================
local function cancelAutoRelicsThread()
    if autoRelicsThread then
        pcall(task.cancel, autoRelicsThread)
        autoRelicsThread = nil
    end
end

local function startAutoRelicsLoop()
    cancelAutoRelicsThread()
    autoRelicsThread = task.spawn(function()
        local relicsConfig = require(ReplicatedStorage.Modules.Config.Core.Relics)
        while Config.AutoRelics do
            local myRelics = ReplicatedData.GetData("Relics") or {}
            local nextRelic = nil
            for _, name in ipairs(relicsConfig.List) do
                if not table.find(myRelics, name) then
                    nextRelic = name
                    break
                end
            end
            
            if nextRelic then
                pcall(function()
                    ReplicatedStorage.Remotes.Relic:FireServer("Craft", nextRelic)
                end)
            end
            task.wait(5.0)
        end
    end)
end

-- =============================================
-- PROMO CODE REDEEMER ENGINE
-- =============================================
local promoCodes = {
    "Sorry", "FiftyCode", "FortyNineCode", "FortyEightCode", "FortySevenCode",
    "FortySixCode", "FortyFiveCode", "FortyFourCode", "FortyThreeCode",
    "FortyTwoCode", "FortyOneCode", "FortyCode", "ThirtyNineCode",
    "ThirtyEightCode", "ThirtySevenCode", "ThirtySixCode", "ThirtyFiveCode",
    "ThirtyFourCode", "ThirtyThreeCode", "ThirtyTwoCode", "ThirtyOneCode",
    "ThirtyCode", "TwentyNinthCode", "TwentyEighthCode"
}

local redeemingCodes = false
local function redeemAllCodes()
    if redeemingCodes then return end
    redeemingCodes = true
    setDebug("Redeeming promo codes...")
    task.spawn(function()
        for _, code in ipairs(promoCodes) do
            pcall(function()
                ReplicatedStorage.Remotes.Codes:FireServer(code)
            end)
            task.wait(0.25)
        end
        setDebug("Codes redemption complete!")
        redeemingCodes = false
    end)
end

-- =============================================
-- DUPLICATES SELLING ENGINE
-- =============================================
local function getInventory()
    local inventoryFrame = PlayerGui:FindFirstChild("Fishing") and
                           PlayerGui.Fishing.Frame.Frames.InventoryFrame.Main
    if not inventoryFrame then return {} end

    local fishList = {}
    for _, v in pairs(inventoryFrame:GetChildren()) do
        if v:IsA("ImageButton") and v.Name ~= "Ghost" and v.Name ~= "Template" then
            local amountLabel = v:FindFirstChild("Amount")
            if amountLabel then
                local amountText = amountLabel.Text or "x1"
                local amount = tonumber(amountText:match("%d+")) or 1
                if amount > 1 then
                    table.insert(fishList, {name = v.Name, amount = amount})
                end
            end
        end
    end
    return fishList
end

local function sellDuplicates()
    local fishList = getInventory()
    if #fishList == 0 then
        return 0
    end

    local totalSoldThisRound = 0
    for _, fishData in ipairs(fishList) do
        if not Config.AutoSellDupes or not autoFishing then break end

        local sellCount = fishData.amount - 1
        setDebug("Auto-Selling " .. fishData.name .. " x" .. sellCount)

        for i = 1, sellCount do
            if not Config.AutoSellDupes or not autoFishing then break end
            pcall(Fish.FireServer, Fish, "Sell", fishData.name)
            totalSoldThisRound = totalSoldThisRound + 1
            task.wait(0.15)
        end
        task.wait(0.3)
    end

    return totalSoldThisRound
end

local function cancelAutoSellThread()
    if autoSellThread then
        pcall(task.cancel, autoSellThread)
        autoSellThread = nil
    end
end

local function startAutoSellLoop()
    cancelAutoSellThread()
    autoSellThread = task.spawn(function()
        while Config.AutoSellDupes and autoFishing do
            task.wait(1.5)
            if not Config.AutoSellDupes or not autoFishing then break end
            
            local sold = sellDuplicates()
            if sold > 0 then
                fishSold = fishSold + sold
                updateStats()
            end
            
            task.wait(5.0)
        end
    end)
end

-- =============================================
-- CLICK ENGINE
-- =============================================
local function simulateClick()
    local vim = nil
    pcall(function() vim = game:GetService("VirtualInputManager") end)
    if vim then
        pcall(function()
            vim:SendMouseButtonEvent(0, 0, 0, true, game, 0)
            RunService.RenderStepped:Wait()
            vim:SendMouseButtonEvent(0, 0, 0, false, game, 0)
        end)
    end
end

local clickCount = 0
local function startClicking(delay)
    if clicking then return end
    clicking = true
    clickCount = 0
    clickThread = task.spawn(function()
        while clicking and autoFishing do
            simulateClick()
            clickCount = clickCount + 1
            if clickCount % 10 == 0 then
                task.wait(0.08)
            end
            task.wait(delay or Config.LegitClickDelay)
        end
    end)
end

local function stopClicking()
    clicking = false
    if clickThread then
        pcall(task.cancel, clickThread)
        clickThread = nil
    end
    pcall(function()
        local VirtualInputManager = game:GetService("VirtualInputManager")
        VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0)
    end)
end

local function cancelInstantThread()
    if instantThread then
        pcall(task.cancel, instantThread)
        instantThread = nil
    end
end

-- =============================================
-- CASTING & FISH ENGINE GETGC
-- =============================================
local function doCast()
    local castVal = Config.Mode == "Blatant" and Config.BlatantCastValue or Config.LegitCastValue
    pcall(Fish.FireServer, Fish, "CastRod", castVal)
    setStatus("Casting...", Color3.fromRGB(255, 214, 0))
    setDebug("Cast sent (Perfect)")
end

local function recast()
    local delay = Config.Mode == "Blatant" and Config.BlatantRecastDelay or Config.LegitRecastDelay
    task.wait(delay)
    if autoFishing then
        doCast()
    end
end

local cachedFishHandler = nil
local function findFishHandlerLoop()
    if cachedFishHandler then
        return cachedFishHandler
    end
    
    local connOk, conns = pcall(getconnections, RunService.RenderStepped)
    if connOk and type(conns) == "table" then
        for _, conn in pairs(conns) do
            local fn = conn.Function
            if fn then
                local ok, info = pcall(getinfo, fn)
                if ok and info then
                    local src = tostring(info.source or ""):lower()
                    local shortSrc = tostring(info.short_src or ""):lower()
                    if src:find("fishhandler") or shortSrc:find("fishhandler") then
                        local upOk, ups = pcall(getupvalues, fn)
                        if upOk and ups and ups[6] ~= nil then
                            cachedFishHandler = fn
                            return fn
                        end
                    end
                end
            end
        end
    end
    
    local gcOk, gc = pcall(getgc)
    if gcOk and type(gc) == "table" then
        for _, v in pairs(gc) do
            if type(v) == "function" then
                local ok, info = pcall(getinfo, v)
                if ok and info then
                    local src = tostring(info.source or ""):lower()
                    local shortSrc = tostring(info.short_src or ""):lower()
                    if src:find("fishhandler") or shortSrc:find("fishhandler") then
                        local upOk, ups = pcall(getupvalues, v)
                        if upOk and ups and ups[6] ~= nil then
                            cachedFishHandler = v
                            return v
                        end
                    end
                end
            end
        end
    end
    
    return nil
end

-- =============================================
-- STRATEGIES
-- =============================================
local function startInstantLoop()
    if not isPC() then
        setDebug("Instant strategy disabled on mobile to prevent crashes.")
        Config.BlatantStrategy = "blatant"
        updateModeUI()
        return
    end
    
    cancelInstantThread()
    instantThread = task.spawn(function()
        while autoFishing do
            local fn = findFishHandlerLoop()
            if fn then
                local ok, ups = pcall(getupvalues, fn)
                if ok and ups then
                    local isMinigameActive = ups[1]
                    if isMinigameActive == true then
                        local goalScore = ups[8]
                        if goalScore then
                            setStatus("🚀 INSTANT: Struggle...", Color3.fromRGB(0, 220, 150))
                            setDebug("Freezing progress at " .. (Config.SlowReelThreshold * 100) .. "%...")
                            
                            local freezeEnd = tick() + Config.InstantCatchDelay
                            while tick() < freezeEnd and autoFishing do
                                pcall(setupvalue, fn, 6, goalScore * Config.SlowReelThreshold)
                                RunService.Heartbeat:Wait()
                            end
                            if not autoFishing then break end
                            
                            setDebug("Completing catch...")
                            while autoFishing do
                                local currentFn = findFishHandlerLoop()
                                if not currentFn then break end
                                local upOk, currentUps = pcall(getupvalues, currentFn)
                                if not upOk or not currentUps or currentUps[1] == false then break end
                                
                                pcall(setupvalue, currentFn, 6, goalScore + 0.1)
                                RunService.Heartbeat:Wait()
                            end
                            
                            setStatus("Caught!", Color3.fromRGB(100, 220, 255))
                            setDebug("Cycle complete")
                        end
                    end
                end
            end
            task.wait(0.1)
        end
    end)
end

local function strategyTurbo(fishName)
    setStatus("⚡ TURBO: " .. tostring(fishName), Color3.fromRGB(0, 180, 255))
    setDebug("Turbo clicking...")
    startClicking(Config.BlatantClickDelay)
end

local function strategyHybrid(fishName)
    setStatus("🔀 HYBRID: " .. tostring(fishName), Color3.fromRGB(180, 50, 255))
    setDebug("Turbo clicking + backup")

    startClicking(Config.BlatantClickDelay)

    cancelInstantThread()
    instantThread = task.spawn(function()
        task.wait(Config.BlatantHybridDelay)
        if not autoFishing then return end
        if clicking then
            setDebug("Hybrid backup: Firing FishCaught...")
            pcall(Fish.FireServer, Fish, "FishCaught")
        end
    end)
end

local function handleStartFishing(fishName)
    if Config.Mode == "Blatant" then
        local strat = Config.BlatantStrategy
        if strat == "instant" then
            setDebug("Waiting for bite (3-7s delay)...")
        elseif strat == "turbo" then
            strategyTurbo(fishName)
        elseif strat == "hybrid" then
            strategyHybrid(fishName)
        elseif strat == "blatant" then
            task.spawn(function()
                task.wait(Config.InstantCatchDelay)
                if not autoFishing then return end
                setStatus("🔥 BLT: Catching...", Color3.fromRGB(0, 180, 255))
                setDebug("Firing FishCaught remote...")
                pcall(Fish.FireServer, Fish, "FishCaught")
            end)
        end
    else
        setStatus("Clicking! " .. tostring(fishName), Color3.fromRGB(0, 255, 120))
        setDebug("Legit clicking")
        startClicking(Config.LegitClickDelay)
    end
end

-- =============================================
-- MAIN EVENT HANDLERS
-- =============================================
local function handleCatch(eventType, fishName)
    stopClicking()
    if Config.BlatantStrategy ~= "instant" then
        cancelInstantThread()
    end
    waitingForCatch = false
    local label = eventType == "FishCaught" and "Caught! " .. tostring(fishName or "") or "Claimed!"
    setStatus(label, Color3.fromRGB(100, 220, 255))
    setDebug("Catch confirmed")

    recast()
end

local function handleEscape(reason)
    stopClicking()
    if Config.BlatantStrategy ~= "instant" then
        cancelInstantThread()
    end
    waitingForCatch = false
    setStatus("Escaped! Recasting...", Color3.fromRGB(255, 100, 0))
    setDebug("Fish escaped: " .. tostring(reason or ""))
    task.wait(Config.EscapeRecastDelay)
    if autoFishing then doCast() end
end

local function startAutoFish()
    autoFishing = true
    fishCaught = 0
    fishSold = 0
    sessionStart = tick()
    toggleBtn.Text = "■ Stop"
    toggleBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)

    task.spawn(function()
        while autoFishing do
            updateStats()
            task.wait(1)
        end
    end)

    if Config.Mode == "Blatant" then
        lockUIHidden(true)
    end

    connection = Fish.OnClientEvent:Connect(function(eventType, fishName, amount)
        if not autoFishing then return end

        if eventType == "StartFishing" then
            handleStartFishing(fishName)
        elseif eventType == "FishCaught" or eventType == "FishClaimed" then
            fishCaught = fishCaught + 1
            updateStats()
            handleCatch(eventType, fishName)
        elseif eventType == "FishEscaped" then
            handleEscape(fishName)
        elseif eventType == "EquipRod" or eventType == "OpenTreasure" then
            setDebug("Event: " .. tostring(eventType))
        elseif eventType == "Sold" then
            setDebug("Duplicate Sold successfully!")
        else
            setDebug("Unknown: " .. tostring(eventType))
        end
    end)

    if Config.BlatantStrategy == "instant" then
        startInstantLoop()
    end

    task.spawn(function()
        task.wait(0.3)
        doCast()
    end)

    safetyThread = task.spawn(function()
        while autoFishing do
            task.wait(Config.SafetyRecastTime)
            if autoFishing and not clicking and not waitingForCatch then
                setStatus("Safety recast...", Color3.fromRGB(255, 150, 0))
                setDebug("Idle too long, recasting")
                doCast()
            end
        end
    end)

    if Config.AutoSellDupes then
        startAutoSellLoop()
    end

    if Config.AutoCollectTokens then
        startAutoCollectTokensLoop()
    end
end

local function stopAutoFish()
    autoFishing = false
    waitingForCatch = false
    stopClicking()
    cancelInstantThread()
    cancelAutoSellThread()
    cancelCollectTokensThread()
    lockUIHidden(false)

    if connection then
        connection:Disconnect()
        connection = nil
    end
    if safetyThread then
        pcall(task.cancel, safetyThread)
        safetyThread = nil
    end

    toggleBtn.Text = "▶ Start"
    toggleBtn.BackgroundColor3 = Color3.fromRGB(0, 180, 90)
    setStatus("Idle", Color3.fromRGB(180, 180, 180))
    setDebug("")
end

-- =============================================
-- ANTI-AFK ENGINE
-- =============================================
local function bypassAFK()
    pcall(function()
        local vim = game:GetService("VirtualInputManager")
        if vim then
            vim:SendKeyPressEvent(Enum.KeyCode.LeftShift, true, game)
            task.wait(0.1)
            vim:SendKeyPressEvent(Enum.KeyCode.LeftShift, false, game)
        end
    end)
end

player.Idled:Connect(bypassAFK)

task.spawn(function()
    while true do
        task.wait(120)
        bypassAFK()
    end
end)

-- =============================================
-- COLLAPSE & OVAL CAPSULE MINIMIZE CONTROL LOGIC
-- =============================================
local savedCapsulePos = nil  -- Remembers last capsule drag position
local savedPanelPos = nil    -- Remembers last full panel drag position

local function toggleMinimize(minimize)
    UICollapsed = minimize
    if UICollapsed then
        -- Save panel position before shrinking
        savedPanelPos = frame.Position
        
        titleBar.Visible = false
        sidebar.Visible = false
        mainPanel.Visible = false
        divider.Visible = false
        
        frame.Size = UDim2.new(0, 40, 0, 40)
        frameCorner.CornerRadius = UDim.new(0, 20)
        
        -- Snap capsule back to last remembered position (if any)
        if savedCapsulePos then
            frame.Position = savedCapsulePos
        end
        
        minimizedBtn.Visible = true
    else
        minimizedBtn.Visible = false
        
        -- Save current capsule position before expanding
        savedCapsulePos = frame.Position
        
        -- Restore panel to its last dragged position, or center on capsule if first time
        if savedPanelPos then
            frame.Position = savedPanelPos
        else
            local capsulePos = frame.Position
            local capsuleCenterX = capsulePos.X.Offset + 20
            local capsuleCenterY = capsulePos.Y.Offset + 20
            local newX = capsuleCenterX - math.floor(originalWidth / 2)
            local newY = capsuleCenterY - math.floor(originalHeight / 2)
            local viewportSize = workspace.CurrentCamera.ViewportSize
            newX = math.clamp(newX, 0, math.max(0, viewportSize.X - originalWidth))
            newY = math.clamp(newY, 0, math.max(0, viewportSize.Y - originalHeight))
            frame.Position = UDim2.new(0, newX, 0, newY)
        end
        
        frame.Size = UDim2.new(0, originalWidth, 0, originalHeight)
        frameCorner.CornerRadius = UDim.new(0, 10)
        
        titleBar.Visible = true
        sidebar.Visible = true
        mainPanel.Visible = true
        divider.Visible = true
        
        updateModeUI()
    end
end

-- =============================================
-- DRAG SYSTEM & DYNAMIC CLICK VERIFICATION
-- =============================================
local dragToggle = nil
local dragStart = nil
local startPos = nil
local pressTime = 0
local startMousePos = nil

local function startDrag(input)
    dragToggle = true
    dragStart = input.Position
    startMousePos = input.Position
    startPos = frame.Position
    pressTime = tick()
    
    local conn
    conn = input.Changed:Connect(function()
        if input.UserInputState == Enum.UserInputState.End then
            dragToggle = false
            conn:Disconnect()
            -- Click detection: Less than 250ms press and moved less than 5 pixels
            if tick() - pressTime < 0.25 and (input.Position - startMousePos).Magnitude < 5 then
                if UICollapsed then
                    toggleMinimize(false)
                end
            end
        end
    end)
end

frame.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        startDrag(input)
    end
end)

titleBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        startDrag(input)
    end
end)

minimizedBtn.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        startDrag(input)
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if dragToggle and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStart
        frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)

-- =============================================
-- BUTTONS LOGIC CONNECTIONS
-- =============================================
minimizeBtn.MouseButton1Click:Connect(function()
    toggleMinimize(true)
end)

modeBtn.MouseButton1Click:Connect(function()
    local wasRunning = autoFishing
    if wasRunning then stopAutoFish() end
    Config.Mode = Config.Mode == "Blatant" and "Legit" or "Blatant"
    updateModeUI()
    if wasRunning then task.wait(0.2); startAutoFish() end
end)

stratBtn.MouseButton1Click:Connect(function()
    local wasRunning = autoFishing
    if wasRunning then stopAutoFish() end

    for i, s in ipairs(strategies) do
        if s == Config.BlatantStrategy then
            Config.BlatantStrategy = strategies[(i % #strategies) + 1]
            break
        end
    end
    updateModeUI()
    if wasRunning then task.wait(0.2); startAutoFish() end
end)

buyPacksBtn.MouseButton1Click:Connect(function()
    Config.AutoBuyPacks = not Config.AutoBuyPacks
    updateModeUI()
    if Config.AutoBuyPacks then
        startAutoBuyPacksLoop()
    else
        cancelAutoBuyPacksThread()
    end
end)

beltSpeedBtn.MouseButton1Click:Connect(function()
    Config.BeltSpeedSpoof = not Config.BeltSpeedSpoof
    updateModeUI()
    updateBeltSpeedSpoof()
end)

codesBtn.MouseButton1Click:Connect(function()
    redeemAllCodes()
end)

toggleBtn.MouseEnter:Connect(function()
    TweenService:Create(toggleBtn, TweenInfo.new(0.1), {
        BackgroundColor3 = autoFishing and Color3.fromRGB(220, 70, 70) or Color3.fromRGB(0, 210, 110)
    }):Play()
end)
toggleBtn.MouseLeave:Connect(function()
    TweenService:Create(toggleBtn, TweenInfo.new(0.1), {
        BackgroundColor3 = autoFishing and Color3.fromRGB(200, 50, 50) or Color3.fromRGB(0, 180, 90)
    }):Play()
end)

-- =============================================
-- PRECISE DELAY TEXTBOX INPUT LOGIC
-- =============================================
delayInputBox.FocusLost:Connect(function(enterPressed)
    local val = tonumber(delayInputBox.Text)
    if val then
        val = math.max(val, 0.001)
        if Config.BlatantStrategy == "instant" or Config.BlatantStrategy == "blatant" then
            Config.InstantCatchDelay = val
            setDebug("Delay set to " .. val .. "s")
        elseif Config.BlatantStrategy == "hybrid" then
            Config.BlatantHybridDelay = val
            setDebug("Hybrid delay set to " .. val .. "s")
        end
        delayInputBox.Text = tostring(val)
    else
        local currentDelay = (Config.BlatantStrategy == "instant" or Config.BlatantStrategy == "blatant") and Config.InstantCatchDelay or Config.BlatantHybridDelay
        delayInputBox.Text = tostring(currentDelay)
    end
end)

-- =============================================
-- SLOW REEL THRESHOLD / RECAST SPAM INPUT LOGIC
-- =============================================
thresholdInputBox.FocusLost:Connect(function(enterPressed)
    local val = tonumber(thresholdInputBox.Text)
    if val then
        if Config.BlatantStrategy == "instant" then
            val = math.clamp(val, 0.01, 1.0)
            Config.SlowReelThreshold = val
            setDebug("Threshold set to " .. (val * 100) .. "%")
        elseif Config.BlatantStrategy == "blatant" then
            val = math.max(val, 0.001)
            Config.BlatantRecastDelay = val
            setDebug("Recast delay set to " .. val .. "s")
        end
        thresholdInputBox.Text = tostring(val)
    else
        local currentVal = Config.BlatantStrategy == "instant" and Config.SlowReelThreshold or Config.BlatantRecastDelay
        thresholdInputBox.Text = tostring(currentVal)
    end
end)

-- =============================================
-- INIT
-- =============================================
showTab("Fishing")
updateModeUI()
if Config.AutoCollectTokens then
    startAutoCollectTokensLoop()
end
if Config.AutoBuyPacks then
    startAutoBuyPacksLoop()
end
if Config.AutoRelics then
    startAutoRelicsLoop()
end
updateBeltSpeedSpoof()
print("[Auto Fisher v44] Loaded!")
