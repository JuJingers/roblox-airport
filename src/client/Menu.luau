--!strict
-- Главное меню и выбор плота.
--
-- Игрок попадает сюда сразу при входе: сначала название и кнопки, потом
-- облёт участков. Камера встаёт напротив входа выбранного аэропорта,
-- стрелки листают, свободный можно занять.
--
-- Пока меню открыто, камера отвязана от персонажа: игрок смотрит карту,
-- а не бегает по ней.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local Menu = {}

type PlotRow = {
	index: number,
	origin: Vector3,
	owner: string?,
}

local gui: ScreenGui? = nil
local titleScreen: Frame? = nil
local browser: Frame? = nil
local plotLabel: TextLabel? = nil
local ownerLabel: TextLabel? = nil
local claimButton: TextButton? = nil

local rows: { PlotRow } = {}
local current = 1
local camera: Camera? = nil
local wanted: CFrame? = nil
local holdConnection: RBXScriptConnection? = nil

-- Пока меню открыто, остальной интерфейс прячем: он относится к игре,
-- в которую ещё не вошли.
local function setGameGuiVisible(visible: boolean)
	local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
	if playerGui == nil then
		return
	end
	for _, name in { "HUD", "Shop" } do
		local screen = playerGui:FindFirstChild(name)
		if screen and screen:IsA("ScreenGui") then
			screen.Enabled = visible
		end
	end
end

-- Точка, откуда смотрим на аэропорт: снаружи, напротив входа.
local function viewFor(origin: Vector3): (CFrame, Vector3)
	local entrance = origin
		+ Config.BuildingCenter
		+ Vector3.new(-Config.BuildingSize.X * 0.5, 4, 0)
	local eye = entrance + Vector3.new(-120, 62, 0)
	return CFrame.new(eye, entrance), entrance
end

local function showPlot(index: number)
	if #rows == 0 then
		return
	end
	current = ((index - 1) % #rows) + 1
	local row = rows[current]

	if plotLabel then
		plotLabel.Text = string.format("PLOT %d", row.index)
	end
	if ownerLabel then
		ownerLabel.Text = if row.owner then string.upper(row.owner) else "FREE"
		ownerLabel.TextColor3 = if row.owner
			then Color3.fromRGB(226, 150, 120)
			else Color3.fromRGB(150, 235, 160)
	end
	if claimButton then
		local free = row.owner == nil
		claimButton.Visible = free
	end

	local cam = camera
	if cam then
		local target = viewFor(row.origin)
		wanted = target
		TweenService:Create(cam, TweenInfo.new(0.5, Enum.EasingStyle.Quad), { CFrame = target }):Play()
	end
end

local function makeButton(parent: Instance, text: string, size: UDim2, position: UDim2, color: Color3): TextButton
	local button = Instance.new("TextButton")
	button.Size = size
	button.Position = position
	button.BackgroundColor3 = color
	button.Text = text
	button.Font = Enum.Font.GothamBold
	button.TextSize = 20
	button.TextColor3 = Color3.fromRGB(245, 250, 255)
	button.BorderSizePixel = 0
	button.AutoButtonColor = true
	button.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = button
	return button
end

-- Возврат камеры к персонажу.
--
-- Одного присвоения типа мало сразу по двум причинам: без назначенного
-- субъекта камере не за кем следовать, а запущенный ранее твин
-- продолжает двигать CFrame и перебивает результат. Поэтому сначала
-- гасим твин собственным присвоением, потом несколько кадров держим
-- нужное состояние.
local function returnCameraToCharacter()
	local player = Players.LocalPlayer
	local character = player.Character or player.CharacterAdded:Wait()
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid == nil or not humanoid:IsA("Humanoid") then
		return
	end

	for _ = 1, 12 do
		local cam = workspace.CurrentCamera
		if cam then
			cam.CameraSubject = humanoid
			cam.CameraType = Enum.CameraType.Custom
			if cam.CameraType == Enum.CameraType.Custom and cam.CameraSubject == humanoid then
				-- Дадим кадру примениться и убедимся, что не перебили обратно.
				RunService.RenderStepped:Wait()
				if cam.CameraType == Enum.CameraType.Custom then
					return
				end
			end
		end
		RunService.RenderStepped:Wait()
	end
end

local function closeMenu()
	if gui then
		gui.Enabled = false
	end
	if holdConnection then
		holdConnection:Disconnect()
		holdConnection = nil
	end
	wanted = nil
	setGameGuiVisible(true)
	task.spawn(returnCameraToCharacter)
end

local function openBrowser()
	if titleScreen then
		titleScreen.Visible = false
	end
	if browser then
		browser.Visible = true
	end
	Remotes.get("RequestPlots"):FireServer()
	showPlot(current)
end

local function build()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local screen = Instance.new("ScreenGui")
	screen.Name = "Menu"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 10
	screen.Parent = playerGui
	gui = screen

	-- Титульный экран.
	local title = Instance.new("Frame")
	title.Size = UDim2.new(1, 0, 1, 0)
	title.BackgroundColor3 = Color3.fromRGB(16, 20, 28)
	title.BackgroundTransparency = 0.25
	title.BorderSizePixel = 0
	title.Parent = screen
	titleScreen = title

	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Size = UDim2.new(1, 0, 0, 90)
	name.Position = UDim2.new(0, 0, 0.24, 0)
	name.Font = Enum.Font.GothamBold
	name.TextSize = 62
	name.TextColor3 = Color3.fromRGB(245, 250, 255)
	name.Text = string.upper(Config.GameName)
	name.Parent = title

	makeButton(title, "Play", UDim2.new(0, 240, 0, 54), UDim2.new(0.5, -120, 0.5, -10),
		Color3.fromRGB(52, 116, 92)).Activated:Connect(openBrowser)

	makeButton(title, "Settings", UDim2.new(0, 240, 0, 48), UDim2.new(0.5, -120, 0.5, 56),
		Color3.fromRGB(52, 60, 74)).Activated:Connect(function()
		local settings = playerGui:FindFirstChild("Settings")
		if settings and settings:IsA("ScreenGui") then
			settings.Enabled = true
		end
	end)

	-- Обзор участков. Экран почти прозрачный: смотрим на мир, а не на панель.
	local pick = Instance.new("Frame")
	pick.Size = UDim2.new(1, 0, 1, 0)
	pick.BackgroundTransparency = 1
	pick.Visible = false
	pick.Parent = screen
	browser = pick

	local plot = Instance.new("TextLabel")
	plot.BackgroundTransparency = 1
	plot.Size = UDim2.new(1, 0, 0, 54)
	plot.Position = UDim2.new(0, 0, 0.08, 0)
	plot.Font = Enum.Font.GothamBold
	plot.TextSize = 40
	plot.TextColor3 = Color3.fromRGB(245, 250, 255)
	plot.TextStrokeTransparency = 0.3
	plot.Text = "PLOT 1"
	plot.Parent = pick
	plotLabel = plot

	local owner = Instance.new("TextLabel")
	owner.BackgroundTransparency = 1
	owner.Size = UDim2.new(1, 0, 0, 34)
	owner.Position = UDim2.new(0, 0, 0.08, 56)
	owner.Font = Enum.Font.GothamMedium
	owner.TextSize = 24
	owner.TextStrokeTransparency = 0.4
	owner.Text = "FREE"
	owner.Parent = pick
	ownerLabel = owner

	makeButton(pick, "‹", UDim2.new(0, 64, 0, 64), UDim2.new(0.5, -220, 0.5, -32),
		Color3.fromRGB(44, 52, 66)).Activated:Connect(function()
		showPlot(current - 1)
	end)
	makeButton(pick, "›", UDim2.new(0, 64, 0, 64), UDim2.new(0.5, 156, 0.5, -32),
		Color3.fromRGB(44, 52, 66)).Activated:Connect(function()
		showPlot(current + 1)
	end)

	claimButton = makeButton(pick, "Claim", UDim2.new(0, 220, 0, 56),
		UDim2.new(0.5, -110, 1, -140), Color3.fromRGB(52, 116, 92))
	if claimButton then
		claimButton.Activated:Connect(function()
			local row = rows[current]
			if row and row.owner == nil then
				Remotes.get("ClaimPlot"):FireServer(row.index)
				closeMenu()
			end
		end)
	end

	makeButton(pick, "Back", UDim2.new(0, 140, 0, 44), UDim2.new(0, 24, 1, -76),
		Color3.fromRGB(52, 60, 74)).Activated:Connect(function()
		pick.Visible = false
		title.Visible = true
	end)
end

function Menu.start()
	build()

	setGameGuiVisible(false)

	-- Обзор карты сверху, пока не выбран плот.
	local overview = CFrame.new(Vector3.new(0, 1100, 1100), Vector3.zero)
	wanted = overview

	local cam = workspace.CurrentCamera
	camera = cam
	if cam then
		cam.CameraType = Enum.CameraType.Scriptable
		cam.CFrame = overview
	end

	-- Камеру приходится сторожить: при появлении персонажа Roblox
	-- переключает её обратно на него, и одной установки не хватает.
	holdConnection = RunService.RenderStepped:Connect(function()
		local live = workspace.CurrentCamera
		local target = wanted
		if live == nil or target == nil then
			return
		end
		camera = live
		if live.CameraType ~= Enum.CameraType.Scriptable then
			live.CameraType = Enum.CameraType.Scriptable
			live.CFrame = target
		end
	end)

	Remotes.get("PlotListing").OnClientEvent:Connect(function(listing: { PlotRow })
		rows = listing
		table.sort(rows, function(a, b)
			return a.index < b.index
		end)
		if browser and browser.Visible then
			showPlot(current)
		end
	end)

	Remotes.get("RequestPlots"):FireServer()
end

return Menu
