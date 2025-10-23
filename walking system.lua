-- [[ Script GUI Rekam/Playback Client-Side (Jalankan di Executor) ]]

-- Services
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui") -- Atau bisa juga Players.LocalPlayer.PlayerGui

-- Player & Character Vars
local localPlayer = Players.LocalPlayer
local character = nil
local humanoid = nil
local rootPart = nil

-- Recording Vars
local isRecording = false
local recordedData = {} -- Data rekaman saat ini (sebelum disimpan)
local loadedData = nil -- Data rekaman yang di-load
local lastRecordTime = 0
local recordingConnection = nil
local REKAM_INTERVAL = 0.01 -- Interval rekam

-- Playback Vars
local playbackConnection = nil
local ghostNpc = nil

-- --- Konfigurasi File ---
local DEFAULT_FILENAME = "rekaman"
-- ------------------------

-- Helper Functions (Executor-specific file operations)
local function saveDataToFile(fileName, dataTable)
    if not writefile then warn("Fungsi writefile() tidak ditemukan."); return false, "writefile() missing" end
    if not dataTable or #dataTable == 0 then warn("Tidak ada data untuk disimpan."); return false, "No data" end

    -- Pastikan waktu dimulai dari 0
    local startTime = dataTable[1].time
    for i = 1, #dataTable do
        dataTable[i].time = dataTable[i].time - startTime
    end

    local successEncode, jsonData = pcall(function() return HttpService:JSONEncode(dataTable) end)
    if not successEncode then warn("Gagal encode JSON:", jsonData); return false, "JSON Encode Error" end

    local successSave, errSave = pcall(function() writefile(fileName .. ".json", jsonData) end) -- Tambah .json otomatis
    if successSave then
        print("Rekaman disimpan ke:", fileName .. ".json")
        return true
    else
        warn("Gagal menyimpan file:", errSave)
        return false, "File Save Error"
    end
end

local function loadDataFromFile(fileName)
    if not readfile or not isfile then warn("Fungsi readfile()/isfile() tidak ditemukan."); return nil end
    if not isfile(fileName .. ".json") then warn("File tidak ditemukan:", fileName .. ".json"); return nil end

    local jsonData = readfile(fileName .. ".json")
    local success, data = pcall(function() return HttpService:JSONDecode(jsonData) end)

    if success then
        print("Berhasil load data dari", fileName .. ".json")
        return data
    else
        warn("Gagal decode JSON:", data)
        return nil
    end
end

-- --- GUI Creation ---
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "RecorderGui"
screenGui.ResetOnSpawn = false -- Biar gak hilang pas mati

local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.new(0, 200, 0, 250) -- Lebar 200, Tinggi 250 pixel
mainFrame.Position = UDim2.new(0, 10, 0, 10) -- Pojok kiri atas
mainFrame.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
mainFrame.BorderSizePixel = 1
mainFrame.Draggable = true -- Biar bisa digeser-geser
mainFrame.Active = true
mainFrame.Parent = screenGui

local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "Title"
titleLabel.Size = UDim2.new(1, 0, 0, 20)
titleLabel.Position = UDim2.new(0, 0, 0, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
titleLabel.Text = "Rekam & Putar Ulang"
titleLabel.Font = Enum.Font.SourceSansBold
titleLabel.TextSize = 14
titleLabel.Parent = mainFrame

local nameInput = Instance.new("TextBox")
nameInput.Name = "NameInput"
nameInput.Size = UDim2.new(1, -10, 0, 30)
nameInput.Position = UDim2.new(0, 5, 0, 25)
nameInput.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
nameInput.TextColor3 = Color3.fromRGB(255, 255, 255)
nameInput.PlaceholderText = "Nama File Rekaman..."
nameInput.Text = DEFAULT_FILENAME
nameInput.ClearTextOnFocus = false
nameInput.Font = Enum.Font.SourceSans
nameInput.TextSize = 14
nameInput.Parent = mainFrame

local recordButton = Instance.new("TextButton")
recordButton.Name = "RecordButton"
recordButton.Size = UDim2.new(1, -10, 0, 30)
recordButton.Position = UDim2.new(0, 5, 0, 60)
recordButton.BackgroundColor3 = Color3.fromRGB(200, 0, 0)
recordButton.TextColor3 = Color3.fromRGB(255, 255, 255)
recordButton.Text = "🔴 Mulai Rekam"
recordButton.Font = Enum.Font.SourceSansBold
recordButton.TextSize = 14
recordButton.Parent = mainFrame

local saveButton = Instance.new("TextButton")
saveButton.Name = "SaveButton"
saveButton.Size = UDim2.new(0.5, -7.5, 0, 30) -- Setengah lebar frame dikurangi sedikit
saveButton.Position = UDim2.new(0, 5, 0, 95)
saveButton.BackgroundColor3 = Color3.fromRGB(0, 150, 200)
saveButton.TextColor3 = Color3.fromRGB(255, 255, 255)
saveButton.Text = "💾 Simpan"
saveButton.Font = Enum.Font.SourceSansBold
saveButton.TextSize = 14
saveButton.Parent = mainFrame
saveButton.AutoButtonColor = false -- Disable sementara

local loadButton = Instance.new("TextButton")
loadButton.Name = "LoadButton"
loadButton.Size = UDim2.new(0.5, -7.5, 0, 30)
loadButton.Position = UDim2.new(0.5, 2.5, 0, 95) -- Sebelahnya save button
loadButton.BackgroundColor3 = Color3.fromRGB(0, 200, 100)
loadButton.TextColor3 = Color3.fromRGB(255, 255, 255)
loadButton.Text = "📁 Muat"
loadButton.Font = Enum.Font.SourceSansBold
loadButton.TextSize = 14
loadButton.Parent = mainFrame

local playButton = Instance.new("TextButton")
playButton.Name = "PlayButton"
playButton.Size = UDim2.new(1, -10, 0, 30)
playButton.Position = UDim2.new(0, 5, 0, 130)
playButton.BackgroundColor3 = Color3.fromRGB(0, 200, 0)
playButton.TextColor3 = Color3.fromRGB(255, 255, 255)
playButton.Text = "▶️ Putar Ulang"
playButton.Font = Enum.Font.SourceSansBold
playButton.TextSize = 14
playButton.Parent = mainFrame
playButton.AutoButtonColor = false -- Disable sementara

local statusLabel = Instance.new("TextLabel")
statusLabel.Name = "StatusLabel"
statusLabel.Size = UDim2.new(1, -10, 0, 60)
statusLabel.Position = UDim2.new(0, 5, 0, 165)
statusLabel.BackgroundTransparency = 1
statusLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
statusLabel.Text = "Status: Siap"
statusLabel.Font = Enum.Font.SourceSans
statusLabel.TextSize = 12
statusLabel.TextWrapped = true
statusLabel.TextYAlignment = Enum.TextYAlignment.Top
statusLabel.Parent = mainFrame

-- Masukkan GUI ke CoreGui (atau PlayerGui)
screenGui.Parent = CoreGui -- Lebih aman pakai CoreGui biar gak ke-reset pas karakter mati

-- --- Recording Logic ---
local function getCurrentDataPoint()
    -- (Sama seperti script rekam sebelumnya)
    if not character or not rootPart or not humanoid then return nil end
    local currentTime = tick()
    return {
        time = currentTime,
        position = {x = rootPart.Position.X, y = rootPart.Position.Y, z = rootPart.Position.Z},
        rotation = math.atan2(rootPart.CFrame.LookVector.X, rootPart.CFrame.LookVector.Z) * -1,
        velocity = {x = rootPart.Velocity.X, y = rootPart.Velocity.Y, z = rootPart.Velocity.Z},
        moveDirection = {x = humanoid.MoveDirection.X, y = humanoid.MoveDirection.Y, z = humanoid.MoveDirection.Z},
        state = humanoid:GetState().Name,
        jumping = humanoid:GetState() == Enum.HumanoidStateType.Jumping
    }
end

local function startRecording()
    character = localPlayer.Character
    if not character then statusLabel.Text = "Status: Karakter tidak ada."; return end
    humanoid = character:FindFirstChildOfClass("Humanoid")
    rootPart = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not rootPart then statusLabel.Text = "Status: Humanoid/RootPart hilang."; return end

    recordedData = {}
    lastRecordTime = tick()
    isRecording = true
    statusLabel.Text = "Status: Merekam..."
    recordButton.Text = "⏹️ Stop Rekam"
    recordButton.BackgroundColor3 = Color3.fromRGB(255, 100, 100)
    saveButton.AutoButtonColor = false -- Disable save pas rekam
    loadButton.AutoButtonColor = false -- Disable load pas rekam
    playButton.AutoButtonColor = false -- Disable play pas rekam

    local firstPoint = getCurrentDataPoint()
    if firstPoint then table.insert(recordedData, firstPoint) end

    recordingConnection = RunService.RenderStepped:Connect(function()
        if not isRecording then return end
        local currentTime = tick()
        if currentTime - lastRecordTime >= REKAM_INTERVAL then
            local dataPoint = getCurrentDataPoint()
            if dataPoint then
                table.insert(recordedData, dataPoint)
                lastRecordTime = currentTime
            else
                -- Karakter mungkin hilang, stop rekam
                recordButton.MouseButton1Click:Fire() -- Panggil fungsi stop
            end
        end
    end)
end

local function stopRecording()
    if not isRecording then return end
    isRecording = false
    if recordingConnection then recordingConnection:Disconnect(); recordingConnection = nil end

    statusLabel.Text = "Status: Rekaman Selesai (" .. #recordedData .. " frame). Siap disimpan."
    recordButton.Text = "🔴 Mulai Rekam"
    recordButton.BackgroundColor3 = Color3.fromRGB(200, 0, 0)
    saveButton.AutoButtonColor = true -- Enable save
    loadButton.AutoButtonColor = true -- Enable load
    playButton.AutoButtonColor = loadedData and true or false -- Enable play jika ada data yg di-load
end

-- --- Playback Logic ---
local function startPlayback()
    if not loadedData then statusLabel.Text = "Status: Belum ada data rekaman dimuat."; return end
    if ghostNpc then statusLabel.Text = "Status: Playback sedang berjalan."; return end -- Jangan mulai kalau masih ada ghost

    -- Clone model (pakai karakter player saat ini aja biar gampang)
    character = localPlayer.Character
    if not character then statusLabel.Text = "Status: Karakter player hilang."; return end
    ghostNpc = character:Clone()
    ghostNpc.Name = "GhostReplay"
    ghostNpc.Parent = Workspace
    ghostNpc:MakeJoints()

    local ghostHumanoid = ghostNpc:FindFirstChildOfClass("Humanoid")
    if ghostHumanoid then ghostHumanoid:SetStateEnabled(Enum.HumanoidStateType.Physics, false) end

    for _, part in pairs(ghostNpc:GetDescendants()) do
        if part:IsA("BasePart") then
            part.Transparency = 0.6
            part.CanCollide = false
            part.Anchored = true
        end
    end
    local ghostRoot = ghostNpc:FindFirstChild("HumanoidRootPart")
    if not ghostRoot then ghostNpc:Destroy(); ghostNpc = nil; statusLabel.Text = "Status: Error, ghost root hilang."; return end
    ghostRoot.Anchored = false

    statusLabel.Text = "Status: Memutar ulang..."
    playButton.Text = "⏹️ Stop Putar"
    playButton.BackgroundColor3 = Color3.fromRGB(255, 100, 100)
    recordButton.AutoButtonColor = false -- Disable record pas playback
    saveButton.AutoButtonColor = false -- Disable save pas playback
    loadButton.AutoButtonColor = false -- Disable load pas playback

    local startTime = tick()
    local recordStartTime = loadedData[1].time

    playbackConnection = RunService.RenderStepped:Connect(function()
        if not ghostNpc or not ghostNpc.Parent then -- Cek kalau ghost masih ada
            if playbackConnection then playbackConnection:Disconnect(); playbackConnection = nil; end
            return
        end

        local currentTime = tick()
        local elapsedTime = currentTime - startTime
        local targetRecordTime = recordStartTime + elapsedTime

        local currentFrameData, nextFrameData
        for i = 1, #loadedData do
            if loadedData[i].time >= targetRecordTime then
                currentFrameData = loadedData[math.max(1, i-1)]
                nextFrameData = loadedData[i]
                break
            end
        end

        if not nextFrameData and targetRecordTime > loadedData[#loadedData].time then
            playButton.MouseButton1Click:Fire() -- Panggil fungsi stop playback
            return
        end

        if not currentFrameData or not nextFrameData then
             currentFrameData = loadedData[1]; nextFrameData = loadedData[1]
        end

        local timeDiff = nextFrameData.time - currentFrameData.time
        local alpha = 0
        if timeDiff > 0 then alpha = math.clamp((targetRecordTime - currentFrameData.time) / timeDiff, 0, 1) end

        local currentPos = Vector3.new(currentFrameData.position.x, currentFrameData.position.y, currentFrameData.position.z)
        local nextPos = Vector3.new(nextFrameData.position.x, nextFrameData.position.y, nextFrameData.position.z)
        local currentRotY = currentFrameData.rotation
        local nextRotY = nextFrameData.rotation
        local interpolatedPos = currentPos:Lerp(nextPos, alpha)
        local interpolatedRotY = currentRotY + (nextRotY - currentRotY) * alpha

        ghostRoot.CFrame = CFrame.new(interpolatedPos) * CFrame.Angles(0, interpolatedRotY, 0)
    end)
end

local function stopPlayback()
    if playbackConnection then playbackConnection:Disconnect(); playbackConnection = nil end
    if ghostNpc then ghostNpc:Destroy(); ghostNpc = nil end

    statusLabel.Text = "Status: Siap"
    playButton.Text = "▶️ Putar Ulang"
    playButton.BackgroundColor3 = Color3.fromRGB(0, 200, 0)
    playButton.AutoButtonColor = loadedData and true or false -- Re-enable kalo ada data
    recordButton.AutoButtonColor = true -- Enable record lagi
    saveButton.AutoButtonColor = #recordedData > 0 and true or false -- Enable save kalo ada data rekaman baru
    loadButton.AutoButtonColor = true -- Enable load lagi
end

-- --- GUI Button Connections ---
recordButton.MouseButton1Click:Connect(function()
    if isRecording then
        stopRecording()
    else
        stopPlayback() -- Pastikan playback berhenti sebelum rekam
        startRecording()
    end
end)

saveButton.MouseButton1Click:Connect(function()
    if isRecording then return end -- Jangan simpan pas lagi rekam
    if #recordedData == 0 then statusLabel.Text = "Status: Tidak ada rekaman baru untuk disimpan."; return end

    local fileName = nameInput.Text
    if fileName == "" then fileName = DEFAULT_FILENAME end

    local success, msg = saveDataToFile(fileName, recordedData)
    if success then
        statusLabel.Text = "Status: Tersimpan ke '" .. fileName .. ".json'"
        recordedData = {} -- Kosongkan data rekaman saat ini setelah disimpan
        saveButton.AutoButtonColor = false -- Disable save lagi
    else
        statusLabel.Text = "Status: Gagal menyimpan! (" .. msg .. ")"
    end
end)

loadButton.MouseButton1Click:Connect(function()
    if isRecording then return end -- Jangan load pas lagi rekam
    stopPlayback() -- Stop playback yg mungkin jalan

    local fileName = nameInput.Text
    if fileName == "" then fileName = DEFAULT_FILENAME end

    local data = loadDataFromFile(fileName)
    if data then
        loadedData = data
        statusLabel.Text = "Status: '" .. fileName .. ".json' dimuat (" .. #loadedData .. " frame)."
        playButton.AutoButtonColor = true -- Enable tombol play
    else
        loadedData = nil
        statusLabel.Text = "Status: Gagal memuat '" .. fileName .. ".json'"
        playButton.AutoButtonColor = false -- Disable tombol play
    end
end)

playButton.MouseButton1Click:Connect(function()
    if not loadedData and not ghostNpc then -- Kalau tidak ada data DAN tidak ada ghost
        statusLabel.Text = "Status: Muat data rekaman dulu!"
        return
    end

    if ghostNpc then -- Kalau tombol ditekan pas playback jalan -> Stop
        stopPlayback()
    else -- Kalau tombol ditekan pas gak ada playback -> Start
        startPlayback()
    end
end)

-- --- Initialization ---
saveButton.AutoButtonColor = false -- Awalnya disable save
playButton.AutoButtonColor = false -- Awalnya disable play
