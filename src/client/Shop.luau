--!strict
-- Кошелёк и магазин.
--
-- Магазин спрятан за кнопкой, но кошелёк виден всегда: без него не
-- понять, к чему копишь. Кнопка подсвечивается, когда хватает хотя бы
-- на одну покупку — так дальняя цель напоминает о себе, не занимая
-- экран.
--
-- Две вкладки: улучшения действуют сразу и невидимы, оборудование —
-- объекты, которые появляются в мире. Разделены потому, что это разные
-- решения: одно про числа, другое про устройство пункта.
--
-- Покупку решает сервер. Отсюда уходит только идентификатор.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local Shop = {}

type Row = {
	id: string,
	displayName: string,
	price: number,
	owned: number,
	maxCount: number,
}

local moneyLabel: TextLabel? = nil
local openButton: TextButton? = nil
local listFrame: Frame? = nil
local emptyLabel: TextLabel? = nil
local tabButtons: { [string]: TextButton } = {}

local buttons: { [string]: TextButton? } = {}
local wallet = 0
local rows: { Row } = {}

local ACCENT = Color3.fromRGB(52, 116, 92)
local DIM = Color3.fromRGB(48, 54, 64)

local function canAffordAny(): boolean
	for _, row in rows do
		if row.owned < row.maxCount and wallet >= row.price then
			return true
		end
	end
	return false
end

local function refresh()
	if moneyLabel then
		moneyLabel.Text = string.format("$ %d", wallet)
	end

	-- Кнопка подсвечивается, когда есть что купить: напоминание
	-- без занятого экрана.
	if openButton then
		local ready = canAffordAny()
		openButton.BackgroundColor3 = if ready then ACCENT else DIM
		openButton.TextColor3 = if ready
			then Color3.fromRGB(240, 250, 244)
			else Color3.fromRGB(170, 178, 190)
	end

	for _, row in rows do
		local button = buttons[row.id]
		if button then
			local maxed = row.owned >= row.maxCount
			local affordable = wallet >= row.price

			button.Text = if maxed
				then string.format("%s   MAX", row.displayName)
				else string.format("%s  lv%d   $%d", row.displayName, row.owned, row.price)

			button.BackgroundColor3 = if maxed
				then Color3.fromRGB(58, 66, 78)
				elseif affordable then ACCENT
				else DIM
			button.TextColor3 = if affordable and not maxed
				then Color3.fromRGB(240, 250, 244)
				else Color3.fromRGB(150, 158, 172)
		end
	end
end

local function setTab(tab: string)
	for name, button in tabButtons do
		local on = name == tab
		button.BackgroundColor3 = if on then Color3.fromRGB(64, 72, 86) else Color3.fromRGB(40, 46, 56)
		button.TextColor3 = if on then Color3.fromRGB(240, 246, 252) else Color3.fromRGB(150, 158, 172)
	end

	local showUpgrades = tab == "Upgrades"
	if listFrame then
		listFrame.Visible = showUpgrades
	end
	if emptyLabel then
		emptyLabel.Visible = not showUpgrades
	end
end

local function makeTab(parent: Instance, name: string, text: string, x: number)
	local button = Instance.new("TextButton")
	button.Size = UDim2.new(0.5, -4, 0, 34)
	button.Position = UDim2.new(x, if x == 0 then 0 else 4, 0, 0)
	button.Font = Enum.Font.GothamMedium
	button.TextSize = 15
	button.Text = text
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button

	button.Activated:Connect(function()
		setTab(name)
	end)
	tabButtons[name] = button
end

local function build()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "Shop"
	gui.ResetOnSpawn = false
	gui.Parent = playerGui

	local money = Instance.new("TextLabel")
	money.BackgroundTransparency = 1
	money.Size = UDim2.new(0, 240, 0, 40)
	money.Position = UDim2.new(1, -264, 0, 14)
	money.Font = Enum.Font.GothamBold
	money.TextSize = 30
	money.TextXAlignment = Enum.TextXAlignment.Right
	money.TextColor3 = Color3.fromRGB(240, 226, 150)
	money.TextStrokeTransparency = 0.4
	money.Text = "$ 0"
	money.Parent = gui
	moneyLabel = money

	local open = Instance.new("TextButton")
	open.Size = UDim2.new(0, 120, 0, 36)
	open.Position = UDim2.new(1, -144, 0, 58)
	open.Font = Enum.Font.GothamBold
	open.TextSize = 16
	open.Text = "Shop"
	open.BorderSizePixel = 0
	open.AutoButtonColor = true
	open.Parent = gui
	openButton = open

	local openCorner = Instance.new("UICorner")
	openCorner.CornerRadius = UDim.new(0, 8)
	openCorner.Parent = open

	local board = Instance.new("Frame")
	board.Size = UDim2.new(0, 300, 0, 290)
	board.Position = UDim2.new(1, -324, 0, 102)
	board.BackgroundColor3 = Color3.fromRGB(28, 32, 40)
	board.BorderSizePixel = 0
	board.Visible = false
	board.Parent = gui

	local boardCorner = Instance.new("UICorner")
	boardCorner.CornerRadius = UDim.new(0, 12)
	boardCorner.Parent = board

	local tabs = Instance.new("Frame")
	tabs.BackgroundTransparency = 1
	tabs.Size = UDim2.new(1, -24, 0, 34)
	tabs.Position = UDim2.new(0, 12, 0, 12)
	tabs.Parent = board

	makeTab(tabs, "Upgrades", "Upgrades", 0)
	makeTab(tabs, "Equipment", "Equipment", 0.5)

	local list = Instance.new("Frame")
	list.BackgroundTransparency = 1
	list.Size = UDim2.new(1, -24, 1, -66)
	list.Position = UDim2.new(0, 12, 0, 56)
	list.Parent = board
	listFrame = list

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, 8)
	layout.Parent = list

	local empty = Instance.new("TextLabel")
	empty.BackgroundTransparency = 1
	empty.Size = UDim2.new(1, -24, 1, -66)
	empty.Position = UDim2.new(0, 12, 0, 56)
	empty.Font = Enum.Font.Gotham
	empty.TextSize = 15
	empty.TextWrapped = true
	empty.TextColor3 = Color3.fromRGB(150, 158, 172)
	empty.Text = "Extra lanes, checkpoints and helpers arrive here soon."
	empty.Visible = false
	empty.Parent = board
	emptyLabel = empty

	open.Activated:Connect(function()
		board.Visible = not board.Visible
	end)

	setTab("Upgrades")
end

local function rebuildButtons()
	local list = listFrame
	if list == nil then
		return
	end

	local buy = Remotes.get("BuyUpgrade")
	for index, row in rows do
		if buttons[row.id] ~= nil then
			continue
		end

		local button = Instance.new("TextButton")
		button.Size = UDim2.new(1, 0, 0, 40)
		button.LayoutOrder = index
		button.Font = Enum.Font.GothamMedium
		button.TextSize = 15
		button.AutoButtonColor = true
		button.BorderSizePixel = 0
		button.Text = ""
		button.Parent = list

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = button

		local id = row.id
		button.Activated:Connect(function()
			buy:FireServer(id)
		end)

		buttons[row.id] = button
	end
end

function Shop.start()
	build()

	Remotes.get("WalletChanged").OnClientEvent:Connect(function(amount: number)
		wallet = amount
		refresh()
	end)

	Remotes.get("ShopChanged").OnClientEvent:Connect(function(state: { Row })
		rows = state
		rebuildButtons()
		refresh()
	end)
end

return Shop
