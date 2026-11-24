--!strict
-- Точка входа сервера.
--
-- Здесь только глобальное: проверка конфига, деньги, коды, карта плотов
-- и каналы связи. Всё, что относится к конкретному аэропорту, собирает
-- PlotRuntime — по одному набору на плот.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CodeService = require(script.Parent.CodeService)
local Config = require(ReplicatedStorage.Shared.Config)
local EconomyService = require(script.Parent.EconomyService)
local PlotRuntime = require(script.Parent.PlotRuntime)
local PlotService = require(script.Parent.PlotService)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

-- ─────────────────────────────────────────────────────────────
-- Проверка конфига
-- ─────────────────────────────────────────────────────────────
--
-- Смысл в том, чтобы опечатка в числе — например, 25 вместо 0.25 в доле
-- оффлайн-дохода — обнаруживалась при запуске, а не через неделю по
-- кривым метрикам.

local problems: { string } = {}

local function expect(condition: boolean, message: string)
	if not condition then
		table.insert(problems, message)
	end
end

local function isShare(value: number): boolean
	return value >= 0 and value <= 1
end

expect(Config.PassengerInterval > 0, "PassengerInterval must be above zero")
expect(Config.TargetBagsOnBelt >= 1, "TargetBagsOnBelt must be at least 1")
expect(Config.PassengerSpeed > 0, "PassengerSpeed must be above zero")
expect(Config.BeltTravelSeconds > 0, "BeltTravelSeconds must be above zero")
expect(Config.BeltCapacity >= 1, "BeltCapacity must be at least 1")
expect(Config.QueueCapacity >= 1, "QueueCapacity must be at least 1")
expect(Config.LineCapacity >= 1, "LineCapacity must be at least 1")
expect(Config.WaitCapacity >= 1, "WaitCapacity must be at least 1")
expect(Config.WaitPerRow >= 1, "WaitPerRow must be at least 1")
expect(Config.BasePayPerBag > 0, "BasePayPerBag must be above zero")
expect(Config.VipPayMultiplier >= 1, "VipPayMultiplier must be at least 1")
expect(Config.CostGrowth > 1, "CostGrowth must be above 1, otherwise prices never rise")
expect(Config.PlotCount >= 1, "PlotCount must be at least 1")
expect(Config.PlotColumns >= 1, "PlotColumns must be at least 1")

-- Доли — это доли, а не проценты. Самая вероятная опечатка во всём файле.
expect(isShare(Config.OversizedChance), "OversizedChance must be between 0 and 1")
expect(isShare(Config.FragileChance), "FragileChance must be between 0 and 1")
expect(isShare(Config.FlaggedChance), "FlaggedChance must be between 0 and 1")
expect(isShare(Config.VipChance), "VipChance must be between 0 and 1")
expect(isShare(Config.OfflineRate), "OfflineRate must be between 0 and 1")
expect(isShare(Config.SuspiciousChance), "SuspiciousChance must be between 0 and 1")
expect(isShare(Config.BeepChance), "BeepChance must be between 0 and 1")
expect(isShare(Config.GuiltyChance), "GuiltyChance must be between 0 and 1")

expect(Config.BacklogCapSeconds > 0, "BacklogCapSeconds must be above zero")
expect(#Config.Destinations > 1, "Need at least two destinations to sort between")
expect(#Config.Tiers == Config.MaxTier, "Tiers list does not match MaxTier")

-- Ступени должны идти по возрастанию, иначе правило откроется раньше предыдущего.
for i = 2, #Config.Tiers do
	expect(
		Config.Tiers[i].unlockAtBags > Config.Tiers[i - 1].unlockAtBags,
		string.format("Tier %d unlocks no later than tier %d", i, i - 1)
	)
end

if #problems > 0 then
	for _, message in problems do
		warn("[config] " .. message)
	end
	error(string.format("[config] %d problem(s) found — fix Config.luau", #problems))
end

print(string.format("[server] %s v%s ready", Config.GameName, Config.Version))

-- ─────────────────────────────────────────────────────────────
-- Глобальные службы
-- ─────────────────────────────────────────────────────────────

-- Каналы связи создаём до всего остального: часть из них рождается
-- внутри аэропорта, а клиент ждёт их сразу при входе.
Remotes.ensureAll()

EconomyService.start()
CodeService.start()

-- Промокоды: список и решение живут на сервере, клиент шлёт только строку.
local codeResult = Remotes.get("CodeResult")
Remotes.get("RedeemCode").OnServerEvent:Connect(function(player, raw)
	local outcome, money = CodeService.redeem(player, raw)
	codeResult:FireClient(player, { outcome = outcome, money = money })
end)

-- ─────────────────────────────────────────────────────────────
-- Аэропорты по плотам
-- ─────────────────────────────────────────────────────────────

local runtimes: { [number]: any } = {}

local function runtimeOf(player: Player): any?
	local plot = PlotService.plotOf(player)
	return if plot then runtimes[plot.index] else nil
end

PlotService.setClaimHandler(function(plot)
	runtimes[plot.index] = PlotRuntime.new(plot)

	-- Переносим хозяина к своему аэропорту: иначе он остаётся на точке
	-- спавна и идти ему через всю карту.
	local owner = plot.owner
	if owner then
		local character = owner.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			root.CFrame = CFrame.new(
				plot.origin + Config.BuildingCenter + Vector3.new(-Config.BuildingSize.X * 0.5 - 20, 2, 0)
			)
		end
	end

	print(string.format("[server] plot %d claimed by %s", plot.index,
		if owner then owner.Name else "?"))
end)

PlotService.setReleaseHandler(function(plot)
	local runtime = runtimes[plot.index]
	if runtime then
		runtime.destroy()
		runtimes[plot.index] = nil
	end
	print(string.format("[server] plot %d released", plot.index))
end)

-- ─────────────────────────────────────────────────────────────
-- Каналы от клиента
-- ─────────────────────────────────────────────────────────────
--
-- Каждый проверяет, что игрок распоряжается своим аэропортом:
-- чужим управлять нельзя, даже зайдя в гости.

Remotes.get("SetAirportOpen").OnServerEvent:Connect(function(player, open)
	local runtime = runtimeOf(player)
	if runtime and typeof(open) == "boolean" then
		runtime.setOpen(open)
	end
end)

Remotes.get("CheckDecision").OnServerEvent:Connect(function(player, payload)
	local runtime = runtimeOf(player)
	if runtime == nil or typeof(payload) ~= "table" then
		return
	end
	local id = payload.passengerId
	local detain = payload.detain
	if typeof(id) ~= "string" or typeof(detain) ~= "boolean" then
		return
	end
	runtime.passengers.decide(id, detain)
end)

Remotes.get("BuyUpgrade").OnServerEvent:Connect(function(player, id)
	local runtime = runtimeOf(player)
	if runtime and typeof(id) == "string" then
		runtime.upgrades.buy(player, id)
	end
end)

-- ─────────────────────────────────────────────────────────────
-- Карта
-- ─────────────────────────────────────────────────────────────

PlotService.start()

local plotListing = Remotes.get("PlotListing")

local function pushListing()
	plotListing:FireAllClients(PlotService.listing())
end

Remotes.get("ClaimPlot").OnServerEvent:Connect(function(player, index)
	if typeof(index) == "number" then
		PlotService.claim(player, index)
		pushListing()
	end
end)

Remotes.get("RequestPlots").OnServerEvent:Connect(function(player)
	plotListing:FireClient(player, PlotService.listing())
end)

Players.PlayerRemoving:Connect(function()
	task.defer(pushListing)
end)

print(string.format("[server] map ready: %d plots, waiting for a claim", Config.PlotCount))
