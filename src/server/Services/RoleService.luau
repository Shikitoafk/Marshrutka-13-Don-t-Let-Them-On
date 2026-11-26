--!strict
-- Роли рейса: один случайный Водитель, остальные Кондукторы; если игрок один — он Кондуктор, а едет автопилот.
-- Водитель вышел из игры: назначаем нового из оставшихся, а если остался один игрок — автопилот.

local Players = game:GetService("Players")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local RoleService = {}

local roles: { [Player]: string } = {}
local driver: Player? = nil

local function setRole(player: Player, role: string)
	roles[player] = role
	Remotes.Event("RoleAssigned"):FireClient(player, role)
end

-- nil = водителя нет, едет автопилот.
function RoleService:GetDriver(): Player?
	return driver
end

-- Раздать роли участникам рейса; каждому уходит RoleAssigned.
function RoleService:AssignRoles(players: { Player })
	table.clear(roles)
	driver = if #players >= 2 then players[math.random(#players)] else nil
	for _, player in players do
		setRole(player, if player == driver then "Driver" else "Conductor")
	end
end

-- Зашёл посреди рейса — кондуктор.
function RoleService:AddConductor(player: Player)
	setRole(player, "Conductor")
end

function RoleService:ClearRoles()
	table.clear(roles)
	driver = nil
end

function RoleService:Init(_services: { [string]: any })
	Players.PlayerRemoving:Connect(function(player)
		roles[player] = nil
		if player ~= driver then
			return
		end
		driver = nil
		local rest: { Player } = {}
		for other in roles do
			table.insert(rest, other)
		end
		if #rest >= 2 then
			local newDriver = rest[math.random(#rest)]
			driver = newDriver
			setRole(newDriver, "Driver") -- на сиденье его посадит RoundService
		end
	end)
end

return RoleService
