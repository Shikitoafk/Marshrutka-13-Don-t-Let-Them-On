--!strict
-- Точка входа сервера. НЕ добавляйте сюда игровую логику.
-- Загружает все ModuleScript из папки Services (кроме тех, что начинаются с "_"),
-- затем вызывает у каждого :Init(registry), а потом :Start() в отдельном потоке.
-- registry — таблица всех сервисов по имени, через неё сервисы находят друг друга.

local servicesFolder = script.Parent:WaitForChild("Services")

local registry: { [string]: any } = {}

for _, child in servicesFolder:GetChildren() do
	if child:IsA("ModuleScript") and string.sub(child.Name, 1, 1) ~= "_" then
		local ok, result = pcall(require, child)
		if ok then
			registry[child.Name] = result
		else
			warn(`[Server] Не удалось загрузить {child.Name}: {result}`)
		end
	end
end

for name, service in registry do
	if type(service) == "table" and type(service.Init) == "function" then
		local ok, err = pcall(service.Init, service, registry)
		if not ok then
			warn(`[Server] {name}:Init упал: {err}`)
		end
	end
end

for name, service in registry do
	if type(service) == "table" and type(service.Start) == "function" then
		task.spawn(function()
			local ok, err = pcall(service.Start, service)
			if not ok then
				warn(`[Server] {name}:Start упал: {err}`)
			end
		end)
	end
end

local count = 0
for _ in registry do
	count += 1
end
print(`[Server] Запущено сервисов: {count}`)
