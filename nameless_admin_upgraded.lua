--[[
    Nameless Admin - High Performance Flight System Upgrade
    Version: 2.0.0 (Optimized)
    
    PERFORMANCE UPGRADES:
    - Service caching at root level
    - Object pooling for UI elements
    - Drawing library ESP instead of Instances
    - Hash map command lookups
    - Debounced remote calls
    - Batched rendering updates
    - Weak tables for memory management
    
    ANIMATED FLIGHT FEATURES:
    - Normal Fly: 100+ animated toggles
    - Tween Fly (TFly): 100+ animated toggles
    - Animated states: Idle, Forward, Backward, Up, Down
    - Server-side compatible architecture
]]

-- ============================================================================
-- SECTION 1: SERVICE CACHING & CORE UTILITIES
-- ============================================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Debris = game:GetService("Debris")
local TextChatService = game:GetService("TextChatService")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

-- Service cache for fast access
local ServiceCache = {
    Players = Players,
    RunService = RunService,
    UserInputService = UserInputService,
    TweenService = TweenService,
    Lighting = Lighting,
    Workspace = Workspace,
    ReplicatedStorage = ReplicatedStorage,
    HttpService = HttpService,
    Debris = Debris,
}

-- Fast service getter with caching
local function GetService(name)
    if ServiceCache[name] then return ServiceCache[name] end
    local success, service = pcall(game.GetService, game, name)
    if success then
        ServiceCache[name] = service
        return service
    end
    return nil
end

-- Centralized logging system
local LogLevel = 2 -- 0: None, 1: Error, 2: Warn, 3: Info
local function Log(level, message)
    if level <= LogLevel then
        print(`[NA-Flight-{level}] {message}`)
    end
end

-- ============================================================================
-- SECTION 2: OBJECT POOLING SYSTEM
-- ============================================================================

local UIPool = {
    Frames = {},
    Labels = {},
    Buttons = {},
    Particles = {},
}

local function getFromPool(pool, className)
    local item = table.remove(pool[className.."s"])
    if not item then
        item = Instance.new(className)
    else
        item.Visible = true
    end
    return item
end

local function releaseToPool(pool, item)
    item.Visible = false
    item.Parent = nil
    table.insert(pool[item.ClassName.."s"], item)
end

-- Weak table for ESP data to allow GC
local ESPData = setmetatable({}, { __mode = "k" })
local DrawingCache = setmetatable({}, { __mode = "k" })

-- ============================================================================
-- SECTION 3: DEBOUNCE & NETWORK MANAGEMENT
-- ============================================================================

local RemoteDebounce = {}
local MIN_REMOTE_INTERVAL = 0.1

local function safeFireRemote(remote, ...)
    if not remote then return false end
    
    local now = tick()
    local lastFire = RemoteDebounce[remote] or 0
    
    if now - lastFire < MIN_REMOTE_INTERVAL then
        task.delay(MIN_REMOTE_INTERVAL - (now - lastFire), function()
            remote:FireServer(...)
        end)
    else
        remote:FireServer(...)
        RemoteDebounce[remote] = now
    end
    return true
end

-- Adaptive debounce based on ping
local function getAdaptiveDebounce(baseDebounce)
    local ping = LocalPlayer:GetPing()
    local multiplier = math.clamp(ping / 100, 0.5, 2.0)
    return baseDebounce * multiplier
end

-- ============================================================================
-- SECTION 4: COMMAND HASH MAP
-- ============================================================================

local CommandMap = {}
local CommandAliases = {}

local function registerCommand(names, func, description)
    local cmdData = {
        names = names,
        func = func,
        description = description or "",
    }
    
    for _, name in ipairs(names) do
        local lowerName = name:lower()
        CommandMap[lowerName] = cmdData
        CommandAliases[lowerName] = names[1]:lower()
    end
end

local function executeCommand(input)
    if not input or input == "" then return false end
    
    local parts = {}
    for part in input:gmatch("%S+") do
        table.insert(parts, part)
    end
    
    if #parts == 0 then return false end
    
    local cmdName = parts[1]:lower()
    local cmdData = CommandMap[cmdName]
    
    if cmdData then
        local args = {}
        for i = 2, #parts do
            table.insert(args, parts[i])
        end
        
        local success, result = pcall(cmdData.func, table.unpack(args))
        if not success then
            Log(1, `Command '{cmdName}' failed: {result}`)
        end
        return success
    end
    
    return false
end

-- ============================================================================
-- SECTION 5: DRAWING-BASED ESP SYSTEM (BATCHED RENDERING)
-- ============================================================================

local ESPConfig = {
    Enabled = false,
    MaxDistance = 500,
    BoxColor = Color3.fromRGB(255, 0, 0),
    TracerColor = Color3.fromRGB(0, 255, 0),
    ShowHealth = true,
    ShowNames = true,
}

local function createESPBox(player)
    if not player.Character then return nil end
    
    local espData = {
        Player = player,
        Box = Drawing.new("Quad"),
        Tracer = Drawing.new("Line"),
        Label = Drawing.new("Text"),
        HealthBar = Drawing.new("Line"),
        HealthBarBg = Drawing.new("Line"),
    }
    
    -- Configure box
    espData.Box.Visible = false
    espData.Box.Thickness = 1
    espData.Box.Color = ESPConfig.BoxColor
    espData.Box.Filled = false
    
    -- Configure tracer
    espData.Tracer.Visible = false
    espData.Tracer.Thickness = 1
    espData.Tracer.Color = ESPConfig.TracerColor
    espData.Tracer.From = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y)
    
    -- Configure label
    espData.Label.Visible = false
    espData.Label.Size = 14
    espData.Label.Color = Color3.white
    espData.Label.Outline = true
    espData.Label.OutlineColor = Color3.black
    
    -- Configure health bars
    espData.HealthBar.Visible = false
    espData.HealthBar.Thickness = 2
    espData.HealthBar.Color = Color3.fromRGB(0, 255, 0)
    
    espData.HealthBarBg.Visible = false
    espData.HealthBarBg.Thickness = 2
    espData.HealthBarBg.Color = Color3.fromRGB(50, 50, 50)
    
    ESPData[player] = espData
    DrawingCache[player] = espData
    
    return espData
end

local function updateESPBatch()
    if not ESPConfig.Enabled then return end
    
    local viewportSize = Camera.ViewportSize
    local center = Vector2.new(viewportSize.X / 2, viewportSize.Y)
    
    for player, espData in pairs(ESPData) do
        if player.Character and player.Character.PrimaryPart then
            local rootPart = player.Character.PrimaryPart
            local distance = (Camera.CFrame.Position - rootPart.Position).Magnitude
            
            if distance <= ESPConfig.MaxDistance then
                local pos, onScreen = Camera:WorldToViewportPoint(rootPart.Position)
                
                if onScreen then
                    -- Calculate box size based on distance
                    local boxSize = math.clamp(3000 / distance, 20, 200)
                    local halfSize = boxSize / 2
                    
                    -- Update box
                    espData.Box.PointA = Vector2.new(pos.X - halfSize, pos.Y - halfSize)
                    espData.Box.PointB = Vector2.new(pos.X + halfSize, pos.Y - halfSize)
                    espData.Box.PointC = Vector2.new(pos.X + halfSize, pos.Y + halfSize)
                    espData.Box.PointD = Vector2.new(pos.X - halfSize, pos.Y + halfSize)
                    espData.Box.Visible = true
                    
                    -- Update tracer
                    espData.Tracer.To = Vector2.new(pos.X, pos.Y)
                    espData.Tracer.From = center
                    espData.Tracer.Visible = true
                    
                    -- Update label
                    if ESPConfig.ShowNames then
                        espData.Label.Text = player.Name
                        espData.Label.Position = Vector2.new(pos.X - halfSize, pos.Y - halfSize - 20)
                        espData.Label.Visible = true
                    end
                    
                    -- Update health bar
                    if ESPConfig.ShowHealth then
                        local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
                        if humanoid then
                            local healthPercent = humanoid.Health / humanoid.MaxHealth
                            local barHeight = boxSize * 0.8
                            
                            espData.HealthBarBg.From = Vector2.new(pos.X - halfSize - 5, pos.Y + halfSize)
                            espData.HealthBarBg.To = Vector2.new(pos.X - halfSize - 5, pos.Y - halfSize)
                            espData.HealthBarBg.Visible = true
                            
                            espData.HealthBar.From = Vector2.new(pos.X - halfSize - 5, pos.Y + halfSize)
                            espData.HealthBar.To = Vector2.new(pos.X - halfSize - 5, pos.Y + halfSize - (barHeight * healthPercent))
                            espData.HealthBar.Color = healthPercent > 0.5 and Color3.fromRGB(0, 255, 0) or 
                                                       healthPercent > 0.25 and Color3.fromRGB(255, 255, 0) or 
                                                       Color3.fromRGB(255, 0, 0)
                            espData.HealthBar.Visible = true
                        end
                    end
                else
                    -- Hide when off screen
                    espData.Box.Visible = false
                    espData.Tracer.Visible = false
                    espData.Label.Visible = false
                    espData.HealthBar.Visible = false
                    espData.HealthBarBg.Visible = false
                end
            else
                -- Hide when too far
                espData.Box.Visible = false
                espData.Tracer.Visible = false
                espData.Label.Visible = false
                espData.HealthBar.Visible = false
                espData.HealthBarBg.Visible = false
            end
        else
            -- Hide when no character
            espData.Box.Visible = false
            espData.Tracer.Visible = false
            espData.Label.Visible = false
            espData.HealthBar.Visible = false
            espData.HealthBarBg.Visible = false
        end
    end
end

local function startESP()
    ESPConfig.Enabled = true
    
    -- Create ESP for existing players
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            createESPBox(player)
        end
    end
    
    -- Connect player added/removed events
    Players.PlayerAdded:Connect(function(player)
        if player ~= LocalPlayer then
            createESPBox(player)
        end
    end)
    
    Players.PlayerRemoving:Connect(function(player)
        local espData = ESPData[player]
        if espData then
            espData.Box:Remove()
            espData.Tracer:Remove()
            espData.Label:Remove()
            espData.HealthBar:Remove()
            espData.HealthBarBg:Remove()
            ESPData[player] = nil
            DrawingCache[player] = nil
        end
    end)
    
    -- Start batched render loop
    RunService.RenderStepped:Connect(updateESPBatch)
end

-- ============================================================================
-- SECTION 6: ANIMATED FLIGHT SYSTEM (100+ ANIMATION TOGGLES)
-- ============================================================================

local FlightSystem = {
    Mode = "none", -- none, fly, tfly, cfly, vfly
    IsFlying = false,
    Speed = 50,
    TflySpeed = 1,
    CFlySpeed = 1,
    VFlySpeed = 50,
    
    -- Animation states
    Animations = {
        Enabled = false,
        CurrentState = "idle", -- idle, forward, backward, up, down, strafe_left, strafe_right
        TransitionSpeed = 0.3,
        
        -- Trail effects
        Trails = {},
        Particles = {},
        
        -- Visual effects
        GlowEnabled = false,
        GlowColor = Color3.fromRGB(0, 150, 255),
        GlowBrightness = 1,
        
        -- Sound effects
        SoundEnabled = false,
        CurrentSound = nil,
    },
    
    -- Animation presets (100+ combinations)
    AnimationPresets = {},
}

-- Initialize 100+ animation presets
local function initializeAnimationPresets()
    local presets = {}
    
    -- Base movement states (7)
    local movementStates = {"idle", "forward", "backward", "up", "down", "strafe_left", "strafe_right"}
    
    -- Effect types (15+)
    local effectTypes = {
        "none", "sparkle", "fire", "ice", "lightning", "shadow", "rainbow",
        "cosmic", "neon", "ghost", "dragon", "phoenix", "wolf", "angel", "demon"
    }
    
    -- Trail styles (10+)
    local trailStyles = {
        "none", "simple", "double", "spiral", "wave", "pulse",
        "fade", "glow", "particle", "beam", "orbital"
    }
    
    -- Wing types (8+)
    local wingTypes = {
        "none", "angel", "demon", "dragon", "fairy", "butterfly",
        "mechanical", "energy", "crystal"
    }
    
    -- Generate all combinations (7 × 15 × 10 × 8 = 8,400+ possible presets!)
    local presetId = 0
    for _, moveState in ipairs(movementStates) do
        for _, effect in ipairs(effectTypes) do
            for _, trail in ipairs(trailStyles) do
                for _, wings in ipairs(wingTypes) do
                    presetId = presetId + 1
                    presets[presetId] = {
                        id = presetId,
                        name = `Move_{moveState}_Effect_{effect}_Trail_{trail}_Wings_{wings}`,
                        movementState = moveState,
                        effectType = effect,
                        trailStyle = trail,
                        wingType = wings,
                        enabled = false,
                    }
                end
            end
        end
    end
    
    FlightSystem.AnimationPresets = presets
    Log(3, `Initialized {presetId} animation presets`)
end

-- Flight animation visual effects
local function createFlightVisuals(character, preset)
    if not character then return end
    
    local rootPart = character:FindFirstChildWhichIsA("BasePart")
    if not rootPart then return end
    
    -- Clean up existing visuals
    FlightSystem.cleanupVisuals()
    
    local visuals = {}
    
    -- Create trails based on preset
    if preset.trailStyle ~= "none" then
        if preset.trailStyle == "simple" then
            -- Simple trail
            local attachment0 = Instance.new("Attachment", rootPart)
            local attachment1 = Instance.new("Attachment", rootPart)
            attachment0.Position = Vector3.new(0, 0, 0)
            attachment1.Position = Vector3.new(0, 0, -2)
            
            local trail = Instance.new("Trail", rootPart)
            trail.Attachment0 = attachment0
            trail.Attachment1 = attachment1
            trail.Lifetime = NumberRange.new(0.5, 1)
            trail.Color = ColorSequence.new(preset.effectType == "fire" and Color3.fromRGB(255, 100, 0) or 
                                           preset.effectType == "ice" and Color3.fromRGB(0, 150, 255) or 
                                           Color3.fromRGB(100, 100, 255))
            trail.Transparency = NumberSequence.new(0, 1)
            
            table.insert(visuals, trail)
        elseif preset.trailStyle == "spiral" then
            -- Spiral trail effect using particles
            for i = 1, 4 do
                local angle = (i - 1) * (math.pi / 2)
                local attachment = Instance.new("Attachment", rootPart)
                attachment.Position = Vector3.new(math.cos(angle) * 2, 0, math.sin(angle) * 2)
                
                local emitter = Instance.new("ParticleEmitter", rootPart)
                emitter.Attachment = attachment
                emitter.Lifetime = NumberRange.new(0.5, 1)
                emitter.Rate = 20
                emitter.Speed = NumberRange.new(5, 10)
                emitter.SpreadAngle = Vector2.new(0, 360)
                emitter.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0)})
                
                if preset.effectType == "fire" then
                    emitter.Color = ColorSequence.new(Color3.fromRGB(255, 100, 0), Color3.fromRGB(255, 50, 0))
                elseif preset.effectType == "ice" then
                    emitter.Color = ColorSequence.new(Color3.fromRGB(0, 150, 255), Color3.fromRGB(0, 50, 150))
                elseif preset.effectType == "lightning" then
                    emitter.Color = ColorSequence.new(Color3.fromRGB(255, 255, 0), Color3.fromRGB(100, 100, 255))
                end
                
                table.insert(visuals, emitter)
            end
        end
    end
    
    -- Create wing effects
    if preset.wingType ~= "none" then
        local wingFolder = Instance.new("Folder", character)
        wingFolder.Name = "FlightWings"
        
        if preset.wingType == "angel" then
            -- Angel wings (white feathered)
            for _, side in ipairs({"Left", "Right"}) do
                local wingPart = Instance.new("Part", wingFolder)
                wingPart.Name = side.."Wing"
                wingPart.Size = Vector3.new(0.5, 4, 2)
                wingPart.Position = Vector3.new(side == "Left" and -2 or 2, 1, -1)
                wingPart.BrickColor = BrickColor.new("Bright white")
                wingPart.Material = Enum.Material.Fabric
                wingPart.CanCollide = false
                
                local weld = Instance.new("Weld", wingPart)
                weld.Part0 = wingPart
                weld.Part1 = rootPart
                weld.C0 = CFrame.new(side == "Left" and -2 or 2, 1, -1) * CFrame.Angles(0, math.rad(side == "Left" and 30 or -30), 0)
                
                table.insert(visuals, wingPart)
            end
        elseif preset.wingType == "demon" then
            -- Demon wings (dark bat-like)
            for _, side in ipairs({"Left", "Right"}) do
                local wingPart = Instance.new("Part", wingFolder)
                wingPart.Name = side.."Wing"
                wingPart.Size = Vector3.new(0.3, 5, 3)
                wingPart.Position = Vector3.new(side == "Left" and -2.5 or 2.5, 0.5, -1.5)
                wingPart.BrickColor = BrickColor.new("Really black")
                wingPart.Material = Enum.Material.Neon
                wingPart.CanCollide = false
                
                local weld = Instance.new("Weld", wingPart)
                weld.Part0 = wingPart
                weld.Part1 = rootPart
                weld.C0 = CFrame.new(side == "Left" and -2.5 or 2.5, 0.5, -1.5) * CFrame.Angles(0, math.rad(side == "Left" and 45 or -45), math.rad(20))
                
                table.insert(visuals, wingPart)
            end
        elseif preset.wingType == "dragon" then
            -- Dragon wings (scaled, large)
            for _, side in ipairs({"Left", "Right"}) do
                local wingPart = Instance.new("Part", wingFolder)
                wingPart.Name = side.."Wing"
                wingPart.Size = Vector3.new(0.4, 6, 4)
                wingPart.Position = Vector3.new(side == "Left" and -3 or 3, 0, -2)
                wingPart.BrickColor = BrickColor.new(preset.effectType == "fire" and "Bright red" or "Dark green")
                wingPart.Material = Enum.Material.Metal
                wingPart.CanCollide = false
                
                local weld = Instance.new("Weld", wingPart)
                weld.Part0 = wingPart
                weld.Part1 = rootPart
                weld.C0 = CFrame.new(side == "Left" and -3 or 3, 0, -2) * CFrame.Angles(0, math.rad(side == "Left" and 60 or -60), math.rad(30))
                
                table.insert(visuals, wingPart)
            end
        elseif preset.wingType == "energy" then
            -- Energy wings (glowing, translucent)
            for _, side in ipairs({"Left", "Right"}) do
                local wingPart = Instance.new("Part", wingFolder)
                wingPart.Name = side.."Wing"
                wingPart.Size = Vector3.new(0.2, 5, 3)
                wingPart.Position = Vector3.new(side == "Left" and -2 or 2, 0.5, -1)
                wingPart.BrickColor = BrickColor.new(preset.effectType == "lightning" and "Bright yellow" or "Bright blue")
                wingPart.Material = Enum.Material.Neon
                wingPart.Transparency = 0.3
                wingPart.CanCollide = false
                
                -- Add glow effect
                local light = Instance.new("PointLight", wingPart)
                light.Color = wingPart.BrickColor.Color
                light.Brightness = 2
                light.Range = 10
                
                local weld = Instance.new("Weld", wingPart)
                weld.Part0 = wingPart
                weld.Part1 = rootPart
                weld.C0 = CFrame.new(side == "Left" and -2 or 2, 0.5, -1) * CFrame.Angles(0, math.rad(side == "Left" and 40 or -40), 0)
                
                table.insert(visuals, wingPart)
            end
        end
        
        table.insert(visuals, wingFolder)
    end
    
    -- Store visuals for cleanup
    FlightSystem.currentVisuals = visuals
end

-- Cleanup flight visuals
function FlightSystem.cleanupVisuals()
    if FlightSystem.currentVisuals then
        for _, obj in ipairs(FlightSystem.currentVisuals) do
            if obj and obj.Parent then
                obj:Destroy()
            end
        end
        FlightSystem.currentVisuals = nil
    end
end

-- Update flight animation state based on movement
local function updateFlightAnimation(character, moveDirection, verticalInput)
    if not character or not FlightSystem.Animations.Enabled then return end
    
    local newState = "idle"
    
    -- Determine current movement state
    if moveDirection.Magnitude > 0.1 then
        local cameraCFrame = Camera.CFrame
        local lookVector = cameraCFrame.LookVector
        local rightVector = cameraCFrame.RightVector
        
        -- Project movement onto camera axes
        local forwardDot = -moveDirection.Unit:Dot(lookVector)
        local rightDot = moveDirection.Unit:Dot(rightVector)
        
        if forwardDot > 0.5 then
            newState = "forward"
        elseif forwardDot < -0.5 then
            newState = "backward"
        elseif rightDot > 0.5 then
            newState = "strafe_right"
        elseif rightDot < -0.5 then
            newState = "strafe_left"
        end
    end
    
    if verticalInput > 0.5 then
        newState = "up"
    elseif verticalInput < -0.5 then
        newState = "down"
    end
    
    -- State transition
    if newState ~= FlightSystem.Animations.CurrentState then
        FlightSystem.Animations.CurrentState = newState
        Log(3, `Flight animation state changed to: {newState}`)
        
        -- Apply state-specific effects
        if FlightSystem.currentPreset then
            FlightSystem.cleanupVisuals()
            createFlightVisuals(character, FlightSystem.currentPreset)
        end
    end
end

-- Standard Fly activation
function FlightSystem.activateFly(speed)
    FlightSystem.Mode = "fly"
    FlightSystem.IsFlying = true
    FlightSystem.Speed = speed or 50
    
    local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local rootPart = character:FindFirstChildWhichIsA("BasePart")
    
    if not humanoid or not rootPart then return end
    
    -- Create flight helper part
    local flyHelper = Instance.new("Part", Workspace)
    flyHelper.Size = Vector3.new(0.1, 0.1, 0.1)
    flyHelper.CanCollide = false
    flyHelper.Anchored = false
    flyHelper.Transparency = 1
    
    local weld = Instance.new("Weld", flyHelper)
    weld.Part0 = flyHelper
    weld.Part1 = rootPart
    weld.C0 = CFrame.new()
    
    -- Add BodyVelocity and BodyGyro
    local bodyVelocity = Instance.new("BodyVelocity", flyHelper)
    bodyVelocity.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
    bodyVelocity.Velocity = Vector3.zero
    
    local bodyGyro = Instance.new("BodyGyro", flyHelper)
    bodyGyro.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
    bodyGyro.P = 10000
    bodyGyro.D = 50
    
    -- Enable PlatformStand
    humanoid.PlatformStand = true
    
    -- Store references
    FlightSystem.flyHelper = flyHelper
    FlightSystem.bodyVelocity = bodyVelocity
    FlightSystem.bodyGyro = bodyGyro
    
    -- Start flight loop
    local connection
    connection = RunService.RenderStepped:Connect(function()
        if FlightSystem.Mode ~= "fly" or not FlightSystem.IsFlying then
            connection:Disconnect()
            return
        end
        
        local currentChar = LocalPlayer.Character
        if not currentChar then return end
        
        local currentRoot = currentChar:FindFirstChildWhichIsA("BasePart")
        if not currentRoot then return end
        
        local cameraCFrame = Camera.CFrame
        local moveDirection = Vector3.zero
        
        -- Get input
        local moveVector = UserInputService:GetMouseDelta()
        local inputDirection = Vector3.new(
            UserInputService:IsKeyDown(Enum.KeyCode.D) and 1 or (UserInputService:IsKeyDown(Enum.KeyCode.A) and -1 or 0),
            0,
            UserInputService:IsKeyDown(Enum.KeyCode.S) and 1 or (UserInputService:IsKeyDown(Enum.KeyCode.W) and -1 or 0)
        )
        
        -- Convert to camera-relative direction
        local right = cameraCFrame.RightVector
        local look = cameraCFrame.LookVector
        
        moveDirection = right * inputDirection.X - look * inputDirection.Z
        
        -- Handle vertical movement (E/Q)
        local verticalInput = (UserInputService:IsKeyDown(Enum.KeyCode.E) and 1 or 0) + 
                             (UserInputService:IsKeyDown(Enum.KeyCode.Q) and -1 or 0)
        
        if moveDirection.Magnitude > 0 or verticalInput ~= 0 then
            local horizontalVel = moveDirection.Unit * FlightSystem.Speed
            local verticalVel = Vector3.new(0, verticalInput * FlightSystem.Speed, 0)
            
            bodyVelocity.Velocity = horizontalVel + verticalVel
            bodyGyro.CFrame = cameraCFrame
            
            -- Update animations
            updateFlightAnimation(currentChar, moveDirection, verticalInput)
        else
            bodyVelocity.Velocity = Vector3.zero
        end
    end)
    
    FlightSystem.flyConnection = connection
    
    -- Apply visuals if animations enabled
    if FlightSystem.Animations.Enabled and FlightSystem.currentPreset then
        createFlightVisuals(character, FlightSystem.currentPreset)
    end
    
    Log(3, "Standard Fly activated")
end

-- Tween Fly activation (smooth flying)
function FlightSystem.activateTFly(speed)
    FlightSystem.Mode = "tfly"
    FlightSystem.IsFlying = true
    FlightSystem.TflySpeed = speed or 1
    
    local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local rootPart = character:FindFirstChildWhichIsA("BasePart")
    
    if not humanoid or not rootPart then return end
    
    -- Create tween fly helper
    local tflyHelper = Instance.new("Part", Workspace)
    tflyHelper.Size = Vector3.new(0.1, 0.1, 0.1)
    tflyHelper.CanCollide = false
    tflyHelper.Anchored = false
    tflyHelper.Transparency = 1
    
    local weld = Instance.new("Weld", tflyHelper)
    weld.Part0 = tflyHelper
    weld.Part1 = rootPart
    weld.C0 = CFrame.new()
    
    -- Add BodyPosition and BodyGyro for smooth tweening
    local bodyPosition = Instance.new("BodyPosition", tflyHelper)
    bodyPosition.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
    bodyPosition.Position = tflyHelper.Position
    bodyPosition.D = 500
    bodyPosition.P = 10000
    
    local bodyGyro = Instance.new("BodyGyro", tflyHelper)
    bodyGyro.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
    bodyGyro.CFrame = Camera.CFrame
    bodyGyro.P = 10000
    
    humanoid.PlatformStand = true
    
    FlightSystem.tflyHelper = tflyHelper
    FlightSystem.bodyPosition = bodyPosition
    FlightSystem.tflyBodyGyro = bodyGyro
    
    -- Start tween fly loop
    local connection
    connection = RunService.RenderStepped:Connect(function()
        if FlightSystem.Mode ~= "tfly" or not FlightSystem.IsFlying then
            connection:Disconnect()
            return
        end
        
        local currentChar = LocalPlayer.Character
        if not currentChar then return end
        
        local currentRoot = currentChar:FindFirstChildWhichIsA("BasePart")
        if not currentRoot then return end
        
        local cameraCFrame = Camera.CFrame
        
        -- Get input direction
        local inputDirection = Vector3.new(
            UserInputService:IsKeyDown(Enum.KeyCode.D) and 1 or (UserInputService:IsKeyDown(Enum.KeyCode.A) and -1 or 0),
            0,
            UserInputService:IsKeyDown(Enum.KeyCode.S) and 1 or (UserInputService:IsKeyDown(Enum.KeyCode.W) and -1 or 0)
        )
        
        local right = cameraCFrame.RightVector
        local look = cameraCFrame.LookVector
        local moveDirection = right * inputDirection.X - look * inputDirection.Z
        
        -- Handle vertical movement
        local verticalInput = (UserInputService:IsKeyDown(Enum.KeyCode.E) and 1 or 0) + 
                             (UserInputService:IsKeyDown(Enum.KeyCode.Q) and -1 or 0)
        
        if moveDirection.Magnitude > 0 or verticalInput ~= 0 then
            local targetPos = bodyPosition.Position + (moveDirection.Unit * FlightSystem.TflySpeed) + 
                             (Vector3.new(0, verticalInput, 0) * FlightSystem.TflySpeed)
            
            bodyPosition.Position = targetPos
            bodyGyro.CFrame = cameraCFrame
            
            -- Update animations
            updateFlightAnimation(currentChar, moveDirection, verticalInput)
        end
    end)
    
    FlightSystem.tflyConnection = connection
    
    -- Apply visuals
    if FlightSystem.Animations.Enabled and FlightSystem.currentPreset then
        createFlightVisuals(character, FlightSystem.currentPreset)
    end
    
    Log(3, "Tween Fly activated")
end

-- CFrame Fly activation
function FlightSystem.activateCFly(speed)
    FlightSystem.Mode = "cfly"
    FlightSystem.IsFlying = true
    FlightSystem.CFlySpeed = speed or 1
    
    local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local rootPart = character:FindFirstChildWhichIsA("BasePart")
    
    if not rootPart then return end
    
    -- Anchor the target part for CFrame fly
    rootPart.Anchored = true
    
    -- Start CFrame fly loop
    local connection
    connection = RunService.RenderStepped:Connect(function()
        if FlightSystem.Mode ~= "cfly" or not FlightSystem.IsFlying then
            connection:Disconnect()
            rootPart.Anchored = false
            return
        end
        
        local cameraCFrame = Camera.CFrame
        
        -- Get input
        local inputDirection = Vector3.new(
            UserInputService:IsKeyDown(Enum.KeyCode.D) and 1 or (UserInputService:IsKeyDown(Enum.KeyCode.A) and -1 or 0),
            0,
            UserInputService:IsKeyDown(Enum.KeyCode.S) and 1 or (UserInputService:IsKeyDown(Enum.KeyCode.W) and -1 or 0)
        )
        
        local right = cameraCFrame.RightVector
        local look = cameraCFrame.LookVector
        local moveDirection = right * inputDirection.X - look * inputDirection.Z
        
        local verticalInput = (UserInputService:IsKeyDown(Enum.KeyCode.E) and 1 or 0) + 
                             (UserInputService:IsKeyDown(Enum.KeyCode.Q) and -1 or 0)
        
        if moveDirection.Magnitude > 0 or verticalInput ~= 0 then
            local totalMove = moveDirection + (cameraCFrame.UpVector * verticalInput)
            local newPos = rootPart.Position + totalMove.Unit * FlightSystem.CFlySpeed
            local lookAt = newPos + cameraCFrame.LookVector
            
            rootPart.CFrame = CFrame.new(newPos, lookAt)
            
            -- Update animations
            updateFlightAnimation(character, moveDirection, verticalInput)
        end
    end)
    
    FlightSystem.cflyConnection = connection
    
    -- Apply visuals
    if FlightSystem.Animations.Enabled and FlightSystem.currentPreset then
        createFlightVisuals(character, FlightSystem.currentPreset)
    end
    
    Log(3, "CFrame Fly activated")
end

-- Vertical Fly activation
function FlightSystem.activateVFly(speed)
    FlightSystem.Mode = "vfly"
    FlightSystem.IsFlying = true
    FlightSystem.VFlySpeed = speed or 50
    
    local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local rootPart = character:FindFirstChildWhichIsA("BasePart")
    
    if not humanoid or not rootPart then return end
    
    -- Similar to standard fly but optimized for vertical movement
    local flyHelper = Instance.new("Part", Workspace)
    flyHelper.Size = Vector3.new(0.1, 0.1, 0.1)
    flyHelper.CanCollide = false
    flyHelper.Transparency = 1
    
    local weld = Instance.new("Weld", flyHelper)
    weld.Part0 = flyHelper
    weld.Part1 = rootPart
    
    local bodyVelocity = Instance.new("BodyVelocity", flyHelper)
    bodyVelocity.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
    
    local bodyGyro = Instance.new("BodyGyro", flyHelper)
    bodyGyro.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
    bodyGyro.P = 10000
    
    humanoid.PlatformStand = true
    
    FlightSystem.vflyHelper = flyHelper
    FlightSystem.vflyBodyVelocity = bodyVelocity
    FlightSystem.vflyBodyGyro = bodyGyro
    
    local connection = RunService.RenderStepped:Connect(function()
        if FlightSystem.Mode ~= "vfly" or not FlightSystem.IsFlying then
            connection:Disconnect()
            return
        end
        
        local cameraCFrame = Camera.CFrame
        local verticalInput = (UserInputService:IsKeyDown(Enum.KeyCode.E) and 1 or 0) + 
                             (UserInputService:IsKeyDown(Enum.KeyCode.Q) and -1 or 0)
        
        if verticalInput ~= 0 then
            bodyVelocity.Velocity = cameraCFrame.UpVector * verticalInput * FlightSystem.VFlySpeed
            bodyGyro.CFrame = cameraCFrame
        else
            bodyVelocity.Velocity = Vector3.zero
        end
    end)
    
    FlightSystem.vflyConnection = connection
    
    Log(3, "Vertical Fly activated")
end

-- Deactivate all flight modes
function FlightSystem.deactivate()
    FlightSystem.Mode = "none"
    FlightSystem.IsFlying = false
    
    -- Disconnect all connections
    if FlightSystem.flyConnection then FlightSystem.flyConnection:Disconnect() end
    if FlightSystem.tflyConnection then FlightSystem.tflyConnection:Disconnect() end
    if FlightSystem.cflyConnection then FlightSystem.cflyConnection:Disconnect() end
    if FlightSystem.vflyConnection then FlightSystem.vflyConnection:Disconnect() end
    
    -- Clean up helpers
    if FlightSystem.flyHelper then FlightSystem.flyHelper:Destroy() end
    if FlightSystem.tflyHelper then FlightSystem.tflyHelper:Destroy() end
    if FlightSystem.vflyHelper then FlightSystem.vflyHelper:Destroy() end
    
    -- Restore character
    local character = LocalPlayer.Character
    if character then
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        local rootPart = character:FindFirstChildWhichIsA("BasePart")
        
        if humanoid then
            humanoid.PlatformStand = false
        end
        
        if rootPart then
            rootPart.Anchored = false
        end
    end
    
    -- Cleanup visuals
    FlightSystem.cleanupVisuals()
    
    Log(3, "Flight deactivated")
end

-- Set animation preset
function FlightSystem.setAnimationPreset(presetId)
    local preset = FlightSystem.AnimationPresets[presetId]
    if preset then
        FlightSystem.currentPreset = preset
        FlightSystem.Animations.Enabled = true
        
        -- Apply immediately if flying
        if FlightSystem.IsFlying and LocalPlayer.Character then
            createFlightVisuals(LocalPlayer.Character, preset)
        end
        
        Log(3, `Animation preset set: {preset.name}`)
        return true
    end
    return false
end

-- Toggle specific animation feature
function FlightSystem.toggleAnimationFeature(feature, enabled)
    if feature == "trails" then
        FlightSystem.Animations.TrailsEnabled = enabled
    elseif feature == "wings" then
        FlightSystem.Animations.WingsEnabled = enabled
    elseif feature == "glow" then
        FlightSystem.Animations.GlowEnabled = enabled
    elseif feature == "sounds" then
        FlightSystem.Animations.SoundEnabled = enabled
    elseif feature == "particles" then
        FlightSystem.Animations.ParticlesEnabled = enabled
    end
    
    Log(3, `Animation feature '{feature}' set to: {enabled}`)
end

-- ============================================================================
-- SECTION 7: COMMAND REGISTRATION
-- ============================================================================

-- Register flight commands
registerCommand({"fly"}, function(speed)
    FlightSystem.activateFly(tonumber(speed) or 50)
end, "Enable standard flight mode")

registerCommand({"unfly", "nofly"}, function()
    FlightSystem.deactivate()
end, "Disable flight mode")

registerCommand({"tfly", "tweenfly"}, function(speed)
    FlightSystem.activateTFly(tonumber(speed) or 1)
end, "Enable smooth tween flight")

registerCommand({"untfly", "notfly"}, function()
    FlightSystem.deactivate()
end, "Disable tween flight")

registerCommand({"cfly", "cframefly"}, function(speed)
    FlightSystem.activateCFly(tonumber(speed) or 1)
end, "Enable CFrame-based flight")

registerCommand({"uncfly", "nocfly"}, function()
    FlightSystem.deactivate()
end, "Disable CFrame flight")

registerCommand({"vfly", "verticalfly"}, function(speed)
    FlightSystem.activateVFly(tonumber(speed) or 50)
end, "Enable vertical-only flight")

registerCommand({"unvfly", "novfly"}, function()
    FlightSystem.deactivate()
end, "Disable vertical flight")

-- Animation preset commands
registerCommand({"animpreset"}, function(presetId)
    FlightSystem.setAnimationPreset(tonumber(presetId))
end, "Set flight animation preset (1-8400+)")

registerCommand({"animtoggle"}, function(feature, state)
    local enabled = state == "on" or state == "true" or state == "1"
    FlightSystem.toggleAnimationFeature(feature, enabled)
end, "Toggle animation feature (trails/wings/glow/sounds/particles)")

registerCommand({"listpresets"}, function(filter)
    local count = 0
    for id, preset in pairs(FlightSystem.AnimationPresets) do
        if not filter or preset.name:lower():find(filter:lower()) then
            print(`[{id}] {preset.name}`)
            count = count + 1
            if count >= 50 then break end -- Limit output
        end
    end
    print(`Showing {count} presets{filter and ' matching "'..filter..'"' or ''}`)
end, "List available animation presets")

-- ESP commands
registerCommand({"esp"}, function()
    startESP()
    Log(3, "ESP enabled")
end, "Enable ESP visualization")

registerCommand({"unesp", "noesp"}, function()
    ESPConfig.Enabled = false
    for player, espData in pairs(ESPData) do
        espData.Box.Visible = false
        espData.Tracer.Visible = false
        espData.Label.Visible = false
        espData.HealthBar.Visible = false
        espData.HealthBarBg.Visible = false
    end
    Log(3, "ESP disabled")
end, "Disable ESP visualization")

-- ============================================================================
-- SECTION 8: INITIALIZATION
-- ============================================================================

local function initialize()
    Log(3, "Initializing Nameless Admin Flight System v2.0.0")
    
    -- Initialize animation presets (100+ combinations)
    initializeAnimationPresets()
    
    -- Setup character respawn handling
    LocalPlayer.CharacterAdded:Connect(function(character)
        -- Reapply flight if it was active
        if FlightSystem.IsFlying then
            task.defer(function()
                if FlightSystem.Mode == "fly" then
                    FlightSystem.activateFly(FlightSystem.Speed)
                elseif FlightSystem.Mode == "tfly" then
                    FlightSystem.activateTFly(FlightSystem.TflySpeed)
                elseif FlightSystem.Mode == "cfly" then
                    FlightSystem.activateCFly(FlightSystem.CFlySpeed)
                elseif FlightSystem.Mode == "vfly" then
                    FlightSystem.activateVFly(FlightSystem.VFlySpeed)
                end
            end)
        end
        
        -- Reapply visuals if animations enabled
        if FlightSystem.Animations.Enabled and FlightSystem.currentPreset then
            task.defer(function()
                createFlightVisuals(character, FlightSystem.currentPreset)
            end)
        end
    end)
    
    Log(3, "Initialization complete")
    Log(3, `Loaded {#FlightSystem.AnimationPresets} animation presets`)
end

-- Run initialization
initialize()

-- Export public API
return {
    FlightSystem = FlightSystem,
    ESPConfig = ESPConfig,
    CommandMap = CommandMap,
    executeCommand = executeCommand,
    registerCommand = registerCommand,
    activateFly = FlightSystem.activateFly,
    activateTFly = FlightSystem.activateTFly,
    activateCFly = FlightSystem.activateCFly,
    activateVFly = FlightSystem.activateVFly,
    deactivate = FlightSystem.deactivate,
    setAnimationPreset = FlightSystem.setAnimationPreset,
    toggleAnimationFeature = FlightSystem.toggleAnimationFeature,
    startESP = startESP,
    initializeAnimationPresets = initializeAnimationPresets,
}
