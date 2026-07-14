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
local MarketplaceService = game:GetService("MarketplaceService")

-- Forward declare local variables that need to be in scope for the hook below
local autoFishing = false
local Config

-- Block Robux purchase prompts and FishEscaped signals on client
pcall(function()
    local mt = getrawmetatable(game)
    if mt then
        setreadonly(mt, false)
        local old = mt.__namecall
        mt.__namecall = newcclosure(function(self, ...)
            local method = getnamecallmethod()
            local args = {...}
            
            -- Blocker 1: Robux prompt purchase protection
            if self == MarketplaceService and (method == "PromptProductPurchase" or method == "PromptPurchase" or method == "PromptGamePassPurchase") then
                return
            end
            
            -- Blocker 2: Auto-fishing escape blocker
            local selfName = pcall(function() return self.Name end) and self.Name
            if selfName and tostring(selfName):lower() == "fish" and (method == "FireServer" or method == "fireServer") and args[1] == "FishEscaped" then
                if autoFishing and Config and Config.BlatantStrategy == "instant" then
                    return
                end
            end
            
            return old(self, ...)
        end)
        setreadonly(mt, true)
    end
end)

local player = Players.LocalPlayer
local PlayerGui = player.PlayerGui
local Fish = ReplicatedStorage.Remotes.Fish

local getinfo = getinfo or (debug and debug.getinfo)
local getupvalues = getupvalues or (debug and debug.getupvalues)
local setupvalue = setupvalue or (debug and debug.setupvalue)

local CardConfig = require(ReplicatedStorage.Modules.Config.Core.CardConfig)
local PetConfig = require(ReplicatedStorage.Modules.Config.Core.PetConfig)
local ReplicatedData = require(ReplicatedFirst:WaitForChild("ReplicatedData"))
local FishHandler = require(ReplicatedStorage.Client.UI.FishHandler)
local RaidHandler = require(ReplicatedStorage.Client.UI.RaidHandler)
local lastPetQuestCheck = 0
local lastPackOpenerCheck = 0
-- =============================================
-- CONFIG
-- =============================================
Config = {
    Mode = "Blatant",

    -- Blatant strategy: "instant" | "turbo" | "hybrid" | "blatant"
    BlatantStrategy = "blatant", -- Default to blatant for stability and crash-proofing

    -- Legit
    LegitClickDelay = 0.05,
    LegitRecastDelay = 1,
    LegitCastValue = 1.0,        -- Perfect cast

    -- Blatant
    BlatantClickDelay = 0.05,
    BlatantHybridDelay = 3.5,
    
    -- Instant/Blatant Catch Delay settings:
    InstantCatchDelay = 1.2,     -- Default delay before catch (e.g. 1.2s struggle)
    SlowReelThreshold = 0.91,     -- Target struggle percentage (default 91% or 0.91)
    
    BlatantRecastDelay = 0.05,   -- Recast delay between catches (default 0.05s)
    BlatantCastValue = 1.0,      -- Perfect cast
    
    -- Auto Sell Duplicate Fish
    AutoSellDupes = false,
    ProtectCookingIngredients = true, -- Protect cooking ingredients
    ProtectRodIngredients = true,     -- Protect rod crafting requirements

    -- Auto Collect drops & card display wall cash
    AutoCollect = false,

    -- Auto Collect spawned tokens (Grade & Travel tokens)
    AutoCollectTokens = true,

    -- Auto Collect Dragon Balls (Spawns + Card Market VII auto-buy)
    AutoCollectDragonBalls = true,

    -- Auto Wish (Shenron)
    AutoWish = false,
    WishType = "GradeTokens",

    -- Auto Roll Pet Eggs (Used to obtain Dragon Ball II)
    AutoRollPets = false,
    AutoPetQuests = false,
    
    -- Auto Pack Opener settings
    AutoPackOpener = false,
    AutoPackTarget = "Ghoul",
    AutoApplyHatchPotions = false,
    
    -- Auto Cook & Rod Settings
    AutoCook = false,
    AutoCookTarget = "Auto All",
    AutoUpgradeRod = false,
    
    -- UI Scale
    UIScale = 1.0,
    
    -- Discord Webhooks
    DiscordWebhookUrl = "",
    NotifyMerchant = false,
    NotifyRareCatches = false,
    NotifyNewIndex = false,
    MinMutationNotify = "Rainbow",
    MerchantHop = false,
    
    PetEggType = "Basic",
    PetRollMethod = "Roll5",

    -- Auto Raid settings (Used to obtain Dragon Ball III + Manga card evolution)
    AutoRaid = false,
    RaidMode = "Auto Select",
    RaidSelectedPack = "Pirate",

    -- Auto Voyage settings (Latest update feature)
    AutoVoyage = false,
    VoyageSelectedPack = "Pirate",

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
-- PERSISTENT CONFIGURATION HELPERS
-- =============================================
local HttpService = game:GetService("HttpService")
local CONFIG_FILE = "AnimeCardCollection_Config.json"

function saveSettings()
    pcall(function()
        if writefile then
            writefile(CONFIG_FILE, HttpService:JSONEncode(Config))
        end
    end)
end

function loadSettings()
    pcall(function()
        if isfile and isfile(CONFIG_FILE) and readfile then
            local raw = readfile(CONFIG_FILE)
            local data = HttpService:JSONDecode(raw)
            if data and type(data) == "table" then
                for k, v in pairs(data) do
                    if type(v) == "table" and k == "SelectedItems" then
                        for key, val in pairs(v) do
                            Config.SelectedItems[key] = val
                        end
                    elseif Config[k] ~= nil then
                        Config[k] = v
                    end
                end
            end
        end
    end)
end

-- Load previous settings on startup
loadSettings()

-- Periodically autosave settings if they change
task.spawn(function()
    local lastSavedConfigStr = HttpService:JSONEncode(Config)
    while true do
        task.wait(2.0)
        pcall(function()
            local currentStr = HttpService:JSONEncode(Config)
            if currentStr ~= lastSavedConfigStr then
                lastSavedConfigStr = currentStr
                saveSettings()
            end
        end)
    end
end)

-- =============================================
-- STATE
-- =============================================
autoFishing = false
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
local lastNotifiedMerchantTime = 0
local sessionStart = 0
local waitingForCatch = false
local UICollapsed = false
local originalWidth = 460
local originalHeight = 320
local strategies = {"instant", "turbo", "hybrid", "blatant"}

local gpuActive = false
local whiteScreen = nil

local FishUI = PlayerGui:FindFirstChild("FishUI")

-- Auto Grading State
local autoGrading = false
local gradingMode = "Single" -- "Single" | "BestToLeast" | "LeastToBest"
local gradingCardName = ""
local gradingTargetGrade = "UR"
local gradingMethod = "Cash"
local gradingThread = nil

-- =============================================
-- STUB DEFINITIONS FOR GUI INITIALIZATION
-- =============================================
-- Global UI elements to save local registers
modeLabel, stratLabel, statusLabel, statsLabel, modeBtn, stratBtn, toggleBtn = nil, nil, nil, nil, nil, nil, nil
inputContainer, thresholdContainer, inputLabel, thresholdLabel, delayInputBox, thresholdInputBox, debugLabel = nil, nil, nil, nil, nil, nil, nil
buyPacksBtn, beltSpeedBtn, sidebar, mainPanel, divider, frame, titleBar, minimizedBtn, frameCorner = nil, nil, nil, nil, nil, nil, nil, nil, nil
gradeStatusLabel, gradeToggleBtn, gradeMethodBtn, gradeTargetBtn, gradeModeBtn, gradingCard, nameRow, targetRow, methodRow = nil, nil, nil, nil, nil, nil, nil, nil, nil
wishTypeBtn, petEggTypeBtn, petRollMethodBtn, raidModeBtn, raidSelectedPackBtn, cardSelectedFn, codesBtn, gradeCardInputBox, raidTimerLabel, voyageSelectedPackBtn = nil, nil, nil, nil, nil, nil, nil, nil, nil, nil


_G.StopAutoFisher = function()
    autoFishing = false
    clicking = false
    autoGrading = false
    pcall(function()
        if FishHandler and FishHandler.InFishingArea then
            FishHandler.ExitFishingArea(true)
        end
    end)
    pcall(function()
        if RaidHandler then
            local lobbyPos = Vector3.new(-536.8, -113.5, -250.9)
            local char = player.Character
            local root = char and char:FindFirstChild("HumanoidRootPart")
            local inLobby = root and (root.Position - lobbyPos).Magnitude < 50
            if inLobby then
                RaidHandler.ExitRaidLobby()
            end
        end
    end)
    if connection then pcall(function() connection:Disconnect() end) end
    if clickThread then pcall(task.cancel, clickThread) end
    if safetyThread then pcall(task.cancel, safetyThread) end
    if instantThread then pcall(task.cancel, instantThread) end
    if _G.BiteConnection then pcall(function() _G.BiteConnection:Disconnect() end) _G.BiteConnection = nil end
    if autoSellThread then pcall(task.cancel, autoSellThread) end
    if collectThread then pcall(task.cancel, collectThread) end
    if collectTokensThread then pcall(task.cancel, collectTokensThread) end
    if autoBuyPacksThread then pcall(task.cancel, autoBuyPacksThread) end
    if autoRelicsThread then pcall(task.cancel, autoRelicsThread) end
    if gradingThread then pcall(task.cancel, gradingThread) end
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
screenGui.Name = "AutoFishUI_v56"
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

uiScale = Instance.new("UIScale")
uiScale.Scale = Config.UIScale or 1.0
uiScale.Parent = frame

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

-- Hamburger menu button for sidebar collapse (mobile friendly)
local menuBtn = Instance.new("TextButton")
menuBtn.Size = UDim2.new(0, 20, 0, 20)
menuBtn.Position = UDim2.new(0, 5, 0.5, -10)
menuBtn.BackgroundTransparency = 1
menuBtn.Text = "☰"
menuBtn.TextColor3 = Color3.fromRGB(230, 230, 235)
menuBtn.TextSize = 14
menuBtn.Font = Enum.Font.GothamBold
menuBtn.Parent = titleBar

local titleText = Instance.new("TextLabel")
titleText.Size = UDim2.new(0.5, 0, 1, 0)
titleText.Position = UDim2.new(0, 30, 0, 0)
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

local sidebarOpen = true
local function toggleSidebar()
    sidebarOpen = not sidebarOpen
    sidebar:TweenPosition(
        sidebarOpen and UDim2.new(0, 0, 0, 26) or UDim2.new(0, -130, 0, 26),
        Enum.EasingDirection.Out,
        Enum.EasingStyle.Quad,
        0.25,
        true
    )
    mainPanel:TweenSizeAndPosition(
        sidebarOpen and UDim2.new(1, -131, 1, -26) or UDim2.new(1, -10, 1, -26),
        sidebarOpen and UDim2.new(0, 131, 0, 26) or UDim2.new(0, 5, 0, 26),
        Enum.EasingDirection.Out,
        Enum.EasingStyle.Quad,
        0.25,
        true
    )
    divider.Visible = sidebarOpen
end

menuBtn.MouseButton1Click:Connect(toggleSidebar)

task.spawn(function()
    task.wait(0.2)
    if not isPC() then
        toggleSidebar()
    end
end)

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
local fishingTab = Instance.new("ScrollingFrame")
fishingTab.Size = UDim2.new(1, -20, 1, -20)
fishingTab.Position = UDim2.new(0, 10, 0, 10)
fishingTab.BackgroundTransparency = 1
fishingTab.BorderSizePixel = 0
fishingTab.ScrollBarThickness = 4
fishingTab.CanvasSize = UDim2.new(0, 0, 0, 300)
fishingTab.Parent = mainPanel
tabFrames["Fishing"] = fishingTab

local conveyorTab = Instance.new("ScrollingFrame")
conveyorTab.Size = UDim2.new(1, -20, 1, -20)
conveyorTab.Position = UDim2.new(0, 10, 0, 10)
conveyorTab.BackgroundTransparency = 1
conveyorTab.BorderSizePixel = 0
conveyorTab.ScrollBarThickness = 4
conveyorTab.CanvasSize = UDim2.new(0, 0, 0, 700)
conveyorTab.Visible = false
conveyorTab.Parent = mainPanel
tabFrames["Conveyor"] = conveyorTab

-- Convert Automation Tab to ScrollingFrame for extended layout
local automationTab = Instance.new("ScrollingFrame")
automationTab.Size = UDim2.new(1, -20, 1, -20)
automationTab.Position = UDim2.new(0, 10, 0, 10)
automationTab.BackgroundTransparency = 1
automationTab.BorderSizePixel = 0
automationTab.ScrollBarThickness = 4
automationTab.CanvasSize = UDim2.new(0, 0, 0, 1228)
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

-- Sort packs from latest to oldest (reverse of CardConfig.List.Packs)
local sortedPacks = {}
for i = #CardConfig.List.Packs, 1, -1 do
    table.insert(sortedPacks, CardConfig.List.Packs[i])
end

local packFrames = {}

-- Populate Conveyor list
for idx, p in ipairs(sortedPacks) do
    local packContainer = Instance.new("Frame")
    packContainer.Size = UDim2.new(1, 0, 0, 0)
    packContainer.AutomaticSize = Enum.AutomaticSize.Y
    packContainer.BackgroundTransparency = 1
    packContainer.BorderSizePixel = 0
    packContainer.Name = p
    packContainer.LayoutOrder = idx
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

-- Card Container for Toggles (Height 175, fitting all toggles plus the Wish Type selector)
local autoCard = createCard(automationTab, "AUTOMATION MODULES", UDim2.new(1, -10, 0, 248), UDim2.new(0, 0, 0, 0))

function createGridToggle(cardParent, labelText, position, size, initialValue, onToggle)
    local row = Instance.new("Frame")
    row.Size = size
    row.Position = position
    row.BackgroundTransparency = 1
    row.Parent = cardParent
    
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -55, 1, 0)
    label.Position = UDim2.new(0, 8, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = labelText
    label.TextColor3 = Color3.fromRGB(200, 200, 210)
    label.TextSize = 10
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Font = Enum.Font.Gotham
    label.Parent = row
    
    local toggle = Instance.new("TextButton")
    toggle.Size = UDim2.new(0, 40, 0, 16)
    toggle.Position = UDim2.new(1, -45, 0.5, -8)
    toggle.BackgroundColor3 = initialValue and Color3.fromRGB(0, 180, 90) or Color3.fromRGB(45, 45, 50)
    toggle.Text = initialValue and "ON" or "OFF"
    toggle.TextColor3 = Color3.fromRGB(255, 255, 255)
    toggle.TextSize = 8
    toggle.Font = Enum.Font.GothamBold
    toggle.Parent = row
    Instance.new("UICorner", toggle).CornerRadius = UDim.new(0, 4)
    
    toggle.MouseButton1Click:Connect(function()
        initialValue = not initialValue
        toggle.BackgroundColor3 = initialValue and Color3.fromRGB(0, 180, 90) or Color3.fromRGB(45, 45, 50)
        toggle.Text = initialValue and "ON" or "OFF"
        onToggle(initialValue)
        saveSettings()
    end)
    
    return toggle
end

-- Add toggles inside the grid card
createGridToggle(autoCard, "🖥️ GPU Saver", UDim2.new(0, 0, 0, 20), UDim2.new(1, 0, 0, 18), Config.GPUSaver, function(val)
    Config.GPUSaver = val
    if val then enableGPU() else disableGPU() end
end)

createGridToggle(autoCard, "🪙 Collect Cash", UDim2.new(0, 0, 0, 38), UDim2.new(1, 0, 0, 18), Config.AutoCollect, function(val)
    Config.AutoCollect = val
    if val then startAutoCollectLoop() else stopAutoCollectLoop() end
end)

createGridToggle(autoCard, "💰 Sell Duplicate Fish", UDim2.new(0, 0, 0, 56), UDim2.new(1, 0, 0, 18), Config.AutoSellDupes, function(val)
    Config.AutoSellDupes = val
    if autoFishing then
        if val then startAutoSellLoop() else cancelAutoSellThread() end
    end
end)

createGridToggle(autoCard, "🍳 Protect Cooking", UDim2.new(0, 0, 0, 74), UDim2.new(1, 0, 0, 18), Config.ProtectCookingIngredients, function(val)
    Config.ProtectCookingIngredients = val
end)

createGridToggle(autoCard, "🎣 Protect Rod Craft", UDim2.new(0, 0, 0, 92), UDim2.new(1, 0, 0, 18), Config.ProtectRodIngredients, function(val)
    Config.ProtectRodIngredients = val
end)

createGridToggle(autoCard, "🪙 Collect Map Tokens", UDim2.new(0, 0, 0, 110), UDim2.new(1, 0, 0, 18), Config.AutoCollectTokens, function(val)
    Config.AutoCollectTokens = val
    if autoFishing then
        startAutoCollectTokensLoop()
    end
end)

createGridToggle(autoCard, "🏺 Auto Craft Relics", UDim2.new(0, 0, 0, 128), UDim2.new(1, 0, 0, 18), Config.AutoRelics, function(val)
    Config.AutoRelics = val
    if val then startAutoRelicsLoop() else cancelAutoRelicsThread() end
end)

createGridToggle(autoCard, "🐉 Collect Dragon Balls", UDim2.new(0, 0, 0, 146), UDim2.new(1, 0, 0, 18), Config.AutoCollectDragonBalls, function(val)
    Config.AutoCollectDragonBalls = val
    if autoFishing then
        startAutoCollectTokensLoop()
    end
end)

createGridToggle(autoCard, "🐉 Auto Wish (Shenron)", UDim2.new(0, 0, 0, 164), UDim2.new(1, 0, 0, 18), Config.AutoWish, function(val)
    Config.AutoWish = val
    if autoFishing then
        startAutoCollectTokensLoop()
    end
end)

-- Wish Type Selection Row
local wishRow = Instance.new("Frame")
wishRow.Size = UDim2.new(1, -16, 0, 20)
wishRow.Position = UDim2.new(0, 0, 0, 184)
wishRow.BackgroundTransparency = 1
wishRow.Parent = autoCard

local wLabel = Instance.new("TextLabel")
wLabel.Size = UDim2.new(1, -105, 1, 0)
wLabel.Position = UDim2.new(0, 8, 0, 0)
wLabel.BackgroundTransparency = 1
wLabel.Text = "🌟 Desired Wish Type:"
wLabel.TextColor3 = Color3.fromRGB(200, 200, 210)
wLabel.TextSize = 10
wLabel.TextXAlignment = Enum.TextXAlignment.Left
wLabel.Font = Enum.Font.Gotham
wLabel.Parent = wishRow

wishTypeBtn = Instance.new("TextButton")
wishTypeBtn.Size = UDim2.new(0, 95, 0, 16)
wishTypeBtn.Position = UDim2.new(1, -95, 0.5, -8)
wishTypeBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
wishTypeBtn.Text = "Wish: GradeTokens"
wishTypeBtn.TextColor3 = Color3.fromRGB(255, 200, 0)
wishTypeBtn.TextSize = 8
wishTypeBtn.Font = Enum.Font.GothamBold
wishTypeBtn.Parent = wishRow
Instance.new("UICorner", wishTypeBtn).CornerRadius = UDim.new(0, 4)

-- UI Scale Slider Row
local scaleRow = Instance.new("Frame")
scaleRow.Size = UDim2.new(1, -16, 0, 20)
scaleRow.Position = UDim2.new(0, 0, 0, 212)
scaleRow.BackgroundTransparency = 1
scaleRow.Parent = autoCard

local scLabel = Instance.new("TextLabel")
scLabel.Size = UDim2.new(0.5, -10, 1, 0)
scLabel.Position = UDim2.new(0, 8, 0, 0)
scLabel.BackgroundTransparency = 1
scLabel.Text = "📏 UI Scale:"
scLabel.TextColor3 = Color3.fromRGB(200, 200, 210)
scLabel.TextSize = 10
scLabel.TextXAlignment = Enum.TextXAlignment.Left
scLabel.Font = Enum.Font.Gotham
scLabel.Parent = scaleRow

local sliderBar = Instance.new("Frame")
sliderBar.Size = UDim2.new(0.5, -45, 0, 4)
sliderBar.Position = UDim2.new(0.5, 0, 0.5, -2)
sliderBar.BackgroundColor3 = Color3.fromRGB(45, 45, 50)
sliderBar.BorderSizePixel = 0
sliderBar.Parent = scaleRow
Instance.new("UICorner", sliderBar).CornerRadius = UDim.new(0, 2)

local sliderKnob = Instance.new("TextButton")
sliderKnob.Size = UDim2.new(0, 12, 0, 12)
sliderKnob.Position = UDim2.new(0, 0, 0.5, -6)
sliderKnob.BackgroundColor3 = Color3.fromRGB(0, 220, 120)
sliderKnob.Text = ""
sliderKnob.BorderSizePixel = 0
sliderKnob.Parent = sliderBar
Instance.new("UICorner", sliderKnob).CornerRadius = UDim.new(0, 6)

local scValueLabel = Instance.new("TextLabel")
scValueLabel.Size = UDim2.new(0, 35, 1, 0)
scValueLabel.Position = UDim2.new(1, -35, 0, 0)
scValueLabel.BackgroundTransparency = 1
scValueLabel.Text = string.format("%.1fx", Config.UIScale or 1.0)
scValueLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
scValueLabel.TextSize = 10
scValueLabel.Font = Enum.Font.GothamBold
scValueLabel.Parent = scaleRow

local function updateScale(xPos)
    local percentage = math.clamp(xPos / sliderBar.AbsoluteSize.X, 0, 1)
    local rawVal = 0.7 + percentage * (1.5 - 0.7)
    local val = math.floor(rawVal * 10 + 0.5) / 10
    sliderKnob.Position = UDim2.new(percentage, -6, 0.5, -6)
    scValueLabel.Text = string.format("%.1fx", val)
    Config.UIScale = val
    if uiScale then
        uiScale.Scale = val
    end
end

local initPercentage = ((Config.UIScale or 1.0) - 0.7) / (1.5 - 0.7)
sliderKnob.Position = UDim2.new(initPercentage, -6, 0.5, -6)

local dragging = false
sliderKnob.MouseButton1Down:Connect(function()
    dragging = true
end)

UserInputService.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local relativeX = input.Position.X - sliderBar.AbsolutePosition.X
        updateScale(relativeX)
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)


-- =============================================
-- PETS & QUESTS AUTOMATION CARD (Y = 198, Height 123)
-- =============================================
local petEggCard = createCard(automationTab, "PETS & QUESTS AUTOMATION", UDim2.new(1, -10, 0, 123), UDim2.new(0, 0, 0, 253))

createGridToggle(petEggCard, "🐾 Auto Roll Pet Eggs", UDim2.new(0, 0, 0, 20), UDim2.new(1, 0, 0, 18), Config.AutoRollPets, function(val)
    Config.AutoRollPets = val
    if autoFishing then
        startAutoCollectTokensLoop()
    end
end)

-- Egg Type Selection Row
local eggRow = Instance.new("Frame")
eggRow.Size = UDim2.new(1, -16, 0, 20)
eggRow.Position = UDim2.new(0, 0, 0, 42)
eggRow.BackgroundTransparency = 1
eggRow.Parent = petEggCard

local eLabel = Instance.new("TextLabel")
eLabel.Size = UDim2.new(1, -105, 1, 0)
eLabel.Position = UDim2.new(0, 8, 0, 0)
eLabel.BackgroundTransparency = 1
eLabel.Text = "🥚 Selected Egg Type:"
eLabel.TextColor3 = Color3.fromRGB(200, 200, 210)
eLabel.TextSize = 10
eLabel.TextXAlignment = Enum.TextXAlignment.Left
eLabel.Font = Enum.Font.Gotham
eLabel.Parent = eggRow

petEggTypeBtn = Instance.new("TextButton")
petEggTypeBtn.Size = UDim2.new(0, 95, 0, 16)
petEggTypeBtn.Position = UDim2.new(1, -95, 0.5, -8)
petEggTypeBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
petEggTypeBtn.Text = "Egg: Basic"
petEggTypeBtn.TextColor3 = Color3.fromRGB(0, 220, 255)
petEggTypeBtn.TextSize = 8
petEggTypeBtn.Font = Enum.Font.GothamBold
petEggTypeBtn.Parent = eggRow
Instance.new("UICorner", petEggTypeBtn).CornerRadius = UDim.new(0, 4)

-- Roll Mode Row
local methodRowPet = Instance.new("Frame")
methodRowPet.Size = UDim2.new(1, -16, 0, 20)
methodRowPet.Position = UDim2.new(0, 0, 0, 68)
methodRowPet.BackgroundTransparency = 1
methodRowPet.Parent = petEggCard

local mLabelPet = Instance.new("TextLabel")
mLabelPet.Size = UDim2.new(1, -105, 1, 0)
mLabelPet.Position = UDim2.new(0, 8, 0, 0)
mLabelPet.BackgroundTransparency = 1
mLabelPet.Text = "⚡ Roll Mode:"
mLabelPet.TextColor3 = Color3.fromRGB(200, 200, 210)
mLabelPet.TextSize = 10
mLabelPet.TextXAlignment = Enum.TextXAlignment.Left
mLabelPet.Font = Enum.Font.Gotham
mLabelPet.Parent = methodRowPet

petRollMethodBtn = Instance.new("TextButton")
petRollMethodBtn.Size = UDim2.new(0, 95, 0, 16)
petRollMethodBtn.Position = UDim2.new(1, -95, 0.5, -8)
petRollMethodBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
petRollMethodBtn.Text = "Mode: Roll 5"
petRollMethodBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
petRollMethodBtn.TextSize = 8
petRollMethodBtn.Font = Enum.Font.GothamBold
petRollMethodBtn.Parent = methodRowPet
Instance.new("UICorner", petRollMethodBtn).CornerRadius = UDim.new(0, 4)


createGridToggle(petEggCard, "🐾 Auto Pet Quests", UDim2.new(0, 0, 0, 94), UDim2.new(1, 0, 0, 18), Config.AutoPetQuests, function(val)
    Config.AutoPetQuests = val
    if autoFishing then
        startAutoCollectTokensLoop()
    end
end)

-- =============================================
-- AUTO PACK OPENER CARD (Y = 326, Height 95)
-- =============================================
local packOpenerCard = createCard(automationTab, "AUTO PACK OPENER", UDim2.new(1, -10, 0, 95), UDim2.new(0, 0, 0, 381))

createGridToggle(packOpenerCard, "📦 Auto Place/Open Packs", UDim2.new(0, 0, 0, 20), UDim2.new(1, 0, 0, 18), Config.AutoPackOpener, function(val)
    Config.AutoPackOpener = val
    if autoFishing then
        startAutoCollectTokensLoop()
    end
end)

-- Target Pack Name Row
local packTargetRow = Instance.new("Frame")
packTargetRow.Size = UDim2.new(1, -16, 0, 20)
packTargetRow.Position = UDim2.new(0, 0, 0, 42)
packTargetRow.BackgroundTransparency = 1
packTargetRow.Parent = packOpenerCard

local ptLabel = Instance.new("TextLabel")
ptLabel.Size = UDim2.new(1, -105, 1, 0)
ptLabel.Position = UDim2.new(0, 8, 0, 0)
ptLabel.BackgroundTransparency = 1
ptLabel.Text = "🎯 Target Pack:"
ptLabel.TextColor3 = Color3.fromRGB(200, 200, 210)
ptLabel.TextSize = 10
ptLabel.TextXAlignment = Enum.TextXAlignment.Left
ptLabel.Font = Enum.Font.Gotham
ptLabel.Parent = packTargetRow

local packTargetInputBox = Instance.new("TextBox")
packTargetInputBox.Size = UDim2.new(0, 95, 0, 16)
packTargetInputBox.Position = UDim2.new(1, -95, 0.5, -8)
packTargetInputBox.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
packTargetInputBox.TextColor3 = Color3.fromRGB(255, 255, 255)
packTargetInputBox.Text = Config.AutoPackTarget
packTargetInputBox.PlaceholderText = "e.g. Ghoul"
packTargetInputBox.TextSize = 10
packTargetInputBox.Font = Enum.Font.GothamBold
packTargetInputBox.ClearTextOnFocus = false
packTargetInputBox.Parent = packTargetRow
Instance.new("UICorner", packTargetInputBox).CornerRadius = UDim.new(0, 4)

packTargetInputBox.FocusLost:Connect(function(enterPressed)
    if packTargetInputBox.Text ~= "" then
        Config.AutoPackTarget = packTargetInputBox.Text
        setDebug("Pack target set to: " .. Config.AutoPackTarget)
    else
        packTargetInputBox.Text = Config.AutoPackTarget
    end
end)

createGridToggle(packOpenerCard, "🧪 Auto Apply Potions", UDim2.new(0, 0, 0, 68), UDim2.new(1, 0, 0, 18), Config.AutoApplyHatchPotions, function(val)
    Config.AutoApplyHatchPotions = val
end)

-- =============================================
-- COOKING & ROD AUTOMATION CARD (Y = 463, Height 95)
-- =============================================
local cookCard = createCard(automationTab, "COOKING & ROD AUTOMATION", UDim2.new(1, -10, 0, 95), UDim2.new(0, 0, 0, 481))

createGridToggle(cookCard, "🍳 Auto Cooking Manager", UDim2.new(0, 0, 0, 20), UDim2.new(1, 0, 0, 18), Config.AutoCook, function(val)
    Config.AutoCook = val
    if autoFishing then
        startAutoCollectTokensLoop()
    end
end)

-- Cooking Target Row
local cookTargetRow = Instance.new("Frame")
cookTargetRow.Size = UDim2.new(1, -16, 0, 20)
cookTargetRow.Position = UDim2.new(0, 0, 0, 42)
cookTargetRow.BackgroundTransparency = 1
cookTargetRow.Parent = cookCard

local ctLabel = Instance.new("TextLabel")
ctLabel.Size = UDim2.new(1, -125, 1, 0)
ctLabel.Position = UDim2.new(0, 8, 0, 0)
ctLabel.BackgroundTransparency = 1
ctLabel.Text = "🎯 Cooking Target:"
ctLabel.TextColor3 = Color3.fromRGB(200, 200, 210)
ctLabel.TextSize = 10
ctLabel.TextXAlignment = Enum.TextXAlignment.Left
ctLabel.Font = Enum.Font.Gotham
ctLabel.Parent = cookTargetRow

local cookTargetBtn = Instance.new("TextButton")
cookTargetBtn.Size = UDim2.new(0, 115, 0, 16)
cookTargetBtn.Position = UDim2.new(1, -115, 0.5, -8)
cookTargetBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
cookTargetBtn.Text = "Target: Auto All"
cookTargetBtn.TextColor3 = Color3.fromRGB(0, 220, 120)
cookTargetBtn.TextSize = 8
cookTargetBtn.Font = Enum.Font.GothamBold
cookTargetBtn.Parent = cookTargetRow
Instance.new("UICorner", cookTargetBtn).CornerRadius = UDim.new(0, 4)

local recipesList = {"Auto All", "CrispyFriedFish", "FishPorridge", "FishStew", "SteamFish", "FishPlatter"}
local recipeDisplayNames = {
    ["Auto All"] = "Auto All",
    CrispyFriedFish = "Crispy Fried Fish",
    FishPorridge = "Fish Porridge",
    FishStew = "Fish Stew",
    SteamFish = "Steam Fish",
    FishPlatter = "Fish Platter"
}

cookTargetBtn.MouseButton1Click:Connect(function()
    local currentIdx = table.find(recipesList, Config.AutoCookTarget) or 1
    local nextIdx = (currentIdx % #recipesList) + 1
    Config.AutoCookTarget = recipesList[nextIdx]
    cookTargetBtn.Text = "Target: " .. recipeDisplayNames[Config.AutoCookTarget]
end)

createGridToggle(cookCard, "🎣 Auto Upgrade Rod", UDim2.new(0, 0, 0, 68), UDim2.new(1, 0, 0, 18), Config.AutoUpgradeRod, function(val)
    Config.AutoUpgradeRod = val
    if autoFishing then
        startAutoCollectTokensLoop()
    end
end)

-- =============================================
-- AUTO RAID CARD (Y = 563, Height 130)
-- =============================================
do -- scope block to reduce top-level local register count
local raidCard = createCard(automationTab, "AUTO RAID AUTOMATION", UDim2.new(1, -10, 0, 130), UDim2.new(0, 0, 0, 581))


createGridToggle(raidCard, "⚔️ Auto Join/Start Raids", UDim2.new(0, 0, 0, 20), UDim2.new(1, 0, 0, 18), Config.AutoRaid, function(val)
    Config.AutoRaid = val
    if not val then
        pcall(function()
            local lobbyPos = Vector3.new(-536.8, -113.5, -250.9)
            local char = player.Character
            local root = char and char:FindFirstChild("HumanoidRootPart")
            local inLobby = root and (root.Position - lobbyPos).Magnitude < 50
            if inLobby then
                RaidHandler.ExitRaidLobby()
            end
        end)
    end
    startAutoCollectTokensLoop()
end)

-- Raid Mode Row
local rModeRow = Instance.new("Frame")
rModeRow.Size = UDim2.new(1, -16, 0, 20)
rModeRow.Position = UDim2.new(0, 0, 0, 42)
rModeRow.BackgroundTransparency = 1
rModeRow.Parent = raidCard

local rmLabel = Instance.new("TextLabel")
rmLabel.Size = UDim2.new(1, -105, 1, 0)
rmLabel.Position = UDim2.new(0, 8, 0, 0)
rmLabel.BackgroundTransparency = 1
rmLabel.Text = "⚔️ Raid Voting Mode:"
rmLabel.TextColor3 = Color3.fromRGB(200, 200, 210)
rmLabel.TextSize = 10
rmLabel.TextXAlignment = Enum.TextXAlignment.Left
rmLabel.Font = Enum.Font.Gotham
rmLabel.Parent = rModeRow

raidModeBtn = Instance.new("TextButton")
raidModeBtn.Size = UDim2.new(0, 95, 0, 16)
raidModeBtn.Position = UDim2.new(1, -95, 0.5, -8)
raidModeBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
raidModeBtn.Text = "Mode: Auto Select"
raidModeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
raidModeBtn.TextSize = 8
raidModeBtn.Font = Enum.Font.GothamBold
raidModeBtn.Parent = rModeRow
Instance.new("UICorner", raidModeBtn).CornerRadius = UDim.new(0, 4)

-- Selected Raid Pack Row
local rPackRow = Instance.new("Frame")
rPackRow.Size = UDim2.new(1, -16, 0, 20)
rPackRow.Position = UDim2.new(0, 0, 0, 68)
rPackRow.BackgroundTransparency = 1
rPackRow.Parent = raidCard

local rpLabel = Instance.new("TextLabel")
rpLabel.Size = UDim2.new(1, -105, 1, 0)
rpLabel.Position = UDim2.new(0, 8, 0, 0)
rpLabel.BackgroundTransparency = 1
rpLabel.Text = "🏷️ Target Raid Pack:"
rpLabel.TextColor3 = Color3.fromRGB(200, 200, 210)
rpLabel.TextSize = 10
rpLabel.TextXAlignment = Enum.TextXAlignment.Left
rpLabel.Font = Enum.Font.Gotham
rpLabel.Parent = rPackRow

raidSelectedPackBtn = Instance.new("TextButton")
raidSelectedPackBtn.Size = UDim2.new(0, 95, 0, 16)
raidSelectedPackBtn.Position = UDim2.new(1, -95, 0.5, -8)
raidSelectedPackBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
raidSelectedPackBtn.Text = "Raid: Pirate"
raidSelectedPackBtn.TextColor3 = Color3.fromRGB(0, 220, 255)
raidSelectedPackBtn.TextSize = 8
raidSelectedPackBtn.Font = Enum.Font.GothamBold
raidSelectedPackBtn.Parent = rPackRow
Instance.new("UICorner", raidSelectedPackBtn).CornerRadius = UDim.new(0, 4)

-- Raid Timer Row
local rTimerRow = Instance.new("Frame")
rTimerRow.Size = UDim2.new(1, -16, 0, 20)
rTimerRow.Position = UDim2.new(0, 0, 0, 94)
rTimerRow.BackgroundTransparency = 1
rTimerRow.Parent = raidCard

local rtLabel = Instance.new("TextLabel")
rtLabel.Size = UDim2.new(1, -105, 1, 0)
rtLabel.Position = UDim2.new(0, 8, 0, 0)
rtLabel.BackgroundTransparency = 1
rtLabel.Text = "⏱️ Raid Cooldown:"
rtLabel.TextColor3 = Color3.fromRGB(200, 200, 210)
rtLabel.TextSize = 10
rtLabel.TextXAlignment = Enum.TextXAlignment.Left
rtLabel.Font = Enum.Font.Gotham
rtLabel.Parent = rTimerRow

raidTimerLabel = Instance.new("TextLabel")
raidTimerLabel.Size = UDim2.new(0, 95, 0, 16)
raidTimerLabel.Position = UDim2.new(1, -95, 0.5, -8)
raidTimerLabel.BackgroundTransparency = 1
raidTimerLabel.Text = "Cooldown: --:--"
raidTimerLabel.TextColor3 = Color3.fromRGB(0, 220, 255)
raidTimerLabel.TextSize = 10
raidTimerLabel.TextXAlignment = Enum.TextXAlignment.Right
raidTimerLabel.Font = Enum.Font.GothamBold
raidTimerLabel.Parent = rTimerRow
end -- end raid card scope block

-- Promo Code Redeemer Button (Y = 698)
do -- scope block for promo code button
codesBtn = Instance.new("TextButton")
codesBtn.Size = UDim2.new(1, -10, 0, 24)
codesBtn.Position = UDim2.new(0, 0, 0, 698)
codesBtn.Text = "🎁 Redeem All Promo Codes"
codesBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
codesBtn.BackgroundColor3 = Color3.fromRGB(70, 30, 120)
codesBtn.TextSize = 11
codesBtn.Font = Enum.Font.GothamBold
codesBtn.Parent = automationTab
Instance.new("UICorner", codesBtn).CornerRadius = UDim.new(0, 6)

local codesBtnStroke = Instance.new("UIStroke", codesBtn)
codesBtnStroke.Thickness = 1
codesBtnStroke.Color = Color3.fromRGB(100, 50, 180)
end -- end promo code scope block

-- =============================================
-- AUTO CARD GRADING CARD (Y = 728)
-- =============================================
do -- scope block for grading card UI
gradingCard = createCard(automationTab, "AUTO CARD GRADING", UDim2.new(1, -10, 0, 180), UDim2.new(0, 0, 0, 746))

-- Grading Mode Row
local modeRow = Instance.new("Frame")
modeRow.Size = UDim2.new(1, -16, 0, 20)
modeRow.Position = UDim2.new(0, 8, 0, 25)
modeRow.BackgroundTransparency = 1
modeRow.Parent = gradingCard

local modeLabel = Instance.new("TextLabel")
modeLabel.Size = UDim2.new(0, 90, 1, 0)
modeLabel.BackgroundTransparency = 1
modeLabel.Text = "Grading Mode:"
modeLabel.TextColor3 = Color3.fromRGB(200, 200, 210)
modeLabel.TextSize = 11
modeLabel.TextXAlignment = Enum.TextXAlignment.Left
modeLabel.Font = Enum.Font.Gotham
modeLabel.Parent = modeRow

gradeModeBtn = Instance.new("TextButton")
gradeModeBtn.Size = UDim2.new(1, -100, 1, 0)
gradeModeBtn.Position = UDim2.new(0, 100, 0, 0)
gradeModeBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
gradeModeBtn.Text = "Mode: Single Card"
gradeModeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
gradeModeBtn.TextSize = 11
gradeModeBtn.Font = Enum.Font.GothamBold
gradeModeBtn.Parent = modeRow
Instance.new("UICorner", gradeModeBtn).CornerRadius = UDim.new(0, 4)

-- Card Name Input Row (Single Card only)
nameRow = Instance.new("Frame")
nameRow.Size = UDim2.new(1, -16, 0, 20)
nameRow.Position = UDim2.new(0, 8, 0, 50)
nameRow.BackgroundTransparency = 1
nameRow.Parent = gradingCard

local cNameLabel = Instance.new("TextLabel")
cNameLabel.Size = UDim2.new(0, 90, 1, 0)
cNameLabel.BackgroundTransparency = 1
cNameLabel.Text = "Card Name:"
cNameLabel.TextColor3 = Color3.fromRGB(200, 200, 210)
cNameLabel.TextSize = 11
cNameLabel.TextXAlignment = Enum.TextXAlignment.Left
cNameLabel.Font = Enum.Font.Gotham
cNameLabel.Parent = nameRow

gradeCardInputBox = Instance.new("TextBox")
gradeCardInputBox.Size = UDim2.new(1, -100, 1, 0)
gradeCardInputBox.Position = UDim2.new(0, 100, 0, 0)
gradeCardInputBox.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
gradeCardInputBox.TextColor3 = Color3.fromRGB(255, 255, 255)
gradeCardInputBox.Text = ""
gradeCardInputBox.PlaceholderText = "e.g. Himmel"
gradeCardInputBox.TextSize = 11
gradeCardInputBox.Font = Enum.Font.GothamBold
gradeCardInputBox.ClearTextOnFocus = false
gradeCardInputBox.Parent = nameRow
Instance.new("UICorner", gradeCardInputBox).CornerRadius = UDim.new(0, 4)

-- Target Grade Row
targetRow = Instance.new("Frame")
targetRow.Size = UDim2.new(1, -16, 0, 20)
targetRow.Position = UDim2.new(0, 8, 0, 75)
targetRow.BackgroundTransparency = 1
targetRow.Parent = gradingCard

local targetLabel = Instance.new("TextLabel")
targetLabel.Size = UDim2.new(0, 90, 1, 0)
targetLabel.BackgroundTransparency = 1
targetLabel.Text = "Target Grade:"
targetLabel.TextColor3 = Color3.fromRGB(200, 200, 210)
targetLabel.TextSize = 11
targetLabel.TextXAlignment = Enum.TextXAlignment.Left
targetLabel.Font = Enum.Font.Gotham
targetLabel.Parent = targetRow

gradeTargetBtn = Instance.new("TextButton")
gradeTargetBtn.Size = UDim2.new(1, -100, 1, 0)
gradeTargetBtn.Position = UDim2.new(0, 100, 0, 0)
gradeTargetBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
gradeTargetBtn.Text = "Target: UR"
gradeTargetBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
gradeTargetBtn.TextSize = 11
gradeTargetBtn.Font = Enum.Font.GothamBold
gradeTargetBtn.Parent = targetRow
Instance.new("UICorner", gradeTargetBtn).CornerRadius = UDim.new(0, 4)

-- Method Row
methodRow = Instance.new("Frame")
methodRow.Size = UDim2.new(1, -16, 0, 20)
methodRow.Position = UDim2.new(0, 8, 0, 100)
methodRow.BackgroundTransparency = 1
methodRow.Parent = gradingCard

local methodLabel = Instance.new("TextLabel")
methodLabel.Size = UDim2.new(0, 90, 1, 0)
methodLabel.BackgroundTransparency = 1
methodLabel.Text = "Roll Method:"
methodLabel.TextColor3 = Color3.fromRGB(200, 200, 210)
methodLabel.TextSize = 11
methodLabel.TextXAlignment = Enum.TextXAlignment.Left
methodLabel.Font = Enum.Font.Gotham
methodLabel.Parent = methodRow

gradeMethodBtn = Instance.new("TextButton")
gradeMethodBtn.Size = UDim2.new(1, -100, 1, 0)
gradeMethodBtn.Position = UDim2.new(0, 100, 0, 0)
gradeMethodBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
gradeMethodBtn.Text = "Method: Cash"
gradeMethodBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
gradeMethodBtn.TextSize = 11
gradeMethodBtn.Font = Enum.Font.GothamBold
gradeMethodBtn.Parent = methodRow
Instance.new("UICorner", gradeMethodBtn).CornerRadius = UDim.new(0, 4)

-- Control Buttons
gradeToggleBtn = Instance.new("TextButton")
gradeToggleBtn.Size = UDim2.new(1, -16, 0, 22)
gradeToggleBtn.Position = UDim2.new(0, 8, 0, 128)
gradeToggleBtn.BackgroundColor3 = Color3.fromRGB(0, 180, 90)
gradeToggleBtn.Text = "▶ Start Grading"
gradeToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
gradeToggleBtn.TextSize = 11
gradeToggleBtn.Font = Enum.Font.GothamBold
gradeToggleBtn.Parent = gradingCard
Instance.new("UICorner", gradeToggleBtn).CornerRadius = UDim.new(0, 6)

gradeStatusLabel = Instance.new("TextLabel")
gradeStatusLabel.Size = UDim2.new(1, -16, 0, 16)
gradeStatusLabel.Position = UDim2.new(0, 8, 0, 155)
gradeStatusLabel.BackgroundTransparency = 1
gradeStatusLabel.Text = "Please enter card name..."
gradeStatusLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
gradeStatusLabel.TextSize = 10
gradeStatusLabel.Font = Enum.Font.Gotham
gradeStatusLabel.Parent = gradingCard
end -- end grading card scope block

-- =============================================
-- AUTO VOYAGE CARD (Y = 660, Height 110)
-- =============================================
do -- scope block for Voyage UI
local voyageCard = createCard(automationTab, "AUTO VOYAGE AUTOMATION", UDim2.new(1, -10, 0, 110), UDim2.new(0, 0, 0, 931))

createGridToggle(voyageCard, "⚓ Auto Voyages", UDim2.new(0, 0, 0, 20), UDim2.new(1, 0, 0, 18), Config.AutoVoyage, function(val)
    Config.AutoVoyage = val
    startAutoCollectTokensLoop()
end)

-- Voyage Pack Row
local vPackRow = Instance.new("Frame")
vPackRow.Size = UDim2.new(1, -16, 0, 20)
vPackRow.Position = UDim2.new(0, 0, 0, 42)
vPackRow.BackgroundTransparency = 1
vPackRow.Parent = voyageCard

local vpLabel = Instance.new("TextLabel")
vpLabel.Size = UDim2.new(1, -105, 1, 0)
vpLabel.Position = UDim2.new(0, 8, 0, 0)
vpLabel.BackgroundTransparency = 1
vpLabel.Text = "⚓ Target Voyage Pack:"
vpLabel.TextColor3 = Color3.fromRGB(200, 200, 210)
vpLabel.TextSize = 10
vpLabel.TextXAlignment = Enum.TextXAlignment.Left
vpLabel.Font = Enum.Font.Gotham
vpLabel.Parent = vPackRow

voyageSelectedPackBtn = Instance.new("TextButton")
voyageSelectedPackBtn.Size = UDim2.new(0, 95, 0, 16)
voyageSelectedPackBtn.Position = UDim2.new(1, -95, 0.5, -8)
voyageSelectedPackBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
voyageSelectedPackBtn.Text = "Pack: Pirate"
voyageSelectedPackBtn.TextColor3 = Color3.fromRGB(0, 220, 255)
voyageSelectedPackBtn.TextSize = 8
voyageSelectedPackBtn.Font = Enum.Font.GothamBold
voyageSelectedPackBtn.Parent = vPackRow
Instance.new("UICorner", voyageSelectedPackBtn).CornerRadius = UDim.new(0, 4)

local function updateVoyagePackUI()
    voyageSelectedPackBtn.Text = "Pack: " .. Config.VoyageSelectedPack
end

local voyagePacks = {"Pirate", "Marine", "Kingdom", "Shinobi", "Curse", "Hero", "Wizard"}
voyageSelectedPackBtn.MouseButton1Click:Connect(function()
    local currentIdx = table.find(voyagePacks, Config.VoyageSelectedPack) or 1
    local nextIdx = (currentIdx % #voyagePacks) + 1
    Config.VoyageSelectedPack = voyagePacks[nextIdx]
    updateVoyagePackUI()
end)

updateVoyagePackUI()
end -- end voyage card scope block

do -- scope block for Discord Webhook UI
local discordCard = createCard(automationTab, "DISCORD NOTIFICATIONS", UDim2.new(1, -10, 0, 165), UDim2.new(0, 0, 0, 1048))

-- Webhook URL TextBox
local urlFrame = Instance.new("Frame")
urlFrame.Size = UDim2.new(1, -16, 0, 18)
urlFrame.Position = UDim2.new(0, 8, 0, 20)
urlFrame.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
urlFrame.Parent = discordCard
Instance.new("UICorner", urlFrame).CornerRadius = UDim.new(0, 4)

local urlInput = Instance.new("TextBox")
urlInput.Size = UDim2.new(1, -10, 1, 0)
urlInput.Position = UDim2.new(0, 5, 0, 0)
urlInput.BackgroundTransparency = 1
urlInput.Text = Config.DiscordWebhookUrl
urlInput.PlaceholderText = "Paste Discord Webhook URL here..."
urlInput.PlaceholderColor3 = Color3.fromRGB(120, 120, 130)
urlInput.TextColor3 = Color3.fromRGB(255, 255, 255)
urlInput.TextSize = 8
urlInput.Font = Enum.Font.Gotham
urlInput.TextXAlignment = Enum.TextXAlignment.Left
urlInput.ClearTextOnFocus = false
urlInput.Parent = urlFrame

urlInput.FocusLost:Connect(function()
    Config.DiscordWebhookUrl = urlInput.Text
    saveSettings()
end)

createGridToggle(discordCard, "🎪 Notify Merchant Spawns", UDim2.new(0, 0, 0, 42), UDim2.new(1, 0, 0, 16), Config.NotifyMerchant, function(val)
    Config.NotifyMerchant = val
    if autoFishing then
        startAutoCollectTokensLoop()
    end
end)

createGridToggle(discordCard, "🐋 Notify Rare Catches", UDim2.new(0, 0, 0, 60), UDim2.new(1, 0, 0, 16), Config.NotifyRareCatches, function(val)
    Config.NotifyRareCatches = val
end)

createGridToggle(discordCard, "🆕 Notify New Discoveries", UDim2.new(0, 0, 0, 78), UDim2.new(1, 0, 0, 16), Config.NotifyNewIndex, function(val)
    Config.NotifyNewIndex = val
end)

-- Min Mutation Selector Row
local mutRow = Instance.new("Frame")
mutRow.Size = UDim2.new(1, -16, 0, 18)
mutRow.Position = UDim2.new(0, 0, 0, 96)
mutRow.BackgroundTransparency = 1
mutRow.Parent = discordCard

local mutLabel = Instance.new("TextLabel")
mutLabel.Size = UDim2.new(1, -105, 1, 0)
mutLabel.Position = UDim2.new(0, 8, 0, 0)
mutLabel.BackgroundTransparency = 1
mutLabel.Text = "✨ Min Mutation Notify:"
mutLabel.TextColor3 = Color3.fromRGB(200, 200, 210)
mutLabel.TextSize = 10
mutLabel.TextXAlignment = Enum.TextXAlignment.Left
mutLabel.Font = Enum.Font.Gotham
mutLabel.Parent = mutRow

local mutBtn = Instance.new("TextButton")
mutBtn.Size = UDim2.new(0, 95, 0, 14)
mutBtn.Position = UDim2.new(1, -95, 0.5, -7)
mutBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
mutBtn.Text = "Min: " .. (Config.MinMutationNotify or "Rainbow")
mutBtn.TextColor3 = Color3.fromRGB(255, 200, 0)
mutBtn.TextSize = 8
mutBtn.Font = Enum.Font.GothamBold
mutBtn.Parent = mutRow
Instance.new("UICorner", mutBtn).CornerRadius = UDim.new(0, 4)

local mutList = {"None", "Gold", "Emerald", "Void", "Diamond", "Rainbow"}
mutBtn.MouseButton1Click:Connect(function()
    local currentIdx = table.find(mutList, Config.MinMutationNotify) or 6
    local nextIdx = (currentIdx % #mutList) + 1
    Config.MinMutationNotify = mutList[nextIdx]
    mutBtn.Text = "Min: " .. Config.MinMutationNotify
    saveSettings()
end)

createGridToggle(discordCard, "⚡ Hop for Merchant", UDim2.new(0, 0, 0, 118), UDim2.new(1, 0, 0, 16), Config.MerchantHop, function(val)
    Config.MerchantHop = val
    if val then
        task.spawn(checkAndHopMerchant)
    end
end)

-- Test Webhook Button
local testBtn = Instance.new("TextButton")
testBtn.Size = UDim2.new(1, -16, 0, 18)
testBtn.Position = UDim2.new(0, 8, 0, 138)
testBtn.BackgroundColor3 = Color3.fromRGB(0, 120, 220)
testBtn.Text = "🧪 Send Test Webhook Message"
testBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
testBtn.TextSize = 8
testBtn.Font = Enum.Font.GothamBold
testBtn.Parent = discordCard
Instance.new("UICorner", testBtn).CornerRadius = UDim.new(0, 4)

testBtn.MouseButton1Click:Connect(function()
    Config.DiscordWebhookUrl = urlInput.Text
    saveSettings()
    
    local embed = {
        title = "🌐 ACC Fishing Assistant - System Diagnostics",
        description = "A test payload has been successfully dispatched from the Roblox client. Your notification integration is fully functional.",
        color = 5635925, -- Green
        timestamp = DateTime.now():ToIsoDate(),
        fields = {
            { name = "🖥️ Environment", value = "Roblox Client", inline = true },
            { name = "🏷️ Server Instance", value = string.format("`%s`", game.JobId), inline = true },
            { name = "✅ Verification", value = "Success", inline = true }
        },
        footer = { text = "ACC Webhook Diagnostics System" }
    }
    sendDiscordWebhook(embed)
end)

end -- end discord card scope block

-- Track the dynamic content size to expand scroll height if items change
automationTab:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(function()
    automationTab.CanvasSize = UDim2.new(0, 0, 0, 1228)
end)


-- =============================================
-- CORE FUNCTION DEFINITIONS
-- =============================================
function isPC()
    return UserInputService.KeyboardEnabled and UserInputService.MouseEnabled
end

function findMyPlot()
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

function shouldBuyPack(packType, mutation)
    local mut = (mutation == "nil" or mutation == nil) and "Regular" or mutation
    return Config.SelectedItems[packType .. "-" .. mut] == true
end

-- =============================================
-- SCREEN GUI COLLAPSE FORCE LOGIC
-- =============================================
function lockUIHidden(lock)
    if uiConnection then
        uiConnection:Disconnect()
        uiConnection = nil
    end
    if lock and FishUI then
        FishUI.Enabled = false
        uiConnection = FishUI:GetPropertyChangedSignal("Enabled"):Connect(function()
            if FishUI.Enabled then
                FishUI.Enabled = false
            end
        end)
    elseif FishUI then
        FishUI.Enabled = true
    end
end

-- =============================================
-- GPU SAVER MODE IMPLEMENTATION
-- =============================================
function enableGPU()
    if gpuActive then return end
    gpuActive = true
    pcall(function()
        settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
        game.Lighting.GlobalShadows = false
        game.Lighting.FogEnd = 1
        setfpscap(8)
    end)
    
    whiteScreen = Instance.new("ScreenGui")
    whiteScreen.Name = "AutoFishUI_GPUSaver"
    whiteScreen.ResetOnSpawn = false
    whiteScreen.DisplayOrder = 999999
    
    local blackFrame = Instance.new("Frame")
    blackFrame.Size = UDim2.new(1, 0, 1, 0)
    blackFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
    blackFrame.BorderSizePixel = 0
    blackFrame.Parent = whiteScreen
    
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0, 400, 0, 100)
    label.Position = UDim2.new(0.5, -200, 0.5, -50)
    label.BackgroundTransparency = 1
    label.Text = "🖥️ GPU SAVER ACTIVE\n\nAuto Fisher running...\nPress 'GPU: OFF' to restore graphics."
    label.TextColor3 = Color3.fromRGB(0, 220, 120)
    label.TextSize = 20
    label.Font = Enum.Font.GothamBold
    label.TextXAlignment = Enum.TextXAlignment.Center
    label.Parent = blackFrame
    
    whiteScreen.Parent = PlayerGui
    setDebug("GPU Saver enabled")
end

function disableGPU()
    if not gpuActive then return end
    gpuActive = false
    pcall(function()
        settings().Rendering.QualityLevel = Enum.QualityLevel.Automatic
        game.Lighting.GlobalShadows = true
        game.Lighting.FogEnd = 100000
        setfpscap(0)
    end)
    if whiteScreen then
        whiteScreen:Destroy()
        whiteScreen = nil
    end
    setDebug("GPU Saver disabled")
end

-- =============================================
-- UPDATE MODE UI CORE FUNCTION
-- =============================================
function updateModeUI()
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

function setStatus(text, color)
    statusLabel.Text = "Status: " .. text
    statusLabel.TextColor3 = color or Color3.fromRGB(180, 180, 180)
end

function setDebug(text)
    debugLabel.Text = text
end

function updateStats()
    local elapsed = math.floor((tick() - sessionStart) / 60)
    statsLabel.Text = string.format("Caught: %d | Sold: %d | Time: %dm", fishCaught, fishSold, elapsed)
end

-- Background task to continuously update the Raid Timer Label
task.spawn(function()
    while true do
        pcall(function()
            if raidTimerLabel then
                local hasRaidStart = RaidHandler.VoteActive == true or RaidHandler.RaidActive == true or workspace:GetAttribute("RaidVoteTime") ~= nil
                if hasRaidStart then
                    raidTimerLabel.Text = "Active!"
                    raidTimerLabel.TextColor3 = Color3.fromRGB(0, 255, 120)
                else
                    local StockHandler = require(ReplicatedStorage.Client.UI.StockHandler)
                    local timeLeft = StockHandler.RaidTimeLeft or 0
                    if timeLeft > 0 then
                        local mins = math.floor(timeLeft / 60)
                        local secs = math.floor(timeLeft % 60)
                        raidTimerLabel.Text = string.format("%02d:%02d", mins, secs)
                        raidTimerLabel.TextColor3 = Color3.fromRGB(0, 220, 255)
                    else
                        raidTimerLabel.Text = "00:00"
                        raidTimerLabel.TextColor3 = Color3.fromRGB(150, 150, 160)
                    end
                end
            end
        end)
        task.wait(1.0)
    end
end)

-- =============================================
-- CONVEYOR SPEED SPOOF ENGINE
-- =============================================
function updateBeltSpeedSpoof()
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
-- AUTO COLLECT MONEY ENGINE (PARALLELIZED & PAGE SWEEP RESTORED)
-- =============================================
function cancelCollectThread()
    if collectThread then
        pcall(task.cancel, collectThread)
        collectThread = nil
    end
end

function startAutoCollectLoop()
    cancelCollectThread()
    local maxPages = 30
    
    collectThread = task.spawn(function()
        -- Thread A: Parallel Card Binder Page-turning Sweep (Runs in parallel with floor collection)
        task.spawn(function()
            while Config.AutoCollect do
                local CardRemote = ReplicatedStorage.Remotes:FindFirstChild("Card")
                if CardRemote then
                    setDebug("Starting binder page sweep...")
                    for page = 1, maxPages do
                        if not Config.AutoCollect then break end
                        
                        local myPlot = findMyPlot()
                        if myPlot then
                            local map = myPlot:FindFirstChild("Map")
                            local display = map and map:FindFirstChild("Display")
                            if display then
                                local left = display:FindFirstChild("Left")
                                local right = display:FindFirstChild("Right")
                                
                                local leftCount = left and #left:GetChildren() or 0
                                local rightCount = right and #right:GetChildren() or 0
                                setDebug(string.format("Page %d/%d (Plot: %s, Slots: %d)", page, maxPages, tostring(myPlot.Name), leftCount + rightCount))
                                
                                if left then
                                    for _, slot in ipairs(left:GetChildren()) do
                                        pcall(function() CardRemote:FireServer("Collect", slot) end)
                                    end
                                end
                                if right then
                                    for _, slot in ipairs(right:GetChildren()) do
                                        pcall(function() CardRemote:FireServer("Collect", slot) end)
                                    end
                                end
                            end
                        end
                        
                        task.wait(0.5) -- Briefly wait to process collection clicks
                        
                        if page < maxPages then
                            if not Config.AutoCollect then break end
                            pcall(function() CardRemote:FireServer("Page", "RightArrow") end)
                            task.wait(1.0) -- Give models enough time to load on the new page
                        end
                    end
                    
                    if Config.AutoCollect then
                        setDebug("Resetting binder to Page 1...")
                        for i = 1, maxPages - 1 do
                            pcall(function() CardRemote:FireServer("Page", "LeftArrow") end)
                            if i % 5 == 0 then task.wait(0.05) end
                        end
                        task.wait(1.0)
                    end
                    setDebug("Binder page sweep complete")
                end
                
                -- Dynamic throttle: Cooldown of 15 seconds before sweeping pages again
                for i = 1, 15 do
                    if not Config.AutoCollect then break end
                    task.wait(1.0)
                end
            end
        end)
        
        -- Thread B: Floor Drops loop (Runs every 1.0 second continuously)
        while Config.AutoCollect do
            local char = player.Character
            local root = char and char:FindFirstChild("HumanoidRootPart")
            if root then
                local drops = {}
                pcall(function()
                    local dropFolders = {
                        workspace:FindFirstChild("Drops"),
                        workspace:FindFirstChild("Items") and workspace.Items:FindFirstChild("Drops"),
                        workspace:FindFirstChild("Debris"),
                    }
                    for _, folder in ipairs(dropFolders) do
                        if folder then
                            for _, child in ipairs(folder:GetDescendants()) do
                                if child:IsA("TouchTransmitter") and child.Parent then
                                    table.insert(drops, child.Parent)
                                end
                            end
                        end
                    end
                    
                    for _, child in ipairs(workspace:GetChildren()) do
                        if child:IsA("TouchTransmitter") and child.Parent then
                            table.insert(drops, child.Parent)
                        elseif child.Name:lower():find("drop") or child.Name:lower():find("coin") or child.Name:lower():find("yen") then
                            local transmitter = child:FindFirstChildOfClass("TouchTransmitter")
                            if transmitter then
                                table.insert(drops, child)
                            end
                        end
                    end
                end)
                
                for _, part in ipairs(drops) do
                    if not Config.AutoCollect then break end
                    pcall(function()
                        firetouchinterest(root, part, 0)
                        firetouchinterest(root, part, 1)
                    end)
                end
            end
            task.wait(1.0)
        end
    end)
end

function stopAutoCollectLoop()
    cancelCollectThread()
end

-- =============================================
-- AUTO COLLECT TOKENS & POTIONS & DRAGON BALLS ENGINE
-- =============================================
function cancelCollectTokensThread()
    if collectTokensThread then
        pcall(task.cancel, collectTokensThread)
        collectTokensThread = nil
    end
end

-- Get best 3 cards eligible for Raids
function getBestRaidCards()
    local cards = ReplicatedData.GetData("Cards") or {}
    
    local eligible = {}
    for name, data in pairs(cards) do
        local gradeScore = getGradeIndex(data.Grade or "F")
        local levelScore = data.Level or 1
        local score = gradeScore * 1000 + levelScore
        table.insert(eligible, {Name = name, Score = score})
    end
    
    table.sort(eligible, function(a, b) return a.Score > b.Score end)
    
    local result = {}
    for i = 1, math.min(#eligible, 3) do
        table.insert(result, eligible[i].Name)
    end
    return result
end

-- Discord Webhook Sender
function sendDiscordWebhook(embed)
    local url = Config.DiscordWebhookUrl
    if not url or url == "" then 
        warn("[Webhook] Cancelled: No Webhook URL set.")
        return 
    end
    url = url:gsub("%s+", "") -- strip spaces
    
    local payload = {
        username = "ACC Fishing Assistant",
        avatar_url = "https://raw.githubusercontent.com/InfiniteVoid-d/ACC-AUTO-FISHING/main/anime_boy_avatar.png",
        embeds = { embed }
    }
    
    local req = (syn and syn.request) or (http and http.request) or http_request or request or HttpRequest
    if req then
        setDebug("Sending Webhook notification...")
        task.spawn(function()
            local success, err = pcall(req, {
                Url = url,
                Method = "POST",
                Headers = {
                    ["Content-Type"] = "application/json"
                },
                Body = game:GetService("HttpService"):JSONEncode(payload)
            })
            if success then
                setDebug("Webhook notification sent successfully!")
            else
                warn("[Webhook] Request failed: " .. tostring(err))
            end
        end)
    else
        warn("[Webhook] Failed: Your executor does not support HTTP requests (no request/http_request/HttpRequest function found).")
    end
end

-- Retrieve Travel Merchant Stock
local function getMerchantStock()
    local stock = {}
    pcall(function()
        local getMerchantItems = ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("GetMerchantItems")
        if getMerchantItems then
            local items = getMerchantItems:InvokeServer()
            if items then
                for _, itemData in pairs(items) do
                    if type(itemData) == "table" then
                        local name = itemData.Item or itemData.Name or "Unknown Item"
                        local category = itemData.Category or itemData.Type or "General"
                        local price = itemData.Price or itemData.Cost or "Unknown"
                        table.insert(stock, { Name = name, Category = category, Price = price })
                    end
                end
            end
        end
    end)
    
    if #stock == 0 then
        pcall(function()
            local items = ReplicatedData.GetData("MerchantStock") or ReplicatedData.GetData("MerchantItems") or ReplicatedData.GetData("Merchant")
            if items then
                for k, v in pairs(items) do
                    if type(v) == "table" then
                        local name = v.Name or v.Item or tostring(k)
                        local price = v.Price or v.Cost or 0
                        table.insert(stock, { Name = name, Category = "General", Price = price })
                    elseif type(v) == "number" then
                        table.insert(stock, { Name = tostring(k), Category = "General", Price = v })
                    end
                end
            end
        end)
    end
    
    if #stock == 0 then
        pcall(function()
            local npc = workspace:FindFirstChild("Traveling Merchant") or workspace:FindFirstChild("TravelingMerchant")
            if npc then
                for _, desc in ipairs(npc:GetDescendants()) do
                    if desc:IsA("TextLabel") and desc.Visible and desc.Text ~= "" and not desc.Text:find(":") then
                        table.insert(stock, { Name = desc.Text, Category = "NPC Visual", Price = "Unknown" })
                    end
                end
            end
        end)
    end
    
    return stock
end

-- Merchant Server Hopper Function
function hopServer()
    local PLACE_ID = 76285745979410
    local TeleportService = game:GetService("TeleportService")
    local HttpService = game:GetService("HttpService")
    
    setDebug("Fetching public server list to hop...")
    
    local visitedServers = {}
    pcall(function()
        local data = TeleportService:GetLocalPlayerTeleportData()
        if type(data) == "table" and data.visited then
            visitedServers = data.visited
        end
    end)
    visitedServers[game.JobId] = true
    
    local url = ("https://games.roblox.com/v1/games/%s/servers/Public?sortOrder=Asc&limit=100"):format(PLACE_ID)
    
    local function fetchPage(fetchUrl)
        for attempt = 1, 3 do
            task.wait(1.5)
            local s, r = pcall(function() return HttpService:JSONDecode(game:HttpGetAsync(fetchUrl)) end)
            if s and r and not r.errors and r.data then return r end
            warn("[Hopper] Fetch attempt " .. attempt .. " failed. Retrying...")
        end
        return nil
    end
    
    local page = fetchPage(url)
    local availableServers = {}
    if page and page.data then
        for _, server in ipairs(page.data) do
            if server.playing < server.maxPlayers and not visitedServers[server.id] then
                table.insert(availableServers, server)
            end
        end
    end
    
    if #availableServers == 0 then
        setDebug("Clearing visited list and retrying server hop...")
        visitedServers = {}
        visitedServers[game.JobId] = true
        task.wait(1.0)
        if page and page.data then
            for _, server in ipairs(page.data) do
                if server.playing < server.maxPlayers and server.id ~= game.JobId then
                    table.insert(availableServers, server)
                end
            end
        end
    end
    
    if #availableServers > 0 then
        local target = availableServers[math.random(1, #availableServers)]
        visitedServers[target.id] = true
        setDebug("Hopping to server (" .. target.playing .. "/" .. target.maxPlayers .. ")")
        pcall(function()
            TeleportService:TeleportToPlaceInstance(PLACE_ID, target.id, player, nil, {visited = visitedServers})
        end)
    else
        setDebug("No servers found. Retrying in 5s...")
        task.wait(5.0)
        hopServer()
    end
end

-- Check Merchant and Hop
function checkAndHopMerchant()
    if not Config.MerchantHop then return end
    
    setDebug("Waiting 3.5s to verify Traveling Merchant stand...")
    task.wait(3.5)
    
    local hasStand = false
    pcall(function()
        local Items = workspace:WaitForChild("Items", 10)
        local MerchantFolder = Items and Items:WaitForChild("Merchant", 5)
        local ClientFolder = MerchantFolder and MerchantFolder:WaitForChild("Client", 5)
        hasStand = ClientFolder and ClientFolder:WaitForChild("MerchantStand", 5) ~= nil
    end)
    
    if hasStand then
        setDebug("✅ Traveling Merchant Found! Pausing server hop.")
        
        -- Play notification sound
        pcall(function()
            local sound = Instance.new("Sound")
            sound.SoundId = "rbxassetid://9120386446"
            sound.Volume = 1.0
            sound.Parent = workspace
            sound:Play()
            game:GetService("Debris"):AddItem(sound, 6)
        end)
        
        -- Send notification to Discord Webhook
        if Config.NotifyMerchant then
            pcall(function()
                local merchantTime = ReplicatedData.GetData("MerchantTime") or 0
                if lastNotifiedMerchantTime ~= merchantTime then
                    lastNotifiedMerchantTime = merchantTime
                    local stock = getMerchantStock()
                    local stockListText = ""
                    if #stock > 0 then
                        for _, item in ipairs(stock) do
                            stockListText = stockListText .. string.format("• **%s** (%s) - Cost: %s\n", item.Name, item.Category, tostring(item.Price))
                        end
                    else
                        stockListText = "Check in-game to see his rotating stock of Weather Totems, high-value packs, and Potions!"
                    end
                    
                    local minutesLeft = math.floor((merchantTime - os.time()) / 60)
                    local secondsLeft = (merchantTime - os.time()) % 60
                    
                    local embed = {
                        title = "🎪 Plaza Event: Traveling Merchant Located",
                        description = "An active Traveling Merchant has been successfully located. Server hopping has been suspended.",
                        color = 65280, -- Green
                        timestamp = DateTime.now():ToIsoDate(),
                        fields = {
                            { name = "⏱️ Time Remaining", value = string.format("%d minutes, %d seconds", minutesLeft, secondsLeft), inline = true },
                            { name = "🏷️ Server Instance", value = string.format("`%s`", game.JobId), inline = true },
                            { name = "📦 Stock Inventory", value = stockListText, inline = false }
                        },
                        footer = { text = "ACC Auto-Fisher Server Hopper System" }
                    }
                    sendDiscordWebhook(embed)
                end
            end)
        end
    else
        setDebug("No Traveling Merchant found in this server. Hopping...")
        task.wait(1.5)
        hopServer()
    end
end

-- Process Catch Webhook
local function checkAndSendFishWebhook(fullName)
    if not Config.NotifyRareCatches and not Config.NotifyNewIndex then return end
    
    local mutations = {"Gold", "Emerald", "Void", "Diamond", "Rainbow"}
    local mutation = "None"
    local cleanName = fullName
    for _, mut in ipairs(mutations) do
        if fullName:find(mut) then
            mutation = mut
            cleanName = fullName:gsub(mut .. "%s+", "")
            break
        end
    end
    
    local isNew = false
    pcall(function()
        local pokedex = ReplicatedData.GetData("Pokedex") or ReplicatedData.GetData("FishIndex") or {}
        if pokedex[cleanName] == nil then
            isNew = true
        end
    end)
    
    local severity = {
        ["None"] = 0,
        ["Gold"] = 1,
        ["Emerald"] = 2,
        ["Void"] = 3,
        ["Diamond"] = 4,
        ["Rainbow"] = 5
    }
    
    local userMin = Config.MinMutationNotify or "Rainbow"
    local hasMetMutation = severity[mutation] >= (severity[userMin] or 5)
    
    local isRareFish = false
    pcall(function()
        local FishConfig = require(ReplicatedStorage.Modules.Config.Core.FishConfig)
        local fishData = FishConfig.Fish and FishConfig.Fish[cleanName]
        if fishData then
            local multiplier = fishData.Multiplier or fishData.CashMultiplier or 1.0
            if multiplier >= 5.0 or cleanName == "Giant Whale" or cleanName == "Sea King" then
                isRareFish = true
            end
        end
    end)
    
    local shouldNotify = false
    local reason = ""
    if Config.NotifyNewIndex and isNew then
        shouldNotify = true
        reason = "🆕 New Discovery!"
    elseif Config.NotifyRareCatches and (hasMetMutation or isRareFish) then
        shouldNotify = true
        reason = mutation ~= "None" and "✨ Mutated Catch!" or "🐋 Rare Catch!"
    end
    
    if shouldNotify then
        local colorMap = {
            ["None"] = 5635925,       -- Green (0x55ff55)
            ["Gold"] = 16766720,      -- Gold (0xffd700)
            ["Emerald"] = 65407,      -- Emerald (0x00ff7f)
            ["Void"] = 4915330,       -- Indigo (0x4b0082)
            ["Diamond"] = 65535,      -- Cyan (0x00ffff)
            ["Rainbow"] = 16711935    -- Magenta (0xff00ff)
        }
        
        local isLegendary = cleanName == "Giant Whale" or cleanName == "Sea King"
        local embedTitle = isNew and "🆕 Pokedex Update: New Discovery Captured"
            or (mutation ~= "None" and "✨ Rare Event: Mutation Captured"
            or (isLegendary and "🐋 Legendary Event: Species Captured" or "🐋 Rare Event: Species Captured"))
            
        local embedDesc = isNew and "A brand-new fish species has been registered to your local Pokedex."
            or "A high-tier fish species has been successfully reeled in."

        local embed = {
            title = embedTitle,
            description = embedDesc,
            color = colorMap[mutation] or 16777215,
            timestamp = DateTime.now():ToIsoDate(),
            fields = {
                { name = "🐟 Species", value = cleanName, inline = true },
                { name = "✨ Mutation", value = mutation, inline = true },
                { name = "📈 Session Statistics", value = tostring(fishCaught) .. " catches", inline = true }
            },
            footer = { text = "ACC Auto-Fisher Telemetry Logger" }
        }
        sendDiscordWebhook(embed)
    end
end

-- Get remaining active duration of a cooking buff in seconds
local function getRecipeRemainingTime(recipeName)
    local remaining = 0
    
    -- 1. Query the HUD Boosts UI frame directly
    pcall(function()
        local HUD = PlayerGui:FindFirstChild("HUD")
        local boosts = HUD and HUD:FindFirstChild("Frame") and HUD.Frame:FindFirstChild("Boosts")
        local f = boosts and boosts:FindFirstChild(recipeName)
        if f and f.Visible then
            local timer = f:FindFirstChild("Timer")
            if timer then
                local text = timer.Text or ""
                local min, sec = text:match("(%d+):(%d+)")
                if min and sec then
                    remaining = tonumber(min) * 60 + tonumber(sec)
                end
            end
        end
    end)
    
    -- 2. Fallback: Query replicated replica data cache
    if remaining <= 0 then
        pcall(function()
            local buffs = ReplicatedData.GetData("Buffs") or ReplicatedData.GetData("CookBuffs") or ReplicatedData.GetData("Cooking") or ReplicatedData.GetData("ActiveBuffs")
            if buffs and buffs[recipeName] then
                local val = buffs[recipeName]
                if type(val) == "number" then
                    if val > 1700000000 then
                        remaining = math.max(0, val - os.time())
                    else
                        remaining = val
                    end
                elseif type(val) == "table" then
                    local endTime = val.EndTime or val.Expire or val.Time or val.Duration
                    if endTime then
                        if endTime > 1700000000 then
                            remaining = math.max(0, endTime - os.time())
                        else
                            remaining = endTime
                        end
                    end
                end
            end
        end)
    end
    
    -- 3. Fallback: Parse timers from player UI descendants
    if remaining <= 0 then
        pcall(function()
            local mainGui = PlayerGui:FindFirstChild("Main") or PlayerGui:FindFirstChild("UI") or PlayerGui:FindFirstChild("MainGui")
            if mainGui then
                for _, desc in ipairs(mainGui:GetDescendants()) do
                    if desc:IsA("TextLabel") and desc.Visible then
                        local parentName = desc.Parent and desc.Parent.Name or ""
                        if parentName:lower():find(recipeName:lower()) or desc.Name:lower():find("timer") then
                            local text = desc.Text or ""
                            local min, sec = text:match("(%d+):(%d+)")
                            if min and sec then
                                remaining = tonumber(min) * 60 + tonumber(sec)
                                break
                            end
                        end
                    end
                end
            end
        end)
    end
    
    return remaining
end

-- Auto Cooking Helper
function checkAutoCooking()
    local targetRecipe = Config.AutoCookTarget or "Auto All"
    local FishConfig = require(ReplicatedStorage.Modules.Config.Core.FishConfig)
    
    local toCheck = {}
    if targetRecipe == "Auto All" then
        toCheck = {
            "FishPlatter",
            "SteamFish",
            "FishStew",
            "FishPorridge",
            "CrispyFriedFish"
        }
    else
        toCheck = {targetRecipe}
    end
    
    local tokens = ReplicatedData.GetData("FishTokens") or 0
    local fishInv = ReplicatedData.GetData("Fish") or {}
    local equipped = ReplicatedData.GetData("FishEquipped") or {}
    
    for _, recipeName in ipairs(toCheck) do
        local remaining = getRecipeRemainingTime(recipeName)
        if remaining < 10 then -- Only cook if buff is not active or has less than 10 seconds remaining
            local recipe = FishConfig.Recipes[recipeName]
            if recipe and tokens >= recipe.Price then
                local canCook = true
                local items = recipe.Ingredients or recipe.Requirements
                if items then
                    for fName, reqAmt in pairs(items) do
                        local fishData = fishInv[fName]
                        local locked = fishData and fishData.Locked or false
                        local isEquipped = table.find(equipped, fName) ~= nil
                        local availableAmt = (locked or isEquipped) and 0 or (fishData and fishData.Amount or 0)
                        
                        if availableAmt < reqAmt then
                            canCook = false
                            break
                        end
                    end
                else
                    canCook = false
                end
                
                if canCook then
                    setDebug("Auto-Cooking: " .. recipeName)
                    ReplicatedStorage.Remotes.Fish:FireServer("Cook", recipeName)
                    task.wait(1.0)
                    break -- Cooked one, exit loop
                end
            end
        end
    end
end

-- Auto Rod Upgrader Helper
function checkAutoUpgradeRod()
    local FishConfig = require(ReplicatedStorage.Modules.Config.Core.FishConfig)
    local ownedRods = ReplicatedData.GetData("Rods") or {}
    local currentEquipped = ReplicatedData.GetData("RodEquipped")
    
    -- Sort rods by price
    local rods = {}
    for rName, _ in pairs(FishConfig.Rods) do
        table.insert(rods, rName)
    end
    table.sort(rods, function(a, b)
        return FishConfig.Rods[a].Price < FishConfig.Rods[b].Price
    end)
    
    -- 1. Check if we need to craft a new rod
    local nextRod = nil
    for _, rName in ipairs(rods) do
        if not ownedRods[rName] then
            nextRod = rName
            break
        end
    end
    
    if nextRod then
        local rodDef = FishConfig.Rods[nextRod]
        local tokens = ReplicatedData.GetData("FishTokens") or 0
        if tokens >= rodDef.Price then
            local fishInv = ReplicatedData.GetData("Fish") or {}
            local equipped = ReplicatedData.GetData("FishEquipped") or {}
            local canCraft = true
            
            for fName, reqAmt in pairs(rodDef.Requirements) do
                local fishData = fishInv[fName]
                local locked = fishData and fishData.Locked or false
                local isEquipped = table.find(equipped, fName) ~= nil
                local availableAmt = (locked or isEquipped) and 0 or (fishData and fishData.Amount or 0)
                
                if availableAmt < reqAmt then
                    canCraft = false
                    break
                end
            end
            
            if canCraft then
                setDebug("Auto-Crafting rod: " .. nextRod)
                ReplicatedStorage.Remotes.Fish:FireServer("CraftRod", nextRod)
                task.wait(1.0)
            end
        end
    end
    
    -- 2. Equip the best owned rod if not equipped
    local bestOwned = nil
    for _, rName in ipairs(rods) do
        if ownedRods[rName] then
            bestOwned = rName
        end
    end
    
    if bestOwned and currentEquipped ~= bestOwned then
        setDebug("Auto-Equipping rod: " .. bestOwned)
        ReplicatedStorage.Remotes.Fish:FireServer("EquipRod", bestOwned)
        task.wait(0.5)
    end
end

function startAutoCollectTokensLoop()
    local anyActive = Config.AutoCollectTokens or Config.AutoCollectDragonBalls or Config.AutoWish or Config.AutoRollPets or Config.AutoRaid or Config.AutoVoyage or Config.AutoPetQuests or Config.AutoPackOpener or Config.AutoCook or Config.AutoUpgradeRod or Config.NotifyMerchant
    if not anyActive then
        cancelCollectTokensThread()
        return
    end
    if collectTokensThread then return end
    collectTokensThread = task.spawn(function()
        while Config.AutoCollectTokens or Config.AutoCollectDragonBalls or Config.AutoWish or Config.AutoRollPets or Config.AutoRaid or Config.AutoVoyage or Config.AutoPetQuests or Config.AutoPackOpener or Config.AutoCook or Config.AutoUpgradeRod or Config.NotifyMerchant do
            -- Collect Map Tokens & Potions
            if Config.AutoCollectTokens then
                local tag = player.Name .. "Token"
                local clientTokens = workspace:FindFirstChild("Items")
                    and workspace.Items:FindFirstChild("Tokens")
                    and workspace.Items.Tokens:FindFirstChild("Client")

                local activeNames = {}
                pcall(function()
                    for _, child in ipairs(game:GetService("CollectionService"):GetTagged(tag)) do
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
                end)
                
                for name in pairs(collectedTokens) do
                    if not activeNames[name] then
                        collectedTokens[name] = nil
                    end
                end
                
                pcall(function()
                    for _, item in ipairs(game:GetService("CollectionService"):GetTagged("Potions")) do
                        if item:IsA("BasePart") and item.Transparency < 1 then
                            item.Transparency = 1
                            pcall(function() ReplicatedStorage.Remotes.Potion:FireServer("Collect", item.Name) end)
                        end
                    end
                end)
            end

            -- Collect Spawned Dragon Balls
            if Config.AutoCollectDragonBalls then
                -- 1. Workspace Teleport Collect Spawns
                pcall(function()
                    local dbs = game:GetService("CollectionService"):GetTagged("DragonBall")
                    for _, db in ipairs(dbs) do
                        if db:IsA("BasePart") and db:GetAttribute("Collected") ~= true then
                            local char = player.Character
                            local root = char and char:FindFirstChild("HumanoidRootPart")
                            if root then
                                local oldCFrame = root.CFrame
                                db:SetAttribute("Collected", true) -- Prevent double teleport runs
                                setDebug("Found Dragon Ball! Teleporting...")
                                root.CFrame = db.CFrame
                                task.wait(0.15)
                                pcall(function() ReplicatedStorage.Remotes.DragonBall:FireServer("Collect") end)
                                task.wait(0.15)
                                root.CFrame = oldCFrame
                                setDebug("Dragon Ball collected!")
                            end
                        end
                    end
                end)

                -- 2. Card Market (Stock) Dragon Ball VII Auto-Buy
                pcall(function()
                    local StockHandler = nil
                    pcall(function() StockHandler = require(ReplicatedStorage.Client.UI.StockHandler) end)
                    if StockHandler then
                        local ups = nil
                        if getupvalues then
                            local ok, u = pcall(getupvalues, StockHandler.UpdateStock)
                            ups = ok and u
                        end
                        local t4 = ups and ups[2]
                        if t4 and t4.DragonBall == true then
                            local dbData = ReplicatedData.GetData("DragonBalls") or {}
                            local stockItems = ReplicatedData.GetData("StockItems") or {}
                            if dbData["7"] == nil and stockItems.DragonBall ~= true then
                                setDebug("Auto-buying Dragon Ball VII from Card Market...")
                                pcall(function()
                                    ReplicatedStorage.Remotes.Stock:FireServer("Buy", "DragonBall")
                                end)
                                task.wait(1.0)
                            end
                        end
                    end
                end)
            end

            -- Auto Roll Pet Eggs Loop (Gathering Dragon Ball II)
            if Config.AutoRollPets then
                pcall(function()
                    local tokens = ReplicatedData.GetData("PetTokens") or 0
                    local eggData = PetConfig.Eggs[Config.PetEggType]
                    local eggPrice = eggData and eggData.Price or 1
                    local cost = Config.PetRollMethod == "Roll5" and (eggPrice * 5) or eggPrice
                    
                    if tokens >= cost then
                        local remoteName = Config.PetRollMethod == "Roll5" and "Roll5" or "Roll"
                        setDebug("Auto-rolling " .. Config.PetEggType .. " Egg (" .. Config.PetRollMethod .. ")...")
                        pcall(function()
                            ReplicatedStorage.Remotes.Pet:FireServer(remoteName, Config.PetEggType)
                        end)
                        task.wait(0.35) -- Safety delay to respect the local time check limit
                    end
                end)
            end

            -- Auto Raid Logic (Dragon Ball III & Manga Cards Evolve Farming)
            if Config.AutoRaid then
                pcall(function()
                    local lobbyPos = Vector3.new(-536.8, -113.5, -250.9)
                    local char = player.Character
                    local root = char and char:FindFirstChild("HumanoidRootPart")
                    local inLobby = root and (root.Position - lobbyPos).Magnitude < 50
                    
                    local StockHandler = require(ReplicatedStorage.Client.UI.StockHandler)
                    local cooldownLeft = StockHandler and StockHandler.RaidTimeLeft or 300
                    local hasRaidStart = RaidHandler.VoteActive == true or RaidHandler.RaidActive == true or workspace:GetAttribute("RaidVoteTime") ~= nil or cooldownLeft <= 0
                    
                    if hasRaidStart then
                        if not inLobby and not RaidHandler.InRaid then
                            setDebug("Raid starting! Teleporting to Raid Lobby...")
                            RaidHandler.EnterRaidLobby()
                            task.wait(1.0)
                        end
                    else
                        if inLobby and not RaidHandler.InRaid then
                            setDebug("Raid in cooldown. Returning to base plot...")
                            RaidHandler.ExitRaidLobby()
                            task.wait(1.0)
                        end
                    end
                    
                    -- 1. Handling Voting & Start
                    if RaidHandler.VoteActive == true or workspace:GetAttribute("RaidVoteTime") ~= nil then
                        local currentVote = player:GetAttribute("Vote")
                        if not currentVote then
                            local targetPack = nil
                            if Config.RaidMode == "Auto Select" then
                                local RaidConfig = require(ReplicatedStorage.Modules.Config.Core.RaidConfig)
                                for _, packName in ipairs(RaidConfig.ActiveRaids) do
                                    local defeated = ReplicatedData.GetData("RaidsDefeated", "Packs", packName) or 0
                                    if defeated < 9 then
                                        targetPack = packName
                                        break
                                    end
                                end
                                targetPack = targetPack or Config.RaidSelectedPack or RaidConfig.ActiveRaids[1]
                            else
                                targetPack = Config.RaidSelectedPack
                            end
                            
                            if targetPack then
                                setDebug("Auto-voting for " .. targetPack .. " Raid...")
                                pcall(function() ReplicatedStorage.Remotes.Raid:FireServer("Vote", targetPack) end)
                            end
                        end
                        
                        -- QuickStart if we are alone in the server
                        if #game.Players:GetPlayers() <= 1 then
                            pcall(function() ReplicatedStorage.Remotes.Raid:FireServer("QuickStart") end)
                        end
                    end
                    
                    -- 2. Handling Joining
                    if inLobby and RaidHandler.InRaid == false and workspace:GetAttribute("RaidVoteTime") == nil then
                        local t3 = getBestRaidCards()
                        
                        if t3 and type(t3) == "table" and #t3 > 0 then
                            if #t3 < 3 then
                                local best = getBestRaidCards()
                                for i = 1, #best do
                                    if not table.find(t3, best[i]) and #t3 < 3 then
                                        table.insert(t3, best[i])
                                    end
                                end
                            end
                            
                            setDebug("Auto-joining Raid...")
                            pcall(function() ReplicatedStorage.Remotes.Raid:FireServer("Join", t3) end)
                            task.wait(1.5)
                        end
                    end
                    
                    -- 3. Handling Results Close / Exit
                    local raidGui = PlayerGui:FindFirstChild("Raid")
                    local resultsFrame = raidGui and raidGui:FindFirstChild("Frame") and raidGui.Frame:FindFirstChild("Results")
                    if resultsFrame and resultsFrame.Visible == true then
                        setDebug("Raid completed! Closing results...")
                        pcall(function() RaidHandler.ContinueClicked() end)
                        task.wait(1.0)
                    end
                end)
            end

            -- Auto Voyage Logic (Latest update feature)
            if Config.AutoVoyage then
                pcall(function()
                    local VoyageHandler = require(ReplicatedStorage.Client.UI.VoyageHandler)
                    local VoyageConfig = require(ReplicatedStorage.Modules.Config.Core.VoyageConfig)
                    
                    local VoyageTime = ReplicatedData.GetData("VoyageTime") or 0
                    local serverTime = workspace:GetServerTimeNow()
                    local cooldown = VoyageConfig.GetVoyageCooldown(ReplicatedData.GetReplica())
                    local inCooldown = serverTime - VoyageTime < cooldown
                    
                    local inBattle = VoyageHandler.InBattle == true
                    local inVoyageShip = VoyageHandler.InVoyageShip == true
                    
                    if not inCooldown and not inBattle and not inVoyageShip then
                        setDebug("Voyage cooldown ended. Starting new Voyage...")
                        pcall(function()
                            VoyageHandler.ContinueClicked()
                            ReplicatedStorage.Remotes.Voyage:FireServer("Start", Config.VoyageSelectedPack)
                            VoyageHandler.EnterShip()
                        end)
                        task.wait(2.0)
                    end
                    
                    -- Close results when finished
                    local voyageGui = PlayerGui:FindFirstChild("Voyage")
                    local resultsFrame = voyageGui and voyageGui:FindFirstChild("Frame") and voyageGui.Frame:FindFirstChild("Results")
                    if resultsFrame and resultsFrame.Visible == true then
                        setDebug("Voyage finished! Closing results...")
                        pcall(function() VoyageHandler.ContinueClicked() end)
                        task.wait(1.0)
                    end
                end)
            end

            -- Auto Wish (Shenron) Loop
            if Config.AutoWish then
                pcall(function()
                    local dbData = ReplicatedData.GetData("DragonBalls") or {}
                    local count = 0
                    for _ in pairs(dbData) do count = count + 1 end
                    if count >= 7 then
                        setDebug("Shenron summon active for: " .. Config.WishType)
                        pcall(function()
                            ReplicatedStorage.Remotes.DragonBall:FireServer("Use", Config.WishType)
                        end)
                        task.wait(2.0)
                    end
                end)
            end
            
            -- Auto Pet Quests Loop
            if Config.AutoPetQuests then
                local now = os.time()
                if not lastPetQuestCheck or (now - lastPetQuestCheck) >= 15 then
                    lastPetQuestCheck = now
                    pcall(function()
                        local petQuests = ReplicatedData.GetData("PetQuests") or {}
                        
                        for questId, questData in pairs(petQuests) do
                            if questData.Completed ~= true then
                                local questDef = PetConfig.Quests[questId]
                                if questDef then
                                    -- 1. Potion Crafting Quest
                                    if questDef.Title == "Potion" or questDef.Title == "Potion II" then
                                        local needed = questDef.Requirement - questData.Progress
                                        if needed > 0 then
                                            local packs = ReplicatedData.GetData("Packs") or {}
                                            -- Check if we can craft HatchTime1 (Ninja x4, Soul x3, Pirate x5)
                                            if (packs.Ninja or 0) >= 4 and (packs.Soul or 0) >= 3 and (packs.Pirate or 0) >= 5 then
                                                setDebug("Auto-crafting HatchTime I for Pet Quest...")
                                                ReplicatedStorage.Remotes.Potion:FireServer("Craft", "HatchTime1")
                                                task.wait(0.5)
                                            -- Or check if we can craft Luck1 (Pirate x5, Soul x3, Ninja x4)
                                            elseif (packs.Pirate or 0) >= 5 and (packs.Soul or 0) >= 3 and (packs.Ninja or 0) >= 4 then
                                                setDebug("Auto-crafting Luck I for Pet Quest...")
                                                ReplicatedStorage.Remotes.Potion:FireServer("Craft", "Luck1")
                                                task.wait(0.5)
                                            end
                                        end
                                    
                                    -- 2. Tower Quest
                                    elseif questDef.Title == "Tower" or questDef.Title == "Tower II" then
                                        local towerGui = PlayerGui:FindFirstChild("Tower")
                                        local isTowerActive = towerGui and towerGui:FindFirstChild("Frame") and towerGui.Frame.Visible == true
                                        if not isTowerActive then
                                            setDebug("Starting Tower run for Pet Quest...")
                                            ReplicatedStorage.Remotes.Tower:FireServer("StartTower")
                                            task.wait(2.0)
                                        end

                                    -- 3. Place Packs Quest
                                    elseif questDef.Title == "Place Packs" or questDef.Title == "Place Packs II" then
                                        local packs = ReplicatedData.GetData("Packs") or {}
                                        for packName, count in pairs(packs) do
                                            if count > 0 and packName:find("-Bundle") == nil then
                                                setDebug("Placing " .. packName .. " pack for Pet Quest...")
                                                ReplicatedStorage.Remotes.Card:FireServer("Place", packName)
                                                task.wait(0.2)
                                                break
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end)
                end
            end
            
            -- Auto Pack Opener Loop
            if Config.AutoPackOpener then
                local now = os.time()
                if not lastPackOpenerCheck or (now - lastPackOpenerCheck) >= 8 then
                    lastPackOpenerCheck = now
                    pcall(function()
                        local packsPlaced = ReplicatedData.GetData("PacksPlaced") or {}
                        local maxPlacements = ReplicatedData.GetData("MaxPlacements") or 9
                        local placedCount = 0
                        local hasHatchingPacks = false
                        
                        for _, pData in pairs(packsPlaced) do
                            placedCount = placedCount + 1
                            local serverTime = workspace:GetServerTimeNow()
                            if serverTime - pData.Time < pData.HatchTime then
                                hasHatchingPacks = true
                            end
                        end
                        
                        -- 1. Auto Place Packs if space remains
                        if placedCount < maxPlacements then
                            local ownedPacks = ReplicatedData.GetData("Packs") or {}
                            local target = Config.AutoPackTarget
                            if (ownedPacks[target] or 0) > 0 then
                                setDebug("Auto-placing target pack: " .. target)
                                ReplicatedStorage.Remotes.Card:FireServer("Hotbar", "1", target)
                                task.wait(0.2)
                                ReplicatedStorage.Remotes.Card:FireServer("Equip", target)
                                task.wait(0.2)
                                ReplicatedStorage.Remotes.Card:FireServer("Place", target)
                                task.wait(0.2)
                                ReplicatedStorage.Remotes.Card:FireServer("Unequip", target)
                                task.wait(0.5)
                            end
                        end
                        
                        -- 2. Auto Apply Potions if enabled
                        if Config.AutoApplyHatchPotions and hasHatchingPacks then
                            local consumables = ReplicatedData.GetData("Consumables") or {}
                            local targetPotion = nil
                            if (consumables.HatchTime3 or 0) > 0 then
                                targetPotion = "HatchTime3"
                            elseif (consumables.HatchTime2 or 0) > 0 then
                                targetPotion = "HatchTime2"
                            elseif (consumables.HatchTime1 or 0) > 0 then
                                targetPotion = "HatchTime1"
                            end
                            
                            if targetPotion then
                                setDebug("Auto-applying Hatch Potion: " .. targetPotion)
                                ReplicatedStorage.Remotes.Potion:FireServer("Apply", targetPotion)
                                task.wait(0.5)
                            end
                        end
                        
                        -- 3. Teleport & Trigger ProximityPrompt for Ready Packs
                        local plotName = player:GetAttribute("Plot")
                        local plot = workspace.Plots:FindFirstChild(plotName or "")
                        local char = player.Character
                        local root = char and char:FindFirstChild("HumanoidRootPart")
                        
                        if plot and plot:FindFirstChild("Packs") and root then
                            for _, pack in ipairs(plot.Packs:GetChildren()) do
                                for _, prompt in ipairs(pack:GetDescendants()) do
                                    if prompt:IsA("ProximityPrompt") and prompt.Enabled and prompt.ActionText == "Open Pack" then
                                        setDebug("Teleporting to open pack: " .. pack.Name)
                                        local oldCFrame = root.CFrame
                                        root.CFrame = pack:GetPivot()
                                        task.wait(0.25)
                                        pcall(function()
                                            prompt.HoldDuration = 0
                                            prompt.RequiresLineOfSight = false
                                            if fireproximityprompt then
                                                fireproximityprompt(prompt)
                                            else
                                                prompt:InputBegan(player)
                                            end
                                        end)
                                        task.wait(0.25)
                                        root.CFrame = oldCFrame
                                        task.wait(0.3)
                                    end
                                end
                            end
                        end
                    end)
                end
            end
            
            -- Auto Cooking Check
            if Config.AutoCook then
                local now = os.time()
                if not lastCookingCheck or (now - lastCookingCheck) >= 8 then
                    lastCookingCheck = now
                    pcall(checkAutoCooking)
                end
            end
            
            -- Auto Upgrade Rod Check
            if Config.AutoUpgradeRod then
                local now = os.time()
                if not lastRodCheck or (now - lastRodCheck) >= 10 then
                    lastRodCheck = now
                    pcall(checkAutoUpgradeRod)
                end
            end
            
            -- Traveling Merchant Spawn Notifier
            if Config.NotifyMerchant then
                pcall(function()
                    local merchantTime = ReplicatedData.GetData("MerchantTime") or 0
                    if merchantTime > os.time() then
                        if lastNotifiedMerchantTime ~= merchantTime then
                            lastNotifiedMerchantTime = merchantTime
                            
                            local stock = getMerchantStock()
                            local stockListText = ""
                            if #stock > 0 then
                                for _, item in ipairs(stock) do
                                    stockListText = stockListText .. string.format("• **%s** (Cost: %s)\n", item.Name, tostring(item.Price))
                                end
                            else
                                stockListText = "Check in-game to see his rotating stock of Weather Totems, high-value packs, and Potions!"
                            end
                            
                            local minutesLeft = math.floor((merchantTime - os.time()) / 60)
                            local secondsLeft = (merchantTime - os.time()) % 60
                            
                            local embed = {
                                title = "🎪 Plaza Event: Traveling Merchant Spawned",
                                description = "A new Traveling Merchant has arrived at the Plaza. He will remain active for 10 minutes.",
                                color = 16711850, -- 0xff00aa
                                timestamp = DateTime.now():ToIsoDate(),
                                fields = {
                                    { name = "⏱️ Time Remaining", value = string.format("%d minutes, %d seconds", minutesLeft, secondsLeft), inline = true },
                                    { name = "🏷️ Server Instance", value = string.format("`%s`", game.JobId), inline = true },
                                    { name = "📦 Stock Inventory", value = stockListText, inline = false }
                                },
                                footer = { text = "ACC Auto-Fisher Spawn Alerts System" }
                            }
                            sendDiscordWebhook(embed)
                        end
                    end
                end)
            end
            
            task.wait(1.0)
        end
    end)
end

-- =============================================
-- AUTO BUY PACKS CURRENCY & PRICE HELPERS
-- =============================================
local function getPlayerYen()
    local yen = 0
    pcall(function()
        yen = ReplicatedData.GetData("Yen") or ReplicatedData.GetData("Money") or ReplicatedData.GetData("Cash") or ReplicatedData.GetData("Coins")
    end)
    if not yen or type(yen) ~= "number" then
        pcall(function()
            local leaderstats = player:FindFirstChild("leaderstats")
            local yenVal = leaderstats and (leaderstats:FindFirstChild("Yen") or leaderstats:FindFirstChild("Money") or leaderstats:FindFirstChild("Cash"))
            if yenVal then
                yen = yenVal.Value
            end
        end)
    end
    return yen or 0
end

local suffixes = {
    K = 1e3,
    M = 1e6,
    B = 1e9,
    T = 1e12,
    Q = 1e15,
    QN = 1e18,
    S = 1e21,
    SP = 1e24,
    OC = 1e27,
    N = 1e30
}

local function parseAbbreviatedNumber(str)
    if not str then return nil end
    str = str:gsub("%$", ""):gsub(",", ""):gsub("%s+", "")
    local numPart, suffixPart = str:match("^([%d%.]+)(%a*)$")
    if numPart then
        local num = tonumber(numPart)
        if num then
            if suffixPart and suffixPart ~= "" then
                local multiplier = suffixes[suffixPart:upper()]
                if multiplier then
                    return num * multiplier
                end
            end
            return num
        end
    end
    return nil
end

local mutationMultipliers = {
    Normal = 1,
    Gold = 5,
    Emerald = 10,
    Void = 25,
    Diamond = 60,
    Rainbow = 140
}

local function getPackPrice(packName, mutation)
    local price = nil
    pcall(function()
        if CardConfig.Packs and CardConfig.Packs[packName] then
            local data = CardConfig.Packs[packName]
            price = data.Price or data.Cost or data.Yen or data.Cash or data.Value
        end
        if not price and CardConfig.Prices and CardConfig.Prices[packName] then
            price = CardConfig.Prices[packName]
        end
        if not price and CardConfig[packName] and type(CardConfig[packName]) == "table" then
            price = CardConfig[packName].Price or CardConfig[packName].Cost
        end
    end)
    
    if price and type(price) == "number" then
        local mult = mutationMultipliers[mutation] or 1
        return price * mult
    end
    return price
end

local function getPackPriceFromModel(child)
    local price = nil
    pcall(function()
        local display = child.PrimaryPart and child.PrimaryPart:FindFirstChild("ConveyorDisplay")
        if display then
            for _, v in ipairs(display:GetDescendants()) do
                if v:IsA("TextLabel") and v.Visible then
                    local text = v.Text or ""
                    if text:find("%$") then
                        price = parseAbbreviatedNumber(text)
                        if price then break end
                    end
                end
            end
        end
    end)
    return price
end

local function isRobuxPack(packName)
    local isRobux = false
    pcall(function()
        if CardConfig.Packs and CardConfig.Packs[packName] then
            local data = CardConfig.Packs[packName]
            if data.Robux or data.IsRobux or data.Currency == "Robux" or data.RequireRobux then
                isRobux = true
            end
        end
    end)
    return isRobux
end

local function isRobuxPackFromModel(child)
    local isRobux = false
    pcall(function()
        local display = child.PrimaryPart and child.PrimaryPart:FindFirstChild("ConveyorDisplay")
        if display then
            for _, v in ipairs(display:GetDescendants()) do
                if v:IsA("TextLabel") and v.Visible then
                    local text = v.Text or ""
                    if text:find("Robux") or text:find("R%$") or text:find("") then
                        isRobux = true
                        break
                    end
                end
            end
        end
    end)
    return isRobux
end

-- =============================================
-- AUTO BUY PACKS ENGINE
-- =============================================
function cancelAutoBuyPacksThread()
    if autoBuyPacksThread then
        pcall(task.cancel, autoBuyPacksThread)
        autoBuyPacksThread = nil
    end
end

function startAutoBuyPacksLoop()
    cancelAutoBuyPacksThread()
    autoBuyPacksThread = task.spawn(function()
        local packFolder = nil
        local client = workspace:WaitForChild("Client", 10)
        if client then
            packFolder = client:WaitForChild("Packs", 10)
        end
        if not packFolder then 
            setDebug("Packs folder missing (timed out)!")
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
                
                -- Skip if it requires Robux to buy
                if isRobuxPack(packType) or isRobuxPackFromModel(child) then
                    setDebug("Skipped premium Robux pack: " .. packType)
                    return
                end
                
                -- Verify we have enough in-game Yen/Cash to buy
                local playerYen = getPlayerYen()
                local packPrice = getPackPrice(packType, mutation) or getPackPriceFromModel(child)
                
                if not packPrice then
                    setDebug("Skip " .. packType .. ": Price unresolved")
                    return
                end
                
                if playerYen < packPrice then
                    setDebug(string.format("Skip %s (%s): Need %s (Have %s)", packType, mutation, tostring(packPrice), tostring(playerYen)))
                    return
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
function cancelAutoRelicsThread()
    if autoRelicsThread then
        pcall(task.cancel, autoRelicsThread)
        autoRelicsThread = nil
    end
end

function startAutoRelicsLoop()
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
function redeemAllCodes()
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
function getInventory()
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

local function getRequiredIngredients()
    local cookReq = {}
    local rodReq = {}
    pcall(function()
        local FishConfig = require(ReplicatedStorage.Modules.Config.Core.FishConfig)
        if FishConfig.Recipes then
            for _, r in pairs(FishConfig.Recipes) do
                local items = r.Ingredients or r.Requirements
                if items then
                    for fName, amt in pairs(items) do
                        cookReq[fName] = math.max(cookReq[fName] or 0, amt)
                    end
                end
            end
        end
        if FishConfig.Rods then
            for _, r in pairs(FishConfig.Rods) do
                local items = r.Ingredients or r.Requirements
                if items then
                    for fName, amt in pairs(items) do
                        rodReq[fName] = math.max(rodReq[fName] or 0, amt)
                    end
                end
            end
        end
    end)
    return cookReq, rodReq
end

function sellDuplicates()
    local cookReq, rodReq = getRequiredIngredients()
    local fishList = getInventory()
    if #fishList == 0 then
        return 0
    end

    local totalSoldThisRound = 0
    for _, fishData in ipairs(fishList) do
        if not Config.AutoSellDupes or not autoFishing then break end

        local protect = false
        if Config.ProtectCookingIngredients and cookReq[fishData.name] then
            protect = true
        end
        if Config.ProtectRodIngredients and rodReq[fishData.name] then
            protect = true
        end

        local targetKeep = protect and fishData.amount or 1
        local sellCount = fishData.amount - targetKeep
        if sellCount > 0 then
            setDebug("Auto-Selling " .. fishData.name .. " x" .. sellCount)
            for i = 1, sellCount do
                if not Config.AutoSellDupes or not autoFishing then break end
                pcall(Fish.FireServer, Fish, "Sell", fishData.name)
                totalSoldThisRound = totalSoldThisRound + 1
                task.wait(0.15)
            end
            task.wait(0.3)
        end
    end

    return totalSoldThisRound
end

function cancelAutoSellThread()
    if autoSellThread then
        pcall(task.cancel, autoSellThread)
        autoSellThread = nil
    end
end

function startAutoSellLoop()
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
-- CLICK ENGINE (Viewport-targeted, non-UI-hijacking)
-- =============================================
function simulateClick()
    local vim = nil
    pcall(function() vim = game:GetService("VirtualInputManager") end)
    if vim then
        -- Click at bottom-center of viewport, far from auto-fisher UI (center of screen)
        -- The fishing minigame captures input globally via UserInputService, so position doesn't matter
        -- for the game — but it DOES matter for not hitting our own UI buttons.
        local vp = workspace.CurrentCamera.ViewportSize
        local clickX = vp.X * 0.5
        local clickY = vp.Y * 0.85 -- Bottom 15% of screen, well below center where our UI sits
        pcall(function()
            vim:SendMouseButtonEvent(clickX, clickY, 0, true, game, 0)
            RunService.RenderStepped:Wait()
            vim:SendMouseButtonEvent(clickX, clickY, 0, false, game, 0)
        end)
    end
end

local clickCount = 0
function startClicking(delay)
    if clicking then return end
    clicking = true
    clickCount = 0
    clickThread = task.spawn(function()
        while clicking and autoFishing do
            simulateClick()
            clickCount = clickCount + 1
            -- Breathing gap: every 15 clicks, pause briefly so real user input can get through
            if clickCount % 15 == 0 then
                task.wait(0.12)
            end
            task.wait(delay or Config.LegitClickDelay)
        end
    end)
end

function stopClicking()
    clicking = false
    if clickThread then
        pcall(task.cancel, clickThread)
        clickThread = nil
    end
    pcall(function()
        local vim = game:GetService("VirtualInputManager")
        local vp = workspace.CurrentCamera.ViewportSize
        vim:SendMouseButtonEvent(vp.X * 0.5, vp.Y * 0.85, 0, false, game, 0)
    end)
end

function cancelInstantThread()
    if instantThread then
        pcall(task.cancel, instantThread)
        instantThread = nil
    end
end

-- =============================================
-- CASTING & FISH ENGINE GETGC
-- =============================================
function doCast()
    local castVal = Config.Mode == "Blatant" and Config.BlatantCastValue or Config.LegitCastValue
    pcall(Fish.FireServer, Fish, "CastRod", castVal)
    setStatus("Casting...", Color3.fromRGB(255, 214, 0))
    setDebug("Cast sent (Perfect)")
end

function recast()
    local delay = Config.Mode == "Blatant" and Config.BlatantRecastDelay or Config.LegitRecastDelay
    task.wait(delay)
    if autoFishing then
        doCast()
    end
end



function strategyTurbo(fishName)
    setStatus("⚡ TURBO: " .. tostring(fishName), Color3.fromRGB(0, 180, 255))
    setDebug("Turbo clicking...")
    startClicking(Config.BlatantClickDelay)
end

function strategyHybrid(fishName)
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

function handleStartFishing(fishName)
    if Config.Mode == "Blatant" then
        local strat = Config.BlatantStrategy
        if strat == "instant" or strat == "blatant" then
            if _G.BiteConnection then pcall(function() _G.BiteConnection:Disconnect() end) end
            setStatus(strat == "instant" and "🚀 INS: Waiting bite..." or "🔥 BLT: Waiting bite...", Color3.fromRGB(0, 220, 150))
            setDebug("Waiting for bite sound...")
            local FishAlert = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Sounds"):WaitForChild("Fish"):WaitForChild("FishAlert")
            _G.BiteConnection = FishAlert.Played:Connect(function()
                if not autoFishing or (Config.BlatantStrategy ~= "instant" and Config.BlatantStrategy ~= "blatant") then
                    if _G.BiteConnection then _G.BiteConnection:Disconnect(); _G.BiteConnection = nil end
                    return
                end
                _G.BiteConnection:Disconnect()
                _G.BiteConnection = nil
                
                setStatus(strat == "instant" and "🚀 INS: Catching..." or "🔥 BLT: Catching...", Color3.fromRGB(0, 255, 150))
                setDebug("Bite detected! Waiting catch delay...")
                task.wait(Config.InstantCatchDelay)
                if not autoFishing then return end
                setDebug("Firing FishCaught remote...")
                pcall(Fish.FireServer, Fish, "FishCaught")
            end)
        elseif strat == "turbo" then
            strategyTurbo(fishName)
        elseif strat == "hybrid" then
            strategyHybrid(fishName)
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
function handleCatch(eventType, fishName)
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

function handleEscape(reason)
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

function startAutoFish()
    pcall(function()
        if FishHandler and not FishHandler.InFishingArea then
            FishHandler.EnterFishingArea(true)
        end
    end)
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
            task.spawn(function()
                pcall(checkAndSendFishWebhook, fishName)
            end)
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

    if Config.AutoCollectTokens or Config.AutoCollectDragonBalls or Config.AutoRollPets or Config.AutoRaid or Config.AutoVoyage or Config.AutoWish then
        startAutoCollectTokensLoop()
    end
end

function stopAutoFish()
    autoFishing = false
    waitingForCatch = false
    stopClicking()
    cancelInstantThread()
    if _G.BiteConnection then
        pcall(function() _G.BiteConnection:Disconnect() end)
        _G.BiteConnection = nil
    end
    cancelAutoSellThread()
    if not (Config.AutoRaid or Config.AutoVoyage) then
        cancelCollectTokensThread()
    end
    lockUIHidden(false)

    pcall(function()
        if FishHandler and FishHandler.InFishingArea then
            FishHandler.ExitFishingArea(true)
        end
    end)

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
function bypassAFK()
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
-- KEYBOARD HOTKEY: F6 to Toggle Auto Fish
-- =============================================
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.F6 then
        if autoFishing then
            stopAutoFish()
            setDebug("[F6] Stopped auto fishing")
        else
            startAutoFish()
            setDebug("[F6] Started auto fishing")
        end
    end
end)

-- =============================================
-- COLLAPSE & OVAL CAPSULE MINIMIZE CONTROL LOGIC
-- =============================================
local savedCapsulePos = nil  -- Remembers last capsule drag position
local savedPanelPos = nil    -- Remembers last full panel drag position

function toggleMinimize(minimize)
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

function startDrag(input)
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
-- AUTO CARD GRADING LOGIC IMPLEMENTATION
-- =============================================
function getGradeIndex(gradeName)
    local list = {"F", "E", "D", "C", "B", "A", "S", "S+", "SS", "SR", "UR"}
    return table.find(list, gradeName) or 1
end

function stopAutoGrading()
    autoGrading = false
    if gradingThread then
        pcall(task.cancel, gradingThread)
        gradingThread = nil
    end
    gradeToggleBtn.Text = "▶ Start Grading"
    gradeToggleBtn.BackgroundColor3 = Color3.fromRGB(0, 180, 90)
end

function rollCard(GradeRemote, cardName)
    if gradingMethod == "Tokens" then
        local tokens = ReplicatedData.GetData("GradeTokens") or 0
        if tokens < 1 then
            return false, "No Grade Tokens left!"
        end
        pcall(function() GradeRemote:FireServer("Roll", cardName, "Tokens") end)
        return true
    else
        -- Cash roll logic with strict cost verification
        local cash = getPlayerYen()
        local baseCost = 0
        local Multipliers = nil
        
        pcall(function()
            Multipliers = require(ReplicatedStorage.Modules.Shared.Multipliers)
        end)
        
        if Multipliers then
            pcall(function()
                baseCost = Multipliers.GetGradeCost(cardName) or 0
            end)
        end
        
        local discount = ReplicatedData.GetData("GradeDiscount") or 1
        local actualCost = math.floor(baseCost * discount)
        
        if cash < actualCost then
            return false, "Insufficient Cash! Need: " .. tostring(actualCost)
        end
        
        pcall(function() GradeRemote:FireServer("Roll", cardName) end)
        return true
    end
end

function startAutoGrading()
    if autoGrading then return end
    
    autoGrading = true
    gradeToggleBtn.Text = "■ Stop Grading"
    gradeToggleBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
    
    gradingThread = task.spawn(function()
        local GradeRemote = ReplicatedStorage.Remotes:FindFirstChild("Grade")
        if not GradeRemote then
            setDebug("Grade remote not found!")
            stopAutoGrading()
            return
        end
        
        local targetIdx = getGradeIndex(gradingTargetGrade)
        local packs = CardConfig.List.Packs
        
        if gradingMode == "Single" then
            while autoGrading do
                local currentCards = ReplicatedData.GetData("Cards")
                local cardData = currentCards and currentCards[gradingCardName]
                if not cardData then
                    setDebug("Error: You don't own card '" .. tostring(gradingCardName) .. "'")
                    break
                end
                
                local currentGrade = cardData.Grade or "F"
                local currentIdx = getGradeIndex(currentGrade)
                
                if currentIdx >= targetIdx then
                    setDebug("Success! " .. gradingCardName .. " is now " .. currentGrade)
                    break
                end
                
                local success, err = rollCard(GradeRemote, gradingCardName)
                if not success then
                    if err then setDebug(err) end
                    break
                end
                
                task.wait(0.3)
            end
        else
            -- Collection mode sweeps (Best -> Least or Least -> Best)
            local startIdx, endIdx, step
            if gradingMode == "BestToLeast" then
                startIdx = #packs
                endIdx = 1
                step = -1
            else
                startIdx = 1
                endIdx = #packs
                step = 1
            end
            
            local outOfCurrency = false
            for pIdx = startIdx, endIdx, step do
                if not autoGrading or outOfCurrency then break end
                local packName = packs[pIdx]
                local packData = CardConfig.Packs[packName]
                
                if packData and packData.List then
                    -- Collect and sort cards by Layout order to match binder display
                    local cardNames = {}
                    for name, _ in pairs(packData.List) do
                        table.insert(cardNames, name)
                    end
                    table.sort(cardNames, function(a, b)
                        local la = packData.List[a].Layout or 0
                        local lb = packData.List[b].Layout or 0
                        return la < lb
                    end)
                    
                    -- Grade each owned card in the collection
                    for _, cardName in ipairs(cardNames) do
                        if not autoGrading then break end
                        
                        while autoGrading do
                            local currentCards = ReplicatedData.GetData("Cards")
                            local cardData = currentCards and currentCards[cardName]
                            
                            -- If card is not owned, skip it
                            if not cardData then
                                break
                            end
                            
                            local currentGrade = cardData.Grade or "F"
                            local currentIdx = getGradeIndex(currentGrade)
                            
                            -- If card reached target, skip to next card
                            if currentIdx >= targetIdx then
                                break
                            end
                            
                            -- Live status log inside UI
                            gradeStatusLabel.Text = string.format("[%s] %s: %s -> %s", packName, cardName, currentGrade, gradingTargetGrade)
                            gradeStatusLabel.TextColor3 = Color3.fromRGB(0, 180, 255)
                            
                            local success, err = rollCard(GradeRemote, cardName)
                            if not success then
                                if err then setDebug(err) end
                                outOfCurrency = true
                                break
                            end
                            
                            task.wait(0.3)
                        end
                        if outOfCurrency then break end
                    end
                end
            end
            if not outOfCurrency and autoGrading then
                setDebug("Success: Sweep complete!")
            end
        end
        
        stopAutoGrading()
    end)
end

-- Dynamic Status Checker Loop for Cards
task.spawn(function()
    while true do
        if not screenGui.Parent then break end
        pcall(function()
            if autoGrading and gradingMode ~= "Single" then
                -- Status is updated dynamically by the grading loop thread
            else
                if gradingCardName == "" then
                    gradeStatusLabel.Text = "Please enter card name..."
                    gradeStatusLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
                else
                    local cards = ReplicatedData.GetData("Cards")
                    if cards and cards[gradingCardName] then
                        local currentGrade = cards[gradingCardName].Grade or "F"
                        gradeStatusLabel.Text = "Owned! Current Grade: " .. currentGrade
                        gradeStatusLabel.TextColor3 = Color3.fromRGB(0, 220, 120)
                    else
                        gradeStatusLabel.Text = "Card not found in collection!"
                        gradeStatusLabel.TextColor3 = Color3.fromRGB(220, 60, 60)
                    end
                end
            end
        end)
        task.wait(0.5)
    end
end)

-- Dynamic Layout Shift Helper
function updateGradingUI()
    nameRow.Visible = (gradingMode == "Single")
    if gradingMode == "Single" then
        targetRow.Position = UDim2.new(0, 8, 0, 75)
        methodRow.Position = UDim2.new(0, 8, 0, 100)
        gradeToggleBtn.Position = UDim2.new(0, 8, 0, 128)
        gradeStatusLabel.Position = UDim2.new(0, 8, 0, 155)
        gradingCard.Size = UDim2.new(1, -10, 0, 180)
    else
        targetRow.Position = UDim2.new(0, 8, 0, 50)
        methodRow.Position = UDim2.new(0, 8, 0, 75)
        gradeToggleBtn.Position = UDim2.new(0, 8, 0, 103)
        gradeStatusLabel.Position = UDim2.new(0, 8, 0, 130)
        gradingCard.Size = UDim2.new(1, -10, 0, 155)
    end
end

-- =============================================
-- BUTTON CLICK CONNECTIONS
-- =============================================
do -- scope block for button connections
toggleBtn.MouseButton1Click:Connect(function()
    if autoFishing then stopAutoFish() else startAutoFish() end
end)

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

-- Auto Grading UI Connections
gradeCardInputBox:GetPropertyChangedSignal("Text"):Connect(function()
    gradingCardName = gradeCardInputBox.Text
end)

local modesList = {"Single", "BestToLeast", "LeastToBest"}
gradeModeBtn.MouseButton1Click:Connect(function()
    for i, m in ipairs(modesList) do
        if m == gradingMode then
            gradingMode = modesList[(i % #modesList) + 1]
            break
        end
    end
    gradeModeBtn.Text = gradingMode == "Single" and "Mode: Single Card" 
        or gradingMode == "BestToLeast" and "Mode: Best -> Least"
        or "Mode: Least -> Best"
    updateGradingUI()
end)

local targetsList = {"S", "S+", "SS", "SR", "UR"}
gradeTargetBtn.MouseButton1Click:Connect(function()
    for i, t in ipairs(targetsList) do
        if t == gradingTargetGrade then
            gradingTargetGrade = targetsList[(i % #targetsList) + 1]
            break
        end
    end
    gradeTargetBtn.Text = "Target: " .. gradingTargetGrade
end)

gradeMethodBtn.MouseButton1Click:Connect(function()
    gradingMethod = gradingMethod == "Cash" and "Tokens" or "Cash"
    gradeMethodBtn.Text = "Method: " .. gradingMethod
end)

gradeToggleBtn.MouseButton1Click:Connect(function()
    if autoGrading then stopAutoGrading() else startAutoGrading() end
end)

-- Wish Type Connections
local wishesList = {"GradeTokens", "TraitTokens", "PetTokens", "Cash", "Card", "RainbowCard", "Pet"}
wishTypeBtn.MouseButton1Click:Connect(function()
    for i, w in ipairs(wishesList) do
        if w == Config.WishType then
            Config.WishType = wishesList[(i % #wishesList) + 1]
            break
        end
    end
    wishTypeBtn.Text = "Wish: " .. Config.WishType
end)

-- Pet Egg Type Connections
local petEggsList = {"Basic", "Common", "Uncommon", "Rare", "Epic", "Legendary", "Eternal", "Mythical", "Divine", "Ultimate", "Godly"}
petEggTypeBtn.MouseButton1Click:Connect(function()
    for i, e in ipairs(petEggsList) do
        if e == Config.PetEggType then
            Config.PetEggType = petEggsList[(i % #petEggsList) + 1]
            break
        end
    end
    petEggTypeBtn.Text = "Egg: " .. Config.PetEggType
end)

petRollMethodBtn.MouseButton1Click:Connect(function()
    Config.PetRollMethod = Config.PetRollMethod == "Roll5" and "Roll" or "Roll5"
    petRollMethodBtn.Text = Config.PetRollMethod == "Roll5" and "Mode: Roll 5" or "Mode: Roll 1"
end)

-- Raid Mode Connections
local raidModesList = {"Auto Select", "Manual Select"}
raidModeBtn.MouseButton1Click:Connect(function()
    for i, m in ipairs(raidModesList) do
        if m == Config.RaidMode then
            Config.RaidMode = raidModesList[(i % #raidModesList) + 1]
            break
        end
    end
    raidModeBtn.Text = "Mode: " .. Config.RaidMode
end)

-- Reverse active raids list for dropdown cycles (Newest pack first)
local sortedRaidList = {}
pcall(function()
    local RaidConfig = require(ReplicatedStorage.Modules.Config.Core.RaidConfig)
    for i = #RaidConfig.ActiveRaids, 1, -1 do
        table.insert(sortedRaidList, RaidConfig.ActiveRaids[i])
    end
end)
if #sortedRaidList == 0 then
    sortedRaidList = {"Pirate", "Ninja", "Soul", "Slayer", "Sorcerer", "Dragon", "Fire", "Hero", "Hunter", "Solo"}
end
Config.RaidSelectedPack = sortedRaidList[1] or "Pirate"

raidSelectedPackBtn.MouseButton1Click:Connect(function()
    for i, r in ipairs(sortedRaidList) do
        if r == Config.RaidSelectedPack then
            Config.RaidSelectedPack = sortedRaidList[(i % #sortedRaidList) + 1]
            break
        end
    end
    raidSelectedPackBtn.Text = "Raid: " .. Config.RaidSelectedPack
end)
end -- end button connections scope block

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
updateGradingUI()
if Config.AutoCollectTokens or Config.AutoCollectDragonBalls or Config.AutoRollPets or Config.AutoRaid or Config.AutoVoyage or Config.AutoWish or Config.AutoPetQuests or Config.AutoPackOpener then
    startAutoCollectTokensLoop()
end
if Config.AutoBuyPacks then
    startAutoBuyPacksLoop()
end
if Config.AutoRelics then
    startAutoRelicsLoop()
end
updateBeltSpeedSpoof()
task.spawn(checkAndHopMerchant)
print("[Auto Fisher v56] Loaded successfully!")
