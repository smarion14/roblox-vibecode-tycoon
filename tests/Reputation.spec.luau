--!strict
local Reputation = require("../src/ReplicatedStorage/Shared/Reputation")

local tests = {}

tests["reputation multiplier"] = function()
	assert(Reputation.Multiplier(0, 0.8, 1.5) == 0.8)
	assert(Reputation.Multiplier(100, 0.8, 1.5) == 1.5)
	assert(math.abs(Reputation.Multiplier(50, 0.8, 1.5) - 1.15) < 1e-9)
	assert(Reputation.Multiplier(-10, 0.8, 1.5) == 0.8)
	assert(Reputation.Multiplier(130, 0.8, 1.5) == 1.5)
end

tests["reputation clamps"] = function()
	assert(Reputation.Apply(98, 20) == 100)
	assert(Reputation.Apply(3, -10) == 0)
	assert(Reputation.Apply(50, 10) == 60)
end

return tests
