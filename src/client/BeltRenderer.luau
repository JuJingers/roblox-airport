--!strict
-- Рисует чемоданы, едущие по ленте.
--
-- Сервер сообщает только «появился вот такой чемодан» и «этот снят».
-- Где чемодан находится прямо сейчас, клиент вычисляет сам: часы
-- сервера и клиента синхронны, а скорость ленты одинакова у всех.
-- Поэтому движение идёт без единого сетевого пакета за кадр.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local PlotContext = require(ReplicatedStorage.Shared.PlotContext)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)

local BeltRenderer = {}

type Tracked = {
	bag: Types.Bag,
	part: Part,
}

local tracked: { [string]: Tracked } = {}
local folder: Folder? = nil

local function container(): Folder
	if folder and folder.Parent then
		return folder
	end
	local created = Instance.new("Folder")
	created.Name = "BagsLocal"
	created.Parent = workspace
	folder = created
	return created
end

-- Цвет всегда показывает направление — иначе игрок не сможет решить,
-- куда везти чемодан. VIP отмечается свечением поверх того же цвета,
-- а не подменой цвета: подменённый цвет прятал бы правильный ответ.
local function colorFor(bag: Types.Bag): Color3
	local colors: { [string]: Color3 } = Config.DestinationColors
	return colors[bag.destination] or Color3.fromRGB(200, 200, 200)
end

local function onSpawned(bag: Types.Bag)
	if tracked[bag.id] then
		return
	end

	local part = Instance.new("Part")
	part.Name = bag.id
	part.Size = Config.BagSize
	part.Color = colorFor(bag)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Position = PlotContext.at(Config.BeltStart)
	if bag.isVip then
		part.Material = Enum.Material.Neon
	end
	part.Parent = container()

	tracked[bag.id] = { bag = bag, part = part }
end

local function onDespawned(bagId: string)
	local entry = tracked[bagId]
	if not entry then
		return
	end
	entry.part:Destroy()
	tracked[bagId] = nil
end

-- Подсветка чемодана, который сейчас на очереди. Игрок работает всегда
-- с ближайшим к концу ленты, поэтому он обязан быть виден сразу.
local highlight: Highlight? = nil

local function ensureHighlight(): Highlight
	if highlight and highlight.Parent ~= nil then
		return highlight
	end
	local created = Instance.new("Highlight")
	created.Name = "NextBag"
	-- Заливки быть не должно: она подмешивает белый к цвету чемодана,
	-- а цвет — единственный источник информации в этой игре.
	-- Зелёный под белой заливкой читается как оливковый, и игрок
	-- ошибается не по своей вине.
	created.FillTransparency = 1
	created.OutlineTransparency = 0
	created.OutlineColor = Color3.fromRGB(255, 255, 255)
	created.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	created.Parent = container()
	highlight = created
	return created
end

local function frontmost(): Tracked?
	local best: Tracked? = nil
	for _, entry in tracked do
		if best == nil or entry.bag.spawnedAt < best.bag.spawnedAt then
			best = entry
		end
	end
	return best
end

-- Порядок чемоданов, доехавших до конца и ждущих разбора.
local queueOrder: { string } = {}

local function queueSlot(bagId: string): Vector3?
	local index = table.find(queueOrder, bagId)
	if index == nil then
		return nil
	end
	return PlotContext.at(Config.QueueStart) + Config.QueueStep * (index - 1)
end

local function step()
	local now = workspace:GetServerTimeNow()
	local travel = Config.BeltTravelSeconds

	for _, entry in tracked do
		local slot = queueSlot(entry.bag.id)
		if slot then
			-- В очереди чемодан стоит на месте: он уже приехал.
			entry.part.Position = slot
		else
			local elapsed = now - entry.bag.spawnedAt
			local alpha = math.clamp(elapsed / travel, 0, 1)
			entry.part.Position = PlotContext.at(Config.BeltStart):Lerp(PlotContext.at(Config.BeltEnd), alpha)
		end
	end

	local next = frontmost()
	ensureHighlight().Adornee = if next then next.part else nil
end

function BeltRenderer.countOnBelt(): number
	local count = 0
	for _ in tracked do
		count += 1
	end
	return count
end

function BeltRenderer.countQueued(): number
	return #queueOrder
end

function BeltRenderer.start()
	Remotes.get("BagSpawned").OnClientEvent:Connect(onSpawned)
	Remotes.get("BagDespawned").OnClientEvent:Connect(onDespawned)
	Remotes.get("QueueUpdated").OnClientEvent:Connect(function(order: { string })
		queueOrder = order
	end)
	RunService.RenderStepped:Connect(step)
end

return BeltRenderer
