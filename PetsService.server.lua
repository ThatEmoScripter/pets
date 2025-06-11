-- Import necessary services at the top
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

-- Import required modules using their name as the variable
local PetMovementReplication = require(ReplicatedStorage.Modules.PetMovementReplication)

-- Define constants
local BASEBEHINDDISTANCE = 6
local BEHINDDISTANCEINTERVAL = 6
local PETATTACKCOOLDOWN = 12
local BASEDAMAGE = 0.25
local MAXATTACKDISTANCE = 35

-- Notifications for client
local missedNotification = "You clicked too far! Try again :D"
local inOwnCircleNotification = "Get out of your own attack zone, silly!!!"

-- Create RemoteEvents and RemoteFunctions
local petClickedEvent = Instance.new("RemoteEvent")
petClickedEvent.Name = "PetClicked"
petClickedEvent.Parent = ReplicatedStorage

local updatePhysicsEvent = Instance.new("RemoteEvent")
updatePhysicsEvent.Name = "UpdatePhysics"
updatePhysicsEvent.Parent = ReplicatedStorage

local getMouseHit = Instance.new("RemoteFunction")
getMouseHit.Name = "GetMouseHit"
getMouseHit.Parent = ReplicatedStorage

local notify = Instance.new("RemoteEvent")
notify.Name = "Notify" 
notify.Parent = ReplicatedStorage

-- Attack Indicator
local AttackIndicator = ReplicatedStorage:FindFirstChild("AttackIndicator")

-- Function to get touching parts of a given part
local function GetTouchingParts(part)
    local connection = part.Touched:Connect(function() end)
    local results = part:GetTouchingParts()
    connection:Disconnect()
    return results
end

-- Function to handle the pet attack scene
function petAttackScene(player, centerPoint, petFolder, indicator)
    if player:GetAttribute("AttackScene") then return end 
    player:SetAttribute("AttackScene", true)
    local numBounces = 6 -- Number of bounces
    indicator:FindFirstChild("AttackingParticle", true).Enabled = true

    for _, petObject in pairs(petFolder:GetChildren()) do
        petObject.CanCollide = false -- Temporarily disabling collisions so they dont spazz each other / targets out during the jumps.
        coroutine.wrap(function()
            local originalPosition = petObject.Position

            local jumpHeight = 5 
            local jumpDuration = 0.2 
            local landDuration = 0.1 

            for i = 1, numBounces do
                -- Jump animation
                local petJumpingInfo = TweenInfo.new(jumpDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
                local goalJump = {Position = Vector3.new(centerPoint.X, originalPosition.Y + jumpHeight, centerPoint.Z)}
                local tweenJump = TweenService:Create(petObject, petJumpingInfo, goalJump)
                tweenJump:Play()
                tweenJump.Completed:Wait()

                -- Landing animation
                local petLandingInfo = TweenInfo.new(landDuration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
                local goalLand = {Position = Vector3.new(centerPoint.X, originalPosition.Y, centerPoint.Z)}
                local tweenLand = TweenService:Create(petObject, petLandingInfo, goalLand)
                tweenLand:Play()
                tweenLand.Completed:Wait()

                -- Deal damage when landing on the center
                task.wait(0.15)  -- Wait a bit for stability after landing

                local hitbox = indicator:FindFirstChild("Hitbox")
                if hitbox then
                    local touchingParts = GetTouchingParts(hitbox)
                    for _, part in pairs(touchingParts) do
                        local character = part:FindFirstAncestorWhichIsA("Model")
                        if character == player.Character then 
                            notify:FireClient(player, inOwnCircleNotification)
                            continue end 
                        local humanoid = character:FindFirstChildWhichIsA("Humanoid")
                        if humanoid then
                            humanoid:TakeDamage(BASEDAMAGE) -- Deal minor damage
                        end
                    end
                end

                task.wait(0.15)  -- Small delay before returning to original position

                -- Return animation
                local tweenInfoReturn = TweenInfo.new(jumpDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
                local goalReturn = {Position = originalPosition}
                local tweenReturn = TweenService:Create(petObject, tweenInfoReturn, goalReturn)
                tweenReturn:Play()
                tweenReturn.Completed:Wait()

                if i < numBounces then
                    task.wait(0.5 + math.random() * 1) -- Random wait before next jump
                end
            end
        end)()
    end
end

-- Function to create pet attack
function createPetAttack(player, mouseHit)
    if player:GetAttribute("PetsAttacking") then return end
    player:SetAttribute("PetsAttacking", true)
    local effect = AttackIndicator:Clone()
    effect.Position = mouseHit
    effect.Parent = workspace

    local petsFolder = workspace:FindFirstChild(player.Name .. "Pets")
    local numPets = #petsFolder:GetChildren()

    for i, petObject in pairs(petsFolder:GetChildren()) do 
        -- Calculate angle for each pet to position them on a circle
        local angle = (i - 1) * (2 * math.pi / numPets)
        local x_offset = 5 * math.cos(angle)
        local z_offset = 5 * math.sin(angle)

        local path = PathfindingService:CreatePath({
            AgentCanJump = true,
            AgentRadius = 1.5,
            AgentHeight = 5,
            AgentCanWalkOnWater = false,
            WaypointSpacing = .5
        })
        petObject.CFrame = CFrame.new(petObject.Position, mouseHit)

        path:ComputeAsync(petObject.Position, mouseHit + Vector3.new(x_offset, 0, z_offset))
        local waypoints = path:GetWaypoints()

        if #waypoints > 0 then
            coroutine.wrap(function()
                task.wait(PETATTACKCOOLDOWN)
                player:SetAttribute("AttackScene", nil)
                player:SetAttribute("PetsAttacking", nil)
                effect:Destroy()
                for _,pet in pairs(petsFolder) do 
                    pet.CanCollide = true -- Re-enabling collisions from when I turned them off for the pet attack scene
                end
            end)()

            coroutine.wrap(function()
                for _, waypoint in ipairs(waypoints) do
                    local s = petObject:GetAttribute("Speed") or .1
                    if not player.Character or not player.Character.PrimaryPart then break end

                    local root = player.Character.HumanoidRootPart
                    local targetCFrame = CFrame.new(waypoint.Position + Vector3.new(x_offset, 0, z_offset))
                    local stepCFrame = petObject.CFrame:Lerp(targetCFrame, .1)
                    local cf = CFrame.new(stepCFrame.Position, mouseHit)
                    petObject.CFrame = targetCFrame
                    petObject:SetAttribute("OP", targetCFrame.Position)
                    RunService.Heartbeat:Wait()
                end

                -- Check if all pets have finished their attack sequence
                if i == numPets then
                    petAttackScene(player, mouseHit, petsFolder, effect)
                end
            end)()
        end
    end 
end

-- Function to handle player tool activation
function handlePlayerTool(player)
    local function characterAdded(character)
        local tool = player.Backpack:WaitForChild("Click To Make Pets Attack")
        tool.Activated:Connect(function()
            local hit = getMouseHit:InvokeClient(player)
            if (hit - character.PrimaryPart.Position).Magnitude < MAXATTACKDISTANCE then 
                createPetAttack(player, hit) -- If under the maximum distance, start the attack by sending the pets around the circle via this func
            else 
                notify:FireClient(player, missedNotification) -- Send the missedNotification text to the player's UI through the already-coded notifications!
            end
        end)
    end 

    local getCharacter = player.Character or player.CharacterAdded:Wait()
    characterAdded(getCharacter)
    player.CharacterAdded:Connect(characterAdded)
end

-- Handle pet movement updates
local function handleMovementUpdates(player, petObject)
    PetMovementReplication.server:sendUpdate(petObject.Name, player.Name .. "Pets", petObject.CFrame) -- Initialize positions on spawn
    petObject:GetPropertyChangedSignal("CFrame"):Connect(function()
        PetMovementReplication.server:sendUpdate(petObject.Name, player.Name .. "Pets", petObject.CFrame)
    end)
end 

-- Function to handle player addition
function OnPlayerAdded(player)
    local folder = workspace:FindFirstChild(player.Name .. "Pets") or Instance.new("Folder")
    folder.Name = player.Name .. "Pets"
    folder.Parent = workspace
    handlePlayerTool(player)
end

-- Connect events
Players.PlayerAdded:Connect(OnPlayerAdded)

-- Handle RemoteEvent from client
petClickedEvent.OnServerEvent:Connect(function(player, petName)
    local hit = getMouseHit:InvokeClient(player) -- Adding this check to make sure you can't spawn pets too far, and if they are too far send missed noti.
    if (hit-player.Character.PrimaryPart.Position).Magnitude > MAXATTACKDISTANCE then notify:FireClient(player,missedNotification) return end 
    
    -- Clone the pet's base part and set up pathfinding
    local petsFolder = ReplicatedStorage.Pets
    local petPart = petsFolder:FindFirstChild(petName)
    
    if petPart then

        local clonedPetPart = petPart:Clone()

        if (#workspace:FindFirstChild(player.Name.."Pets"):GetChildren()) > 6 then return end

        -- Set initial position near player and slightly above ground
        local newRandomName = "Pet_" .. player.Name .. "_" .. os.time()..clonedPetPart.Name
        clonedPetPart.Name = newRandomName
        clonedPetPart.Position = getMouseHit:InvokeClient(player)
        clonedPetPart.Transparency = 1
        clonedPetPart.Parent = workspace:FindFirstChild(player.Name.."Pets")
        
        if not player:GetAttribute("BehindDistance") then 
            player:SetAttribute("BehindDistance", BASEBEHINDDISTANCE) 
        end 

        clonedPetPart:SetAttribute("BehindDistance", player:GetAttribute("BehindDistance"))
        player:SetAttribute("BehindDistance", player:GetAttribute("BehindDistance") + BEHINDDISTANCEINTERVAL)
        handleMovementUpdates(player, clonedPetPart)

        -- Set up pathfinding
        local function followPath()
            local function moveDirChanged()
                if player:GetAttribute("PetsAttacking") then return end 
                if player.Character.Humanoid.MoveDirection == Vector3.new(0, 0, 0) then return end
                local value = player.Character.Humanoid.MoveDirection

                while player.Character.Humanoid.MoveDirection == value and not player:GetAttribute("PetsAttacking") do 
                    local path = PathfindingService:CreatePath({
                        AgentCanJump = true,
                        AgentRadius = 1.5,
                        AgentHeight = 5,
                        AgentCanWalkOnWater = false,
                        WaypointSpacing = 1.25
                    })
                    local position = (player.Character.PrimaryPart.CFrame * CFrame.new(0, 0, clonedPetPart:GetAttribute("BehindDistance"))).Position
                    path:ComputeAsync(clonedPetPart.Position, position)
                    local waypoints = path:GetWaypoints()
                    
                    if #waypoints > 0 then
                        for _, waypoint in ipairs(waypoints) do
                            local s = clonedPetPart:GetAttribute("Speed") or .1
                            if not player.Character or not player.Character.PrimaryPart then break end
                            local currentCFrame = clonedPetPart.CFrame
                            local root = player.Character.HumanoidRootPart
                            local look = Vector3.new(root.Position.X, clonedPetPart.Position.Y, root.Position.Z)
                            
                            local targetCFrame = CFrame.new(waypoint.Position, look)
                            local stepCFrame = currentCFrame:Lerp(targetCFrame, .1)
                            clonedPetPart.CFrame = targetCFrame
                                        
                            -- Randomize stop positions
                            if math.random() < 0.2 then
                                local randomOffset = Vector3.new(math.random(-1, 1) * 2.5, 0, math.random(-1, 1) * 2.5)
                                clonedPetPart.CFrame = CFrame.new(waypoint.Position + randomOffset, look)
                            end
                        end
                    end
                end
            end
            if player.Character:FindFirstChild("Humanoid").MoveDirection ~= Vector3.new(0, 0, 0) then 
                moveDirChanged() 
            end
            player.Character:FindFirstChild("Humanoid"):GetPropertyChangedSignal("MoveDirection"):Connect(moveDirChanged)
        end
        
        coroutine.wrap(followPath)()
    end
    
end)
