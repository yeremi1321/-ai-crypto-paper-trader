-- Loads and saves player data (coins, unlocks, equipped kart, settings,
-- records, mastery, challenges) with retries. A failed load never breaks the
-- session: the player gets a fresh temporary profile, is told progress won't
-- save this time, and we never overwrite their real save with it.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")

local PlayerData = require(ReplicatedStorage.Shared.PlayerData)

local Net = require(script.Parent.Net)

local DataService = {}

local STORE_NAME = "KartProfiles_v1"
local AUTOSAVE_SECONDS = 60

type Entry = { data: PlayerData.Data, canSave: boolean, dirty: boolean }

local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		warn("[DataService] DataStores unavailable; progress will not be saved:", result)
	end
end

local entries: { [Player]: Entry } = {}
local loaded = Instance.new("BindableEvent")
DataService.Loaded = loaded.Event

local function key(player: Player): string
	return `p{player.UserId}`
end

local function retry<T>(fn: () -> T): (boolean, any)
	local lastErr = nil
	for attempt = 1, 3 do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastErr = result
		task.wait(attempt)
	end
	return false, lastErr
end

function DataService.get(player: Player): PlayerData.Data?
	local e = entries[player]
	return e and e.data
end

-- Yields until the player's data is ready (or they leave).
function DataService.waitFor(player: Player): PlayerData.Data?
	while player.Parent and not entries[player] do
		loaded.Event:Wait()
	end
	return DataService.get(player)
end

function DataService.markDirty(player: Player)
	local e = entries[player]
	if e then
		e.dirty = true
	end
end

-- Sends the player their own data (for the garage, settings and coins).
function DataService.push(player: Player)
	local e = entries[player]
	if e then
		Net.Profile:FireClient(player, e.data, e.canSave)
	end
end

function DataService.save(player: Player)
	local e = entries[player]
	if not e or not e.canSave or not store then
		return
	end
	local data = e.data
	local ok, err = retry(function()
		return (store :: DataStore):UpdateAsync(key(player), function()
			return data
		end)
	end)
	if ok then
		e.dirty = false
	else
		warn(`[DataService] save failed for {player.Name}:`, err)
	end
end

-- Runs Roblox text filtering for kart names and plates others will see.
function DataService.filter(player: Player, text: string): string
	if text == "" then
		return ""
	end
	local ok, result = pcall(function()
		local filtered = TextService:FilterStringAsync(text, player.UserId)
		return filtered:GetNonChatStringForBroadcastAsync()
	end)
	if ok and type(result) == "string" then
		return result
	end
	-- In Studio without API access filtering fails; never show unfiltered text live.
	return if RunService:IsStudio() then text else ""
end

local function onPlayerAdded(player: Player)
	local data: PlayerData.Data
	local canSave = store ~= nil
	if store then
		local ok, result = retry(function()
			return (store :: DataStore):GetAsync(key(player))
		end)
		if ok then
			data = PlayerData.migrate(result)
		else
			warn(`[DataService] load failed for {player.Name}:`, result)
			data = PlayerData.new()
			canSave = false
			task.delay(3, function()
				if player.Parent then
					Net.Notify:FireClient(player, "Couldn't load your progress. This session won't be saved.")
				end
			end)
		end
	else
		data = PlayerData.new()
	end
	if not player.Parent then
		return
	end
	entries[player] = { data = data, canSave = canSave, dirty = false }
	loaded:Fire(player)
	DataService.push(player)
end

function DataService.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		DataService.save(player)
		entries[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_SECONDS)
			for player, e in entries do
				if e.dirty then
					task.spawn(DataService.save, player)
				end
			end
		end
	end)
	game:BindToClose(function()
		local pending = 0
		for player in entries do
			pending += 1
			task.spawn(function()
				DataService.save(player)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.25)
		end
	end)
end

return DataService
