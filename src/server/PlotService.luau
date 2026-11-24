--!strict
-- Плоты: восемь мест на карте, по одному на игрока.
--
-- Игрок проходит через ворота свободного плота и получает базу. Занятые
-- плоты пускают в гости — посмотреть чужой аэропорт можно, управлять
-- нельзя. При выходе игрока плот освобождается и очищается.
--
-- Ключевое следствие для всего остального кода: координаты в Config —
-- это смещения от начала плота, а не мировые точки. Мир строится
-- относительно origin, иначе восемь аэропортов встали бы друг на друга.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local PlotService = {}

local FOLDER_NAME = "Plots"

export type Plot = {
	index: number,
	origin: Vector3,
	folder: Folder,
	owner: Player?,
}

local plots: { Plot } = {}
local claimedBy: { [Player]: number } = {}

-- Кого звать, когда плот захватили или освободили. Ставится снаружи,
-- чтобы плоты ничего не знали про игровую логику.
local onClaimed: ((Plot) -> ())? = nil
local onReleased: ((Plot) -> ())? = nil

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

-- Раскладка сеткой: колонки слева направо, строки от себя.
local function originFor(index: number): Vector3
	local zeroBased = index - 1
	local column = zeroBased % Config.PlotColumns
	local row = math.floor(zeroBased / Config.PlotColumns)

	local stepX = Config.PlotSize.X + Config.PlotGap.X
	local stepZ = Config.PlotSize.Y + Config.PlotGap.Y

	-- Центрируем сетку вокруг нуля, чтобы карта не уползала в угол.
	local columns = Config.PlotColumns
	local rows = math.ceil(Config.PlotCount / columns)
	local offsetX = (columns - 1) * stepX * 0.5
	local offsetZ = (rows - 1) * stepZ * 0.5

	return Vector3.new(column * stepX - offsetX, 0, row * stepZ - offsetZ)
end

local function buildPlot(index: number, parent: Folder): Plot
	local origin = originFor(index)

	local folder = Instance.new("Folder")
	folder.Name = string.format("Plot_%d", index)
	folder.Parent = parent

	-- Земля плота. Толщиной до самой общей земли: тонкая плита висела
	-- над пустотой и торчала бортиком по краям.
	makePart(
		"Ground",
		Vector3.new(Config.PlotSize.X, 4, Config.PlotSize.Y),
		origin + Vector3.new(0, -2, 0),
		Color3.fromRGB(118, 126, 118)
	).Parent = folder

	-- Место под здание: сюда WorldBuilder положит аэропорт.
	local site = Instance.new("Folder")
	site.Name = "Airport"
	site.Parent = folder

	return {
		index = index,
		origin = origin,
		folder = folder,
		owner = nil,
	}
end

-- Тропинки между плотами.
--
-- Продольные идут насквозь, поперечные — отрезками между ними. Если
-- класть и те и другие на всю длину, они пересекаются на одной высоте
-- и мерцают: видеокарта не может решить, что рисовать поверх.
local function buildPaths(parent: Folder)
	local stepX = Config.PlotSize.X + Config.PlotGap.X
	local stepZ = Config.PlotSize.Y + Config.PlotGap.Y
	local columns = Config.PlotColumns
	local rows = math.ceil(Config.PlotCount / columns)

	local offsetX = (columns - 1) * stepX * 0.5
	local offsetZ = (rows - 1) * stepZ * 0.5

	-- Продольные тянутся и через внешние поперечные полосы, иначе
	-- в углах сетки остаются дыры.
	local spanZ = rows * stepZ + Config.PlotGap.Y
	local color = Color3.fromRGB(146, 150, 158)

	-- Тропинка занимает промежуток целиком. Узкая полоса оставляла по
	-- краям открытую общую землю на -4, и между участками получались
	-- траншеи в четыре единицы вместо ровной поверхности.
	local widthX = Config.PlotGap.X
	local widthZ = Config.PlotGap.Y

	-- Продольные: по одной в каждом промежутке между колонками.
	for column = 0, columns do
		local x = (column - 0.5) * stepX - offsetX
		makePart("PathColumn", Vector3.new(widthX, 4, spanZ),
			Vector3.new(x, -2, 0), color).Parent = parent
	end

	-- Поперечные: отрезками над самими участками, чтобы не наезжать
	-- на продольные.
	for row = 0, rows do
		local z = (row - 0.5) * stepZ - offsetZ
		for column = 0, columns - 1 do
			local x = column * stepX - offsetX
			makePart("PathRow", Vector3.new(Config.PlotSize.X, 4, widthZ),
				Vector3.new(x, -2, z), color).Parent = parent
		end
	end
end

function PlotService.getPlot(index: number): Plot?
	return plots[index]
end

function PlotService.plotOf(player: Player): Plot?
	local index = claimedBy[player]
	return if index then plots[index] else nil
end

function PlotService.setClaimHandler(handler: (Plot) -> ())
	onClaimed = handler
end

function PlotService.setReleaseHandler(handler: (Plot) -> ())
	onReleased = handler
end

local function release(player: Player)
	local index = claimedBy[player]
	if index == nil then
		return
	end
	local plot = plots[index]
	claimedBy[player] = nil
	plot.owner = nil

	-- Плот очищается: сохранений пока нет, вернувшийся начнёт заново.
	local site = plot.folder:FindFirstChild("Airport")
	if site then
		site:ClearAllChildren()
	end

	if onReleased then
		onReleased(plot)
	end
end

-- Захват идёт из меню выбора плота, а не проходом через ворота.
function PlotService.claim(player: Player, index: number)
	if claimedBy[player] ~= nil then
		return -- у игрока уже есть плот
	end
	local plot = plots[index]
	if plot == nil or plot.owner ~= nil then
		return -- занят: пускаем в гости, но не отдаём
	end

	plot.owner = player
	claimedBy[player] = index

	if onClaimed then
		onClaimed(plot)
	end
end

-- Что показать в меню выбора: свободен плот или чей он.
function PlotService.listing(): { { index: number, origin: Vector3, owner: string? } }
	local rows = {}
	for index, plot in plots do
		table.insert(rows, {
			index = index,
			origin = plot.origin,
			owner = if plot.owner then plot.owner.Name else nil,
		})
	end
	return rows
end

-- Базовая платформа Studio лежит верхом ровно на y=0 — там же, где верх
-- земли плотов. Две совпадающие плоскости и давали мерцание.
--
-- Земли ниже сетки не держим вовсе: любая плита под ней даёт обрыв по
-- внешнему краю. Вместо неё окантовка в тот же уровень, что и участки.
local MARGIN = 260

local function gridExtent(): (number, number)
	local stepX = Config.PlotSize.X + Config.PlotGap.X
	local stepZ = Config.PlotSize.Y + Config.PlotGap.Y
	local columns = Config.PlotColumns
	local rows = math.ceil(Config.PlotCount / columns)
	-- Внешние тропинки выходят за крайние участки на половину промежутка
	-- с каждой стороны, поэтому к обоим размерам добавляется целый
	-- промежуток. Без этого окантовка налезала на сетку по оси X.
	return columns * stepX + Config.PlotGap.X, rows * stepZ + Config.PlotGap.Y
end

local function replaceBaseplate(parent: Folder)
	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end
	local stale = workspace:FindFirstChild("MapGround")
	if stale then
		stale:Destroy()
	end

	local spanX, spanZ = gridExtent()
	local halfX, halfZ = spanX * 0.5, spanZ * 0.5
	local color = Color3.fromRGB(118, 126, 118)
	local outX = halfX + MARGIN * 0.5
	local outZ = halfZ + MARGIN * 0.5

	-- Одной полосой на всю ширину не обойтись: у деталей Roblox предел
	-- размера 2048 единиц, и слишком длинная молча обрезается. Именно
	-- так у карты пропадали углы — ошибки при этом не возникает.
	local function slab(size: Vector3, at: Vector3)
		assert(size.X <= 2048 and size.Z <= 2048, "деталь длиннее предела Roblox")
		makePart("Border", size, at, color).Parent = parent
	end

	-- Стороны: ровно по размеру сетки, встык к ней.
	slab(Vector3.new(spanX, 4, MARGIN), Vector3.new(0, -2, -outZ))
	slab(Vector3.new(spanX, 4, MARGIN), Vector3.new(0, -2, outZ))
	slab(Vector3.new(MARGIN, 4, spanZ), Vector3.new(-outX, -2, 0))
	slab(Vector3.new(MARGIN, 4, spanZ), Vector3.new(outX, -2, 0))

	-- Углы: их не закрывает ни одна из сторон.
	for _, corner in { Vector2.new(-1, -1), Vector2.new(1, -1), Vector2.new(-1, 1), Vector2.new(1, 1) } do
		slab(Vector3.new(MARGIN, 4, MARGIN), Vector3.new(corner.X * outX, -2, corner.Y * outZ))
	end
end

function PlotService.start()
	local parent = workspace:FindFirstChild(FOLDER_NAME)
	if parent then
		parent:Destroy()
	end
	local created = Instance.new("Folder")
	created.Name = FOLDER_NAME
	created.Parent = workspace

	replaceBaseplate(created)
	buildPaths(created)

	for index = 1, Config.PlotCount do
		plots[index] = buildPlot(index, created)
	end

	Players.PlayerRemoving:Connect(release)
end

return PlotService
