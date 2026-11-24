--!strict
-- Начало плота, на котором работает этот клиент.
--
-- Координаты в Config — смещения, а не мировые точки. Этот модуль
-- переводит их в мировые: `PlotContext.at(Config.BeltStart)`.
--
-- Раньше значение лежало в атрибуте Workspace и было одно на сервер.
-- С восемью плотами так нельзя: у каждого своё начало. Теперь сервер
-- присылает его владельцу вместе с состоянием аэропорта, а модуль
-- просто хранит присланное.
--
-- На сервере не используется: там координаты берутся прямо из плота.

local PlotContext = {}

local origin: Vector3? = nil

function PlotContext.set(value: Vector3?)
	origin = value
end

function PlotContext.clear()
	origin = nil
end

function PlotContext.origin(): Vector3
	return origin or Vector3.zero
end

-- Смещение в мировую точку.
function PlotContext.at(offset: Vector3): Vector3
	return PlotContext.origin() + offset
end

-- Есть ли у клиента свой аэропорт. До захвата рисовать нечего.
function PlotContext.isActive(): boolean
	return origin ~= nil
end

return PlotContext
