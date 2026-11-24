--!strict
-- Окно досмотра: ожидание проверки, содержимое ручной клади и решение.
--
-- Вещи показываются формой и цветом, без подписей: аудитория молодая
-- и многоязычная, а читать во время работы ленты некогда.
--
-- Решает игрок, а судит сервер. Отсюда уходит только выбор — задержать
-- или пропустить.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)

local SearchPanel = {}

local gui: ScreenGui? = nil
local statusLabel: TextLabel? = nil
local itemsRow: Frame? = nil
local buttonsRow: Frame? = nil

local activeId: string? = nil
local countdownEndsAt = 0
local countdownConnection: RBXScriptConnection? = nil

-- Каждой вещи своя форма: цвет один не различить у дальтоника,
-- а вместе с силуэтом читается однозначно.
local SHAPES: { [string]: { size: UDim2, corner: number } } = {
	Clothes = { size = UDim2.new(0.7, 0, 0.45, 0), corner = 6 },
	Book = { size = UDim2.new(0.45, 0, 0.7, 0), corner = 2 },
	Phone = { size = UDim2.new(0.3, 0, 0.72, 0), corner = 8 },
	Knife = { size = UDim2.new(0.12, 0, 0.8, 0), corner = 2 },
	Liquid = { size = UDim2.new(0.55, 0, 0.55, 0), corner = 40 },
	Lighter = { size = UDim2.new(0.35, 0, 0.35, 0), corner = 4 },
}

local function makeButton(parent: Instance, text: string, color: Color3, x: number): TextButton
	local button = Instance.new("TextButton")
	button.Size = UDim2.new(0.46, 0, 1, 0)
	button.Position = UDim2.new(x, 0, 0, 0)
	button.BackgroundColor3 = color
	button.Text = text
	button.Font = Enum.Font.GothamBold
	button.TextSize = 20
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.AutoButtonColor = true
	button.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = button
	return button
end

local function build()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local screen = Instance.new("ScreenGui")
	screen.Name = "SearchPanel"
	screen.ResetOnSpawn = false
	screen.Enabled = false
	screen.Parent = playerGui
	gui = screen

	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(0, 460, 0, 260)
	panel.Position = UDim2.new(0.5, -230, 0.5, -130)
	panel.BackgroundColor3 = Color3.fromRGB(28, 32, 40)
	panel.BorderSizePixel = 0
	panel.Parent = screen

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = panel

	local status = Instance.new("TextLabel")
	status.BackgroundTransparency = 1
	status.Size = UDim2.new(1, -32, 0, 44)
	status.Position = UDim2.new(0, 16, 0, 14)
	status.Font = Enum.Font.GothamBold
	status.TextSize = 22
	status.TextColor3 = Color3.fromRGB(240, 244, 250)
	status.Text = ""
	status.Parent = panel
	statusLabel = status

	local items = Instance.new("Frame")
	items.BackgroundTransparency = 1
	items.Size = UDim2.new(1, -40, 0, 110)
	items.Position = UDim2.new(0, 20, 0, 64)
	items.Parent = panel
	itemsRow = items

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 14)
	layout.Parent = items

	local buttons = Instance.new("Frame")
	buttons.BackgroundTransparency = 1
	buttons.Size = UDim2.new(1, -40, 0, 52)
	buttons.Position = UDim2.new(0, 20, 1, -70)
	buttons.Visible = false
	buttons.Parent = panel
	buttonsRow = buttons

	local decision = Remotes.get("CheckDecision")

	makeButton(buttons, "Arrest", Color3.fromRGB(196, 66, 58), 0).Activated:Connect(function()
		if activeId then
			decision:FireServer({ passengerId = activeId, detain = true })
			SearchPanel.close()
		end
	end)
	makeButton(buttons, "Let through", Color3.fromRGB(58, 130, 96), 0.54).Activated:Connect(function()
		if activeId then
			decision:FireServer({ passengerId = activeId, detain = false })
			SearchPanel.close()
		end
	end)
end

local function clearItems()
	if itemsRow then
		for _, child in itemsRow:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
	end
end

local function showItems(items: { Types.ItemKind })
	clearItems()
	if not itemsRow then
		return
	end

	local colors: { [string]: Color3 } = Config.ItemColors
	for index, kind in items do
		local cell = Instance.new("Frame")
		cell.Size = UDim2.new(0, 96, 0, 96)
		cell.BackgroundColor3 = Color3.fromRGB(44, 50, 60)
		cell.BorderSizePixel = 0
		cell.LayoutOrder = index
		cell.Parent = itemsRow

		local cellCorner = Instance.new("UICorner")
		cellCorner.CornerRadius = UDim.new(0, 10)
		cellCorner.Parent = cell

		local shape = SHAPES[kind] or { size = UDim2.new(0.5, 0, 0.5, 0), corner = 6 }
		local glyph = Instance.new("Frame")
		glyph.Size = shape.size
		glyph.AnchorPoint = Vector2.new(0.5, 0.5)
		glyph.Position = UDim2.new(0.5, 0, 0.5, 0)
		glyph.BackgroundColor3 = colors[kind] or Color3.fromRGB(200, 200, 200)
		glyph.BorderSizePixel = 0
		glyph.Parent = cell

		local glyphCorner = Instance.new("UICorner")
		glyphCorner.CornerRadius = UDim.new(0, shape.corner)
		glyphCorner.Parent = glyph
	end
end

local function stopCountdown()
	if countdownConnection then
		countdownConnection:Disconnect()
		countdownConnection = nil
	end
end

function SearchPanel.close()
	stopCountdown()
	activeId = nil
	if gui then
		gui.Enabled = false
	end
	if buttonsRow then
		buttonsRow.Visible = false
	end
	clearItems()
end

local function onCheckStarted(payload: { passengerId: string, seconds: number })
	activeId = payload.passengerId
	countdownEndsAt = os.clock() + payload.seconds

	clearItems()
	if buttonsRow then
		buttonsRow.Visible = false
	end
	if gui then
		gui.Enabled = true
	end

	stopCountdown()
	countdownConnection = RunService.RenderStepped:Connect(function()
		local left = math.max(countdownEndsAt - os.clock(), 0)
		if statusLabel then
			statusLabel.Text = string.format("Checking… %.1fs", left)
		end
	end)
end

local function onCheckReady(payload: Types.CheckResult)
	if payload.passengerId ~= activeId then
		return
	end
	stopCountdown()
	if statusLabel then
		statusLabel.Text = "Carry-on contents"
	end
	showItems(payload.items)
	if buttonsRow then
		buttonsRow.Visible = true
	end
end

function SearchPanel.start()
	build()
	Remotes.get("CheckStarted").OnClientEvent:Connect(onCheckStarted)
	Remotes.get("CheckReady").OnClientEvent:Connect(onCheckReady)
end

return SearchPanel
