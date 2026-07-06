-- =============================================
-- Auto Fisher v30 - Ultimate Auto Collect Money
-- For: Anime Card Collection (Fish It!)
-- Author: LO + ENI
-- =============================================

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")

local player = Players.LocalPlayer
local PlayerGui = player.PlayerGui
local Fish = ReplicatedStorage.Remotes.Fish

-- =============================================
-- CONFIG
-- =============================================
local Config = {
    Mode = "Blatant",

    -- Blatant strategy: "instant" | "turbo" | "hybrid" | "blatant"
    BlatantStrategy = "instant",

    -- Legit
    LegitClickDelay = 0.05,
    LegitRecastDelay = 1,
    LegitCastValue = 1.0,        -- Perfect cast

    -- Blatant
    BlatantClickDelay = 0.02,
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

    -- GPU Saver
    GPUSaver = false,

    -- Shared
    SafetyRecastTime = 8.0,
    EscapeRecastDelay = 0.1,
}

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
local uiConnection = nil
local fishCaught = 0
local fishSold = 0
local sessionStart = 0
local waitingForCatch = false
local UICollapsed = false
local originalHeight = 250

local gpuActive = false
local whiteScreen = nil

local FishUI = PlayerGui:FindFirstChild("FishUI")

-- =============================================
-- CLEANUP OLD UI
-- =============================================
for _, g in PlayerGui:GetChildren() do
    if g.Name:match("^AutoFishUI") then
        g:Destroy()
    end
end

-- =============================================
-- UI CREATION
-- =============================================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AutoFishUI_v30"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.DisplayOrder = 1000000 -- Stay on top of GPU Saver screen
screenGui.Parent = PlayerGui

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 210, 0, originalHeight)
frame.Position = UDim2.new(0, 20, 0.5, -125)
frame.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true
frame.Parent = screenGui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)

local stroke = Instance.new("UIStroke", frame)
stroke.Thickness = 1.5

-- Title
local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 26)
title.Position = UDim2.new(0, 0, 0, 0)
title.BorderSizePixel = 0
title.Text = " 🎣 Auto Fisher v12"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.TextScaled = true
title.TextXAlignment = Enum.TextXAlignment.Left
title.Font = Enum.Font.GothamBold
title.Parent = frame
Instance.new("UICorner", title).CornerRadius = UDim.new(0, 10)

-- Minimize Button
local minimizeBtn = Instance.new("TextButton")
minimizeBtn.Size = UDim2.new(0, 20, 0, 20)
minimizeBtn.Position = UDim2.new(1, -25, 0, 3)
minimizeBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
minimizeBtn.TextColor3 = Color3.fromRGB(220, 220, 220)
minimizeBtn.Text = "-"
minimizeBtn.TextScaled = true
minimizeBtn.Font = Enum.Font.GothamBold
minimizeBtn.Parent = frame
Instance.new("UICorner", minimizeBtn).CornerRadius = UDim.new(0, 4)

local modeLabel = Instance.new("TextLabel")
modeLabel.Size = UDim2.new(1, -10, 0, 13)
modeLabel.Position = UDim2.new(0, 5, 0, 28)
modeLabel.BackgroundTransparency = 1
modeLabel.TextScaled = true
modeLabel.Font = Enum.Font.GothamBold
modeLabel.Parent = frame

local stratLabel = Instance.new("TextLabel")
stratLabel.Size = UDim2.new(1, -10, 0, 13)
stratLabel.Position = UDim2.new(0, 5, 0, 42)
stratLabel.BackgroundTransparency = 1
stratLabel.TextScaled = true
stratLabel.Font = Enum.Font.Gotham
stratLabel.Parent = frame

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, -10, 0, 13)
statusLabel.Position = UDim2.new(0, 5, 0, 57)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = "Status: Idle"
statusLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
statusLabel.TextScaled = true
statusLabel.Font = Enum.Font.Gotham
statusLabel.Parent = frame

local statsLabel = Instance.new("TextLabel")
statsLabel.Size = UDim2.new(1, -10, 0, 13)
statsLabel.Position = UDim2.new(0, 5, 0, 72)
statsLabel.BackgroundTransparency = 1
statsLabel.Text = "Caught: 0 | Sold: 0 | Time: 0m"
statsLabel.TextColor3 = Color3.fromRGB(120, 120, 140)
statsLabel.TextScaled = true
statsLabel.Font = Enum.Font.Gotham
statsLabel.Parent = frame

-- Buttons row (Mode, Strategy, Toggle)
local modeBtn = Instance.new("TextButton")
modeBtn.Size = UDim2.new(0.33, -5, 0, 24)
modeBtn.Position = UDim2.new(0, 10, 0, 89)
modeBtn.BorderSizePixel = 0
modeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
modeBtn.TextScaled = true
modeBtn.Font = Enum.Font.GothamBold
modeBtn.Parent = frame
Instance.new("UICorner", modeBtn).CornerRadius = UDim.new(0, 6)

local stratBtn = Instance.new("TextButton")
stratBtn.Size = UDim2.new(0.33, -5, 0, 24)
stratBtn.Position = UDim2.new(0.33, 5, 0, 89)
stratBtn.BorderSizePixel = 0
stratBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
stratBtn.TextScaled = true
stratBtn.Font = Enum.Font.GothamBold
stratBtn.Parent = frame
Instance.new("UICorner", stratBtn).CornerRadius = UDim.new(0, 6)

local toggleBtn = Instance.new("TextButton")
toggleBtn.Size = UDim2.new(0.33, -10, 0, 24)
toggleBtn.Position = UDim2.new(0.66, 5, 0, 89)
toggleBtn.BackgroundColor3 = Color3.fromRGB(0, 180, 90)
toggleBtn.BorderSizePixel = 0
toggleBtn.Text = "▶ Start"
toggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleBtn.TextScaled = true
toggleBtn.Font = Enum.Font.GothamBold
toggleBtn.Parent = frame
Instance.new("UICorner", toggleBtn).CornerRadius = UDim.new(0, 6)

-- Toggles Row (GPU Saver & Auto Collect)
local gpuBtn = Instance.new("TextButton")
gpuBtn.Size = UDim2.new(0.5, -15, 0, 20)
gpuBtn.Position = UDim2.new(0, 10, 0, 118)
gpuBtn.BorderSizePixel = 0
gpuBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
gpuBtn.TextScaled = true
gpuBtn.Font = Enum.Font.Gotham
gpuBtn.Parent = frame
Instance.new("UICorner", gpuBtn).CornerRadius = UDim.new(0, 6)

local collectBtn = Instance.new("TextButton")
collectBtn.Size = UDim2.new(0.5, -15, 0, 20)
collectBtn.Position = UDim2.new(0.5, 5, 0, 118)
collectBtn.BorderSizePixel = 0
collectBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
collectBtn.TextScaled = true
collectBtn.Font = Enum.Font.Gotham
collectBtn.Parent = frame
Instance.new("UICorner", collectBtn).CornerRadius = UDim.new(0, 6)

-- Row 8: Auto Sell duplicates (full width)
local autoSellBtn = Instance.new("TextButton")
autoSellBtn.Size = UDim2.new(1, -20, 0, 20)
autoSellBtn.Position = UDim2.new(0, 10, 0, 143)
autoSellBtn.BorderSizePixel = 0
autoSellBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
autoSellBtn.TextScaled = true
autoSellBtn.Font = Enum.Font.Gotham
autoSellBtn.Parent = frame
Instance.new("UICorner", autoSellBtn).CornerRadius = UDim.new(0, 6)

-- =============================================
-- INPUT BOX 1: CATCH DELAY
-- =============================================
local inputContainer = Instance.new("Frame")
inputContainer.Size = UDim2.new(1, -20, 0, 25)
inputContainer.Position = UDim2.new(0, 10, 0, 168)
inputContainer.BackgroundTransparency = 1
inputContainer.Parent = frame

local inputLabel = Instance.new("TextLabel")
inputLabel.Size = UDim2.new(1, -60, 0, 20)
inputLabel.Position = UDim2.new(0, 0, 0, 0)
inputLabel.BackgroundTransparency = 1
inputLabel.Text = "Instant Catch Delay (s):"
inputLabel.TextColor3 = Color3.fromRGB(200, 200, 210)
inputLabel.TextScaled = true
inputLabel.TextXAlignment = Enum.TextXAlignment.Left
inputLabel.Font = Enum.Font.Gotham
inputLabel.Parent = inputContainer

local delayInputBox = Instance.new("TextBox")
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

-- =============================================
-- INPUT BOX 2: SLOW REEL THRESHOLD / RECAST SPAM INTERVAL
-- =============================================
local thresholdContainer = Instance.new("Frame")
thresholdContainer.Size = UDim2.new(1, -20, 0, 25)
thresholdContainer.Position = UDim2.new(0, 10, 0, 198)
thresholdContainer.BackgroundTransparency = 1
thresholdContainer.Parent = frame

local thresholdLabel = Instance.new("TextLabel")
thresholdLabel.Size = UDim2.new(1, -60, 0, 20)
thresholdLabel.Position = UDim2.new(0, 0, 0, 0)
thresholdLabel.BackgroundTransparency = 1
thresholdLabel.Text = "Slow Reel Threshold:"
thresholdLabel.TextColor3 = Color3.fromRGB(200, 200, 210)
thresholdLabel.TextScaled = true
thresholdLabel.TextXAlignment = Enum.TextXAlignment.Left
thresholdLabel.Font = Enum.Font.Gotham
thresholdLabel.Parent = thresholdContainer

local thresholdInputBox = Instance.new("TextBox")
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

local debugLabel = Instance.new("TextLabel")
debugLabel.Size = UDim2.new(1, -10, 0, 13)
debugLabel.Position = UDim2.new(0, 5, 0, 228)
debugLabel.BackgroundTransparency = 1
debugLabel.Text = ""
debugLabel.TextColor3 = Color3.fromRGB(80, 80, 90)
debugLabel.TextScaled = true
debugLabel.Font = Enum.Font.Gotham
debugLabel.Parent = frame

-- =============================================
-- UI HELPERS & UPDATER
-- =============================================
local strategies = {"instant", "turbo", "hybrid", "blatant"}
local childrenToToggle = {
    modeLabel, stratLabel, statusLabel, statsLabel,
    modeBtn, stratBtn, toggleBtn, gpuBtn, collectBtn, autoSellBtn,
    inputContainer, thresholdContainer, debugLabel
}

local function updateModeUI()
    local isBlatant = Config.Mode == "Blatant"

    modeLabel.Text = "Mode: " .. Config.Mode
    modeLabel.TextColor3 = isBlatant and Color3.fromRGB(255, 60, 60) or Color3.fromRGB(0, 200, 120)
    modeBtn.Text = isBlatant and "⚡BLT" or "🎣LEG"
    modeBtn.BackgroundColor3 = isBlatant and Color3.fromRGB(180, 30, 30) or Color3.fromRGB(30, 130, 70)
    title.BackgroundColor3 = isBlatant and Color3.fromRGB(140, 20, 20) or Color3.fromRGB(0, 130, 65)
    stroke.Color = isBlatant and Color3.fromRGB(255, 50, 50) or Color3.fromRGB(0, 200, 100)

    stratBtn.Visible = isBlatant
    stratLabel.Visible = isBlatant
    gpuBtn.Visible = true
    collectBtn.Visible = true
    autoSellBtn.Visible = true
    
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

    gpuBtn.Text = Config.GPUSaver and "🖥️ GPU: ON" or "🖥️ GPU: OFF"
    gpuBtn.BackgroundColor3 = Config.GPUSaver and Color3.fromRGB(180, 100, 0) or Color3.fromRGB(50, 50, 55)

    collectBtn.Text = Config.AutoCollect and "🪙 Collect: ON" or "🪙 Collect: OFF"
    collectBtn.BackgroundColor3 = Config.AutoCollect and Color3.fromRGB(180, 100, 0) or Color3.fromRGB(50, 50, 55)

    autoSellBtn.Text = Config.AutoSellDupes and "💰 SellDupes: ON" or "💰 SellDupes: OFF"
    autoSellBtn.BackgroundColor3 = Config.AutoSellDupes and Color3.fromRGB(180, 100, 0) or Color3.fromRGB(50, 50, 55)
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
-- COLLAPSE/MINIMIZE WINDOW LOGIC
-- =============================================
minimizeBtn.MouseButton1Click:Connect(function()
    UICollapsed = not UICollapsed
    if UICollapsed then
        for _, child in ipairs(childrenToToggle) do
            child.Visible = false
        end
        frame.Size = UDim2.new(0, 210, 0, 26)
        minimizeBtn.Text = "+"
    else
        for _, child in ipairs(childrenToToggle) do
            child.Visible = true
        end
        updateModeUI()
        frame.Size = UDim2.new(0, 210, 0, originalHeight)
        minimizeBtn.Text = "-"
    end
end)

-- =============================================
-- PRECISE DELAY TEXTBOX INPUT LOGIC
-- =============================================
delayInputBox.FocusLost:Connect(function(enterPressed)
    local val = tonumber(delayInputBox.Text)
    if val then
        val = math.max(val, 0.001) -- Clamp at 1ms minimum
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
            val = math.clamp(val, 0.01, 1.0) -- Clamp between 1% and 100%
            Config.SlowReelThreshold = val
            setDebug("Threshold set to " .. (val * 100) .. "%")
        elseif Config.BlatantStrategy == "blatant" then
            val = math.max(val, 0.001) -- Minimum 1ms recast
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
-- SCREEN GUI COLLAPSE FORCE LOGIC
-- =============================================
local function lockUIHidden(lock)
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
local function enableGPU()
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

local function disableGPU()
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
-- AUTO COLLECT MONEY ENGINE (FLOOR & CARD BINDER)
-- =============================================
local function cancelCollectThread()
    if collectThread then
        pcall(task.cancel, collectThread)
        collectThread = nil
    end
end

local function findMyPlot()
    local plotsFolder = workspace:FindFirstChild("Plots")
    if not plotsFolder then return nil end
    for _, p in ipairs(plotsFolder:GetChildren()) do
        for _, descendant in ipairs(p:GetDescendants()) do
            if descendant.Name == "Owner" and descendant:IsA("StringValue") and descendant.Value == player.Name then
                return p
            end
        end
    end
    return nil
end

local function startAutoCollectLoop()
    cancelCollectThread()
    local lastCardCollect = 0
    
    collectThread = task.spawn(function()
        while Config.AutoCollect and autoFishing do
            -- 1. Floor Drops Sweep
            pcall(function()
                local char = player.Character
                local root = char and char:FindFirstChild("HumanoidRootPart")
                if root then
                    for _, v in pairs(workspace:GetDescendants()) do
                        if not Config.AutoCollect or not autoFishing then break end
                        if v:IsA("TouchTransmitter") and v.Parent then
                            local name = v.Parent.Name:lower()
                            if name:find("coin") or name:find("yen") or name:find("money") or name:find("gem") or name:find("drop") or name:find("cash") or name:find("gold") then
                                firetouchinterest(root, v.Parent, 0)
                                task.wait()
                                firetouchinterest(root, v.Parent, 1)
                            end
                        end
                    end
                end
            end)
            
            -- 2. Card Binder Sweep (Runs every 20 seconds)
            if tick() - lastCardCollect > 20 then
                lastCardCollect = tick()
                pcall(function()
                    local CardRemote = ReplicatedStorage.Remotes:FindFirstChild("Card")
                    if CardRemote then
                        setDebug("Sweeping card display walls...")
                        
                        -- Reset to Page 1
                        for i = 1, 8 do
                            if not Config.AutoCollect or not autoFishing then break end
                            CardRemote:FireServer("Page", "LeftArrow")
                            task.wait(0.05)
                        end
                        
                        -- Sweep Pages 1 to 8
                        for page = 1, 8 do
                            if not Config.AutoCollect or not autoFishing then break end
                            
                            local myPlot = findMyPlot()
                            if myPlot then
                                local map = myPlot:FindFirstChild("Map")
                                local display = map and map:FindFirstChild("Display")
                                if display then
                                    local left = display:FindFirstChild("Left")
                                    if left then
                                        for _, slot in ipairs(left:GetChildren()) do
                                            if slot:IsA("BasePart") and tonumber(slot.Name) then
                                                CardRemote:FireServer("Collect", slot)
                                            end
                                        end
                                    end
                                    local right = display:FindFirstChild("Right")
                                    if right then
                                        for _, slot in ipairs(right:GetChildren()) do
                                            if slot:IsA("BasePart") and tonumber(slot.Name) then
                                                CardRemote:FireServer("Collect", slot)
                                            end
                                        end
                                    end
                                end
                            end
                            
                            task.wait(0.1)
                            CardRemote:FireServer("Page", "RightArrow")
                            task.wait(0.1)
                        end
                        
                        -- Reset to Page 1
                        for i = 1, 8 do
                            if not Config.AutoCollect or not autoFishing then break end
                            CardRemote:FireServer("Page", "LeftArrow")
                            task.wait(0.05)
                        end
                        setDebug("Card display sweep complete")
                    end
                end)
            end
            task.wait(1.5) -- Loop throttle
        end
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

        local sellCount = fishData.amount - 1 -- Keep exactly 1
        setDebug("Auto-Selling " .. fishData.name .. " x" .. sellCount)

        for i = 1, sellCount do
            if not Config.AutoSellDupes or not autoFishing then break end
            pcall(Fish.FireServer, Fish, "Sell", fishData.name)
            totalSoldThisRound = totalSoldThisRound + 1
            task.wait(0.15) -- Safe cooldown delay between server fires
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
            task.wait(1.5) -- Wait briefly after catch cycle to let inventory render
            if not Config.AutoSellDupes or not autoFishing then break end
            
            local sold = sellDuplicates()
            if sold > 0 then
                fishSold = fishSold + sold
                updateStats()
            end
            
            task.wait(5.0) -- Repeat scan every 5 seconds
        end
    end)
end

-- =============================================
-- CLICK ENGINE (For Legit/Turbo/Hybrid)
-- =============================================
local function simulateClick()
    local VirtualInputManager = game:GetService("VirtualInputManager")
    VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 0)
    RunService.RenderStepped:Wait()
    VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0)
end

local function startClicking(delay)
    if clicking then return end
    clicking = true
    clickThread = task.spawn(function()
        while clicking and autoFishing do
            simulateClick()
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
    -- Guarantee mouse button release to prevent holding states
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
-- CASTING
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

-- =============================================
-- FIND FISH RES LOOP
-- =============================================
local function findFishHandlerLoop()
    local conns = getconnections(RunService.RenderStepped)
    for _, conn in pairs(conns) do
        local fn = conn.Function
        if fn then
            local info = getinfo(fn)
            if info and info.source and info.source:find("FishHandler") then
                return fn
            end
        end
    end
    return nil
end

-- =============================================
-- STRATEGIES
-- =============================================

local function startInstantLoop()
    cancelInstantThread()
    instantThread = task.spawn(function()
        while autoFishing do
            local fn = findFishHandlerLoop()
            if fn then
                local ok, ups = pcall(getupvalues, fn)
                if ok and ups then
                    local isMinigameActive = ups[1] -- v7
                    if isMinigameActive == true then
                        local goalScore = ups[8] -- v18
                        if goalScore then
                            setStatus("🚀 INSTANT: Struggle...", Color3.fromRGB(0, 220, 150))
                            setDebug("Freezing progress at " .. (Config.SlowReelThreshold * 100) .. "%...")
                            
                            -- Disable the minigame drain completely
                            pcall(debug.setupvalue, fn, 15, 0) -- v19 (drain rate) to 0
                            pcall(debug.setupvalue, fn, 14, 0) -- v26 (hold drain) to 0
                            
                            -- Instantly set the progress bar to struggle percentage
                            pcall(debug.setupvalue, fn, 6, goalScore * Config.SlowReelThreshold) -- v17 (current score)
                            
                            -- Wait the dynamic user-configured delay
                            task.wait(Config.InstantCatchDelay)
                            if not autoFishing then break end
                            
                            -- Complete the catch
                            setDebug("Completing catch...")
                            pcall(debug.setupvalue, fn, 6, goalScore) -- Set progress to 100%
                            
                            -- Wait until game ends to start checking again
                            repeat 
                                task.wait(0.1) 
                                local currentUps = getupvalues(fn)
                            until not autoFishing or not currentUps or currentUps[1] == false
                            
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

-- =============================================
-- MAIN LOGIC
-- =============================================
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
            -- Blatant: Direct network catch immediately when fish bites!
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

    -- Lock UI visibility in Blatant mode (fully suppresses minigame bars for instant/blatant strategy)
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

    -- Start background loop for the instant strategy
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

    -- Start auto sell loop if enabled
    if Config.AutoSellDupes then
        startAutoSellLoop()
    end

    -- Start auto collect loop if enabled
    if Config.AutoCollect then
        startAutoCollectLoop()
    end
end

local function stopAutoFish()
    autoFishing = false
    waitingForCatch = false
    stopClicking()
    cancelInstantThread()
    cancelAutoSellThread()
    cancelCollectThread()
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
-- ANTI-AFK
-- =============================================
player.Idled:Connect(function()
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new())
end)

-- =============================================
-- BUTTONS
-- =============================================
toggleBtn.MouseButton1Click:Connect(function()
    if autoFishing then stopAutoFish() else startAutoFish() end
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

gpuBtn.MouseButton1Click:Connect(function()
    Config.GPUSaver = not Config.GPUSaver
    updateModeUI()
    if Config.GPUSaver then
        enableGPU()
    else
        disableGPU()
    end
end)

collectBtn.MouseButton1Click:Connect(function()
    Config.AutoCollect = not Config.AutoCollect
    updateModeUI()
    if autoFishing then
        if Config.AutoCollect then
            startAutoCollectLoop()
        else
            cancelCollectThread()
        end
    end
end)

autoSellBtn.MouseButton1Click:Connect(function()
    Config.AutoSellDupes = not Config.AutoSellDupes
    updateModeUI()
    if autoFishing then
        if Config.AutoSellDupes then
            startAutoSellLoop()
        else
            cancelAutoSellThread()
        end
    end
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
-- INIT
-- =============================================
updateModeUI()
print("[Auto Fisher v12] Loaded!")
