--!strict
-- Простейший счётчик на экране.
--
-- Полноценный интерфейс — это более поздний шаг. Здесь ровно столько,
-- чтобы во время проверки на серых кубах было видно, сколько разобрано
-- верно и сколько мимо: без этих двух чисел нельзя судить, играется ли.
--
-- Надписи по-английски: игра англоязычная, остальное закрывает
-- автоперевод Roblox.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlotContext = require(ReplicatedStorage.Shared.PlotContext)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local HUD = {}

type SortReport = {
	bagId: string,
	correct: boolean,
	chosenChute: string,
	correctChute: string,
	correctCount: number,
	wrongCount: number,
	lostToQueue: boolean?,
}

type SecurityReport = {
	correct: boolean,
	wasSearch: boolean,
}

local openButton: TextButton? = nil
local claimed = false
local airportOpen = false

local scoreLabel: TextLabel? = nil
local hintLabel: TextLabel? = nil
local securityLabel: TextLabel? = nil
local caught = 0
local slipped = 0
local laneBlocked = false

local function makeLabel(parent: Instance, position: UDim2, size: UDim2, textSize: number): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = position
	label.Size = size
	label.Font = Enum.Font.GothamBold
	label.TextSize = textSize
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.4
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = ""
	label.Parent = parent
	return label
end

local function build()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "HUD"
	gui.ResetOnSpawn = false
	-- Верхнюю панель Roblox (меню, чат, микрофон) нельзя перекрывать:
	-- при IgnoreGuiInset = true наши надписи уезжают под неё.
	gui.IgnoreGuiInset = false
	gui.Parent = playerGui

	scoreLabel = makeLabel(gui, UDim2.new(0, 24, 0, 24), UDim2.new(0, 400, 0, 34), 26)
	hintLabel = makeLabel(gui, UDim2.new(0, 24, 0, 58), UDim2.new(0, 500, 0, 26), 18)
	securityLabel = makeLabel(gui, UDim2.new(0, 24, 0, 88), UDim2.new(0, 500, 0, 26), 18)

	if scoreLabel then
		scoreLabel.Text = "Sorted 0   Missed 0"
	end
	if hintLabel then
		hintLabel.Text = "Click a chute to send the highlighted bag"
	end
	if securityLabel then
		securityLabel.Text = "Search 0   Slipped 0"
		securityLabel.TextColor3 = Color3.fromRGB(190, 196, 210)
	end

	-- Кнопка открытия. Аэропорт не начинает работать сам: игрок сначала
	-- осматривается, потом запускает поток.
	local open = Instance.new("TextButton")
	open.Size = UDim2.new(0, 180, 0, 44)
	open.Position = UDim2.new(0, 24, 0, 124)
	open.Font = Enum.Font.GothamBold
	open.TextSize = 17
	open.BorderSizePixel = 0
	open.AutoButtonColor = true
	open.Visible = false
	open.Parent = gui
	openButton = open

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = open

	local setOpen = Remotes.get("SetAirportOpen")
	open.Activated:Connect(function()
		setOpen:FireServer(not airportOpen)
	end)

	-- Настройки должны быть доступны и в игре, а не только из меню:
	-- громкость и облегчённый режим нужны как раз во время работы.
	local settings = Instance.new("TextButton")
	settings.Size = UDim2.new(0, 44, 0, 44)
	settings.Position = UDim2.new(0, 212, 0, 124)
	settings.BackgroundColor3 = Color3.fromRGB(52, 60, 74)
	settings.Font = Enum.Font.GothamBold
	settings.TextSize = 22
	settings.TextColor3 = Color3.fromRGB(230, 236, 244)
	settings.Text = "⚙"
	settings.BorderSizePixel = 0
	settings.AutoButtonColor = true
	settings.Parent = gui

	local settingsCorner = Instance.new("UICorner")
	settingsCorner.CornerRadius = UDim.new(0, 10)
	settingsCorner.Parent = settings

	settings.Activated:Connect(function()
		local screen = playerGui:FindFirstChild("Settings")
		if screen and screen:IsA("ScreenGui") then
			screen.Enabled = true
		end
	end)
end

local function onResult(report: SortReport)
	if scoreLabel then
		scoreLabel.Text = string.format("Sorted %d   Missed %d", report.correctCount, report.wrongCount)
		scoreLabel.TextColor3 = if report.correct
			then Color3.fromRGB(150, 235, 160)
			else Color3.fromRGB(240, 140, 130)
	end

	if hintLabel and not laneBlocked then
		if report.correct then
			hintLabel.Text = "Correct"
		elseif report.lostToQueue then
			hintLabel.Text = "Queue overflowed — a bag was lost"
		else
			hintLabel.Text = string.format("Wrong — that one belonged to %s", report.correctChute)
		end
	end
end

-- Пока проход перекрыт, подсказка держится: она объясняет, почему
-- очередь встала, и не должна теряться под сообщениями про багаж.
local function onAlert(blocked: boolean)
	laneBlocked = blocked
	if not hintLabel then
		return
	end
	if blocked then
		hintLabel.Text = "Scanner alert — click the waiting passenger to reopen the lane"
		hintLabel.TextColor3 = Color3.fromRGB(240, 170, 120)
	else
		hintLabel.Text = "Lane open"
		hintLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	end
end

local function onSecurity(report: SecurityReport)
	if report.wasSearch then
		if report.correct then
			caught += 1
		end
	else
		slipped += 1
	end

	if securityLabel then
		securityLabel.Text = string.format("Search %d   Slipped %d", caught, slipped)
		securityLabel.TextColor3 = if report.wasSearch and report.correct
			then Color3.fromRGB(150, 235, 160)
			elseif report.wasSearch then Color3.fromRGB(220, 200, 140)
			else Color3.fromRGB(240, 140, 130)
	end
end

local function refreshOpenButton()
	local button = openButton
	if button == nil then
		return
	end
	button.Visible = claimed
	button.Text = if airportOpen then "Close airport" else "Open airport"
	button.BackgroundColor3 = if airportOpen
		then Color3.fromRGB(120, 74, 66)
		else Color3.fromRGB(52, 116, 92)
	button.TextColor3 = Color3.fromRGB(240, 250, 244)
end

function HUD.start()
	build()

	Remotes.get("AirportState").OnClientEvent:Connect(function(state)
		claimed = state.claimed
		airportOpen = state.open
		-- Отсюда клиент узнаёт, где стоит его аэропорт: отрисовка
		-- чемоданов считает координаты от начала плота.
		PlotContext.set(state.origin)
		refreshOpenButton()
	end)
	refreshOpenButton()
	Remotes.get("SortResult").OnClientEvent:Connect(onResult)
	Remotes.get("SecurityResult").OnClientEvent:Connect(onSecurity)
	Remotes.get("SecurityAlert").OnClientEvent:Connect(onAlert)
end

return HUD
