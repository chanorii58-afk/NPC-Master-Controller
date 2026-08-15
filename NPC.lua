-- NPC Controller (Server-Sided & Infinite Range Optimized)
-- MODIFIED FOR SERVER OWNERSHIP: All players will see these changes.
-- NOTE: For this to work globally, this must be executed in a Server Script or SS Executor.
-- UPDATE: Added SimulationRadius bypass for Arceus X Neo client-side execution to maintain infinite range.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local StarterGui = game:GetService("StarterGui")

-- In a true Server Script, LocalPlayer is nil. We try to grab the first player or define it if injected.
local LocalPlayer = Players.LocalPlayer or Players:GetPlayers()[1]
Players.PlayerAdded:Connect(function(p)
	if not LocalPlayer then LocalPlayer = p end
end)

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
	StackUpPos = nil,
	NetworkRange = math.huge,
	SpecificFollow = {},
	RoamPoints = {},
	CurrentRoamIndex = {},
	PathfindTarget = nil,
	MimicNPCs = {},
	OrbitSpeed = 1,
	SelfDefense = false,
	ShowRadius = false,
	NanFlingTarget = nil,
	GlobalAttackTarget = nil,
	GlobalFreeze = false,
	PossessedNPC = nil,
	MMKiller = nil,
	MMFleeing = {},
	MMChasing = nil,
	AURoles = {},
	AUVents = {},
	AUTasks = {},
	AUCafs = {},
	AUMeeting = false,
	AUVotes = {},
	AULastKill = tick(),
	AUPhase = nil,
	BuildMode = nil,
	BlueNPC = nil,
	RedNPC = nil,
	PurplePhase = 0,
	PurpleTick = 0,
	PurpleStartCFrame = nil,
	PossessedNPC = nil,
	BlueNPC = nil,
	RedNPC = nil,
	PurplePhase = 0,
	PurpleTick = 0,
	PurpleStartCFrame = nil
}

-- ==========================================
-- INFINITE RANGE EXECUTOR OPTIMIZATION
-- ==========================================
-- Bypasses the client-side physics cutoff by maximizing your simulation radius.
task.spawn(function()
	RunService.Heartbeat:Connect(function()
		pcall(function()
			if LocalPlayer then
				local r = state.NetworkRange or math.huge
				if sethiddenproperty then
					sethiddenproperty(LocalPlayer, "SimulationRadius", r)
					sethiddenproperty(LocalPlayer, "MaxSimulationRadius", r)
				else
					LocalPlayer.SimulationRadius = r
				end
				
				local radPart = workspace:FindFirstChild("NPCRadiusVisual")
				if state.ShowRadius and r ~= math.huge then
					if not radPart then
						radPart = Instance.new("Part")
						radPart.Name = "NPCRadiusVisual"
						radPart.Shape = Enum.PartType.Ball
						radPart.Material = Enum.Material.ForceField
						radPart.Color = Color3.fromRGB(0, 255, 0)
						radPart.Anchored = true
						radPart.CanCollide = false
						radPart.CastShadow = false
						radPart.Parent = workspace
					end
					radPart.Size = Vector3.new(r * 2, r * 2, r * 2)
					local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
					if myRoot then
						radPart.Position = myRoot.Position
					end
				elseif radPart then
					radPart:Destroy()
				end
			end
		end)
	end)
end)

-- Enforce Absolute Server Ownership (Infinite Range & Superior Control)
local function smartMoveTo(hum, targetPos)
	local hrp = hum.Parent and hum.Parent:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	if (hrp.Position - targetPos).Magnitude < 15 then
		hum:MoveTo(targetPos)
		return
	end
	local path = PathfindingService:CreatePath()
	local s, e = pcall(function() path:ComputeAsync(hrp.Position, targetPos) end)
	if s and path.Status == Enum.PathStatus.Success then
		local wps = path:GetWaypoints()
		if #wps > 1 then
			hum:MoveTo(wps[2].Position)
		else
			hum:MoveTo(targetPos)
		end
	else
		hum:MoveTo(targetPos)
	end
end

local function enforceServerOwnership(hrp)
	if hrp and hrp:IsA("BasePart") then
		pcall(function()
			if type(hrp.SetNetworkOwner) == "function" then hrp:SetNetworkOwner(nil) end -- nil forces the SERVER to calculate physics
		end)
	end
end

local function isConnected(npc)
	local hrp = npc:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end

	local success, owner = pcall(function() if type(getnetworkowner)=="function" then return getnetworkowner(hrp) elseif type(hrp.GetNetworkOwner)=="function" then return hrp:GetNetworkOwner() else error("No NetOwner") end end)
	if success and owner == nil then
		return true -- Server owns it
	end

	local successAge, age = pcall(function() return hrp.ReceiveAge end)
	if successAge and age == 0 and not hrp.Anchored then
		return true
	end
	return false
end

local function forceConnect(npc)
	local hrp = npc:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local hum = npc:FindFirstChild("Humanoid")
	if not hum or hum.Health <= 0 then return end

	-- Absolute Server Ownership Assignment
	enforceServerOwnership(hrp)

	pcall(function()
		hum:ChangeState(Enum.HumanoidStateType.Running)
		hum.PlatformStand = false
		hum.Sit = false
	end)
	hrp.Anchored = false

	-- Micro-movement to keep physics awake
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

function CloneRecovery.RefreshCloneReferences(npc)
	local hum = npc:FindFirstChild("Humanoid")
	local hrp = npc:FindFirstChild("HumanoidRootPart")
	return hum, hrp
end

function CloneRecovery.MoveToCloneForRecovery(npc)
	if not LocalPlayer then return nil end
	local myChar = LocalPlayer.Character
	local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
	local hum, hrp = CloneRecovery.RefreshCloneReferences(npc)
	if myRoot and hrp then
		local oldCFrame = myRoot.CFrame
		myRoot.CFrame = hrp.CFrame
		return oldCFrame
	end
	return nil
end

function CloneRecovery.RestoreOriginalPosition(oldCFrame)
	if not LocalPlayer then return end
	local myChar = LocalPlayer.Character
	local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
	if myRoot and oldCFrame then
		myRoot.CFrame = oldCFrame
		myRoot.AssemblyLinearVelocity = Vector3.zero
	end
end

function CloneRecovery.RecoverClone(npc)
	if CloneRecovery.IsCloneConnected(npc) then return true end

	local oldPos = CloneRecovery.MoveToCloneForRecovery(npc)
	task.wait(0.15)
	forceConnect(npc)

	local attempts = 0
	while not CloneRecovery.IsCloneConnected(npc) and attempts < 10 do
		attempts = attempts + 1
		forceConnect(npc)
		task.wait(0.1)
	end

	if oldPos then
		CloneRecovery.RestoreOriginalPosition(oldPos)
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
	local nameStrLower = string.lower(string.match(nameStr, "^%s*(.-)%s*$") or nameStr)
	nameStrLower = string.gsub(nameStrLower, "[%(%)]", "")
	if nameStrLower == "" then return nil end
	for _, p in ipairs(Players:GetPlayers()) do
		local pName = p.Name and string.lower(p.Name) or ""
		local pDisp = p.DisplayName and string.lower(p.DisplayName) or ""
		if pName == nameStrLower or pDisp == nameStrLower then return p end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		local pName = p.Name and string.lower(p.Name) or ""
		local pDisp = p.DisplayName and string.lower(p.DisplayName) or ""
		if string.find(pName, nameStrLower, 1, true) or string.find(pDisp, nameStrLower, 1, true) then
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
		if (pName ~= "" and string.find(pName, nameStrLower, 1, true)) or
			(pDisp ~= "" and string.find(pDisp, nameStrLower, 1, true)) then
			table.insert(matches, p)
		end
	end
	return matches
end

local function notify(title, text)
	print("[NPC Controller] " .. title .. ": " .. text)
end

-- GUI Setup
local targetParent
if LocalPlayer then
	targetParent = LocalPlayer:WaitForChild("PlayerGui")
else
	targetParent = game:GetService("StarterGui")
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
ScreenGui.IgnoreGuiInset = true
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
MainFrame.Size = UDim2.new(0, 150, 0, 285)
MainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
MainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
MainFrame.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
MainFrame.Active = true
MainFrame.Parent = ScreenGui

local CloseMainBtn = Instance.new("TextButton")
CloseMainBtn.Size = UDim2.new(0, 25, 0, 25)
CloseMainBtn.Position = UDim2.new(1, -25, 0, 0)
CloseMainBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
CloseMainBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CloseMainBtn.Text = "X"
CloseMainBtn.Font = Enum.Font.SourceSansBold
CloseMainBtn.TextSize = 14
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
Title.Size = UDim2.new(1, -25, 0, 25)
Title.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
Title.TextColor3 = Color3.fromRGB(255, 255, 255)
Title.Text = "NPC Controller (Server)"
Title.Font = Enum.Font.SourceSansBold
Title.TextSize = 14
Title.Parent = MainFrame

local MainScroll = Instance.new("ScrollingFrame")
MainScroll.Size = UDim2.new(1, 0, 1, -25)
MainScroll.Position = UDim2.new(0, 0, 0, 25)
MainScroll.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
MainScroll.ScrollBarThickness = 4
MainScroll.CanvasSize = UDim2.new(0, 0, 0, 310)
MainScroll.Parent = MainFrame

local UIListLayoutMain = Instance.new("UIListLayout")
UIListLayoutMain.Padding = UDim.new(0, 2)
UIListLayoutMain.HorizontalAlignment = Enum.HorizontalAlignment.Center
UIListLayoutMain.Parent = MainScroll

UIListLayoutMain:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	MainScroll.CanvasSize = UDim2.new(0, 0, 0, UIListLayoutMain.AbsoluteContentSize.Y + 10)
end)

local function createToggle(name)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, -16, 0, 25)
	btn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.Text = name .. ": OFF"
	btn.Font = Enum.Font.SourceSans
	btn.TextSize = 12
	btn.Parent = MainScroll
	return btn
end

local function createButton(name)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, -16, 0, 25)
	btn.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.Text = name
	btn.Font = Enum.Font.SourceSans
	btn.TextSize = 12
	btn.Parent = MainScroll
	return btn
end

local Spacer = Instance.new("Frame")
Spacer.Size = UDim2.new(1, 0, 0, 2)
Spacer.BackgroundTransparency = 1
Spacer.Parent = MainScroll

local btnFollow = createToggle("Follow Me")
local btnSpin = createToggle("Spin NPCs")
local btnChat = createToggle("Chat Commands")
local btnESP = createToggle("NPC ESP")
local btnAutoConnect = createToggle("Auto Connect")
local btnGossip = createToggle("Gossip Mode")
local btnAntiLag = createToggle("Anti-Lag")
local btnShowRadius = createToggle("Visible Radius")
local btnCmdsList = createButton("Show Commands")
local btnToggleList = createButton("NPC Lists")
local Spacer2 = Instance.new("Frame")
Spacer2.Size = UDim2.new(1, 0, 0, 10)
Spacer2.BackgroundTransparency = 1
Spacer2.Parent = MainScroll

local btnKillRadius = createButton("Kill NPCs (2 Studs)")
btnKillRadius.BackgroundColor3 = Color3.fromRGB(150, 50, 50)
btnKillRadius.MouseButton1Click:Connect(function()
	local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
	if myRoot then
		local count = 0
		for _, npc in ipairs(getNPCs()) do
			local hrp = npc:FindFirstChild("HumanoidRootPart")
			local hum = npc:FindFirstChild("Humanoid")
			if hrp and hum and hum.Health > 0 then
				if (hrp.Position - myRoot.Position).Magnitude <= 2.5 then
					hrp.CFrame = CFrame.new(0, -50000, 0)
						hrp.Velocity = Vector3.new(0, -1000, 0)
					count = count + 1
				end
			end
		end
		notify("Kill", "Killed " .. count .. " NPCs nearby.")
	end
end)

local function getNetOwnerSafe(hrp)
	if type(getnetworkowner) == "function" then
		local s, o = pcall(getnetworkowner, hrp)
		if s then return o end
	end
	if hrp and type(hrp.GetNetworkOwner) == "function" then
		local s, o = pcall(function() if type(getnetworkowner)=="function" then return getnetworkowner(hrp) elseif type(hrp.GetNetworkOwner)=="function" then return hrp:GetNetworkOwner() else error("No NetOwner") end end)
		if s then return o end
	end
	return nil
end

local btnKillLocal = createButton("Kill Local (2 Studs)")
btnKillLocal.BackgroundColor3 = Color3.fromRGB(150, 80, 50)
btnKillLocal.MouseButton1Click:Connect(function()
	local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
	if myRoot then
		local count = 0
		for _, npc in ipairs(getNPCs()) do
			local hrp = npc:FindFirstChild("HumanoidRootPart")
			local hum = npc:FindFirstChild("Humanoid")
			if hrp and hum and hum.Health > 0 then
				if (hrp.Position - myRoot.Position).Magnitude <= 2.5 then
					local owner = getNetOwnerSafe(hrp)
					if owner ~= nil then
						hrp.CFrame = CFrame.new(0, -50000, 0)
						hrp.Velocity = Vector3.new(0, -1000, 0)
						count = count + 1
					end
				end
			end
		end
		notify("Kill Local", "Killed " .. count .. " owned NPCs nearby.")
	end
end)

local btnKillPassive = createButton("Kill Passive (900 Studs)")
btnKillPassive.BackgroundColor3 = Color3.fromRGB(150, 50, 80)
btnKillPassive.MouseButton1Click:Connect(function()
	local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
	if myRoot then
		local count = 0
		for _, npc in ipairs(getNPCs()) do
			local hrp = npc:FindFirstChild("HumanoidRootPart")
			local hum = npc:FindFirstChild("Humanoid")
			if hrp and hum and hum.Health > 0 then
				if (hrp.Position - myRoot.Position).Magnitude <= 900 then
					local owner = getNetOwnerSafe(hrp)
					if owner == nil then
						hrp.CFrame = CFrame.new(0, -50000, 0)
						hrp.Velocity = Vector3.new(0, -1000, 0)
						count = count + 1
					end
				end
			end
		end
		notify("Kill Passive", "Killed " .. count .. " unowned NPCs.")
	end
end)

btnShowRadius.MouseButton1Click:Connect(function()
	state.ShowRadius = not state.ShowRadius
	btnShowRadius.Text = "Visible Radius: " .. (state.ShowRadius and "ON" or "OFF")
	btnShowRadius.BackgroundColor3 = state.ShowRadius and Color3.fromRGB(50, 150, 50) or Color3.fromRGB(50, 50, 50)
end)




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
	"[id] follow [player] - Specific follow",
	"ufo - Orbit and levitate",
	".range [inf/number] - Set network range",
	"roam here [id] - Set roam point (use twice)",
	"stop roam [id] - Stop roaming",
	"pathfind [player] - Pathfind to target",
	"[id] goto [player] - Teleport ID to target",
	"[id] tempgoto [player] - Teleport ID for 5s",
	"follow me [id/all] - Mimic your movements",
	"self defense - Toggle fling protection",
	"fling [player] - Target walks to fling",
	"nanfling [player] - Teleport inside target and fling",
	"orbit speed [value] - Adjust UFO/orbit speed",
	"tp [id] - Teleport to NPC",
	"posses [id] - Take control of NPC",
	"unposses - Stop possessing",
	"star - Orbit in star shape",
	"lapse blue - Gojo Lapse Blue",
	"reversal red - Gojo Reversal Red",
	"hollow purple - Combine Blue and Red",
	"wall orbit - Orbit in a wall formation",
	"helicopter - Fly like a helicopter",
	"sphere - Orbit in a perfect sphere",
	"murder mystery - Start Murder Mystery game",
	"!among us - Start Among Us game",
	"!build - Get the map build tool",
	"!stop game - Stop active minigame",
	"!attack [display] - All NPCs attack target",
	"!freeze - Freeze all NPCs",
	"!unfreeze - Unfreeze all NPCs",
	"tp [id] - Teleport to NPC",
	"posses [id] - Take control of NPC",
	"unposses - Stop possessing",
	"star - Orbit in star shape",
	"lapse blue - Gojo Lapse Blue",
	"reversal red - Gojo Reversal Red",
	"hollow purple - Combine Blue and Red",

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

	local isNumericFirst = tonumber(cmd) ~= nil
	if isNumericFirst then
		local npcId = tonumber(cmd)
		local subCmd = args[2]
		if subCmd == "follow" and args[3] then
			local target = getPlayer(table.concat(args, " ", 3))
			local npc = getNPCById(npcId)
			if target and npc then
				state.SpecificFollow[npc] = target
				notify("Follow", "NPC " .. npcId .. " following " .. target.Name)
			end
		elseif subCmd == "goto" and args[3] then
			local target = getPlayer(table.concat(args, " ", 3))
			local npc = getNPCById(npcId)
			if target and npc and target.Character and target.Character:FindFirstChild("HumanoidRootPart") then
				local tRoot = target.Character.HumanoidRootPart
				local hrp = npc:FindFirstChild("HumanoidRootPart")
				if hrp then
					hrp.CFrame = tRoot.CFrame * CFrame.new(0, 0, -3)
				end
			end
		elseif subCmd == "tempgoto" and args[3] then
			local target = getPlayer(table.concat(args, " ", 3))
			local npc = getNPCById(npcId)
			if target and npc and target.Character and target.Character:FindFirstChild("HumanoidRootPart") then
				task.spawn(function()
					local tRoot = target.Character.HumanoidRootPart
					local hrp = npc:FindFirstChild("HumanoidRootPart")
					if hrp then
						hrp.CFrame = tRoot.CFrame * CFrame.new(0, 0, -3)
						task.wait(5)
						local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
						if myRoot and hrp then
							hrp.CFrame = myRoot.CFrame * CFrame.new(0, 0, -3)
						end
					end
				end)
			end
		end
		return
	end


	if cmd == ".givecommand" and player == LocalPlayer then
		local target = getPlayer(table.concat(args, " ", 2))
		local permCmd = args[3]
		if target and permCmd then
			if not permissions[target.UserId] then
				permissions[target.UserId] = {}
			end
			permissions[target.UserId][permCmd] = true
			notify("Permission", "Gave " .. target.Name .. " access to: " .. permCmd)
		end
	elseif cmd == ".stripcommand" and player == LocalPlayer then
		local target = getPlayer(table.concat(args, " ", 2))
		local permCmd = args[3]
		if target and permCmd and permissions[target.UserId] then
			permissions[target.UserId][permCmd] = nil
			notify("Permission", "Removed " .. target.Name .. "'s access to: " .. permCmd)
		end
	elseif cmd == "ufo" then
		state.Mode = "UFO"
		state.Follow = false
		state.CommandIssuer = player
	elseif cmd == ".range" and args[2] then
		if args[2] == "inf" or args[2] == "nil" then
			state.NetworkRange = math.huge
		else
			state.NetworkRange = tonumber(args[2]) or math.huge
		end
	elseif cmd == "roam" and args[2] == "here" and args[3] then
		local npcId = tonumber(args[3])
		if npcId then
			local npc = getNPCById(npcId)
			local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
			if npc and myRoot then
				state.RoamPoints[npc] = state.RoamPoints[npc] or {}
				table.insert(state.RoamPoints[npc], myRoot.Position)
				
				state.CurrentRoamIndex[npc] = 1
			end
		end
	elseif cmd == "stop" and args[2] == "roam" and args[3] then
		local npcId = tonumber(args[3])
		if npcId then
			local npc = getNPCById(npcId)
			if npc then
				state.RoamPoints[npc] = nil
			end
		end
	elseif cmd == "tp" and args[2] then
		local npcId = tonumber(args[2])
		if npcId then
			local npc = getNPCById(npcId)
			local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
			if npc and myRoot and npc:FindFirstChild("HumanoidRootPart") then
				myRoot.CFrame = npc.HumanoidRootPart.CFrame
				notify("TP", "Teleported to NPC " .. npcId)
			end
		end
	elseif cmd == "posses" and args[2] then
		local npcId = tonumber(args[2])
		if npcId then
			local npc = getNPCById(npcId)
			if npc and npc:FindFirstChild("Humanoid") then
				state.PossessedNPC = npc
				notify("Possess", "Possessing NPC " .. npcId)
			end
		end
	elseif cmd == "unposses" then
		state.PossessedNPC = nil
		if workspace.CurrentCamera and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
			workspace.CurrentCamera.CameraSubject = LocalPlayer.Character.Humanoid
		end
		notify("Possess", "Unpossessed")
	elseif cmd == "star" then
		state.Mode = "Star"
		state.Follow = false
		state.CommandIssuer = player
	elseif cmd == "lapse" and args[2] == "blue" then
		local npc = nil
		for _, n in ipairs(getNPCs()) do
			if n ~= state.RedNPC and n ~= state.BlueNPC and not state.StayingNPCs[n] then
				npc = n
				break
			end
		end
		if npc then
			state.BlueNPC = npc
			state.PurplePhase = 0
			notify("JJK", "Lapse Blue initiated")
		end
	elseif cmd == "reversal" and args[2] == "red" then
		local npc = nil
		for _, n in ipairs(getNPCs()) do
			if n ~= state.RedNPC and n ~= state.BlueNPC and not state.StayingNPCs[n] then
				npc = n
				break
			end
		end
		if npc then
			state.RedNPC = npc
			state.PurplePhase = 0
			notify("JJK", "Reversal Red initiated")
		end
	elseif cmd == "hollow" and args[2] == "purple" then
		if state.BlueNPC and state.RedNPC then
			state.PurplePhase = 1
			state.PurpleTick = tick()
			notify("JJK", "Hollow Purple combining!")
		else
			notify("JJK", "Need both Blue and Red active!")
		end
	elseif cmd == "tp" and args[2] then
		local npcId = tonumber(args[2])
		if npcId then
			local npc = getNPCById(npcId)
			local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
			if npc and myRoot and npc:FindFirstChild("HumanoidRootPart") then
				myRoot.CFrame = npc.HumanoidRootPart.CFrame
				notify("TP", "Teleported to NPC " .. npcId)
			end
		end
	elseif cmd == "posses" and args[2] then
		local npcId = tonumber(args[2])
		if npcId then
			local npc = getNPCById(npcId)
			if npc and npc:FindFirstChild("Humanoid") then
				state.PossessedNPC = npc
				notify("Possess", "Possessing NPC " .. npcId)
			end
		end
	elseif cmd == "unposses" then
		state.PossessedNPC = nil
		if workspace.CurrentCamera and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
			workspace.CurrentCamera.CameraSubject = LocalPlayer.Character.Humanoid
		end
		notify("Possess", "Unpossessed")
	elseif cmd == "star" then
		state.Mode = "Star"
		state.Follow = false
		state.CommandIssuer = player
	elseif cmd == "lapse" and args[2] == "blue" then
		local npc = nil
		for _, n in ipairs(getNPCs()) do
			if n ~= state.RedNPC and n ~= state.BlueNPC and not state.StayingNPCs[n] then
				npc = n
				break
			end
		end
		if npc then
			state.BlueNPC = npc
			state.PurplePhase = 0
			notify("JJK", "Lapse Blue initiated")
		end
	elseif cmd == "reversal" and args[2] == "red" then
		local npc = nil
		for _, n in ipairs(getNPCs()) do
			if n ~= state.RedNPC and n ~= state.BlueNPC and not state.StayingNPCs[n] then
				npc = n
				break
			end
		end
		if npc then
			state.RedNPC = npc
			state.PurplePhase = 0
			notify("JJK", "Reversal Red initiated")
		end
	elseif cmd == "hollow" and args[2] == "purple" then
		if state.BlueNPC and state.RedNPC then
			state.PurplePhase = 1
			state.PurpleTick = tick()
			notify("JJK", "Hollow Purple combining!")
		else
			notify("JJK", "Need both Blue and Red active!")
		end
	elseif cmd == "!attack" and args[2] then
		local target = getPlayer(table.concat(args, " ", 2))
		if target then
			state.GlobalAttackTarget = target
			notify("Global Attack", "All NPCs attacking " .. target.Name)
		end
	elseif cmd == "!freeze" then
		state.GlobalFreeze = true
		notify("Global Freeze", "All NPCs frozen")
	elseif cmd == "wall" and args[2] == "orbit" then
		state.Mode = "WallOrbit"
		notify("Wall", "Orbiting")
	elseif cmd == "murder" and args[2] == "mystery" then
		state.Mode = "MurderMystery"
		state.MMKiller = nil
		state.MMChasing = nil
		state.MMFleeing = {}
		local npcs = getNPCs()
		if #npcs > 0 then
			state.MMKiller = npcs[math.random(1, #npcs)]
			notify("Murder Mystery", "Game started! Killer selected.")
		end
	elseif cmd == "helicopter" then
		state.Mode = "Helicopter"
		notify("Helicopter", "Assembling helicopter")
	elseif cmd == "sphere" then
		state.Mode = "Sphere"
		notify("Sphere", "Orbiting in a sphere")
	elseif cmd == "!among" and args[2] == "us" then
		state.Mode = "AmongUs"
		state.AUPhase = "Playing"
		state.AURoles = {}
		state.AULastKill = tick()
		local npcs = getNPCs()
		local shuffled = {}
		for _, n in ipairs(npcs) do table.insert(shuffled, n) end
		for i = #shuffled, 2, -1 do
			local j = math.random(i)
			shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
		end
		local numImps = math.min(3, math.floor(#shuffled / 4))
		if numImps < 1 then numImps = 1 end
		local numEng = math.min(2, math.floor(#shuffled / 5))
		for i = 1, #shuffled do
			if i <= numImps then state.AURoles[shuffled[i]] = "Imposter"
			elseif i <= numImps + numEng then state.AURoles[shuffled[i]] = "Engineer"
			else state.AURoles[shuffled[i]] = "Crew" end
		end
		notify("Among Us", "Started with " .. numImps .. " imposters.")
	elseif cmd == "!stop" and args[2] == "game" then
		state.Mode = nil
		state.GlobalFreeze = false
		for _, n in ipairs(getNPCs()) do
			local hl = n:FindFirstChild("AUHighlight")
			if hl then hl:Destroy() end
		end
		notify("Game", "Stopped special modes.")
	elseif cmd == "!build" then
		state.BuildMode = true
		local tool = Instance.new("Tool")
		tool.Name = "Build"
		tool.RequiresHandle = false
		tool.Parent = LocalPlayer:WaitForChild("Backpack")
		local toolConn; toolConn = tool.Activated:Connect(function()
			local mouse = LocalPlayer:GetMouse()
			local target = mouse.Target
			if target and state.BuildSelected then
				if state.BuildSelected == "Vent" then table.insert(state.AUVents, target); target.Color = Color3.fromRGB(10, 10, 10)
				elseif state.BuildSelected == "Cafeteria" then table.insert(state.AUCafs, target); target.Color = Color3.fromRGB(139, 69, 19)
				elseif state.BuildSelected == "Task" then table.insert(state.AUTasks, target); target.Color = Color3.fromRGB(173, 216, 230) end
				notify("Build", "Assigned " .. state.BuildSelected .. " to " .. target.Name)
			end
		end)
		local bGui = Instance.new("ScreenGui")
		bGui.Name = "BuildGui"
		bGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
		local bFrame = Instance.new("Frame")
		bFrame.Size = UDim2.new(0, 150, 0, 150); bFrame.Position = UDim2.new(0, 50, 0.5, -75); bFrame.Parent = bGui
		local function makeBtn(name, y, mode)
			local b = Instance.new("TextButton")
			b.Size = UDim2.new(1, 0, 0, 40); b.Position = UDim2.new(0, 0, 0, y); b.Text = name; b.Parent = bFrame
			b.MouseButton1Click:Connect(function() state.BuildSelected = mode; notify("Build", "Selected " .. mode) end)
		end
		makeBtn("Vent (Black)", 0, "Vent"); makeBtn("Cafeteria (Brown)", 50, "Cafeteria"); makeBtn("Task (Blue)", 100, "Task")
		tool.Unequipped:Connect(function() bGui.Enabled = false end)
		tool.Equipped:Connect(function() bGui.Enabled = true end)
		notify("Build", "Build tool given.")
	elseif cmd == "!unfreeze" then
		state.GlobalFreeze = false
		notify("Global Freeze", "All NPCs unfrozen")
	elseif cmd == "self" and args[2] == "defense" then
		state.SelfDefense = not state.SelfDefense
		notify("Self Defense", state.SelfDefense and "ON" or "OFF")
	elseif cmd == "orbit" and args[2] == "speed" and args[3] then
		state.OrbitSpeed = tonumber(args[3]) or 1
		notify("Orbit Speed", "Set to " .. state.OrbitSpeed)
	elseif cmd == "nanfling" and args[2] then
		local target = getPlayer(table.concat(args, " ", 2))
		if target then
			state.Mode = "NanFling"
			state.NanFlingTarget = target
			notify("NanFling", "Targeting " .. target.Name)
		end
	elseif cmd == "fling" and args[2] then
		local target = getPlayer(table.concat(args, " ", 2))
		if target then
			state.Mode = "Fling"
			state.CurrentTarget = target
			notify("Fling", "Targeting " .. target.Name)
		end
	elseif cmd == "pathfind" and args[2] then
		local target = getPlayer(table.concat(args, " ", 2))
		if target then
			state.Mode = "Pathfind"
			state.PathfindTarget = target
		end
	elseif cmd == "follow" and args[2] == "me" and args[3] then
		state.Mode = "Mimic"
		state.Follow = false
		if args[3] == "all" then
			state.MimicNPCs = {}
			for _, npc in ipairs(getNPCs()) do
				state.MimicNPCs[npc] = true
			end
		else
			local npcId = tonumber(args[3])
			if npcId then
				local npc = getNPCById(npcId)
				if npc then state.MimicNPCs[npc] = true end
			end
		end
	elseif cmd == "attack" and args[2] then
		local target = getPlayer(table.concat(args, " ", 2))
		if target and target.Character then
			state.CurrentTarget = target
			state.Mode = "Attack"
			state.Follow = false
			state.CommandIssuer = player
			if player == LocalPlayer then btnFollow.Text = "Follow Me: OFF" end
		end
	elseif cmd == "look" and args[2] == "at" and args[3] then
		local target = getPlayer(table.concat(args, " ", 3))
		if target then
			state.CurrentTargetName = table.concat(args, " ", 3)
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
		state.CurrentTargetName = table.concat(args, " ", 2)
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
	pcall(function()
		if LocalPlayer then
			local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
			if myRoot then
				local vel = myRoot.AssemblyLinearVelocity
				if vel.Magnitude > 250 then
					myRoot.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
					myRoot.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
				end
			end
		end
	end)

	local npcs = getNPCs()
	local ownedNpcs = {}

	for _, npc in ipairs(npcs) do
		local hrp = npc:FindFirstChild("HumanoidRootPart")
		local hum = npc:FindFirstChild("Humanoid")

		if hrp then
			local isOwned = isConnected(npc)

			local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
			local inRange = true
			if myRoot and state.NetworkRange ~= math.huge then
				inRange = (hrp.Position - myRoot.Position).Magnitude <= state.NetworkRange
			end

			if inRange and (isOwned or state.AutoConnect) then
				hrp.Anchored = false
				pcall(function()
					local vel = hrp.AssemblyLinearVelocity
					if vel.Magnitude < 0.1 then
						hrp.AssemblyLinearVelocity = vel + Vector3.new(0, 0.001, 0)
					end
				end)

				enforceServerOwnership(hrp)

				if isOwned then
					table.insert(ownedNpcs, npc)
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
		local myRoot = LocalPlayer and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
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

	
	-- Handle Possession
	if state.PossessedNPC and state.PossessedNPC.Parent and state.PossessedNPC:FindFirstChild("Humanoid") then
		local myChar = LocalPlayer.Character
		local myHum = myChar and myChar:FindFirstChild("Humanoid")
		if myHum and workspace.CurrentCamera then
			myHum.WalkSpeed = 0
			myHum.JumpPower = 0
			workspace.CurrentCamera.CameraSubject = state.PossessedNPC.Humanoid
			state.PossessedNPC.Humanoid:Move(myHum.MoveDirection, false)
			state.PossessedNPC.Humanoid.Jump = myHum.Jump
		end
	else
		if not state.PossessedNPC and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
			local myHum = LocalPlayer.Character.Humanoid
			if myHum.WalkSpeed == 0 then
				myHum.WalkSpeed = 16
				myHum.JumpPower = 50
			end
		end
	end

	-- Handle Gojo Animations
	local t = tick()
	if state.BlueNPC and state.BlueNPC.Parent then
		local hrp = state.BlueNPC:FindFirstChild("HumanoidRootPart")
		local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
		if hrp and myRoot then
			state.BlueNPC.Humanoid.PlatformStand = true
			if state.PurplePhase == 0 then
				local targetPos = myRoot.CFrame * CFrame.new(-5, 3, -4)
				hrp.CFrame = hrp.CFrame:Lerp(targetPos * CFrame.Angles(0, t * 5, 0), 0.1)
				hrp.Velocity = Vector3.zero
			end
		end
	end
	if state.RedNPC and state.RedNPC.Parent then
		local hrp = state.RedNPC:FindFirstChild("HumanoidRootPart")
		local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
		if hrp and myRoot then
			state.RedNPC.Humanoid.PlatformStand = true
			if state.PurplePhase == 0 then
				local targetPos = myRoot.CFrame * CFrame.new(5, 3, -4)
				hrp.CFrame = hrp.CFrame:Lerp(targetPos * CFrame.Angles(0, t * 200, 0), 0.1)
				hrp.Velocity = Vector3.zero
			end
		end
	end
	if state.PurplePhase == 1 and state.BlueNPC and state.RedNPC then
		local bRoot = state.BlueNPC:FindFirstChild("HumanoidRootPart")
		local rRoot = state.RedNPC:FindFirstChild("HumanoidRootPart")
		local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
		if bRoot and rRoot and myRoot then
			local targetPos = myRoot.CFrame * CFrame.new(0, 4, -6)
			bRoot.CFrame = bRoot.CFrame:Lerp(targetPos * CFrame.Angles(0, t * 500, 0), 0.05)
			rRoot.CFrame = rRoot.CFrame:Lerp(targetPos * CFrame.Angles(0, t * 500, 0), 0.05)
			if tick() - state.PurpleTick > 3 then
				state.PurplePhase = 2
				state.PurpleStartCFrame = myRoot.CFrame
				state.PurpleTick = tick()
			end
		end
	elseif state.PurplePhase == 2 and state.BlueNPC and state.RedNPC then
		local bRoot = state.BlueNPC:FindFirstChild("HumanoidRootPart")
		local rRoot = state.RedNPC:FindFirstChild("HumanoidRootPart")
		if bRoot and rRoot and state.PurpleStartCFrame then
			local elapsed = (tick() - state.PurpleTick) * 200
			local targetCFrame = state.PurpleStartCFrame * CFrame.new(0, 4, -6 - elapsed)
			bRoot.CFrame = targetCFrame * CFrame.Angles(0, t * 500, 0)
			rRoot.CFrame = targetCFrame * CFrame.Angles(0, t * 500, 0)
			if elapsed > 400 then
				state.PurplePhase = 0
				state.BlueNPC = nil
				state.RedNPC = nil
			end
		end
	end

	-- Handle Possession
	if state.PossessedNPC and state.PossessedNPC.Parent and state.PossessedNPC:FindFirstChild("Humanoid") then
		local myChar = LocalPlayer.Character
		local myHum = myChar and myChar:FindFirstChild("Humanoid")
		if myHum and workspace.CurrentCamera then
			myHum.WalkSpeed = 0
			myHum.JumpPower = 0
			workspace.CurrentCamera.CameraSubject = state.PossessedNPC.Humanoid
			state.PossessedNPC.Humanoid:Move(myHum.MoveDirection, false)
			state.PossessedNPC.Humanoid.Jump = myHum.Jump
		end
	else
		if not state.PossessedNPC and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
			local myHum = LocalPlayer.Character.Humanoid
			if myHum.WalkSpeed == 0 then
				myHum.WalkSpeed = 16
				myHum.JumpPower = 50
			end
		end
	end

	-- Handle Gojo Animations
	local t = tick()
	if state.BlueNPC and state.BlueNPC.Parent then
		local hrp = state.BlueNPC:FindFirstChild("HumanoidRootPart")
		local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
		if hrp and myRoot then
			state.BlueNPC.Humanoid.PlatformStand = true
			if state.PurplePhase == 0 then
				local targetPos = myRoot.CFrame * CFrame.new(-5, 3, -4)
				hrp.CFrame = hrp.CFrame:Lerp(targetPos * CFrame.Angles(0, t * 5, 0), 0.1)
				hrp.Velocity = Vector3.zero
			end
		end
	end
	if state.RedNPC and state.RedNPC.Parent then
		local hrp = state.RedNPC:FindFirstChild("HumanoidRootPart")
		local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
		if hrp and myRoot then
			state.RedNPC.Humanoid.PlatformStand = true
			if state.PurplePhase == 0 then
				local targetPos = myRoot.CFrame * CFrame.new(5, 3, -4)
				hrp.CFrame = hrp.CFrame:Lerp(targetPos * CFrame.Angles(0, t * 200, 0), 0.1)
				hrp.Velocity = Vector3.zero
			end
		end
	end
	if state.PurplePhase == 1 and state.BlueNPC and state.RedNPC then
		local bRoot = state.BlueNPC:FindFirstChild("HumanoidRootPart")
		local rRoot = state.RedNPC:FindFirstChild("HumanoidRootPart")
		local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
		if bRoot and rRoot and myRoot then
			local targetPos = myRoot.CFrame * CFrame.new(0, 4, -6)
			bRoot.CFrame = bRoot.CFrame:Lerp(targetPos * CFrame.Angles(0, t * 500, 0), 0.05)
			rRoot.CFrame = rRoot.CFrame:Lerp(targetPos * CFrame.Angles(0, t * 500, 0), 0.05)
			if tick() - state.PurpleTick > 3 then
				state.PurplePhase = 2
				state.PurpleStartCFrame = myRoot.CFrame
				state.PurpleTick = tick()
			end
		end
	elseif state.PurplePhase == 2 and state.BlueNPC and state.RedNPC then
		local bRoot = state.BlueNPC:FindFirstChild("HumanoidRootPart")
		local rRoot = state.RedNPC:FindFirstChild("HumanoidRootPart")
		if bRoot and rRoot and state.PurpleStartCFrame then
			local elapsed = (tick() - state.PurpleTick) * 200
			local targetCFrame = state.PurpleStartCFrame * CFrame.new(0, 4, -6 - elapsed)
			bRoot.CFrame = targetCFrame * CFrame.Angles(0, t * 500, 0)
			rRoot.CFrame = targetCFrame * CFrame.Angles(0, t * 500, 0)
			if elapsed > 400 then
				state.PurplePhase = 0
				state.BlueNPC = nil
				state.RedNPC = nil
			end
		end
	end

	-- Global Overrides (!attack and !freeze)
	if state.GlobalFreeze or state.GlobalAttackTarget then
		local allNPCs = getNPCs()
		local gTargetRoot = state.GlobalAttackTarget and state.GlobalAttackTarget.Character and state.GlobalAttackTarget.Character:FindFirstChild("HumanoidRootPart")
		
		for _, npc in ipairs(allNPCs) do
			local hrp = npc:FindFirstChild("HumanoidRootPart")
			local hum = npc:FindFirstChild("Humanoid")
			if hrp and hum and hum.Health > 0 and not state.IsOverridden[npc] then
				if state.GlobalFreeze then
					hrp.Velocity = Vector3.new(0, 0, 0)
					hrp.RotVelocity = Vector3.new(0, 0, 0)
				elseif gTargetRoot then
					hum:MoveTo(gTargetRoot.Position)
					local objTarget = npc:FindFirstChild("Target") or npc:FindFirstChild("target")
					if objTarget and objTarget:IsA("ObjectValue") then
						objTarget.Value = state.GlobalAttackTarget.Character
					end
				end
			end
		end
	end

	-- Pre-process overrides (SpecificFollow, Roam, Mimic)
	state.IsOverridden = {}
	for _, npc in ipairs(ownedNpcs) do
		local overriden = false
		-- SpecificFollow
		local sTarget = state.SpecificFollow[npc]
		if sTarget and sTarget.Character then
			local tRoot = sTarget.Character:FindFirstChild("HumanoidRootPart")
			local hum = npc:FindFirstChild("Humanoid")
			if tRoot and hum then
				if (npc.HumanoidRootPart.Position - tRoot.Position).Magnitude > 3 then
					hum:MoveTo(tRoot.Position)
				end
				overriden = true
			end
		end
		-- Roaming
		local rPoints = state.RoamPoints[npc]
		if not overriden and rPoints and #rPoints > 0 then
			local hrp = npc:FindFirstChild("HumanoidRootPart")
			local hum = npc:FindFirstChild("Humanoid")
			if hrp and hum then
				local idx = state.CurrentRoamIndex[npc] or 1
				local tPos = rPoints[idx]
				if (hrp.Position - tPos).Magnitude < 3 then
					state.CurrentRoamIndex[npc] = (idx % #rPoints) + 1
				else
					hum:MoveTo(tPos)
				end
				overriden = true
			end
		end
		state.IsOverridden[npc] = overriden or npc == state.BlueNPC or npc == state.RedNPC
	end

	local issuerChar = state.CommandIssuer and state.CommandIssuer.Character
	local issuerRoot = issuerChar and issuerChar:FindFirstChild("HumanoidRootPart")

	if state.Follow and issuerRoot then
		for _, npc in ipairs(ownedNpcs) do
			if state.IsOverridden[npc] then continue end
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
	elseif state.Mode == "UFO" and issuerRoot then
		local t = tick()
		for i, npc in ipairs(ownedNpcs) do
			if not state.StayingNPCs[npc] and not state.IsOverridden[npc] then
				local hrp = npc:FindFirstChild("HumanoidRootPart")
				local hum = npc:FindFirstChild("Humanoid")
				if hrp and hum then
					hum.PlatformStand = true
					local angle = (t * 2 * (state.OrbitSpeed or 1)) + (i * (math.pi * 2 / #ownedNpcs))
					local radius = 10
					local yOffset = math.sin(t * 3) * 5 + 10
					local targetPos = issuerRoot.Position + Vector3.new(math.cos(angle) * radius, yOffset, math.sin(angle) * radius)
					
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
					alignPos.Position = targetPos
					local mechaOri = hrp:FindFirstChild("MechaOri")
					if mechaOri then 
						mechaOri.CFrame = CFrame.new(hrp.Position, issuerRoot.Position)
					end
					hrp.Velocity = Vector3.zero
					hrp.RotVelocity = Vector3.zero
				end
			end
		end
	elseif state.Mode == "Mimic" and issuerRoot then
		local myHum = issuerChar:FindFirstChild("Humanoid")
		for i, npc in ipairs(ownedNpcs) do
			if state.MimicNPCs[npc] and not state.IsOverridden[npc] then
				local hrp = npc:FindFirstChild("HumanoidRootPart")
				local hum = npc:FindFirstChild("Humanoid")
				if hrp and hum and myHum then
					hum.Jump = myHum.Jump
					local dist = (hrp.Position - issuerRoot.Position).Magnitude
					if dist > 50 then
						hrp.CFrame = issuerRoot.CFrame * CFrame.new(math.random(-2,2), 0, math.random(-2,2))
					else
						hum:MoveTo(issuerRoot.Position)
					end
				end
			end
		end
	elseif state.Mode == "Star" and issuerRoot then
		local t_star = tick() * (state.OrbitSpeed or 1)
		for i, npc in ipairs(ownedNpcs) do
			if not state.StayingNPCs[npc] and not state.IsOverridden[npc] then
				local hrp = npc:FindFirstChild("HumanoidRootPart")
				local hum = npc:FindFirstChild("Humanoid")
				if hrp and hum then
					hum.PlatformStand = true
					-- Pentagon/Star angle offset
					local angle = t_star + (i * 4 * math.pi / #ownedNpcs)
					local radius = 15
					local targetPos = issuerRoot.Position + Vector3.new(math.cos(angle) * radius, 5, math.sin(angle) * radius)
					
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
					alignPos.Position = targetPos
					local mechaOri = hrp:FindFirstChild("MechaOri")
					if mechaOri then 
						mechaOri.CFrame = CFrame.new(hrp.Position, issuerRoot.Position)
					end
					hrp.Velocity = Vector3.zero
					hrp.RotVelocity = Vector3.zero
				end
			end
		end
	elseif state.Mode == "Star" and issuerRoot then
		local t_star = tick() * (state.OrbitSpeed or 1)
		for i, npc in ipairs(ownedNpcs) do
			if not state.StayingNPCs[npc] and not state.IsOverridden[npc] then
				local hrp = npc:FindFirstChild("HumanoidRootPart")
				local hum = npc:FindFirstChild("Humanoid")
				if hrp and hum then
					hum.PlatformStand = true
					-- Pentagon/Star angle offset
					local angle = t_star + (i * 4 * math.pi / #ownedNpcs)
					local radius = 15
					local targetPos = issuerRoot.Position + Vector3.new(math.cos(angle) * radius, 5, math.sin(angle) * radius)
					
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
					alignPos.Position = targetPos
					local mechaOri = hrp:FindFirstChild("MechaOri")
					if mechaOri then 
						mechaOri.CFrame = CFrame.new(hrp.Position, issuerRoot.Position)
					end
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
	elseif state.Mode == "WallOrbit" then
		local pChar = LocalPlayer.Character
		local pRoot = pChar and pChar:FindFirstChild("HumanoidRootPart")
		if pRoot then
			local count = math.min(#ownedNpcs, 4)
			for i=1, count do
				local npc = ownedNpcs[i]
				local hrp = npc:FindFirstChild("HumanoidRootPart")
				if hrp then
					local angle = (i - 1) * (math.pi / 2) + tick() * 2
					local targetCFrame = pRoot.CFrame * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, -10)
					hrp.CFrame = hrp.CFrame:Lerp(targetCFrame, 0.1)
					hrp.Velocity = Vector3.new(0,0,0)
					hrp.RotVelocity = Vector3.new(0,0,0)
				end
			end
		end
	elseif state.Mode == "Helicopter" then
		local pChar = LocalPlayer.Character
		local pRoot = pChar and pChar:FindFirstChild("HumanoidRootPart")
		if pRoot then
			local count = math.min(#ownedNpcs, 5)
			if count >= 1 then
				local baseHrp = ownedNpcs[1]:FindFirstChild("HumanoidRootPart")
				if baseHrp then
					local baseCF = pRoot.CFrame * CFrame.new(0, 15, 0)
					baseHrp.CFrame = baseHrp.CFrame:Lerp(baseCF, 0.2)
					baseHrp.Velocity = Vector3.new(0,0,0)
					for i=2, count do
						local bHrp = ownedNpcs[i]:FindFirstChild("HumanoidRootPart")
						if bHrp then
							local angle = (i - 2) * (math.pi * 2 / (count - 1)) + tick() * 10
							local bCF = baseCF * CFrame.new(0, 2, 0) * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, -8) * CFrame.Angles(math.pi/2, 0, 0)
							bHrp.CFrame = bHrp.CFrame:Lerp(bCF, 0.5)
							bHrp.Velocity = Vector3.new(0,0,0)
							bHrp.RotVelocity = Vector3.new(0,0,0)
						end
					end
				end
			end
		end
	elseif state.Mode == "Sphere" then
		local pChar = LocalPlayer.Character
		local pRoot = pChar and pChar:FindFirstChild("HumanoidRootPart")
		if pRoot then
			local count = #ownedNpcs
			local phi = math.pi * (3 - math.sqrt(5))
			for i, npc in ipairs(ownedNpcs) do
				local hrp = npc:FindFirstChild("HumanoidRootPart")
				if hrp then
					local y = 1 - (i / (count)) * 2
					local radius = math.sqrt(1 - y * y)
					local theta = phi * i + tick() * 2
					local x = math.cos(theta) * radius
					local z = math.sin(theta) * radius
					local offset = Vector3.new(x, y, z) * 15
					local targetCF = CFrame.new(pRoot.Position + offset, pRoot.Position)
					hrp.CFrame = hrp.CFrame:Lerp(targetCF, 0.1)
					hrp.Velocity = Vector3.new(0,0,0)
					hrp.RotVelocity = Vector3.new(0,0,0)
				end
			end
		end
	elseif state.Mode == "MurderMystery" then
		local killer = state.MMKiller
		if killer and killer:FindFirstChild("HumanoidRootPart") then
			local kHrp = killer:FindFirstChild("HumanoidRootPart")
			local kHum = killer:FindFirstChild("Humanoid")
			for npc, timeStart in pairs(state.MMFleeing) do
				if tick() - timeStart > 6 then
					state.MMFleeing[npc] = nil
				else
					local hrp = npc:FindFirstChild("HumanoidRootPart")
					local hum = npc:FindFirstChild("Humanoid")
					if hrp and hum then
						local dir = (hrp.Position - kHrp.Position).Unit
						smartMoveTo(hum, hrp.Position + dir * 30)
					end
				end
			end
			if state.MMChasing and state.MMChasing:FindFirstChild("HumanoidRootPart") and state.MMChasing:FindFirstChild("Humanoid").Health > 0 then
				smartMoveTo(kHum, state.MMChasing.HumanoidRootPart.Position)
				if (kHrp.Position - state.MMChasing.HumanoidRootPart.Position).Magnitude < 5 then
					state.MMChasing.HumanoidRootPart.CFrame = CFrame.new(0, -50000, 0)
					state.MMChasing.HumanoidRootPart.Velocity = Vector3.new(0,-1000,0)
					state.MMChasing = nil
				end
			else
				local bestTarget = nil
				local bestDist = math.huge
				for _, npc in ipairs(ownedNpcs) do
					if npc ~= killer and not state.MMFleeing[npc] then
						local hrp = npc:FindFirstChild("HumanoidRootPart")
						if hrp then
							local isIsolated = true
							for _, other in ipairs(ownedNpcs) do
								if other ~= npc and other ~= killer then
									local oHrp = other:FindFirstChild("HumanoidRootPart")
									if oHrp and (oHrp.Position - hrp.Position).Magnitude < 30 then
										isIsolated = false; break
									end
								end
							end
							if isIsolated then
								local d = (hrp.Position - kHrp.Position).Magnitude
								if d < bestDist then bestDist = d; bestTarget = npc end
							end
						end
					end
				end
				if bestTarget then
					smartMoveTo(kHum, bestTarget.HumanoidRootPart.Position)
					if bestDist < 5 then
						bestTarget.HumanoidRootPart.CFrame = CFrame.new(0, -50000, 0)
						bestTarget.HumanoidRootPart.Velocity = Vector3.new(0,-1000,0)
						for _, other in ipairs(ownedNpcs) do
							if other ~= killer and other ~= bestTarget then
								local oHrp = other:FindFirstChild("HumanoidRootPart")
								if oHrp and (oHrp.Position - kHrp.Position).Magnitude < 50 then
									state.MMFleeing[other] = tick()
									state.MMChasing = other
								end
							end
						end
					end
				else
					if tick() % 3 < 0.1 then
						smartMoveTo(kHum, kHrp.Position + Vector3.new(math.random(-30,30), 0, math.random(-30,30)))
					end
				end
			end
		end
	elseif state.Mode == "AmongUs" then
		if state.AUPhase == "Playing" then
			local imps = {}
			local crews = {}
			for _, npc in ipairs(ownedNpcs) do
				local role = state.AURoles[npc]
				if role == "Imposter" then table.insert(imps, npc)
				elseif role == "Crew" or role == "Engineer" then table.insert(crews, npc) end
				local hl = npc:FindFirstChild("AUHighlight")
				if not hl then
					hl = Instance.new("Highlight"); hl.Name = "AUHighlight"; hl.Parent = npc
				end
				if role == "Imposter" then hl.FillColor = Color3.fromRGB(255, 0, 0)
				elseif role == "Engineer" then hl.FillColor = Color3.fromRGB(255, 105, 180)
				else hl.FillColor = Color3.fromRGB(0, 0, 255) end
			end
			if tick() - state.AULastKill > 15 then
				for _, imp in ipairs(imps) do
					local iHrp = imp:FindFirstChild("HumanoidRootPart")
					local iHum = imp:FindFirstChild("Humanoid")
					if iHrp and iHum then
						local nearest = nil
						local nDist = math.huge
						for _, crew in ipairs(crews) do
							local cHrp = crew:FindFirstChild("HumanoidRootPart")
							if cHrp then
								local d = (cHrp.Position - iHrp.Position).Magnitude
								if d < nDist then nDist = d; nearest = crew end
							end
						end
						if nearest and nDist < 30 then
							smartMoveTo(iHum, nearest.HumanoidRootPart.Position)
							if nDist < 5 then
								local meetingTriggered = false
								for _, otherCrew in ipairs(crews) do
									if otherCrew ~= nearest then
										local ocHrp = otherCrew:FindFirstChild("HumanoidRootPart")
										if ocHrp and (ocHrp.Position - iHrp.Position).Magnitude < 6 then
											local ocHum = otherCrew:FindFirstChild("Humanoid")
											if ocHum then ocHum.Jump = true end
											meetingTriggered = true
										end
									end
								end
								nearest.HumanoidRootPart.CFrame = CFrame.new(0, -50000, 0)
								nearest.HumanoidRootPart.Velocity = Vector3.new(0,-1000,0)
								state.AULastKill = tick()
								if meetingTriggered then
									state.AUPhase = "Meeting"
									state.AUMeetingStart = tick()
								end
							end
						else
							if math.random() < 0.05 and #state.AUVents > 0 then
								iHrp.CFrame = state.AUVents[math.random(1, #state.AUVents)].CFrame + Vector3.new(0, 5, 0)
							end
						end
					end
				end
			end
			for _, crew in ipairs(crews) do
				local cHrp = crew:FindFirstChild("HumanoidRootPart")
				local cHum = crew:FindFirstChild("Humanoid")
				if cHrp and cHum then
					if not state.AUTaskCooldowns then state.AUTaskCooldowns = {} end
					if not state.AUTaskCooldowns[crew] or tick() - state.AUTaskCooldowns[crew] > 6 then
						state.AUTaskCooldowns[crew] = tick()
						if #state.AUTasks > 0 then
							smartMoveTo(cHum, state.AUTasks[math.random(1, #state.AUTasks)].Position)
						else
							smartMoveTo(cHum, cHrp.Position + Vector3.new(math.random(-20,20), 0, math.random(-20,20)))
						end
					end
				end
			end
		elseif state.AUPhase == "Meeting" then
			local mtgPart = (#state.AUCafs > 0) and state.AUCafs[1] or nil
			for _, npc in ipairs(ownedNpcs) do
				local hrp = npc:FindFirstChild("HumanoidRootPart")
				if hrp then
					if mtgPart then hrp.CFrame = mtgPart.CFrame + Vector3.new(math.random(-5,5), 5, math.random(-5,5)) end
					hrp.Velocity = Vector3.new(0,0,0)
					hrp.RotVelocity = Vector3.new(0,0,0)
				end
			end
			if tick() - state.AUMeetingStart > 10 then
				local victim = ownedNpcs[math.random(1, #ownedNpcs)]
				if victim and victim:FindFirstChild("HumanoidRootPart") then
					victim.HumanoidRootPart.CFrame = CFrame.new(0, -50000, 0)
					victim.HumanoidRootPart.Velocity = Vector3.new(0,-1000,0)
				end
				state.AUPhase = "Playing"
				state.AULastKill = tick()
			end
		end
	elseif state.Mode == "KillNPC" and state.KillTargetNPC then
		local targetRoot = state.KillTargetNPC:FindFirstChild("HumanoidRootPart")
		local targetHum = state.KillTargetNPC:FindFirstChild("Humanoid")
		if targetRoot and targetHum and targetHum.Health > 0 then
			local com = Vector3.new(0,0,0)
			local acount = 0
			for _, npc in ipairs(ownedNpcs) do
				if npc ~= state.KillTargetNPC and not state.StayingNPCs[npc] then
					local hrp = npc:FindFirstChild("HumanoidRootPart")
					if hrp then com = com + hrp.Position; acount = acount + 1 end
				end
			end
			if acount > 0 then
				com = com / acount
				local runDir = (targetRoot.Position - com).Unit
				smartMoveTo(targetHum, targetRoot.Position + runDir * 40)
			end
			for _, npc in ipairs(ownedNpcs) do
				if npc ~= state.KillTargetNPC and not state.StayingNPCs[npc] then
					local hum = npc:FindFirstChild("Humanoid")
					local hrp = npc:FindFirstChild("HumanoidRootPart")
					if hum and hrp then
						smartMoveTo(hum, targetRoot.Position)
						if (hrp.Position - targetRoot.Position).Magnitude < 5 then
							targetRoot.CFrame = CFrame.new(0, -50000, 0)
							targetRoot.Velocity = Vector3.new(0, -1000, 0)
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
	elseif state.Mode ~= "Drag" and state.Mode ~= "StackUp" and state.Mode ~= "Mecha" and state.Mode ~= "Stairs" and state.Mode ~= "Wall" and state.Mode ~= "Find" and state.Mode ~= "UFO" and state.Mode ~= "NanFling" and state.Mode ~= "Star" then
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

	
	-- Self Defense & Fling Logic
	for _, npc in ipairs(ownedNpcs) do
		local hrp = npc:FindFirstChild("HumanoidRootPart")
		if hrp then
			local isFlingMode = (state.Mode == "Fling")
			local shouldFling = state.SelfDefense or isFlingMode
			
			if shouldFling then
				-- We apply fling velocity directly inside heartbeat to ensure physics replication
				local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
				for _, p in ipairs(Players:GetPlayers()) do
					if p ~= LocalPlayer and p.Character then
						local tRoot = p.Character:FindFirstChild("HumanoidRootPart")
						local hum = p.Character:FindFirstChild("Humanoid")
						if tRoot and hum and hum.Health > 0 then
							if (hrp.Position - tRoot.Position).Magnitude < 4 then
								-- Fling them
								hrp.Velocity = Vector3.new(0, 15000, 0)
								hrp.RotVelocity = Vector3.new(15000, 15000, 15000)
							end
						end
					end
				end
			end
		end
	end

	-- NanFling Mode
	if state.Mode == "NanFling" and state.NanFlingTarget and state.NanFlingTarget.Character then
		local tRoot = state.NanFlingTarget.Character:FindFirstChild("HumanoidRootPart")
		if tRoot then
			for _, npc in ipairs(ownedNpcs) do
				local hrp = npc:FindFirstChild("HumanoidRootPart")
				if hrp then
					hrp.CanCollide = false
					hrp.CFrame = tRoot.CFrame
					hrp.Velocity = Vector3.new(0/0, 0/0, 0/0) -- NaN velocity forces extreme physics recalculation / fling
					hrp.RotVelocity = Vector3.new(9e9, 9e9, 9e9)
				end
			end
		end
	end

	if state.Mode == "Attack" and state.CurrentTarget and state.CurrentTarget.Character then
			targetRoot = state.CurrentTarget.Character:FindFirstChild("HumanoidRootPart")
		elseif state.Mode == "Pathfind" and state.PathfindTarget and state.PathfindTarget.Character then
			targetRoot = state.PathfindTarget.Character:FindFirstChild("HumanoidRootPart")
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

local UserInputService = game:GetService("UserInputService")

local function makeDraggable(frame)
	local dragging
	local dragInput
	local dragStart
	local startPos

	local function update(input)
		local delta = input.Position - dragStart
		frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
	end

	frame.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = frame.Position

			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
				end
			end)
		end
	end)

	frame.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			dragInput = input
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if input == dragInput and dragging then
			update(input)
		end
	end)
end

makeDraggable(MainFrame)
makeDraggable(BubbleFrame)

local PathfindingService = game:GetService("PathfindingService")

task.spawn(function()
	while task.wait(0.5) do
		if not state.AutoConnect then continue end
		local npcs = getNPCs()
		local targetRoot = nil

		if state.Mode == "Attack" and state.CurrentTarget and state.CurrentTarget.Character then
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
