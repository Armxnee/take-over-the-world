--!strict
-- Server entry point.
local Players = game:GetService("Players")
Players.CharacterAutoLoads = false

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Match = require(script.Parent.Match)
local DevTests = require(script.Parent.DevTests)
local PlayerData = require(script.Parent.PlayerData)
local Shop = require(script.Parent.Shop)

Match.init()
PlayerData.init()
Shop.init(ReplicatedStorage:WaitForChild("Remotes") :: Folder)
DevTests.init()
