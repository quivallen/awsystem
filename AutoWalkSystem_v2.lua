-- AutoWalkSystem_v2.lua (robust)
-- Self-contained LocalScript for StarterPlayer > StarterPlayerScripts
-- Adds better diagnostics, safer table clearing, and HRP checks.
-- Keys: F = Record/Stop, P = Play (Local), L = Clear

-- ===== Services =====
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
if not player then
	warn("[AutoWalk v2] LocalPlayer missing. Ensure this is a *LocalScript* in StarterPlayerScripts.")
	return
end

-- ===== Config =====
local SAMPLE_RATE_HZ = 60
local GHOST_TRANSPARENCY = 0.35
local GHOST_COLOR = Color3.fromRGB(180, 230, 255)

-- ===== State =====
local isRecording = false
local isPlayingLocal = false
local timeline = {}           -- { {t, cf}, ... }
local recConn : RBXScriptConnection? = nil
local recStart = 0
local playStart = 0
local playIndex = 1
local ghostModel : Model? = nil
local lastSampleTime = 0

-- ===== Utils =====
local function tclear(t)
	if table.clear then
		table.clear(t)
	else
		for k in pairs(t) do t[k] = nil end
	end
end

local function getCharacter()
	local ch = player.Character or player.CharacterAdded:Wait()
	-- Ensure HRP exists
	if not ch:FindFirstChild("HumanoidRootPart") then
		ch:WaitForChild("HumanoidRootPart")
	end
	return ch
end

local function stripScripts(model: Instance)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		end
	end
end

local function anchorGhost(model: Instance)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d:SetNetworkOwnershipAuto()
			d.Transparency = math.clamp(GHOST_TRANSPARENCY,0,1)
			d.Color = GHOST_COLOR
		end
	end
end

local function destroyGhost()
	if ghostModel and ghostModel.Parent then
		ghostModel:Destroy()
	end
	ghostModel = nil
end

local function makeGhostFromCharacter(character: Model)
	destroyGhost()
	local clone = character:Clone()
	stripScripts(clone)
	local hum = clone:FindFirstChildOfClass("Humanoid")
	if hum then hum:Destroy() end
	anchorGhost(clone)
	local hrp = clone:FindFirstChild("HumanoidRootPart")
	if hrp then clone.PrimaryPart = hrp end
	clone.Name = "PlaybackGhost_" .. player.Name
	clone.Parent = workspace
	ghostModel = clone
	return clone
end

local function info(msg)
	print("[AutoWalk v2] " .. tostring(msg))
	if script:FindFirstChild("StatusBinder") then
		script.StatusBinder.Value = msg
	end
end

-- ===== Recording =====
local function startRecording()
	if isPlayingLocal then info("Stop playback first."); return end

	local character = getCharacter()
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		warn("[AutoWalk v2] HumanoidRootPart not found.")
		return
	end

	tclear(timeline)
	playIndex = 1
	recStart = time()
	lastSampleTime = recStart
	isRecording = true
	info("Recording started.")

	if recConn then recConn:Disconnect(); recConn = nil end
	recConn = RunService.Heartbeat:Connect(function()
		if not isRecording then return end
		local now = time()
		if now - lastSampleTime >= (1 / SAMPLE_RATE_HZ) then
			table.insert(timeline, { t = now - recStart, cf = hrp.CFrame })
			lastSampleTime = now
		end
	end)
end

local function stopRecording()
	if not isRecording then return end
	isRecording = false
	if recConn then recConn:Disconnect(); recConn = nil end
	if #timeline < 2 then
		info("Recording too short (no movement sampled).")
		tclear(timeline)
		return
	end
	info(("Recording stopped. %d keys / %.2fs"):format(#timeline, timeline[#timeline].t))
end

-- ===== Local Playback =====
local function playLocal()
	if isRecording then info("Stop recording first."); return end
	if isPlayingLocal then info("Already playing."); return end
	if #timeline < 2 then info("No recording to play."); return end

	local character = getCharacter()
	local ghost = makeGhostFromCharacter(character)
	local hrp = ghost.PrimaryPart
	if not hrp then info("Ghost HRP missing."); destroyGhost(); return end

	ghost:PivotTo(timeline[1].cf)
	isPlayingLocal = true
	playStart = time()
	playIndex = 1
	info("Local playback started.")

	local conn
	conn = RunService.Heartbeat:Connect(function()
		if not isPlayingLocal then conn:Disconnect(); return end
		local elapsed = time() - playStart
		if elapsed >= timeline[#timeline].t then
			ghost:PivotTo(timeline[#timeline].cf)
			isPlayingLocal = false
			info("Local playback finished.")
			return
		end

		while playIndex < #timeline and timeline[playIndex + 1].t < elapsed do
			playIndex += 1
		end

        -- Safety for out-of-range
		playIndex = math.clamp(playIndex, 1, math.max(1, #timeline - 1))
		local a = timeline[playIndex]
		local b = timeline[playIndex + 1]
		if not b then ghost:PivotTo(a.cf); return end

		local dur = math.max(1e-6, b.t - a.t)
		local alpha = (elapsed - a.t) / dur
		local cf = a.cf:Lerp(b.cf, alpha)
		ghost:PivotTo(cf)
	end)
end

local function clearRecording()
	if isRecording then stopRecording() end
	isPlayingLocal = false
	tclear(timeline)
	playIndex = 1
	destroyGhost()
	info("Cleared.")
end

-- ===== Simple "Auto Walk System" GUI =====
local StatusBinder = Instance.new("StringValue")
StatusBinder.Name = "StatusBinder"
StatusBinder.Parent = script
StatusBinder.Value = ""

local playerGui = player:WaitForChild("PlayerGui")
local gui = Instance.new("ScreenGui")
gui.Name = "AutoWalkSystem"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local frame = Instance.new("Frame")
frame.Name = "Main"
frame.Size = UDim2.new(0, 320, 0, 380)
frame.Position = UDim2.new(0, 16, 0.25, 0)
frame.BackgroundColor3 = Color3.fromRGB(24,24,24)
frame.BorderSizePixel = 0
frame.Parent = gui
local uic = Instance.new("UICorner", frame); uic.CornerRadius = UDim.new(0,8)

local top = Instance.new("Frame", frame)
top.Size = UDim2.new(1,0,0,36)
top.BackgroundColor3 = Color3.fromRGB(18,18,18)
local topCorner = Instance.new("UICorner", top); topCorner.CornerRadius = UDim.new(0,8)

local title = Instance.new("TextLabel", top)
title.Size = UDim2.new(1,-40,1,0)
title.Position = UDim2.new(0,8,0,0)
title.BackgroundTransparency = 1
title.Text = "Auto Walk System"
title.TextSize = 18
title.TextColor3 = Color3.fromRGB(240,240,240)
title.Font = Enum.Font.GothamBold
title.TextXAlignment = Enum.TextXAlignment.Left

local closeBtn = Instance.new("TextButton", top)
closeBtn.Size = UDim2.new(0,28,0,28)
closeBtn.Position = UDim2.new(1,-36,0,4)
closeBtn.Text = "X"
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 14
closeBtn.TextColor3 = Color3.fromRGB(240,240,240)
closeBtn.BackgroundColor3 = Color3.fromRGB(80,20,20)
local cbCorner = Instance.new("UICorner", closeBtn); cbCorner.CornerRadius = UDim.new(0,6)
closeBtn.MouseButton1Click:Connect(function() gui.Enabled = false end)

local content = Instance.new("Frame", frame)
content.Size = UDim2.new(1,-16,1,-56)
content.Position = UDim2.new(0,8,0,44)
content.BackgroundTransparency = 1

local function mkLabel(text, parent, sizeY)
	local l = Instance.new("TextLabel", parent)
	l.Size = UDim2.new(1,0,0,sizeY or 20)
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextColor3 = Color3.fromRGB(220,220,220)
	l.Font = Enum.Font.Gotham
	l.TextSize = 14
	l.TextXAlignment = Enum.TextXAlignment.Left
	return l
end
local function mkButton(text, parent, color)
	local b = Instance.new("TextButton", parent)
	b.Size = UDim2.new(1,0,0,36)
	b.BackgroundColor3 = color or Color3.fromRGB(60,60,60)
	b.Text = text
	b.Font = Enum.Font.GothamSemibold
	b.TextSize = 15
	b.TextColor3 = Color3.fromRGB(240,240,240)
	local c = Instance.new("UICorner", b); c.CornerRadius = UDim.new(0,6)
	return b
end

-- Record row
local recRow = Instance.new("Frame", content)
recRow.Size = UDim2.new(1,0,0,34)
recRow.BackgroundTransparency = 1
local recIndicator = Instance.new("Frame", recRow)
recIndicator.Size = UDim2.new(0,18,0,18)
recIndicator.Position = UDim2.new(0,6,0,8)
recIndicator.BackgroundColor3 = Color3.fromRGB(160,160,160)
recIndicator.BorderSizePixel = 0
local recLabel = Instance.new("TextLabel", recRow)
recLabel.Size = UDim2.new(1, -30, 1, 0)
recLabel.Position = UDim2.new(0,32,0,0)
recLabel.BackgroundTransparency = 1
recLabel.TextXAlignment = Enum.TextXAlignment.Left
recLabel.Text = "Record: OFF (Press F)"
recLabel.TextColor3 = Color3.fromRGB(200,200,200)
recLabel.Font = Enum.Font.Gotham
recLabel.TextSize = 14

local function toggleRecord()
	if isRecording then
		stopRecording()
		isRecording = false
		recIndicator.BackgroundColor3 = Color3.fromRGB(160,160,160)
		recLabel.Text = "Record: OFF (Press F)"
	else
		startRecording()
		isRecording = true
		recIndicator.BackgroundColor3 = Color3.fromRGB(220,60,60)
		recLabel.Text = "Record: ON (Press F)"
	end
end

-- Big button
local bigBtn = mkButton("STOP WALK", content, Color3.fromRGB(200,40,40))
bigBtn.Position = UDim2.new(0,0,0,46)

-- Save / Refresh row (local-only list)
local saveRow = Instance.new("Frame", content)
saveRow.Size = UDim2.new(1,0,0,40)
saveRow.Position = UDim2.new(0,0,0,96)
saveRow.BackgroundTransparency = 1

local nameBox = Instance.new("TextBox", saveRow)
nameBox.Size = UDim2.new(1, -110, 0, 34)
nameBox.Position = UDim2.new(0,6,0,0)
nameBox.PlaceholderText = "checkpoint name..."
nameBox.Text = "checkpoint_1"
nameBox.ClearTextOnFocus = false
nameBox.BackgroundColor3 = Color3.fromRGB(40,40,40)
nameBox.Font = Enum.Font.Gotham
nameBox.TextSize = 14
local nbCorner = Instance.new("UICorner", nameBox); nbCorner.CornerRadius = UDim.new(0,6)

local saveBtn = Instance.new("TextButton", saveRow)
saveBtn.Size = UDim2.new(0, 54, 0, 34)
saveBtn.Position = UDim2.new(1, -98, 0, 0)
saveBtn.BackgroundColor3 = Color3.fromRGB(30,140,40)
saveBtn.Text = "Save"
saveBtn.Font = Enum.Font.GothamSemibold
saveBtn.TextSize = 14
saveBtn.TextColor3 = Color3.fromRGB(240,240,240)
local sCorner = Instance.new("UICorner", saveBtn); sCorner.CornerRadius = UDim.new(0,6)

local refreshBtn = Instance.new("TextButton", saveRow)
refreshBtn.Size = UDim2.new(0, 54, 0, 34)
refreshBtn.Position = UDim2.new(1, -38, 0, 0)
refreshBtn.BackgroundColor3 = Color3.fromRGB(36,120,220)
refreshBtn.Text = "Refresh"
refreshBtn.Font = Enum.Font.GothamSemibold
refreshBtn.TextSize = 14
refreshBtn.TextColor3 = Color3.fromRGB(240,240,240)
local rCorner = Instance.new("UICorner", refreshBtn); rCorner.CornerRadius = UDim.new(0,6)

local savedLabel = mkLabel("Saved Checkpoints", content, 20)
savedLabel.Position = UDim2.new(0,0,0,146)

local scroll = Instance.new("ScrollingFrame", content)
scroll.Size = UDim2.new(1,0,0,140)
scroll.Position = UDim2.new(0,0,0,170)
scroll.CanvasSize = UDim2.new(0,0)
scroll.ScrollBarThickness = 6
scroll.BackgroundTransparency = 1
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y

local savedListLayout = Instance.new("UIListLayout", scroll)
savedListLayout.Padding = UDim.new(0,6)
savedListLayout.SortOrder = Enum.SortOrder.LayoutOrder
local savedItems = {}

local function rebuildSavedList()
	for _, v in ipairs(scroll:GetChildren()) do
		if v:IsA("Frame") or v:IsA("TextButton") then v:Destroy() end
	end
	for i, name in ipairs(savedItems) do
		local row = Instance.new("Frame", scroll)
		row.Size = UDim2.new(1, -12, 0, 26)
		row.BackgroundTransparency = 1
		local btn = Instance.new("TextButton", row)
		btn.Size = UDim2.new(1,0,1,0)
		btn.BackgroundColor3 = Color3.fromRGB(40,40,40)
		btn.Text = "  "..tostring(name)
		btn.Font = Enum.Font.Gotham
		btn.TextSize = 14
		btn.TextXAlignment = Enum.TextXAlignment.Left
		local corner = Instance.new("UICorner", btn); corner.CornerRadius = UDim.new(0,6)
		btn.MouseButton1Click:Connect(function()
			info("Selected checkpoint: "..tostring(name).." (simple local list only)")
		end)
		local del = Instance.new("TextButton", row)
		del.Size = UDim2.new(0,24,0,24)
		del.Position = UDim2.new(1,-28,0,1)
		del.Text = "✕"
		del.Font = Enum.Font.Gotham
		del.TextSize = 12
		del.BackgroundColor3 = Color3.fromRGB(120,30,30)
		local dcorner = Instance.new("UICorner", del); dcorner.CornerRadius = UDim.new(0,6)
		del.MouseButton1Click:Connect(function()
			table.remove(savedItems, i)
			rebuildSavedList()
		end)
	end
	task.defer(function()
		scroll.CanvasSize = UDim2.new(0,0,0, (#savedItems * 32) )
	end)
end

-- Button behavior
bigBtn.MouseButton1Click:Connect(function()
	playLocal()
end)

saveBtn.MouseButton1Click:Connect(function()
	local name = tostring(nameBox.Text ~= "" and nameBox.Text or "checkpoint")
	local found = false
	for _, v in ipairs(savedItems) do if v == name then found = true end end
	if not found then table.insert(savedItems, 1, name) end
	rebuildSavedList()
	info("Saved checkpoint name locally: "..name.." (no DataStore in this .lua)")
end)

refreshBtn.MouseButton1Click:Connect(function()
	rebuildSavedList()
	info("Refreshed checkpoints.")
end)

-- Keyboard: F toggle record, P play, L clear
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.F then
		toggleRecord()
	elseif input.KeyCode == Enum.KeyCode.P then
		playLocal()
	elseif input.KeyCode == Enum.KeyCode.L then
		clearRecording()
	end
end)

-- Show status on GUI
local statusLabel = mkLabel("Ready", content, 20)
statusLabel.Position = UDim2.new(0,0,0,320)
StatusBinder.Changed:Connect(function()
	statusLabel.Text = StatusBinder.Value
end)

-- optional draggable panel
do
	local dragging, dragStart, startPos
	frame.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true
			dragStart = input.Position
			startPos = frame.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then dragging = false end
			end)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
			local delta = input.Position - dragStart
			frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
		end
	end)
end

info("Auto Walk System v2 ready. F=Record, P=Play, L=Clear.")
