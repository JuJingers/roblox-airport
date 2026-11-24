--!strict
-- Пассажиры: встают в очередь, кладут чемодан на ленту, идут через рамку.
--
-- Раньше чемоданы появлялись из воздуха. Теперь у каждого есть хозяин,
-- и это меняет игру больше, чем кажется: видно, откуда берётся работа,
-- а рамка получает смысл.
--
-- Очередь перед приёмкой — главный источник обратной связи. Когда игрок
-- не успевает, хвост растёт у него на глазах. Прежний вариант, где
-- пассажиры просто переставали приходить, прятал эту информацию:
-- спрос молча исчезал, и понять, что отстаёшь, было нельзя.
--
-- Почему пассажиры двигаются на сервере, хотя чемоданы мы намеренно
-- считаем логически и рисуем на клиенте: чемоданов много и они быстрые,
-- а пассажиров единицы и они медленные. Для десятка неспешных болванок
-- серверное движение дешевле в коде и незаметно по сети.
--
-- Сейчас это болванки. Скины друзей игрока — более поздний шаг.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)

local PassengerService = {}

-- plot и belt относятся к одному аэропорту. Всё состояние ниже —
-- внутри экземпляра: восемь плотов не должны делить одну очередь.
function PassengerService.new(plot: any, belt: any, upgrades: any)
	local api = {}

	local FOLDER_NAME = "Passengers"

	type Stage = "InLine" | "ToDrop" | "ToFrame" | "AtFrame" | "UnderCheck" | "ToWait" | "Waiting" | "ToExit"

	type Passenger = {
		id: string,
		model: Part,
		stage: Stage,
		target: Vector3,
		-- Досмотр. suspicious — его следует досмотреть; beeps — рамка
		-- поймала его сама. Молчащий подозрительный опаснее: он идёт дальше.
		suspicious: boolean,
		beeps: boolean,
		pausedAtFrame: number,
		searched: boolean,
		waitedAtFrame: number,
		items: { Types.ItemKind },
		guilty: boolean,
	}

	-- Стоящие в очереди, по порядку прихода. Первый в списке — у приёмки.
	local line: { Passenger } = {}
	-- Уже отошедшие от очереди: несут чемодан, идут к рамке или на выход.
	local moving: { Passenger } = {}
	-- Прошедшие рамку и ждущие свой чемодан. Пока человек здесь, потеря
	-- багажа имеет лицо: он уйдёт расстроенным, а не растворится молча.
	local waiting: { Passenger } = {}

	-- Охрана: двое стоят у рамки и уводят задержанных в будку.
	-- Арест должен быть виден, а не сводиться к исчезновению человека.
	type GuardState = "AtPost" | "ToTarget" | "Escorting" | "Returning"

	type Guard = {
		model: Part,
		post: Vector3,
		state: GuardState,
		captive: Passenger?,
	}

	local guards: { Guard } = {}

	local folder: Folder? = nil
	local heartbeat: RBXScriptConnection? = nil
	local sinceLastArrival = 0
	local turnedAway = 0
	local nextId = 0
	local upset = 0
	local caught = 0
	local slipped = 0
	local falseSearches = 0
	local rng = Random.new()
	local frameState = "Idle"

	-- Аэропорт закрыт, пока игрок сам его не откроет. Захват плота и начало
	-- работы — разные события: свалившийся сразу поток нервирует и не даёт
	-- осмотреться.
	local isOpen = false

	-- Кому сообщать об итоге досмотра. Ставится снаружи: пассажиры
	-- не знают ни про деньги, ни про интерфейс.
	local onSearched: ((boolean, boolean) -> ())? = nil

	-- Сообщает наружу, перекрыт ли проход. Первый раз игрок иначе не поймёт,
	-- почему всё встало.
	local onAlert: ((boolean) -> ())? = nil

	-- Вердикты для тех, чей чемодан решили раньше, чем они дошли до зоны
	-- ожидания. Без этого при быстрой сортировке человек застревал навсегда:
	-- resolveBag не находил его среди ждущих и молча ничего не делал.
	local pendingVerdict: { [string]: boolean } = {}

	-- Папка людей лежит внутри своего плота. В общем Workspace восемь
	-- аэропортов делили бы одну и затирали друг друга.
	local function container(): Folder
		if folder and folder.Parent then
			return folder
		end
		local existing = plot.folder:FindFirstChild(FOLDER_NAME)
		if existing then
			existing:Destroy()
		end
		local created = Instance.new("Folder")
		created.Name = FOLDER_NAME
		created.Parent = plot.folder
		folder = created
		return created
	end

	-- Прошёл ли человек контроль. До этого момента его нельзя отпускать
	-- к выходу ни под каким предлогом: иначе разбор чемодана уводил бы
	-- его мимо рамки.
	local function clearedSecurity(passenger: Passenger): boolean
		local stage = passenger.stage
		return stage == "ToWait" or stage == "Waiting" or stage == "ToExit"
	end

	-- Занят ли пункт досмотра. Считаем занятым весь путь от ленты до
	-- выхода из рамки: иначе двое оказываются в ней одновременно
	-- и налезают друг на друга.
	local function checkpointBusy(): boolean
		for _, passenger in moving do
			local stage = passenger.stage
			if stage == "ToDrop" or stage == "ToFrame" or stage == "AtFrame" or stage == "UnderCheck" then
				return true
			end
		end
		return false
	end

	-- Апгрейды читаются на месте, а не кэшируются: купленное должно
	-- действовать сразу, без перезапуска.
	local function passengerSpeed(): number
		local effect = Config.UpgradeEffects.FasterLane
		return Config.PassengerSpeed + effect.speedBonus * upgrades.getLevel("FasterLane")
	end

	local function framePause(): number
		local effect = Config.UpgradeEffects.FasterLane
		local cut = effect.pauseCut * upgrades.getLevel("FasterLane")
		return math.max(Config.FramePauseSeconds - cut, 0.5)
	end

	-- Улучшение сокращает проверку, но не отменяет её: иначе досмотр
	-- перестал бы чего-либо стоить.
	local function searchSeconds(): number
		local effect = Config.UpgradeEffects.FastCheck
		local cut = effect.checkCut * upgrades.getLevel("FastCheck")
		return math.max(Config.SearchSeconds - cut, Config.MinSearchSeconds)
	end

	local function beepChance(): number
		local effect = Config.UpgradeEffects.BetterScanner
		local bonus = effect.beepBonus * upgrades.getLevel("BetterScanner")
		return math.min(Config.BeepChance + bonus, 1)
	end

	local function lineSlot(index: number): Vector3
		return (plot.origin + Config.LineStart) + Config.LineStep * (index - 1)
	end

	-- Ждущие раскладываются в несколько рядов: длинная шеренга занимала
	-- полэкрана и мешала смотреть на ленту.
	local function waitSlot(index: number): Vector3
		local zeroBased = index - 1
		local column = zeroBased % Config.WaitPerRow
		local row = math.floor(zeroBased / Config.WaitPerRow)
		return (plot.origin + Config.WaitStart) + Config.WaitStep * column + Config.WaitRowStep * row
	end

	-- Что показывает рамка прямо сейчас: пусто, сканер чист, сканер сработал.
	local function currentFrameState(): string
		for _, passenger in moving do
			if passenger.stage == "AtFrame" or passenger.stage == "UnderCheck" then
				return if passenger.beeps then "Alert" else "Clear"
			end
		end
		return "Idle"
	end

	local function setFrameState(state: string)
		if frameState == state then
			return
		end
		frameState = state

		-- Подсказка нужна только когда проход заперт звенящим.
		if onAlert then
			onAlert(state == "Alert")
		end

		local terminal = plot.folder:FindFirstChild("Airport")
		if not terminal then
			return
		end
		local color = Config.FrameIdleColor
		if state == "Alert" then
			color = Config.FrameAlertColor
		elseif state == "Clear" then
			color = Config.FrameClearColor
		end
		for _, name in { "FrameLeft", "FrameRight", "FrameTop" } do
			local part = terminal:FindFirstChild(name)
			if part and part:IsA("BasePart") then
				part.Color = color
			end
		end
	end

	-- Собирает ручную кладь. У виновного ровно одна запрещённая вещь среди
	-- разрешённых: искать надо глазами, а не считать количество.
	local function makeItems(guilty: boolean): { Types.ItemKind }
		local allowed: { Types.ItemKind } = {}
		for _, kind in Config.AllItems do
			if not table.find(Config.ProhibitedItems, kind) then
				table.insert(allowed, kind)
			end
		end

		local items: { Types.ItemKind } = {}
		for _ = 1, Config.ItemsPerCheck do
			table.insert(items, allowed[rng:NextInteger(1, #allowed)])
		end

		if guilty then
			local banned: { Types.ItemKind } = Config.ProhibitedItems
			items[rng:NextInteger(1, #items)] = banned[rng:NextInteger(1, #banned)]
		end

		return items
	end

	-- Охрана принадлежит аэропорту, а не серверу: создаётся при захвате
	-- плота и в его координатах. Раньше она появлялась при старте сервера
	-- и вставала на точке спавна игроков.
	local function makeGuards()
		for _, offset in Config.GuardPosts do
			local post = (plot.origin + offset)
			local body = Instance.new("Part")
			body.Name = "Guard"
			body.Size = Vector3.new(2.2, 5.4, 2.2)
			body.Color = Config.GuardColor
			body.Anchored = true
			body.CanCollide = false
			body.CanQuery = false
			body.TopSurface = Enum.SurfaceType.Smooth
			body.BottomSurface = Enum.SurfaceType.Smooth
			body.Position = post
			body.Parent = container()

			table.insert(guards, { model = body, post = post, state = "AtPost", captive = nil })
		end
	end

	local function moveToward(part: Part, target: Vector3, speed: number, deltaTime: number): boolean
		local toTarget = target - part.Position
		local distance = toTarget.Magnitude
		local stepLength = speed * deltaTime
		if distance > stepLength then
			part.Position = part.Position + toTarget.Unit * stepLength
			return false
		end
		part.Position = target
		return true
	end

	local function sendGuards(captive: Passenger)
		for _, guard in guards do
			if guard.state == "AtPost" then
				guard.state = "ToTarget"
				guard.captive = captive
			end
		end
	end

	local function stepGuards(deltaTime: number)
		for _, guard in guards do
			local captive = guard.captive
			if guard.state == "ToTarget" and captive then
				if moveToward(guard.model, captive.model.Position, Config.GuardSpeed, deltaTime) then
					guard.state = "Escorting"
				end
			elseif guard.state == "Escorting" and captive then
				local arrived = moveToward(guard.model, (plot.origin + Config.GuardBooth), Config.GuardSpeed, deltaTime)
				-- Задержанный идёт вместе с конвоем.
				captive.model.Position = guard.model.Position + Vector3.new(0, 0, 3)
				if arrived then
					captive.model:Destroy()
					guard.captive = nil
					guard.state = "Returning"
				end
			elseif guard.state == "Returning" then
				if moveToward(guard.model, guard.post, Config.GuardSpeed, deltaTime) then
					guard.state = "AtPost"
				end
			end
		end
	end

	local function makeBody(suspicious: boolean): Part
		local body = Instance.new("Part")
		body.Name = "Passenger"
		body.Size = Vector3.new(2, 5, 2)
		-- Цвет и есть подсказка: подозрительный отличается оттенком.
		-- Заметить его — работа игрока, звон достаётся не всем.
		body.Color = if suspicious then Config.PassengerSuspectColor else Config.PassengerCalmColor
		body.Anchored = true
		body.CanCollide = false
		-- CanQuery обязателен: без него луч мыши не попадает в деталь
		-- и ClickDetector молчит. Кликать по пассажиру — основа досмотра.
		body.CanQuery = true
		body.TopSurface = Enum.SurfaceType.Smooth
		body.BottomSurface = Enum.SurfaceType.Smooth
		body.Position = (plot.origin + Config.PassengerEntry)
		body.Parent = container()

		local detector = Instance.new("ClickDetector")
		detector.MaxActivationDistance = 200
		detector.Parent = body

		return body
	end

	local function arrive()
		-- Очередь не бесконечна: когда хвост упёрся в потолок, пассажир
		-- разворачивается. Это потерянный доход, а не тихое ничего.
		if #line >= Config.LineCapacity then
			turnedAway += 1
			return
		end

		nextId += 1
		local suspicious = rng:NextNumber() < Config.SuspiciousChance
		-- Отметка означает «проверь», а не «виновен»: часть проверенных
		-- окажется чистой, и в этом весь смысл решения.
		local guilty = suspicious and rng:NextNumber() < Config.GuiltyChance
		table.insert(line, {
			id = string.format("p%d", nextId),
			model = makeBody(suspicious),
			stage = "InLine",
			target = lineSlot(#line + 1),
			suspicious = suspicious,
			beeps = suspicious and rng:NextNumber() < beepChance(),
			pausedAtFrame = 0,
			searched = false,
			waitedAtFrame = 0,
			items = makeItems(guilty),
			guilty = guilty,
		})
	end

	local function walk(passenger: Passenger, deltaTime: number): boolean
		local position = passenger.model.Position
		local toTarget = passenger.target - position
		local distance = toTarget.Magnitude
		local stepLength = passengerSpeed() * deltaTime

		if distance > stepLength then
			passenger.model.Position = position + toTarget.Unit * stepLength
			return false
		end

		passenger.model.Position = passenger.target
		return true -- дошёл до своей точки
	end

	-- Отпускает пассажира к выходу с понятной эмоцией.
	local function release(passenger: Passenger, good: boolean)
		passenger.model.Color = if good
			then Color3.fromRGB(150, 220, 160)
			else Color3.fromRGB(226, 120, 110)
		passenger.stage = "ToExit"
		passenger.target = (plot.origin + Config.PassengerExit)
		if not good then
			upset += 1
		end
	end

	local function stepLine(deltaTime: number)
		for index, passenger in line do
			passenger.target = lineSlot(index)
			walk(passenger, deltaTime)
		end

		-- Первый в очереди отходит к приёмке, как только на ленте есть место.
		local head = line[1]
		if head == nil then
			return
		end
		-- Пункт досмотра одноместный: пока предыдущий не прошёл рамку,
		-- следующий стоит в очереди. Это разом решает и наложение тел,
		-- и слипание чемоданов, и делает рамку настоящим узким местом.
		if checkpointBusy() then
			return
		end

		if not belt.canAcceptBag() then
			return
		end

		if (head.model.Position - lineSlot(1)).Magnitude > 1 then
			return -- ещё подходит к началу очереди
		end

		table.remove(line, 1)
		head.stage = "ToDrop"
		head.target = (plot.origin + Config.PassengerDropPoint)
		table.insert(moving, head)
	end

	-- Единственное место, где человек попадает в зону ожидания.
	-- Здесь же применяется вердикт, если чемодан решили раньше времени.
	-- Не дождавшийся своего чемодана уходит: иначе зона ожидания растёт
	-- без предела и загромождает пункт.
	local function evictOldestWaiting()
		local oldest = waiting[1]
		if oldest == nil then
			return
		end
		table.remove(waiting, 1)
		table.insert(moving, oldest)
		upset += 1
		release(oldest, false)
	end

	local function moveToWaiting(passenger: Passenger)
		local at = table.find(moving, passenger)
		if at then
			table.remove(moving, at)
		end

		local verdict = pendingVerdict[passenger.id]
		if verdict ~= nil then
			pendingVerdict[passenger.id] = nil
			table.insert(moving, passenger)
			release(passenger, verdict)
			return
		end

		if #waiting >= Config.WaitCapacity then
			evictOldestWaiting()
		end

		passenger.stage = "ToWait"
		table.insert(waiting, passenger)
		passenger.target = waitSlot(#waiting)
	end

	local function stepMoving(deltaTime: number)
		for index = #moving, 1, -1 do
			local passenger = moving[index]

			-- Звенящий стоит у рамки, но не вечно: иначе игрок, не заметивший
			-- сигнала, оказался бы в тупике без выхода.
			if passenger.stage == "UnderCheck" then
				continue -- стоит, пока идёт проверка
			end

			if passenger.stage == "AtFrame" then
				passenger.waitedAtFrame += deltaTime

				-- Не звенящий стоит лишь короткое окно и идёт дальше.
				if not passenger.beeps then
					passenger.pausedAtFrame += deltaTime
					if passenger.pausedAtFrame >= framePause() then
						if passenger.suspicious then
							slipped += 1
							if onSearched then
								onSearched(false, false)
							end
						end
						moveToWaiting(passenger)
					end
					continue
				end

				if passenger.waitedAtFrame >= Config.SearchPatienceSeconds then
					slipped += 1
					if onSearched then
						onSearched(false, false)
					end
					release(passenger, false)
				end
				continue
			end

			if not walk(passenger, deltaTime) then
				continue
			end

			if passenger.stage == "ToDrop" then
				belt.putBag(passenger.id)
				passenger.stage = "ToFrame"
				passenger.target = (plot.origin + Config.PassengerFramePoint)
			elseif passenger.stage == "ToFrame" then
				-- В рамке притормаживают все: звенящий стоит до досмотра,
				-- остальные — короткое окно, за которое их можно поймать.
				if not passenger.searched then
					passenger.stage = "AtFrame"
					continue
				end

				moveToWaiting(passenger)
			else
				if passenger.suspicious and not passenger.searched then
					slipped += 1
					if onSearched then
						onSearched(false, false)
					end
				end
				passenger.model:Destroy()
				table.remove(moving, index)
			end
		end
	end

	local function stepWaiting(deltaTime: number)
		for index, passenger in waiting do
			passenger.target = waitSlot(index)
			if walk(passenger, deltaTime) and passenger.stage == "ToWait" then
				passenger.stage = "Waiting"
			end
		end
	end

	-- Досмотр идёт в два такта: сначала проверка, потом решение игрока.
	--
	-- Отметка означает «проверь», а не «виновен», поэтому одного нажатия
	-- мало: надо увидеть содержимое и решить. Проверка занимает время,
	-- и всё это время лента едет без присмотра — в этом её цена.

	local checkReady = Remotes.get("CheckReady")
	local checkStarted = Remotes.get("CheckStarted")

	local function findAnywhere(passengerId: string): Passenger?
		for _, list in { moving, waiting, line } do
			for _, passenger in list do
				if passenger.id == passengerId then
					return passenger
				end
			end
		end
		return nil
	end

	function api.beginCheck(player: Player, passengerId: string)
		local passenger = findAnywhere(passengerId)
		if passenger == nil or passenger.searched or passenger.stage == "UnderCheck" then
			return
		end
		-- Досмотр идёт только в рамке: там человек стоит, и только там
		-- у игрока есть окно, чтобы его поймать.
		if passenger.stage ~= "AtFrame" then
			return
		end

		passenger.stage = "UnderCheck"
		local seconds = searchSeconds()
		checkStarted:FireClient(player, {
			passengerId = passenger.id,
			seconds = seconds,
		})

		task.delay(seconds, function()
			if (passenger.stage :: Stage) ~= "UnderCheck" then
				return -- успел уйти по нетерпению
			end
			checkReady:FireClient(player, {
				passengerId = passenger.id,
				items = passenger.items,
			})
		end)
	end

	function api.decide(passengerId: string, detain: boolean)
		local passenger = findAnywhere(passengerId)
		if passenger == nil or passenger.stage ~= "UnderCheck" then
			return
		end

		passenger.searched = true
		local correct = detain == passenger.guilty
		if correct then
			caught += 1
		else
			falseSearches += 1
		end

		-- Задержанного уводит охрана, отпущенный идёт получать багаж.
		if detain then
			passenger.stage = "ToExit" -- шагами больше не управляет
			local at = table.find(moving, passenger)
			if at then
				table.remove(moving, at)
			end
			sendGuards(passenger)
		else
			if table.find(moving, passenger) == nil then
				table.insert(moving, passenger)
			end
			moveToWaiting(passenger)
		end

		if onSearched then
			onSearched(correct, true)
		end
	end

	function api.setSearchHandler(handler: (boolean, boolean) -> ())
		onSearched = handler
	end

	function api.setAlertHandler(handler: (boolean) -> ())
		onAlert = handler
	end

	-- Нажатие по телу пассажира начинает проверку.
	function api.connectSearch()
		local box = container()
		box.ChildAdded:Connect(function(child)
			local detector = child:FindFirstChildOfClass("ClickDetector")
			if not detector then
				return
			end
			detector.MouseClick:Connect(function(player)
				for _, list in { moving, waiting } do
					for _, passenger in list do
						if passenger.model == child then
							api.beginCheck(player, passenger.id)
							return
						end
					end
				end
			end)
		end)
	end

	-- Судьба чемодана решена: хозяин уходит довольным или расстроенным.
	-- Зовётся снаружи, чтобы пассажиры ничего не знали про начисления.
	function api.resolveBag(ownerId: string, good: boolean)
		for index, passenger in waiting do
			if passenger.id == ownerId then
				table.remove(waiting, index)
				table.insert(moving, passenger)
				release(passenger, good)
				return
			end
		end

		-- Может оказаться, что человек ещё идёт к рамке или от неё.
		-- Но стоящего в рамке или под досмотром выпускать нельзя: иначе
		-- проверку можно было бы обойти, просто разобрав его багаж.
		for _, passenger in moving do
			if passenger.id == ownerId then
				if clearedSecurity(passenger) then
					release(passenger, good)
				else
					-- Ещё идёт к рамке или стоит в ней: отпускать нельзя,
					-- иначе разбор чемодана уводит его мимо контроля.
					pendingVerdict[ownerId] = good
				end
				return
			end
		end

		-- Хозяин ещё не дошёл: запомним вердикт и применим на месте.
		pendingVerdict[ownerId] = good
	end

	local function step(deltaTime: number)
		-- Пока плот не захвачен, водить некого.
		if not true then
			return
		end

		-- Закрытие перекрывает вход, а не жизнь внутри. Иначе люди застывают
		-- посреди зала, а игрок спокойно разбирает накопленное без всякого
		-- давления — то есть закрытие превращается в способ фармить.
		sinceLastArrival += deltaTime
		if isOpen and sinceLastArrival >= Config.PassengerInterval then
			sinceLastArrival = 0
			arrive()
		end

		stepLine(deltaTime)
		stepMoving(deltaTime)
		stepWaiting(deltaTime)
		stepGuards(deltaTime)

		-- Цвет отражает действительность, а не историю.
		setFrameState(currentFrameState())
	end

	function api.getStats(): { inLine: number, moving: number, waiting: number, turnedAway: number, upset: number, caught: number, slipped: number, falseSearches: number }
		return {
			inLine = #line,
			moving = #moving,
			waiting = #waiting,
			turnedAway = turnedAway,
			upset = upset,
			caught = caught,
			slipped = slipped,
			falseSearches = falseSearches,
		}
	end

	function api.setOpen(open: boolean)
		isOpen = open
	end

	function api.isOpen(): boolean
		return isOpen
	end

	-- Аэропорт построен: ставим охрану. Зовётся при захвате плота.
	function api.buildForPlot()
		isOpen = false
		table.clear(guards)
		container():ClearAllChildren()
		table.clear(line)
		table.clear(moving)
		table.clear(waiting)
		makeGuards()
	end

	-- Аэропорт свернули: убираем всё, что стояло в мире.
	function api.teardown()
		if heartbeat then
			heartbeat:Disconnect()
			heartbeat = nil
		end
		table.clear(guards)
		table.clear(line)
		table.clear(moving)
		table.clear(waiting)
		local box = plot.folder:FindFirstChild(FOLDER_NAME)
		if box then
			box:Destroy()
		end
		folder = nil
	end

	function api.start()
		container()
		api.connectSearch()
		-- Обработчик держим в переменной: при сносе плота его надо
		-- отключить, иначе он останется висеть на мёртвом состоянии.
		heartbeat = RunService.Heartbeat:Connect(step)
	end

	return api
end

return PassengerService
