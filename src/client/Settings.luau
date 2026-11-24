--!strict
-- Настройки: громкость, коды, режим для слабых устройств.
--
-- Громкость и качество — целиком клиентские: они ни на что в игре не
-- влияют и серверу о них знать незачем. Коды наоборот: клиент шлёт
-- только строку, а список и решение живут на сервере.
--
-- Выбор запоминается в этом же сеансе. Постоянным станет вместе
-- с сохранениями.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local PlotContext = require(ReplicatedStorage.Shared.PlotContext)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local Settings = {}

local codeBox: TextBox? = nil
local codeStatus: TextLabel? = nil

local musicVolume = 0.5
local soundVolume = 0.7
local lowSpec = false

-- Звуковые группы: создаём заранее, чтобы музыке и эффектам было куда
-- попадать, когда они появятся.
local function soundGroup(name: string): SoundGroup
	local existing = SoundService:FindFirstChild(name)
	if existing and existing:IsA("SoundGroup") then
		return existing
	end
	local group = Instance.new("SoundGroup")
	group.Name = name
	group.Parent = SoundService
	return group
end

local function applyVolumes()
	soundGroup("Music").Volume = musicVolume
	soundGroup("Effects").Volume = soundVolume
end

-- Что именно урезает облегчённый режим.
--
-- Главная тяжесть здесь — чужие аэропорты: их семь, и каждый со своей
-- геометрией и людьми. Скрыть их — куда полезнее, чем крутить тени.
local function applyLowSpec()
	Lighting.GlobalShadows = not lowSpec

	local plots = workspace:FindFirstChild("Plots")
	if plots == nil then
		return
	end

	local mine = if PlotContext.isActive() then PlotContext.origin() else nil
	for _, plot in plots:GetChildren() do
		local site = plot:FindFirstChild("Airport")
		if site then
			local ground = plot:FindFirstChild("Ground")
			local isMine = typeof(mine) == "Vector3"
				and ground
				and ground:IsA("BasePart")
				and (Vector3.new(ground.Position.X, 0, ground.Position.Z) - Vector3.new(mine.X, 0, mine.Z)).Magnitude < 1

			for _, part in site:GetDescendants() do
				if part:IsA("BasePart") then
					part.LocalTransparencyModifier = if lowSpec and not isMine then 1 else 0
				end
			end
		end
	end
end

local function makeSlider(parent: Instance, label: string, y: number, initial: number, onChange: (number) -> ())
	local caption = Instance.new("TextLabel")
	caption.BackgroundTransparency = 1
	caption.Size = UDim2.new(1, -32, 0, 24)
	caption.Position = UDim2.new(0, 16, 0, y)
	caption.Font = Enum.Font.GothamMedium
	caption.TextSize = 15
	caption.TextXAlignment = Enum.TextXAlignment.Left
	caption.TextColor3 = Color3.fromRGB(220, 228, 240)
	caption.Text = string.format("%s   %d%%", label, math.floor(initial * 100))
	caption.Parent = parent

	local track = Instance.new("Frame")
	track.Size = UDim2.new(1, -32, 0, 10)
	track.Position = UDim2.new(0, 16, 0, y + 28)
	track.BackgroundColor3 = Color3.fromRGB(52, 60, 74)
	track.BorderSizePixel = 0
	track.Parent = parent

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(0, 5)
	trackCorner.Parent = track

	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(initial, 0, 1, 0)
	fill.BackgroundColor3 = Color3.fromRGB(96, 186, 120)
	fill.BorderSizePixel = 0
	fill.Parent = track

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 5)
	fillCorner.Parent = fill

	-- Ползунок сделан кнопкой во всю дорожку: нажатие ставит значение
	-- по месту клика. Проще перетаскивания и работает на касании.
	local hit = Instance.new("TextButton")
	hit.Size = UDim2.new(1, 0, 1, 12)
	hit.Position = UDim2.new(0, 0, 0, -6)
	hit.BackgroundTransparency = 1
	hit.Text = ""
	hit.Parent = track

	local function setFromX(x: number)
		local ratio = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
		fill.Size = UDim2.new(ratio, 0, 1, 0)
		caption.Text = string.format("%s   %d%%", label, math.floor(ratio * 100))
		onChange(ratio)
	end

	hit.MouseButton1Down:Connect(function(x: number)
		setFromX(x)
	end)
end

local function makeToggle(parent: Instance, label: string, y: number, onChange: (boolean) -> ()): TextButton
	local button = Instance.new("TextButton")
	button.Size = UDim2.new(1, -32, 0, 40)
	button.Position = UDim2.new(0, 16, 0, y)
	button.BackgroundColor3 = Color3.fromRGB(52, 60, 74)
	button.Font = Enum.Font.GothamMedium
	button.TextSize = 15
	button.TextColor3 = Color3.fromRGB(220, 228, 240)
	button.Text = label .. "   OFF"
	button.BorderSizePixel = 0
	button.AutoButtonColor = true
	button.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button

	local on = false
	button.Activated:Connect(function()
		on = not on
		button.Text = label .. (if on then "   ON" else "   OFF")
		button.BackgroundColor3 = if on
			then Color3.fromRGB(52, 116, 92)
			else Color3.fromRGB(52, 60, 74)
		onChange(on)
	end)
	return button
end

local function build()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local screen = Instance.new("ScreenGui")
	screen.Name = "Settings"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 20
	screen.Enabled = false
	screen.Parent = playerGui

	local shade = Instance.new("Frame")
	shade.Size = UDim2.new(1, 0, 1, 0)
	shade.BackgroundColor3 = Color3.fromRGB(10, 12, 18)
	shade.BackgroundTransparency = 0.4
	shade.BorderSizePixel = 0
	shade.Parent = screen

	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(0, 380, 0, 430)
	panel.Position = UDim2.new(0.5, -190, 0.5, -215)
	panel.BackgroundColor3 = Color3.fromRGB(24, 28, 36)
	panel.BorderSizePixel = 0
	panel.Parent = screen

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = panel

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 44)
	title.Position = UDim2.new(0, 0, 0, 12)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 24
	title.TextColor3 = Color3.fromRGB(245, 250, 255)
	title.Text = "Settings"
	title.Parent = panel

	makeSlider(panel, "Music", 66, musicVolume, function(value)
		musicVolume = value
		applyVolumes()
	end)
	makeSlider(panel, "Sound effects", 128, soundVolume, function(value)
		soundVolume = value
		applyVolumes()
	end)

	makeToggle(panel, "Low spec mode", 190, function(value)
		lowSpec = value
		applyLowSpec()
	end)

	-- Коды.
	local codeCaption = Instance.new("TextLabel")
	codeCaption.BackgroundTransparency = 1
	codeCaption.Size = UDim2.new(1, -32, 0, 22)
	codeCaption.Position = UDim2.new(0, 16, 0, 244)
	codeCaption.Font = Enum.Font.GothamMedium
	codeCaption.TextSize = 15
	codeCaption.TextXAlignment = Enum.TextXAlignment.Left
	codeCaption.TextColor3 = Color3.fromRGB(220, 228, 240)
	codeCaption.Text = "Promo code"
	codeCaption.Parent = panel

	local box = Instance.new("TextBox")
	box.Size = UDim2.new(1, -132, 0, 40)
	box.Position = UDim2.new(0, 16, 0, 270)
	box.BackgroundColor3 = Color3.fromRGB(40, 46, 58)
	box.Font = Enum.Font.GothamMedium
	box.TextSize = 16
	box.TextColor3 = Color3.fromRGB(240, 246, 252)
	box.PlaceholderText = "Enter code"
	box.Text = ""
	box.ClearTextOnFocus = false
	box.BorderSizePixel = 0
	box.Parent = panel
	codeBox = box

	local boxCorner = Instance.new("UICorner")
	boxCorner.CornerRadius = UDim.new(0, 8)
	boxCorner.Parent = box

	local redeem = Instance.new("TextButton")
	redeem.Size = UDim2.new(0, 100, 0, 40)
	redeem.Position = UDim2.new(1, -116, 0, 270)
	redeem.BackgroundColor3 = Color3.fromRGB(52, 116, 92)
	redeem.Font = Enum.Font.GothamBold
	redeem.TextSize = 16
	redeem.TextColor3 = Color3.fromRGB(240, 250, 244)
	redeem.Text = "Redeem"
	redeem.BorderSizePixel = 0
	redeem.Parent = panel

	local redeemCorner = Instance.new("UICorner")
	redeemCorner.CornerRadius = UDim.new(0, 8)
	redeemCorner.Parent = redeem

	local status = Instance.new("TextLabel")
	status.BackgroundTransparency = 1
	status.Size = UDim2.new(1, -32, 0, 40)
	status.Position = UDim2.new(0, 16, 0, 314)
	status.Font = Enum.Font.GothamMedium
	status.TextSize = 15
	status.TextWrapped = true
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.TextColor3 = Color3.fromRGB(160, 170, 186)
	status.Text = ""
	status.Parent = panel
	codeStatus = status

	redeem.Activated:Connect(function()
		if box.Text ~= "" then
			Remotes.get("RedeemCode"):FireServer(box.Text)
		end
	end)

	local close = Instance.new("TextButton")
	close.Size = UDim2.new(1, -32, 0, 44)
	close.Position = UDim2.new(0, 16, 1, -60)
	close.BackgroundColor3 = Color3.fromRGB(52, 60, 74)
	close.Font = Enum.Font.GothamBold
	close.TextSize = 16
	close.TextColor3 = Color3.fromRGB(230, 236, 244)
	close.Text = "Close"
	close.BorderSizePixel = 0
	close.Parent = panel

	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0, 10)
	closeCorner.Parent = close

	close.Activated:Connect(function()
		screen.Enabled = false
	end)
end

local MESSAGES: { [string]: string } = {
	Granted = "Code accepted",
	Unknown = "No such code",
	AlreadyUsed = "You already used this code",
	Expired = "This code has expired",
}

function Settings.start()
	build()
	applyVolumes()

	Remotes.get("CodeResult").OnClientEvent:Connect(function(payload)
		local status = codeStatus
		if status == nil then
			return
		end
		local text = MESSAGES[payload.outcome] or "Something went wrong"
		if payload.outcome == "Granted" and payload.money > 0 then
			text = string.format("%s — $%d", text, payload.money)
		end
		status.Text = text
		status.TextColor3 = if payload.outcome == "Granted"
			then Color3.fromRGB(150, 235, 160)
			else Color3.fromRGB(226, 150, 120)
		if payload.outcome == "Granted" and codeBox then
			codeBox.Text = ""
		end
	end)
end

return Settings
