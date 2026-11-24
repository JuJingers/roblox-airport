--!strict
-- Деньги игрока.
--
-- Единственное место, где меняется баланс. Клиент никогда не присылает
-- сумму — только намерение, а решение принимает сервер.
--
-- Деньги общие для игрока и не зависят от плота: сменив участок, он
-- останется при своих. Уровни улучшений, наоборот, принадлежат
-- аэропорту и живут в UpgradeService.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)

local EconomyService = {}

local walletChanged = Remotes.get("WalletChanged")
local money: { [Player]: number } = {}

local function pushWallet(player: Player)
	walletChanged:FireClient(player, money[player] or 0)
end

function EconomyService.getMoney(player: Player): number
	return money[player] or 0
end

-- Начислить. Отрицательная сумма — штраф; баланс при этом никогда
-- не уходит ниже нуля: наказание должно раздражать, а не разорять.
function EconomyService.add(player: Player, amount: number)
	local current = money[player] or 0
	money[player] = math.max(current + amount, 0)
	pushWallet(player)
end

function EconomyService.payForBag(player: Player, bag: Types.Bag, correct: boolean)
	local value = Config.BasePayPerBag
	if bag.isVip then
		value *= Config.VipPayMultiplier
	end
	if correct then
		EconomyService.add(player, value)
	else
		EconomyService.add(player, -math.floor(value * Config.MisSortPenalty))
	end
end

function EconomyService.payForSearch(player: Player, correct: boolean)
	local value = Config.BasePayPerBag
	EconomyService.add(player, if correct then value else -value)
end

function EconomyService.start()
	Players.PlayerAdded:Connect(function(player)
		money[player] = 0
		pushWallet(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		money[player] = nil
	end)

	for _, player in Players:GetPlayers() do
		money[player] = money[player] or 0
		pushWallet(player)
	end
end

return EconomyService
