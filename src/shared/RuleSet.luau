--!strict
-- Свод правил сортировки.
--
-- Один вопрос: в какой жёлоб должен уехать этот чемодан. Ответ зависит от
-- ступени, до которой добрался игрок, — правила открываются по мере
-- прокачки, а не по общему таймеру.
--
-- Модуль общий: сервер по нему судит, клиент по нему подсказывает
-- в обучении. Судить при этом имеет право только сервер.

local Types = require(script.Parent.Types)

local RuleSet = {}

-- Порядок проверок задаёт приоритет правил, и он важен.
-- Чемодан может быть одновременно хрупким и негабаритным; выигрывает
-- то правило, что выше. Досмотр перекрывает всё: подозрительный
-- чемодан не летит никуда, пока его не проверили.
function RuleSet.correctChute(bag: Types.Bag, tier: number): Types.ChuteId
	if tier >= 4 and bag.flagged then
		return "Security"
	end
	if tier >= 3 and bag.fragile then
		return "Fragile"
	end
	if tier >= 2 and bag.size == "Oversized" then
		return "Oversized"
	end
	return bag.destination
end

-- Какие жёлоба вообще открыты на этой ступени. Нужно, чтобы не строить
-- в мире приёмники, о которых игрок ещё не знает.
function RuleSet.chutesForTier(tier: number, destinations: { Types.Destination }): { Types.ChuteId }
	local chutes: { Types.ChuteId } = {}
	for _, destination in destinations do
		table.insert(chutes, destination)
	end
	if tier >= 2 then
		table.insert(chutes, "Oversized")
	end
	if tier >= 3 then
		table.insert(chutes, "Fragile")
	end
	if tier >= 4 then
		table.insert(chutes, "Security")
	end
	return chutes
end

return RuleSet
