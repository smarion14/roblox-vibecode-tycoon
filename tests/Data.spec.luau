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
	for _, phrase in PromptBank.BOSS_PHRASES do
		table.insert(prompts, phrase)
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
	assert(#PromptBank.BOSS_PHRASES >= 6, "need at least 6 boss phrases")
	for _, phrase in PromptBank.BOSS_PHRASES do
		local words = #string.split(phrase, " ")
		assert(words >= 3 and words <= 5, `boss phrase "{phrase}" needs 3-5 words`)
	end
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
	assert(count == 24, `expected 24 remote names, got {count}`)
end

tests["intro contains the exact doubter line"] = function()
	local StoryText = require("../src/ReplicatedStorage/Shared/StoryText")
	local found = table.find(
		StoryText.INTRO,
		"That's not coding. That's autocomplete in a hoodie. You've got one month to make rent or you're out."
	)
	assert(found, "doubter line missing")
	assert(#StoryText.SIBLING_TEXTS >= 6)
	assert(StoryText.SIBLING_TEXTS[1] == "lol it crashed for me")
	assert(table.find(StoryText.SIBLING_TEXTS, "...how much did that pay?"))
	assert(StoryText.ACT1_COMPLETE == "Act 1 complete. To be continued.")
end

tests["every station has a minigame"] = function()
	local known = { Typing = true, PatchPanel = true, RaidRebuild = true, TrainingRun = true }
	for _, component in GameConfig.COMPONENTS do
		local kind = GameConfig.STATION_MINIGAMES[component]
		assert(kind and known[kind], `{component} has no minigame`)
	end
	assert(GameConfig.STATION_MINIGAMES.FrontendUnits == "Typing")
end

tests["act 1 ending uses the exact brother lines"] = function()
	local StoryText = require("../src/ReplicatedStorage/Shared/StoryText")
	local wanted = {
		"...Okay. You can stay.",
		"Don't make it weird.",
		"A buddy of mine is subletting a tiny office downtown. First month's free. Take it. Get off my couch.",
	}
	for _, text in wanted do
		local found = false
		for _, line in StoryText.ACT1_END do
			if line.Speaker == "Brother" and line.Text == text then
				found = true
			end
		end
		assert(found, `missing brother line: {text}`)
	end
	assert(StoryText.ACT2_INTRO_TEXT == "Two weeks later…")
	assert(StoryText.BROTHER_TEXT_ACT2 == "don't burn it down")
	assert(StoryText.ACT_TITLES.Act2 == "ACT 2: MOVE OUT")
end

return tests
