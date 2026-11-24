--!strict
-- Лента: появление чемоданов, их продвижение и снятие в конце.
-- Один экземпляр на плот.
--
-- Здесь живёт только логика. Чемодан — это запись в таблице, а не деталь
-- в мире: физику Roblox мы намеренно не используем, иначе при десятке
-- чемоданов начнутся тормоза и рассинхрон.
--
-- Клиенту уходит одно сообщение на появление и одно на снятие. Положение
-- он вычисляет сам из времени появления, поэтому за кадр по сети не идёт
-- ничего.
--
-- Сообщения уходят владельцу плота, а не всем на сервере: иначе клиент
-- рисовал бы у себя чужие чемоданы, а восемь лент слились бы в одну кучу.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)

local BeltService = {}

export type Belt = {
	putBag: (ownerId: string) -> (),
	take: (bagId: string) -> Types.Bag?,
	getFrontmost: () -> Types.Bag?,
	getStats: () -> { onBelt: number, queued: number, lost: number },
	canAcceptBag: () -> boolean,
	setLostHandler: (handler: (Types.Bag) -> ()) -> (),
	setQueueBonus: (bonus: number) -> (),
	step: (deltaTime: number) -> (),
	sendSnapshot: (player: Player) -> (),
	destroy: () -> (),
}

function BeltService.new(plot: any): Belt
	local bagSpawned = Remotes.get("BagSpawned")
	local bagDespawned = Remotes.get("BagDespawned")
	local queueUpdated = Remotes.get("QueueUpdated")

	local bags: { [string]: Types.Bag } = {}
	local bagCount = 0
	local nextId = 0
	local rng = Random.new()

	-- Очередь у конца ленты: чемоданы, до которых игрок не успел.
	-- Порядок в списке = порядок прибытия.
	local queue: { string } = {}

	-- Потерянные при переполнении очереди. Это единственный способ
	-- потерять чемодан: доехать до конца больше не значит пропасть.
	local lost = 0

	-- Когда последний раз клали чемодан: нужно, чтобы держать просвет
	-- между ними на ленте.
	local lastPutAt = -math.huge

	-- Прибавка мест от улучшения. Ставится снаружи: лента не должна
	-- знать про магазин.
	local queueBonus = 0

	local onLost: ((Types.Bag) -> ())? = nil

	local api = {}

	local function now(): number
		return workspace:GetServerTimeNow()
	end

	-- Всё, что лента сообщает, адресовано хозяину этого аэропорта.
	local function tell(remote: RemoteEvent, ...)
		local owner = plot.owner
		if owner then
			remote:FireClient(owner, ...)
		end
	end

	local function makeBag(ownerId: string): Types.Bag
		nextId += 1

		local destinations: { Types.Destination } = Config.Destinations
		local destination: Types.Destination = destinations[rng:NextInteger(1, #destinations)]

		-- Тип указан на переменной, а не выводится из литерала: иначе Luau
		-- расширяет "Red" до string и перечисление Destination теряется.
		local bag: Types.Bag = {
			id = string.format("p%d_bag%d", plot.index, nextId),
			destination = destination,
			size = "Normal",
			fragile = false,
			flagged = false,
			isVip = rng:NextNumber() < Config.VipChance,
			ownerId = ownerId,
			spawnedAt = now(),
		}
		return bag
	end

	local function queueCapacity(): number
		return Config.QueueCapacity + queueBonus
	end

	local function removeFromQueue(bagId: string)
		local index = table.find(queue, bagId)
		if index then
			table.remove(queue, index)
		end
	end

	local function forget(bagId: string)
		bags[bagId] = nil
		bagCount -= 1
		removeFromQueue(bagId)
		tell(bagDespawned, bagId)
	end

	-- Чемодан доехал до конца ленты и встаёт в очередь.
	local function enqueue(bag: Types.Bag)
		table.insert(queue, bag.id)

		-- Переполнение: самый старый чемодан уезжает совсем.
		if #queue > queueCapacity() then
			local oldestId = queue[1]
			local oldest = bags[oldestId]
			forget(oldestId)
			lost += 1
			if onLost and oldest then
				onLost(oldest)
			end
		end

		tell(queueUpdated, queue)
	end

	function api.setQueueBonus(bonus: number)
		queueBonus = bonus
	end

	function api.setLostHandler(handler: (Types.Bag) -> ())
		onLost = handler
	end

	-- Положить чемодан на ленту. Зовёт пассажир, дошедший до приёмки:
	-- сама лента ничего не порождает.
	function api.putBag(ownerId: string)
		if bagCount >= Config.BeltCapacity then
			return -- лента забита: это и есть завал
		end
		lastPutAt = now()

		local bag = makeBag(ownerId)
		bags[bag.id] = bag
		bagCount += 1
		tell(bagSpawned, bag)
	end

	function api.getStats(): { onBelt: number, queued: number, lost: number }
		-- Едущие по ленте — это все за вычетом тех, кто уже доехал и ждёт
		-- в очереди.
		return { onBelt = bagCount - #queue, queued = #queue, lost = lost }
	end

	-- Готова ли лента принять ещё один чемодан. Проверяет и загрузку,
	-- и просвет: без просвета чемоданы слипаются в одной точке.
	function api.canAcceptBag(): boolean
		if bagCount - #queue >= Config.TargetBagsOnBelt then
			return false
		end
		if bagCount >= Config.BeltCapacity then
			return false
		end
		return now() - lastPutAt >= Config.MinBagGapSeconds
	end

	-- Чемодан, ближе всех подъехавший к концу ленты: он появился раньше
	-- прочих. Игрок работает именно с ним, поэтому очередь разбирается
	-- по порядку, а не выборочно.
	function api.getFrontmost(): Types.Bag?
		local frontmost: Types.Bag? = nil
		for _, bag in bags do
			if frontmost == nil or bag.spawnedAt < frontmost.spawnedAt then
				frontmost = bag
			end
		end
		return frontmost
	end

	-- Снять чемодан после того, как его отсортировали. В отличие от
	-- переполнения не увеличивает счётчик потерянных.
	function api.take(bagId: string): Types.Bag?
		local bag = bags[bagId]
		if bag == nil then
			return nil
		end
		forget(bagId)
		tell(queueUpdated, queue)
		return bag
	end

	-- Захвативший плот должен увидеть то, что уже едет.
	function api.sendSnapshot(player: Player)
		for _, bag in bags do
			bagSpawned:FireClient(player, bag)
		end
		queueUpdated:FireClient(player, queue)
	end

	function api.step(_deltaTime: number)
		local current = now()
		for _, bag in bags do
			local arrived = current - bag.spawnedAt >= Config.BeltTravelSeconds
			if arrived and table.find(queue, bag.id) == nil then
				enqueue(bag)
			end
		end
	end

	function api.destroy()
		for id in bags do
			tell(bagDespawned, id)
		end
		table.clear(bags)
		table.clear(queue)
		bagCount = 0
		lost = 0
		onLost = nil
	end

	return api
end

return BeltService
