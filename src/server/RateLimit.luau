--!strict
-- Ограничение частоты вызовов ремоута одним игроком: лишнее в этой секунде отбрасываем до любой работы.
-- Использование: local allow = RateLimit.new(5)  …  if not allow(player) then return end

local Players = game:GetService("Players")

local RateLimit = {}

function RateLimit.new(perSecond: number): (Player) -> boolean
	local windowStart: { [Player]: number } = {}
	local count: { [Player]: number } = {}
	Players.PlayerRemoving:Connect(function(player)
		windowStart[player] = nil
		count[player] = nil
	end)
	return function(player: Player): boolean
		local now = time()
		if now - (windowStart[player] or -math.huge) >= 1 then
			windowStart[player] = now
			count[player] = 0
		end
		local calls = (count[player] or 0) + 1
		count[player] = calls
		return calls <= perSecond
	end
end

return RateLimit
