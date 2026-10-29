--!strict
-- Client bootstrap: Init and Start on each controller.
type Controller = { Init: () -> (), Start: () -> () }

local controllersFolder = script.Parent:FindFirstChild("Controllers")
local controllers: { Controller } = {}
if controllersFolder then
	for _, child in controllersFolder:GetChildren() do
		if child:IsA("ModuleScript") then
			table.insert(controllers, require(child) :: any)
		end
	end
end

for _, controller in controllers do
	controller.Init()
end
for _, controller in controllers do
	controller.Start()
end
