-- AutoWalkSystem_JSON.lua
-- Works locally (executor only): record, play, save as JSON, load from JSON
-- Press F = Start/Stop Record | P = Play | L = Clear

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
if not player then
    warn("[AutoWalkSystem] Must run as LocalScript or executor.")
    return
end

-- === CONFIG ===
local SAMPLE_RATE = 60
local SAVE_PATH = "checkpoint_"
local isRecording = false
local isPlaying = false
local timeline = {}
local recConn
local recStart = 0
local ghostModel
local playIndex = 1
local playStart = 0
local recordingCount = 0

-- === UTILS ===
local function info(msg)
    print("[AutoWalkSystem] " .. msg)
end

local function getCharacter()
    local ch = player.Character or player.CharacterAdded:Wait()
    ch:WaitForChild("HumanoidRootPart")
    return ch
end

local function stripScripts(model)
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("Script") or d:IsA("LocalScript") then
            d:Destroy()
        end
    end
end

local function makeGhost(char)
    if ghostModel then ghostModel:Destroy() end
    local clone = char:Clone()
    stripScripts(clone)
    local hum = clone:FindFirstChildOfClass("Humanoid")
    if hum then hum:Destroy() end
    for _, p in ipairs(clone:GetDescendants()) do
        if p:IsA("BasePart") then
            p.Anchored = true
            p.CanCollide = false
            p.Color = Color3.fromRGB(0, 200, 255)
            p.Transparency = 0.4
        end
    end
    clone.Parent = workspace
    clone.Name = "Ghost_" .. player.Name
    ghostModel = clone
    return clone
end

local function saveRecordingToJSON(name)
    if #timeline < 2 then
        info("No data to save.")
        return
    end
    local data = {}
    for _, v in ipairs(timeline) do
        table.insert(data, {
            t = v.t,
            cf = {
                X = v.cf.X, Y = v.cf.Y, Z = v.cf.Z,
                R00 = v.cf.R00, R01 = v.cf.R01, R02 = v.cf.R02,
                R10 = v.cf.R10, R11 = v.cf.R11, R12 = v.cf.R12,
                R20 = v.cf.R20, R21 = v.cf.R21, R22 = v.cf.R22
            }
        })
    end
    local json = HttpService:JSONEncode(data)
    local filename = SAVE_PATH .. tostring(name) .. ".json"
    writefile(filename, json)
    info("Saved recording to " .. filename)
end

local function loadRecordingFromJSON(name)
    local filename = SAVE_PATH .. tostring(name) .. ".json"
    if not isfile(filename) then
        info("File not found: " .. filename)
        return
    end
    local json = readfile(filename)
    local data = HttpService:JSONDecode(json)
    timeline = {}
    for _, v in ipairs(data) do
        local cf = CFrame.new(
            v.cf.X, v.cf.Y, v.cf.Z,
            v.cf.R00, v.cf.R01, v.cf.R02,
            v.cf.R10, v.cf.R11, v.cf.R12,
            v.cf.R20, v.cf.R21, v.cf.R22
        )
        table.insert(timeline, { t = v.t, cf = cf })
    end
    info("Loaded " .. filename .. " (" .. tostring(#timeline) .. " frames)")
end

-- === RECORDING ===
local function startRecording()
    if isPlaying then return end
    local char = getCharacter()
    local hrp = char:WaitForChild("HumanoidRootPart")
    timeline = {}
    isRecording = true
    recStart = tick()
    info("Recording started...")

    if recConn then recConn:Disconnect() end
    recConn = RunService.Heartbeat:Connect(function()
        if not isRecording then return end
        table.insert(timeline, { t = tick() - recStart, cf = hrp.CFrame })
    end)
end

local function stopRecording()
    if not isRecording then return end
    isRecording = false
    if recConn then recConn:Disconnect() end
    recordingCount += 1
    info("Recording stopped (" .. tostring(#timeline) .. " frames).")
    saveRecordingToJSON(recordingCount)
end

-- === PLAYBACK ===
local function playRecording()
    if #timeline < 2 then
        info("No recording loaded.")
        return
    end
    if isPlaying then
        info("Already playing.")
        return
    end
    local char = getCharacter()
    local ghost = makeGhost(char)
    ghost:PivotTo(timeline[1].cf)
    isPlaying = true
    playStart = tick()
    playIndex = 1
    info("Playback started...")

    local conn
    conn = RunService.Heartbeat:Connect(function()
        if not isPlaying then conn:Disconnect() return end
        local elapsed = tick() - playStart
        if elapsed >= timeline[#timeline].t then
            ghost:PivotTo(timeline[#timeline].cf)
            info("Playback finished.")
            isPlaying = false
            conn:Disconnect()
            return
        end
        while playIndex < #timeline and timeline[playIndex + 1].t < elapsed do
            playIndex += 1
        end
        local a = timeline[playIndex]
        local b = timeline[playIndex + 1]
        if not (a and b) then return end
        local alpha = (elapsed - a.t) / (b.t - a.t)
        ghost:PivotTo(a.cf:Lerp(b.cf, alpha))
    end)
end

-- === CLEAR ===
local function clearAll()
    timeline = {}
    if ghostModel then ghostModel:Destroy() end
    ghostModel = nil
    isPlaying = false
    isRecording = false
    info("Cleared timeline.")
end

-- === INPUT BINDINGS ===
UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == Enum.KeyCode.F then
        if isRecording then
            stopRecording()
        else
            startRecording()
        end
    elseif input.KeyCode == Enum.KeyCode.P then
        playRecording()
    elseif input.KeyCode == Enum.KeyCode.L then
        clearAll()
    end
end)

info("AutoWalkSystem_JSON loaded. [F]=Record, [P]=Play, [L]=Clear")
info("Each recording will save as checkpoint_#.json automatically.")
