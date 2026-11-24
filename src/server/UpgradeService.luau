--!strict
-- Улучшения аэропорта. Один экземпляр на плот.
--
-- Деньги принадлежат игроку и живут в EconomyService, а уровни
-- улучшений принадлежат аэропорту и живут здесь: если игрок сменит
-- плот, деньги останутся при нём, а прокачка — при участке.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local EconomyService = require(script.Parent.EconomyService)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)

local UpgradeService = {}

export type Row = {
	id: string,
	displayName: string,
	price: number,
	owned: number,
	maxCount: number,
}

export type Upgrades = {
	getLevel: (id: string) -> number,
	buy: (player: Player, id: string) -> (),
	sendState: (player: Player) -> (),
	destroy: () -> (),
}

local function upgradeById(id: string): Types.Upgrade?
	for _, upgrade in Config.Upgrades do
		if upgrade.id == id then
			return upgrade
		end
	end
	return nil
end

function UpgradeService.new(plot: any, onChanged: (() -> ())?): Upgrades
	local shopChanged = Remotes.get("ShopChanged")
	local levels: { [string]: number } = {}

	local api = {}

	-- Цена следующей покупки: база, умноженная на рост в степени
	-- количества уже купленных. Смысл роста — держать время до
	-- следующей покупки примерно постоянным.
	local function priceOf(upgrade: Types.Upgrade): number
		local owned = levels[upgrade.id] or 0
		return math.floor(upgrade.baseCost * Config.CostGrowth ^ owned)
	end

	local function state(): { Row }
		local rows: { Row } = {}
		for _, upgrade in Config.Upgrades do
			table.insert(rows, {
				id = upgrade.id,
				displayName = upgrade.displayName,
				price = priceOf(upgrade),
				owned = levels[upgrade.id] or 0,
				maxCount = upgrade.maxCount,
			})
		end
		return rows
	end

	function api.getLevel(id: string): number
		return levels[id] or 0
	end

	function api.sendState(player: Player)
		shopChanged:FireClient(player, state())
	end

	function api.buy(player: Player, id: string)
		-- Прокачивать можно только свой аэропорт.
		if plot.owner ~= player then
			return
		end

		local upgrade = upgradeById(id)
		if upgrade == nil then
			return
		end

		local owned = levels[id] or 0
		if owned >= upgrade.maxCount then
			return
		end

		local price = priceOf(upgrade)
		if EconomyService.getMoney(player) < price then
			return
		end

		EconomyService.add(player, -price)
		levels[id] = owned + 1
		api.sendState(player)

		if onChanged then
			onChanged()
		end
	end

	function api.destroy()
		table.clear(levels)
	end

	return api
end

return UpgradeService
