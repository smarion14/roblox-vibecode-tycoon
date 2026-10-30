--!strict
-- Day/night cycle. Every client derives the same time of day from the server clock (no network traffic) and
-- blends between a bright day look and a moody-but-readable night. Building neon only switches on at night.
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DayCycle = require(Shared:WaitForChild("DayCycle"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))

type Look = {
	Brightness: number,
	Ambient: Color3,
	OutdoorAmbient: Color3,
	AtmosphereDensity: number,
	AtmosphereColor: Color3,
	AtmosphereDecay: Color3,
	Tint: Color3,
	Contrast: number,
	Saturation: number,
	Bloom: number,
}

local DAY: Look = {
	Brightness = 2.5,
	Ambient = Color3.fromRGB(120, 112, 135),
	OutdoorAmbient = Color3.fromRGB(140, 132, 155),
	AtmosphereDensity = 0.25,
	AtmosphereColor = Color3.fromRGB(205, 185, 225),
	AtmosphereDecay = Color3.fromRGB(150, 120, 190),
	Tint = Color3.fromRGB(255, 250, 255),
	Contrast = 0.05,
	Saturation = 0.05,
	Bloom = 0.35,
}

-- Night stays readable: ambient never drops to black, the neon does the mood.
local NIGHT: Look = {
	Brightness = 1.2,
	Ambient = Color3.fromRGB(70, 55, 100),
	OutdoorAmbient = Color3.fromRGB(75, 60, 110),
	AtmosphereDensity = 0.32,
	AtmosphereColor = Color3.fromRGB(110, 70, 160),
	AtmosphereDecay = Color3.fromRGB(45, 25, 80),
	Tint = Color3.fromRGB(230, 215, 255),
	Contrast = 0.15,
	Saturation = 0.15,
	Bloom = 0.9,
}

local UPDATE_SECONDS = 0.1
local LIGHT_BRIGHTNESS = 2
local OFF_COLOR_SCALE = 0.25
local BLINK_CHANCE = 0.12 -- per update, each homelab status LED flickers off with this chance -- unlit neon keeps a dim tint so the fixtures still read as fixtures

local LightingController = {}

local elapsed = 0

local function mix(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function apply(daylight: number)
	-- t = 0 is night, 1 is day
	local t = daylight
	Lighting.Brightness = mix(NIGHT.Brightness, DAY.Brightness, t)
	Lighting.Ambient = NIGHT.Ambient:Lerp(DAY.Ambient, t)
	Lighting.OutdoorAmbient = NIGHT.OutdoorAmbient:Lerp(DAY.OutdoorAmbient, t)

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		atmosphere.Density = mix(NIGHT.AtmosphereDensity, DAY.AtmosphereDensity, t)
		atmosphere.Color = NIGHT.AtmosphereColor:Lerp(DAY.AtmosphereColor, t)
		atmosphere.Decay = NIGHT.AtmosphereDecay:Lerp(DAY.AtmosphereDecay, t)
	end
	local grade = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
	if grade then
		grade.TintColor = NIGHT.Tint:Lerp(DAY.Tint, t)
		grade.Contrast = mix(NIGHT.Contrast, DAY.Contrast, t)
		grade.Saturation = mix(NIGHT.Saturation, DAY.Saturation, t)
	end
	local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
	if bloom then
		bloom.Intensity = mix(NIGHT.Bloom, DAY.Bloom, t)
	end

	-- Building lights fade up through dusk and switch to glowing neon once it's night.
	local nightness = 1 - daylight
	local lit = nightness >= 0.5
	for _, fixture in CollectionService:GetTagged("NightLight") do
		if not fixture:IsA("BasePart") then
			continue
		end
		local color = fixture:GetAttribute("NightColor")
		if typeof(color) == "Color3" then
			fixture.Color = Color3.new(color.R * OFF_COLOR_SCALE, color.G * OFF_COLOR_SCALE, color.B * OFF_COLOR_SCALE):Lerp(color, nightness)
		end
		fixture.Material = if lit then Enum.Material.Neon else Enum.Material.SmoothPlastic
		local light = fixture:FindFirstChildOfClass("PointLight")
		if light then
			light.Enabled = nightness > 0.05
			light.Brightness = LIGHT_BRIGHTNESS * nightness
		end
	end
end

-- Homelab status LEDs: mostly on, with random flickers like real drive and network activity.
local function blinkLeds()
	for _, led in CollectionService:GetTagged("BlinkLed") do
		if led:IsA("BasePart") then
			led.Transparency = if math.random() < BLINK_CHANCE then 0.85 else 0
		end
	end
end

local function step()
	blinkLeds()
	local clock = DayCycle.ClockAt(Workspace:GetServerTimeNow(), GameConfig.DAY_CYCLE)
	Lighting.ClockTime = clock
	apply(DayCycle.Daylight(clock))
end

function LightingController.Init() end

function LightingController.Start()
	step()
	RunService.Heartbeat:Connect(function(deltaTime: number)
		elapsed += deltaTime
		if elapsed >= UPDATE_SECONDS then
			elapsed = 0
			step()
		end
	end)
end

return LightingController
