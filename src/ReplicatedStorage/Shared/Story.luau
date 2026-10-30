--!strict
-- Pure: no requires, no Roblox APIs. Which story cutscene comes next, the Act 1 -> Act 2 transition, the act goal,
-- and the cheap checks on a startup name before the server's text filter sees it.

export type CutsceneId = "Act1Intro" | "Act1End" | "Act2Intro"

export type StoryState = {
	Act: number,
	SeenIntro: boolean,
	RentPaid: boolean,
	Flags: { [string]: boolean },
}

local NAME_MIN = 3
local NAME_MAX = 24

local Story = {}

-- The one cutscene this save still owes the player, in story order. Resumes correctly after leaving mid-scene.
function Story.NextBeat(state: StoryState): CutsceneId?
	if state.Act == 1 then
		if state.RentPaid then
			return "Act1End"
		elseif not state.SeenIntro then
			return "Act1Intro"
		end
		return nil
	end
	if state.Act == 2 and not state.Flags.Act2IntroSeen then
		return "Act2Intro"
	end
	return nil
end

-- A client may only finish the cutscene the server is waiting for.
function Story.AcceptDone(state: StoryState, id: string): boolean
	return id == Story.NextBeat(state)
end

function Story.Act2Start(valuation: number, step: number): { Act: number, ActDeploys: number, ActGoal: number }
	return { Act = 2, ActDeploys = 0, ActGoal = valuation + step }
end

function Story.ActGoalReached(act: number, valuation: number, goal: number): boolean
	return act >= 2 and valuation >= goal
end

-- Trims and collapses spaces, then checks length and that there's at least one letter or number.
function Story.PrecheckName(raw: string): (string?, string?)
	local clean = string.gsub(raw, "%s+", " ")
	clean = string.match(clean, "^%s*(.-)%s*$") or ""
	if utf8.len(clean) == nil or #clean < NAME_MIN then
		return nil, "Too short"
	end
	if (utf8.len(clean) :: number) > NAME_MAX then
		return nil, "Too long"
	end
	if not string.find(clean, "%w") then
		return nil, "Letters or numbers only"
	end
	return clean, nil
end

return Story
