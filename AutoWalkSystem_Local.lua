-- AutoWalkSystem_Local.lua
-- Single-file LocalScript (LOCAL-ONLY): record, save/load (in memory), and playback.
-- Place into: StarterPlayer > StarterPlayerScripts > LocalScript
-- Keys: F = Record/Stop, P = Play, L = Clear

-- ========== Services ==========
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
if not player then
	warn("[AutoWalk Local] LocalPlayer not found. Ensure this is a LocalScript under StarterPlayerScripts.")
	return
end

-- ========== Config ==========
local SAMPLE_RATE_HZ = 60
local GHOST_TRANSPARENCY = 0.35
local GHOST_COLOR = Color3.fromRGB(180, 230, 255)

-- ========== State ==========
local isRecording = false
local isPlaying = false
local timeline = {}       -- current recording: array of { t, cf }
local recConn : RBXScriptConnection? = nil
local recStart = 0
local playStart = 0
local playIndex = 1
local ghostModel : Model? = nil
local lastSampleTime = 0

-- local-only storage (lives in memory while game runs)
local savedRecordings : {[string]: {timeline: any, count: number, duration: number, updatedAt: number}} = {}

-- ========== Utils ==========
local function tclear(t)
	if table.clear then table.clear(t) else for k in pairs(t) do t[k] = nil end end
end

local function info(msg: string)
	print("[AutoWalk Local] " .. msg)
	if script:FindFirstChild("StatusBinder") then
		script.StatusBinder.Value = msg
	end
end

local function getCharacter(): Model
	local ch = player.Character or player.CharacterAdded:Wait()
	if not ch:FindFirstChild("HumanoidRootPart") then ch:WaitForChild("HumanoidRootPart") end
	return ch
end

local function stripScripts(model: Instance)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Script") or d:IsA("LocalScript") then d:Destroy() end
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

local function makeGhostFromCharacter(character: Model): Model
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

-- ========== Recording ==========
local function startRecording()
	if isPlaying then info("Stop playback first."); return end
	local character = getCharacter()
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then info("HumanoidRootPart missing."); return end

	tclear(timeline)
	playIndex = 1
	recStart = time()
	lastSampleTime = recStart
	isRecording = true
	info("Recording started. Move your character, press F again to stop.")

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
		info("Recording too short (no samples). Try moving a bit longer.")
		tclear(timeline)
		return
	end
	info(("Recording stopped. %d keys / %.2fs"):format(#timeline, timeline[#timeline].t))
end

-- ========== Playback ==========
local function playRecording()
	if isRecording then info("Stop recording first."); return end
	if isPlaying then info("Already playing."); return end
	if #timeline < 2 then info("No recording to play."); return end

	local character = getCharacter()
	local ghost = makeGhostFromCharacter(character)
	if not ghost.PrimaryPart then info("Ghost HRP missing."); destroyGhost(); return end

	ghost:PivotTo(timeline[1].cf)
	isPlaying = true
	playStart = time()
	playIndex = 1
	info("Playback started.")

	local conn
	conn = RunService.Heartbeat:Connect(function()
		if not isPlaying then conn:Disconnect(); return end
		local elapsed = time() - playStart
		if elapsed >= timeline[#timeline].t then
			ghost:PivotTo(timeline[#timeline].cf)
			isPlaying = false
			info("Playback finished.")
			return
		end

		while playIndex < #timeline and timeline[playIndex + 1].t < elapsed do
			playIndex += 1
		end
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
	isPlaying = false
	tclear(timeline)
	playIndex = 1
	destroyGhost()
	info("Cleared current recording & ghost.")
end

-- ========== Local Save / Load (in-memory) ==========
local function saveCurrent(name: string)
	if #timeline < 2 then info("No data to save. Record something first."); return end
	name = tostring(name or ""):gsub("^%s*(.-)%s*$", "%1")
	if name == "" then name = "checkpoint_" .. os.time() end

	-- deep copy timeline to avoid later mutations
	local copy = table.create(#timeline)
	for i, k in ipairs(timeline) do
		copy[i] = { t = k.t, cf = k.cf }
	end
	savedRecordings[name] = {
		timeline = copy,
		count = #copy,
		duration = copy[#copy].t,
		updatedAt = os.time()
	}
	info(("Saved '%s' (%d keys / %.2fs) [local]"):format(name, #copy, copy[#copy].t))
end

local function loadByName(name: string)
	local item = savedRecordings[name]
	if not item then info("No local recording named '"..tostring(name).."'."); return end
	timeline = table.create(item.count)
	for i, k in ipairs(item.timeline) do
		timeline[i] = { t = k.t, cf = k.cf }
	end
	info(("Loaded '%s' (%d keys / %.2fs) [local]"):format(name, #timeline, timeline[#timeline].t))
end

local function deleteByName(name: string)
	if savedRecordings[name] then
		savedRecordings[name] = nil
		info("Deleted '"..name.."' from local saves.")
	end
end

local function listAll()
	-- returns array of {name=..., count=..., duration=..., updatedAt=...}
	local out = {}
	for nm, meta in pairs(savedRecordings) do
		table.insert(out, {name = nm, count = meta.count, duration = meta.duration, updatedAt = meta.updatedAt})
	end
	table.sort(out, function(a,b) return (a.updatedAt or 0) > (b.updatedAt or 0) end)
	return out
end

-- ========== GUI (Auto Walk System style) ==========
local playerGui = player:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "AutoWalkSystem_Local"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.IgnoreGuiInset = true
gui.Parent = playerGui

local frame = Instance.new("Frame", gui)
frame.Name = "Main"
frame.Size = UDim2.new(0, 360, 0, 460)
frame.Position = UDim2.new(0, 16, 0.22, 0)
frame.BackgroundColor3 = Color3.fromRGB(24,24,24)
frame.BorderSizePixel = 0
local frCorner = Instance.new("UICorner", frame); frCorner.CornerRadius = UDim.new(0,10)

local top = Instance.new("Frame", frame)
top.Size = UDim2.new(1,0,0,36)
top.BackgroundColor3 = Color3.fromRGB(18,18,18)
local topCorner = Instance.new("UICorner", top); topCorner.CornerRadius = UDim.new(0,10)

local title = Instance.new("TextLabel", top)
title.Size = UDim2.new(1,-40,1,0)
title.Position = UDim2.new(0,10,0,0)
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

local function mkLabel(text: string, parent: Instance, h: number?)
	local l = Instance.new("TextLabel", parent)
	l.Size = UDim2.new(1,0,0,h or 20)
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextColor3 = Color3.fromRGB(220,220,220)
	l.Font = Enum.Font.Gotham
	l.TextSize = 14
	l.TextXAlignment = Enum.TextXAlignment.Left
	return l
end

local function mkButton(text: string, parent: Instance, color: Color3?)
	local b = Instance.new("TextButton", parent)
	b.Size = UDim2.new(1,0,0,36)
	b.BackgroundColor3 = color or Color3.fromRGB(60,60,60)
	b.Text = text
	b.Font = Enum.Font.GothamSemibold
	b.TextSize = 15
	b.TextColor3 = Color3.fromRGB(240,240,240)
	local c = Instance.new("UICorner", b); c.CornerRadius = UDim.new(0,8)
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
recLabel.Size = UDim2.new(1,-30,1,0)
recLabel.Position = UDim2.new(0,32,0,0)
recLabel.BackgroundTransparency = 1
recLabel.TextXAlignment = Enum.TextXAlignment.Left
recLabel.Text = "Record: OFF (Press F)"
recLabel.TextColor3 = Color3.fromRGB(200,200,200)
recLabel.Font = Enum.Font.Gotham
recLabel.TextSize = 14

local function setRecordUI(on: boolean)
	recIndicator.BackgroundColor3 = on and Color3.fromRGB(220,60,60) or Color3.fromRGB(160,160,160)
	recLabel.Text = on and "Record: ON (Press F)" or "Record: OFF (Press F)"
end

local function toggleRecord()
	if isRecording then
		stopRecording()
		isRecording = false
		setRecordUI(false)
	else
		startRecording()
		isRecording = true
		setRecordUI(true)
	end
end

-- Big red button
local bigBtn = mkButton("STOP WALK", content, Color3.fromRGB(200,40,40))
bigBtn.Position = UDim2.new(0,0,0,46)
bigBtn.MouseButton1Click:Connect(function() playRecording() end)

-- Save / Refresh / Name Row
local row2 = Instance.new("Frame", content)
row2.Size = UDim2.new(1,0,0,40)
row2.Position = UDim2.new(0,0,0,96)
row2.BackgroundTransparency = 1

local nameBox = Instance.new("TextBox", row2)
nameBox.Size = UDim2.new(1,-220,0,34)
nameBox.Position = UDim2.new(0,6,0,0)
nameBox.PlaceholderText = "checkpoint name..."
nameBox.Text = "myRun"
nameBox.ClearTextOnFocus = false
nameBox.BackgroundColor3 = Color3.fromRGB(40,40,40)
nameBox.Font = Enum.Font.Gotham
nameBox.TextSize = 14
local nbCorner = Instance.new("UICorner", nameBox); nbCorner.CornerRadius = UDim.new(0,8)

local saveBtn = mkButton("Save", row2, Color3.fromRGB(30,140,40))
saveBtn.Size = UDim2.new(0, 68, 0, 34)
saveBtn.Position = UDim2.new(1,-206,0,0)

local refreshBtn = mkButton("Refresh", row2, Color3.fromRGB(36,120,220))
refreshBtn.Size = UDim2.new(0, 86, 0, 34)
refreshBtn.Position = UDim2.new(1,-136,0,0)

local clearBtn = mkButton("Clear", row2, Color3.fromRGB(80,80,80))
clearBtn.Size = UDim2.new(0, 68, 0, 34)
clearBtn.Position = UDim2.new(1,-68,0,0)

-- Saved list label
local savedLabel = mkLabel("Saved Checkpoints (Local)", content, 20)
savedLabel.Position = UDim2.new(0,0,0,146)

-- Scroll list
local scroll = Instance.new("ScrollingFrame", content)
scroll.Size = UDim2.new(1,0,0,230)
scroll.Position = UDim2.new(0,0,0,170)
scroll.CanvasSize = UDim2.new(0,0)
scroll.ScrollBarThickness = 6
scroll.BackgroundTransparency = 1
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y

local listLayout = Instance.new("UIListLayout", scroll)
listLayout.Padding = UDim.new(0,6)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder

local function addRow(item: {name:string, count:number, duration:number})
	local row = Instance.new("Frame", scroll)
	row.Size = UDim2.new(1,-12,0,32)
	row.BackgroundTransparency = 1

	local nameBtn = mkButton("  "..item.name, row, Color3.fromRGB(40,40,40))
	nameBtn.Size = UDim2.new(1,-140,1,0)
	nameBtn.TextXAlignment = Enum.TextXAlignment.Left

	local loadBtn = mkButton("Load", row, Color3.fromRGB(70,70,70))
	loadBtn.Size = UDim2.new(0, 46, 1, 0)
	loadBtn.Position = UDim2.new(1,-92,0,0)

	local playBtn = mkButton("Play", row, Color3.fromRGB(90,90,90))
	playBtn.Size = UDim2.new(0, 46, 1, 0)
	playBtn.Position = UDim2.new(1,-46,0,0)

	local delBtn = Instance.new("TextButton", row)
	delBtn.Size = UDim2.new(0, 28, 1, 0)
	delBtn.Position = UDim2.new(1, 0, 0, 0)
	delBtn.Text = "✕"
	delBtn.Font = Enum.Font.Gotham
	delBtn.TextSize = 14
	delBtn.TextColor3 = Color3.fromRGB(240,240,240)
	delBtn.BackgroundColor3 = Color3.fromRGB(120,30,30)
	local dCorner = Instance.new("UICorner", delBtn); dCorner.CornerRadius = UDim.new(0,8)

	nameBtn.MouseButton1Click:Connect(function() nameBox.Text = item.name end)
	loadBtn.MouseButton1Click:Connect(function() loadByName(item.name) end)
	playBtn.MouseButton1Click:Connect(function() loadByName(item.name); task.delay(0.05, function() playRecording() end) end)
	delBtn.MouseButton1Click:Connect(function() deleteByName(item.name); task.defer(function() rebuildList() end) end)
end

function rebuildList()
	for _, ch in ipairs(scroll:GetChildren()) do
		if ch:IsA("Frame") or ch:IsA("TextButton") then ch:Destroy() end
	end
	local items = listAll()
	for _, it in ipairs(items) do
		addRow(it)
	end
	task.defer(function()
		scroll.CanvasSize = UDim2.new(0,0,0, (#items * 38))
	end)
end

-- Button callbacks
saveBtn.MouseButton1Click:Connect(function()
	saveCurrent(nameBox.Text)
	rebuildList()
end)

refreshBtn.MouseButton1Click:Connect(function()
	rebuildList()
	info("List refreshed.")
end)

clearBtn.MouseButton1Click:Connect(function()
	clearRecording()
end)

-- Status label at bottom
local StatusBinder = Instance.new("StringValue")
StatusBinder.Name = "StatusBinder"
StatusBinder.Parent = script
local statusLabel = mkLabel("Ready", content, 20)
statusLabel.Position = UDim2.new(0,0,0,410)
StatusBinder.Changed:Connect(function() statusLabel.Text = StatusBinder.Value end)

-- Keyboard binds
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.F then
		toggleRecord()
	elseif input.KeyCode == Enum.KeyCode.P then
		playRecording()
	elseif input.KeyCode == Enum.KeyCode.L then
		clearRecording()
	end
end)

-- Optional drag to move panel
do
	local dragging, dragStart, startPos
	frame.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true
			dragStart = input.Position
			startPos = frame.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then dragging = false end
			end)
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
			local delta = input.Position - dragStart
			frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
		end
	end)
end

-- Init
rebuildList()
info("AutoWalk Local ready. Keys: F=Record/Stop, P=Play, L=Clear.")
