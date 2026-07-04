-- =============================================
-- Auto Fisher v22 - Sequential Blatant Strategy
-- For: Anime Card Collection (Fish It!)
-- Author: LO + ENI
-- =============================================

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

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
    BlatantParallelCasts = true,
    
    -- Auto Sell Duplicate Fish
    AutoSellDupes = false,

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
local blatantThread = nil
local autoSellThread = nil
local uiConnection = nil
local fishCaught = 0
local fishSold = 0
local sessionStart = 0
local waitingForCatch = false
local UICollapsed = false
local originalHeight = 235

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
screenGui.Name = "AutoFishUI_v22"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = PlayerGui

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 210, 0, originalHeight)
frame.Position = UDim2.new(0, 20, 0.5, -117)
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

-- Toggles Row (Parallel Casts & Auto Sell duplicates)
local parallelBtn = Instance.new("TextButton")
parallelBtn.Size = UDim2.new(0.5, -15, 0, 20)
parallelBtn.Position = UDim2.new(0, 10, 0, 118)
parallelBtn.BorderSizePixel = 0
parallelBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
parallelBtn.TextScaled = true
parallelBtn.Font = Enum.Font.Gotham
parallelBtn.Parent = frame
Instance.new("UICorner", parallelBtn).CornerRadius = UDim.new(0, 6)

local autoSellBtn = Instance.new("TextButton")
autoSellBtn.Size = UDim2.new(0.5, -15, 0, 20)
autoSellBtn.Position = UDim2.new(0.5, 5, 0, 118)
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
inputContainer.Position = UDim2.new(0, 10, 0, 143)
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
thresholdContainer.Position = UDim2.new(0, 10, 0, 173)
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
debugLabel.Position = UDim2.new(0, 5, 0, 210)
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
    modeBtn, stratBtn, toggleBtn, parallelBtn, autoSellBtn,
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
    parallelBtn.Visible = isBlatant
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

    parallelBtn.Text = Config.BlatantParallelCasts and "⚡ Parallel: ON" or "⚡ Parallel: OFF"
    parallelBtn.BackgroundColor3 = Config.BlatantParallelCasts and Color3.fromRGB(180, 100, 0) or Color3.fromRGB(50, 50, 55)

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

-- =============================================
-- DYNAMIC DELAY CALCULATOR FOR RARE FISH (NEW)
-- =============================================
local function getCatchDelayForFish(fishName)
    local baseDelay = Config.InstantCatchDelay
    if not fishName then return baseDelay end
    
    local nameLower = fishName:lower()
    -- Keywords for rare/high-tier fish that require a longer struggle window
    if nameLower:find("legendary") or nameLower:find("mythical") or nameLower:find("giant") or nameLower:find("gold") or nameLower:find("diamond") or nameLower:find("ancient") or nameLower:find("kraken") or nameLower:find("whale") then
        return baseDelay + 0.8 -- Add a 0.8s buffer to prevent server-side escapes
    end
    return baseDelay
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

    if Config.Mode == "Blatant" and Config.BlatantParallelCasts then
        task.spawn(function()
            pcall(Fish.FireServer, Fish, "CastRod", castVal)
        end)
        task.wait(0.02) -- 20ms split for near-simultaneous parallel casts
        task.spawn(function()
            pcall(Fish.FireServer, Fish, "CastRod", castVal)
        end)
    else
        pcall(Fish.FireServer, Fish, "CastRod", castVal)
    end

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
-- PURE SEQUENTIAL BLATANT CAST/CATCH LOOP (REVERTED FOR ACC SERVER COMPATIBILITY)
-- =============================================
local function startBlatantLoop()
    cancelInstantThread()
    blatantThread = task.spawn(function()
        while autoFishing and Config.BlatantStrategy == "blatant" do
            setStatus("🔥 BLT: Casting...", Color3.fromRGB(255, 100, 0))
            setDebug("Casting rod...")
            
            -- Fire the cast remote
            local castVal = Config.BlatantCastValue
            pcall(Fish.FireServer, Fish, "CastRod", castVal)
            
            -- Wait the Catch Delay (struggle delay) sequentially BEFORE catching
            task.wait(Config.InstantCatchDelay)
            if not autoFishing or Config.BlatantStrategy ~= "blatant" then break end
            
            setStatus("🔥 BLT: Catching...", Color3.fromRGB(0, 180, 255))
            setDebug("Firing FishCaught...")
            pcall(Fish.FireServer, Fish, "FishCaught")
            
            fishCaught = fishCaught + 1
            updateStats()
            
            -- Wait recast delay before casting again
            task.wait(Config.BlatantRecastDelay)
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
    fishCaught = fishCaught + 1
    updateStats()

    local label = eventType == "FishCaught" and "Caught! " .. tostring(fishName or "") or "Claimed!"
    setStatus(label, Color3.fromRGB(100, 220, 255))
    setDebug("Catch #" .. fishCaught .. " confirmed")

    recast()
end

local function handleEscape()
    stopClicking()
    if Config.BlatantStrategy ~= "instant" then
        cancelInstantThread()
    end
    waitingForCatch = false
    setStatus("Escaped! Recasting...", Color3.fromRGB(255, 100, 0))
    setDebug("Fish escaped")
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

    if Config.BlatantStrategy == "blatant" then
        startBlatantLoop()
    else
        connection = Fish.OnClientEvent:Connect(function(eventType, fishName, amount)
            if not autoFishing then return end

            if eventType == "StartFishing" then
                handleStartFishing(fishName)
            elseif eventType == "FishCaught" or eventType == "FishClaimed" then
                handleCatch(eventType, fishName)
            elseif eventType == "FishEscaped" then
                handleEscape()
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
    end

    -- Start auto sell loop if enabled
    if Config.AutoSellDupes then
        startAutoSellLoop()
    end
end

local function stopAutoFish()
    autoFishing = false
    waitingForCatch = false
    stopClicking()
    cancelInstantThread()
    cancelAutoSellThread()
    lockUIHidden(false)

    if blatantThread then
        pcall(task.cancel, blatantThread)
        blatantThread = nil
    end

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

    for i, s in strategies do
        if s == Config.BlatantStrategy then
            Config.BlatantStrategy = strategies[(i % #strategies) + 1]
            break
        end
    end
    updateModeUI()
    if wasRunning then task.wait(0.2); startAutoFish() end
end)

parallelBtn.MouseButton1Click:Connect(function()
    Config.BlatantParallelCasts = not Config.BlatantParallelCasts
    updateModeUI()
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
