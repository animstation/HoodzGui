--[[
	Hoodz UI Library  (open source)  v1.1

	* Full-bleed pixelated red/black gradient background that flows toward the top-left
	* Full-screen transparent loading screen with a smooth crossfade into the window
	* Logo badge (top-left) with rounded corners + animated gradient outline.
	  The logo is auto-downloaded from your GitHub repo the first time and cached in the workspace folder.
	* Rounded everything: window, panels, tabs, rows, toggles, sliders, buttons
	* Categories, tabs, sections, toggles, sliders, buttons, labels
	* Draggable (mouse + touch), auto-scales on phones / tablets / PC
	* RightShift or the round "H" button shows / hides the UI

	Usage:
		local Hoodz = loadstring(game:HttpGet("<raw url>"))()
		local UI = Hoodz.new({ Title = "Hoodz" })
		local tab = UI:CreateCategory("Player"):CreateTab("Movement")
		tab:CreateToggle({ Name = "Speed", Callback = function(on) end })
		tab:CreateSlider({ Name = "Walk Speed", Min = 16, Max = 100, Default = 16, Callback = function(v) end })
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Library = {}
Library.__index = Library
Library.Version = "1.1"

local DEFAULT_LOGO_URL = "https://raw.githubusercontent.com/animstation/HoodzGui/refs/heads/main/IMG_3411.jpeg"

----------------------------------------------------------------------
-- Theme
----------------------------------------------------------------------
local Theme = {
	Black = Color3.fromRGB(8, 5, 7),
	Row = Color3.fromRGB(22, 13, 16),
	Stroke = Color3.fromRGB(78, 24, 32),
	Red = Color3.fromRGB(255, 72, 84),
	RedDark = Color3.fromRGB(150, 14, 30),
	Light = Color3.fromRGB(255, 150, 158), -- light red (sliders / accents)
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

-- palette for the pixel gradient (black -> deep red -> bright red)
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

-- Uses the local file if it exists, otherwise downloads it once from the repo and caches it.
local function resolveImage(file, url)
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
		if ok and type(data) == "string" and #data > 200 and data:sub(1, 3) ~= "404" then
			pcall(writefile, file, data)
		end
	end
	if exists() then
		local ok, asset = pcall(getcustomasset, file)
		if ok and asset then
			return asset
		end
	end
	return nil
end

----------------------------------------------------------------------
-- Shared animation loop (one connection for everything, 30Hz)
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
-- Pixel gradient mosaic: a grid of cells coloured by a drifting plasma.
-- Every wave has positive coefficients + time, so the whole pattern flows toward the TOP-LEFT.
-- Cells only get a property write when their palette colour actually changes.
----------------------------------------------------------------------
function Library:_mosaic(container, w, h, cell, alpha, isActive)
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
				Size = UDim2.fromOffset(cell + 1, cell + 1), -- +1 hides seams when scaled
			}, holder)
			last[n] = 0
			p1[n] = (i + j) * 0.26
			p2[n] = i * 0.46 + j * 0.15
			p3[n] = j * 0.55 + i * 0.08
		end
	end

	local acc = 1 -- force a first paint
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
-- Classes
----------------------------------------------------------------------
local Category = {}
Category.__index = Category
local Tab = {}
Tab.__index = Tab

local WIN_W, WIN_H = 580, 370

function Library.new(config)
	config = config or {}
	local self = setmetatable({}, Library)
	self._tasks = {}
	self._conns = {}
	self._visible = false
	self._loaded = false
	self._token = 0
	self._catMap = {}
	self._catCount = 0
	self._tabs = {}

	local function track(c)
		table.insert(self._conns, c)
		return c
	end
	self._track = track

	self:_startLoop()

	local parent = getGuiParent()
	local name = config.Name or "Hoodz"

	-- Full-screen gui (window + loading). ScreenInsets None = covers notches / cutouts too.
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

	-- Safe-area gui (logo badge + open button stay clear of the notch / topbar)
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

	-- Window (CanvasGroup => rounded clipping + whole-window fade) ----------
	local main = create("CanvasGroup", {
		Name = "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(WIN_W, WIN_H),
		BackgroundColor3 = Theme.Black,
		BorderSizePixel = 0,
		GroupTransparency = 1,
		Visible = false,
	}, gui)
	corner(main, UDim.new(0, 18))
	local mainScale = create("UIScale", {}, main)
	local _, mainStrokeGrad = gradStroke(main, 2, OUTLINE)
	self.Main = main

	-- animated pixel gradient + soft shade for readability
	self:_mosaic(main, WIN_W, WIN_H, 18, 0, function()
		return main.Visible
	end)
	local shade = create("Frame", {
		Name = "Shade",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Black,
		BorderSizePixel = 0,
		ZIndex = 2,
	}, main)
	create("UIGradient", {
		Rotation = 45,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.78),
			NumberSequenceKeypoint.new(1, 0.2),
		}),
	}, shade)

	-- Top bar ---------------------------------------------------------------
	local top = create("Frame", {
		Name = "TopBar",
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundColor3 = Theme.Black,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		ZIndex = 3,
	}, main)
	local titleRow = create("Frame", {
		Position = UDim2.fromOffset(18, 0),
		Size = UDim2.new(1, -70, 1, 0),
		BackgroundTransparency = 1,
	}, top)
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, titleRow)
	local title = label(titleRow, config.Title or "Hoodz", 20, WHITE, nil, true)
	title.AutomaticSize = Enum.AutomaticSize.X
	title.Size = UDim2.fromOffset(0, 24)
	title.TextTruncate = Enum.TextTruncate.None
	title.LayoutOrder = 1
	grad(title, TEXTGRAD, 0)
	local sub = label(titleRow, config.Subtitle or ("v" .. Library.Version), 12, Theme.Dim)
	sub.AutomaticSize = Enum.AutomaticSize.X
	sub.Size = UDim2.fromOffset(0, 24)
	sub.TextTruncate = Enum.TextTruncate.None
	sub.LayoutOrder = 2

	local close = create("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(28, 28),
		BackgroundColor3 = Theme.Row,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		Text = "×",
		Font = Theme.Bold,
		TextSize = 22,
		TextColor3 = Theme.Light,
		AutoButtonColor = false,
	}, top)
	corner(close, UDim.new(1, 0))
	close.MouseEnter:Connect(function()
		tween(close, 0.15, { BackgroundColor3 = Theme.RedDark })
	end)
	close.MouseLeave:Connect(function()
		tween(close, 0.15, { BackgroundColor3 = Theme.Row })
	end)

	-- Sidebar panel -----------------------------------------------------------
	local sidePanel = create("Frame", {
		Name = "SidePanel",
		Position = UDim2.fromOffset(10, 52),
		Size = UDim2.new(0, 158, 1, -62),
		BackgroundColor3 = Theme.Black,
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
		ZIndex = 3,
	}, main)
	corner(sidePanel, UDim.new(0, 14))
	solidStroke(sidePanel, 1, Theme.Stroke, 0.45)

	local side = create("ScrollingFrame", {
		Name = "Sidebar",
		Size = UDim2.new(1, 0, 1, -26),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 2,
		ScrollBarImageColor3 = Theme.Light,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
	}, sidePanel)
	create("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, side)
	create("UIPadding", {
		PaddingTop = UDim.new(0, 10),
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
		PaddingBottom = UDim.new(0, 8),
	}, side)
	self.Sidebar = side

	local footer = label(sidePanel, "Hoodz  •  v" .. Library.Version, 11, Theme.Dim, Enum.TextXAlignment.Center)
	footer.AnchorPoint = Vector2.new(0, 1)
	footer.Position = UDim2.new(0, 0, 1, -4)
	footer.Size = UDim2.new(1, 0, 0, 18)

	-- Content panel -----------------------------------------------------------
	local contentPanel = create("Frame", {
		Name = "ContentPanel",
		Position = UDim2.fromOffset(176, 52),
		Size = UDim2.new(1, -186, 1, -62),
		BackgroundColor3 = Theme.Black,
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
		ZIndex = 3,
	}, main)
	corner(contentPanel, UDim.new(0, 14))
	solidStroke(contentPanel, 1, Theme.Stroke, 0.45)

	local pageTitle = label(contentPanel, "", 16, WHITE, nil, true)
	pageTitle.Position = UDim2.fromOffset(16, 0)
	pageTitle.Size = UDim2.new(1, -32, 0, 40)
	grad(pageTitle, TEXTGRAD, 0)
	self._pageTitle = pageTitle
	create("Frame", {
		Position = UDim2.fromOffset(12, 40),
		Size = UDim2.new(1, -24, 0, 1),
		BackgroundColor3 = Theme.Stroke,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
	}, contentPanel)

	local pages = create("Frame", {
		Name = "Pages",
		Position = UDim2.fromOffset(0, 44),
		Size = UDim2.new(1, 0, 1, -44),
		BackgroundTransparency = 1,
	}, contentPanel)
	self.Content = pages

	-- Responsive scale -------------------------------------------------------
	local badgeScale
	local function rescale()
		local cam = workspace.CurrentCamera
		if not cam then
			return
		end
		local vp = cam.ViewportSize
		mainScale.Scale = math.clamp(math.min(vp.X / 640, vp.Y / 420), 0.55, 1.1)
		if badgeScale then
			badgeScale.Scale = math.clamp(math.min(vp.X / 900, vp.Y / 500), 0.75, 1)
		end
	end
	rescale()
	track(workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(rescale))
	if workspace.CurrentCamera then
		track(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale))
	end

	-- Dragging (mouse + touch) -----------------------------------------------
	local dragging, dragStart, startPos = false, nil, nil
	track(top.InputBegan:Connect(function(input)
		if isPointer(input) then
			dragging, dragStart, startPos = true, input.Position, main.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
				end
			end)
		end
	end))
	track(UserInputService.InputChanged:Connect(function(input)
		if dragging and isMove(input) then
			local cam = workspace.CurrentCamera
			local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
			local d = input.Position - dragStart
			main.Position = UDim2.fromScale(
				math.clamp(startPos.X.Scale + d.X / vp.X, 0.05, 0.95),
				math.clamp(startPos.Y.Scale + d.Y / vp.Y, 0.05, 0.95)
			)
		end
	end))

	-- Logo badge (top-left, safe area) -----------------------------------------
	local badge = create("ImageLabel", {
		Name = "Badge",
		Position = UDim2.fromOffset(12, 12),
		Size = UDim2.fromOffset(64, 64),
		BackgroundColor3 = Theme.Black,
		BackgroundTransparency = 1,
		Image = "",
		ImageTransparency = 1,
		ScaleType = Enum.ScaleType.Crop,
		Visible = false,
	}, safe)
	corner(badge, UDim.new(0, 16))
	local badgeStroke, badgeGrad = gradStroke(badge, 2.5, OUTLINE)
	badgeStroke.Transparency = 1
	badgeScale = create("UIScale", {}, badge)
	self.Badge, self.BadgeStroke = badge, badgeStroke
	self._hasBadge = false
	rescale()

	-- Round "H" open button (mobile friendly)
	local openBtn = create("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 12),
		Size = UDim2.fromOffset(44, 44),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		Visible = false,
	}, safe)
	local openBg = create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
	}, openBtn)
	corner(openBg, UDim.new(0, 14))
	grad(openBg, REDGRAD, 45)
	solidStroke(openBg, 1.5, Theme.Light, 0.35)
	local openTxt = label(openBtn, "H", 20, WHITE, Enum.TextXAlignment.Center, true)
	openTxt.Size = UDim2.fromScale(1, 1)
	openTxt.ZIndex = 2
	self._openBtn = openBtn

	-- Outline animation (one shared loop)
	self:_addTask(function(_, now)
		if main.Visible then
			mainStrokeGrad.Rotation = (now * 60) % 360
		end
		if badge.Visible then
			badgeGrad.Rotation = (now * 90) % 360
		end
	end)

	track(close.Activated:Connect(function()
		self:SetVisible(false)
	end))
	track(openBtn.Activated:Connect(function()
		self:Toggle()
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
function Library:SetVisible(v)
	if not self._loaded then
		return
	end
	self._visible = v
	self._token += 1
	local tok = self._token
	local main, badge = self.Main, self.Badge
	if v then
		main.Visible = true
		tween(main, 0.25, { GroupTransparency = 0 })
		if self._hasBadge then
			badge.Visible = true
			tween(badge, 0.25, { ImageTransparency = 0 })
			tween(self.BadgeStroke, 0.25, { Transparency = 0 })
		end
	else
		tween(main, 0.2, { GroupTransparency = 1 }).Completed:Connect(function()
			if self._token == tok then
				main.Visible = false
			end
		end)
		if self._hasBadge then
			tween(badge, 0.2, { ImageTransparency = 1 })
			tween(self.BadgeStroke, 0.2, { Transparency = 1 }).Completed:Connect(function()
				if self._token == tok then
					badge.Visible = false
				end
			end)
		end
	end
end

function Library:Toggle()
	self:SetVisible(not self._visible)
end

----------------------------------------------------------------------
-- Loading screen (full screen, transparent) -> smooth crossfade into the window
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
		BackgroundTransparency = 0.3, -- see-through
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
	title.Position = UDim2.fromOffset(0, 0)
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

	-- logo download/cache happens in parallel with the bar
	local asset, assetDone = nil, false
	task.spawn(function()
		asset = resolveImage(config.Image or "IMG_3411.jpeg", config.ImageUrl or DEFAULT_LOGO_URL)
		assetDone = true
	end)

	local duration = config.LoadingTime or 2
	local steps = { "Starting up", "Loading assets", "Building interface", "Ready" }
	for i, text in ipairs(steps) do
		status.Text = text
		tween(fill, duration / #steps, { Size = UDim2.fromScale(i / #steps, 1) }, Enum.EasingStyle.Sine)
		task.wait(duration / #steps)
	end
	local t0 = os.clock()
	while not assetDone and os.clock() - t0 < 5 do
		task.wait(0.05)
	end
	if asset then
		self.Badge.Image = asset
		self._hasBadge = true
	end
	task.wait(0.15)

	-- smooth transition: window rises + fades in while the loading screen fades out
	self._loaded = true
	self._visible = true
	self._openBtn.Visible = true
	local main = self.Main
	main.Position = UDim2.fromScale(0.5, 0.55)
	main.Visible = true
	tween(main, 0.8, { GroupTransparency = 0, Position = UDim2.fromScale(0.5, 0.5) }, Enum.EasingStyle.Quint)
	if self._hasBadge then
		task.delay(0.45, function()
			if self.Badge.Parent and self._visible then
				self.Badge.Visible = true
				tween(self.Badge, 0.8, { ImageTransparency = 0 })
				tween(self.BadgeStroke, 0.8, { Transparency = 0 })
			end
		end)
	end
	tween(grp, 0.7, { GroupTransparency = 1 }, Enum.EasingStyle.Sine).Completed:Wait()
	active = false
	removeMosaic()
	grp:Destroy()
end

function Library:Destroy()
	if self._conn then
		self._conn:Disconnect()
	end
	for _, c in ipairs(self._conns) do
		c:Disconnect()
	end
	self._tasks = {}
	self.Gui:Destroy()
	self.SafeGui:Destroy()
end

----------------------------------------------------------------------
-- Categories & tabs
----------------------------------------------------------------------
function Library:CreateCategory(name)
	self._catCount += 1
	local frame = create("Frame", {
		Name = name,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = self._catCount,
	}, self.Sidebar)
	create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, frame)
	local header = label(frame, string.upper(name), 11, Theme.Light, nil, true)
	header.Size = UDim2.new(1, 0, 0, 16)
	header.LayoutOrder = 0
	create("UIPadding", { PaddingLeft = UDim.new(0, 6) }, header)

	local cat = setmetatable({ Window = self, Frame = frame, Name = name, _n = 0 }, Category)
	self._catMap[name] = cat
	return cat
end

-- Convenience: UI:CreateTab("Name", "Category")
function Library:CreateTab(name, categoryName)
	categoryName = categoryName or "General"
	local cat = self._catMap[categoryName] or self:CreateCategory(categoryName)
	return cat:CreateTab(name)
end

function Library:_select(tab)
	self._pageTitle.Text = tab.Name
	for _, t in ipairs(self._tabs) do
		local on = t == tab
		t.Page.Visible = on
		tween(t.Bg, 0.18, { BackgroundTransparency = on and 0.05 or 1 })
		tween(t.Text, 0.18, { TextColor3 = on and WHITE or Theme.Dim })
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
	}, self.Frame)
	local bg = create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, btn)
	corner(bg, UDim.new(0, 10))
	grad(bg, REDGRAD, 0)
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
		PaddingLeft = UDim.new(0, 12),
		PaddingRight = UDim.new(0, 14),
		PaddingBottom = UDim.new(0, 10),
	}, page)

	local tab = setmetatable({ Window = lib, Page = page, Button = btn, Bg = bg, Text = txt, Name = name, _order = 0 }, Tab)
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
-- Components
----------------------------------------------------------------------
local ROW_ALPHA = 0.25

local function row(tab, height)
	tab._order += 1
	local r = create("Frame", {
		Size = UDim2.new(1, 0, 0, height),
		BackgroundColor3 = Theme.Row,
		BackgroundTransparency = ROW_ALPHA,
		BorderSizePixel = 0,
		LayoutOrder = tab._order,
	}, tab.Page)
	corner(r, UDim.new(0, 12))
	solidStroke(r, 1, Theme.Stroke, 0.5)
	return r
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
	self._order += 1
	local l = label(self.Page, string.upper(text), 11, Theme.Light, nil, true)
	l.Size = UDim2.new(1, 0, 0, 18)
	l.LayoutOrder = self._order
	create("UIPadding", { PaddingLeft = UDim.new(0, 4) }, l)
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
	self._order += 1
	local b = create("TextButton", {
		Size = UDim2.new(1, 0, 0, 38),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		LayoutOrder = self._order,
	}, self.Page)
	local bg = create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
	}, b)
	corner(bg, UDim.new(0, 12))
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
	local r = row(self, 42)
	local l = label(r, opts.Name or "Toggle", 14, Theme.Text)
	l.Position = UDim2.fromOffset(14, 0)
	l.Size = UDim2.new(1, -80, 1, 0)

	local sw = create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		Size = UDim2.fromOffset(44, 24),
		BackgroundColor3 = Theme.Off,
		BorderSizePixel = 0,
	}, r)
	corner(sw, UDim.new(1, 0))
	local onFill = create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, sw)
	corner(onFill, UDim.new(1, 0))
	grad(onFill, REDGRAD, 0)
	local knob = create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 3, 0.5, 0),
		Size = UDim2.fromOffset(18, 18),
		BackgroundColor3 = Theme.Text,
		BorderSizePixel = 0,
	}, sw)
	corner(knob, UDim.new(1, 0))

	local function render(animate)
		local pos = UDim2.new(0, state and 23 or 3, 0.5, 0)
		local alpha = state and 0 or 1
		if animate then
			tween(onFill, 0.18, { BackgroundTransparency = alpha })
			tween(knob, 0.18, { Position = pos }, Enum.EasingStyle.Back)
		else
			onFill.BackgroundTransparency = alpha
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
	}, r)
	hoverable(r, hit)
	self.Window._track(hit.Activated:Connect(function()
		obj:Set(not state)
	end))

	if opts.Default and opts.Callback then
		task.spawn(opts.Callback, state)
	end
	return obj
end

function Tab:CreateSlider(opts)
	local min, max, inc = opts.Min or 0, opts.Max or 100, opts.Increment or 1
	local value = math.clamp(opts.Default or min, min, max)
	local r = row(self, 60)
	hoverable(r, r)

	local l = label(r, opts.Name or "Slider", 14, Theme.Text)
	l.Position = UDim2.fromOffset(14, 8)
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

	local hit = create("Frame", {
		Position = UDim2.new(0, 16, 0, 32),
		Size = UDim2.new(1, -32, 0, 24),
		BackgroundTransparency = 1,
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

	local dragging = false
	local page = self.Page
	local reg = self.Window._track
	reg(hit.InputBegan:Connect(function(input)
		if isPointer(input) then
			dragging = true
			page.ScrollingEnabled = false -- don't scroll the page while sliding on touch
			tween(thumb, 0.12, { Size = UDim2.fromOffset(24, 24) })
			fromInput(input)
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
					page.ScrollingEnabled = true
					tween(thumb, 0.15, { Size = UDim2.fromOffset(18, 18) })
				end
			end)
		end
	end))
	reg(UserInputService.InputChanged:Connect(function(input)
		if dragging and isMove(input) then
			fromInput(input)
		end
	end))

	if opts.Callback then
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

return Library
