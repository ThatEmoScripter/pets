-- This script manages client-side behavior for pet interactions in a game. It handles toggling UI elements, creating pet viewports, and detecting mouse hits.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

-- Constants for tweening and notification
local bodyInfo = TweenInfo.new(1, Enum.EasingStyle.Back)
local notificationInfo = TweenInfo.new(.5, Enum.EasingStyle.Bounce)
local notificationWaitTime = 2

-- Get references to local player and UI elements
local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")
local petManager = playerGui:WaitForChild("PetManager")
local notification = petManager:WaitForChild("Notification")
local toggleButton = petManager:WaitForChild("ButtonHolder"):WaitForChild("ImageButton")
local Mouse = localPlayer:GetMouse()

-- Remote events and functions
local PetClicked = ReplicatedStorage:WaitForChild("PetClicked")
local getMouseHitRemoteFunction = ReplicatedStorage:WaitForChild("GetMouseHit")
local notify = ReplicatedStorage:WaitForChild("Notify")

-- Variable to track currently selected pet
local activePlacementViewport = nil
local isNotifying = false

notify.OnClientEvent:Connect(function(args)
    if isNotifying then return end 
    isNotifying = true
    
    -- Initialize notification position attribute if not set
    if not notification:GetAttribute("OriginalPosition") then 
        notification:SetAttribute("OriginalPosition", notification.Position) 
    end 
    
    -- Animate the notification to show the message
    notification.Position = notification:GetAttribute("OriginalPosition") + UDim2.new(1, 0, 0, 0)
    notification.Text = args 
    TweenService:Create(notification, bodyInfo, { Position = notification:GetAttribute("OriginalPosition") }):Play()
    
    coroutine.wrap(function()
        task.wait(notificationInfo.Time + notificationWaitTime)
        TweenService:Create(notification, notificationInfo, { Position = notification:GetAttribute("OriginalPosition") + UDim2.new(1, 0, 0, 0) }):Play()
        wait(notificationInfo.Time + 0.1)
        notification.Text = ""
        isNotifying = false
    end)()
end)

-- Save the original size of the toggle button's parent if not already saved
if not toggleButton.Parent:GetAttribute("OriginalSize") then 
    toggleButton.Parent:SetAttribute("OriginalSize", toggleButton.Parent.Size) 
end

-- Reference to the body frame in the pet manager UI
local bodyFrame = petManager:WaitForChild("Frame"):WaitForChild("Body")

-- Function to handle toggle button click
toggleButton.MouseButton1Click:Connect(function()
    if petManager:GetAttribute("CurrentlyTweening") then return end 
    petManager:SetAttribute("CurrentlyTweening", true)
    
    local sizeFactor = 0.85
    local mainFrame = bodyFrame.Parent
    
    -- Save the original position of the main frame if not already saved
    if not mainFrame:GetAttribute("OriginalPosition") then 
        mainFrame:SetAttribute("OriginalPosition", mainFrame.Position) 
    end 
    
    local originalSize = toggleButton.Parent:GetAttribute("OriginalSize")
    local originalPosition = mainFrame:GetAttribute("OriginalPosition")
    
    -- Calculate the adjusted size for toggling
    local adjustedSize = UDim2.new(originalSize.X.Scale * sizeFactor, originalSize.X.Offset * sizeFactor, 
                                   originalSize.Y.Scale * sizeFactor, originalSize.Y.Offset * sizeFactor)
    
    -- Create a tween to adjust the size of the toggle button's parent
    local info = TweenInfo.new(0.2, Enum.EasingStyle.Quad)
    TweenService:Create(toggleButton.Parent, info, { Size = adjustedSize }):Play()
    
    coroutine.wrap(function()
        task.wait(info.Time)
        
        -- Create a tween to revert the size back to original
        TweenService:Create(toggleButton.Parent, info, {Size = originalSize}):Play()
    end)()
    
    -- Handle visibility toggle of the main frame
    if mainFrame.Visible then 
        -- Move the main frame off-screen and hide it
        TweenService:Create(mainFrame, bodyInfo, { Position = originalPosition + UDim2.new(0, 0, -1, 0) }):Play()
        
        coroutine.wrap(function()
            task.wait(bodyInfo.Time)
            mainFrame.Visible = false
            petManager:SetAttribute("CurrentlyTweening", nil)
        end)()
    else 
        mainFrame.Visible = true
        
        -- Move the main frame back to its original position
        TweenService:Create(mainFrame, bodyInfo, { Position = originalPosition }):Play()
        
        coroutine.wrap(function()
            task.wait(bodyInfo.Time)
            petManager:SetAttribute("CurrentlyTweening", nil)
        end)()
    end 
end)

-- Reference to the template viewport frame in ReplicatedStorage
local templateViewportFrame = ReplicatedStorage:WaitForChild("TEMPLATE")

-- Function to create a viewport for a pet part
local function createPetViewport(petPart)
    local originalViewport = templateViewportFrame:Clone()
    originalViewport.Parent = bodyFrame
    originalViewport.Name = petPart.Name
    
    -- Ensure the viewport frame has a camera
    if not originalViewport.CurrentCamera then 
        originalViewport.CurrentCamera = Instance.new("Camera", originalViewport) 
    end 
    
    local partClone = petPart:Clone()
    
    -- Calculate the camera position to look at the pet part
    local cf = CFrame.new((partClone.CFrame * CFrame.new(0, 0, -3.5)).Position, partClone.Position)
    originalViewport.CurrentCamera.CFrame = cf
    
    -- Parent the cloned pet part to the viewport's WorldModel
    partClone.Parent = originalViewport.WorldModel

    local button = originalViewport:FindFirstChild("BUTTON")
    if button then
        -- Function to handle pet selection and movement
        button.MouseButton1Click:Connect(function()
            if activePlacementViewport then return end
            
            local placementViewportTemp = originalViewport:Clone()
            activePlacementViewport = placementViewportTemp
            
            if placementViewportTemp:FindFirstChild("BUTTON") then 
                placementViewportTemp.Active = false -- make it so ui button clicks wont block spawning in the 3d space!
            end 
            -- Position the cloned viewport in the pet manager UI
            placementViewportTemp.Parent = petManager
            placementViewportTemp.Size = UDim2.new(0, 100, 0, 100)
            
            local trackIsMoving

            -- Function to handle mouse movement
            local function moveVP(input, gameProcessed)
                if not gameProcessed then
                    local mousePos = UserInputService:GetMouseLocation()
                    placementViewportTemp.Position = UDim2.new(0, mousePos.X, 0, mousePos.Y)
                end
            end

            -- Function to handle single click to place the pet
            local function onceEndPlace()
                trackIsMoving:Disconnect()
                placementViewportTemp:Destroy()
                PetClicked:FireServer(originalViewport.Name)
                activePlacementViewport = nil
            end
            
            -- Connect mouse movement and click events
            trackIsMoving = RunService.RenderStepped:Connect(moveVP)
            Mouse.Button1Down:Once(onceEndPlace)
        end)
    end
end

-- Reference to the pets folder in ReplicatedStorage
local petsFolder = ReplicatedStorage:WaitForChild("Pets")

-- Create viewports for existing pet parts
for _, getExistingPet in pairs(petsFolder:GetChildren()) do
    if not getExistingPet:IsA("BasePart") then 
        return 
    end 
    createPetViewport(getExistingPet)
end

-- Connect to the ChildAdded event to create viewports for new pet parts
petsFolder.ChildAdded:Connect(function(newObject)
    if not newObject:IsA("BasePart") then 
        warn("Sooo, this error should never happen: in your setup you added incorrect instance types to your pet folder.")
        return 
    end
    createPetViewport(newObject)
end)

-- Function to get the mouse hit position
local function getMouseHit(isSpawning)
    if not Mouse.Target and not isSpawning then 
    return 
end 
    local checkIfInvalidCharacter = Mouse.Target:FindFirstAncestorOfClass("Model")
    
    -- Check if the target is a player character
    if checkIfInvalidCharacter and checkIfInvalidCharacter:FindFirstChild("Humanoid") and not isSpawning then 
    return 
end 
    
    return Mouse.Hit.Position
end 

-- Set the client-side function for GetMouseHit remote event
getMouseHitRemoteFunction.OnClientInvoke = getMouseHit

-- Require and initialize pet movement replication module
require(ReplicatedStorage.Modules:WaitForChild("PetMovementReplication",5)).client:listener()