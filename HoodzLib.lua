local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")

local PixelLib = {}

-- Theme Configuration (Red & Black Pixelated)
local Theme = {
    Background = Color3.fromRGB(15, 12, 12),
    Container = Color3.fromRGB(25, 18, 18),
    AccentRed = Color3.fromRGB(220, 20, 60),
    DarkRed = Color3.fromRGB(120, 10, 20),
    Text = Color3.fromRGB(240, 240, 240),
    SubText = Color3.fromRGB(150, 140, 140),
    Border = Color3.fromRGB(60, 10, 15)
}

function PixelLib:CreateWindow(config)
    config = config or {}
    local windowName = config.Name or "Pixel Hub"

    -- Root ScreenGui
    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "PixelScriptGui_" .. math.random(1000, 9999)
    ScreenGui.ResetOnSpawn = false
    
    if gethui then
        ScreenGui.Parent = gethui()
    else
        ScreenGui.Parent = CoreGui
    end

    -- 1. Transparency Loading Screen
    local LoadScreen = Instance.new("Frame")
    LoadScreen.Size = UDim2.new(1, 0, 1, 0)
    LoadScreen.BackgroundColor3 = Color3.fromRGB(5, 5, 5)
    LoadScreen.BackgroundTransparency = 0.2
    LoadScreen.ZIndex = 10
    LoadScreen.Parent = ScreenGui

    local LoadLabel = Instance.new("TextLabel")
    LoadLabel.Size = UDim2.new(0, 300, 0, 50)
    LoadLabel.Position = UDim2.new(0.5, -150, 0.5, -25)
    LoadLabel.BackgroundTransparency = 1
    LoadLabel.Text = "LOADING SYSTEM..."
    LoadLabel.TextColor3 = Theme.AccentRed
    LoadLabel.TextSize = 18
    LoadLabel.Font = Enum.Font.Code
    LoadLabel.ZIndex = 11
    LoadLabel.Parent = LoadScreen

    -- Fade out loading screen after 1.5 seconds
    task.delay(1.5, function()
        local tween = TweenService:Create(LoadScreen, TweenInfo.new(0.8), {BackgroundTransparency = 1})
        local textTween = TweenService:Create(LoadLabel, TweenInfo.new(0.8), {TextTransparency = 1})
        tween:Play()
        textTween:Play()
        tween.Completed:Connect(function()
            LoadScreen:Destroy()
        end)
    end)

    -- Main Container Window
    local MainFrame = Instance.new("Frame")
    MainFrame.Size = UDim2.new(0, 560, 0, 380)
    MainFrame.Position = UDim2.new(0.5, -280, 0.5, -190)
    MainFrame.BackgroundColor3 = Theme.Background
    MainFrame.BorderSizePixel = 0
    MainFrame.ClipsDescendants = true
    MainFrame.Parent = ScreenGui

    local MainCorner = Instance.new("UICorner")
    MainCorner.CornerRadius = UDim.new(0, 4)
    MainCorner.Parent = MainFrame

    -- Main Frame Gradient Outline
    local MainStroke = Instance.new("UIStroke")
    MainStroke.Thickness = 2
    MainStroke.Parent = MainFrame
    local MainStrokeGrad = Instance.new("UIGradient")
    MainStrokeGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Theme.AccentRed),
        ColorSequenceKeypoint.new(1, Theme.DarkRed)
    })
    MainStrokeGrad.Parent = MainStroke

    -- 2. Red & Black Pixelated Animated Background with Gradient Pixels
    local PixelBgContainer = Instance.new("Folder")
    PixelBgContainer.Name = "PixelBackground"
    PixelBgContainer.Parent = MainFrame

    local gridCols, gridRows = 28, 19
    local pixWidth, pixHeight = 560 / gridCols, 380 / gridRows
    local pixels = {}

    for x = 0, gridCols - 1 do
        for y = 0, gridRows - 1 do
            local pixel = Instance.new("Frame")
            pixel.Size = UDim2.new(0, pixWidth + 1, 0, pixHeight + 1)
            pixel.Position = UDim2.new(0, x * pixWidth, 0, y * pixHeight)
            pixel.BackgroundColor3 = (math.random() > 0.5) and Theme.Background or Theme.DarkRed
            pixel.BorderSizePixel = 0
            pixel.BackgroundTransparency = 0.85
            
            -- Pixel Gradient Effect
            local pixGrad = Instance.new("UIGradient")
            pixGrad.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Theme.AccentRed),
                ColorSequenceKeypoint.new(1, Theme.Background)
            })
            pixGrad.Rotation = math.random(0, 360)
            pixGrad.Parent = pixel
            
            pixel.Parent = PixelBgContainer
            table.insert(pixels, {Instance = pixel, Gradient = pixGrad})
        end
    end

    -- Efficient background animation loop via RunService
    local tickCounter = 0
    local bgConn
    bgConn = RunService.RenderStepped:Connect(function(dt)
        tickCounter = tickCounter + dt
        if tickCounter >= 0.3 then -- update every 300ms for retro pixel frame-rate feel
            tickCounter = 0
            for _, pData in ipairs(pixels) do
                if math.random() > 0.85 then
                    pData.Gradient.Rotation = math.random(0, 360)
                end
            end
        end
        if not ScreenGui.Parent then
            bgConn:Disconnect()
        end
    end)

    -- 3. Image Handling: IMG_3411.jpeg Fading in Top Left with UI Corner & Gradient Outline
    local ImageHolder = Instance.new("Frame")
    ImageHolder.Size = UDim2.new(0, 45, 0, 45)
    ImageHolder.Position = UDim2.new(0, 10, 0, 10)
    ImageHolder.BackgroundTransparency = 1
    ImageHolder.ZIndex = 5
    ImageHolder.Parent = MainFrame

    local ProfileImage = Instance.new("ImageLabel")
    ProfileImage.Size = UDim2.new(1, 0, 1, 0)
    ProfileImage.BackgroundTransparency = 1
    -- Supports custom asset or rbxassetid format (falls back safely if local asset needs custom loader)
    pcall(function()
        ProfileImage.Image = getcustomasset and getcustomasset("IMG_3411.jpeg") or "rbxassetid://0"
    end)
    ProfileImage.ImageTransparency = 1
    ProfileImage.ZIndex = 5
    ProfileImage.Parent = ImageHolder

    local ImgCorner = Instance.new("UICorner")
    ImgCorner.CornerRadius = UDim.new(0, 8)
    ImgCorner.Parent = ProfileImage

    local ImgStroke = Instance.new("UIStroke")
    ImgStroke.Thickness = 2
    ImgStroke.Parent = ProfileImage
    local ImgStrokeGrad = Instance.new("UIGradient")
    ImgStrokeGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Theme.AccentRed),
        ColorSequenceKeypoint.new(1, Theme.DarkRed)
    })
    ImgStrokeGrad.Parent = ImgStroke

    -- Fade in the image smoothly after load
    task.delay(1.0, function()
        TweenService:Create(ProfileImage, TweenInfo.new(0.6), {ImageTransparency = 0}):Play()
    end)

    -- Top Bar Title & Dragging
    local TopBar = Instance.new("Frame")
    TopBar.Size = UDim2.new(1, 0, 0, 35)
    TopBar.BackgroundTransparency = 1
    TopBar.ZIndex = 4
    TopBar.Parent = MainFrame

    local TitleLabel = Instance.new("TextLabel")
    TitleLabel.Size = UDim2.new(1, -70, 1, 0)
    TitleLabel.Position = UDim2.new(0, 65, 0, 0)
    TitleLabel.BackgroundTransparency = 1
    TitleLabel.Text = windowName
    TitleLabel.TextColor3 = Theme.Text
    TitleLabel.Font = Enum.Font.Code
    TitleLabel.TextSize = 15
    TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
    TitleLabel.ZIndex = 4
    TitleLabel.Parent = TopBar

    -- Draggable implementation
    local dragging, dragInput, dragStart, startPos
    TopBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = MainFrame.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)
    TopBar.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement then
            dragInput = input
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            local delta = input.Position - dragStart
            MainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)

    -- Sidebar / Categories Panel
    local Sidebar = Instance.new("ScrollingFrame")
    Sidebar.Size = UDim2.new(0, 130, 1, -55)
    Sidebar.Position = UDim2.new(0, 10, 0, 45)
    Sidebar.BackgroundTransparency = 0.3
    Sidebar.BackgroundColor3 = Theme.Container
    Sidebar.BorderSizePixel = 0
    Sidebar.ScrollBarThickness = 2
    Sidebar.ZIndex = 3
    Sidebar.Parent = MainFrame

    local SidebarCorner = Instance.new("UICorner")
    SidebarCorner.CornerRadius = UDim.new(0, 4)
    SidebarCorner.Parent = Sidebar

    local SidebarLayout = Instance.new("UIListLayout")
    SidebarLayout.SortOrder = Enum.SortOrder.LayoutOrder
    SidebarLayout.Padding = UDim.new(0, 4)
    SidebarLayout.Parent = Sidebar

    -- Content Area for Tabs
    local ContentArea = Instance.new("Frame")
    ContentArea.Size = UDim2.new(1, -155, 1, -55)
    ContentArea.Position = UDim2.new(0, 145, 0, 45)
    ContentArea.BackgroundTransparency = 1
    ContentArea.ZIndex = 3
    ContentArea.Parent = MainFrame

    local Window = { Tabs = {} }

    -- 4. Categories & Tabs Generator
    function Window:CreateTab(tabName)
        local TabButton = Instance.new("TextButton")
        TabButton.Size = UDim2.new(1, -6, 0, 30)
        TabButton.Position = UDim2.new(0, 3, 0, 0)
        TabButton.BackgroundColor3 = Theme.Background
        TabButton.Text = " " .. tabName
        TabButton.TextColor3 = Theme.SubText
        TabButton.Font = Enum.Font.Code
        TabButton.TextSize = 12
        TabButton.TextXAlignment = Enum.TextXAlignment.Left
        TabButton.ZIndex = 4
        TabButton.Parent = Sidebar

        local BtnCorner = Instance.new("UICorner")
        BtnCorner.CornerRadius = UDim.new(0, 3)
        BtnCorner.Parent = TabButton

        local Container = Instance.new("ScrollingFrame")
        Container.Size = UDim2.new(1, 0, 1, 0)
        Container.BackgroundTransparency = 1
        Container.ScrollBarThickness = 3
        Container.Visible = false
        Container.ZIndex = 3
        Container.Parent = ContentArea

        local ContainerLayout = Instance.new("UIListLayout")
        ContainerLayout.SortOrder = Enum.SortOrder.LayoutOrder
        ContainerLayout.Padding = UDim.new(0, 6)
        ContainerLayout.Parent = Container

        local Tab = {}

        local function activateTab()
            for _, t in pairs(Window.Tabs) do
                t.Container.Visible = false
                t.Button.TextColor3 = Theme.SubText
                t.Button.BackgroundColor3 = Theme.Background
            end
            Container.Visible = true
            TabButton.TextColor3 = Theme.Text
            TabButton.BackgroundColor3 = Theme.DarkRed
        end

        TabButton.MouseButton1Click:Connect(activateTab)

        if #Window.Tabs == 0 then
            activateTab()
        end

        -- 5. UI Sliders Implementation
        function Tab:CreateSlider(opts)
            opts = opts or {}
            local sliderName = opts.Name or "Slider"
            local min = opts.Min or 0
            local max = opts.Max or 100
            local default = opts.Default or min
            local callback = opts.Callback or function() end

            local SliderFrame = Instance.new("Frame")
            SliderFrame.Size = UDim2.new(1, -6, 0, 42)
            SliderFrame.BackgroundColor3 = Theme.Container
            SliderFrame.ZIndex = 4
            SliderFrame.Parent = Container

            local SCorner = Instance.new("UICorner")
            SCorner.CornerRadius = UDim.new(0, 4)
            SCorner.Parent = SliderFrame

            local Label = Instance.new("TextLabel")
            Label.Size = UDim2.new(1, -10, 0, 20)
            Label.Position = UDim2.new(0, 6, 0, 2)
            Label.BackgroundTransparency = 1
            Label.Text = sliderName .. ": " .. tostring(default)
            Label.TextColor3 = Theme.Text
            Label.Font = Enum.Font.Code
            Label.TextSize = 11
            Label.TextXAlignment = Enum.TextXAlignment.Left
            Label.ZIndex = 5
            Label.Parent = SliderFrame

            local Track = Instance.new("Frame")
            Track.Size = UDim2.new(1, -12, 0, 6)
            Track.Position = UDim2.new(0, 6, 0, 26)
            Track.BackgroundColor3 = Theme.Background
            Track.ZIndex = 5
            Track.Parent = SliderFrame

            local TCorner = Instance.new("UICorner")
            TCorner.CornerRadius = UDim.new(0, 2)
            TCorner.Parent = Track

            local Fill = Instance.new("Frame")
            Fill.Size = UDim2.new((default - min) / (max - min), 0, 1, 0)
            Fill.BackgroundColor3 = Theme.AccentRed
            Fill.ZIndex = 6
            Fill.Parent = Track

            local FCorner = Instance.new("UICorner")
            FCorner.CornerRadius = UDim.new(0, 2)
            FCorner.Parent = Fill

            local DraggingSlider = false
            Track.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 then
                    DraggingSlider = true
                end
            end)
            UserInputService.InputEnded:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 then
                    DraggingSlider = false
                end
            end)
            UserInputService.InputChanged:Connect(function(input)
                if DraggingSlider and input.UserInputType == Enum.UserInputType.MouseMovement then
                    local pos = math.clamp((input.Position.X - Track.AbsolutePosition.X) / Track.AbsoluteSize.X, 0, 1)
                    Fill.Size = UDim2.new(pos, 0, 1, 0)
                    local val = math.floor(min + ((max - min) * pos))
                    Label.Text = sliderName .. ": " .. tostring(val)
                    pcall(callback, val)
                end
            end)
        end

        -- 6. Toggle Buttons Implementation
        function Tab:CreateToggle(opts)
            opts = opts or {}
            local toggleName = opts.Name or "Toggle"
            local state = opts.Default or false
            local callback = opts.Callback or function() end

            local ToggleFrame = Instance.new("Frame")
            ToggleFrame.Size = UDim2.new(1, -6, 0, 32)
            ToggleFrame.BackgroundColor3 = Theme.Container
            ToggleFrame.ZIndex = 4
            ToggleFrame.Parent = Container

            local TCorner = Instance.new("UICorner")
            TCorner.CornerRadius = UDim.new(0, 4)
            TCorner.Parent = ToggleFrame

            local Label = Instance.new("TextLabel")
            Label.Size = UDim2.new(1, -45, 1, 0)
            Label.Position = UDim2.new(0, 8, 0, 0)
            Label.BackgroundTransparency = 1
            Label.Text = toggleName
            Label.TextColor3 = Theme.Text
            Label.Font = Enum.Font.Code
            Label.TextSize = 11
            Label.TextXAlignment = Enum.TextXAlignment.Left
            Label.ZIndex = 5
            Label.Parent = ToggleFrame

            local Box = Instance.new("Frame")
            Box.Size = UDim2.new(0, 16, 0, 16)
            Box.Position = UDim2.new(1, -24, 0.5, -8)
            Box.BackgroundColor3 = state and Theme.AccentRed or Theme.Background
            Box.ZIndex = 5
            Box.Parent = ToggleFrame

            local BCorner = Instance.new("UICorner")
            BCorner.CornerRadius = UDim.new(0, 3)
            BCorner.Parent = Box

            local ClickBtn = Instance.new("TextButton")
            ClickBtn.Size = UDim2.new(1, 0, 1, 0)
            ClickBtn.BackgroundTransparency = 1
            ClickBtn.Text = ""
            ClickBtn.ZIndex = 6
            ClickBtn.Parent = ToggleFrame

            ClickBtn.MouseButton1Click:Connect(function()
                state = not state
                TweenService:Create(Box, TweenInfo.new(0.15), {
                    BackgroundColor3 = state and Theme.AccentRed or Theme.Background
                }):Play()
                pcall(callback, state)
            end)
        end

        Tab.Container = Container
        Tab.Button = TabButton
        table.insert(Window.Tabs, Tab)
        return Tab
    end

    return Window
end

return PixelLib
