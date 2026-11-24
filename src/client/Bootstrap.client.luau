--!strict
-- Точка входа клиента.
--
-- Клиент читает конфиг только ради интерфейса: показать цену, подписать жёлоб.
-- Ничего ценного он не считает — все начисления и проверки живут на сервере.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local BeltRenderer = require(script.Parent.BeltRenderer)
local HUD = require(script.Parent.HUD)
local Menu = require(script.Parent.Menu)
local Settings = require(script.Parent.Settings)
local SearchPanel = require(script.Parent.SearchPanel)
local Shop = require(script.Parent.Shop)

print(string.format("[client] %s v%s ready", Config.GameName, Config.Version))
print(string.format("[client] sorting between %d destinations", #Config.Destinations))

BeltRenderer.start()
HUD.start()
SearchPanel.start()
Shop.start()
Settings.start()
Menu.start()
print("[client] renderer and HUD running")
