-- This is a module I have made for the pets system to ensure universal smoothness across clients even with largescale pathfinding and pets at play, we do this by manually setting CF on server then sending it here to tween across the server-specified points!
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

-- Initialize, setting up client and servers as tables also so we can directly add functions to them w/out having to specify the tables later.
local PetMovementReplication = {}
PetMovementReplication.client={}
PetMovementReplication.server={}

function PetMovementReplication.server:sendUpdate(nameToMatch, partParentName, currentCFrame)
    -- Ensuring here that the RemoteEvent exists in ReplicatedStorage, manually create it if not as a failsafe!!
    local replicationEvent = ReplicatedStorage:FindFirstChild("PetMovementEvent") 
    if not replicationEvent then 
    replicationEvent =  Instance.new("RemoteEvent",ReplicatedStorage)
    replicationEvent.Name = "PetMovementEvent"
end 
    replicationEvent:FireAllClients(nameToMatch, partParentName, currentCFrame) -- We'll call this from PetsService to let the client know its time to tween the part to its updated cf!
end


function PetMovementReplication.client:listener() -- The brains of the client, dedicated to handling synchrony of physics, making it appear smooth per each client.
    local player = Players.LocalPlayer
    local clientOnlyClones = {}
    
    -- Yielding here for, if some reason, the replicationEvent was not initialized right away.
    local replicationEvent = ReplicatedStorage:WaitForChild("PetMovementEvent")

    -- Connect w/ OnClientEvent to handle pathfinding comm from the server
    replicationEvent.OnClientEvent:Connect(function(nameToMatch, partParentName, currentCFrame)
        if not clientOnlyClones[nameToMatch] then 
            -- Find the parent folder in workspace and clone the part if it doesn't exist
            local getMatchingPlayerFolder = workspace:FindFirstChild(partParentName) 
            if not getMatchingPlayerFolder then 
                getMatchingPlayerFolder = workspace
            end 
            if getMatchingPlayerFolder then
                clientOnlyClones[nameToMatch] = getMatchingPlayerFolder:FindFirstChild(nameToMatch):Clone()
                clientOnlyClones[nameToMatch].CanCollide = false
                clientOnlyClones[nameToMatch].Parent = getMatchingPlayerFolder 
                clientOnlyClones[nameToMatch].Transparency = 0
            end 
        end 
        
        local clone = clientOnlyClones[nameToMatch]

        if not clone then 
            return 
        end
            -- Use tweening on the client to ensure local smoothness, as opposed to my manual lerping in the service.
            local height = clone.Size.Y
            local getGroundedOffset = Vector3.new(0,height/2,0)
            currentCFrame+=getGroundedOffset
            local dist = (clone.Position - currentCFrame.Position).Magnitude
            
            -- Here I am adapting the tween time varying by 1) are pets attacking? and 2) if not, what is their distance? 
            local calcMovementSpeed
            if not player:GetAttribute("PetsAttacking") then 
                calcMovementSpeed = 0.1325 * dist
            else 
                calcMovementSpeed = 0.175
            end 
            if not calcMovementSpeed then calcMovementSpeed = .1 end
            TweenService:Create(clone,TweenInfo.new(calcMovementSpeed),{CFrame=currentCFrame}):Play() 
    end)
end

return PetMovementReplication