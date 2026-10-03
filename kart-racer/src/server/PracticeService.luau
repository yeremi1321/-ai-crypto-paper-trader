-- Practice karts on the lobby loop. Anyone not in a race can take one out to
-- try drifting, the jump ramp and the boost tunnel. Practice karts are
-- client-driven like race karts but nothing is scored.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local LobbyLayout = require(Shared.LobbyLayout)
local Track = require(Shared.Track)
local KartRig = require(ReplicatedStorage.Common.KartRig)

local Net = require(script.Parent.Net)

local PracticeService = {}

local folder = Instance.new("Folder")
folder.Name = "PracticeKarts"
folder.Parent = Workspace

local practiceTrack = Track.build(LobbyLayout.PracticeTrack)
local karts: { [Player]: Model } = {}
local nextSlot = 0

function PracticeService.stop(player: Player)
	local kart = karts[player]
	karts[player] = nil
	if kart then
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Sit = false
		end
		kart:Destroy()
	end
end

function PracticeService.isPracticing(player: Player): boolean
	return karts[player] ~= nil
end

function PracticeService.start(player: Player, kartId: string, look: any)
	PracticeService.stop(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	nextSlot = nextSlot % 8 + 1
	local pos, d = Track.gridSpot(practiceTrack, nextSlot)
	local _, tan = Track.at(practiceTrack, d)
	local yaw = math.atan2(-tan.x, -tan.z)
	local kart = KartRig.build(kartId, player.DisplayName, CFrame.new(pos.x, pos.y, pos.z) * CFrame.Angles(0, yaw, 0), folder, look)
	karts[player] = kart

	local seat = kart:FindFirstChild("DriverSeat") :: Seat
	humanoid.Sit = false
	character:PivotTo(seat.CFrame + Vector3.new(0, 2, 0))
	seat:Sit(humanoid)
	if kart.PrimaryPart and kart.PrimaryPart:CanSetNetworkOwnership() then
		kart.PrimaryPart:SetNetworkOwner(player)
	end
	-- Getting out of the seat ends practice.
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		if seat.Occupant == nil then
			task.delay(0.5, function()
				if karts[player] == kart and seat.Occupant == nil then
					PracticeService.stop(player)
				end
			end)
		end
	end)
	Net.PracticeStart:FireClient(player, {
		trackId = LobbyLayout.PracticeTrack.id,
		theme = LobbyLayout.PracticeTrack.theme,
		kart = kart,
		kartId = kartId,
		yaw = yaw,
	})
end

function PracticeService.init()
	Net.LeavePractice.OnServerEvent:Connect(PracticeService.stop)
	Players.PlayerRemoving:Connect(PracticeService.stop)
end

return PracticeService
