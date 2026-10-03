-- Local wall displays and proximity doors for Kart HQ. SurfaceGuis belong
-- to PlayerGui; the server supplies round data and departure authorization.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local UI = require(script.Parent.UI)
local TrackPreview = require(script.Parent.TrackPreview)
local Tracks = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Tracks"))

local LobbyScreens = {}
local state: any = nil
local lobby: Instance? = nil
local surfaces = {}
local doors = {}
local faces = {}
local nextScan, nextFaces = 0, 0
local featured: string? = nil
local randomFeatured: string? = nil
local displayKey = ""
local gold = Color3.fromRGB(255, 200, 60)

local function clear(display)
	for _, preview in display.previews do
		preview:destroy()
	end
	display.previews = {}
	for _, child in display.root:GetChildren() do
		child:Destroy()
	end
end

local function label(parent, text, x, y, w, h, color)
	return UI.label(parent, {
		Text = text, Position = UDim2.fromScale(x, y), Size = UDim2.fromScale(w, h),
		TextColor3 = color or UI.Colors.text,
	})
end

local function preview(display, parent, id, x, y, w, h)
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Position = UDim2.fromScale(x, y)
	holder.Size = UDim2.fromScale(w, h)
	holder.Parent = parent
	table.insert(display.previews, TrackPreview.new(holder, id))
end

local function addFaces(parent, ids, x, y, w, h)
	local count = math.min(#ids, 6)
	for i = 1, count do
		local face = Instance.new("ImageLabel")
		face.Name = "Voter"
		face.BackgroundColor3 = UI.Colors.panelLight
		face.Size = UDim2.fromScale(w / 7, h)
		face.Position = UDim2.fromScale(x + (i - 1) * w / 7, y)
		face.Image = UI.headshot(ids[i], true)
		face.Parent = parent
		local aspect = Instance.new("UIAspectRatioConstraint")
		aspect.Parent = face
		table.insert(faces, { image = face, id = ids[i] })
	end
	if #ids > count then
		label(parent, `+{#ids - count}`, x + count * w / 7, y, w / 7, h)
	end
end

local function standings(display, title, rows, limit)
	label(display.root, title, 0.03, 0.02, 0.94, 0.13, gold)
	local count = math.min(#rows, limit)
	if count == 0 then
		label(display.root, "No race yet · ready up to race", 0.05, 0.35, 0.9, 0.25)
		return
	end
	local height = math.min(0.2, 0.76 / count)
	for i = 1, count do
		local row = rows[i]
		local suffix = if row.finished then " · FINISHED" elseif row.isCpu then " · CPU" else ""
		label(display.root, `{i}. {row.name}{suffix}`, 0.05, 0.19 + (i - 1) * height, 0.9, height * 0.86,
			if i <= 3 then gold else UI.Colors.text)
	end
end

local function trackTitle(id)
	return Tracks.get(id).name
end

local function featuredTrack(display, id, announcing)
	preview(display, display.root, id, 0.04, 0.04, 0.92, 0.69)
	label(display.root, trackTitle(id), 0.03, 0.75, 0.94, 0.13, gold)
	label(display.root, if announcing then "TRACK CHOSEN · head to departure" else "Step onto a pad to race",
		0.03, 0.9, 0.94, 0.08)
end

local function render()
	faces = {}
	local s = state or { phase = "lobby", options = {}, players = {} }
	for key, display in surfaces do
		clear(display)
		if key == "vote" then
			if s.phase == "voting" then
				for i = 1, 4 do
					local opt = (s.options or {})[i]
					local ids = if i == 4 then s.randomVoters or {} else (opt and opt.voters or {})
					local x = (i - 1) / 4 + 0.012
					local card = UI.panel(display.root, { Position = UDim2.fromScale(x, 0.025), Size = UDim2.fromScale(0.226, 0.95) })
					if opt and i < 4 then
						preview(display, card, opt.id, 0.04, 0.04, 0.92, 0.52)
					elseif i == 4 and s.options and s.options[1] then
						preview(display, card, randomFeatured or s.options[1].id, 0.04, 0.04, 0.92, 0.52)
						label(card, "? ? ?", 0.05, 0.15, 0.9, 0.25, UI.Colors.purple)
					else
						label(card, "—", 0.05, 0.12, 0.9, 0.34, UI.Colors.purple)
					end
					label(card, if i == 4 then "RANDOM" else (opt and opt.name or "Waiting"), 0.04, 0.59, 0.92, 0.13)
					local votes = if i == 4 then #ids else (opt and opt.votes or 0)
					label(card, `{votes} vote{if votes == 1 then "" else "s"}`, 0.04, 0.75, 0.92, 0.08, gold)
					addFaces(card, ids, 0.04, 0.86, 0.92, 0.1)
				end
			elseif s.phase == "announce" and s.winner then
				featuredTrack(display, s.winner, true)
			elseif s.phase == "racing" then
				standings(display, `LIVE · {if s.spectate then s.spectate.trackName else "Race"}`, s.spectate and s.spectate.rows or {}, 8)
			elseif s.phase == "results" then
				standings(display, "RACE RESULTS · TOP 3", s.lastResults or {}, 3)
			else
				featuredTrack(display, featured or Tracks.VotePool[1], false)
			end
		elseif key == "status" then
			display.title = label(display.root, "KART HQ", 0.02, 0.06, 0.96, 0.45, gold)
			display.detail = label(display.root, "", 0.02, 0.56, 0.96, 0.36)
		else
			local index = tonumber(string.match(key, "%d+"))
			local opt = (s.options or {})[index]
			local votes = if index == 4 then #(s.randomVoters or {}) else (opt and opt.votes or 0)
			label(display.root, `{index} · {if index == 4 then "RANDOM" else (opt and opt.name or "TRACK")}`, 0.02, 0.05, 0.96, 0.55)
			label(display.root, if s.phase == "voting" then `{votes} votes` else "Step on pad to race", 0.02, 0.66, 0.96, 0.27, gold)
		end
	end
end

local function surface(key, part)
	if not part or not part:IsA("BasePart") then return end
	local gui = Instance.new("SurfaceGui")
	gui.Name = `LobbyScreen_{key}`
	gui.Adornee = part
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(1920, math.floor(1920 * part.Size.Y / part.Size.X))
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.ResetOnSpawn = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	local root = Instance.new("Frame")
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = UI.Colors.panel
	root.BorderSizePixel = 0
	root.Parent = gui
	surfaces[key] = { gui = gui, root = root, previews = {} }
end

local function discover()
	local found = Workspace:FindFirstChild("Lobby")
	local chamber = found and found:FindFirstChild("Chamber")
	-- Wait for complete replication without blocking the Round event handler.
	if not chamber or not chamber:FindFirstChild("PadSign4")  then return end
	if found == lobby then return end
	for _, display in surfaces do
		clear(display)
		display.gui:Destroy()
	end
	surfaces, doors = {}, {}
	lobby = found
	surface("vote", chamber:FindFirstChild("VoteScreen"))
	surface("status", chamber:FindFirstChild("StatusBoard"))
	for i = 1, 4 do surface(`pad{i}`, chamber:FindFirstChild(`PadSign{i}`)) end

	for _, model in found:GetDescendants() do
		if model:IsA("Model") and model:GetAttribute("SlidingDoor") then
			local parts, glows = {}, {}
			local center = nil
			for _, part in model:GetDescendants() do
				if part:IsA("BasePart") then
					if part:GetAttribute("Side") then
						table.insert(parts, { part = part, closed = part.CFrame, side = part:GetAttribute("Side") })
					end
					if part.Name == "Glow" then table.insert(glows, { part = part, color = part.Color }) end
					if part.Name == "Panel1" or part.Name == "Panel2" then
						local foot = part.CFrame.Position - Vector3.new(0, part.Size.Y / 2, 0)
						center = if center then (center + foot) / 2 else foot
					end
				end
			end
			if center then table.insert(doors, { model = model, parts = parts, glows = glows, center = center, amount = 0 }) end
		end
	end
	render()
end

-- Round snapshots arrive regularly even when no visible content changed.
-- Preserve the expensive viewport models and faces until display data changes.
function LobbyScreens.setState(s)
	state = s
	local key = { s.phase, s.winner or "", s.spectate and s.spectate.trackName or "" }
	for _, opt in s.options or {} do
		table.insert(key, `{opt.id}:{opt.name}:{opt.votes}`)
		for _, id in opt.voters or {} do table.insert(key, tostring(id)) end
		table.insert(key, "/")
	end
	for _, id in s.randomVoters or {} do table.insert(key, `random:{id}`) end
	for _, row in s.spectate and s.spectate.rows or {} do
		table.insert(key, `{row.name}:{row.finished}:{row.isCpu}`)
	end
	for _, row in s.lastResults or {} do table.insert(key, `result:{row.name}`) end
	local nextKey = table.concat(key, "|")
	if displayKey ~= nextKey then
		displayKey = nextKey
		randomFeatured = nil
		render()
	end
end

function LobbyScreens.step(dt: number)
	local t = Workspace:GetServerTimeNow()
	if t >= nextScan then
		nextScan = t + 0.5
		discover()
	end
	if not lobby or not lobby.Parent then return end
	if not state or state.phase == "lobby" then
		local id = Tracks.VotePool[math.floor(t / 8) % #Tracks.VotePool + 1]
		if featured ~= id then
			featured = id
			render()
		end
	elseif state.phase == "voting" and state.options and #state.options > 0 then
		local id = state.options[math.floor(t / 4) % #state.options + 1].id
		if randomFeatured ~= id then
			randomFeatured = id
			render()
		end
	end
	local board = surfaces.status
	if board and state then
		local ready, voted = 0, 0
		local voters = {}
		for _, p in state.players or {} do if p.ready then ready += 1 end end
		for _, opt in state.options or {} do
			for _, id in opt.voters or {} do voters[id] = true end
		end
		for _, id in state.randomVoters or {} do voters[id] = true end
		for _ in voters do voted += 1 end
		local left = if state.deadline then ` · {math.max(0, math.ceil(state.deadline - t))}s` else ""
		board.title.Text = string.upper(state.phase) .. left
		board.detail.Text = `{ready} ready · {voted} voted`
	end
	for _, display in surfaces do for _, p in display.previews do p:step(t) end end
	if t >= nextFaces then
		nextFaces = t + 0.5
		for _, face in faces do face.image.Image = UI.headshot(face.id, true) end
	end
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	for _, door in doors do
		if not door.model.Parent then continue end
		local departure = door.model:GetAttribute("Departure") == true
		local lit = door.model:GetAttribute("Lit") == true
		local nearby = root ~= nil and (root.Position - door.center).Magnitude <= 18
		local open = nearby and (not departure or lit)
		door.amount += ((if open then 1 else 0) - door.amount) * (1 - math.exp(-10 * dt))
		local travel = (door.model:GetAttribute("Width") / 2 - 0.8) * door.amount
		for _, item in door.parts do item.part.CFrame = item.closed * CFrame.new(item.side * travel, 0, 0) end
		for _, glow in door.glows do
			glow.part.Color = if departure and lit then gold:Lerp(Color3.fromRGB(230, 205, 160), (math.sin(t * 2) + 1) * 0.12) else glow.color
		end
	end
end

return LobbyScreens
