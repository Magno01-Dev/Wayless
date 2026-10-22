-- Saved server Script: functional Seats and persistent interaction prompts.
for _, seat in ipairs(script.Parent:GetDescendants()) do
    if seat:IsA("Seat") then
        local prompt = seat:FindFirstChildOfClass("ProximityPrompt")
        if prompt then
            local function refresh()
                prompt.Enabled = seat.Occupant == nil
            end
            seat:GetPropertyChangedSignal("Occupant"):Connect(refresh)
            prompt.Triggered:Connect(function(player)
                local character = player.Character
                local humanoid = character and character:FindFirstChildOfClass("Humanoid")
                local root = character and character:FindFirstChild("HumanoidRootPart")
                if humanoid and humanoid.Health > 0 and root and not seat.Occupant
                    and (root.Position - seat.Position).Magnitude <= 10 then
                    seat:Sit(humanoid)
                end
            end)
            refresh()
        end
    end
end
