-- Run in Studio's EDIT-mode command bar AFTER importing the reviewed FBXs.
-- Paste this script there; it changes only KartAssets models.
local root = game:GetService("ReplicatedStorage"):WaitForChild("KartAssets")
for _, folder in root:GetChildren() do
	if folder:IsA("Folder") and folder.Name ~= "Sounds" then
		for _, model in folder:GetChildren() do
			if model:IsA("Model") then
				local wheelCount = 0
				for _, part in model:GetDescendants() do
					if part:IsA("BasePart") then
						part.Anchored = true
						part.CanCollide = false
						part.CanTouch = false
						if string.match(part.Name, "^EngineIntake") or string.match(part.Name, "^IntakeStack") or string.match(part.Name, "^IntakeThrottle") then
							part:SetAttribute("Anim", "engine")
						end
						if table.find({"WheelFL", "WheelFR", "WheelRL", "WheelRR"}, part.Name) then
							wheelCount += 1
						end
					end
				end
				if folder.Name == "Bodies" and wheelCount ~= 4 then
					warn(model.Name .. ": expected exactly four named wheel MeshParts; got " .. wheelCount)
				end
				print("Prepared " .. folder.Name .. "/" .. model.Name)
			end
		end
	end
end
