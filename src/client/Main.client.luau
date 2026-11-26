--!strict
-- Точка входа клиента. НЕ добавляйте сюда логику.
-- Загружает все ModuleScript из папки Controllers (кроме тех, что начинаются с "_"),
-- вызывает :Init(registry), затем :Start() в отдельном потоке.

local controllersFolder = script.Parent:WaitForChild("Controllers")

local registry: { [string]: any } = {}

for _, child in controllersFolder:GetChildren() do
	if child:IsA("ModuleScript") and string.sub(child.Name, 1, 1) ~= "_" then
		local ok, result = pcall(require, child)
		if ok then
			registry[child.Name] = result
		else
			warn(`[Client] Не удалось загрузить {child.Name}: {result}`)
		end
	end
end

for name, controller in registry do
	if type(controller) == "table" and type(controller.Init) == "function" then
		local ok, err = pcall(controller.Init, controller, registry)
		if not ok then
			warn(`[Client] {name}:Init упал: {err}`)
		end
	end
end

for name, controller in registry do
	if type(controller) == "table" and type(controller.Start) == "function" then
		task.spawn(function()
			local ok, err = pcall(controller.Start, controller)
			if not ok then
				warn(`[Client] {name}:Start упал: {err}`)
			end
		end)
	end
end
