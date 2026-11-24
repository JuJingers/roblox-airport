--!strict
-- Судит попытки сортировки. Один экземпляр на плот.
--
-- Это единственное место, где решается «верно или мимо». Клиент лишь
-- сообщает намерение — в какой жёлоб он отправляет, — а какой чемодан
-- сейчас на очереди и правильный ли это жёлоб, определяет сервер.
--
-- Состояние держится внутри экземпляра, а не в модуле: иначе восемь
-- аэропортов делили бы один счётчик и один ограничитель частоты.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EconomyService = require(script.Parent.EconomyService)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RuleSet = require(ReplicatedStorage.Shared.RuleSet)
local Types = require(ReplicatedStorage.Shared.Types)

local SortingService = {}

-- Ограничитель частоты. Без него канал превращается в способ
-- положить сервер, а заодно в способ разобрать ленту одним махом.
local MIN_SECONDS_BETWEEN_SORTS = 0.15

export type Tally = { correct: number, wrong: number }

export type Sorting = {
	trySort: (player: Player, chuteId: Types.ChuteId) -> (),
	registerLoss: (bag: Types.Bag) -> (),
	setResolvedHandler: (handler: (string, boolean) -> ()) -> (),
	getTally: (player: Player) -> Tally,
	setTier: (tier: number) -> (),
	destroy: () -> (),
}

-- plot и belt относятся к одному аэропорту. Передаются, а не берутся
-- из модуля: судья обязан судить именно свою ленту и уведомлять
-- именно своих.
function SortingService.new(plot: any, belt: any): Sorting
	local sortResult = Remotes.get("SortResult")

	local onResolved: ((string, boolean) -> ())? = nil
	local lastSortAt: { [Player]: number } = {}
	local tally: { [Player]: Tally } = {}

	-- Ступень пока одна: профилей игроков ещё нет.
	local tier = 1

	local api = {}

	local function tallyFor(player: Player): Tally
		local existing = tally[player]
		if existing then
			return existing
		end
		local created: Tally = { correct = 0, wrong = 0 }
		tally[player] = created
		return created
	end

	function api.setTier(value: number)
		tier = value
	end

	function api.setResolvedHandler(handler: (string, boolean) -> ())
		onResolved = handler
	end

	function api.getTally(player: Player): Tally
		return tallyFor(player)
	end

	function api.trySort(player: Player, chuteId: Types.ChuteId)
		local now = workspace:GetServerTimeNow()
		local last = lastSortAt[player]
		if last ~= nil and now - last < MIN_SECONDS_BETWEEN_SORTS then
			return -- частим: молча игнорируем
		end
		lastSortAt[player] = now

		local bag = belt.getFrontmost()
		if bag == nil then
			return -- на ленте пусто, отправлять нечего
		end

		local correctChute = RuleSet.correctChute(bag, tier)
		local correct = chuteId == correctChute

		-- Снимаем чемодан в любом случае: ошибка тоже разбирает очередь,
		-- иначе игрок застревает на одном чемодане.
		local taken = belt.take(bag.id)
		if taken == nil then
			return -- кто-то успел раньше
		end

		local counts = tallyFor(player)
		if correct then
			counts.correct += 1
		else
			counts.wrong += 1
		end

		EconomyService.payForBag(player, bag, correct)

		if onResolved then
			onResolved(bag.ownerId, correct)
		end

		sortResult:FireClient(player, {
			bagId = bag.id,
			correct = correct,
			chosenChute = chuteId,
			correctChute = correctChute,
			correctCount = counts.correct,
			wrongCount = counts.wrong,
		})
	end

	-- Чемодан, потерянный при переполнении очереди, — тоже промах.
	-- Зовётся лентой, которая про начисления ничего не знает.
	--
	-- Сообщаем владельцу этого плота, а не всем на сервере: раньше
	-- уведомление уходило каждому, включая чужие аэропорты.
	function api.registerLoss(bag: Types.Bag)
		if onResolved then
			onResolved(bag.ownerId, false)
		end

		local owner = plot.owner
		if owner == nil then
			return
		end

		local counts = tallyFor(owner)
		counts.wrong += 1
		sortResult:FireClient(owner, {
			bagId = bag.id,
			correct = false,
			chosenChute = "",
			correctChute = bag.destination,
			correctCount = counts.correct,
			wrongCount = counts.wrong,
			lostToQueue = true,
		})
	end

	function api.destroy()
		table.clear(lastSortAt)
		table.clear(tally)
		onResolved = nil
	end

	return api
end

return SortingService
