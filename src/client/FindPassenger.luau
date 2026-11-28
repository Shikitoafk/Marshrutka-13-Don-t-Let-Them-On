--!strict

return function(folder: Instance?, id: string): Model?
	if folder then
		for _, model in folder:GetChildren() do
			if model:IsA("Model") and model:GetAttribute("PassengerId") == id then
				return model
			end
		end
	end
	return nil
end
