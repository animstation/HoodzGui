--[[
	Hoodz test script (v1.3)

	1. Loads the library from GitHub and builds a demo UI that exercises every component
	   (tile pairing, sliders, categories, scrolling).
	2. Runs a self-test (components, settings, themes, show/hide) and shows every PASS / FAIL
	   in Tests > Self-test (also in the console).
	3. OPTIONAL: set RELOAD_TEST = true to also load the library a second time and prove that
	   reloading replaces the old UI. That makes the loading screen + music play twice,
	   so it is OFF by default.

	Sliders: grab one in "Stress Test > Scrolling" and drag up/down -
	only the slider you grabbed should move.
]]

local URL = "https://raw.githubusercontent.com/animstation/HoodzGui/refs/heads/main/HoodzLib.lua"

local RELOAD_TEST = false -- true = also load the library a 2nd time (UI loads twice on purpose)

local function loadLib()
	return loadstring(game:HttpGet(URL))()
end

local ok, Hoodz = pcall(loadLib)
if not ok or type(Hoodz) ~= "table" then
	warn("[Hoodz test] failed to load the library:", Hoodz)
	return
end

local results = {}
local function check(name, cond)
	table.insert(results, { name = name, ok = cond and true or false })
	print("[Hoodz test] " .. (cond and "PASS" or "FAIL") .. "  " .. name)
end

----------------------------------------------------------------------
-- Demo UI (nothing else is needed: logo + music are built in)
----------------------------------------------------------------------
local function build(lib, summary)
	local UI = lib.new({
		Title = "Hoodz",
		LoadingTime = 2,
		ToggleKey = Enum.KeyCode.RightShift,
	})
	local c = {}

	-- Category 1: Components
	local components = UI:CreateCategory("Components")

	local togglesTab = components:CreateTab("Toggles")
	local status = togglesTab:CreateLabel("Status: waiting...")
	togglesTab:CreateSection("Tiles pair up two per row")
	c.toggleA = togglesTab:CreateToggle({
		Name = "Toggle A",
		Default = false,
		Callback = function(on)
			status:Set("Toggle A = " .. tostring(on))
		end,
	})
	togglesTab:CreateToggle({
		Name = "Toggle B",
		Default = true,
		Callback = function(on)
			status:Set("Toggle B = " .. tostring(on))
		end,
	})
	togglesTab:CreateToggle({ Name = "Toggle C", Callback = print })
	togglesTab:CreateToggle({ Name = "Toggle D", Callback = print })
	togglesTab:CreateToggle({ Name = "A lone toggle stays full width", Callback = print })
	togglesTab:CreateSection("Buttons")
	togglesTab:CreateButton({
		Name = "Flip Toggle A",
		Callback = function()
			c.toggleA:Set(not c.toggleA:Get())
		end,
	})
	togglesTab:CreateButton({
		Name = "Print hello",
		Callback = function()
			print("[Hoodz test] hello from a button")
		end,
	})

	local slidersTab = components:CreateTab("Sliders")
	local readout = slidersTab:CreateLabel("Slider value: 50")
	slidersTab:CreateSection("Values")
	c.sliderA = slidersTab:CreateSlider({
		Name = "Whole numbers",
		Min = 0,
		Max = 100,
		Default = 50,
		Increment = 1,
		Callback = function(v)
			readout:Set("Slider value: " .. v)
		end,
	})
	c.sliderB = slidersTab:CreateSlider({
		Name = "Decimals (0.05 steps)",
		Min = 0,
		Max = 1,
		Default = 0.5,
		Increment = 0.05,
	})
	slidersTab:CreateSlider({ Name = "Big range (step 10)", Min = 0, Max = 500, Default = 100, Increment = 10 })

	-- Category 2: Stress Test
	local stress = UI:CreateCategory("Stress Test")
	local scrollTab = stress:CreateTab("Scrolling")
	for i = 1, 6 do
		scrollTab:CreateSlider({ Name = "Value " .. i, Min = 0, Max = 10, Default = i })
	end
	for i = 1, 6 do
		scrollTab:CreateToggle({ Name = "Option " .. i })
	end

	-- Category 3: Tests (self-test report)
	local tests = UI:CreateCategory("Tests")
	local report = tests:CreateTab("Self-test")
	if summary then
		local passed = 0
		for _, r in ipairs(summary) do
			if r.ok then
				passed += 1
			end
		end
		report:CreateSection(passed .. " / " .. #summary .. " passed")
		for _, r in ipairs(summary) do
			report:CreateLabel((r.ok and "PASS   " or "FAIL   ") .. r.name)
		end
	else
		c.report = report
		c.status = report:CreateLabel("Running self-test...")
	end

	return UI, c
end

----------------------------------------------------------------------
-- Self-test
----------------------------------------------------------------------
local UI, c = build(Hoodz, nil)
check("library exposes new()", type(Hoodz.new) == "function")
check("UI finished loading", UI:WaitUntilLoaded(40))

-- themes
local startedTheme = UI.ThemeName
check("starts on a known theme", startedTheme == "Hoodz" or startedTheme == "BlackGrey" or startedTheme == "Blue" or startedTheme == "White" or startedTheme == "Admin")
check("SetTheme(Blue) switches ThemeName", UI:SetTheme("Blue") == true and UI.ThemeName == "Blue")
check("SetTheme(BlackGrey) switches ThemeName", UI:SetTheme("BlackGrey") == true and UI.ThemeName == "BlackGrey")
check("SetTheme(White) switches ThemeName", UI:SetTheme("White") == true and UI.ThemeName == "White")
check("unknown theme name is rejected", UI:SetTheme("NotARealTheme") == false)
check("Themes tab exists in the Hoodz category", UI.ThemesTab ~= nil)
check("the hidden Admin theme is reachable by name and is Static", (function()
	local ok = UI:SetTheme("Admin")
	return ok == true and UI.ThemeName == "Admin" and UI.ActiveTheme.Static == true
end)())
UI:SetTheme(startedTheme) -- restore

-- components
c.toggleA:Set(true, true)
check("toggle: Set(true) then Get() == true", c.toggleA:Get() == true)
c.toggleA:Set(false, true)
check("toggle: Set(false) then Get() == false", c.toggleA:Get() == false)
c.sliderA:Set(150)
check("slider: value above Max is clamped to 100", c.sliderA:Get() == 100)
c.sliderA:Set(33.4)
check("slider: Increment 1 rounds 33.4 to 33", c.sliderA:Get() == 33)
c.sliderB:Set(0.37)
check("slider: Increment 0.05 rounds 0.37 to 0.35", c.sliderB:Get() == 0.35)

-- built-in settings
local oldVol, oldMusic, oldXf = UI.Settings.Volume, UI.Settings.Music, UI.Settings.Crossfade
UI:SetVolume(25)
check("settings: SetVolume(25)", UI.Settings.Volume == 25)
UI:SetCrossfade(6)
check("settings: SetCrossfade(6)", UI.Settings.Crossfade == 6)
UI:SetMusic(not oldMusic)
check("settings: SetMusic toggles", UI.Settings.Music == (not oldMusic))
UI:SetMusic(oldMusic)
UI:SetVolume(oldVol)
UI:SetCrossfade(oldXf)
check("settings: values restored", UI.Settings.Music == oldMusic and UI.Settings.Volume == oldVol)
check("built-in Settings tab exists", UI.SettingsTab ~= nil)

-- show / hide
UI:SetVisible(false)
task.wait(0.4)
check("SetVisible(false) hides the UI", UI.Main.Visible == false)
UI:SetVisible(true)
task.wait(0.4)
check("SetVisible(true) shows the UI", UI.Main.Visible == true)

local function countPassed()
	local n = 0
	for _, r in ipairs(results) do
		if r.ok then
			n += 1
		end
	end
	return n
end

if RELOAD_TEST then
	-- reload: loading the library a second time must replace the first UI
	local first = UI
	local lib2 = loadLib()
	task.wait(0.3)
	check("reload: loading the library again destroys the old UI", first.Gui.Parent == nil)
	check("reload: a fresh library table is returned", lib2 ~= nil and lib2 ~= Hoodz)
	-- rebuild with the new library and show the report
	UI = build(lib2, results)
else
	-- single load: write the results into the existing UI
	c.status:Set(countPassed() .. " / " .. #results .. " passed")
	for _, r in ipairs(results) do
		c.report:CreateLabel((r.ok and "PASS   " or "FAIL   ") .. r.name)
	end
end

print(("[Hoodz test] done: %d / %d passed"):format(countPassed(), #results))
