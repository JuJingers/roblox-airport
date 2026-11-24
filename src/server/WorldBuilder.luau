--!strict
-- Собирает серую геометрию сцены из кода.
--
-- Строим кодом, а не руками в Studio, чтобы сцена лежала в git и
-- восстанавливалась одинаково. Текстур и моделей здесь нет и на этом
-- шаге быть не должно: если на серых кубах играть неинтересно,
-- графика этого не исправит.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local RuleSet = require(ReplicatedStorage.Shared.RuleSet)
local Types = require(ReplicatedStorage.Shared.Types)

local WorldBuilder = {}

local CHUTE_ATTRIBUTE = "ChuteId"

-- Цвета для жёлобов, у которых нет своего направления.
local SPECIAL_CHUTE_COLORS: { [string]: Color3 } = {
	Oversized = Color3.fromRGB(150, 110, 190),
	Fragile = Color3.fromRGB(220, 140, 90),
	Security = Color3.fromRGB(90, 90, 100),
}

local function makePart(name: string, size: Vector3, position: Vector3, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Position = position
	part.Color = color
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

-- Принимает обычную строку, а не Types.ChuteId: функция всего лишь ищет
-- цвет по имени, и лишнее приведение типов здесь ничего не защищает.
local function chuteColor(chuteId: string): Color3
	local byDestination: { [string]: Color3 } = Config.DestinationColors
	return byDestination[chuteId] or SPECIAL_CHUTE_COLORS[chuteId] or Color3.fromRGB(180, 180, 180)
end

local function buildChutes(origin: Vector3, folder: Folder, tier: number)
	local chutes = RuleSet.chutesForTier(tier, Config.Destinations)
	local count = #chutes

	local startPoint = (origin + Config.BeltStart)
	local endPoint = (origin + Config.BeltEnd)
	local span = endPoint - startPoint

	-- Раскладываем приёмники вдоль ленты, отступив в сторону.
	local sideways = Vector3.new(0, 0, Config.BeltWidth * 0.5 + 6)

	for index, chuteId in chutes do
		-- Равномерно по длине ленты, не прижимая к самым краям.
		local along = (index - 0.5) / count
		local position = startPoint + span * along + sideways - Vector3.new(0, 2, 0)

		local chute = makePart(
			"Chute_" .. chuteId,
			Vector3.new(8, 4, 8),
			position,
			chuteColor(chuteId)
		)
		chute:SetAttribute(CHUTE_ATTRIBUTE, chuteId)

		-- ClickDetector срабатывает на сервере и работает как на мыши,
		-- так и на касании. Отдельный канал связи для ввода не нужен.
		local detector = Instance.new("ClickDetector")
		detector.MaxActivationDistance = 200
		detector.Parent = chute

		chute.Parent = folder
	end
end

-- Рамка досмотра: через неё проходит пассажир после того, как сдал багаж.
-- Пока это просто ворота — механика досмотра появится следующим шагом.
local function buildFrame(origin: Vector3, folder: Folder)
	local at = (origin + Config.FramePosition)
	local pillar = Vector3.new(1.5, 10, 1.5)
	local grey = Color3.fromRGB(158, 164, 172)

	makePart("FrameLeft", pillar, at - Vector3.new(3.5, 0, 0), grey).Parent = folder
	makePart("FrameRight", pillar, at + Vector3.new(3.5, 0, 0), grey).Parent = folder
	makePart("FrameTop", Vector3.new(8.5, 1.5, 1.5), at + Vector3.new(0, 5.5, 0), grey).Parent = folder
end

-- Будка охраны: сюда уводят задержанных.
local function buildBooth(origin: Vector3, folder: Folder)
	local at = (origin + Config.GuardBooth)
	local wall = Color3.fromRGB(96, 112, 150)
	makePart("BoothFloor", Vector3.new(16, 1, 12), at - Vector3.new(0, 3, 0), wall).Parent = folder
	makePart("BoothBack", Vector3.new(16, 8, 1), at + Vector3.new(0, 1, -6), wall).Parent = folder
	makePart("BoothLeft", Vector3.new(1, 8, 12), at + Vector3.new(-8, 1, 0), wall).Parent = folder
	makePart("BoothRight", Vector3.new(1, 8, 12), at + Vector3.new(8, 1, 0), wall).Parent = folder
end

-- Здание аэропорта: общий пол, стены по периметру, проёмы входа
-- и выхода, вывеска. Всё происходящее — внутри него.
--
-- Крыши нет намеренно: сверху смотрит камера, и накрытое здание
-- превратилось бы в чёрный ящик.
local function buildBuilding(origin: Vector3, folder: Folder)
	local center = (origin + Config.BuildingCenter)
	local width = Config.BuildingSize.X
	local depth = Config.BuildingSize.Y
	local wall = Config.WallHeight
	local floorColor = Color3.fromRGB(104, 110, 122)
	local wallColor = Color3.fromRGB(132, 140, 154)

	makePart("Floor", Vector3.new(width, 1, depth),
		center - Vector3.new(0, 3, 0), floorColor).Parent = folder

	local wallY = wall * 0.5 - 2.5

	-- Продольные стены целиком.
	makePart("WallFar", Vector3.new(width, wall, 2),
		center + Vector3.new(0, wallY, -depth * 0.5), wallColor).Parent = folder
	makePart("WallNear", Vector3.new(width, wall, 2),
		center + Vector3.new(0, wallY, depth * 0.5), wallColor).Parent = folder

	-- Торцевые стены с проёмами: вход слева, выход справа.
	local function endWall(name: string, sideX: number, doorWidth: number)
		local piece = (depth - doorWidth) * 0.5
		local offset = (doorWidth + piece) * 0.5
		for _, direction in { -1, 1 } do
			makePart(name, Vector3.new(2, wall, piece),
				center + Vector3.new(sideX, wallY, direction * offset),
				wallColor).Parent = folder
		end
	end

	endWall("WallEntry", -width * 0.5, Config.EntryDoorWidth)
	endWall("WallExit", width * 0.5, Config.ExitDoorWidth)

	-- Перемычка над входом и сама вывеска на ней.
	--
	-- Ширина ровно по проёму, а верх заподлицо с верхом стены: раньше
	-- перемычка была шире двери и заходила на стену той же толщины,
	-- отчего мерцала, а сверху ещё и торчала над стеной.
	local lintelHeight = 5
	local lintel = makePart("EntryLintel", Vector3.new(2, lintelHeight, Config.EntryDoorWidth),
		center + Vector3.new(-width * 0.5, wallY + wall * 0.5 - lintelHeight * 0.5, 0),
		Color3.fromRGB(150, 158, 172))
	lintel.Parent = folder

	local sign = Instance.new("SurfaceGui")
	sign.Name = "Sign"
	sign.Face = Enum.NormalId.Left
	sign.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sign.PixelsPerStud = 50
	sign.Parent = lintel

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(245, 248, 252)
	label.Text = "AIRPORT"
	label.Parent = sign

	-- Размеченные места под декор.
	for index, slot in Config.DecorSlots do
		local worldSlot = (origin + slot)
		local pad = makePart(
			string.format("DecorSlot_%d", index),
			Vector3.new(6, 0.4, 6),
			worldSlot - Vector3.new(0, 2.8, 0),
			Color3.fromRGB(88, 94, 106)
		)
		pad:SetAttribute("SlotIndex", index)
		pad.Parent = folder
	end
end

-- Меняет надпись на вывеске. По умолчанию это ник игрока, но текст
-- можно будет задать любой.
function WorldBuilder.setSignText(folder: Folder, text: string)
	local lintel = folder:FindFirstChild("EntryLintel")
	if lintel == nil then
		return
	end
	local sign = lintel:FindFirstChild("Sign")
	local label = sign and sign:FindFirstChild("Text")
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

-- Строит аэропорт внутрь переданной папки. Координаты берутся от
-- начала активного плота, поэтому восемь аэропортов не встают друг
-- на друга.
-- origin — начало плота. Передаётся явно: общего «текущего плота»
-- на сервере нет и быть не должно, аэропортов восемь.
function WorldBuilder.build(site: Folder, origin: Vector3, tier: number)
	site:ClearAllChildren()
	local folder = site

	local startPoint = (origin + Config.BeltStart)
	local endPoint = (origin + Config.BeltEnd)
	local span = endPoint - startPoint
	local length = span.Magnitude
	local middle = startPoint + span * 0.5

	-- Полотно ленты.
	local belt = makePart(
		"Belt",
		Vector3.new(length, 1, Config.BeltWidth),
		middle - Vector3.new(0, 1, 0),
		Color3.fromRGB(78, 84, 92)
	)
	belt.Parent = folder

	-- Метки начала и конца — чтобы глазом было видно направление движения.
	local marker = Vector3.new(1, 3, Config.BeltWidth + 2)
	makePart("StartMarker", marker, startPoint, Color3.fromRGB(120, 128, 138)).Parent = folder
	makePart("EndMarker", marker, endPoint, Color3.fromRGB(150, 90, 90)).Parent = folder

	buildBuilding(origin, folder)
	buildChutes(origin, folder, tier)
	buildFrame(origin, folder)
	buildBooth(origin, folder)

	return folder
end

-- Подписывает все жёлоба на обработчик. Вынесено сюда, чтобы строитель
-- мира ничего не знал про правила начисления.
function WorldBuilder.connectChutes(folder: Folder, handler: (Player, Types.ChuteId) -> ())
	for _, child in folder:GetChildren() do
		local chuteId = child:GetAttribute(CHUTE_ATTRIBUTE)
		if typeof(chuteId) == "string" then
			local detector = child:FindFirstChildOfClass("ClickDetector")
			if detector then
				detector.MouseClick:Connect(function(player)
					handler(player, chuteId :: Types.ChuteId)
				end)
			end
		end
	end
end

return WorldBuilder
