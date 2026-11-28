--!strict

local Config = require(script.Parent.Config)

export type Category = "Flashlight" | "TakenEffect"
export type Item = { Id: string, Price: number, GamepassId: number? }
local Cosmetics = {}
Cosmetics.Categories = { "Flashlight", "TakenEffect" } :: { Category }
Cosmetics.Default = { Flashlight = "Classic", TakenEffect = "Fade" }

function Cosmetics.list(category: Category): { Item }
	return Config.COSMETICS[category]
end

function Cosmetics.find(category: Category, id: string): Item?
	for _, item in Cosmetics.list(category) do
		if item.Id == id then return item end
	end
	return nil
end

Cosmetics.Beams = {
	Classic = { color = Color3.fromRGB(255, 239, 189), angle = 28 },
	Warm = { color = Color3.fromRGB(255, 170, 90), angle = 34 },
	Neon = { color = Color3.fromRGB(75, 248, 217), angle = 19 },
	Alarm = { color = Color3.fromRGB(255, 65, 68), angle = 23 },
	Rainbow = { color = Color3.fromRGB(181, 147, 255), angle = 31 },
}

return Cosmetics
