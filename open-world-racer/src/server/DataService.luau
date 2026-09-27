-- Loads and saves player profiles and the per-spot leaderboards.
-- Falls back to in-memory data when DataStores are unavailable (e.g. Studio
-- without "Enable Studio Access to API Services"), so the game still runs.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local PlayerProfile = require(Shared.PlayerProfile)
local Records = require(Shared.Records)

local DataService = {}

local PROFILE_STORE = "Profiles_v1"
local RECORD_STORE = "Records_v1"
local AUTOSAVE_SECONDS = 90

local profileStore, recordStore
do
	local ok = pcall(function()
		profileStore = DataStoreService:GetDataStore(PROFILE_STORE)
		recordStore = DataStoreService:GetDataStore(RECORD_STORE)
	end)
	if not ok then
		warn("[DataService] DataStores unavailable; progress will not be saved this session")
	end
end

local profiles: { [Player]: PlayerProfile.Profile } = {}
local loaded = Instance.new("BindableEvent")
local boards: { [string]: { Records.Entry } } = {}

local function retry<T>(fn: () -> T): (boolean, T?)
	for attempt = 1, 3 do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		warn(`[DataService] attempt {attempt} failed: {result}`)
		task.wait(attempt * 2)
	end
	return false, nil
end

local function key(player: Player): string
	return `u{player.UserId}`
end

DataService.ProfileLoaded = loaded.Event

function DataService.get(player: Player): PlayerProfile.Profile?
	return profiles[player]
end

-- Yields until the player's profile is ready (or the player leaves).
function DataService.waitFor(player: Player): PlayerProfile.Profile?
	while player.Parent and not profiles[player] do
		loaded.Event:Wait()
	end
	return profiles[player]
end

function DataService.save(player: Player)
	local profile = profiles[player]
	if not profile or not profileStore then
		return
	end
	retry(function()
		profileStore:SetAsync(key(player), profile, { player.UserId })
	end)
end

local function onPlayerAdded(player: Player)
	local data = nil
	if profileStore then
		local ok, result = retry(function()
			return profileStore:GetAsync(key(player))
		end)
		if ok then
			data = result
		elseif RunService:IsStudio() then
			warn("[DataService] Studio has no DataStore access; running without saves")
			profileStore, recordStore = nil, nil
		else
			player:Kick("Could not load your garage. Please rejoin.")
			return
		end
	end
	if not player.Parent then
		return
	end
	profiles[player] = PlayerProfile.migrate(data)
	loaded:Fire(player)
end

local function onPlayerRemoving(player: Player)
	DataService.save(player)
	profiles[player] = nil
end

-- Leaderboards -------------------------------------------------------------

function DataService.getBoard(boardId: string): { Records.Entry }
	if not boards[boardId] then
		boards[boardId] = {}
		if recordStore then
			local ok, result = retry(function()
				return recordStore:GetAsync(boardId)
			end)
			if ok and type(result) == "table" then
				boards[boardId] = result
			end
		end
	end
	return boards[boardId]
end

-- Submits to the local copy immediately and merges into the saved board.
function DataService.submitRecord(boardId: string, entry: Records.Entry, descending: boolean?): number?
	local rank = Records.submit(DataService.getBoard(boardId), entry, nil, descending)
	if rank and recordStore then
		task.spawn(retry, function()
			recordStore:UpdateAsync(boardId, function(saved)
				saved = if type(saved) == "table" then saved else {}
				Records.submit(saved, entry, nil, descending)
				boards[boardId] = saved
				return saved
			end)
		end)
	end
	return rank
end

function DataService.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_SECONDS)
			for player in profiles do
				task.spawn(DataService.save, player)
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for player in profiles do
			pending += 1
			task.spawn(function()
				DataService.save(player)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.5)
		end
	end)
end

return DataService
