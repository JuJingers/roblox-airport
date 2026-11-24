--!strict
-- Живой аэропорт одного плота: мир, лента, пассажиры, судья, улучшения.
--
-- Здесь собирается всё, что раньше висело на уровне модулей и потому
-- было одно на весь сервер. Теперь у каждого плота свой набор, и восемь
-- аэропортов не мешают друг другу.
--
-- Точка входа сервера этих связей не знает: она лишь просит создать
-- аэропорт при захвате плота и снести при уходе.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BeltService = require(script.Parent.BeltService)
local Config = require(ReplicatedStorage.Shared.Config)
local PassengerService = require(script.Parent.PassengerService)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local SortingService = require(script.Parent.SortingService)
local UpgradeService = require(script.Parent.UpgradeService)
local WorldBuilder = require(script.Parent.WorldBuilder)

local PlotRuntime = {}

local STARTING_TIER = 1

export type Runtime = {
	plot: any,
	belt: any,
	passengers: any,
	sorting: any,
	upgrades: any,
	setOpen: (open: boolean) -> (),
	destroy: () -> (),
}

local airportState = Remotes.get("AirportState")
local securityResult = Remotes.get("SecurityResult")
local securityAlert = Remotes.get("SecurityAlert")

function PlotRuntime.new(plot: any): Runtime
	local owner = plot.owner

	-- Лента объявлена заранее: улучшениям нужен обработчик покупки,
	-- а он обращается к ленте. Ссылка проставляется следующей строкой.
	local belt
	local upgrades

	upgrades = UpgradeService.new(plot, function()
		-- Улучшение мест в очереди принадлежит аэропорту, поэтому лента
		-- получает прибавку снаружи и сама про магазин не знает.
		if belt then
			local effect = Config.UpgradeEffects.ExtraStorage
			belt.setQueueBonus(effect.queueBonus * upgrades.getLevel("ExtraStorage"))
		end
	end)

	belt = BeltService.new(plot)
	local sorting = SortingService.new(plot, belt)
	local passengers = PassengerService.new(plot, belt, upgrades)

	-- Мир строится в папку своего плота и от его начала.
	local site = plot.folder:FindFirstChild("Airport") :: Folder
	local terminal = WorldBuilder.build(site, plot.origin, STARTING_TIER)
	WorldBuilder.connectChutes(terminal, sorting.trySort)
	WorldBuilder.setSignText(
		terminal,
		if owner then string.upper(owner.Name) .. Config.SignSuffix else "AIRPORT"
	)

	sorting.setTier(STARTING_TIER)

	-- Потерянный при переполнении чемодан засчитывается как промах.
	belt.setLostHandler(sorting.registerLoss)

	-- Хозяин чемодана ждёт за рамкой и уходит довольным или расстроенным.
	sorting.setResolvedHandler(passengers.resolveBag)

	-- Итоги досмотра и состояние прохода уходят только владельцу.
	passengers.setSearchHandler(function(correct: boolean, wasSearch: boolean)
		if owner == nil then
			return
		end
		securityResult:FireClient(owner, { correct = correct, wasSearch = wasSearch })
	end)
	passengers.setAlertHandler(function(blocked: boolean)
		if owner then
			securityAlert:FireClient(owner, blocked)
		end
	end)

	passengers.buildForPlot()
	passengers.start()

	local runtime = {
		plot = plot,
		belt = belt,
		passengers = passengers,
		sorting = sorting,
		upgrades = upgrades,
	}

	-- Лента продвигается вместе с пассажирами: отдельный обработчик ей
	-- не нужен, а один общий проще выключать при сносе.
	local heartbeat = game:GetService("RunService").Heartbeat:Connect(belt.step)

	function runtime.setOpen(open: boolean)
		passengers.setOpen(open)
		if owner then
			airportState:FireClient(owner, { claimed = true, open = open, origin = plot.origin })
		end
	end

	function runtime.destroy()
		heartbeat:Disconnect()
		passengers.teardown()
		belt.destroy()
		sorting.destroy()
		upgrades.destroy()
		site:ClearAllChildren()
		if owner then
			airportState:FireClient(owner, { claimed = false, open = false, origin = nil })
		end
	end

	if owner then
		belt.sendSnapshot(owner)
		upgrades.sendState(owner)
		airportState:FireClient(owner, { claimed = true, open = false, origin = plot.origin })
	end

	return runtime
end

return PlotRuntime
