-- Creates the RemoteEvents listed in Shared.RemoteNames under ReplicatedStorage.Remotes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteNames = require(ReplicatedStorage.Shared.RemoteNames)

local folder = Instance.new("Folder")
folder.Name = "Remotes"

local Net: { [string]: RemoteEvent } = {}
for name in RemoteNames do
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = folder
	Net[name] = remote
end

folder.Parent = ReplicatedStorage

return Net
