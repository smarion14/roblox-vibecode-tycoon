--!strict
local Cutscenes = require("../src/ReplicatedStorage/Shared/Cutscenes")
local StoryText = require("../src/ReplicatedStorage/Shared/StoryText")

local COPY = {
	RentGoal = 750,
	ActGoal = 3.1,
	Act1Intro = StoryText.ACT1_INTRO,
	Act1End = StoryText.ACT1_END,
	Act2Text = StoryText.ACT2_INTRO_TEXT,
	BrotherText = StoryText.BROTHER_TEXT_ACT2,
	Titles = StoryText.ACT_TITLES,
	Act3Goal = 40000,
	StartupName = "Night Shift Labs",
	PlayerName = "Ada",
	Act2Ticker = StoryText.ACT2_END_TICKER,
	Act3Text = StoryText.ACT3_INTRO_TEXT,
	BrotherTextAct3 = StoryText.BROTHER_TEXT_ACT3,
	Finale = StoryText.FINALE,
}

local function lines(steps: { Cutscenes.Step }): { string }
	local found: { string } = {}
	for _, step in steps do
		if step.Kind == "Line" then
			table.insert(found, (step :: any).Text)
		end
	end
	return found
end

local function indexOf(steps: { Cutscenes.Step }, kind: string): number
	local last = 0
	for index, step in steps do
		if step.Kind == kind then
			last = index
		end
	end
	return last
end

local tests = {}

tests["each cutscene validates against its layout"] = function()
	local ok1, err1 = Cutscenes.Validate(Cutscenes.Get("Act1Intro", COPY), Cutscenes.HOMELAB_MARKERS)
	assert(ok1, err1)
	local ok2, err2 = Cutscenes.Validate(Cutscenes.Get("Act1End", COPY), Cutscenes.HOMELAB_MARKERS)
	assert(ok2, err2)
	local ok3, err3 = Cutscenes.Validate(Cutscenes.Get("Act2Intro", COPY), Cutscenes.OFFICE_MARKERS)
	assert(ok3, err3)
end

tests["exact brother lines appear"] = function()
	local intro = lines(Cutscenes.Get("Act1Intro", COPY))
	assert(table.find(intro, "You're STILL doing this garbage? Typing wishes at a robot all night won't get you anywhere!"))
	assert(table.find(intro, "One month. I'll give you one month to make rent or you and your little robot pal are sleeping on the curb!"))
	local ending = lines(Cutscenes.Get("Act1End", COPY))
	assert(table.find(ending, "...Okay. You can stay."))
	assert(table.find(ending, "Don't make it weird."))
	assert(table.find(ending, "A buddy of mine is subletting a tiny office downtown. First month's free. Take it. Get off my couch."))
end

tests["act 2 intro asks for a name before its title"] = function()
	local steps = Cutscenes.Get("Act2Intro", COPY)
	assert(indexOf(steps, "NameStartup") > 0)
	assert(indexOf(steps, "NameStartup") < indexOf(steps, "Title"))
end

tests["the player sits on the couch in the act 1 intro"] = function()
	local seated = false
	for _, step in Cutscenes.Get("Act1Intro", COPY) do
		if step.Kind == "Actor" and step.Marker == "CouchSeat" then
			seated = step.Seated == true
		end
	end
	assert(seated, "the CouchSeat actor step must be Seated")
end

tests["the camera turns to the brother whenever he speaks"] = function()
	for _, id in { "Act1Intro", "Act1End" } do
		for _, step in Cutscenes.Get(id, COPY) do
			if step.Kind == "Line" and step.Speaker == "Brother" then
				assert(step.Focus == "Brother", `{id}: "{step.Text}" doesn't focus the brother`)
			end
		end
	end
end

tests["the rent threat is delivered under stress"] = function()
	for _, step in Cutscenes.Get("Act1Intro", COPY) do
		if step.Kind == "Line" and string.find(step.Text or "", "sleeping on the curb", 1, true) then
			assert(step.Fx == "Stress")
			return
		end
	end
	error("rent threat line missing")
end

tests["act 3 scenes validate against their layouts"] = function()
	local ok1, err1 = Cutscenes.Validate(Cutscenes.Get("Act2End", COPY), Cutscenes.OFFICE_MARKERS)
	assert(ok1, err1)
	local ok2, err2 = Cutscenes.Validate(Cutscenes.Get("Act3Intro", COPY), Cutscenes.CAMPUS_MARKERS)
	assert(ok2, err2)
	local ok3, err3 = Cutscenes.Validate(Cutscenes.Get("Finale", COPY), Cutscenes.CAMPUS_MARKERS)
	assert(ok3, err3)
end

tests["finale lines are exact and focused"] = function()
	local steps = Cutscenes.Get("Finale", COPY)
	local found = lines(steps)
	assert(table.find(found, "...Okay. This is actually impressive."))
	assert(table.find(found, "I'm still not calling it real coding."))
	assert(table.find(found, "...Proud of you. Don't make it weird."))
	local fx: { string } = {}
	for _, step in steps do
		if step.Kind == "Line" and step.Speaker == "Brother" then
			assert(step.Focus == "Brother", `"{step.Text}" doesn't focus the brother`)
			table.insert(fx, step.Fx :: string)
		end
	end
	assert(table.concat(fx, ",") == "Push,Shout,Push")
end

tests["credits name the player and startup"] = function()
	for _, step in Cutscenes.Get("Finale", COPY) do
		if step.Kind == "Credits" then
			assert(table.find(step.Lines :: { string }, "Founded by Ada"))
			assert(table.find(step.Lines :: { string }, "Night Shift Labs"))
			return
		end
	end
	error("credits step missing")
end

tests["act 2 ending names the startup and act 3 states the goal"] = function()
	for _, step in Cutscenes.Get("Act2End", COPY) do
		if step.Prop == "NewsTicker" then
			assert(step.Text == "BREAKING: Night Shift Labs closes record funding round")
		end
	end
	local steps = Cutscenes.Get("Act3Intro", COPY)
	assert(steps[#steps].Sub == "Earn $40,000")
end

tests["validate rejects an unknown effect"] = function()
	local steps: { Cutscenes.Step } = {
		{ Kind = "Line", Speaker = "Brother", Text = "X", Fx = "Explode" } :: any,
		{ Kind = "Title", Text = "X" } :: any,
	}
	local ok, err = Cutscenes.Validate(steps, Cutscenes.HOMELAB_MARKERS)
	assert(not ok and err and string.find(err, "Explode", 1, true))
end

tests["validate rejects a missing marker"] = function()
	local steps: { Cutscenes.Step } = {
		{ Kind = "Shot", From = "Nowhere", Seconds = 1 } :: any,
		{ Kind = "Title", Text = "X" } :: any,
	}
	local ok, err = Cutscenes.Validate(steps, Cutscenes.HOMELAB_MARKERS)
	assert(not ok and err and string.find(err, "Nowhere", 1, true))
end

return tests
