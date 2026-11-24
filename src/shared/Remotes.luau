--!strict
-- Каналы связи между сервером и клиентом.
--
-- Сервер создаёт канал при первом обращении, клиент его дожидается.
-- Благодаря этому порядок запуска скриптов не важен.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "Remotes"

local Remotes = {}

-- Все каналы игры перечислены здесь, чтобы сервер мог создать их сразу
-- при запуске.
--
-- Это не формальность: часть каналов создаётся внутри аэропорта, то есть
-- только после захвата плота. Клиент же ждёт их при старте и без этого
-- списка виснет на ожидании канала, которого ещё нет.
local NAMES = {
	"AirportState",
	"BagDespawned",
	"BagSpawned",
	"BuyUpgrade",
	"CheckDecision",
	"CheckReady",
	"CheckStarted",
	"ClaimPlot",
	"CodeResult",
	"PlotListing",
	"QueueUpdated",
	"RedeemCode",
	"RequestPlots",
	"SecurityAlert",
	"SecurityResult",
	"SetAirportOpen",
	"ShopChanged",
	"SortResult",
	"WalletChanged",
}

function Remotes.get(name: string): RemoteEvent
	if RunService:IsServer() then
		local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if folder == nil then
			local created = Instance.new("Folder")
			created.Name = FOLDER_NAME
			created.Parent = ReplicatedStorage
			folder = created
		end
		assert(folder ~= nil, "remote folder missing")

		local existing = folder:FindFirstChild(name)
		if existing then
			return existing :: RemoteEvent
		end

		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
		return remote
	end

	local folder = ReplicatedStorage:WaitForChild(FOLDER_NAME)
	return folder:WaitForChild(name) :: RemoteEvent
end

-- Зовётся сервером один раз при запуске, до появления игроков.
function Remotes.ensureAll()
	for _, name in NAMES do
		Remotes.get(name)
	end
end

return Remotes
