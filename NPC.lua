-- NPC Controller (Delta Executor Optimized & Server-Sided Replication)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")
local StarterGui = game:GetService("StarterGui")
local LocalPlayer = Players.LocalPlayer

-- Maximum Client-Side Network Ownership Power for Delta
local function setupNetworkOwnership()
    -- Delta compatibility for UNC hidden properties
    local sethidden = sethiddenproperty or set_hidden_property or set_hidden_prop or function() end
    local setsim = setsimulationradius or set_simulation_radius or function(rad) pcall(function() sethidden(LocalPlayer, "SimulationRadius", rad) end) end

    pcall(function()
        settings().Physics.AllowSleep = false
        settings().Physics.PhysicsEnvironmentalThrottle = Enum.EnviromentalPhysicsThrottle.Disabled
    end)

    -- Delta-specific maximums (forces replication to server for all players to see)
    local maxRadius = 9e9
    pcall(function() setsim(maxRadius, maxRadius) end)
    pcall(function() sethidden(LocalPlayer, "SimulationRadius", maxRadius) end)
    pcall(function() sethidden(LocalPlayer, "MaxSimulationRadius", maxRadius) end)
    pcall(function() LocalPlayer.MaximumSimulationRadius = maxRadius end)
    pcall(function() LocalPlayer.SimulationRadius = maxRadius end)
end

RunService.RenderStepped:Connect(setupNetworkOwnership)
RunService.Stepped:Connect(setupNetworkOwnership)
RunService.Heartbeat:Connect(setupNetworkOwnership)

local function isConnected(npc)
    local hrp = npc:FindFirstChild("HumanoidRootPart")
    local hum = npc:FindFirstChild("Humanoid")
    if not hrp or not hum or hum.Health <= 0 then return false end

    -- 1. Delta / UNC isnetworkowner check (Most Accurate & Smooth)
    if type(isnetworkowner) == "function" then
        local success, res = pcall(isnetworkowner, hrp)
        if success then return res == true or res == LocalPlayer end
    end

    -- 2. ReceiveAge Fallback
    local success, age = pcall(function() return hrp.ReceiveAge end)
    if success and age == 0 and not hrp.Anchored then
        return true
    end

    return false
end

local function forceConnect(npc)
    setupNetworkOwnership()
    local hrp = npc:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local hum = npc:FindFirstChild("Humanoid")
    if not hum or hum.Health <= 0 then return end

    -- Direct Executor Ownership Assignment
    pcall(function()
        if type(setnetworkowner) == "function" then
            setnetworkowner(hrp, LocalPlayer)
        elseif type(setnetworkownership) == "function" then
            setnetworkownership(hrp, LocalPlayer)
        end
    end)

    pcall(function()
        hum:ChangeState(Enum.HumanoidStateType.Running)
        hum.PlatformStand = false
        hum.Sit = false
    end)
    hrp.Anchored = false
    
    -- Micro-movement to keep physics awake, NO CAMERA TELEPORTING
    pcall(function()
        hrp.AssemblyLinearVelocity = hrp.AssemblyLinearVelocity + Vector3.new(0, 0.05, 0)
    end)
end

-- ==========================================
-- ADVANCED CLONE RECOVERY SYSTEM (SMOOTH/ANTI-LAG)
-- ==========================================
local CloneRecovery = {}

function CloneRecovery.IsCloneConnected(npc)
    return isConnected(npc)
end

function CloneRecovery.RecoverClone(npc)
    if CloneRecovery.IsCloneConnected(npc) then return true end
    
    -- Phase 1: Silent Executor Override (No Lag, best for Delta)
    forceConnect(npc)
    if CloneRecovery.IsCloneConnected(npc) then return true end
    
    -- Phase 2: Proximity Override (With Camera Lock to prevent mobile screen glitching)
    local myChar = LocalPlayer.Character
    local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
    local hrp = npc:FindFirstChild("HumanoidRootPart")
    
    if myRoot and hrp then
        local cam = workspace.CurrentCamera
        local oldCamType = cam.CameraType
        local oldCamCF = cam.CFrame
        local oldPos = myRoot.CFrame
        
        -- Freeze camera for smoothness (prevents the screen glitch)
        cam.CameraType = Enum.CameraType.Scriptable
        cam.CFrame = oldCamCF
        
        -- Swiftly move to clone, claim, and return
        myRoot.CFrame = hrp.CFrame
        task.wait(0.05)
        forceConnect(npc)
        
        myRoot.CFrame = oldPos
        cam.CameraType = oldCamType
    end
    
    return CloneRecovery.IsCloneConnected(npc)
end

function CloneRecovery.VerifyCloneControl(npc)
    return CloneRecovery.IsCloneConnected(npc) or CloneRecovery.RecoverClone(npc)
end

local function teleportClone(npc, targetCFrame)
    local hrp = npc:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    
    if not CloneRecovery.VerifyCloneControl(npc) then
        return false
    end
    
    hrp.CFrame = targetCFrame
    hrp.AssemblyLinearVelocity = Vector3.zero
    hrp.AssemblyAngularVelocity = Vector3.zero
    return true
end

local npcCache = {}
local cachedNpcsList = {}
local nextNpcId = 1
local npcOwnershipState = {}
local lastNpcRefresh = 0

local function refreshNPCs()
    local currentNPCs = {}
    for _, obj in ipairs(workspace:GetDescendants()) do
        local hum = obj:FindFirstChild("Humanoid")
        if obj:IsA("Model") and hum and hum.Health > 0 and obj:FindFirstChild("HumanoidRootPart") then
            local isPlayer = false
            for _, p in ipairs(Players:GetPlayers()) do
                if p.Character == obj then
                    isPlayer = true
                    break
                end
            end
            if not isPlayer then
                table.insert(currentNPCs, obj)
                if not npcCache[obj] then
                    npcCache[obj] = {
                        id = nextNpcId,
                        type = obj.Name,
                        path = nil
                    }
                    nextNpcId = nextNpcId + 1
                end
            end
        end
    end
    cachedNpcsList = currentNPCs
end

local function getNPCs()
    if tick() - lastNpcRefresh > 2 then
        lastNpcRefresh = tick()
        task.spawn(refreshNPCs)
    end

    for i = #cachedNpcsList, 1, -1 do
        local obj = cachedNpcsList[i]
        local hum = obj and obj:FindFirstChild("Humanoid")
        if not obj or not obj.Parent or not obj:FindFirstChild("HumanoidRootPart") or not hum or hum.Health <= 0 then
            table.remove(cachedNpcsList, i)
        end
    end

    for obj, _ in pairs(npcCache) do
        if not obj or not obj.Parent then
            npcCache[obj] = nil
            npcOwnershipState[obj] = nil
        end
    end

    return cachedNpcsList
end

local function getNPCById(id)
    for obj, data in pairs(npcCache) do
        if data.id == id and obj and obj.Parent then
            return obj
        end
    end
    return nil
end

local function getPlayer(nameStr)
    if type(nameStr) ~= "string" then return nil end
    local nameStrLower = string.lower(nameStr)
    if nameStrLower == "" then return nil end
    for _, p in ipairs(Players:GetPlayers()) do
        local pName = p.Name and string.lower(p.Name) or ""
        local pDisp = p.DisplayName and string.lower(p.DisplayName) or ""
        if (pName ~= "" and string.sub(pName, 1, #nameStrLower) == nameStrLower) or
           (pDisp ~= "" and string.sub(pDisp, 1, #nameStrLower) == nameStrLower) then
            return p
        end
    end
    return nil
end

local function getPlayersByName(nameStr)
    if type(nameStr) ~= "string" then return {} end
    local matches = {}
    local nameStrLower = string.lower(nameStr)
    if nameStrLower == "" then return matches end
    for _, p in ipairs(Players:GetPlayers()) do
        local pName = p.Name and string.lower(p.Name) or ""
        local pDisp = p.DisplayName and string.lower(p.DisplayName) or ""
        if (pName ~= "" and string.sub(pName, 1, #nameStrLower) == nameStrLower) or
           (pDisp ~= "" and string.sub(pDisp, 1, #nameStrLower) == nameStrLower) then
            table.insert(matches, p)
        end
    end
    return matches
end

local function notify(title, text)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title;
            Text = text;
            Duration = 5;
        })
    end)
end

-- GUI Setup & Fallback for Mobile Executors (Delta)
local CoreGui = game:GetService("CoreGui")
local PlayerGui = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
local targetParent = PlayerGui

local successHui, hui = pcall(function() return gethui() end)
if successHui and hui then
    targetParent = hui
elseif pcall(function() local _ = CoreGui.Name end) then
    targetParent = CoreGui
end

pcall(function()
    for _, gui in ipairs(targetParent:GetChildren()) do
        if gui.Name == "NPCControllerGUI" then gui:Destroy() end
    end
end)

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "NPCControllerGUI"
ScreenGui.Parent = targetParent
ScreenGui.ResetOnSpawn = false
ScreenGui.DisplayOrder = 9999
ScreenGui.IgnoreGuiInset = true -- Crucial for mobile devices
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local BubbleFrame = Instance.new("ImageButton")
BubbleFrame.Size = UDim2.new(0, 50, 0, 50)
BubbleFrame.AnchorPoint = Vector2.new(0.5, 0)
BubbleFrame.Position = UDim2.new(0.5, 0, 0.1, 0)
BubbleFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
BubbleFrame.Visible = false
BubbleFrame.Parent = ScreenGui
BubbleFrame.AutoButtonColor = false
local UICorner = Instance.new("UICorner")
UICorner.CornerRadius = UDim.new(1, 0)
UICorner.Parent = BubbleFrame
local BubbleText = Instance.new("TextLabel")
BubbleText.Size = UDim2.new(1, 0, 1, 0)
BubbleText.BackgroundTransparency = 1
BubbleText.Text = "NPC"
BubbleText.TextColor3 = Color3.fromRGB(255, 255, 255)
BubbleText.Font = Enum.Font.SourceSansBold
BubbleText.TextSize = 14
BubbleText.Parent = BubbleFrame

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 200, 0, 370)
MainFrame.AnchorPoint = Vector2.new(0.5, 0.5) -- Perfect center anchor
MainFrame.Position = UDim2.new(0.5, 0, 0.5, 0) -- Perfect center position
MainFrame.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
MainFrame.Active = true
MainFrame.Parent = ScreenGui

local CloseMainBtn = Instance.new("TextButton")
CloseMainBtn.Size = UDim2.new(0, 30, 0, 30)
CloseMainBtn.Position = UDim2.new(1, -30, 0, 0)
CloseMainBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
CloseMainBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CloseMainBtn.Text = "X"
CloseMainBtn.Font = Enum.Font.SourceSansBold
CloseMainBtn.TextSize = 16
CloseMainBtn.Parent = MainFrame

CloseMainBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = false
    BubbleFrame.Visible = true
end)
BubbleFrame.MouseButton1Click:Connect(function()
    BubbleFrame.Visible = false
    MainFrame.Visible = true
end)

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -30, 0, 30)
Title.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
Title.TextColor3 = Color3.fromRGB(255, 255, 255)
Title.Text = "NPC Controller"
Title.Font = Enum.Font.SourceSansBold
Title.TextSize = 16
Title.Parent = MainFrame

local function createToggle(name, yPos)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, -20, 0, 30)
    btn.Position = UDim2.new(0, 10, 0, yPos)
    btn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.Text = name .. ": OFF"
    btn.Font = Enum.Font.SourceSans
    btn.TextSize = 14
    btn.Parent = MainFrame
    return btn
end

local function createButton(name, yPos)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, -20, 0, 30)
    btn.Position = UDim2.new(0, 10, 0, yPos)
    btn.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.Text = name
    btn.Font = Enum.Font.SourceSans
    btn.TextSize = 14
    btn.Parent = MainFrame
    return btn
end

local btnFollow = createToggle("Follow Me", 40)
local btnSpin = createToggle("Spin NPCs", 80)
local btnChat = createToggle("Chat Commands", 120)
local btnESP = createToggle("NPC ESP", 160)
local btnAutoConnect = createToggle("Auto Connect", 200)
local btnGossip = createToggle("Gossip Mode", 240)
local btnAntiLag = createToggle("Anti-Lag", 280)
local btnCmdsList = createButton("Show Commands", 320)
local btnToggleList = createButton("NPC Lists", 360)

local state = {
    Follow = false,
    Spin = false,
    Chat = false,
    ESP = false,
    AutoConnect = false,
    Gossip = false,
    AntiLag = false,
    CurrentTarget = nil,
    CurrentTargetName = nil,
    Mode = nil,
    CommandIssuer = LocalPlayer,
    YesOrNoPick = 1,
    YesOrNoTick = 0,
    StayingNPCs = {},
    StackUpPos = nil
}

local permissions = {}

local NPCListFrame = Instance.new("Frame")
NPCListFrame.Size = UDim2.new(0, 250, 1, 0)
NPCListFrame.Position = UDim2.new(1, 10, 0, 0)
NPCListFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
NPCListFrame.Visible = false
NPCListFrame.Parent = MainFrame

local NPCListTitle = Instance.new("TextLabel")
NPCListTitle.Size = UDim2.new(1, 0, 0, 30)
NPCListTitle.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
NPCListTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
NPCListTitle.Text = "NPC Connections List"
NPCListTitle.Font = Enum.Font.SourceSansBold
NPCListTitle.TextSize = 14
NPCListTitle.Parent = NPCListFrame

local NPCScroll = Instance.new("ScrollingFrame")
NPCScroll.Size = UDim2.new(1, 0, 1, -30)
NPCScroll.Position = UDim2.new(0, 0, 0, 30)
NPCScroll.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
NPCScroll.ScrollBarThickness = 5
NPCScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
NPCScroll.Parent = NPCListFrame

local UIListLayout = Instance.new("UIListLayout")
UIListLayout.Padding = UDim.new(0, 2)
UIListLayout.Parent = NPCScroll
UIListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    NPCScroll.CanvasSize = UDim2.new(0, 0, 0, UIListLayout.AbsoluteContentSize.Y)
end)

btnToggleList.MouseButton1Click:Connect(function()
    NPCListFrame.Visible = not NPCListFrame.Visible
end)

local CmdsFrame = Instance.new("Frame")
CmdsFrame.Size = UDim2.new(0, 250, 0, 330)
CmdsFrame.Position = UDim2.new(0, -260, 0, 0)
CmdsFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
CmdsFrame.Visible = false
CmdsFrame.Parent = MainFrame

local CmdsTitle = Instance.new("TextLabel")
CmdsTitle.Size = UDim2.new(1, 0, 0, 30)
CmdsTitle.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
CmdsTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
CmdsTitle.Text = "Command List"
CmdsTitle.Font = Enum.Font.SourceSansBold
CmdsTitle.TextSize = 14
CmdsTitle.Parent = CmdsFrame

local CmdsScroll = Instance.new("ScrollingFrame")
CmdsScroll.Size = UDim2.new(1, 0, 1, -30)
CmdsScroll.Position = UDim2.new(0, 0, 0, 30)
CmdsScroll.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
CmdsScroll.ScrollBarThickness = 5
CmdsScroll.Parent = CmdsFrame
CmdsScroll.CanvasSize = UDim2.new(0, 0, 0, 600)

local CmdsLayout = Instance.new("UIListLayout")
CmdsLayout.Padding = UDim.new(0, 2)
CmdsLayout.Parent = CmdsScroll
CmdsLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    CmdsScroll.CanvasSize = UDim2.new(0, 0, 0, CmdsLayout.AbsoluteContentSize.Y)
end)

local cmdListText = {
    "attack [player] - Attack target",
    "makeway - Move away from you",
    "arise - Walk randomly",
    "train - Follow each other",
    ".bring - Teleport to your location",
    ".givecommand [player] [cmd] - Grant access",
    ".stripcommand [player] [cmd] - Revoke access",
    ".drag - Drag NPCs like a ladder",
    "stack up - Jumps and stacks in front of you",
    "sit - Sit down",
    "look at [player] - Look at target",
    ".disarm [id] or all - Drop tools from NPC",
    "yes or no - Random nod or shake head",
    "stay [id] or all - NPCs stay at their spot",
    "follow [id] or all - NPCs stop staying",
    ".summon - Teleport all alive NPCs to you",
    "mecha - Form a mecha with up to 5 NPCs",
    "sts - Shoulder to shoulder formation",
    "dance - Make NPCs dance",
    "orbit - Circle around you",
    "make a wall - 5-wide wall formation",
    "do a backflip - NPCs backflip",
    "who did it - Point at random player",
    "kill [id/name] - Chase and kill target",
    "stairs - Make NPCs form stairs in front of you",
    "assemble - Assemble behind you",
    "find [player] - Push you to the target player"
}

for _, msg in ipairs(cmdListText) do
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -10, 0, 25)
    lbl.BackgroundTransparency = 1
    lbl.TextColor3 = Color3.fromRGB(220, 220, 220)
    lbl.Text = " " .. msg
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Font = Enum.Font.SourceSans
    lbl.TextSize = 13
    lbl.Parent = CmdsScroll
end

btnCmdsList.MouseButton1Click:Connect(function()
    CmdsFrame.Visible = not CmdsFrame.Visible
end)

btnFollow.MouseButton1Click:Connect(function()
    state.Follow = not state.Follow
    btnFollow.Text = "Follow Me: " .. (state.Follow and "ON" or "OFF")
    if state.Follow then
        state.Mode = nil
        state.CommandIssuer = LocalPlayer
    end
end)

btnSpin.MouseButton1Click:Connect(function()
    state.Spin = not state.Spin
    btnSpin.Text = "Spin NPCs: " .. (state.Spin and "ON" or "OFF")

    local npcs = getNPCs()
    for _, npc in ipairs(npcs) do
        local hrp = npc:FindFirstChild("HumanoidRootPart")
        if hrp then
            if state.Spin then
                local av = Instance.new("AngularVelocity")
                av.Name = "NPCSpin"
                av.MaxTorque = math.huge
                av.AngularVelocity = Vector3.new(0, 50, 0)
                local att = Instance.new("Attachment")
                att.Name = "SpinAtt"
                att.Parent = hrp
                av.Attachment0 = att
                av.Parent = hrp
            else
                local av = hrp:FindFirstChild("NPCSpin")
                if av then av:Destroy() end
                local att = hrp:FindFirstChild("SpinAtt")
                if att then att:Destroy() end
                hrp.RotVelocity = Vector3.new(0,0,0)
            end
        end
    end
end)

btnChat.MouseButton1Click:Connect(function()
    state.Chat = not state.Chat
    btnChat.Text = "Chat Commands: " .. (state.Chat and "ON" or "OFF")
end)

btnESP.MouseButton1Click:Connect(function()
    state.ESP = not state.ESP
    btnESP.Text = "NPC ESP: " .. (state.ESP and "ON" or "OFF")

    if not state.ESP then
        local npcs = getNPCs()
        for _, npc in ipairs(npcs) do
            local hl = npc:FindFirstChild("NPC_ESP_HL")
            if hl then hl:Destroy() end
            local bb = npc:FindFirstChild("NPC_ESP_BB")
            if bb then bb:Destroy() end
        end
    end
end)

btnGossip.MouseButton1Click:Connect(function()
    state.Gossip = not state.Gossip
    btnGossip.Text = "Gossip Mode: " .. (state.Gossip and "ON" or "OFF")
end)
btnAutoConnect.MouseButton1Click:Connect(function()
    state.AutoConnect = not state.AutoConnect
    btnAutoConnect.Text = "Auto Connect: " .. (state.AutoConnect and "ON" or "OFF")
end)

btnAntiLag.MouseButton1Click:Connect(function()
    state.AntiLag = not state.AntiLag
    btnAntiLag.Text = "Anti-Lag: " .. (state.AntiLag and "ON" or "OFF")
    for _, npc in ipairs(getNPCs()) do
        for _, v in ipairs(npc:GetDescendants()) do
            if v:IsA("BasePart") then
                v.Material = state.AntiLag and Enum.Material.SmoothPlastic or Enum.Material.Plastic
                v.CastShadow = not state.AntiLag
            end
        end
    end
end)

local function handleCommand(player, msg)
    if type(msg) ~= "string" then return end
    if not state.Chat then return end

    local msgLower = string.lower(msg)

    if player ~= LocalPlayer then
        local pPerms = permissions[player.UserId]
        if not pPerms then return end

        local hasPerm = false
        for permCmd, _ in pairs(pPerms) do
            if string.find(msgLower, permCmd) or permCmd == "all" then
                hasPerm = true
                break
            end
        end
        if not hasPerm then return end
    end

    local args = string.split(msgLower, " ")
    local cmd = args[1]

    if cmd == ".givecommand" and player == LocalPlayer then
        local target = getPlayer(args[2])
        local permCmd = args[3]
        if target and permCmd then
            if not permissions[target.UserId] then
                permissions[target.UserId] = {}
            end
            permissions[target.UserId][permCmd] = true
            notify("Permission", "Gave " .. target.Name .. " access to: " .. permCmd)
        end
    elseif cmd == ".stripcommand" and player == LocalPlayer then
        local target = getPlayer(args[2])
        local permCmd = args[3]
        if target and permCmd and permissions[target.UserId] then
            permissions[target.UserId][permCmd] = nil
            notify("Permission", "Removed " .. target.Name .. "'s access to: " .. permCmd)
        end
    elseif cmd == "attack" and args[2] then
        local target = getPlayer(args[2])
        if target and target.Character then
            state.CurrentTarget = target
            state.Mode = "Attack"
            state.Follow = false
            state.CommandIssuer = player
            if player == LocalPlayer then btnFollow.Text = "Follow Me: OFF" end
        end
    elseif cmd == "look" and args[2] == "at" and args[3] then
        local target = getPlayer(args[3])
        if target then
            state.CurrentTargetName = args[3]
            state.Mode = "LookAt"
            state.Follow = false
            state.CommandIssuer = player
            if player == LocalPlayer then btnFollow.Text = "Follow Me: OFF" end
        end
    elseif cmd == "makeway" then
        state.Mode = "Makeway"
        state.Follow = false
        state.CommandIssuer = player
        if player == LocalPlayer then btnFollow.Text = "Follow Me: OFF" end
    elseif cmd == "arise" then
        state.Mode = "Arise"
        state.Follow = false
        state.CommandIssuer = player
        if player == LocalPlayer then btnFollow.Text = "Follow Me: OFF" end
    elseif cmd == "train" then
        state.Mode = "Train"
        state.Follow = false
        state.CommandIssuer = player
        if player == LocalPlayer then btnFollow.Text = "Follow Me: OFF" end
    elseif cmd == ".drag" then
        state.Mode = "Drag"
        state.Follow = false
        state.CommandIssuer = player
        if player == LocalPlayer then btnFollow.Text = "Follow Me: OFF" end
    elseif cmd == "stack" and args[2] == "up" then
        state.Mode = "StackUp"
        state.Follow = false
        state.CommandIssuer = player
        local issuerChar = player.Character
        local issuerRoot = issuerChar and issuerChar:FindFirstChild("HumanoidRootPart")
        if issuerRoot then
            state.StackUpPos = issuerRoot.Position + issuerRoot.CFrame.LookVector * 5
        end
        if player == LocalPlayer then btnFollow.Text = "Follow Me: OFF" end
    elseif cmd == "stay" and args[2] then
        if args[2] == "all" then
            for _, npc in ipairs(getNPCs()) do
                state.StayingNPCs[npc] = true
            end
        else
            local targetId = tonumber(args[2])
            if targetId then
                local npc = getNPCById(targetId)
                if npc then state.StayingNPCs[npc] = true end
            end
        end
    elseif cmd == "follow" and args[2] then
        if args[2] == "all" then
            for _, npc in ipairs(getNPCs()) do
                state.StayingNPCs[npc] = nil
            end
        else
            local targetId = tonumber(args[2])
            if targetId then
                local npc = getNPCById(targetId)
                if npc then state.StayingNPCs[npc] = nil end
            end
        end
    elseif cmd == "sit" then
        state.Mode = "Sit"
        state.Follow = false
        state.CommandIssuer = player
        if player == LocalPlayer then btnFollow.Text = "Follow Me: OFF" end
    elseif cmd == "yes" and args[2] == "or" and args[3] == "no" then
        state.Mode = "YesOrNo"
        state.YesOrNoPick = Random.new():NextInteger(1, 2)
        state.YesOrNoTick = tick()
        state.Follow = false
        state.CommandIssuer = player
        if player == LocalPlayer then btnFollow.Text = "Follow Me: OFF" end
    elseif cmd == "orbit" then
        state.Mode = "Orbit"
        state.Follow = false
        state.CommandIssuer = player
    elseif cmd == "make" and args[2] == "a" and args[3] == "wall" then
        state.Mode = "Wall"
        state.Follow = false
        state.CommandIssuer = player
        local issuerChar = player.Character
        local issuerRoot = issuerChar and issuerChar:FindFirstChild("HumanoidRootPart")
        if issuerRoot then
            state.WallPos = issuerRoot.Position + issuerRoot.CFrame.LookVector * 10
            state.WallDir = issuerRoot.CFrame.RightVector
        end
    elseif cmd == "do" and args[2] == "a" and args[3] == "backflip" then
        state.Mode = "Backflip"
        state.Follow = false
        state.CommandIssuer = player
    elseif cmd == "who" and args[2] == "did" and args[3] == "it" then
        state.Mode = "WhoDidIt"
        state.Follow = false
        state.CommandIssuer = player
        local players = Players:GetPlayers()
        if #players > 0 then
            state.WhoDidItTarget = players[math.random(1, #players)]
        end
    elseif cmd == "kill" and args[2] then
        local targetNpc = nil
        local targetId = tonumber(args[2])
        if targetId then
            targetNpc = getNPCById(targetId)
        end
        if not targetNpc then
            for _, n in ipairs(getNPCs()) do
                if string.lower(n.Name) == args[2] then
                    targetNpc = n
                    break
                end
            end
        end
        if targetNpc then
            state.Mode = "KillNPC"
            state.KillTargetNPC = targetNpc
            state.Follow = false
        end
    elseif cmd == ".bring" then
        -- Removed teleport-heavy logic here for clean executor usage
    elseif cmd == ".summon" then
        local npcs = getNPCs()
        local pChar = player.Character
        local pRoot = pChar and pChar:FindFirstChild("HumanoidRootPart")
        if pRoot then
            task.spawn(function()
                for i, npc in ipairs(npcs) do
                    local offset = Vector3.new(math.cos(i) * 5, 0, math.sin(i) * 5)
                    local targetCFrame = pRoot.CFrame + offset
                    teleportClone(npc, targetCFrame)
                end
            end)
        end
    elseif cmd == "mecha" then
        state.Mode = "Mecha"
        state.Follow = false
        state.CommandIssuer = player
        if player == LocalPlayer then btnFollow.Text = "Follow Me: OFF" end
    elseif cmd == "sts" then
        state.Mode = "STS"
        state.Follow = false
        state.CommandIssuer = player
        if player == LocalPlayer then btnFollow.Text = "Follow Me: OFF" end
    elseif cmd == "dance" then
        state.Mode = "Dance"
        state.Follow = false
        state.CommandIssuer = player
        if player == LocalPlayer then btnFollow.Text = "Follow Me: OFF" end
    elseif cmd == "stairs" then
        state.Mode = "Stairs"
        state.Follow = false
        state.CommandIssuer = player
        if player == LocalPlayer then btnFollow.Text = "Follow Me: OFF" end
    elseif cmd == "assemble" then
        state.Mode = "Assemble"
        state.Follow = false
        state.CommandIssuer = player
        if player == LocalPlayer then btnFollow.Text = "Follow Me: OFF" end
    elseif cmd == "find" and args[2] then
        state.Mode = "Find"
        state.CurrentTargetName = args[2]
        state.Follow = false
        state.CommandIssuer = player
        if player == LocalPlayer then btnFollow.Text = "Follow Me: OFF" end
        local npcs = getNPCs()
        local pChar = player.Character
        local pRoot = pChar and pChar:FindFirstChild("HumanoidRootPart")
        if pRoot then
            for i, npc in ipairs(npcs) do
                local hrp = npc:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local offset = Vector3.new(math.cos(i) * 5, 0, math.sin(i) * 5)
                    hrp.CFrame = pRoot.CFrame + offset
                    hrp.Velocity = Vector3.new(0,0,0)
                    hrp.RotVelocity = Vector3.new(0,0,0)
                end
            end
        end
    elseif cmd == ".disarm" and args[2] then
        local list = {}
        if args[2] == "all" then
            list = getNPCs()
        else
            local targetId = tonumber(args[2])
            if targetId then
                local npc = getNPCById(targetId)
                if npc then table.insert(list, npc) end
            end
        end
        for _, targetNpc in ipairs(list) do
            local hum = targetNpc:FindFirstChild("Humanoid")
            if hum then hum:UnequipTools() end
            for _, v in ipairs(targetNpc:GetDescendants()) do
                if v:IsA("Tool") then
                    v.Parent = workspace
                elseif v:IsA("Weld") and (v.Name == "RightGrip" or v.Name == "AccessoryWeld") then
                    v:Destroy()
                end
            end
        end
    end
end

for _, p in ipairs(Players:GetPlayers()) do
    p.Chatted:Connect(function(msg) handleCommand(p, msg) end)
end
Players.PlayerAdded:Connect(function(p)
    p.Chatted:Connect(function(msg) handleCommand(p, msg) end)
end)

local nextRandomMove = tick()
local lastUIRefresh = tick()
local lastAutoConnectTick = tick()

RunService.Heartbeat:Connect(function()
    local npcs = getNPCs()
    local ownedNpcs = {}

    for _, npc in ipairs(npcs) do
        local hrp = npc:FindFirstChild("HumanoidRootPart")
        local hum = npc:FindFirstChild("Humanoid")

        if hrp then
            local isOwned = isConnected(npc)

            if isOwned or state.AutoConnect then
                hrp.Anchored = false

                -- Anti-sleep mechanism
                pcall(function()
                    local vel = hrp.AssemblyLinearVelocity
                    if vel.Magnitude < 0.1 then
                        hrp.AssemblyLinearVelocity = vel + Vector3.new(0, 0.001, 0)
                    end
                end)

                if isOwned then
                    table.insert(ownedNpcs, npc)
                    pcall(function()
                        for _, part in ipairs(npc:GetDescendants()) do
                            if part:IsA("BasePart") and not part.Anchored then
                                part.CustomPhysicalProperties = PhysicalProperties.new(100, 0, 0, 100, 100)
                            end
                        end
                    end)

                    if npcOwnershipState[npc] ~= true then
                        if hum then
                            hum:ChangeState(Enum.HumanoidStateType.Running)
                            hum.PlatformStand = false
                            hum.Sit = false
                        end
                        npcOwnershipState[npc] = true
                    end
                else
                    npcOwnershipState[npc] = false
                end
            else
                npcOwnershipState[npc] = false
            end
        end
        if hum and state.Mode ~= "Sit" then
            hum.Sit = false
            hum.PlatformStand = false
        end
    end

    if state.Gossip then
        local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if myRoot then
            if not state.nextGossipTick then state.nextGossipTick = tick() end
            if tick() > state.nextGossipTick then
                state.nextGossipTick = tick() + math.random(3, 6)
                for _, npc in ipairs(ownedNpcs) do
                    if not state.StayingNPCs[npc] then
                        local hrp = npc:FindFirstChild("HumanoidRootPart")
                        local hum = npc:FindFirstChild("Humanoid")
                        if hrp and hum then
                            if math.random() > 0.5 then
                                local randomOffset = Vector3.new(math.random(-20, 20), 0, math.random(-20, 20))
                                hum:MoveTo(myRoot.Position + randomOffset)
                            else
                                local animType = math.random(1, 7)
                                if animType == 1 then
                                    hrp.CFrame = hrp.CFrame * CFrame.Angles(0, math.pi/4, 0)
                                elseif animType == 2 then
                                    hrp.CFrame = hrp.CFrame * CFrame.Angles(math.pi/8, 0, 0)
                                elseif animType == 3 then
                                    hum.Jump = true
                                elseif animType == 4 then
                                    hrp.RotVelocity = Vector3.new(0, 10, 0)
                                elseif animType == 5 then
                                    hrp.Velocity = Vector3.new(math.random(-5,5), 0, math.random(-5,5))
                                elseif animType == 7 then
                                    hrp.RotVelocity = Vector3.new(0, 50, 0)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    if state.AutoConnect and tick() - lastAutoConnectTick > 0.5 then
        lastAutoConnectTick = tick()
        for _, npc in ipairs(npcs) do
            if not isConnected(npc) then
                local lastTry = npcCache[npc] and npcCache[npc].lastForceConnect or 0
                if tick() - lastTry > 3 then
                    if npcCache[npc] then npcCache[npc].lastForceConnect = tick() end
                    CloneRecovery.VerifyCloneControl(npc)
                    break
                end
            end
        end
    end

    if state.ESP then
        for _, npc in ipairs(npcs) do
            local cache = npcCache[npc]
            if cache then
                local isConn = isConnected(npc)

                local hl = npc:FindFirstChild("NPC_ESP_HL")
                if not hl then
                    hl = Instance.new("Highlight")
                    hl.Name = "NPC_ESP_HL"
                    hl.FillTransparency = 0.5
                    hl.OutlineTransparency = 0
                    hl.Parent = npc
                end

                if isConn then
                    hl.FillColor = Color3.fromRGB(0, 255, 0)
                    hl.OutlineColor = Color3.fromRGB(0, 255, 0)
                else
                    hl.FillColor = Color3.fromRGB(255, 255, 255)
                    hl.OutlineColor = Color3.fromRGB(255, 255, 255)
                end

                local hrp = npc:FindFirstChild("HumanoidRootPart") or npc:FindFirstChild("Head")
                if hrp then
                    local bb = npc:FindFirstChild("NPC_ESP_BB")
                    if not bb then
                        bb = Instance.new("BillboardGui")
                        bb.Name = "NPC_ESP_BB"
                        bb.Size = UDim2.new(0, 100, 0, 50)
                        bb.StudsOffset = Vector3.new(0, 3, 0)
                        bb.AlwaysOnTop = true

                        local txt = Instance.new("TextLabel")
                        txt.Size = UDim2.new(1, 0, 1, 0)
                        txt.BackgroundTransparency = 1
                        txt.TextColor3 = Color3.fromRGB(255, 255, 255)
                        txt.TextStrokeTransparency = 0
                        txt.Font = Enum.Font.SourceSansBold
                        txt.TextSize = 20
                        txt.Parent = bb
                        bb.Parent = npc
                    end
                    local txt = bb:FindFirstChildOfClass("TextLabel")
                    if txt then
                        txt.Text = "[" .. cache.id .. "] " .. cache.type
                        txt.TextColor3 = isConn and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(255, 255, 255)
                    end
                end
            end
        end
    end

    if tick() - lastUIRefresh > 1 and NPCListFrame.Visible then
        lastUIRefresh = tick()
        for _, v in ipairs(NPCScroll:GetChildren()) do
            if v:IsA("Frame") then v:Destroy() end
        end

        for _, npc in ipairs(npcs) do
            local cache = npcCache[npc]
            if cache then
                local isConn = isConnected(npc)

                local row = Instance.new("Frame")
                row.Size = UDim2.new(1, 0, 0, 30)
                row.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
                row.Parent = NPCScroll

                local lbl = Instance.new("TextLabel")
                lbl.Size = UDim2.new(0.7, -5, 1, 0)
                lbl.Position = UDim2.new(0, 5, 0, 0)
                lbl.BackgroundTransparency = 1
                lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
                lbl.Text = "["..cache.id.."] " .. cache.type
                lbl.TextXAlignment = Enum.TextXAlignment.Left
                lbl.Font = Enum.Font.SourceSans
                lbl.TextSize = 14
                lbl.Parent = row

                local connBtn = Instance.new("TextButton")
                connBtn.Size = UDim2.new(0.3, -5, 0, 24)
                connBtn.Position = UDim2.new(0.7, 0, 0.5, -12)
                connBtn.BackgroundColor3 = isConn and Color3.fromRGB(0, 150, 0) or Color3.fromRGB(150, 0, 0)
                connBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
                connBtn.Text = isConn and "OK" or "Connect"
                connBtn.Font = Enum.Font.SourceSans
                connBtn.TextSize = 12
                connBtn.Parent = row

                connBtn.MouseButton1Click:Connect(function()
                    forceConnect(npc)
                    connBtn.Text = "Wait.."
                end)
            end
        end
    end

    local issuerChar = state.CommandIssuer and state.CommandIssuer.Character
    local issuerRoot = issuerChar and issuerChar:FindFirstChild("HumanoidRootPart")

    if state.Follow and issuerRoot then
        for _, npc in ipairs(ownedNpcs) do
            local hum = npc:FindFirstChild("Humanoid")
            local cache = npcCache[npc]
            if hum and hum.Health > 0 then
                if cache and cache.waypoints and cache.currentWaypoint and cache.currentWaypoint <= #cache.waypoints then
                    local wp = cache.waypoints[cache.currentWaypoint]
                    local hrp = npc:FindFirstChild("HumanoidRootPart")
                    if hrp then
                        hum:MoveTo(wp.Position)

                        local lookDir = hrp.CFrame.LookVector
                        local ray = Ray.new(hrp.Position, lookDir * 4)
                        local hit, pos = workspace:FindPartOnRay(ray, npc)
                        if hit and hit.CanCollide then
                            local jumpRay = Ray.new(pos + Vector3.new(0, 7, 0), Vector3.new(0, -7, 0))
                            local topHit, topPos = workspace:FindPartOnRay(jumpRay, npc)
                            if topHit and math.abs(pos.Y - topPos.Y) < 6 then
                                hum.Jump = true
                            end
                        end

                        if (hrp.Position - wp.Position).Magnitude < 3 then
                            cache.currentWaypoint = cache.currentWaypoint + 1
                        end
                        if wp.Action == Enum.PathWaypointAction.Jump then
                            hum.Jump = true
                        end
                    end
                else
                    hum:MoveTo(issuerRoot.Position)
                end
            end
        end
    elseif state.Mode == "Mecha" and issuerRoot then
        local roles = {
            {offset = CFrame.new(-2, -1, 0)},
            {offset = CFrame.new(2, -1, 0)},
            {offset = CFrame.new(-1, -3, 0)},
            {offset = CFrame.new(1, -3, 0)},
            {offset = CFrame.new(0, -1, 0.5)},
        }
        for i, npc in ipairs(ownedNpcs) do
            if i <= 5 then
                local hrp = npc:FindFirstChild("HumanoidRootPart")
                local hum = npc:FindFirstChild("Humanoid")
                if hrp and hum then
                    hum.PlatformStand = true
                    local alignPos = hrp:FindFirstChild("MechaAlign")
                    if not alignPos then
                        local att = hrp:FindFirstChild("MechaAtt") or Instance.new("Attachment", hrp)
                        att.Name = "MechaAtt"
                        alignPos = Instance.new("AlignPosition")
                        alignPos.Name = "MechaAlign"
                        alignPos.Mode = Enum.PositionAlignmentMode.OneAttachment
                        alignPos.Attachment0 = att
                        alignPos.MaxForce = 1000000
                        alignPos.Responsiveness = 200
                        alignPos.Parent = hrp

                        local alignOri = hrp:FindFirstChild("MechaOri") or Instance.new("AlignOrientation", hrp)
                        alignOri.Name = "MechaOri"
                        alignOri.Mode = Enum.OrientationAlignmentMode.OneAttachment
                        alignOri.Attachment0 = att
                        alignOri.MaxTorque = 1000000
                        alignOri.Responsiveness = 200
                    end
                    local targetCFrame = issuerRoot.CFrame * roles[i].offset
                    local alignOri = hrp:FindFirstChild("MechaOri")
                    alignPos.Position = targetCFrame.Position
                    if alignOri then alignOri.CFrame = targetCFrame end
                    hrp.Velocity = Vector3.zero
                    hrp.RotVelocity = Vector3.zero
                end
            end
        end
    elseif state.Mode == "STS" and issuerRoot then
        for i, npc in ipairs(ownedNpcs) do
            local hum = npc:FindFirstChild("Humanoid")
            local hrp = npc:FindFirstChild("HumanoidRootPart")
            if hum and hrp then
                local offset = (i - (#ownedNpcs/2)) * 4
                local targetPos = (issuerRoot.CFrame * CFrame.new(offset, 0, 0)).Position
                hum:MoveTo(targetPos)
            end
        end
    elseif state.Mode == "Assemble" and issuerRoot then
        for i, npc in ipairs(ownedNpcs) do
            local hum = npc:FindFirstChild("Humanoid")
            local hrp = npc:FindFirstChild("HumanoidRootPart")
            if hum and hrp then
                local offset = -3 - (i * 3)
                local targetPos = (issuerRoot.CFrame * CFrame.new(0, 0, -offset)).Position
                hum:MoveTo(targetPos)
            end
        end
    elseif state.Mode == "Stairs" and issuerRoot then
        for i, npc in ipairs(ownedNpcs) do
            local hrp = npc:FindFirstChild("HumanoidRootPart")
            local hum = npc:FindFirstChild("Humanoid")
            if hrp and hum then
                hum.PlatformStand = true
                local targetCFrame = issuerRoot.CFrame * CFrame.new(0, (i-1)*1.5, -3 - (i*2))
                local alignPos = hrp:FindFirstChild("MechaAlign")
                if not alignPos then
                    local att = hrp:FindFirstChild("MechaAtt") or Instance.new("Attachment", hrp)
                    att.Name = "MechaAtt"
                    alignPos = Instance.new("AlignPosition")
                    alignPos.Name = "MechaAlign"
                    alignPos.Mode = Enum.PositionAlignmentMode.OneAttachment
                    alignPos.Attachment0 = att
                    alignPos.MaxForce = 1000000
                    alignPos.Responsiveness = 200
                    alignPos.Parent = hrp

                    local alignOri = hrp:FindFirstChild("MechaOri") or Instance.new("AlignOrientation", hrp)
                    alignOri.Name = "MechaOri"
                    alignOri.Mode = Enum.OrientationAlignmentMode.OneAttachment
                    alignOri.Attachment0 = att
                    alignOri.MaxTorque = 1000000
                    alignOri.Responsiveness = 200
                end
                alignPos.Position = targetCFrame.Position
                hrp:FindFirstChild("MechaOri").CFrame = targetCFrame
                hrp.Velocity = Vector3.zero
            end
        end
    elseif state.Mode == "Dance" then
        for i, npc in ipairs(ownedNpcs) do
            local hrp = npc:FindFirstChild("HumanoidRootPart")
            local hum = npc:FindFirstChild("Humanoid")
            if hrp and hum then
                if tick() % 1 < 0.1 then
                    hum.Jump = true
                end
                local gyro = hrp:FindFirstChild("LookAtGyro")
                if not gyro then
                    gyro = Instance.new("BodyGyro")
                    gyro.Name = "LookAtGyro"
                    gyro.MaxTorque = Vector3.new(0, 400000, 0)
                    gyro.P = 3000
                    gyro.Parent = hrp
                end
                local angle = tick() * 5 + i
                gyro.CFrame = CFrame.new(hrp.Position) * CFrame.Angles(0, angle, 0)
            end
        end
    elseif state.Mode == "Orbit" and issuerRoot then
        local t = tick()
        for i, npc in ipairs(ownedNpcs) do
            if not state.StayingNPCs[npc] then
                local hum = npc:FindFirstChild("Humanoid")
                local hrp = npc:FindFirstChild("HumanoidRootPart")
                if hum and hrp then
                    local angle = (t * 2) + (i * (math.pi * 2 / #ownedNpcs))
                    local radius = 8
                    local targetPos = issuerRoot.Position + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
                    hum:MoveTo(targetPos)
                end
            end
        end
    elseif state.Mode == "Wall" and state.WallPos and state.WallDir then
        for i, npc in ipairs(ownedNpcs) do
            if not state.StayingNPCs[npc] then
                local hum = npc:FindFirstChild("Humanoid")
                local hrp = npc:FindFirstChild("HumanoidRootPart")
                if hum and hrp then
                    hum.Jump = true
                    local row = math.floor((i-1) / 5)
                    local col = (i-1) % 5
                    local targetPos = state.WallPos + (state.WallDir * ((col - 2) * 3)) + Vector3.new(0, row * 5, 0)
                    local alignPos = hrp:FindFirstChild("StackAlign")
                    if not alignPos then
                        local att = hrp:FindFirstChild("StackAtt") or Instance.new("Attachment", hrp)
                        att.Name = "StackAtt"
                        alignPos = Instance.new("AlignPosition")
                        alignPos.Name = "StackAlign"
                        alignPos.Mode = Enum.PositionAlignmentMode.OneAttachment
                        alignPos.Attachment0 = att
                        alignPos.MaxForce = 100000
                        alignPos.Responsiveness = 50
                        alignPos.Parent = hrp
                    end
                    alignPos.Position = targetPos
                    hrp.RotVelocity = Vector3.new(0,0,0)
                end
            end
        end
    elseif state.Mode == "Backflip" then
        for _, npc in ipairs(ownedNpcs) do
            if not state.StayingNPCs[npc] then
                local hrp = npc:FindFirstChild("HumanoidRootPart")
                local hum = npc:FindFirstChild("Humanoid")
                if hrp and hum then
                    hum.Jump = true
                    hrp.RotVelocity = hrp.CFrame.RightVector * 15
                end
            end
        end
    elseif state.Mode == "WhoDidIt" and state.WhoDidItTarget then
        local targetRoot = state.WhoDidItTarget.Character and state.WhoDidItTarget.Character:FindFirstChild("HumanoidRootPart")
        if targetRoot then
            for _, npc in ipairs(ownedNpcs) do
                local hrp = npc:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local gyro = hrp:FindFirstChild("LookAtGyro")
                    if not gyro then
                        gyro = Instance.new("BodyGyro")
                        gyro.Name = "LookAtGyro"
                        gyro.MaxTorque = Vector3.new(0, 400000, 0)
                        gyro.P = 3000
                        gyro.Parent = hrp
                    end
                    gyro.CFrame = CFrame.new(hrp.Position, Vector3.new(targetRoot.Position.X, hrp.Position.Y, targetRoot.Position.Z))
                end
            end
        end
    elseif state.Mode == "KillNPC" and state.KillTargetNPC then
        local targetRoot = state.KillTargetNPC:FindFirstChild("HumanoidRootPart")
        local targetHum = state.KillTargetNPC:FindFirstChild("Humanoid")
        if targetRoot and targetHum and targetHum.Health > 0 then
            if targetHum.Health > 0 then
                local runDir = Vector3.new(math.random(-1,1), 0, math.random(-1,1)).Unit
                if runDir.Magnitude > 0 then
                    targetHum:MoveTo(targetRoot.Position + runDir * 30)
                end
            end
            for _, npc in ipairs(ownedNpcs) do
                if npc ~= state.KillTargetNPC and not state.StayingNPCs[npc] then
                    local hum = npc:FindFirstChild("Humanoid")
                    local hrp = npc:FindFirstChild("HumanoidRootPart")
                    if hum and hrp then
                        hum:MoveTo(targetRoot.Position)
                        if (hrp.Position - targetRoot.Position).Magnitude < 4 then
                            targetHum.Health = 0
                        end
                    end
                end
            end
        end
    elseif state.Mode == "Find" and state.CurrentTargetName and issuerRoot then
        local matches = getPlayersByName(state.CurrentTargetName)
        local tRoot = nil
        for _, p in ipairs(matches) do
            if p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
                tRoot = p.Character.HumanoidRootPart
                break
            end
        end
        if tRoot then
            for i, npc in ipairs(ownedNpcs) do
                local hrp = npc:FindFirstChild("HumanoidRootPart")
                local hum = npc:FindFirstChild("Humanoid")
                if hrp and hum then
                    hum.PlatformStand = true
                    local targetCFrame = issuerRoot.CFrame * CFrame.new(0, 0, 1.5)
                    local alignPos = hrp:FindFirstChild("MechaAlign")
                    if not alignPos then
                        local att = hrp:FindFirstChild("MechaAtt") or Instance.new("Attachment", hrp)
                        att.Name = "MechaAtt"
                        alignPos = Instance.new("AlignPosition")
                        alignPos.Name = "MechaAlign"
                        alignPos.Mode = Enum.PositionAlignmentMode.OneAttachment
                        alignPos.Attachment0 = att
                        alignPos.MaxForce = 1000000
                        alignPos.Responsiveness = 200
                        alignPos.Parent = hrp

                        local alignOri = hrp:FindFirstChild("MechaOri") or Instance.new("AlignOrientation", hrp)
                        alignOri.Name = "MechaOri"
                        alignOri.Mode = Enum.OrientationAlignmentMode.OneAttachment
                        alignOri.Attachment0 = att
                        alignOri.MaxTorque = 1000000
                        alignOri.Responsiveness = 200
                    end
                    alignPos.Position = targetCFrame.Position
                    hrp:FindFirstChild("MechaOri").CFrame = targetCFrame
                end
            end
            local dir = (tRoot.Position - issuerRoot.Position).Unit
            issuerRoot.Velocity = Vector3.new(dir.X * 50, issuerRoot.Velocity.Y, dir.Z * 50)
        end
    elseif state.Mode == "YesOrNo" then
        if state.YesOrNoPick == 1 then
            if tick() - state.YesOrNoTick < 2 then
                for _, npc in ipairs(ownedNpcs) do
                    local hrp = npc:FindFirstChild("HumanoidRootPart")
                    if hrp then
                        local gyro = hrp:FindFirstChild("LookAtGyro")
                        if not gyro then
                            gyro = Instance.new("BodyGyro")
                            gyro.Name = "LookAtGyro"
                            gyro.MaxTorque = Vector3.new(400000, 400000, 400000)
                            gyro.P = 3000
                            gyro.Parent = hrp
                        end
                        local angle = math.sin(tick() * 10) * 0.5
                        gyro.CFrame = CFrame.new(hrp.Position) * CFrame.Angles(angle, 0, 0)
                    end
                end
            else
                state.Mode = nil
                for _, npc in ipairs(ownedNpcs) do
                    local hrp = npc:FindFirstChild("HumanoidRootPart")
                    if hrp then
                        local gyro = hrp:FindFirstChild("LookAtGyro")
                        if gyro then gyro:Destroy() end
                    end
                end
            end
        else
            if tick() - state.YesOrNoTick < 2 then
                for _, npc in ipairs(ownedNpcs) do
                    local hrp = npc:FindFirstChild("HumanoidRootPart")
                    if hrp then
                        local gyro = hrp:FindFirstChild("LookAtGyro")
                        if not gyro then
                            gyro = Instance.new("BodyGyro")
                            gyro.Name = "LookAtGyro"
                            gyro.MaxTorque = Vector3.new(0, 400000, 0)
                            gyro.P = 3000
                            gyro.Parent = hrp
                        end
                        local angle = math.sin(tick() * 10) * 1.5
                        gyro.CFrame = CFrame.new(hrp.Position) * CFrame.Angles(0, angle, 0)
                    end
                end
            else
                state.Mode = nil
                for _, npc in ipairs(ownedNpcs) do
                    local hrp = npc:FindFirstChild("HumanoidRootPart")
                    if hrp then
                        local gyro = hrp:FindFirstChild("LookAtGyro")
                        if gyro then gyro:Destroy() end
                    end
                end
            end
        end
    elseif state.Mode == "Train" and issuerRoot then
        local prevTarget = issuerRoot
        for _, npc in ipairs(ownedNpcs) do
            if not state.StayingNPCs[npc] then
                local hum = npc:FindFirstChild("Humanoid")
                local hrp = npc:FindFirstChild("HumanoidRootPart")
                if hum and hrp then
                    local targetPos = prevTarget.Position - (prevTarget.CFrame.LookVector * 4)
                    hum:MoveTo(targetPos)
                    prevTarget = hrp
                end
            else
                local hrp = npc:FindFirstChild("HumanoidRootPart")
                if hrp then prevTarget = hrp end
            end
        end
    elseif state.Mode == "Drag" and issuerRoot then
        local basePos = issuerRoot.Position + issuerRoot.CFrame.LookVector * 5
        for i, npc in ipairs(ownedNpcs) do
            if not state.StayingNPCs[npc] then
                local hum = npc:FindFirstChild("Humanoid")
                local hrp = npc:FindFirstChild("HumanoidRootPart")
                if hum and hrp then
                    local targetHeight = basePos + Vector3.new(0, (i-1) * 5, 0)

                    local alignPos = hrp:FindFirstChild("StackAlign")
                    if not alignPos then
                        local att = Instance.new("Attachment", hrp)
                        att.Name = "StackAtt"
                        alignPos = Instance.new("AlignPosition")
                        alignPos.Name = "StackAlign"
                        alignPos.Mode = Enum.PositionAlignmentMode.OneAttachment
                        alignPos.Attachment0 = att
                        alignPos.MaxForce = 100000
                        alignPos.Responsiveness = 200
                        alignPos.Parent = hrp
                    end
                    alignPos.Position = targetHeight
                    hrp.Velocity = Vector3.new(0,0,0)
                    hrp.RotVelocity = Vector3.new(0,0,0)
                end
            end
        end
    elseif state.Mode == "StackUp" and state.StackUpPos then
        for i, npc in ipairs(ownedNpcs) do
            if not state.StayingNPCs[npc] then
                local hum = npc:FindFirstChild("Humanoid")
                local hrp = npc:FindFirstChild("HumanoidRootPart")
                if hum and hrp then
                    local flatDist = (Vector2.new(hrp.Position.X, hrp.Position.Z) - Vector2.new(state.StackUpPos.X, state.StackUpPos.Z)).Magnitude
                    if flatDist > 2.5 then
                        hum:MoveTo(state.StackUpPos)
                        local alignPos = hrp:FindFirstChild("StackAlign")
                        if alignPos then alignPos:Destroy() end
                    else
                        hum.Jump = true
                        local targetHeight = state.StackUpPos + Vector3.new(0, (i-1) * 5, 0)
                        local alignPos = hrp:FindFirstChild("StackAlign")
                        if not alignPos then
                            local att = hrp:FindFirstChild("StackAtt") or Instance.new("Attachment", hrp)
                            att.Name = "StackAtt"
                            alignPos = Instance.new("AlignPosition")
                            alignPos.Name = "StackAlign"
                            alignPos.Mode = Enum.PositionAlignmentMode.OneAttachment
                            alignPos.Attachment0 = att
                            alignPos.MaxForce = 100000
                            alignPos.Responsiveness = 50
                            alignPos.Parent = hrp
                        end
                        alignPos.Position = targetHeight
                        hrp.RotVelocity = Vector3.new(0,0,0)
                    end
                end
            end
        end
    elseif state.Mode ~= "Drag" and state.Mode ~= "StackUp" and state.Mode ~= "Mecha" and state.Mode ~= "Stairs" and state.Mode ~= "Wall" and state.Mode ~= "Find" then
        for _, npc in ipairs(ownedNpcs) do
            local hrp = npc:FindFirstChild("HumanoidRootPart")
            local hum = npc:FindFirstChild("Humanoid")
            if hrp then
                local alignPos = hrp:FindFirstChild("StackAlign")
                if alignPos then alignPos:Destroy() end
                local att = hrp:FindFirstChild("StackAtt")
                if att then att:Destroy() end

                local mechaAlign = hrp:FindFirstChild("MechaAlign")
                if mechaAlign then mechaAlign:Destroy() end
                local mechaOri = hrp:FindFirstChild("MechaOri")
                if mechaOri then mechaOri:Destroy() end
                local mechaAtt = hrp:FindFirstChild("MechaAtt")
                if mechaAtt then mechaAtt:Destroy() end
            end
            if hum and not hrp:FindFirstChild("StackAlign") and not hrp:FindFirstChild("MechaAlign") then
                hum.PlatformStand = false
            end
        end
    end

    if state.Mode == "Sit" then
        for _, npc in ipairs(ownedNpcs) do
            local hum = npc:FindFirstChild("Humanoid")
            if hum then hum.Sit = true end
        end
    elseif state.Mode == "LookAt" and state.CurrentTargetName then
        local matches = getPlayersByName(state.CurrentTargetName)
        for _, npc in ipairs(ownedNpcs) do
            local hrp = npc:FindFirstChild("HumanoidRootPart")
            if hrp then
                local closestDist = math.huge
                local closestRoot = nil
                for _, p in ipairs(matches) do
                    local tRoot = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
                    if tRoot then
                        local dist = (tRoot.Position - hrp.Position).Magnitude
                        if dist < closestDist then
                            closestDist = dist
                            closestRoot = tRoot
                        end
                    end
                end

                if closestRoot then
                    local gyro = hrp:FindFirstChild("LookAtGyro")
                    if not gyro then
                        gyro = Instance.new("BodyGyro")
                        gyro.Name = "LookAtGyro"
                        gyro.MaxTorque = Vector3.new(0, 400000, 0)
                        gyro.P = 3000
                        gyro.Parent = hrp
                    end
                    gyro.CFrame = CFrame.new(hrp.Position, Vector3.new(closestRoot.Position.X, hrp.Position.Y, closestRoot.Position.Z))
                end
            end
        end
    elseif state.Mode ~= "LookAt" and state.Mode ~= "YesOrNo" and state.Mode ~= "WhoDidIt" then
        for _, npc in ipairs(ownedNpcs) do
            local hrp = npc:FindFirstChild("HumanoidRootPart")
            if hrp then
                local gyro = hrp:FindFirstChild("LookAtGyro")
                if gyro then gyro:Destroy() end
            end
        end
    end

    if state.Mode == "Attack" and state.CurrentTarget and state.CurrentTarget.Character then
        local targetRoot = state.CurrentTarget.Character:FindFirstChild("HumanoidRootPart")
        if targetRoot then
            for _, npc in ipairs(ownedNpcs) do
                local hum = npc:FindFirstChild("Humanoid")
                local cache = npcCache[npc]
                if hum and hum.Health > 0 then
                    if cache and cache.waypoints and cache.currentWaypoint and cache.currentWaypoint <= #cache.waypoints then
                        local wp = cache.waypoints[cache.currentWaypoint]
                        local hrp = npc:FindFirstChild("HumanoidRootPart")
                        if hrp then
                            hum:MoveTo(wp.Position)

                            local lookDir = hrp.CFrame.LookVector
                            local ray = Ray.new(hrp.Position, lookDir * 4)
                            local hit, pos = workspace:FindPartOnRay(ray, npc)
                            if hit and hit.CanCollide then
                                local jumpRay = Ray.new(pos + Vector3.new(0, 7, 0), Vector3.new(0, -7, 0))
                                local topHit, topPos = workspace:FindPartOnRay(jumpRay, npc)
                                if topHit and math.abs(pos.Y - topPos.Y) < 6 then
                                    hum.Jump = true
                                end
                            end

                            if (hrp.Position - wp.Position).Magnitude < 3 then
                                cache.currentWaypoint = cache.currentWaypoint + 1
                            end
                            if wp.Action == Enum.PathWaypointAction.Jump then
                                hum.Jump = true
                            end
                        end
                    else
                        hum:MoveTo(targetRoot.Position)
                    end
                end
            end
        end
    elseif state.Mode == "Makeway" and issuerRoot then
        for _, npc in ipairs(ownedNpcs) do
            local hum = npc:FindFirstChild("Humanoid")
            local hrp = npc:FindFirstChild("HumanoidRootPart")
            if hum and hrp then
                local dir = (hrp.Position - issuerRoot.Position).Unit
                hum:MoveTo(hrp.Position + dir * 30)
            end
        end
    elseif state.Mode == "Arise" then
        if tick() > nextRandomMove then
            for _, npc in ipairs(ownedNpcs) do
                local hum = npc:FindFirstChild("Humanoid")
                local hrp = npc:FindFirstChild("HumanoidRootPart")
                if hum and hrp then
                    local randomOffset = Vector3.new(math.random(-40, 40), 0, math.random(-40, 40))
                    hum:MoveTo(hrp.Position + randomOffset)
                end
            end
        end
    end

    if state.Mode == "Arise" and tick() > nextRandomMove then
        nextRandomMove = tick() + math.random(2, 5)
    end

    for _, npc in ipairs(ownedNpcs) do
        if state.StayingNPCs[npc] then
            local hum = npc:FindFirstChild("Humanoid")
            local hrp = npc:FindFirstChild("HumanoidRootPart")
            if hum and hrp then
                hum:MoveTo(hrp.Position)
                local alignPos = hrp:FindFirstChild("StackAlign")
                if alignPos then alignPos:Destroy() end
            end
        end
    end
end)

local dragging, dragInput, dragStart, startPos
local draggingB, dragInputB, dragStartB, startPosB

MainFrame.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = MainFrame.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
end)

MainFrame.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
        dragInput = input
    end
end)

BubbleFrame.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        draggingB = true
        dragStartB = input.Position
        startPosB = BubbleFrame.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                draggingB = false
            end
        end)
    end
end)

BubbleFrame.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
        dragInputB = input
    end
end)

RunService.RenderStepped:Connect(function()
    if dragging and dragInput then
        local delta = dragInput.Position - dragStart
        MainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
    if draggingB and dragInputB then
        local delta = dragInputB.Position - dragStartB
        BubbleFrame.Position = UDim2.new(startPosB.X.Scale, startPosB.X.Offset + delta.X, startPosB.Y.Scale, startPosB.Y.Offset + delta.Y)
    end
end)

local PathfindingService = game:GetService("PathfindingService")

task.spawn(function()
    while task.wait(0.5) do
        if not state.AutoConnect then continue end
        local npcs = getNPCs()
        local targetRoot = nil

        if state.Mode == "Attack" and state.CurrentTarget and state.CurrentTarget.Character then
            targetRoot = state.CurrentTarget.Character:FindFirstChild("HumanoidRootPart")
        elseif state.Follow and state.CommandIssuer and state.CommandIssuer.Character then
            targetRoot = state.CommandIssuer.Character:FindFirstChild("HumanoidRootPart")
        end

        if targetRoot then
            for _, npc in ipairs(npcs) do
                local hrp = npc:FindFirstChild("HumanoidRootPart")
                local hum = npc:FindFirstChild("Humanoid")
                local cache = npcCache[npc]
                if hrp and hum and hum.Health > 0 and cache and isConnected(npc) then
                    local dist = (hrp.Position - targetRoot.Position).Magnitude
                    if dist > 5 and dist < 500 then
                        local ray = Ray.new(hrp.Position, (targetRoot.Position - hrp.Position).Unit * dist)
                        local hit, pos = workspace:FindPartOnRayWithIgnoreList(ray, {npc, targetRoot.Parent})
                        if hit and not hit.CanCollide then hit = nil end

                        if hit then
                            local path = PathfindingService:CreatePath({
                                AgentRadius = 2,
                                AgentHeight = 5,
                                AgentCanJump = true,
                                AgentCanClimb = true,
                                WaypointSpacing = 4,
                            })
                            pcall(function()
                                path:ComputeAsync(hrp.Position, targetRoot.Position)
                                if path.Status == Enum.PathStatus.Success then
                                    cache.waypoints = path:GetWaypoints()
                                    cache.currentWaypoint = 2
                                else
                                    cache.waypoints = nil
                                end
                            end)
                        else
                            cache.waypoints = nil
                        end
                    else
                        cache.waypoints = nil
                    end
                end
            end
        end
    end
end)
