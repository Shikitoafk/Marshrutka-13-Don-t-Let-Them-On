--!strict
-- Детали внешности NPC (форма контролёра, платок бабушки): простая деталь, приваренная к части тела.
-- Без массы и столкновений, чтобы не мешать ходьбе, сиденью и автобусу.

local Outfit = {}

function Outfit.attach(base: BasePart, name: string, size: Vector3, offset: CFrame, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.CanCollide, part.CanQuery, part.CanTouch, part.Massless = false, false, false, true
	part.CFrame = base.CFrame * offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0, weld.Part1 = base, part
	weld.Parent = part
	part.Parent = base.Parent
	return part
end

return Outfit
