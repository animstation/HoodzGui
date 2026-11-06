--[[
	PixelRed UI Library  (open source)
	Red + black pixelated theme with animated gradient pixels.

	Features
	  * Animated pixel background (single shared 30Hz loop, pauses when hidden)
	  * Transparent loading screen
	  * Image badge (IMG_3411.jpeg) fades in top-left with UICorner + animated gradient outline
	  * Categories, tabs, toggles, sliders (+ buttons and labels)
	  * Draggable (mouse + touch), auto-scales for phones/tablets/PC
	  * Toggle with RightShift or the on-screen "UI" button (mobile friendly)
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Library = {}
Library.__index = Library

----------------------------------------------------------------------
-- Theme
----------------------------------------------------------------------
local Theme = {
	Black = Color3.fromRGB(8, 5, 7),
	Panel = Color3.fromRGB(16, 9, 11),
	Red = Color3.fromRGB(255, 45, 55),
	Dark = Color3.fromRGB(90, 0, 10),
	Text = Color3.fromRGB(245, 235, 235),
	Dim = Color3.fromRGB(170, 140, 145),
	Font = Enum.Font.Arcade, -- pixel font
}
Library.Theme = Theme

local PIXEL = 6 -- pixel grid size
local WHITE = Color3.new(1, 1, 1)
local REDGRAD = ColorSequence.new(Theme.Red, Theme.Dark)
local OFFGRAD = ColorSequence.new(Color3.fromRGB(60, 40, 44), Color3.fromRGB(20, 12, 14))
local OUTLINE = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Theme.Red),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(25, 0, 0)),
	ColorSequenceKeypoint.new(1, Theme.Red),
})

local rng = Random.new()

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

local function grad(parent, seq, rot)
	return create("UIGradient", { Color = seq, Rotation = rot or 0 }, parent)
end

-- gradient outline, returns the stroke and its gradient (so it can be animated)
local function gradStroke(parent, thickness, seq)
	local s = create("UIStroke", {
		Thickness = thickness,
		Color = WHITE,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, parent)
	return s, grad(s, seq, 0)
end

local function solidStroke(parent, thickness, color)
	return create("UIStroke", {
		Thickness = thickness,
		Color = color,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, parent)
end

local function label(parent, text, size, color, align)
	return create("TextLabel", {
		BackgroundTransparency = 1,
		Text = text,
		Font = Theme.Font,
		TextSize = size,
		TextColor3 = color or Theme.Text,
		TextXAlignment = align or Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, parent)
end

local function tween(obj, t, props)
	local tw = TweenService:Create(obj, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
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

local function loadImageAsset(file)
	if file and getcustomasset and isfile then
		local ok, exists = pcall(isfile, file)
		if ok and exists then
			local ok2, asset = pcall(getcustomasset, file)
			if ok2 and asset then
				return asset
			end
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
-- Pixel field: pooled gradient pixels drifting upward forever
----------------------------------------------------------------------
function Library:_pixelField(container, count, isActive)
	local field = create("Frame", {
		Name = "PixelField",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ClipsDescendants = true,
		ZIndex = 1,
	}, container)

	local W, H = 400, 300
	local function resize()
		local s = field.AbsoluteSize
		W, H = math.max(s.X, 1), math.max(s.Y, 1)
	end
	resize()
	field:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize)

	local pixels = {}
	for i = 1, count do
		local s = PIXEL * rng:NextInteger(1, 3)
		local f = create("Frame", {
			BorderSizePixel = 0,
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.3 + rng:NextNumber() * 0.5,
			Size = UDim2.fromOffset(s, s),
			ZIndex = 1,
		}, field)
		local g = grad(f, REDGRAD, rng:NextInteger(0, 359))
		pixels[i] = {
			f = f,
			g = g,
			s = s,
			x = rng:NextNumber() * W,
			y = rng:NextNumber() * H,
			vx = rng:NextNumber() * 16 - 8,
			vy = 14 + rng:NextNumber() * 46,
			vr = rng:NextNumber() * 120 - 60,
		}
	end

	local function update(dt)
		if not isActive() then
			return
		end
		for _, p in ipairs(pixels) do
			p.y -= p.vy * dt
			p.x += p.vx * dt
			if p.y < -p.s then
				p.y = H + p.s
				p.x = rng:NextNumber() * W
			end
			if p.x > W then
				p.x = -p.s
			elseif p.x < -p.s then
				p.x = W
			end
			-- snap to the pixel grid so motion looks pixelated
			p.f.Position = UDim2.fromOffset(math.floor(p.x / PIXEL) * PIXEL, math.floor(p.y / PIXEL) * PIXEL)
			p.g.Rotation = (p.g.Rotation + p.vr * dt) % 360
		end
	end

	local remove = self:_addTask(update)
	return function()
		remove()
		field:Destroy()
	end
end

----------------------------------------------------------------------
-- Window
----------------------------------------------------------------------
local Window = {}
Window.__index = Window
local Category = {}
Category.__index = Category
local Tab = {}
Tab.__index = Tab

function Library.new(config)
	config = config or {}
	local self = setmetatable({}, Library)
	self._tasks = {}
	self._conns = {}
	self._visible = false
	self._cats = {}
	self._tabs = {}
	self._camera = workspace.CurrentCamera

	local function track(c)
		table.insert(self._conns, c)
		return c
	end
	self._track = track

	self:_startLoop()

	local gui = create("ScreenGui", {
		Name = config.Name or "PixelRed",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 999,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, nil)
	pcall(function()
		if syn and syn.protect_gui then
			syn.protect_gui(gui)
		end
	end)
	gui.Parent = getGuiParent()
	self.Gui = gui

	-- Main window ------------------------------------------------------
	local main = create("Frame", {
		Name = "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(540, 340),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Visible = false,
	}, gui)
	grad(main, ColorSequence.new(Theme.Black, Color3.fromRGB(40, 0, 6)), 45)
	local mainScale = create("UIScale", {}, main)
	local _, mainStrokeGrad = gradStroke(main, 2, OUTLINE)
	self.Main = main

	self:_pixelField(main, 55, function()
		return main.Visible
	end)

	-- Top bar
	local top = create("Frame", {
		Name = "TopBar",
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundColor3 = Theme.Black,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		ZIndex = 5,
	}, main)
	local title = label(top, config.Title or "PIXELRED", 18, WHITE)
	title.Position = UDim2.fromOffset(12, 0)
	title.Size = UDim2.new(1, -60, 1, 0)
	title.ZIndex = 6
	grad(title, REDGRAD, 0)

	local close = create("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -6, 0.5, 0),
		Size = UDim2.fromOffset(24, 20),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Text = "X",
		Font = Theme.Font,
		TextSize = 14,
		TextColor3 = Theme.Text,
		AutoButtonColor = false,
		ZIndex = 6,
	}, top)
	grad(close, REDGRAD, 90)

	-- Sidebar
	local side = create("ScrollingFrame", {
		Name = "Sidebar",
		Position = UDim2.fromOffset(0, 32),
		Size = UDim2.new(0, 140, 1, -32),
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		ScrollBarThickness = 2,
		ScrollBarImageColor3 = Theme.Red,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ZIndex = 4,
	}, main)
	create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, side)
	create("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), PaddingBottom = UDim.new(0, 8) }, side)
	self.Sidebar = side

	-- Content
	local content = create("Frame", {
		Name = "Content",
		Position = UDim2.new(0, 140, 0, 32),
		Size = UDim2.new(1, -140, 1, -32),
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		ZIndex = 4,
	}, main)
	self.Content = content

	-- Responsive scale ---------------------------------------------------
	local badgeScale
	local function rescale()
		local cam = workspace.CurrentCamera
		if not cam then
			return
		end
		local vp = cam.ViewportSize
		local s = math.clamp(math.min(vp.X / 580, vp.Y / 380), 0.55, 1.15)
		mainScale.Scale = s
		if badgeScale then
			badgeScale.Scale = math.clamp(s, 0.7, 1)
		end
	end
	rescale()
	track(workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(rescale))
	if self._camera then
		track(self._camera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale))
	end

	-- Dragging (mouse + touch) -----------------------------------------
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

	-- Image badge (top-left) -------------------------------------------
	local asset = loadImageAsset(config.Image or "IMG_3411.jpeg")
	local badge, badgeStroke, badgeGrad
	if asset then
		badge = create("ImageLabel", {
			Name = "Badge",
			Position = UDim2.fromOffset(12, 12),
			Size = UDim2.fromOffset(64, 64),
			BackgroundColor3 = Theme.Black,
			BackgroundTransparency = 1,
			Image = asset,
			ImageTransparency = 1,
			ScaleType = Enum.ScaleType.Crop,
			Visible = false,
		}, gui)
		create("UICorner", { CornerRadius = UDim.new(0, 12) }, badge)
		badgeStroke, badgeGrad = gradStroke(badge, 2, OUTLINE)
		badgeStroke.Transparency = 1
		badgeScale = create("UIScale", {}, badge)
		badgeScale.Scale = 1
		rescale()
	end

	-- Outline animation (rotating gradients)
	self:_addTask(function(_, now)
		if main.Visible then
			mainStrokeGrad.Rotation = (now * 70) % 360
		end
		if badgeGrad and badge.Visible then
			badgeGrad.Rotation = (now * 90) % 360
		end
	end)

	-- Visibility ---------------------------------------------------------
	function self:SetVisible(v)
		self._visible = v
		main.Visible = v
		if badge and self._loaded then
			badge.Visible = v
		end
	end
	function self:Toggle()
		self:SetVisible(not self._visible)
	end
	track(close.Activated:Connect(function()
		self:SetVisible(false)
	end))

	-- Mobile / quick toggle button
	local openBtn = create("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 12),
		Size = UDim2.fromOffset(44, 36),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Text = "UI",
		Font = Theme.Font,
		TextSize = 16,
		TextColor3 = Theme.Text,
		AutoButtonColor = false,
		Visible = false,
	}, gui)
	grad(openBtn, REDGRAD, 90)
	gradStroke(openBtn, 2, OUTLINE)
	self._openBtn = openBtn
	track(openBtn.Activated:Connect(function()
		self:Toggle()
	end))

	local key = config.ToggleKey or Enum.KeyCode.RightShift
	track(UserInputService.InputBegan:Connect(function(input, gp)
		if not gp and input.KeyCode == key then
			self:Toggle()
		end
	end))

	-- Loading screen, then reveal ---------------------------------------
	task.spawn(function()
		self:_runLoading(config.LoadingTime or 1.8, badge, badgeStroke)
	end)

	return self
end

function Library:_runLoading(duration, badge, badgeStroke)
	local grp = create("CanvasGroup", {
		Name = "Loading",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Black,
		BackgroundTransparency = 0.35, -- transparent loading screen
		BorderSizePixel = 0,
		ZIndex = 50,
	}, self.Gui)

	local active = true
	local removeField = self:_pixelField(grp, 90, function()
		return active
	end)

	local title = label(grp, "PIXELRED", 40, WHITE, Enum.TextXAlignment.Center)
	title.AnchorPoint = Vector2.new(0.5, 0.5)
	title.Position = UDim2.new(0.5, 0, 0.5, -34)
	title.Size = UDim2.fromOffset(320, 48)
	title.ZIndex = 3
	grad(title, REDGRAD, 90)

	local barBg = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 14),
		Size = UDim2.fromOffset(260, 14),
		BackgroundColor3 = Theme.Black,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		ZIndex = 3,
	}, grp)
	gradStroke(barBg, 2, OUTLINE)
	local fill = create("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ZIndex = 4,
	}, barBg)
	grad(fill, REDGRAD, 0)

	local status = label(grp, "", 14, Theme.Dim, Enum.TextXAlignment.Center)
	status.AnchorPoint = Vector2.new(0.5, 0.5)
	status.Position = UDim2.new(0.5, 0, 0.5, 40)
	status.Size = UDim2.fromOffset(260, 18)
	status.ZIndex = 3

	local steps = { "Initializing", "Loading assets", "Building interface", "Ready" }
	for i, text in ipairs(steps) do
		status.Text = text
		tween(fill, duration / #steps, { Size = UDim2.fromScale(i / #steps, 1) })
		task.wait(duration / #steps)
	end

	-- reveal window + badge while the loading screen fades out
	self._loaded = true
	self._openBtn.Visible = true
	self:SetVisible(true)
	if badge then
		badge.Visible = true
		tween(badge, 0.8, { ImageTransparency = 0 })
		tween(badgeStroke, 0.8, { Transparency = 0 })
	end
	tween(grp, 0.5, { GroupTransparency = 1 }).Completed:Wait()
	active = false
	removeField()
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
end

----------------------------------------------------------------------
-- Categories & tabs
----------------------------------------------------------------------
function Library:CreateCategory(name)
	local frame = create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = #self._cats + 1,
		ZIndex = 5,
	}, self.Sidebar)
	create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, frame)
	local header = label(frame, "// " .. string.upper(name), 12, WHITE)
	header.Size = UDim2.new(1, 0, 0, 18)
	header.LayoutOrder = 0
	header.ZIndex = 5
	grad(header, REDGRAD, 0)

	local cat = setmetatable({ Window = self, Frame = frame, Name = name }, Category)
	self._cats[name] = cat
	table.insert(self._cats, cat)
	return cat
end

-- Convenience: Library:CreateTab("Name", "Category")
function Library:CreateTab(name, categoryName)
	categoryName = categoryName or "General"
	local cat = self._cats[categoryName] or self:CreateCategory(categoryName)
	return cat:CreateTab(name)
end

function Library:_select(tab)
	for _, t in ipairs(self._tabs) do
		local on = t == tab
		t.Page.Visible = on
		t.Indicator.Visible = on
		t.Button.TextColor3 = on and Theme.Text or Theme.Dim
		t.Button.BackgroundTransparency = on and 0.3 or 0.7
	end
end

function Category:CreateTab(name)
	local lib = self.Window
	local btn = create("TextButton", {
		Size = UDim2.new(1, 0, 0, 26),
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.7,
		BorderSizePixel = 0,
		Text = name,
		Font = Theme.Font,
		TextSize = 14,
		TextColor3 = Theme.Dim,
		TextXAlignment = Enum.TextXAlignment.Left,
		AutoButtonColor = false,
		LayoutOrder = #self.Frame:GetChildren(),
		ZIndex = 5,
	}, self.Frame)
	create("UIPadding", { PaddingLeft = UDim.new(0, 12) }, btn)
	local ind = create("Frame", {
		Size = UDim2.new(0, 3, 1, 0),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 6,
	}, btn)
	grad(ind, REDGRAD, 90)

	local page = create("ScrollingFrame", {
		Name = name,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = Theme.Red,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Visible = false,
		ZIndex = 5,
	}, lib.Content)
	create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, page)
	create("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 10), PaddingBottom = UDim.new(0, 8) }, page)

	local tab = setmetatable({ Window = lib, Page = page, Button = btn, Indicator = ind, _order = 0 }, Tab)
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
local function row(tab, height)
	tab._order += 1
	local r = create("Frame", {
		Size = UDim2.new(1, 0, 0, height),
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		LayoutOrder = tab._order,
		ZIndex = 5,
	}, tab.Page)
	solidStroke(r, 1, Theme.Dark)
	return r
end

function Tab:CreateLabel(text)
	local r = row(self, 26)
	local l = label(r, text, 14, Theme.Dim)
	l.Position = UDim2.fromOffset(10, 0)
	l.Size = UDim2.new(1, -20, 1, 0)
	l.ZIndex = 6
	return {
		Set = function(_, t)
			l.Text = t
		end,
	}
end

function Tab:CreateButton(opts)
	local r = row(self, 32)
	local b = create("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		Text = opts.Name or "Button",
		Font = Theme.Font,
		TextSize = 14,
		TextColor3 = Theme.Text,
		AutoButtonColor = false,
		ZIndex = 6,
	}, r)
	grad(b, REDGRAD, 0)
	self.Window._track(b.Activated:Connect(function()
		if opts.Callback then
			task.spawn(opts.Callback)
		end
	end))
end

function Tab:CreateToggle(opts)
	local state = opts.Default == true
	local r = row(self, 32)
	local l = label(r, opts.Name or "Toggle", 14, Theme.Text)
	l.Position = UDim2.fromOffset(10, 0)
	l.Size = UDim2.new(1, -70, 1, 0)
	l.ZIndex = 6

	local sw = create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(36, 16),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ZIndex = 6,
	}, r)
	local swGrad = grad(sw, OFFGRAD, 0)
	solidStroke(sw, 1, Theme.Dark)
	local knob = create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 2, 0.5, 0),
		Size = UDim2.fromOffset(12, 12),
		BackgroundColor3 = Theme.Text,
		BorderSizePixel = 0,
		ZIndex = 7,
	}, sw)

	local function render(animate)
		swGrad.Color = state and REDGRAD or OFFGRAD
		local pos = UDim2.new(0, state and 22 or 2, 0.5, 0)
		if animate then
			tween(knob, 0.12, { Position = pos })
		else
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
		ZIndex = 8,
	}, r)
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
	local r = row(self, 48)

	local l = label(r, opts.Name or "Slider", 14, Theme.Text)
	l.Position = UDim2.fromOffset(10, 4)
	l.Size = UDim2.new(1, -90, 0, 18)
	l.ZIndex = 6
	local valLbl = label(r, "", 14, Theme.Red, Enum.TextXAlignment.Right)
	valLbl.AnchorPoint = Vector2.new(1, 0)
	valLbl.Position = UDim2.new(1, -10, 0, 4)
	valLbl.Size = UDim2.fromOffset(70, 18)
	valLbl.ZIndex = 6

	local hit = create("Frame", {
		Position = UDim2.new(0, 10, 0, 26),
		Size = UDim2.new(1, -20, 0, 18),
		BackgroundTransparency = 1,
		ZIndex = 6,
	}, r)
	local track = create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(1, 0, 0, 8),
		BackgroundColor3 = Theme.Black,
		BorderSizePixel = 0,
		ZIndex = 6,
	}, hit)
	solidStroke(track, 1, Theme.Dark)
	local fill = create("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ZIndex = 7,
	}, track)
	grad(fill, REDGRAD, 0)

	local function apply(v, silent)
		v = math.clamp(math.floor((v - min) / inc + 0.5) * inc + min, min, max)
		v = tonumber(string.format("%.6g", v))
		local changed = v ~= value
		value = v
		fill.Size = UDim2.fromScale((v - min) / math.max(max - min, 1e-9), 1)
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
	local track_ = self.Window._track
	track_(hit.InputBegan:Connect(function(input)
		if isPointer(input) then
			dragging = true
			page.ScrollingEnabled = false -- don't scroll while sliding on touch
			fromInput(input)
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
					page.ScrollingEnabled = true
				end
			end)
		end
	end))
	track_(UserInputService.InputChanged:Connect(function(input)
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
