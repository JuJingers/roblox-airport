--!strict
-- Формы данных, которыми обмениваются сервер и клиент.
-- Модуль ничего не выполняет: он нужен, чтобы редактор и компилятор
-- ловили ошибки до запуска игры.

-- Куда летит чемодан. Это же значение служит цветом бирки.
export type Destination = "Red" | "Blue" | "Green" | "Yellow"

export type BagSize = "Normal" | "Oversized"

-- Жёлоба: четыре по направлениям плюс три особых.
export type ChuteId = Destination | "Oversized" | "Fragile" | "Security"

-- Чемодан — это запись в очереди, а не физическая деталь.
-- Сервер держит logicalPosition, клиент по нему рисует движение.
export type Bag = {
	id: string,
	destination: Destination,
	size: BagSize,
	fragile: boolean,
	flagged: boolean, -- нужен досмотр
	isVip: boolean, -- золотой чемодан, платит больше
	ownerId: string, -- кто его принёс: потеря должна иметь лицо
	-- workspace:GetServerTimeNow() на момент появления. Часы синхронны
	-- у сервера и клиентов, поэтому клиент вычисляет положение сам
	-- и по сети не идёт ни одного пакета за кадр.
	spawnedAt: number,
}

-- Вещи в ручной клади. Часть запрещена — какая именно, игрок узнаёт
-- у наставника, и список растёт вместе со ступенями.
export type ItemKind = "Clothes" | "Book" | "Phone" | "Knife" | "Liquid" | "Lighter"

-- Что показывают игроку после досмотра.
export type CheckResult = {
	passengerId: string,
	items: { ItemKind },
}

-- Результат попытки отсортировать. Считается только на сервере.
export type SortOutcome = {
	correct: boolean,
	payout: number, -- уже с учётом VIP и штрафа, всегда >= 0
	correctChute: ChuteId, -- куда следовало отправить
}

-- Что лежит в сохранении игрока.
export type Profile = {
	money: number,
	tier: number, -- ступень правил, 1..4
	upgrades: { [string]: number }, -- идентификатор -> сколько куплено
	cosmetics: { string },
	lastSeen: number, -- os.time() последнего выхода, отсюда считается оффлайн
	backlog: number, -- накопленный завал в чемоданах
}

-- Один апгрейд в магазине. displayName показывается игроку, поэтому английский.
export type Upgrade = {
	id: string,
	displayName: string,
	baseCost: number,
	maxCount: number,
}

return {}
