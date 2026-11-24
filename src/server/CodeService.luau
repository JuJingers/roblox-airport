--!strict
-- Промокоды.
--
-- Список лежит только здесь, на сервере. В общий конфиг его класть
-- нельзя: всё, что попадает в ReplicatedStorage, клиент читает целиком,
-- и коды разошлись бы в первый же день.
--
-- Клиент присылает строку, сервер решает. Награда начисляется тут же,
-- клиент получает только ответ «принято» или «нет».
--
-- Память о введённых кодах пока живёт до выхода из игры: постоянной
-- станет вместе с сохранениями.

local Players = game:GetService("Players")

local EconomyService = require(script.Parent.EconomyService)

local CodeService = {}

export type Outcome = "Granted" | "Unknown" | "AlreadyUsed" | "Expired"

type Reward = {
	money: number?,
}

type Code = {
	reward: Reward,
	-- Код можно погасить: раздали слишком щедро — выключили, не трогая код.
	active: boolean,
}

-- Сравнение идёт по верхнему регистру без пробелов, поэтому здесь
-- ключи можно писать как удобно.
local CODES: { [string]: Code } = {
	WELCOME = { reward = { money = 250 }, active = true },
	BAGGAGE = { reward = { money = 500 }, active = true },
	FIRSTFLIGHT = { reward = { money = 1000 }, active = true },
}

local redeemed: { [Player]: { [string]: boolean } } = {}

local function normalise(raw: string): string
	return string.upper((string.gsub(raw, "%s", "")))
end

function CodeService.redeem(player: Player, raw: string): (Outcome, number)
	if typeof(raw) ~= "string" or #raw == 0 or #raw > 40 then
		return "Unknown", 0
	end

	local key = normalise(raw)
	local code = CODES[key]
	if code == nil then
		return "Unknown", 0
	end
	if not code.active then
		return "Expired", 0
	end

	local used = redeemed[player]
	if used == nil then
		used = {}
		redeemed[player] = used
	end
	if used[key] then
		return "AlreadyUsed", 0
	end

	used[key] = true

	local money = code.reward.money or 0
	if money > 0 then
		EconomyService.add(player, money)
	end
	return "Granted", money
end

function CodeService.start()
	Players.PlayerRemoving:Connect(function(player)
		redeemed[player] = nil
	end)
end

return CodeService
