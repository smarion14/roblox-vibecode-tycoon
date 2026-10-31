--!strict
-- Answer keys for the Act 3 incident minigames (Triage / ClapBack). Server only: in ServerStorage so clients can't
-- match a round against the bank. IncidentService passes them into the pure modules through options.Bank.
-- No Roblox APIs, so tests can require it by path.
local IncidentBanks = {}

IncidentBanks.TRIAGE_REPORTS = {
	{ Text = "Checkout button deletes every customer's cart. Confetti still plays.", Answer = "Critical" },
	{ Text = "Login page accepts any password, including 'password'.", Answer = "Critical" },
	{ Text = "The database backup has been running into a wall since Tuesday.", Answer = "Critical" },
	{ Text = "App crashes on launch for everyone holding a left-handed mouse.", Answer = "Critical" },
	{ Text = "Payments are charged twice, once in dollars and once in vibes.", Answer = "Critical" },
	{ Text = "Logo is two pixels off-center on the loading screen.", Answer = "Minor" },
	{ Text = "Settings page says 'Setings'.", Answer = "Minor" },
	{ Text = "Dark mode is a slightly different dark on Thursdays.", Answer = "Minor" },
	{ Text = "Tooltip appears half a second late and looks a bit smug.", Answer = "Minor" },
	{ Text = "Footer link color is teal when the brand guide says cyan.", Answer = "Minor" },
	{ Text = "User reports the app 'works too fast' and wants a slower mode.", Answer = "NotABug" },
	{ Text = "Customer says the Back button doesn't work. They are pressing Refresh.", Answer = "NotABug" },
	{ Text = "Bug: the office plant is not in the app.", Answer = "NotABug" },
	{ Text = "Report says 'it's broken' with no screenshot, steps, or hope.", Answer = "NotABug" },
	{ Text = "Tester wants the intern's lunch order to appear in the analytics.", Answer = "NotABug" },
} :: { { Text: string, Answer: string } }

-- Best = index of the reply that de-escalates with humor. The other two are too hostile or too robotic.
IncidentBanks.CLAPBACK_POSTS = {
	{
		Post = "your app deleted my homework and also my streak of 3 days",
		Replies = {
			"Skill issue. Next.",
			"Ouch! We restored both and added a small cape to your streak. Thanks for the shout.",
			"Per policy 4.2.1, homework is out of scope. Have a productive day.",
		},
		Best = 2,
	},
	{
		Post = "this startup is just a hoodie with a logo lol",
		Replies = {
			"The hoodie is premium and the logo is vector. We accept your respect.",
			"We have lawyers and also lawyers for the lawyers.",
			"Delete this or we'll mute you.",
		},
		Best = 1,
	},
	{
		Post = "why does the app take 40 seconds to load??",
		Replies = {
			"It builds anticipation. Just kidding, fix incoming, grab a snack while we sprint.",
			"Your internet is the problem. Our internet is perfect.",
			"Loading time is a feature. Please re-read the feature list.",
		},
		Best = 1,
	},
	{
		Post = "updated the app and now it's purple?? I hate purple",
		Replies = {
			"Purple is now mandatory.",
			"Noted! We added a color picker. Retro cyan is one tap away.",
			"Have you tried not hating purple?",
		},
		Best = 2,
	},
	{
		Post = "support never replies. i've waited a whole day",
		Replies = {
			"Our team replied at the speed of light. You were in a tunnel.",
			"A whole day? Ouch. Sorry! We just bumped you to the front of the line and sent snacks.",
			"We are experiencing high volumes of nothing wrong.",
		},
		Best = 2,
	},
	{
		Post = "ur CEO's keynote slides had 47 emojis. cringe",
		Replies = {
			"Forty-eight. You missed the tiny one. We're proud of every single emoji.",
			"Emoji count is confidential.",
			"Bold of you to read slides this carefully and not hire us.",
		},
		Best = 1,
	},
	{
		Post = "bug: the app says 'good morning' at 11 PM",
		Replies = {
			"It's morning somewhere. Probably.",
			"That is not a bug, that is your clock being dramatic.",
			"Fair catch! The app is now a night owl and says 'good evening'. Thanks for the tip.",
		},
		Best = 3,
	},
	{
		Post = "your mascot looks like a toaster in a tie",
		Replies = {
			"He prefers 'executive appliance'. We'll pass along the compliment.",
			"Our mascot has feelings. Please apologize.",
			"Sticks and stones, toaster-hater.",
		},
		Best = 1,
	},
	{
		Post = "Hey, I paid for premium and got ads for premium",
		Replies = {
			"Premium ads are a premium experience.",
			"Whoops, that's on us! Ads are gone and you get a free month. Thank you for flagging it.",
			"Please consult the Terms of Service, page 900.",
		},
		Best = 2,
	},
	{
		Post = "the retro terminal font gives me eye strain",
		Replies = {
			"Eyes get used to greatness.",
			"Maybe try a bigger monitor and a better attitude.",
			"Good point. We added a font size slider and a rest-your-eyes dim mode. Hydrate, friend!",
		},
		Best = 3,
	},
} :: { { Post: string, Replies: { string }, Best: number } }

return IncidentBanks
