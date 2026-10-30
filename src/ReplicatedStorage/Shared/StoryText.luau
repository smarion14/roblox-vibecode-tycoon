--!strict
-- Story copy. English, generic setting. The doubter is the player's older sibling, a senior engineer.
local StoryText = {}

StoryText.INTRO = {
	"3:07 AM. Your sibling's couch.",
	"Your first AI-built app is one prompt away from shipping.",
	"Your sibling reads your screen over your shoulder. Then closes the laptop.",
	"That's not coding. That's autocomplete in a hoodie. You've got one month to make rent or you're out.",
	"Rent goal is on your screen. Check your phone for work.",
}

-- Sent after each deploy, in order: mocking first, grudging later.
StoryText.SIBLING_TEXTS = {
	"lol it crashed for me",
	"who is paying you for this",
	"why is the button pink. why is it always pink",
	"ok the taco truck site is kind of clean",
	"...how much did that pay?",
	"fine. it works. don't tell anyone i said that",
	"are you eating? you should eat",
}

StoryText.RENT_PAID = {
	"You hand over the rent. Your sibling counts it twice.",
	"\"...Okay. You can stay.\"",
	"\"Don't make it weird.\"",
}

StoryText.ACT1_COMPLETE = "Act 1 complete. To be continued."

-- Act 1 ending cutscene (after paying rent). The last line points to the office for Act 2.
StoryText.ACT1_END = {
	{ Speaker = "Brother", Text = "...Okay. You can stay." },
	{ Speaker = "Brother", Text = "Don't make it weird." },
	{ Speaker = "Brother", Text = "A buddy of mine is subletting a tiny office downtown. First month's free. Take it. Get off my couch." },
} :: { { Speaker: string, Text: string } }

-- Act 1 opening cutscene lines.
StoryText.ACT1_INTRO = {
	{ Speaker = "Brother", Text = "That's not coding. That's autocomplete in a hoodie." },
	{ Speaker = "Brother", Text = "You've got one month to make rent or you're out." },
} :: { { Speaker: string, Text: string } }

StoryText.ACT2_INTRO_TEXT = "Two weeks later…"
StoryText.BROTHER_TEXT_ACT2 = "don't burn it down"
StoryText.ACT_TITLES = {
	Act1 = "ACT 1: MAKE RENT",
	Act1Done = "ACT 1 COMPLETE",
	Act2 = "ACT 2: MOVE OUT",
}

return StoryText
