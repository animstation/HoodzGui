--[[
	Hoodz UI Library  (open source)  v1.3

	LAYOUT: floating "islands" instead of one window
	  [ header ............................................ ]   title, breadcrumb, close
	  [rail] [tabs] [ main grid .......................... ]   category circles | tabs | tile grid
	  [ dock .............................................. ]   quick music switch + hints
	  Toggles and buttons are tiles that pair up two per row; sliders are full-width cards.
	  One continuous pixel-gradient background flows toward the top-left through all islands.

	* Logo = show/hide button (top-left). RightShift also works.
	* Built-in music: substance.mp3 plays loud + underwater while loading, settles into a low
	  clean loop that crossfades with itself (no hard restart). Settings tab: music on/off,
	  volume, crossfade length (all saved).
	* Everything is built in: logo + song auto-download from your GitHub repo on first run.
	* Loading the script twice reloads: the previous UI/music is destroyed and replaced by the new code.

	Usage:
		local Hoodz = loadstring(game:HttpGet("<raw url>"))()
		local UI = Hoodz.new({ Title = "Hoodz" })
		local tab = UI:CreateCategory("Player"):CreateTab("Movement")
		tab:CreateToggle({ Name = "Speed", Callback = function(on) end })
		tab:CreateSlider({ Name = "Walk Speed", Min = 16, Max = 100, Default = 16, Callback = function(v) end })

	Config: Title, Subtitle, LoadingTime, ToggleKey, Music (default true), MusicVolume (0-100),
	CrossfadeTime (1-10 s), Image, ImageUrl, MusicFile, MusicUrl, Name
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local HttpService = game:GetService("HttpService")

local Library = {}
Library.__index = Library
Library.Version = "1.3"

local ENV = (getgenv and getgenv()) or _G

local REPO = "https://raw.githubusercontent.com/animstation/HoodzGui/refs/heads/main/"
local DEFAULT_LOGO_FILE, DEFAULT_LOGO_URL = "IMG_3411.jpeg", REPO .. "IMG_3411.jpeg"
local DEFAULT_MUSIC_FILE, DEFAULT_MUSIC_URL = "substance.mp3", REPO .. "substance.mp3"
local SETTINGS_FILE = "Hoodz_Settings.json"

local LOUD = 2 -- volume while loading (underwater)
local CELL = 18 -- pixel size of the background mosaic

-- layout (all multiples of CELL so the background lines up across islands)
local ROOT_W, ROOT_H = 648, 432

----------------------------------------------------------------------
-- Theme
----------------------------------------------------------------------
local Theme = {
	Black = Color3.fromRGB(8, 5, 7),
	Row = Color3.fromRGB(22, 13, 16),
	Stroke = Color3.fromRGB(78, 24, 32),
	Red = Color3.fromRGB(255, 72, 84),
	RedDark = Color3.fromRGB(150, 14, 30),
	Light = Color3.fromRGB(255, 150, 158),
	LightDeep = Color3.fromRGB(255, 108, 118),
	Text = Color3.fromRGB(245, 236, 237),
	Dim = Color3.fromRGB(168, 146, 150),
	Off = Color3.fromRGB(54, 38, 43),
	Font = Enum.Font.GothamMedium,
	Bold = Enum.Font.GothamBold,
}
Library.Theme = Theme

local WHITE = Color3.new(1, 1, 1)
local REDGRAD = ColorSequence.new(Theme.Red, Theme.RedDark)
local LIGHTGRAD = ColorSequence.new(Theme.Light, Theme.LightDeep)
local TEXTGRAD = ColorSequence.new(Color3.fromRGB(255, 190, 195), Theme.Red)
local OUTLINE = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Theme.Red),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(30, 0, 4)),
	ColorSequenceKeypoint.new(1, Theme.Red),
})

local PAL = 16
local PALETTE = (function()
	local keys = {
		{ 0, Color3.fromRGB(6, 3, 5) },
		{ 0.3, Color3.fromRGB(38, 4, 12) },
		{ 0.55, Color3.fromRGB(115, 10, 26) },
		{ 0.8, Color3.fromRGB(210, 30, 46) },
		{ 1, Color3.fromRGB(255, 92, 102) },
	}
	local out = {}
	for i = 1, PAL do
		local a = (i - 1) / (PAL - 1)
		for k = 1, #keys - 1 do
			local a0, c0 = keys[k][1], keys[k][2]
			local a1, c1 = keys[k + 1][1], keys[k + 1][2]
			if a <= a1 or k == #keys - 1 then
				out[i] = c0:Lerp(c1, math.clamp((a - a0) / (a1 - a0), 0, 1))
				break
			end
		end
	end
	return out
end)()

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------
local function create(class, props, parent)
	local obj = Instance.new(class)
	for k, v in pairs(props) do
		obj[k] = v
	end
	obj.Parent = parent
	return obj
end

local function corner(parent, radius)
	return create("UICorner", { CornerRadius = radius or UDim.new(0, 10) }, parent)
end

local function grad(parent, seq, rot)
	return create("UIGradient", { Color = seq, Rotation = rot or 0 }, parent)
end

local function gradStroke(parent, thickness, seq)
	local s = create("UIStroke", {
		Thickness = thickness,
		Color = WHITE,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, parent)
	return s, grad(s, seq, 0)
end

local function solidStroke(parent, thickness, color, transparency)
	return create("UIStroke", {
		Thickness = thickness,
		Color = color,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, parent)
end

local function label(parent, text, size, color, align, bold)
	return create("TextLabel", {
		BackgroundTransparency = 1,
		Text = text,
		Font = bold and Theme.Bold or Theme.Font,
		TextSize = size,
		TextColor3 = color or Theme.Text,
		TextXAlignment = align or Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, parent)
end

local function tween(obj, t, props, style, dir)
	local tw = TweenService:Create(
		obj,
		TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out),
		props
	)
	tw:Play()
	return tw
end

local function isPointer(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

local function isMove(input)
	return input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch
end

local function getGuiParent()
	if gethui then
		local ok, r = pcall(gethui)
		if ok and r then
			return r
		end
	end
	local ok, cg = pcall(function()
		return game:GetService("CoreGui")
	end)
	if ok and cg then
		local probe = Instance.new("Folder")
		local good = pcall(function()
			probe.Parent = cg
		end) and probe.Parent == cg
		probe:Destroy()
		if good then
			return cg
		end
	end
	return Players.LocalPlayer:WaitForChild("PlayerGui")
end

-- Local file first; otherwise download once from the repo and cache it in the workspace.
local function resolveFile(file, url, minSize)
	if not (getcustomasset and isfile) then
		return nil
	end
	local function exists()
		local ok, r = pcall(isfile, file)
		return ok and r
	end
	if not exists() and url and writefile then
		local ok, data = pcall(function()
			return game:HttpGet(url)
		end)
		if ok and type(data) == "string" and #data > (minSize or 200) and data:sub(1, 3) ~= "404" then
			pcall(writefile, file, data)
		end
	end
	if exists() then
		local ok, asset = pcall(getcustomasset, file)
		if ok and asset and asset ~= "" then
			return asset
		end
	end
	return nil
end

----------------------------------------------------------------------
-- Reload support: loading the library twice replaces the old UI + music
----------------------------------------------------------------------
local function sweepOrphans()
	local hosts = {}
	if gethui then
		local ok, r = pcall(gethui)
		if ok and r then
			table.insert(hosts, r)
		end
	end
	pcall(function()
		table.insert(hosts, game:GetService("CoreGui"))
	end)
	local lp = Players.LocalPlayer
	if lp then
		local pg = lp:FindFirstChildOfClass("PlayerGui")
		if pg then
			table.insert(hosts, pg)
		end
	end
	for _, h in ipairs(hosts) do
		pcall(function()
			for _, c in ipairs(h:GetChildren()) do
				if c:IsA("ScreenGui") and (c.Name == "Hoodz" or c.Name == "HoodzSafe") then
					c:Destroy()
				end
			end
		end)
	end
	pcall(function()
		for _, c in ipairs(SoundService:GetChildren()) do
			if c.Name == "HoodzMusic" then
				c:Destroy()
			end
		end
	end)
end

local function cleanupPrevious()
	local prev = ENV.__HoodzInstance
	ENV.__HoodzInstance = nil
	if prev and type(prev.Destroy) == "function" then
		pcall(function()
			prev:Destroy()
		end)
	end
	sweepOrphans()
end

----------------------------------------------------------------------
-- Shared animation loop (one connection, 30Hz)
----------------------------------------------------------------------
function Library:_startLoop()
	local acc = 0
	self._conn = RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 1 / 30 then
			return
		end
		local step = acc
		acc = 0
		local now = os.clock()
		for fn in pairs(self._tasks) do
			fn(step, now)
		end
	end)
end

function Library:_addTask(fn)
	self._tasks[fn] = true
	return function()
		self._tasks[fn] = nil
	end
end

----------------------------------------------------------------------
-- Pixel gradient mosaic (flows toward the top-left).
-- ox/oy = the island's origin in cells, so every island samples the SAME background.
----------------------------------------------------------------------
function Library:_mosaic(container, w, h, cell, alpha, isActive, ox, oy)
	ox, oy = ox or 0, oy or 0
	local holder = create("Frame", {
		Name = "Mosaic",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
	}, container)

	local cols, rows = math.ceil(w / cell), math.ceil(h / cell)
	local cells, last, p1, p2, p3 = {}, {}, {}, {}, {}
	local n = 0
	for j = 0, rows - 1 do
		for i = 0, cols - 1 do
			n += 1
			cells[n] = create("Frame", {
				BorderSizePixel = 0,
				BackgroundColor3 = PALETTE[1],
				BackgroundTransparency = alpha,
				Position = UDim2.fromOffset(i * cell, j * cell),
				Size = UDim2.fromOffset(cell + 1, cell + 1),
			}, holder)
			last[n] = 0
			local gi, gj = i + ox, j + oy
			p1[n] = (gi + gj) * 0.26
			p2[n] = gi * 0.46 + gj * 0.15
			p3[n] = gj * 0.55 + gi * 0.08
		end
	end

	local acc = 1
	local sin, floor = math.sin, math.floor
	local function update(dt, now)
		if not isActive() then
			return
		end
		acc += dt
		if acc < 1 / 15 then
			return
		end
		acc = 0
		local a, b, c = now * 1.0, now * 0.75, now * 0.55
		for k = 1, n do
			local v = 0.5 + 0.30 * sin(p1[k] + a) + 0.20 * sin(p2[k] + b) + 0.10 * sin(p3[k] + c)
			local idx = floor(v * (PAL - 1) + 0.5) + 1
			if idx < 1 then
				idx = 1
			elseif idx > PAL then
				idx = PAL
			end
			if idx ~= last[k] then
				last[k] = idx
				cells[k].BackgroundColor3 = PALETTE[idx]
			end
		end
	end

	return self:_addTask(update)
end

----------------------------------------------------------------------
-- Settings (saved to the workspace)
----------------------------------------------------------------------
function Library:_loadSettings(config)
	local s = {
		Music = config.Music ~= false,
		Volume = math.clamp(config.MusicVolume or 30, 0, 100),
		Crossfade = math.clamp(config.CrossfadeTime or 4, 1, 10),
	}
	if isfile and readfile then
		local ok, raw = pcall(function()
			if isfile(SETTINGS_FILE) then
				return readfile(SETTINGS_FILE)
			end
		end)
		if ok and raw then
			local ok2, data = pcall(function()
				return HttpService:JSONDecode(raw)
			end)
			if ok2 and type(data) == "table" then
				if type(data.Music) == "boolean" then
					s.Music = data.Music
				end
				if type(data.Volume) == "number" then
					s.Volume = math.clamp(data.Volume, 0, 100)
				end
				if type(data.Crossfade) == "number" then
					s.Crossfade = math.clamp(data.Crossfade, 1, 10)
				end
			end
		end
	end
	return s
end

function Library:_saveSettings()
	if not writefile or self._saveQueued then
		return
	end
	self._saveQueued = true
	task.delay(0.5, function()
		self._saveQueued = false
		pcall(function()
			writefile(SETTINGS_FILE, HttpService:JSONEncode(self.Settings))
		end)
	end)
end

----------------------------------------------------------------------
-- Music: loud + underwater while loading -> low, clean, crossfading loop
----------------------------------------------------------------------
function Library:_createSound(asset)
	if self._soundA then
		return
	end
	-- A carries the underwater effects; B is a clean twin used for the crossfade loop
	local a = create("Sound", { Name = "HoodzMusic", SoundId = asset, Looped = false, Volume = 0 }, SoundService)
	self._eq = create("EqualizerSoundEffect", { LowGain = 3, MidGain = -14, HighGain = -60 }, a)
	self._chorus = create("ChorusSoundEffect", { Depth = 0.5, Mix = 0.45, Rate = 0.8 }, a)
	self._reverb = create("ReverbSoundEffect", {
		DecayTime = 2.8,
		Density = 1,
		Diffusion = 1,
		DryLevel = -2,
		WetLevel = -5,
	}, a)
	local b = create("Sound", { Name = "HoodzMusic", SoundId = asset, Looped = false, Volume = 0 }, SoundService)
	self._soundA, self._soundB, self._cur = a, b, a
end

function Library:_neutralizeFx()
	for _, fx in ipairs({ self._eq, self._chorus, self._reverb }) do
		if fx then
			fx.Enabled = false
		end
	end
end

function Library:_loadMusic()
	if self._soundA then
		return true
	end
	if self._musicLoading then
		return false
	end
	self._musicLoading = true
	local asset = resolveFile(self._musicFile, self._musicUrl, 2000)
	self._musicLoading = false
	if asset and not self._destroyed then
		self:_createSound(asset)
	end
	return self._soundA ~= nil
end

function Library:_startLoadingMusic()
	local s = self._soundA
	if not (s and self._musicOn) then
		return
	end
	s.Volume = 0
	s:Play()
	tween(s, 0.8, { Volume = LOUD })
end

function Library:_playNormal()
	local s = self._cur
	if not s then
		return
	end
	self:_neutralizeFx()
	if s.IsPaused then
		s:Resume()
	elseif not s.IsPlaying then
		s.Volume = 0
		s:Play()
	end
	tween(s, 0.8, { Volume = self.Settings.Volume / 100 })
end

-- underwater/loud -> normal/low, smoothly
function Library:_settleMusic()
	self._phase = "normal"
	local s = self._soundA
	if not s then
		return
	end
	if self._musicOn and s.IsPlaying then
		local T = 2.5
		tween(self._eq, T, { LowGain = 0, MidGain = 0, HighGain = 0 }, Enum.EasingStyle.Sine)
		tween(self._chorus, T, { Mix = 0 }, Enum.EasingStyle.Sine)
		tween(self._reverb, T, { DryLevel = 0, WetLevel = -80 }, Enum.EasingStyle.Sine)
		tween(s, T, { Volume = self.Settings.Volume / 100 }, Enum.EasingStyle.Sine).Completed:Connect(function()
			if self._phase == "normal" then
				self:_neutralizeFx()
			end
		end)
	else
		self:_neutralizeFx()
		if s.IsPlaying then
			s:Pause()
		end
	end
end

-- Smooth loop: near the end of the track, the other copy fades in from 0:00
-- while the current copy fades out, so there is never a hard restart.
function Library:_crossfade(xf)
	local cur = self._cur
	local nxt = (cur == self._soundA) and self._soundB or self._soundA
	if not (cur and nxt) then
		return
	end
	self._xfading = true
	self._xfToken += 1
	local tok = self._xfToken
	local target = self.Settings.Volume / 100
	nxt.TimePosition = 0
	nxt.Volume = 0
	nxt:Play()
	tween(nxt, xf, { Volume = target }, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	tween(cur, xf, { Volume = 0 }, Enum.EasingStyle.Sine, Enum.EasingDirection.In)
	task.delay(xf + 0.05, function()
		if self._xfToken ~= tok or self._destroyed then
			return
		end
		cur:Stop()
		self._cur = nxt
		nxt.Volume = self.Settings.Volume / 100
		self._xfading = false
	end)
end

function Library:_loopTick()
	if self._phase ~= "normal" or not self._musicOn or self._xfading then
		return
	end
	local cur = self._cur
	if not cur or cur.IsPaused or not cur.IsLoaded then
		return
	end
	if not cur.IsPlaying then
		-- ended on its own (extremely short track): just start again
		cur.TimePosition = 0
		cur:Play()
		return
	end
	local len = cur.TimeLength
	if len <= 0 then
		return
	end
	local xf = math.min(self._xfade, len / 3)
	if len - cur.TimePosition <= xf then
		self:_crossfade(xf)
	end
end

function Library:_fadeOutPause()
	self._xfToken += 1
	self._xfading = false
	local cur = self._cur
	for _, s in ipairs({ self._soundA, self._soundB }) do
		if s and s ~= cur and s.IsPlaying then
			s:Stop()
		end
	end
	if cur then
		tween(cur, 0.5, { Volume = 0 }).Completed:Connect(function()
			if not self._musicOn and cur.IsPlaying then
				cur:Pause()
			end
		end)
	end
end

function Library:_dockSync()
	if self._dockUpdate then
		self._dockUpdate()
	end
end

function Library:SetMusic(on)
	on = on and true or false
	if self._musicOn == on then
		return
	end
	self._musicOn = on
	self.Settings.Music = on
	self:_saveSettings()
	self:_dockSync()
	if self._musicToggle and self._musicToggle:Get() ~= on then
		self._musicToggle:Set(on, true)
	end

	if self._phase == "loading" then
		if self._soundA then
			if on then
				self:_startLoadingMusic()
			else
				local s = self._soundA
				tween(s, 0.4, { Volume = 0 }).Completed:Connect(function()
					if not self._musicOn then
						s:Pause()
					end
				end)
			end
		end
		return
	end

	if on then
		if self._soundA then
			self:_playNormal()
		else
			task.spawn(function()
				if self:_loadMusic() and self._musicOn then
					self:_playNormal()
				end
			end)
		end
	elseif self._soundA then
		self:_fadeOutPause()
	end
end

function Library:SetVolume(pct)
	pct = math.clamp(pct, 0, 100)
	self.Settings.Volume = pct
	self:_saveSettings()
	if self._volSlider and self._volSlider:Get() ~= pct then
		self._volSlider:Set(pct)
	end
	if self._phase == "normal" and self._musicOn and self._cur and not self._xfading then
		tween(self._cur, 0.1, { Volume = pct / 100 })
	end
end

function Library:SetCrossfade(sec)
	sec = math.clamp(sec, 1, 10)
	self._xfade = sec
	self.Settings.Crossfade = sec
	self:_saveSettings()
	if self._xfSlider and self._xfSlider:Get() ~= sec then
		self._xfSlider:Set(sec)
	end
end

----------------------------------------------------------------------
-- Single drag owner (only the grabbed slider / window ever moves)
----------------------------------------------------------------------
function Library:_beginDrag(input, update, onEnd)
	self:_endDrag()
	self._drag = { input = input, update = update, onEnd = onEnd }
end

function Library:_endDrag()
	local d = self._drag
	if d then
		self._drag = nil
		if d.onEnd then
			d.onEnd()
		end
	end
end

----------------------------------------------------------------------
-- Islands (floating rounded panels that share one background)
----------------------------------------------------------------------
function Library:_island(name, x, y, w, h, ox, oy)
	local root = self._root
	local isl = create("CanvasGroup", {
		Name = name,
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(w, h),
		BackgroundColor3 = Theme.Black,
		BorderSizePixel = 0,
		GroupTransparency = 1,
	}, root)
	corner(isl, UDim.new(0, 16))
	local _, sg = gradStroke(isl, 2, OUTLINE)
	table.insert(self._strokeGrads, sg)
	self:_mosaic(isl, w, h, CELL, 0, function()
		return root.Visible
	end, ox, oy)
	local shade = create("Frame", {
		Name = "Shade",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Black,
		BorderSizePixel = 0,
		ZIndex = 2,
	}, isl)
	create("UIGradient", {
		Rotation = 45,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.78),
			NumberSequenceKeypoint.new(1, 0.25),
		}),
	}, shade)
	local body = create("Frame", {
		Name = "Body",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 3,
	}, isl)
	table.insert(self._islands, isl)
	return isl, body
end

function Library:_fade(alpha, t, stagger)
	local last
	for i, isl in ipairs(self._islands) do
		if stagger then
			task.delay((i - 1) * stagger, function()
				if isl.Parent then
					tween(isl, t, { GroupTransparency = alpha }, Enum.EasingStyle.Quint)
				end
			end)
		else
			last = tween(isl, t, { GroupTransparency = alpha })
		end
	end
	return last
end

----------------------------------------------------------------------
-- Classes
----------------------------------------------------------------------
local Category = {}
Category.__index = Category
local Tab = {}
Tab.__index = Tab

function Library.new(config)
	config = config or {}
	cleanupPrevious()

	local self = setmetatable({}, Library)
	self._tasks = {}
	self._conns = {}
	self._islands = {}
	self._strokeGrads = {}
	self._cats = {}
	self._catMap = {}
	self._tabs = {}
	self._visible = false
	self._loaded = false
	self._destroyed = false
	self._token = 0
	self._xfToken = 0
	self._xfading = false
	self._phase = "idle"
	self._hasLogo = false
	self._musicFile = config.MusicFile or DEFAULT_MUSIC_FILE
	self._musicUrl = config.MusicUrl or DEFAULT_MUSIC_URL
	self.Settings = self:_loadSettings(config)
	self._musicOn = self.Settings.Music
	self._xfade = self.Settings.Crossfade
	ENV.__HoodzInstance = self

	local function track(c)
		table.insert(self._conns, c)
		return c
	end
	self._track = track

	self:_startLoop()

	local parent = getGuiParent()
	local name = config.Name or "Hoodz"

	-- Full-screen gui (UI + loading). ScreenInsets None = covers notches too.
	local gui = create("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 999,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, nil)
	pcall(function()
		gui.ScreenInsets = Enum.ScreenInsets.None
	end)
	-- Safe-area gui (logo button clears the notch / topbar)
	local safe = create("ScreenGui", {
		Name = name .. "Safe",
		ResetOnSpawn = false,
		DisplayOrder = 1000,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, nil)
	for _, g in ipairs({ gui, safe }) do
		pcall(function()
			if syn and syn.protect_gui then
				syn.protect_gui(g)
			end
		end)
		g.Parent = parent
	end
	self.Gui, self.SafeGui = gui, safe

	-- Root container (moves as one) ------------------------------------------
	local root = create("Frame", {
		Name = "Root",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(ROOT_W, ROOT_H),
		BackgroundTransparency = 1,
		Visible = false,
	}, gui)
	local rootScale = create("UIScale", {}, root)
	self._root, self.Main = root, root

	local headerI, hb = self:_island("Header", 0, 0, 648, 54, 0, 0)
	local railI, rb = self:_island("Rail", 0, 72, 54, 306, 0, 4)
	local tabsI, tb = self:_island("Tabs", 72, 72, 144, 306, 4, 4)
	local mainI, mb = self:_island("Main", 234, 72, 414, 306, 13, 4)
	local dockI, db = self:_island("Dock", 0, 396, 648, 36, 0, 22)
	self.Islands = { headerI, railI, tabsI, mainI, dockI }

	-- Header: title, breadcrumb, close ------------------------------------------
	local titleRow = create("Frame", {
		Position = UDim2.fromOffset(18, 0),
		Size = UDim2.new(0, 220, 1, 0),
		BackgroundTransparency = 1,
	}, hb)
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 9),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, titleRow)
	local accent = create("Frame", {
		Size = UDim2.fromOffset(4, 22),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		LayoutOrder = 0,
	}, titleRow)
	corner(accent, UDim.new(1, 0))
	grad(accent, LIGHTGRAD, 90)
	local title = label(titleRow, config.Title or "Hoodz", 22, WHITE, nil, true)
	title.AutomaticSize = Enum.AutomaticSize.X
	title.Size = UDim2.fromOffset(0, 26)
	title.TextTruncate = Enum.TextTruncate.None
	title.LayoutOrder = 1
	grad(title, TEXTGRAD, 0)
	local chip = create("Frame", {
		Size = UDim2.fromOffset(40, 18),
		BackgroundColor3 = Color3.fromRGB(60, 22, 30),
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		LayoutOrder = 2,
	}, titleRow)
	corner(chip, UDim.new(1, 0))
	solidStroke(chip, 1, Theme.Light, 0.6)
	local chipText = label(chip, config.Subtitle or ("v" .. Library.Version), 11, Theme.Light, Enum.TextXAlignment.Center, true)
	chipText.Size = UDim2.fromScale(1, 1)

	local crumb = label(hb, "", 13, Theme.Dim, Enum.TextXAlignment.Center)
	crumb.AnchorPoint = Vector2.new(0.5, 0.5)
	crumb.Position = UDim2.new(0.5, 40, 0.5, 0)
	crumb.Size = UDim2.fromOffset(230, 20)
	self._crumb = crumb

	local close = create("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		Size = UDim2.fromOffset(30, 30),
		BackgroundColor3 = Theme.Row,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		Text = "×",
		Font = Theme.Bold,
		TextSize = 24,
		TextColor3 = Theme.Light,
		AutoButtonColor = false,
	}, hb)
	corner(close, UDim.new(1, 0))
	close.MouseEnter:Connect(function()
		tween(close, 0.15, { BackgroundColor3 = Theme.RedDark })
	end)
	close.MouseLeave:Connect(function()
		tween(close, 0.15, { BackgroundColor3 = Theme.Row })
	end)

	local shimmer = create("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 2),
		BackgroundColor3 = Theme.Light,
		BorderSizePixel = 0,
	}, hb)
	local shimmerGrad = create("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.05),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}, shimmer)

	-- Rail: category circles ---------------------------------------------------
	local rail = create("ScrollingFrame", {
		Name = "Rail",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 0,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
	}, rb)
	create("UIListLayout", {
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
	}, rail)
	create("UIPadding", { PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10) }, rail)
	self._rail = rail

	-- Tabs island: category title + the active category's tab list ----------------
	local catTitle = label(tb, "", 12, Theme.Light, nil, true)
	catTitle.Position = UDim2.fromOffset(26, 0)
	catTitle.Size = UDim2.new(1, -34, 0, 36)
	self._catTitle = catTitle
	local catDot = create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(14, 18),
		Size = UDim2.fromOffset(6, 6),
		BackgroundColor3 = Theme.Light,
		BorderSizePixel = 0,
	}, tb)
	corner(catDot, UDim.new(1, 0))
	create("Frame", {
		Position = UDim2.fromOffset(12, 36),
		Size = UDim2.new(1, -24, 0, 1),
		BackgroundColor3 = Theme.Stroke,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
	}, tb)
	self._tabsHost = create("Frame", {
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.new(1, 0, 1, -40),
		BackgroundTransparency = 1,
	}, tb)

	-- Main island: page title + tile grid host -------------------------------------
	local pageTitle = label(mb, "", 17, WHITE, nil, true)
	pageTitle.Position = UDim2.fromOffset(18, 0)
	pageTitle.Size = UDim2.new(1, -36, 0, 40)
	grad(pageTitle, TEXTGRAD, 0)
	self._pageTitle = pageTitle
	create("Frame", {
		Position = UDim2.fromOffset(14, 40),
		Size = UDim2.new(1, -28, 0, 1),
		BackgroundColor3 = Theme.Stroke,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
	}, mb)
	self.Content = create("Frame", {
		Name = "Pages",
		Position = UDim2.fromOffset(0, 44),
		Size = UDim2.new(1, 0, 1, -44),
		BackgroundTransparency = 1,
	}, mb)

	-- glass sheen on the main island
	local sheen = create("Frame", {
		Name = "Sheen",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ZIndex = 10,
	}, mainI)
	local sheenGrad = create("UIGradient", {
		Rotation = 25,
		Offset = Vector2.new(2, 0),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.4, 1),
			NumberSequenceKeypoint.new(0.5, 0.93),
			NumberSequenceKeypoint.new(0.6, 1),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}, sheen)

	-- Dock: quick music switch + hints -------------------------------------------
	local musicBtn = create("TextButton", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		Size = UDim2.fromOffset(116, 24),
		BackgroundColor3 = Color3.fromRGB(60, 22, 30),
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
	}, db)
	corner(musicBtn, UDim.new(1, 0))
	solidStroke(musicBtn, 1, Theme.Light, 0.6)
	local musicDot = create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		Size = UDim2.fromOffset(8, 8),
		BackgroundColor3 = Theme.Light,
		BorderSizePixel = 0,
	}, musicBtn)
	corner(musicDot, UDim.new(1, 0))
	local musicLbl = label(musicBtn, "", 11, Theme.Light, nil, true)
	musicLbl.Position = UDim2.fromOffset(26, 0)
	musicLbl.Size = UDim2.new(1, -30, 1, 0)
	self._dockUpdate = function()
		musicDot.BackgroundColor3 = self._musicOn and Theme.Light or Theme.Off
		musicLbl.Text = "Music  " .. (self._musicOn and "ON" or "OFF")
	end
	self._dockUpdate()
	track(musicBtn.Activated:Connect(function()
		if self._loaded then
			self:SetMusic(not self._musicOn)
		end
	end))
	local hint = label(db, "Drag the top bar  •  RightShift or the logo = hide", 11, Theme.Dim, Enum.TextXAlignment.Center)
	hint.AnchorPoint = Vector2.new(0.5, 0.5)
	hint.Position = UDim2.fromScale(0.5, 0.5)
	hint.Size = UDim2.fromOffset(320, 18)
	local verLbl = label(db, "Hoodz v" .. Library.Version, 11, Theme.Dim, Enum.TextXAlignment.Right)
	verLbl.AnchorPoint = Vector2.new(1, 0.5)
	verLbl.Position = UDim2.new(1, -14, 0.5, 0)
	verLbl.Size = UDim2.fromOffset(120, 18)

	-- Responsive scale -------------------------------------------------------
	local badgeScale
	local function rescale()
		local cam = workspace.CurrentCamera
		if not cam then
			return
		end
		local vp = cam.ViewportSize
		rootScale.Scale = math.clamp(math.min(vp.X / (ROOT_W + 36), vp.Y / (ROOT_H + 36)), 0.5, 1.15)
		if badgeScale then
			badgeScale.Scale = math.clamp(math.min(vp.X / 900, vp.Y / 500), 0.75, 1)
		end
	end
	rescale()
	track(workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(rescale))
	if workspace.CurrentCamera then
		track(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale))
	end

	-- Global drag controller: ONE owner at a time, always released on input end -----
	track(UserInputService.InputChanged:Connect(function(input)
		local d = self._drag
		if not d then
			return
		end
		local st = d.input.UserInputState
		if st == Enum.UserInputState.End or st == Enum.UserInputState.Cancel then
			self:_endDrag()
			return
		end
		if isMove(input) then
			d.update(input)
		end
	end))
	track(UserInputService.InputEnded:Connect(function(input)
		local d = self._drag
		if d and (input == d.input or input.UserInputType == d.input.UserInputType) then
			self:_endDrag()
		end
	end))

	-- Move everything by dragging the header
	track(hb.InputBegan:Connect(function(input)
		if isPointer(input) then
			local startPos, startInput = root.Position, input.Position
			self:_beginDrag(input, function(i)
				local cam = workspace.CurrentCamera
				local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
				local d = i.Position - startInput
				root.Position = UDim2.fromScale(
					math.clamp(startPos.X.Scale + d.X / vp.X, 0.05, 0.95),
					math.clamp(startPos.Y.Scale + d.Y / vp.Y, 0.05, 0.95)
				)
			end)
		end
	end))

	-- Logo = the show/hide button (top-left, safe area) --------------------------------
	local badge = create("ImageButton", {
		Name = "Logo",
		Position = UDim2.fromOffset(12, 12),
		Size = UDim2.fromOffset(64, 64),
		BackgroundColor3 = Theme.Red,
		BackgroundTransparency = 1,
		Image = "",
		ImageTransparency = 1,
		ScaleType = Enum.ScaleType.Crop,
		AutoButtonColor = false,
		Visible = false,
	}, safe)
	corner(badge, UDim.new(0, 16))
	local badgeStroke, badgeGrad = gradStroke(badge, 2.5, OUTLINE)
	badgeStroke.Transparency = 1
	badgeScale = create("UIScale", {}, badge)
	local letter = label(badge, "H", 30, WHITE, Enum.TextXAlignment.Center, true)
	letter.Size = UDim2.fromScale(1, 1)
	letter.TextTransparency = 1
	letter.Visible = false
	self.Badge, self.BadgeStroke, self._badgeLetter = badge, badgeStroke, letter
	rescale()

	track(badge.Activated:Connect(function()
		if not self._loaded then
			return
		end
		self:Toggle()
		badgeStroke.Thickness = 5
		tween(badgeStroke, 0.25, { Thickness = 2.5 })
	end))

	-- shared loop: outlines, shimmer, sheen, underwater wobble, music loop ---------------
	self:_addTask(function(_, now)
		if root.Visible then
			local rot = (now * 60) % 360
			for _, g in ipairs(self._strokeGrads) do
				g.Rotation = rot
			end
			shimmerGrad.Offset = Vector2.new(((now * 0.45) % 2) - 1, 0)
			local ph = (now % 8) / 8
			sheenGrad.Offset = Vector2.new(ph < 0.3 and (-1 + ph / 0.3 * 2) or 2, 0)
		end
		if badge.Visible then
			badgeGrad.Rotation = (now * 90) % 360
		end
		if self._phase == "loading" and self._eq and self._eq.Enabled then
			self._eq.HighGain = -55 - 12 * (0.5 + 0.5 * math.sin(now * 0.9))
		end
		self:_loopTick()
	end)

	track(close.Activated:Connect(function()
		self:SetVisible(false)
	end))
	local key = config.ToggleKey or Enum.KeyCode.RightShift
	track(UserInputService.InputBegan:Connect(function(input, gp)
		if not gp and input.KeyCode == key then
			self:Toggle()
		end
	end))

	task.spawn(function()
		self:_runLoading(config)
	end)

	return self
end

----------------------------------------------------------------------
-- Show / hide (smooth)
----------------------------------------------------------------------
function Library:_badgeTo(alpha, t)
	local b = self.Badge
	if self._hasLogo then
		tween(b, t, { ImageTransparency = alpha })
	else
		tween(b, t, { BackgroundTransparency = alpha })
		tween(self._badgeLetter, t, { TextTransparency = alpha })
	end
end

function Library:SetVisible(v)
	if not self._loaded or self._destroyed then
		return
	end
	self._visible = v
	self._token += 1
	self:_endDrag()
	local tok = self._token
	local root = self._root
	if v then
		root.Visible = true
		self:_fade(0, 0.3)
	else
		local last = self:_fade(1, 0.22)
		if last then
			last.Completed:Connect(function()
				if self._token == tok then
					root.Visible = false
				end
			end)
		end
	end
	self:_badgeTo(v and 0 or 0.45, 0.25)
end

function Library:Toggle()
	self:SetVisible(not self._visible)
end

function Library:IsLoaded()
	return self._loaded
end

function Library:WaitUntilLoaded(timeout)
	local t0 = os.clock()
	while not self._loaded and not self._destroyed and os.clock() - t0 < (timeout or 30) do
		task.wait(0.1)
	end
	return self._loaded
end

----------------------------------------------------------------------
-- Built-in Settings category (always last on the rail)
----------------------------------------------------------------------
function Library:_buildSettings()
	local div = create("Frame", {
		Size = UDim2.fromOffset(24, 2),
		BackgroundColor3 = Theme.Stroke,
		BorderSizePixel = 0,
		LayoutOrder = 999999,
	}, self._rail)
	corner(div, UDim.new(1, 0))

	local cat = self:CreateCategory("Hoodz")
	cat.Btn.LayoutOrder = 1000000
	local tab = cat:CreateTab("Settings")
	tab:CreateSection("Audio")
	self._musicToggle = tab:CreateToggle({
		Name = "Background music",
		Default = self.Settings.Music,
		NoInit = true,
		Callback = function(on)
			self:SetMusic(on)
		end,
	})
	self._volSlider = tab:CreateSlider({
		Name = "Music volume",
		Min = 0,
		Max = 100,
		Default = self.Settings.Volume,
		Increment = 1,
		NoInit = true,
		Callback = function(v)
			self:SetVolume(v)
		end,
	})
	self._xfSlider = tab:CreateSlider({
		Name = "Loop crossfade (seconds)",
		Min = 1,
		Max = 10,
		Default = self.Settings.Crossfade,
		Increment = 1,
		NoInit = true,
		Callback = function(v)
			self:SetCrossfade(v)
		end,
	})
	tab:CreateSection("Interface")
	tab:CreateLabel("RightShift or the logo = show / hide")
	tab:CreateButton({
		Name = "Unload UI",
		Callback = function()
			self:Destroy()
		end,
	})
	self.SettingsTab = tab
end

----------------------------------------------------------------------
-- Loading screen (full screen, transparent) -> assemble the islands
----------------------------------------------------------------------
function Library:_runLoading(config)
	local gui = self.Gui
	local vp = gui.AbsoluteSize
	if vp.X < 10 or vp.Y < 10 then
		local cam = workspace.CurrentCamera
		vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
	end

	local grp = create("CanvasGroup", {
		Name = "Loading",
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromScale(0, 0),
		BackgroundColor3 = Theme.Black,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		ZIndex = 50,
	}, gui)

	local active = true
	local cell = math.max(18, math.floor(math.sqrt(vp.X * vp.Y / 650) / 2 + 0.5) * 2)
	local removeMosaic = self:_mosaic(grp, vp.X, vp.Y, cell, 0.5, function()
		return active
	end)

	local card = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(320, 120),
		BackgroundTransparency = 1,
		ZIndex = 5,
	}, grp)
	local title = label(card, string.upper(config.Title or "Hoodz"), 46, WHITE, Enum.TextXAlignment.Center, true)
	title.Size = UDim2.new(1, 0, 0, 56)
	grad(title, TEXTGRAD, 0)
	local barBg = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 70),
		Size = UDim2.fromOffset(260, 8),
		BackgroundColor3 = Theme.Black,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
	}, card)
	corner(barBg, UDim.new(1, 0))
	solidStroke(barBg, 1, Theme.Stroke, 0.3)
	local fill = create("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
	}, barBg)
	corner(fill, UDim.new(1, 0))
	grad(fill, LIGHTGRAD, 0)
	local status = label(card, "", 13, Theme.Dim, Enum.TextXAlignment.Center)
	status.Position = UDim2.fromOffset(0, 88)
	status.Size = UDim2.new(1, 0, 0, 20)

	-- assets download in parallel (logo + music), cached after the first run
	self._phase = "loading"
	local logoDone, logoAsset = false, nil
	task.spawn(function()
		logoAsset = resolveFile(config.Image or DEFAULT_LOGO_FILE, config.ImageUrl or DEFAULT_LOGO_URL, 200)
		logoDone = true
	end)
	local musicDone = not self._musicOn
	if self._musicOn then
		task.spawn(function()
			self:_loadMusic()
			if self._soundA and not self._destroyed then
				if self._phase == "loading" then
					self:_startLoadingMusic() -- loud + underwater
				elseif self._musicOn then
					self:_playNormal()
				end
			end
			musicDone = true
		end)
	end

	local q = (config.LoadingTime or 2.5) / 4
	for i, text in ipairs({ "Starting up", "Loading assets", "Building interface" }) do
		status.Text = text
		tween(fill, q, { Size = UDim2.fromScale(i / 4, 1) }, Enum.EasingStyle.Sine)
		task.wait(q)
		if self._destroyed then
			return
		end
	end
	if not (logoDone and musicDone) then
		status.Text = "Downloading assets"
	end
	local t0 = os.clock()
	while not (logoDone and musicDone) and os.clock() - t0 < 10 do
		task.wait(0.05)
		if self._destroyed then
			return
		end
	end
	status.Text = "Ready"
	tween(fill, 0.3, { Size = UDim2.fromScale(1, 1) })
	task.wait(0.35)
	if self._destroyed then
		return
	end

	local badge = self.Badge
	if logoAsset then
		badge.Image = logoAsset
		self._hasLogo = true
	else
		badge.BackgroundColor3 = Theme.Red
		self._badgeLetter.Visible = true
	end

	self:_buildSettings()
	self._loaded = true
	self._visible = true

	-- assemble: the islands rise and fade in one after another, loading fades out,
	-- and the song settles from loud/underwater to low/clean
	local root = self._root
	root.Position = UDim2.fromScale(0.5, 0.56)
	root.Visible = true
	tween(root, 0.9, { Position = UDim2.fromScale(0.5, 0.5) }, Enum.EasingStyle.Quint)
	self:_fade(0, 0.7, 0.07)
	self:_settleMusic()
	task.delay(0.5, function()
		if badge.Parent and not self._destroyed then
			badge.Visible = true
			tween(self.BadgeStroke, 0.8, { Transparency = 0 })
			self:_badgeTo(self._visible and 0 or 0.45, 0.8)
		end
	end)
	tween(grp, 0.7, { GroupTransparency = 1 }, Enum.EasingStyle.Sine).Completed:Wait()
	active = false
	removeMosaic()
	grp:Destroy()
end

function Library:Destroy()
	if self._destroyed then
		return
	end
	self._destroyed = true
	self:_endDrag()
	if ENV.__HoodzInstance == self then
		ENV.__HoodzInstance = nil
	end
	if self._conn then
		self._conn:Disconnect()
	end
	for _, c in ipairs(self._conns) do
		c:Disconnect()
	end
	self._tasks = {}
	for _, s in ipairs({ self._soundA, self._soundB }) do
		if s then
			s:Destroy()
		end
	end
	self.Gui:Destroy()
	self.SafeGui:Destroy()
end

----------------------------------------------------------------------
-- Categories (rail circles) & tabs
----------------------------------------------------------------------
function Library:CreateCategory(name)
	local order = #self._cats + 1
	local btn = create("TextButton", {
		Name = name,
		Size = UDim2.fromOffset(40, 40),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		LayoutOrder = order,
	}, self._rail)
	local base = create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Row,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
	}, btn)
	local c1 = corner(base, UDim.new(1, 0))
	local stroke = solidStroke(base, 1.5, Theme.Stroke, 0.2)
	local on = create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, btn)
	local c2 = corner(on, UDim.new(1, 0))
	grad(on, REDGRAD, 45)
	local letter = label(btn, string.upper(string.sub(name, 1, 1)), 18, Theme.Dim, Enum.TextXAlignment.Center, true)
	letter.Size = UDim2.fromScale(1, 1)
	letter.ZIndex = 2

	local list = create("ScrollingFrame", {
		Name = name,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 2,
		ScrollBarImageColor3 = Theme.Light,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Visible = false,
	}, self._tabsHost)
	create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	create("UIPadding", {
		PaddingTop = UDim.new(0, 8),
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
		PaddingBottom = UDim.new(0, 8),
	}, list)

	local cat = setmetatable({
		Window = self,
		Name = name,
		List = list,
		Btn = btn,
		On = on,
		Letter = letter,
		Stroke = stroke,
		C1 = c1,
		C2 = c2,
		Tabs = {},
		_n = 0,
	}, Category)
	table.insert(self._cats, cat)
	self._catMap[name] = cat
	self._track(btn.Activated:Connect(function()
		self:_selectCategory(cat)
	end))
	return cat
end

function Library:CreateTab(name, categoryName)
	categoryName = categoryName or "General"
	local cat = self._catMap[categoryName] or self:CreateCategory(categoryName)
	return cat:CreateTab(name)
end

function Library:_selectCategory(cat, skipTab)
	self._activeCat = cat
	self._catTitle.Text = string.upper(cat.Name)
	for _, c in ipairs(self._cats) do
		local on = c == cat
		c.List.Visible = on
		tween(c.On, 0.2, { BackgroundTransparency = on and 0 or 1 })
		tween(c.Letter, 0.2, { TextColor3 = on and WHITE or Theme.Dim })
		tween(c.Stroke, 0.2, { Color = on and Theme.Light or Theme.Stroke })
		local r = on and UDim.new(0, 14) or UDim.new(1, 0) -- circle morphs into a rounded square
		tween(c.C1, 0.25, { CornerRadius = r })
		tween(c.C2, 0.25, { CornerRadius = r })
	end
	if skipTab then
		return
	end
	local tab = cat.Current or cat.Tabs[1]
	if tab then
		self:_select(tab)
	else
		for _, t in ipairs(self._tabs) do
			t.Page.Visible = false
		end
		self._pageTitle.Text = ""
		self._crumb.Text = cat.Name
	end
end

function Library:_select(tab)
	local cat = tab.Category
	cat.Current = tab
	if self._activeCat ~= cat then
		self:_selectCategory(cat, true)
	end
	self._pageTitle.Text = tab.Name
	self._crumb.Text = cat.Name .. "  /  " .. tab.Name
	for _, t in ipairs(self._tabs) do
		local on = t == tab
		t.Page.Visible = on
		tween(t.Bg, 0.18, { BackgroundTransparency = on and 0.05 or 1 })
		tween(t.Bar, 0.2, { Size = UDim2.fromOffset(3, on and 14 or 0) })
		tween(t.Text, 0.2, {
			TextColor3 = on and WHITE or Theme.Dim,
			Position = UDim2.fromOffset(on and 20 or 14, 0),
		})
	end
end

function Category:CreateTab(name)
	local lib = self.Window
	self._n += 1
	local btn = create("TextButton", {
		Name = name,
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		LayoutOrder = self._n,
	}, self.List)
	local bg = create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, btn)
	corner(bg, UDim.new(0, 10))
	grad(bg, REDGRAD, 0)
	local bar = create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 7, 0.5, 0),
		Size = UDim2.fromOffset(3, 0),
		BackgroundColor3 = Theme.Light,
		BorderSizePixel = 0,
		ZIndex = 2,
	}, btn)
	corner(bar, UDim.new(1, 0))
	local txt = label(btn, name, 14, Theme.Dim)
	txt.Position = UDim2.fromOffset(14, 0)
	txt.Size = UDim2.new(1, -20, 1, 0)
	txt.ZIndex = 2

	local page = create("ScrollingFrame", {
		Name = name,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = Theme.Light,
		ScrollBarImageTransparency = 0.3,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Visible = false,
	}, lib.Content)
	create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, page)
	create("UIPadding", {
		PaddingTop = UDim.new(0, 10),
		PaddingLeft = UDim.new(0, 14),
		PaddingRight = UDim.new(0, 16),
		PaddingBottom = UDim.new(0, 10),
	}, page)

	local tab = setmetatable({
		Window = lib,
		Category = self,
		Page = page,
		Button = btn,
		Bg = bg,
		Bar = bar,
		Text = txt,
		Name = name,
		_order = 0,
	}, Tab)
	table.insert(self.Tabs, tab)
	table.insert(lib._tabs, tab)
	lib._track(btn.Activated:Connect(function()
		lib:_select(tab)
	end))
	if #lib._tabs == 1 then
		lib:_select(tab)
	end
	return tab
end

----------------------------------------------------------------------
-- Components (tile grid)
----------------------------------------------------------------------
local ROW_ALPHA = 0.25

-- full-width row
local function row(tab, height)
	tab._pair = nil
	tab._order += 1
	local r = create("Frame", {
		Size = UDim2.new(1, 0, 0, height),
		BackgroundColor3 = Theme.Row,
		BackgroundTransparency = ROW_ALPHA,
		BorderSizePixel = 0,
		LayoutOrder = tab._order,
	}, tab.Page)
	corner(r, UDim.new(0, 14))
	solidStroke(r, 1, Theme.Stroke, 0.5)
	return r
end

-- tiles of the same kind pair up two per row (a lone tile stays full width until its partner arrives)
local function cellFor(tab, kind, height)
	local p = tab._pair
	if p and p.kind == kind and p.slots == 1 then
		p.slots = 2
		tween(p.left, 0.2, { Size = UDim2.new(0.5, -4, 1, 0) })
		p.right.Visible = true
		return p.right
	end
	tab._order += 1
	local rowF = create("Frame", {
		Size = UDim2.new(1, 0, 0, height),
		BackgroundTransparency = 1,
		LayoutOrder = tab._order,
	}, tab.Page)
	local left = create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, rowF)
	local right = create("Frame", {
		Position = UDim2.new(0.5, 4, 0, 0),
		Size = UDim2.new(0.5, -4, 1, 0),
		BackgroundTransparency = 1,
		Visible = false,
	}, rowF)
	tab._pair = { kind = kind, slots = 1, left = left, right = right }
	return left
end

local function hoverable(r, target)
	target.MouseEnter:Connect(function()
		tween(r, 0.15, { BackgroundTransparency = 0.05 })
	end)
	target.MouseLeave:Connect(function()
		tween(r, 0.15, { BackgroundTransparency = ROW_ALPHA })
	end)
end

function Tab:CreateSection(text)
	self._pair = nil
	self._order += 1
	local l = label(self.Page, string.upper(text), 11, Theme.Light, nil, true)
	l.Size = UDim2.new(1, 0, 0, 18)
	l.LayoutOrder = self._order
	create("UIPadding", { PaddingLeft = UDim.new(0, 16) }, l)
	local dot = create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 4, 0.5, 0),
		Size = UDim2.fromOffset(6, 6),
		BackgroundColor3 = Theme.Light,
		BorderSizePixel = 0,
	}, l)
	corner(dot, UDim.new(1, 0))
end

function Tab:CreateLabel(text)
	local r = row(self, 30)
	local l = label(r, text, 13, Theme.Dim)
	l.Position = UDim2.fromOffset(14, 0)
	l.Size = UDim2.new(1, -28, 1, 0)
	return {
		Set = function(_, t)
			l.Text = t
		end,
	}
end

function Tab:CreateButton(opts)
	local slot = cellFor(self, "button", 44)
	local b = create("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
	}, slot)
	local bg = create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
	}, b)
	corner(bg, UDim.new(0, 14))
	grad(bg, REDGRAD, 20)
	local txt = label(b, opts.Name or "Button", 14, WHITE, Enum.TextXAlignment.Center, true)
	txt.Size = UDim2.fromScale(1, 1)
	txt.ZIndex = 2
	b.MouseEnter:Connect(function()
		tween(bg, 0.15, { BackgroundTransparency = 0.12 })
	end)
	b.MouseLeave:Connect(function()
		tween(bg, 0.15, { BackgroundTransparency = 0 })
	end)
	self.Window._track(b.Activated:Connect(function()
		bg.BackgroundTransparency = 0.45
		tween(bg, 0.25, { BackgroundTransparency = 0 })
		if opts.Callback then
			task.spawn(opts.Callback)
		end
	end))
end

function Tab:CreateToggle(opts)
	local state = opts.Default == true
	local slot = cellFor(self, "toggle", 72)

	local tile = create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Row,
		BackgroundTransparency = ROW_ALPHA,
		BorderSizePixel = 0,
	}, slot)
	corner(tile, UDim.new(0, 14))
	solidStroke(tile, 1, Theme.Stroke, 0.5)
	-- the whole tile glows red when ON
	local glow = create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, tile)
	corner(glow, UDim.new(0, 14))
	grad(glow, REDGRAD, 35)

	local nameLbl = label(tile, opts.Name or "Toggle", 14, Theme.Text, nil, true)
	nameLbl.Position = UDim2.fromOffset(14, 10)
	nameLbl.Size = UDim2.new(1, -28, 0, 20)
	nameLbl.ZIndex = 2
	local stateLbl = label(tile, "OFF", 11, Theme.Dim, nil, true)
	stateLbl.Position = UDim2.new(0, 14, 1, -28)
	stateLbl.Size = UDim2.fromOffset(60, 18)
	stateLbl.ZIndex = 2

	local sw = create("Frame", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -12, 1, -10),
		Size = UDim2.fromOffset(42, 22),
		BackgroundColor3 = Theme.Off,
		BorderSizePixel = 0,
		ZIndex = 2,
	}, tile)
	corner(sw, UDim.new(1, 0))
	local onFill = create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, sw)
	corner(onFill, UDim.new(1, 0))
	grad(onFill, LIGHTGRAD, 0)
	local knob = create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 3, 0.5, 0),
		Size = UDim2.fromOffset(16, 16),
		BackgroundColor3 = Theme.Text,
		BorderSizePixel = 0,
		ZIndex = 3,
	}, sw)
	corner(knob, UDim.new(1, 0))

	local function render(animate)
		local pos = UDim2.new(0, state and 23 or 3, 0.5, 0)
		stateLbl.Text = state and "ON" or "OFF"
		if animate then
			tween(glow, 0.2, { BackgroundTransparency = state and 0.5 or 1 })
			tween(onFill, 0.18, { BackgroundTransparency = state and 0 or 1 })
			tween(stateLbl, 0.18, { TextColor3 = state and Theme.Light or Theme.Dim })
			tween(knob, 0.18, { Position = pos }, Enum.EasingStyle.Back)
		else
			glow.BackgroundTransparency = state and 0.5 or 1
			onFill.BackgroundTransparency = state and 0 or 1
			stateLbl.TextColor3 = state and Theme.Light or Theme.Dim
			knob.Position = pos
		end
	end
	render(false)

	local obj = {}
	function obj:Set(v, silent)
		state = v and true or false
		render(true)
		if not silent and opts.Callback then
			task.spawn(opts.Callback, state)
		end
	end
	function obj:Get()
		return state
	end

	local hit = create("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		ZIndex = 5,
	}, tile)
	hoverable(tile, hit)
	self.Window._track(hit.Activated:Connect(function()
		obj:Set(not state)
	end))

	if opts.Default and opts.Callback and not opts.NoInit then
		task.spawn(opts.Callback, state)
	end
	return obj
end

function Tab:CreateSlider(opts)
	local lib = self.Window
	local min, max, inc = opts.Min or 0, opts.Max or 100, opts.Increment or 1
	local value = math.clamp(opts.Default or min, min, max)
	local r = row(self, 64)
	hoverable(r, r)

	local l = label(r, opts.Name or "Slider", 14, Theme.Text, nil, true)
	l.Position = UDim2.fromOffset(14, 9)
	l.Size = UDim2.new(1, -90, 0, 20)

	local chip = create("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 8),
		Size = UDim2.fromOffset(58, 22),
		BackgroundColor3 = Color3.fromRGB(60, 22, 30),
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
	}, r)
	corner(chip, UDim.new(1, 0))
	solidStroke(chip, 1, Theme.Light, 0.6)
	local valLbl = label(chip, "", 12, Theme.Light, Enum.TextXAlignment.Center, true)
	valLbl.Size = UDim2.fromScale(1, 1)

	-- Active = true so touching the slider never starts a page scroll
	local hit = create("Frame", {
		Position = UDim2.new(0, 16, 0, 34),
		Size = UDim2.new(1, -32, 0, 24),
		BackgroundTransparency = 1,
		Active = true,
	}, r)
	local track = create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(1, 0, 0, 10),
		BackgroundColor3 = Theme.Off,
		BorderSizePixel = 0,
	}, hit)
	corner(track, UDim.new(1, 0))
	local fill = create("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
	}, track)
	corner(fill, UDim.new(1, 0))
	grad(fill, LIGHTGRAD, 0)
	local thumb = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(18, 18),
		BackgroundColor3 = Color3.fromRGB(255, 236, 238),
		BorderSizePixel = 0,
		ZIndex = 3,
	}, track)
	corner(thumb, UDim.new(1, 0))
	solidStroke(thumb, 2.5, Theme.LightDeep, 0)

	local function apply(v, silent)
		v = math.clamp(math.floor((v - min) / inc + 0.5) * inc + min, min, max)
		v = tonumber(string.format("%.6g", v))
		local changed = v ~= value
		value = v
		local a = (v - min) / math.max(max - min, 1e-9)
		fill.Size = UDim2.fromScale(a, 1)
		thumb.Position = UDim2.fromScale(a, 0.5)
		valLbl.Text = tostring(v)
		if changed and not silent and opts.Callback then
			task.spawn(opts.Callback, v)
		end
	end
	apply(value, true)

	local function fromInput(input)
		local a = math.clamp((input.Position.X - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
		apply(min + a * (max - min))
	end

	local page = self.Page
	lib._track(hit.InputBegan:Connect(function(input)
		if isPointer(input) then
			page.ScrollingEnabled = false
			tween(thumb, 0.12, { Size = UDim2.fromOffset(24, 24) })
			fromInput(input)
			-- only this slider owns the drag; releasing ALWAYS ends it
			lib:_beginDrag(input, fromInput, function()
				page.ScrollingEnabled = true
				tween(thumb, 0.15, { Size = UDim2.fromOffset(18, 18) })
			end)
		end
	end))

	if opts.Callback and not opts.NoInit then
		task.spawn(opts.Callback, value)
	end
	return {
		Set = function(_, v)
			apply(v)
		end,
		Get = function()
			return value
		end,
	}
end

----------------------------------------------------------------------
-- Loading the library again reloads it: the old UI + music are replaced
----------------------------------------------------------------------
if ENV.__HoodzInstance then
	print("[Hoodz] v" .. Library.Version .. " loaded again - replacing the previous instance with the new code")
end
cleanupPrevious()

return Library
