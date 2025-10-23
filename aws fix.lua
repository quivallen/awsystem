-- AutoWalkSystem_StudioJSON_Local.lua
-- Lokal-only (AMAN): Rekam, simpan di memori, Export/Import JSON via UI (copy–paste).
-- Toggle GUI = K, F = Record/Stop, P = Play, L = Clear.

-- ========== Services ==========
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
if not player then
	warn("[AutoWalk Local] Harus LocalScript di StarterPlayerScripts.")
	return
end

-- ========== Config / Theme ==========
local SAMPLE_RATE_HZ = 60
local THEME_BG = Color3.fromRGB(22,22,22)       -- hitam matte lembut
local THEME_PANEL = Color3.fromRGB(28,28,28)
local THEME_TEXT = Color3.fromRGB(235,235,235)
local THEME_MUTED = Color3.fromRGB(170,170,170)
local THEME_ACCENT = Color3.fromRGB(200,50,50)  -- merah elegan
local THEME_ACCENT_2 = Color3.fromRGB(100,100,100)

local GHOST_TRANSPARENCY = 0.35
local GHOST_COLOR = Color3.fromRGB(220,60,60)

-- ========== State ==========
local isRecording = false
local isPlaying = false
local timeline = {} -- { {t, cf}, ... }
local recConn
local recStart = 0
local lastSampleTime = 0
local playStart = 0
local playIndex = 1
local ghostModel

-- Simpan rekaman di memori lokal selama sesi (nama -> meta + timeline)
local saved = {}  -- [name] = { timeline = {...}, count = n, duration = sec, updatedAt = os.time() }

-- ========== Utils ==========
local function tclear(t) if table.clear then table.clear(t) else for k in pairs(t) do t[k]=nil end end end
local function info(msg)
	print("[AutoWalk] "..msg)
	if script:FindFirstChild("StatusBinder") then script.StatusBinder.Value = msg end
end
local function getCharacter()
	local ch = player.Character or player.CharacterAdded:Wait()
	ch:WaitForChild("HumanoidRootPart")
	return ch
end
local function stripScripts(model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Script") or d:IsA("LocalScript") then d:Destroy() end
	end
end
local function anchorGhost(model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d:SetNetworkOwnershipAuto()
			d.Transparency = GHOST_TRANSPARENCY
			d.Color = GHOST_COLOR
		end
	end
end
local function destroyGhost()
	if ghostModel and ghostModel.Parent then ghostModel:Destroy() end
	ghostModel = nil
end
local function makeGhostFromCharacter(character)
	destroyGhost()
	local clone = character:Clone()
	stripScripts(clone)
	local hum = clone:FindFirstChildOfClass("Humanoid")
	if hum then hum:Destroy() end
	anchorGhost(clone)
	local hrp = clone:FindFirstChild("HumanoidRootPart")
	if hrp then clone.PrimaryPart = hrp end
	clone.Name = "Ghost_"..player.Name
	clone.Parent = workspace
	ghostModel = clone
	return clone
end

-- ========== Recording ==========
local function startRecording()
	if isPlaying then info("Stop playback dulu."); return end
	local character = getCharacter()
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then info("HRP tidak ditemukan."); return end

	tclear(timeline)
	playIndex = 1
	recStart = time()
	lastSampleTime = recStart
	isRecording = true
	info("Recording... (F untuk Stop)")

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
		info("Rekaman terlalu pendek.")
		tclear(timeline)
		return
	end
	info(("Stopped. %d frames / %.2fs"):format(#timeline, timeline[#timeline].t))
end

-- ========== Playback ==========
local function playLocal()
	if isRecording then info("Stop recording dulu."); return end
	if isPlaying then info("Sedang play."); return end
	if #timeline < 2 then info("Tidak ada rekaman aktif."); return end

	local character = getCharacter()
	local ghost = makeGhostFromCharacter(character)
	if not ghost.PrimaryPart then info("Ghost HRP hilang."); destroyGhost(); return end
	ghost:PivotTo(timeline[1].cf)

	isPlaying = true
	playStart = time()
	playIndex = 1
	info("Playing...")

	local conn
	conn = RunService.Heartbeat:Connect(function()
		if not isPlaying then conn:Disconnect(); return end
		local elapsed = time() - playStart
		if elapsed >= timeline[#timeline].t then
			ghost:PivotTo(timeline[#timeline].cf)
			isPlaying = false
			info("Selesai.")
			conn:Disconnect()
			return
		end
		while playIndex < #timeline and timeline[playIndex + 1].t < elapsed do
			playIndex += 1
		end
		playIndex = math.clamp(playIndex, 1, math.max(1, #timeline - 1))
		local a = timeline[playIndex]
		local b = timeline[playIndex + 1]
		if not b then ghost:PivotTo(a.cf); return end
		local alpha = (elapsed - a.t) / math.max(1e-6, b.t - a.t)
		ghost:PivotTo(a.cf:Lerp(b.cf, alpha))
	end)
end

local function clearActive()
	if isRecording then stopRecording() end
	isPlaying = false
	tclear(timeline)
	playIndex = 1
	destroyGhost()
	info("Cleared.")
end

-- ========== Save to Memory ==========
local function saveLocal(name)
	name = tostring(name or ""):gsub("^%s*(.-)%s*$","%1")
	if name == "" then name = "checkpoint_"..os.time() end
	if #timeline < 2 then info("Belum ada data untuk disimpan."); return end
	-- deep copy
	local copy = table.create(#timeline)
	for i, k in ipairs(timeline) do copy[i] = { t = k.t, cf = k.cf } end
	saved[name] = { timeline = copy, count = #copy, duration = copy[#copy].t, updatedAt = os.time() }
	info(("Saved local '%s' (%d frames / %.2fs)"):format(name, #copy, copy[#copy].t))
end

local function loadLocal(name)
	local it = saved[name]
	if not it then info("Tidak ada rekaman bernama '"..name.."'"); return end
	timeline = table.create(it.count)
	for i, k in ipairs(it.timeline) do timeline[i] = { t = k.t, cf = k.cf } end
	info(("Loaded '%s' (%d frames / %.2fs)"):format(name, #timeline, timeline[#timeline].t))
end

local function deleteLocal(name)
	if saved[name] then saved[name] = nil; info("Deleted '"..name.."'") end
end

local function listLocal()
	local out = {}
	for nm, meta in pairs(saved) do
		table.insert(out, {name=nm, count=meta.count, duration=meta.duration, updatedAt=meta.updatedAt})
	end
	table.sort(out, function(a,b) return (a.updatedAt or 0) > (b.updatedAt or 0) end)
	return out
end

-- ========== JSON Export / Import (via UI TextBox) ==========
local function timelineToJSONArray(tl)
	local arr = table.create(#tl)
	for i, v in ipairs(tl) do
		arr[i] = {
			t = v.t,
			cf = {
				X = v.cf.X, Y = v.cf.Y, Z = v.cf.Z,
				R00 = v.cf.R00, R01 = v.cf.R01, R02 = v.cf.R02,
				R10 = v.cf.R10, R11 = v.cf.R11, R12 = v.cf.R12,
				R20 = v.cf.R20, R21 = v.cf.R21, R22 = v.cf.R22
			}
		}
	end
	return arr
end

local function jsonToTimeline(jsonText)
	local ok, data = pcall(function() return HttpService:JSONDecode(jsonText) end)
	if not ok or type(data) ~= "table" then return nil, "JSON invalid" end
	local out = {}
	for _, v in ipairs(data) do
		if type(v) == "table" and v.t and v.cf then
			local cf = CFrame.new(
				v.cf.X, v.cf.Y, v.cf.Z,
				v.cf.R00, v.cf.R01, v.cf.R02,
				v.cf.R10, v.cf.R11, v.cf.R12,
				v.cf.R20, v.cf.R21, v.cf.R22
			)
			table.insert(out, { t = v.t, cf = cf })
		end
	end
	if #out < 2 then return nil, "Data kurang (frames < 2)" end
	return out
end

-- ========== UI (Black-Red Minimal) ==========
local pg = player:WaitForChild("PlayerGui")
local gui = Instance.new("ScreenGui")
gui.Name = "AutoWalk_JSON_UI"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.Enabled = true
gui.Parent = pg

-- Toggle with K
UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == Enum.KeyCode.K then
		gui.Enabled = not gui.Enabled
	end
end)

local root = Instance.new("Frame", gui)
root.AnchorPoint = Vector2.new(0.5, 0.5)
root.Position = UDim2.fromScale(0.5, 0.5)
root.Size = UDim2.fromOffset(420, 520)
root.BackgroundColor3 = THEME_PANEL
root.BorderSizePixel = 0
local rc = Instance.new("UICorner", root); rc.CornerRadius = UDim.new(0,12)
local pad = Instance.new("UIPadding", root)
pad.PaddingTop = UDim.new(0,14); pad.PaddingBottom = UDim.new(0,14)
pad.PaddingLeft = UDim.new(0,14); pad.PaddingRight = UDim.new(0,14)

local header = Instance.new("TextLabel", root)
header.BackgroundTransparency = 1
header.Size = UDim2.new(1,0,0,28)
header.Text = "Auto Walk System (Local JSON)"
header.Font = Enum.Font.GothamBold
header.TextSize = 18
header.TextColor3 = THEME_TEXT
header.TextXAlignment = Enum.TextXAlignment.Left

local function mkBtn(text, h)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1,0,0,h or 36)
	b.BackgroundColor3 = THEME_ACCENT
	b.AutoButtonColor = true
	b.Text = text
	b.TextColor3 = THEME_TEXT
	b.Font = Enum.Font.GothamSemibold
	b.TextSize = 15
	local c = Instance.new("UICorner", b); c.CornerRadius = UDim.new(0,10)
	return b
end

local col = Instance.new("Frame", root)
col.BackgroundTransparency = 1
col.Size = UDim2.new(1,0,0,160)
col.Position = UDim2.new(0,0,0,36)
local vlist = Instance.new("UIListLayout", col)
vlist.Padding = UDim.new(0,8)
vlist.FillDirection = Enum.FillDirection.Vertical
vlist.HorizontalAlignment = Enum.HorizontalAlignment.Stretch
vlist.SortOrder = Enum.SortOrder.LayoutOrder

-- Buttons row
local btnRecord = mkBtn("● RECORD / STOP  (F)")
btnRecord.BackgroundColor3 = Color3.fromRGB(160,40,40)
btnRecord.Parent = col

local btnPlay = mkBtn("▶ PLAY  (P)")
btnPlay.BackgroundColor3 = Color3.fromRGB(60,60,60)
btnPlay.Parent = col

local btnClear = mkBtn("🧹 CLEAR  (L)")
btnClear.BackgroundColor3 = Color3.fromRGB(50,50,50)
btnClear.Parent = col

-- Name + Save Row
local nameRow = Instance.new("Frame", root)
nameRow.BackgroundTransparency = 1
nameRow.Size = UDim2.new(1,0,0,38)
nameRow.Position = UDim2.new(0,0,0,36+160+6)
local nh = Instance.new("UIListLayout", nameRow)
nh.FillDirection = Enum.FillDirection.Horizontal
nh.Padding = UDim.new(0,8)
nh.HorizontalAlignment = Enum.HorizontalAlignment.Left

local nameBox = Instance.new("TextBox", nameRow)
nameBox.Size = UDim2.new(1,-110,1,0)
nameBox.BackgroundColor3 = Color3.fromRGB(36,36,36)
nameBox.TextColor3 = THEME_TEXT
nameBox.PlaceholderText = "checkpoint name..."
nameBox.Text = "checkpoint_1"
nameBox.ClearTextOnFocus = false
nameBox.Font = Enum.Font.Gotham
nameBox.TextSize = 14
local nb = Instance.new("UICorner", nameBox); nb.CornerRadius = UDim.new(0,10)

local btnSave = mkBtn("Save")
btnSave.Size = UDim2.new(0,48,1,0)
btnSave.BackgroundColor3 = Color3.fromRGB(70,70,70)
btnSave.Parent = nameRow

local btnRefresh = mkBtn("Refresh")
btnRefresh.Size = UDim2.new(0,54,1,0)
btnRefresh.BackgroundColor3 = Color3.fromRGB(70,70,70)
btnRefresh.Parent = nameRow

-- Saved list
local savedLabel = Instance.new("TextLabel", root)
savedLabel.BackgroundTransparency = 1
savedLabel.Text = "Local Saved Checkpoints"
savedLabel.Size = UDim2.new(1,0,0,20)
savedLabel.Position = UDim2.new(0,0,0,36+160+6+38+6)
savedLabel.Font = Enum.Font.Gotham
savedLabel.TextSize = 14
savedLabel.TextColor3 = THEME_MUTED
savedLabel.TextXAlignment = Enum.TextXAlignment.Left

local list = Instance.new("ScrollingFrame", root)
list.Size = UDim2.new(1,0,0,120)
list.Position = UDim2.new(0,0,0,36+160+6+38+6+22)
list.BackgroundColor3 = Color3.fromRGB(30,30,30)
list.BorderSizePixel = 0
list.ScrollBarThickness = 6
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
local lc = Instance.new("UICorner", list); lc.CornerRadius = UDim.new(0,10)
local ll = Instance.new("UIListLayout", list)
ll.Padding = UDim.new(0,6)
ll.SortOrder = Enum.SortOrder.LayoutOrder

local function addSavedRow(item)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1,-8,0,32)
	row.BackgroundColor3 = Color3.fromRGB(36,36,36)
	row.BorderSizePixel = 0
	local rc = Instance.new("UICorner", row); rc.CornerRadius = UDim.new(0,8)

	local nameBtn = mkBtn("  "..item.name, 32)
	nameBtn.BackgroundColor3 = Color3.fromRGB(46,46,46)
	nameBtn.TextXAlignment = Enum.TextXAlignment.Left
	nameBtn.Size = UDim2.new(1,-148,1,0)
	nameBtn.Parent = row

	local loadBtn = mkBtn("Load", 32)
	loadBtn.BackgroundColor3 = Color3.fromRGB(60,60,60)
	loadBtn.Size = UDim2.new(0,50,1,0)
	loadBtn.Parent = row

	local playBtn = mkBtn("Play", 32)
	playBtn.BackgroundColor3 = Color3.fromRGB(70,70,70)
	playBtn.Size = UDim2.new(0,50,1,0)
	playBtn.Parent = row

	local delBtn = mkBtn("✕", 32)
	delBtn.BackgroundColor3 = Color3.fromRGB(120,40,40)
	delBtn.Size = UDim2.new(0,32,1,0)
	delBtn.Parent = row

	nameBtn.MouseButton1Click:Connect(function() nameBox.Text = item.name end)
	loadBtn.MouseButton1Click:Connect(function() loadLocal(item.name) end)
	playBtn.MouseButton1Click:Connect(function() loadLocal(item.name); task.delay(0.05, function() playLocal() end) end)
	delBtn.MouseButton1Click:Connect(function() deleteLocal(item.name); task.defer(function() _G.__rebuildSaved() end) end)

	return row
end

function _G.__rebuildSaved()
	for _, c in ipairs(list:GetChildren()) do
		if c:IsA("Frame") or c:IsA("TextButton") then c:Destroy() end
	end
	for _, it in ipairs(listLocal()) do
		addSavedRow(it).Parent = list
	end
end

-- JSON Panel (Export / Import)
local jsonPanel = Instance.new("Frame", root)
jsonPanel.Size = UDim2.new(1,0,0,160)
jsonPanel.Position = UDim2.new(0,0,1,-160)
jsonPanel.BackgroundColor3 = Color3.fromRGB(26,26,26)
jsonPanel.BorderSizePixel = 0
local jp = Instance.new("UICorner", jsonPanel); jp.CornerRadius = UDim.new(0,10)

local jsonTitle = Instance.new("TextLabel", jsonPanel)
jsonTitle.BackgroundTransparency = 1
jsonTitle.Size = UDim2.new(1,0,0,20)
jsonTitle.Position = UDim2.new(0,8,0,6)
jsonTitle.Text = "JSON Export / Import"
jsonTitle.Font = Enum.Font.Gotham
jsonTitle.TextSize = 14
jsonTitle.TextColor3 = THEME_MUTED
jsonTitle.TextXAlignment = Enum.TextXAlignment.Left

local jsonBox = Instance.new("TextBox", jsonPanel)
jsonBox.MultiLine = true
jsonBox.ClearTextOnFocus = false
jsonBox.Text = ""
jsonBox.PlaceholderText = "JSON muncul di sini saat Export.\nAtau paste JSON lalu tekan Import."
jsonBox.Font = Enum.Font.Code
jsonBox.TextSize = 14
jsonBox.TextWrapped = false
jsonBox.TextXAlignment = Enum.TextXAlignment.Left
jsonBox.TextYAlignment = Enum.TextYAlignment.Top
jsonBox.BackgroundColor3 = Color3.fromRGB(20,20,20)
jsonBox.TextColor3 = THEME_TEXT
jsonBox.Size = UDim2.new(1,-108,1,-34)
jsonBox.Position = UDim2.new(0,8,0,30)
local jbc = Instance.new("UICorner", jsonBox); jbc.CornerRadius = UDim.new(0,8)

local jsonBtns = Instance.new("Frame", jsonPanel)
jsonBtns.BackgroundTransparency = 1
jsonBtns.Size = UDim2.new(0, 92, 1, -34)
jsonBtns.Position = UDim2.new(1,-100,0,30)
local jlist = Instance.new("UIListLayout", jsonBtns)
jlist.Padding = UDim.new(0,6)

local btnExport = mkBtn("Export", 32); btnExport.Parent = jsonBtns
local btnImport = mkBtn("Import", 32); btnImport.BackgroundColor3 = Color3.fromRGB(60,60,60); btnImport.Parent = jsonBtns
local btnPlayJSON = mkBtn("Play JSON", 32); btnPlayJSON.BackgroundColor3 = Color3.fromRGB(70,70,70); btnPlayJSON.Parent = jsonBtns

-- Status
local statusLabel = Instance.new("TextLabel", root)
statusLabel.BackgroundTransparency = 1
statusLabel.Size = UDim2.new(1,0,0,20)
statusLabel.Position = UDim2.new(0,0,1,-186)
statusLabel.Text = "Ready. (Toggle GUI = K)"
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextSize = 14
statusLabel.TextColor3 = THEME_TEXT
statusLabel.TextXAlignment = Enum.TextXAlignment.Left

local binder = Instance.new("StringValue", script)
binder.Name = "StatusBinder"
binder.Changed:Connect(function() statusLabel.Text = binder.Value end)

-- ========== Wiring ==========
btnRecord.MouseButton1Click:Connect(function()
	if isRecording then stopRecording() else startRecording() end
end)
btnPlay.MouseButton1Click:Connect(function() playLocal() end)
btnClear.MouseButton1Click:Connect(function() clearActive() end)
btnSave.MouseButton1Click:Connect(function() saveLocal(nameBox.Text); _G.__rebuildSaved() end)
btnRefresh.MouseButton1Click:Connect(function() _G.__rebuildSaved(); info("List refreshed.") end)

-- Export current timeline to JSON editor
btnExport.MouseButton1Click:Connect(function()
	if #timeline < 2 then
		info("Tidak ada rekaman aktif untuk diexport.")
		return
	end
	local arr = timelineToJSONArray(timeline)
	jsonBox.Text = HttpService:JSONEncode(arr)
	info("Exported ke panel JSON. Copy manual lalu simpan sebagai file .json (mis. checkpoint_1.json).")
end)

-- Import timeline from JSON editor (replace current timeline)
btnImport.MouseButton1Click:Connect(function()
	local txt = tostring(jsonBox.Text or "")
	if txt == "" then info("JSON kosong."); return end
	local tl, err = jsonToTimeline(txt)
	if not tl then info("Gagal import: "..tostring(err)); return end
	timeline = tl
	info(("Imported JSON (%d frames / %.2fs)"):format(#timeline, timeline[#timeline].t))
end)

-- Play directly from JSON editor
btnPlayJSON.MouseButton1Click:Connect(function()
	local txt = tostring(jsonBox.Text or "")
	if txt == "" then info("JSON kosong."); return end
	local tl, err = jsonToTimeline(txt)
	if not tl then info("Gagal import untuk play: "..tostring(err)); return end
	timeline = tl
	task.defer(playLocal)
end)

-- Keybinds
UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == Enum.KeyCode.F then
		if isRecording then stopRecording() else startRecording() end
	elseif input.KeyCode == Enum.KeyCode.P then
		playLocal()
	elseif input.KeyCode == Enum.KeyCode.L then
		clearActive()
	elseif input.KeyCode == Enum.KeyCode.K then
		-- handled above (toggle)
	end
end)

-- Draggable
do
	local dragging, dragStart, startPos
	root.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true
			dragStart = input.Position
			startPos = root.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then dragging = false end
			end)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
			local delta = input.Position - dragStart
			root.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
		end
	end)
end

-- init
_G.__rebuildSaved()
info("Ready. F=Record/Stop, P=Play, L=Clear, K=Toggle GUI. Export/Import JSON via panel bawah.")
