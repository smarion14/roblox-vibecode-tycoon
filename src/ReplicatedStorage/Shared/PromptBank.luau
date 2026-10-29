--!strict
-- Player-facing typing content. English, generic setting, lowercase ascii only.
-- Prompts must never contain a bug word: typing it would squash a bug mid-prompt.
local PromptBank = {}

PromptBank.BURST_PROMPTS = {
	FrontendUnits = {
		"make the navbar sticky on scroll",
		"add a dark mode toggle to the header",
		"center the hero image on mobile",
		"give the buttons rounded corners",
		"show a spinner while the page loads",
		"make the footer links bigger",
		"add a contact form with an email field",
		"use a bold font for every heading",
		"put the logo in the top left corner",
		"fade in the cards when they appear",
	},
	BackendEndpoints = {
		"add an endpoint that lists all orders",
		"return a friendly error when login fails",
		"send a welcome email after signup",
		"limit each user to ten requests a second",
		"add a health check route for the server",
		"save uploaded photos to cloud storage",
		"cache the menu for five minutes",
		"log every payment with a timestamp",
		"add a route to cancel a booking",
		"validate the phone number on signup",
	},
	DatabaseTables = {
		"create a table for customer bookings",
		"add an index on the email column",
		"store prices as whole cents",
		"keep a history of every order change",
		"add a created at column to each table",
		"link each pet to its owner",
		"delete expired sessions every night",
		"make usernames unique in the users table",
		"back up the database every hour",
		"add a table for gift card balances",
	},
	PromptTokens = {
		"write a cheerful welcome message",
		"summarize each review in one sentence",
		"suggest three names for a new menu item",
		"reply to support emails in a calm tone",
		"turn this price list into a short poem",
		"write alt text for every product photo",
		"translate the menu into plain words",
		"draft a thank you note for new customers",
		"pick an emoji for each food category",
		"explain the refund policy simply",
	},
} :: { [string]: { string } }

PromptBank.BATTLE_PROMPTS = {
	"add a booking calendar and send reminder emails the day before",
	"let customers pay online and email them a receipt right away",
	"build a menu page that shows todays specials at the top",
	"add a review section with star ratings under each service",
	"make a map page that shows where the truck parks each day",
	"add a sign up form that saves the email to the mailing list",
	"show a banner when the shop is closed for the holidays",
	"let staff mark an order as ready and notify the customer",
	"add a search box that filters products as you type",
	"build a simple admin page to edit prices and photos",
	"add a gallery of before and after grooming photos",
	"send a text message when a table becomes available",
}

PromptBank.BUG_WORDS = {
	"null",
	"cors",
	"race",
	"typo",
	"leak",
	"loop",
	"crash",
	"lag",
	"panic",
	"stack",
	"hang",
	"nan",
	"drift",
	"fault",
	"oops",
	"segv",
}

return PromptBank
