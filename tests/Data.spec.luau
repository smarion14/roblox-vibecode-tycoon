--!strict
local GameConfig = require("../src/ReplicatedStorage/Shared/GameConfig")
local PromptBank = require("../src/ReplicatedStorage/Shared/PromptBank")
local RemoteNames = require("../src/ReplicatedStorage/Shared/RemoteNames")

local function allPrompts(): { string }
	local prompts: { string } = {}
	for _, list in PromptBank.BURST_PROMPTS do
		for _, prompt in list do
			table.insert(prompts, prompt)
		end
	end
	for _, prompt in PromptBank.BATTLE_PROMPTS do
		table.insert(prompts, prompt)
	end
	return prompts
end

local tests = {}

tests["every recipe names only known components"] = function()
	local known: { [string]: boolean } = {}
	for _, component in GameConfig.COMPONENTS do
		known[component] = true
	end
	for recipeName, recipe in GameConfig.RECIPES do
		for component in recipe do
			assert(known[component], `{recipeName} uses unknown component {component}`)
		end
	end
end

tests["every client project has a recipe"] = function()
	for _, client in GameConfig.CLIENTS do
		assert(GameConfig.RECIPES[client.Project], `{client.Id} has no recipe`)
	end
end

tests["every component has burst prompts"] = function()
	for _, component in GameConfig.COMPONENTS do
		local list = PromptBank.BURST_PROMPTS[component]
		assert(list and #list >= 8, `{component} needs at least 8 burst prompts`)
	end
	assert(#PromptBank.BATTLE_PROMPTS >= 10, "need at least 10 battle prompts")
	assert(#PromptBank.BUG_WORDS >= 12, "need at least 12 bug words")
end

tests["prompts are lowercase ascii"] = function()
	for _, prompt in allPrompts() do
		assert(string.match(prompt, "^[a-z0-9 ,]+$"), `bad characters in "{prompt}"`)
	end
end

tests["no prompt contains a bug word as a whole word"] = function()
	for _, prompt in allPrompts() do
		local padded = ` {string.gsub(prompt, ",", " ")} `
		for _, word in PromptBank.BUG_WORDS do
			assert(string.find(padded, ` {word} `, 1, true) == nil, `"{prompt}" contains bug word "{word}"`)
		end
	end
end

tests["bug words are unique"] = function()
	local seen: { [string]: boolean } = {}
	for _, word in PromptBank.BUG_WORDS do
		assert(not seen[word], `duplicate bug word {word}`)
		seen[word] = true
	end
end

tests["remote names map to themselves"] = function()
	local count = 0
	for key, value in RemoteNames do
		assert(key == value, `{key} maps to {value}`)
		count += 1
	end
	assert(count == 15, `expected 15 remote names, got {count}`)
end

return tests
