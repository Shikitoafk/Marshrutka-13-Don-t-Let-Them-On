--!strict
-- Роли рейса: один случайный Водитель, остальные Кондукторы; если игрок один — он Кондуктор, а едет автопилот.
-- Водитель вышел из игры: назначаем нового из оставшихся живых (не призраков), если живых хотя бы двое
-- (один рулит, другой ищет аномалии); иначе — автопилот.

local Players = game:GetService("Players")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local RoleService = {}

local registry: { [string]: any } = {}
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

function RoleService:Init(services: { [string]: any })
	registry = services
	Players.PlayerRemoving:Connect(function(player)
		roles[player] = nil
		if player ~= driver then
			return
		end
		driver = nil
		local ghosts = registry.GhostService
		local living: { Player } = {}
		for other in roles do
			if not (ghosts and ghosts:IsGhost(other)) then
				table.insert(living, other)
			end
		end
		if #living >= 2 then
			local newDriver = living[math.random(#living)]
			driver = newDriver
			setRole(newDriver, "Driver") -- на сиденье его посадит RoundService
		end
	end)
end

return RoleService
