--[[
    XL 翻译器 · Ultra（毛玻璃面板版）
    ------------------------------------------------------------
    · 单文件 Luau，注入执行器直接运行；无混淆 / 无采集 / 无授权校验
    · 启动先显示自包含加载动画，最少 5 秒；界面构建成功后才提示「加载成功」
    · 构建失败时停留在加载页，提示「加载失败，请重新加载」，可点按钮重试
    · 面板：首页 / 搜索 / 翻译 / 设置 四页，可拖拽、可最小化、可缩放适配
    · 翻译：长文本自动分段，多引擎依次降级；失败段自动补译一次，仍失败则保留原文并计数
    · 重复注入：旧实例立即停手并回收连接，不会与新界面互相拆台
    · 仅在你点击翻译时访问公开翻译接口，其余功能全部本地运行
]]

------------------------------------------------------------
-- 零、服务与运行环境
------------------------------------------------------------
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local TextService      = game:GetService("TextService")
local HttpService      = game:GetService("HttpService")
local GuiService       = game:GetService("GuiService")
local Workspace        = game:GetService("Workspace")

-- 等待游戏本体加载完成，避免早期注入时 PlayerGui / 相机尚未建立
if 不 game:IsLoaded() then
    game.Loaded:Wait()
end

-- LocalPlayer：最多等 15 秒，仍为空则安全退出而不是抛错
local LocalPlayer = Players.LocalPlayer
local envDeadline = tick() + 15
而 not LocalPlayer and tick() < envDeadline do
    task.wait(0.1)
    LocalPlayer = Players.LocalPlayer
end
if not LocalPlayer then
    return warn("[XLTranslator] LocalPlayer 未就绪，脚本终止")
end

-- PlayerGui：优先取现有实例，再带超时等待
local PlayerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    or LocalPlayer:WaitForChild("PlayerGui", 15)
if not PlayerGui then
    return warn("[XLTranslator] PlayerGui 未就绪，脚本终止")
end

-- 运行时全局表：执行器提供 getgenv 时用它，缺失时回退 _G
local runtime = _G
if type(getgenv) == "function" then
    local ok, env = pcall(getgenv)
    if ok and type(env) == "table" then
        runtime = env
    end
end

-- 每次注入分配运行号：旧实例发现编号变化后立刻停手，避免双开互相拆界面
local RUN_ID = (tonumber(runtime.XLTranslatorRunId) or 0) + 1
runtime.XLTranslatorRunId = RUN_ID

------------------------------------------------------------
-- 一、加载动画（自包含，不依赖任何外部库）
------------------------------------------------------------
local SPLASH_ID   = "XL_Splash"
local SPLASH_MIN  = 5      -- 最少展示秒数，加载更快也补足到 5 秒
local BUILD_RETRY = 3      -- 构建尝试次数上限（每次都是完整重建）

local SPLASH_ACCENT = Color3.fromRGB(181, 0, 255)
local SPLASH_BG     = Color3.fromRGB(15, 0, 26)
local SPLASH_BG2    = Color3.fromRGB(26, 0, 43)
local SPLASH_TEXT   = Color3.fromRGB(255, 255, 255)
local SPLASH_SUB    = Color3.fromRGB(209, 213, 219)

local function createSplash()
    local old = PlayerGui:FindFirstChild(SPLASH_ID)
    if old then
        old:Destroy()
    end

    local gui = Instance.new("ScreenGui")
    gui.Name = SPLASH_ID
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 9999
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

    local backdrop = Instance.new("Frame")
    backdrop.Size = UDim2.fromScale(1, 1)
    backdrop.BackgroundColor3 = SPLASH_BG
    backdrop.BorderSizePixel = 0
    backdrop.Parent = gui

    local bgGradient = Instance.new("UIGradient")
    bgGradient.Color = ColorSequence.new(SPLASH_BG2, SPLASH_BG)
    bgGradient.Rotation = 90
    bgGradient.Parent = backdrop

    local center = Instance.new("Frame")
    center.AnchorPoint = Vector2.new(0.5, 0.5)
    center.Position = UDim2.fromScale(0.5, 0.5)
    center.Size = UDim2.fromOffset(280, 236)
    center.BackgroundTransparency = 1
    center.Parent = backdrop

    local title = Instance.new("TextLabel")
    title.BackgroundTransparency = 1
    title.Font = Enum.Font.GothamBold
    title.Text = "XL 翻译器"
    title.TextSize = 30
    title.TextColor3 = SPLASH_TEXT
    title.Size = UDim2.new(1, 0, 0, 42)
    title.Position = UDim2.fromOffset(0, 6)
    title.Parent = center

    local titleGradient = Instance.new("UIGradient")
    titleGradient.Color = ColorSequence.new(SPLASH_TEXT, SPLASH_ACCENT)
    titleGradient.Rotation = 45
    titleGradient.Parent = title

    local subtitle = Instance.new("TextLabel")
    subtitle.BackgroundTransparency = 1
    subtitle.Font = Enum.Font.Gotham
    subtitle.Text = "ULTRA · 毛玻璃面板"
    subtitle.TextSize = 12
    subtitle.TextColor3 = SPLASH_SUB
    subtitle.Size = UDim2.new(1, 0, 0, 18)
    subtitle.Position = UDim2.fromOffset(0, 52)
    subtitle.Parent = center

    -- 三个跳动圆点
    local dotRow = Instance.new("Frame")
    dotRow.BackgroundTransparency = 1
    dotRow.AnchorPoint = Vector2.new(0.5, 0)
    dotRow.Position = UDim2.fromOffset(140, 92)
    dotRow.Size = UDim2.fromOffset(96, 22)
    dotRow.Parent = center

    local dotTweens = {}
    local dots = {}
    for index = 1, 3 do
        local dot = Instance.new("Frame")
        dot.AnchorPoint = Vector2.new(0.5, 0.5)
        dot.Position = UDim2.fromOffset((index - 1) * 36 + 12, 11)
        dot.Size = UDim2.fromOffset(14, 14)
        dot.BackgroundColor3 = SPLASH_ACCENT
        dot.BorderSizePixel = 0
        dot.Parent = dotRow

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(1, 0)
        corner.Parent = dot

        local info = TweenInfo.new(0.45, Enum.EasingStyle.Quad,
            Enum.EasingDirection.InOut, -1, true, (index - 1) * 0.18)
        local tw = TweenService:Create(dot, info, {
            Size = UDim2.fromOffset(9, 9),
            BackgroundTransparency = 0.55,
        })
        tw:Play()
        table.insert(dotTweens, tw)
        table.insert(dots, dot)
    end

    local status = Instance.new("TextLabel")
    status.BackgroundTransparency = 1
    status.Font = Enum.Font.Gotham
    status.TextSize = 13
    status.TextColor3 = SPLASH_SUB
    status.Text = "正在准备界面，请稍候…"
    status.Size = UDim2.new(1, 0, 0, 20)
    status.Position = UDim2.fromOffset(0, 124)
    status.TextWrapped = true
    status.Parent = center

    local tip = Instance.new("TextLabel")
    tip.BackgroundTransparency = 1
    tip.Font = Enum.Font.Gotham
    tip.TextSize = 11
    tip.TextColor3 = Color3.fromRGB(150, 136, 168)
    tip.Text = "手机端点标题栏「—」最小化，点悬浮球恢复"
    tip.Size = UDim2.new(1, 0, 0, 18)
    tip.Position = UDim2.fromOffset(0, 148)
    tip.TextWrapped = true
    tip.Parent = center

    -- 失败详情：只创建一次，反复失败时更新文字而不是叠加新标签
    local detail = Instance.new("TextLabel")
    detail.BackgroundTransparency = 1
    detail.Font = Enum.Font.Gotham
    detail.TextSize = 10
    detail.TextColor3 = Color3.fromRGB(190, 150, 150)
    detail.Text = ""
    detail.Size = UDim2.new(1, 0, 0, 30)
    detail.Position = UDim2.fromOffset(0, 150)
    detail.TextWrapped = true
    detail.Visible = false
    detail.Parent = center

    -- 失败态：按钮 + 重试
    local retryBtn = Instance.new("TextButton")
    retryBtn.AnchorPoint = Vector2.new(0.5, 0)
    retryBtn.Position = UDim2.fromOffset(140, 186)
    retryBtn.Size = UDim2.fromOffset(160, 36)
    retryBtn.BackgroundColor3 = SPLASH_ACCENT
    retryBtn.Text = "重新加载"
    retryBtn.Font = Enum.Font.GothamSemibold
    retryBtn.TextSize = 15
    retryBtn.TextColor3 = SPLASH_TEXT
    retryBtn.AutoButtonColor = false
    retryBtn.Visible = false
    retryBtn.Parent = center

    local retryCorner = Instance.new("UICorner")
    retryCorner.CornerRadius = UDim.new(0, 10)
    retryCorner.Parent = retryBtn

    local function truncateText(text, limit)
        local length = utf8.len(text)
        if not length then
            if #text > limit then
                return string.sub(text, 1, limit) .. "…"
            end
            return text
        end
        if length <= limit then
            return text
        end
        local cut = utf8.offset(text, limit + 1)
        if not cut then
            return text
        end
        return string.sub(text, 1, cut - 1) .. "…"
    end

    local handle = {}

    function handle.SetLoading()
        dotRow.Visible = true
        retryBtn.Visible = false
        tip.Visible = true
        detail.Visible = false
        status.Text = "正在准备界面，请稍候…"
        status.TextColor3 = SPLASH_SUB
        for _, dot in ipairs(dots) do
            dot.Size = UDim2.fromOffset(14, 14)
            dot.BackgroundTransparency = 0
        end
        for _, tw in ipairs(dotTweens) do
            tw:Play()
        end
    end

    function handle.SetFailed(reason)
        dotRow.Visible = false
        retryBtn.Visible = true
        tip.Visible = false
        status.Text = "加载失败，请重新加载"
        status.TextColor3 = Color3.fromRGB(255, 138, 138)

        local text = truncateText(tostring(reason or ""), 48)
        detail.Text = text
        detail.Visible = (text ~= "")

        for _, tw in ipairs(dotTweens) do
            tw:Cancel()
        end
    end

    function handle.BindRetry(callback)
        retryBtn.MouseButton1Click:Connect(callback)
    end

    function handle.Destroy()
        for _, tw in ipairs(dotTweens) do
            tw:Cancel()
        end
        gui:Destroy()
    end

    gui.Parent = PlayerGui
    return handle
end

local splash = createSplash()

------------------------------------------------------------
-- 二、面板构建（整体包在函数里，失败可完整重建，不留半成品）
------------------------------------------------------------
local PANEL_ID = "XLGlassPanel"

local function buildPanel()
    -- 已被更新的一次注入取代时直接放弃，避免旧实例拆掉新界面
    if runtime.XLTranslatorRunId ~= RUN_ID then
        return nil
    end

    ------------------------------------------------------------
    -- 2.1 清掉上一次的残留界面（含构建到一半失败的情况）
    ------------------------------------------------------------
    do
        -- 先断开上一份面板的输入 / 渲染连接，再销毁界面，避免重复注入后残留监听
        if type(runtime.XLTranslatorCleanup) == "function" then
            pcall(runtime.XLTranslatorCleanup)
        end
        runtime.XLTranslatorCleanup = nil

        local existing = PlayerGui:FindFirstChild(PANEL_ID)
        if existing then
            existing:Destroy()
        end
    end

    ------------------------------------------------------------
    -- 2.2 用户配置（可导入导出）
    ------------------------------------------------------------
    local Config = {
        Theme       = "xlpurple",
        Accent      = Color3.fromRGB(181, 0, 255),
        Opacity     = 0,
        Layout      = "cozy",
        Animations  = true,
        FontName    = "Gotham",
        ScaleBoost  = 0,

        AnimHover     = 0.15,
        AnimToggle    = 0.18,
        AnimNotifyIn  = 0.25,
        AnimNotifyOut = 0.20,

        TapThreshold    = 8,
        DragClampFactor = 0.4,
        DragEdgeMargin  = 4,

        NotifyDuration    = 3,
        NotifySlideOffset = 0.85,
        NotifyExitScale   = 0.90,

        TextMeasureBound = 4096,

        PopoverGap        = 6,
        PopoverMaxHeight  = 220,
        PopoverItemHeight = 28,
        PopoverItemGap    = 4,

        ScaleMin = 0.62,
        ScaleMax = 1.30,

        -- 翻译相关
        TransChunkSize    = 900,
        TransCacheLimit   = 200,
        TransHistoryLimit = 5,
        TransMaxChars     = 4000,
        TransInterval     = 0.6,
        TransSource       = "auto",
        TransTarget       = "zh-CN",
        TransAutoCopy     = true,
    }

    ------------------------------------------------------------
    -- 2.3 调色板
    ------------------------------------------------------------
    local Palette = {}

    local RAW_THEMES = {
        light = {
            Card        = Color3.fromRGB(255, 255, 255),
            CardTint    = Color3.fromRGB(239, 237, 250),
            Surface     = Color3.fromRGB(248, 247, 253),
            Stroke      = Color3.fromRGB(255, 255, 255),
            Text        = Color3.fromRGB(38, 36, 52),
            SubText     = Color3.fromRGB(118, 116, 138),
            Placeholder = Color3.fromRGB(168, 166, 182),
            Shadow      = Color3.fromRGB(78, 66, 140),
        },
        dark = {
            Card        = Color3.fromRGB(32, 30, 44),
            CardTint    = Color3.fromRGB(44, 41, 60),
            Surface     = Color3.fromRGB(38, 35, 52),
            Stroke      = Color3.fromRGB(126, 116, 178),
            Text        = Color3.fromRGB(237, 235, 248),
            SubText     = Color3.fromRGB(152, 149, 170),
            Placeholder = Color3.fromRGB(120, 118, 140),
            Shadow      = Color3.fromRGB(10, 8, 20),
        },
        xlpurple = {
            Card        = Color3.fromRGB(26, 0, 43),
            CardTint    = Color3.fromRGB(37, 21, 49),
            Surface     = Color3.fromRGB(20, 0, 34),
            Stroke      = Color3.fromRGB(59, 31, 71),
            Text        = Color3.fromRGB(255, 255, 255),
            SubText     = Color3.fromRGB(209, 213, 219),
            Placeholder = Color3.fromRGB(150, 136, 168),
            Shadow      = Color3.fromRGB(6, 0, 12),
        },
    }

    local THEME_ACCENTS = {
        light    = Color3.fromRGB(139, 124, 246),
        dark     = Color3.fromRGB(139, 124, 246),
        xlpurple = Color3.fromRGB(181, 0, 255),
    }

    local function applyPalette()
        local raw = RAW_THEMES[Config.Theme] or RAW_THEMES.light
        for key, value in pairs(raw) do
            Palette[key] = value
        end
        Palette.Accent = Config.Accent
    end
    applyPalette()

    ------------------------------------------------------------
    -- 2.4 通用工具 / 回收器 / 刷新绑定
    ------------------------------------------------------------
    local function new(className, props, parent)
        local obj = Instance.new(className)
        if props then
            for key, value in pairs(props) do
                obj[key] = value
            end
        end
        if parent then
            obj.Parent = parent
        end
        return obj
    end

    local function Janitor()
        local items = {}
        local cleaned = false
        local self = {}

        function self:Add(item)
            if not cleaned and item ~= nil then
                table.insert(items, item)
            end
            return item
        end

        function self:Untrack(item)
            local index = table.find(items, item)
            if index then
                table.remove(items, index)
            end
        end

        function self:Cleanup()
            if cleaned then
                return
            end
            cleaned = true
            for index = #items, 1, -1 do
                local item = items[index]
                local kind = typeof(item)
                if kind == "RBXScriptConnection" then
                    pcall(function() item:Disconnect() end)
                elseif kind == "Instance" then
                    pcall(function() item:Destroy() end)
                elseif kind == "function" then
                    pcall(item)
                elseif type(item) == "table" and type(item.Cleanup) == "function" then
                    pcall(function() item:Cleanup() end)
                end
            end
            table.clear(items)
        end

        function self:IsCleaned()
            return cleaned
        end

        return self
    end

    local refreshers = {}

    local function detachRefresher(entry)
        local index = table.find(refreshers, entry)
        if index then
            table.remove(refreshers, index)
        end
    end

    local function bindRefresh(fn, probe, janitor)
        local entry = { fn = fn, probe = probe }
        table.insert(refreshers, entry)
        local ok, err = pcall(fn)
        if not ok then
            warn("[XLTranslator] 刷新初始化异常: " .. tostring(err))
        end

        if janitor then
            janitor:Add(function()
                detachRefresher(entry)
            end)
        end

        return entry
    end

    local function refreshAll()
        for index = #refreshers, 1, -1 do
            local entry = refreshers[index]
            local alive = true
            if entry.probe then
                local ok, result = pcall(entry.probe)
                alive = ok and result and true or false
            end
            if not alive then
                table.remove(refreshers, index)
            else
                local ok, err = pcall(entry.fn)
                if not ok then
                    warn("[XLTranslator] 刷新异常: " .. tostring(err))
                end
            end
        end
    end

    ------------------------------------------------------------
    -- 2.5 字体
    ------------------------------------------------------------
    local FONT_OPTIONS = {
        { name = "Gotham",      font = Enum.Font.Gotham },
        { name = "BuilderSans", font = Enum.Font.BuilderSans },
        { name = "SourceSans",  font = Enum.Font.SourceSans },
        { name = "Ubuntu",      font = Enum.Font.Ubuntu },
        { name = "Montserrat",  font = Enum.Font.Montserrat },
    }

    local function resolveFont(name)
        for _, option in ipairs(FONT_OPTIONS) do
            if option.name == name then
                return option.font
            end
        end
        return Enum.Font.Gotham
    end

    local function currentFont()
        return resolveFont(Config.FontName)
    end

    local function registerText(textObj, janitor)
        bindRefresh(function()
            textObj.Font = currentFont()
        end, function()
            return textObj.Parent ~= nil
        end, janitor)
    end

    ------------------------------------------------------------
    -- 2.6 动画与文本测量
    ------------------------------------------------------------
    local function tween(obj, duration, props, easingStyle)
        if not obj then
            return nil
        end
        if not Config.Animations then
            for key, value in pairs(props) do
                obj[key] = value
            end
            return nil
        end
        local info = TweenInfo.new(
            duration,
            easingStyle or Enum.EasingStyle.Quad,
            Enum.EasingDirection.Out
        )
        local tweenObj = TweenService:Create(obj, info, props)
        tweenObj:Play()
        return tweenObj
    end

    local function measureWidth(text, textSize, font)
        local ok, size = pcall(function()
            return TextService:GetTextSize(
                text, textSize, font,
                Vector2.new(Config.TextMeasureBound, Config.TextMeasureBound)
            )
        end)
        if ok and size then
            return size.X
        end
        return textSize * #tostring(text) * 0.62
    end

    -- 删除最后一个完整字符（多字节字符不能被切半个）
    local function trimLastChar(text)
        local index = #text
        while index > 1 do
            local byte = string.byte(text, index)
            if byte and byte >= 0x80 and byte <= 0xBF then
                index = index - 1
            else
                break
            end
        end
        return string.sub(text, 1, math.max(0, index - 1))
    end

    -- 超长文本尾部省略；逐字符回退，避免切出乱码
    local function ellipsize(textObj, text, maxWidth)
        textObj.Text = text
        if measureWidth(text, textObj.TextSize, textObj.Font) <= maxWidth then
            return
        end

        local shortened = text
        local guard = 0
        while #shortened > 0 and guard < 80 do
            guard = guard + 1
            shortened = trimLastChar(shortened)
            local trial = shortened .. "…"
            if measureWidth(trial, textObj.TextSize, textObj.Font) <= maxWidth then
                textObj.Text = trial
                return
            end
        end
        textObj.Text = "…"
    end

    ------------------------------------------------------------
    -- 2.7 安全区与自适应缩放
    ------------------------------------------------------------
    local function getCamera()
        return Workspace.CurrentCamera
    end

    local function getSafeMargin()
        local topInset, bottomInset = GuiService:GetGuiInset()
        return topInset.X, topInset.Y, bottomInset.X, bottomInset.Y
    end

    -- 设计基准 480 × 340；分档后与窗口尺寸约束共同生效
    local function computeUIScale()
        local camera = getCamera()
        if not camera then
            return 1
        end
        local viewport = camera.ViewportSize
        local widthRatio = viewport.X / 480
        local heightRatio = viewport.Y / 340
        local base = math.min(widthRatio, heightRatio)
        local scaled = math.clamp(base, 0.62, 1.12) + Config.ScaleBoost
        return math.clamp(scaled, Config.ScaleMin, Config.ScaleMax)
    end

    local function spacing()
        if Config.Layout == "compact" then
            return { pad = 8, gap = 6, row = 30, corner = 10 }
        end
        return { pad = 14, gap = 10, row = 38, corner = 14 }
    end

    ------------------------------------------------------------
    -- 2.8 基础视觉组件
    ------------------------------------------------------------
    local function glassFrame(name, parent, baseTransparency, janitor)
        local frame = new("Frame", {
            Name = name,
            BackgroundColor3 = Palette.Card,
            BackgroundTransparency = math.clamp((baseTransparency or 0.08) + Config.Opacity, 0, 0.95),
            BorderSizePixel = 0,
        })

        local corner = new("UICorner", { CornerRadius = UDim.new(0, spacing().corner) }, frame)
        local stroke = new("UIStroke", {
            Color = Palette.Stroke,
            Thickness = 1,
            Transparency = 0.35,
        }, frame)
        local gradient = new("UIGradient", {
            Color = ColorSequence.new(Palette.Card, Palette.CardTint),
            Rotation = 90,
            Transparency = NumberSequence.new(0, 0.06),
        }, frame)

        bindRefresh(function()
            frame.BackgroundColor3 = Palette.Card
            frame.BackgroundTransparency =
                math.clamp((baseTransparency or 0.08) + Config.Opacity, 0, 0.95)
            stroke.Color = Palette.Stroke
            gradient.Color = ColorSequence.new(Palette.Card, Palette.CardTint)
            corner.CornerRadius = UDim.new(0, spacing().corner)
        end, function()
            return frame.Parent ~= nil
        end, janitor)

        frame.Parent = parent
        return frame
    end

    local function addShadow(target, spread, transparency, janitor)
        local shadow = new("ImageLabel", {
            Name = "SoftShadow",
            BackgroundTransparency = 1,
            Image = "rbxassetid://1316045217",
            ScaleType = Enum.ScaleType.Slice,
            SliceCenter = Rect.new(10, 10, 118, 118),
            ImageColor3 = Palette.Shadow,
            ImageTransparency = transparency or 0.55,
            Size = UDim2.new(1, spread * 2, 1, spread * 2),
            Position = UDim2.new(0, -spread, 0, -spread),
            ZIndex = 0,
        }, target)
        bindRefresh(function()
            shadow.ImageColor3 = Palette.Shadow
        end, function()
            return shadow.Parent ~= nil
        end, janitor)
        return shadow
    end

    local function resolveLabelColor(colorKey)
        if type(colorKey) == "string" then
            return Palette[colorKey] or Palette.Text
        end
        return colorKey or Palette.Text
    end

    local function makeLabel(parent, text, textSize, colorKey, props, janitor)
        local label = new("TextLabel", {
            BackgroundTransparency = 1,
            Text = text,
            TextSize = textSize,
            TextColor3 = resolveLabelColor(colorKey),
            Font = currentFont(),
            TextWrapped = true,
        }, parent)
        if props then
            for key, value in pairs(props) do
                label[key] = value
            end
        end
        registerText(label, janitor)
        bindRefresh(function()
            label.TextColor3 = resolveLabelColor(colorKey)
        end, function()
            return label.Parent ~= nil
        end, janitor)
        return label
    end

    local function makeButton(parent, janitor, text, callback, props)
        local button = new("TextButton", {
            Name = "Button",
            Text = text,
            Font = currentFont(),
            TextSize = 14,
            TextColor3 = Palette.Card,
            BackgroundColor3 = Palette.Accent,
            BackgroundTransparency = 0.05,
            BorderSizePixel = 0,
            AutoButtonColor = false,
            Size = UDim2.new(1, 0, 0, math.max(32, spacing().row - 4)),
        }, parent)
        registerText(button, janitor)
        local corner = new("UICorner", { CornerRadius = UDim.new(0, 10) }, button)

        janitor:Add(button.MouseEnter:Connect(function()
            tween(button, Config.AnimHover, { BackgroundTransparency = 0.2 })
        end))
        janitor:Add(button.MouseLeave:Connect(function()
            tween(button, Config.AnimHover, { BackgroundTransparency = 0.05 })
        end))
        janitor:Add(button.Activated:Connect(function()
            if callback then
                callback()
            end
        end))

        bindRefresh(function()
            button.BackgroundColor3 = Palette.Accent
            button.TextColor3 = Palette.Card
            corner.CornerRadius = UDim.new(0, math.max(6, spacing().corner - 4))
        end, function()
            return button.Parent ~= nil
        end, janitor)

        if props then
            for key, value in pairs(props) do
                button[key] = value
            end
        end
        return button
    end

    local function makeToggle(parent, janitor, label, default, callback)
        local holder = new("Frame", {
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, math.max(28, spacing().row - 8)),
        }, parent)

        makeLabel(holder, label, 13, "Text", {
            TextXAlignment = Enum.TextXAlignment.Left,
            Size = UDim2.new(1, -56, 1, 0),
            Position = UDim2.new(0, 2, 0, 0),
        }, janitor)

        local track = new("TextButton", {
            Name = "ToggleTrack",
            Text = "",
            BackgroundColor3 = Palette.CardTint,
            BackgroundTransparency = 0.1,
            AutoButtonColor = false,
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, 0, 0.5, 0),
            Size = UDim2.new(0, 44, 0, 22),
        }, holder)
        new("UICorner", { CornerRadius = UDim.new(1, 0) }, track)

        local knob = new("Frame", {
            Name = "Knob",
            BackgroundColor3 = Palette.Card,
            Size = UDim2.new(0, 16, 0, 16),
            Position = UDim2.new(0, 3, 0, 3),
        }, track)
        new("UICorner", { CornerRadius = UDim.new(1, 0) }, knob)

        local state = default and true or false

        local function render()
            if state then
                tween(track, Config.AnimToggle, {
                    BackgroundColor3 = Palette.Accent,
                    BackgroundTransparency = 0,
                })
                tween(knob, Config.AnimToggle, { Position = UDim2.new(1, -19, 0, 3) })
            else
                tween(track, Config.AnimToggle, {
                    BackgroundColor3 = Palette.CardTint,
                    BackgroundTransparency = 0.1,
                })
                tween(knob, Config.AnimToggle, { Position = UDim2.new(0, 3, 0, 3) })
            end
        end

        janitor:Add(track.Activated:Connect(function()
            state = not state
            render()
            if callback then
                callback(state)
            end
        end))

        bindRefresh(function()
            knob.BackgroundColor3 = Palette.Card
            if state then
                track.BackgroundColor3 = Palette.Accent
            else
                track.BackgroundColor3 = Palette.CardTint
            end
        end, function()
            return holder.Parent ~= nil
        end, janitor)

        render()
        return {
            Get = function() return state end,
            Set = function(value)
                state = value and true or false
                render()
            end,
        }
    end

    ------------------------------------------------------------
    -- 2.9 滑块
    ------------------------------------------------------------
    local MOUSE_BUTTON = Enum.UserInputType.MouseButton1
    local TOUCH = Enum.UserInputType.Touch

    local function makeSlider(parent, janitor, opts)
        opts = opts or {}
        local minV = opts.min
        local maxV = opts.max
        if minV == nil then minV = 0 end
        if maxV == nil then maxV = 100 end
        if maxV < minV then
            maxV = minV
        end
        local decimals = opts.decimals or 0
        local value = opts.default
        if value == nil then
            value = minV
        end
        value = math.clamp(value, minV, maxV)

        local holder = new("Frame", {
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, math.max(34, spacing().row)),
        }, parent)

        local valueLabel = makeLabel(holder, "", 13, "SubText", {
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.new(1, 0, 0, 0),
            Size = UDim2.new(0.5, 0, 0, 16),
            TextXAlignment = Enum.TextXAlignment.Right,
        }, janitor)
        makeLabel(holder, opts.label or "", 12, "Text", {
            TextXAlignment = Enum.TextXAlignment.Left,
            Position = UDim2.new(0, 2, 0, 0),
            Size = UDim2.new(1, -50, 0, 16),
        }, janitor)

        local track = new("Frame", {
            BackgroundColor3 = Palette.CardTint,
            BackgroundTransparency = 0.05,
            BorderSizePixel = 0,
            Position = UDim2.new(0, 2, 1, -10),
            Size = UDim2.new(1, -4, 0, 6),
        }, holder)
        new("UICorner", { CornerRadius = UDim.new(1, 0) }, track)

        local fill = new("Frame", {
            BackgroundColor3 = Palette.Accent,
            BorderSizePixel = 0,
            Size = UDim2.new(0, 0, 1, 0),
        }, track)
        new("UICorner", { CornerRadius = UDim.new(1, 0) }, fill)

        local knob = new("Frame", {
            BackgroundColor3 = Palette.Card,
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(0, 0, 0.5, 0),
            Size = UDim2.new(0, 14, 0, 14),
        }, track)
        new("UICorner", { CornerRadius = UDim.new(1, 0) }, knob)
        local knobStroke = new("UIStroke", { Color = Palette.Accent, Thickness = 2 }, knob)

        local hitArea = new("TextButton", {
            Text = "",
            BackgroundTransparency = 1,
            AutoButtonColor = false,
            BorderSizePixel = 0,
            Position = UDim2.new(0, 0, 1, -24),
            Size = UDim2.new(1, 0, 0, 22),
            ZIndex = 6,
        }, holder)

        local activeInput = nil

        local function formatValue()
            if decimals == 0 then
                return tostring(math.round(value))
            end
            return string.format("%." .. decimals .. "f", value)
        end

        local function render()
            local ratio = 0
            if maxV > minV then
                ratio = math.clamp((value - minV) / (maxV - minV), 0, 1)
            end
            fill.Size = UDim2.new(ratio, 0, 1, 0)
            knob.Position = UDim2.new(ratio, 0, 0.5, 0)
            valueLabel.Text = formatValue()
        end

        local function updateFromX(absoluteX)
            local ratio = math.clamp((absoluteX - track.AbsolutePosition.X)
                / math.max(1, track.AbsoluteSize.X), 0, 1)
            local raw = minV + ratio * (maxV - minV)
            if decimals == 0 then
                raw = math.round(raw)
            else
                raw = math.round(raw * 10 ^ decimals) / 10 ^ decimals
            end
            value = math.clamp(raw, minV, maxV)
            render()
            if opts.callback then
                opts.callback(value)
            end
        end

        janitor:Add(hitArea.InputBegan:Connect(function(input)
            if (input.UserInputType == MOUSE_BUTTON or input.UserInputType == TOUCH)
                and not activeInput then
                activeInput = input
                updateFromX(input.Position.X)
            end
        end))
        janitor:Add(UserInputService.InputChanged:Connect(function(input)
            if input == activeInput then
                updateFromX(input.Position.X)
            end
        end))
        janitor:Add(UserInputService.InputEnded:Connect(function(input)
            if input == activeInput then
                activeInput = nil
            end
        end))

        bindRefresh(function()
            fill.BackgroundColor3 = Palette.Accent
            track.BackgroundColor3 = Palette.CardTint
            knob.BackgroundColor3 = Palette.Card
            knobStroke.Color = Palette.Accent
            if decimals == 0 then
                valueLabel.Text = tostring(math.round(value))
            end
        end, function()
            return holder.Parent ~= nil
        end, janitor)

        render()
        return {
            Get = function() return value end,
            Set = function(v)
                value = math.clamp(v, minV, maxV)
                render()
            end,
        }
    end

    ------------------------------------------------------------
    -- 2.10 输入框 / 多行文本域
    ------------------------------------------------------------
    local function makeInput(parent, janitor, placeholder, default, callback)
        local box = new("TextBox", {
            BackgroundColor3 = Palette.Surface,
            BackgroundTransparency = 0.1,
            BorderSizePixel = 0,
            Font = currentFont(),
            TextSize = 14,
            TextColor3 = Palette.Text,
            PlaceholderText = placeholder,
            PlaceholderColor3 = Palette.Placeholder,
            Text = default or "",
            ClearTextOnFocus = false,
            Size = UDim2.new(1, 0, 0, math.max(32, spacing().row - 4)),
        }, parent)
        registerText(box, janitor)
        local corner = new("UICorner", { CornerRadius = UDim.new(0, 10) }, box)
        new("UIPadding", {
            PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10),
        }, box)

        -- 只在文本变化时回调，避免 FocusLost 再触发一次造成重复处理
        janitor:Add(box:GetPropertyChangedSignal("Text"):Connect(function()
            if callback then
                callback(box.Text)
            end
        end))

        bindRefresh(function()
            box.BackgroundColor3 = Palette.Surface
            box.TextColor3 = Palette.Text
            box.PlaceholderColor3 = Palette.Placeholder
            corner.CornerRadius = UDim.new(0, math.max(6, spacing().corner - 4))
        end, function()
            return box.Parent ~= nil
        end, janitor)

        return box
    end

    local function makeTextArea(parent, janitor, placeholder, default, height, readOnly)
        local box = new("TextBox", {
            BackgroundColor3 = Palette.Surface,
            BackgroundTransparency = 0.1,
            BorderSizePixel = 0,
            Font = currentFont(),
            TextSize = 13,
            TextColor3 = Palette.Text,
            PlaceholderText = placeholder,
            PlaceholderColor3 = Palette.Placeholder,
            Text = default or "",
            ClearTextOnFocus = false,
            MultiLine = true,
            TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Top,
            TextEditable = not readOnly,
            Size = UDim2.new(1, 0, 0, height or 96),
        }, parent)
        registerText(box, janitor)
        local corner = new("UICorner", { CornerRadius = UDim.new(0, 10) }, box)
        new("UIPadding", {
            PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10),
            PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8),
        }, box)

        bindRefresh(function()
            box.BackgroundColor3 = Palette.Surface
            box.TextColor3 = Palette.Text
            box.PlaceholderColor3 = Palette.Placeholder
            corner.CornerRadius = UDim.new(0, math.max(6, spacing().corner - 4))
        end, function()
            return box.Parent ~= nil
        end, janitor)

        return box
    end

    ------------------------------------------------------------
    -- 2.11 浮层（下拉 / 颜色拾取共用）
    ------------------------------------------------------------
    local OverlayLayer
    local activePopoverJanitor

    local function dismissOverlay()
        if activePopoverJanitor then
            activePopoverJanitor:Cleanup()
            activePopoverJanitor = nil
        end
        if OverlayLayer then
            for _, child in ipairs(OverlayLayer:GetChildren()) do
                pcall(function() child:Destroy() end)
            end
        end
    end

    local function createPopover(anchor, size, modal)
        dismissOverlay()
        activePopoverJanitor = Janitor()

        local scrim = new("TextButton", {
            Name = "Scrim",
            Text = "",
            BackgroundTransparency = 1,
            AutoButtonColor = false,
            Size = UDim2.fromScale(1, 1),
        }, OverlayLayer)

        local card = glassFrame("PopoverCard", OverlayLayer, 0.04, activePopoverJanitor)
        addShadow(card, 12, 0.5, activePopoverJanitor)
        card.Size = UDim2.new(0, size.X, 0, size.Y)
        card.ZIndex = 20

        if modal then
            card.AnchorPoint = Vector2.new(0.5, 0.5)
            card.Position = UDim2.fromScale(0.5, 0.5)
        else
            local abs = anchor.AbsolutePosition
            local anchorSize = anchor.AbsoluteSize
            local camera = getCamera()
            local viewport = camera and camera.ViewportSize or Vector2.new(800, 600)
            local _, top, _, bottom = getSafeMargin()
            local edge = Config.DragEdgeMargin
            local gap = Config.PopoverGap
            local x = math.clamp(abs.X, edge, math.max(edge, viewport.X - size.X - edge))
            local y = abs.Y + anchorSize.Y + gap
            if y + size.Y > viewport.Y - bottom then
                y = abs.Y - size.Y - gap
            end
            y = math.max(y, top + edge)
            card.Position = UDim2.new(0, x, 0, y)
        end

        activePopoverJanitor:Add(scrim.Activated:Connect(dismissOverlay))
        return card, activePopoverJanitor
    end

    ------------------------------------------------------------
    -- 2.12 下拉选择
    ------------------------------------------------------------
    local function makeDropdown(parent, janitor, options, default, callback)
        options = options or {}
        local current = default
        if current == nil then
            current = options[1]
        end

        local button = new("TextButton", {
            Name = "Dropdown",
            Text = "",
            BackgroundColor3 = Palette.Surface,
            BackgroundTransparency = 0.1,
            AutoButtonColor = false,
            BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, math.max(32, spacing().row - 4)),
        }, parent)
        local corner = new("UICorner", { CornerRadius = UDim.new(0, 10) }, button)

        local selectedLabel = makeLabel(button, tostring(current or ""), 14, "Text", {
            TextXAlignment = Enum.TextXAlignment.Left,
            Position = UDim2.new(0, 10, 0, 0),
            Size = UDim2.new(1, -34, 1, 0),
        }, janitor)
        makeLabel(button, "▾", 14, "SubText", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -10, 0.5, 0),
            Size = UDim2.new(0, 16, 1, 0),
        }, janitor)

        janitor:Add(button.Activated:Connect(function()
            if #options == 0 then
                return
            end

            local itemHeight = Config.PopoverItemHeight
            local itemGap = Config.PopoverItemGap
            local totalHeight = #options * itemHeight + math.max(0, #options - 1) * itemGap
            local cardHeight = math.min(totalHeight + 12, Config.PopoverMaxHeight)

            local width = math.max(button.AbsoluteSize.X, 140)
            local card = createPopover(button, Vector2.new(width, cardHeight), false)
            local popJanitor = activePopoverJanitor

            local scroll = new("ScrollingFrame", {
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                Size = UDim2.new(1, -12, 1, -12),
                Position = UDim2.new(0, 6, 0, 6),
                CanvasSize = UDim2.new(0, 0, 0, totalHeight),
                AutomaticCanvasSize = Enum.AutomaticSize.None,
                ScrollBarThickness = 3,
                ScrollBarImageColor3 = Palette.Accent,
            }, card)
            new("UIListLayout", { Padding = UDim.new(0, itemGap) }, scroll)

            for _, option in ipairs(options) do
                local item = new("TextButton", {
                    Text = tostring(option),
                    Font = currentFont(),
                    TextSize = 13,
                    TextColor3 = option == current and Palette.Card or Palette.Text,
                    BackgroundColor3 = option == current and Palette.Accent or Palette.Surface,
                    BackgroundTransparency = option == current and 0 or 0.2,
                    AutoButtonColor = false,
                    BorderSizePixel = 0,
                    Size = UDim2.new(1, -6, 0, itemHeight),
                }, scroll)
                new("UICorner", { CornerRadius = UDim.new(0, 8) }, item)
                registerText(item, popJanitor)

                local captured = option
                popJanitor:Add(item.Activated:Connect(function()
                    current = captured
                    selectedLabel.Text = tostring(captured)
                    if callback then
                        callback(captured)
                    end
                    dismissOverlay()
                end))
            end
        end))

        bindRefresh(function()
            button.BackgroundColor3 = Palette.Surface
            corner.CornerRadius = UDim.new(0, math.max(6, spacing().corner - 4))
        end, function()
            return button.Parent ~= nil
        end, janitor)

        return {
            Get = function() return current end,
            Set = function(value)
                current = value
                selectedLabel.Text = tostring(value or "")
            end,
        }
    end

    ------------------------------------------------------------
    -- 2.13 颜色拾取器
    ------------------------------------------------------------
    local PRESET_COLORS = {
        Color3.fromRGB(181, 0, 255), Color3.fromRGB(139, 124, 246),
        Color3.fromRGB(124, 170, 255), Color3.fromRGB(236, 121, 210),
        Color3.fromRGB(108, 212, 196), Color3.fromRGB(245, 168, 120),
        Color3.fromRGB(238, 114, 114), Color3.fromRGB(120, 200, 120),
    }

    local function makeColorPicker(parent, janitor, default, callback)
        local working = default or Palette.Accent

        local trigger = new("TextButton", {
            Name = "ColorPicker",
            Text = "",
            BackgroundColor3 = working,
            AutoButtonColor = false,
            BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, math.max(32, spacing().row - 4)),
        }, parent)
        local corner = new("UICorner", { CornerRadius = UDim.new(0, 10) }, trigger)
        new("UIStroke", { Color = Palette.Stroke, Transparency = 0.3 }, trigger)

        janitor:Add(trigger.Activated:Connect(function()
            local card = createPopover(trigger, Vector2.new(240, 300), true)
            local popJanitor = activePopoverJanitor

            local preview = new("Frame", {
                BackgroundColor3 = working,
                Size = UDim2.new(1, -20, 0, 32),
                Position = UDim2.new(0, 10, 0, 10),
                BorderSizePixel = 0,
            }, card)
            new("UICorner", { CornerRadius = UDim.new(0, 10) }, preview)

            local grid = new("Frame", {
                BackgroundTransparency = 1,
                Position = UDim2.new(0, 10, 0, 50),
                Size = UDim2.new(1, -20, 0, 52),
            }, card)
            new("UIGridLayout", {
                CellSize = UDim2.new(0, 34, 0, 24),
                CellPadding = UDim2.new(0, 5, 0, 4),
                HorizontalAlignment = Enum.HorizontalAlignment.Left,
            }, grid)
            for _, color in ipairs(PRESET_COLORS) do
                local swatch = new("TextButton", {
                    Text = "",
                    BackgroundColor3 = color,
                    AutoButtonColor = false,
                    BorderSizePixel = 0,
                }, grid)
                new("UICorner", { CornerRadius = UDim.new(0, 8) }, swatch)
                popJanitor:Add(swatch.Activated:Connect(function()
                    working = color
                    preview.BackgroundColor3 = color
                end))
            end

            local channels = new("Frame", {
                BackgroundTransparency = 1,
                Position = UDim2.new(0, 10, 0, 110),
                Size = UDim2.new(1, -20, 0, 130),
            }, card)
            new("UIListLayout", { Padding = UDim.new(0, 4) }, channels)

            local r, g, b = working.R * 255, working.G * 255, working.B * 255
            local function syncPreview()
                working = Color3.fromRGB(
                    math.clamp(math.round(r), 0, 255),
                    math.clamp(math.round(g), 0, 255),
                    math.clamp(math.round(b), 0, 255)
                )
                preview.BackgroundColor3 = working
            end

            makeSlider(channels, popJanitor, {
                label = "R", min = 0, max = 255, default = r,
                callback = function(v) r = v; syncPreview() end,
            })
            makeSlider(channels, popJanitor, {
                label = "G", min = 0, max = 255, default = g,
                callback = function(v) g = v; syncPreview() end,
            })
            makeSlider(channels, popJanitor, {
                label = "B", min = 0, max = 255, default = b,
                callback = function(v) b = v; syncPreview() end,
            })

            local actions = new("Frame", {
                BackgroundTransparency = 1,
                Position = UDim2.new(0, 10, 1, -40),
                Size = UDim2.new(1, -20, 0, 30),
            }, card)

            local cancelWrap = new("Frame", {
                BackgroundTransparency = 1,
                Size = UDim2.new(0.5, -4, 1, 0),
            }, actions)
            makeButton(cancelWrap, popJanitor, "取消", dismissOverlay)

            local confirmWrap = new("Frame", {
                BackgroundTransparency = 1,
                AnchorPoint = Vector2.new(1, 0),
                Position = UDim2.new(1, 0, 0, 0),
                Size = UDim2.new(0.5, -4, 1, 0),
            }, actions)
            makeButton(confirmWrap, popJanitor, "确认", function()
                trigger.BackgroundColor3 = working
                if callback then
                    callback(working)
                end
                dismissOverlay()
            end)
        end))

        bindRefresh(function()
            corner.CornerRadius = UDim.new(0, math.max(6, spacing().corner - 4))
        end, function()
            return trigger.Parent ~= nil
        end, janitor)

        return {
            Get = function() return working end,
            Render = function(color)
                if color then
                    working = color
                end
                trigger.BackgroundColor3 = working
            end,
        }
    end

    ------------------------------------------------------------
    -- 2.14 窗口拖拽
    ------------------------------------------------------------
    local windowDragRegistry = {}
    local activeDragCount = 0
    local dragPending = false

    local function beginDrag()
        activeDragCount = activeDragCount + 1
    end

    local function endDrag()
        if activeDragCount > 0 then
            activeDragCount = activeDragCount - 1
        end
    end

    local function windowDragger(handle, target, janitor, onMoved, onTap)
        local activeInput = nil
        local startPointer = Vector2.zero
        local startCenter = Vector2.zero
        local desired = nil
        local movedDistance = 0

        -- 目标若挂在带 UIScale 的容器里，屏幕像素位移必须除以缩放值
        local function dragScale()
            local parent = target.Parent
            if parent then
                local uiScale = parent:FindFirstChildOfClass("UIScale")
                if uiScale and uiScale.Scale and uiScale.Scale > 0 then
                    return uiScale.Scale
                end
            end
            return 1
        end

        janitor:Add(handle.InputBegan:Connect(function(input)
            if (input.UserInputType == MOUSE_BUTTON or input.UserInputType == TOUCH)
                and not activeInput then
                activeInput = input
                movedDistance = 0
                beginDrag()
                startPointer = Vector2.new(input.Position.X, input.Position.Y)
                local pos, size = target.AbsolutePosition, target.AbsoluteSize
                startCenter = Vector2.new(pos.X + size.X / 2, pos.Y + size.Y / 2)
                target.AnchorPoint = Vector2.new(0.5, 0.5)
            end
        end))

        janitor:Add(UserInputService.InputChanged:Connect(function(input)
            if input ~= activeInput then
                return
            end
            local pointer = Vector2.new(input.Position.X, input.Position.Y)
            local cx = startCenter.X + pointer.X - startPointer.X
            local cy = startCenter.Y + pointer.Y - startPointer.Y

            movedDistance = math.max(movedDistance,
                (Vector2.new(pointer.X, pointer.Y) - startPointer).Magnitude)

            local camera = getCamera()
            if camera then
                local vp = camera.ViewportSize
                local _, top, _, bottom = getSafeMargin()
                local halfW, halfH = target.AbsoluteSize.X / 2, target.AbsoluteSize.Y / 2
                local factor = Config.DragClampFactor
                cx = math.clamp(cx, halfW * factor, math.max(halfW * factor, vp.X - halfW * factor))
                cy = math.clamp(cy, top + halfH * factor,
                    math.max(top + halfH * factor, vp.Y - bottom - halfH * factor))
            end
            local scale = math.max(0.01, dragScale())
            desired = UDim2.new(0, cx / scale, 0, cy / scale)
            dragPending = true
        end))

        janitor:Add(UserInputService.InputEnded:Connect(function(input)
            if input ~= activeInput then
                return
            end
            activeInput = nil
            endDrag()
            if onTap and movedDistance <= Config.TapThreshold then
                onTap()
            end
        end))

        janitor:Add(UserInputService.WindowFocusReleased:Connect(function()
            if activeInput then
                activeInput = nil
                endDrag()
            end
            desired = nil
            movedDistance = 0
        end))

        table.insert(windowDragRegistry, function()
            if desired then
                target.Position = desired
                if onMoved then
                    onMoved(desired)
                end
                desired = nil
                return true
            end
            return false
        end)
    end

    ------------------------------------------------------------
    -- 2.15 根容器 / 主窗口 / 群公告
    ------------------------------------------------------------
    local RootJanitor = Janitor()
    RootJanitor:Add(dismissOverlay)

    -- 构建耗时较长时可能已被新一次注入取代，此处再确认一次运行号
    if runtime.XLTranslatorRunId ~= RUN_ID then
        return nil
    end

    -- 把上一份面板的连接统一回收，避免重复注入后旧连接继续响应输入
    if type(runtime.XLTranslatorCleanup) == "function" then
        pcall(runtime.XLTranslatorCleanup)
    end
    runtime.XLTranslatorCleanup = function()
        pcall(function()
            RootJanitor:Cleanup()
        end)
    end

    local ScreenGui = new("ScreenGui", {
        Name = PANEL_ID,
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        DisplayOrder = 1000,
    }, PlayerGui)

    -- 缩放根：锚点居中，缩放时窗口不会偏移出屏（原实现缺居中锚点会偏到一侧）
    local ContentRoot = new("Frame", {
        Name = "ContentRoot",
        BackgroundTransparency = 1,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromScale(1, 1),
        ZIndex = 1,
    }, ScreenGui)
    local rootScale = new("UIScale", { Scale = computeUIScale() }, ContentRoot)

    local MainWindow = glassFrame("MainWindow", ContentRoot, 0.06, RootJanitor)
    addShadow(MainWindow, 16, 0.5, RootJanitor)
    MainWindow.AnchorPoint = Vector2.new(0.5, 0.5)
    MainWindow.Position = UDim2.fromScale(0.5, 0.5)
    MainWindow.Size = UDim2.fromScale(0.94, 0.82)
    new("UISizeConstraint", {
        MinSize = Vector2.new(320, 280),
        MaxSize = Vector2.new(600, 460),
    }, MainWindow)

    -- 顶层浮层挂 ScreenGui，不参与缩放，选择器绝对坐标才准确
    OverlayLayer = new("Frame", {
        Name = "OverlayLayer",
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1),
        ZIndex = 5,
    }, ScreenGui)

    -- 通知容器独立于主窗口，最小化时仍可见；不跟随缩放，避免跑到屏幕外
    local topLeftInset = GuiService:GetGuiInset()
    local notifyTop = 12 + (topLeftInset and topLeftInset.Y or 0)
    local NotifyHolder = new("Frame", {
        Name = "NotifyHolder",
        BackgroundTransparency = 1,
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -12, 0, notifyTop),
        Size = UDim2.new(0, 270, 1, -24 - notifyTop),
        ZIndex = 8,
    }, ScreenGui)
    new("UIListLayout", {
        Padding = UDim.new(0, 8),
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
        VerticalAlignment = Enum.VerticalAlignment.Top,
    }, NotifyHolder)

    ------------------------------------------------------------
    -- 2.16 标题栏
    ------------------------------------------------------------
    local TitleBar = new("Frame", {
        BackgroundColor3 = Palette.Surface,
        BackgroundTransparency = 0.15,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 40),
    }, MainWindow)
    new("UICorner", { CornerRadius = UDim.new(0, 14) }, TitleBar)
    local TitleBarFill = new("Frame", {
        BackgroundColor3 = Palette.Surface,
        BackgroundTransparency = 0.15,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.new(1, 0, 0.5, 0),
    }, TitleBar)

    bindRefresh(function()
        TitleBar.BackgroundColor3 = Palette.Surface
        TitleBarFill.BackgroundColor3 = Palette.Surface
    end, nil, RootJanitor)

    makeLabel(TitleBar, "XL 翻译器", 15, "Text", {
        TextXAlignment = Enum.TextXAlignment.Left,
        Position = UDim2.new(0, 14, 0, 0),
        Size = UDim2.new(1, -110, 1, 0),
    }, RootJanitor)

    local MinButton = new("TextButton", {
        Text = "—", Font = currentFont(), TextSize = 16,
        TextColor3 = Palette.Text, BackgroundColor3 = Palette.Card,
        BackgroundTransparency = 0.35, AutoButtonColor = true,
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -40, 0.5, 0),
        Size = UDim2.new(0, 24, 0, 24), BorderSizePixel = 0,
    }, TitleBar)
    new("UICorner", { CornerRadius = UDim.new(1, 0) }, MinButton)
    registerText(MinButton, RootJanitor)

    local CloseButton = new("TextButton", {
        Text = "×", Font = currentFont(), TextSize = 16,
        TextColor3 = Palette.Text, BackgroundColor3 = Palette.Card,
        BackgroundTransparency = 0.35, AutoButtonColor = true,
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0),
        Size = UDim2.new(0, 24, 0, 24), BorderSizePixel = 0,
    }, TitleBar)
    new("UICorner", { CornerRadius = UDim.new(1, 0) }, CloseButton)
    registerText(CloseButton, RootJanitor)

    bindRefresh(function()
        MinButton.BackgroundColor3 = Palette.Card
        MinButton.TextColor3 = Palette.Text
        CloseButton.BackgroundColor3 = Palette.Card
        CloseButton.TextColor3 = Palette.Text
    end, nil, RootJanitor)

    ------------------------------------------------------------
    -- 2.17 群公告（固定在标题栏正下方，点击复制群号）
    ------------------------------------------------------------
    local GROUP_NUMBER = "1127732624"

    local GroupBanner = new("TextButton", {
        Name = "GroupBanner",
        Text = "QQ群号：1127732624　有需要的加，群内可解卡",
        Font = currentFont(),
        TextSize = 12,
        TextColor3 = Palette.SubText,
        BackgroundColor3 = Palette.CardTint,
        BackgroundTransparency = 0.35,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Position = UDim2.new(0, 10, 0, 44),
        Size = UDim2.new(1, -20, 0, 24),
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, MainWindow)
    new("UICorner", { CornerRadius = UDim.new(0, 8) }, GroupBanner)
    local bannerStroke = new("UIStroke", {
        Color = Palette.Accent, Thickness = 1, Transparency = 0.65,
    }, GroupBanner)
    registerText(GroupBanner, RootJanitor)

    bindRefresh(function()
        GroupBanner.BackgroundColor3 = Palette.CardTint
        GroupBanner.TextColor3 = Palette.SubText
        bannerStroke.Color = Palette.Accent
    end, nil, RootJanitor)

    ------------------------------------------------------------
    -- 2.18 标签栏与页面容器
    ------------------------------------------------------------
    local TabBar = new("Frame", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 10, 0, 76),
        Size = UDim2.new(0, 118, 1, -86),
    }, MainWindow)
    new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, TabBar)

    local ContentHolder = new("Frame", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 136, 0, 76),
        Size = UDim2.new(1, -146, 1, -86),
    }, MainWindow)

    local TabNames = { "首页", "搜索", "翻译", "设置" }
    local tabButtons, tabPages = {}, {}
    local currentTab = 3

    local function selectTab(index)
        if not tabButtons[index] or not tabPages[index] then
            return
        end
        currentTab = index
        for i = 1, #TabNames do
            local selected = (i == index)
            tabButtons[i].BackgroundColor3 = selected and Palette.Accent or Palette.Card
            tabButtons[i].BackgroundTransparency = selected and 0.1 or 1
            tabButtons[i].TextColor3 = selected and Palette.Card or Palette.Text
            tabPages[i].Visible = selected
        end
    end

    for index, tabName in ipairs(TabNames) do
        local button = new("TextButton", {
            Name = "Tab_" .. tabName,
            Text = tabName, Font = currentFont(), TextSize = 14,
            TextColor3 = Palette.Text, BackgroundColor3 = Palette.Card,
            BackgroundTransparency = 1, BorderSizePixel = 0,
            AutoButtonColor = false, Size = UDim2.new(1, 0, 0, 34),
            LayoutOrder = index,
        }, TabBar)
        new("UICorner", { CornerRadius = UDim.new(0, 10) }, button)
        registerText(button, RootJanitor)
        RootJanitor:Add(button.Activated:Connect(function()
            selectTab(index)
        end))
        tabButtons[index] = button

        local page = new("ScrollingFrame", {
            Name = "Page_" .. tabName,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Visible = false,
            Size = UDim2.fromScale(1, 1),
            CanvasSize = UDim2.new(),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            ScrollBarThickness = 3,
            ScrollBarImageColor3 = Palette.Accent,
            ClipsDescendants = true,
        }, ContentHolder)
        new("UIListLayout", {
            Padding = UDim.new(0, 10),
            HorizontalAlignment = Enum.HorizontalAlignment.Left,
        }, page)
        tabPages[index] = page
    end

    selectTab(currentTab)

    bindRefresh(function()
        selectTab(currentTab)
    end, nil, RootJanitor)

    ------------------------------------------------------------
    -- 2.19 最小化悬浮球
    ------------------------------------------------------------
    local FloatingOrb = new("TextButton", {
        Name = "FloatingOrb",
        Text = "XL", Font = Enum.Font.GothamBold, TextSize = 14,
        TextColor3 = Palette.Card, BackgroundColor3 = Palette.Accent,
        AutoButtonColor = false, Size = UDim2.new(0, 48, 0, 48),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(1, -36, 0.5, 0),
        Visible = false,
        ZIndex = 9,
    }, ScreenGui)
    new("UICorner", { CornerRadius = UDim.new(1, 0) }, FloatingOrb)
    addShadow(FloatingOrb, 10, 0.45, RootJanitor)

    bindRefresh(function()
        FloatingOrb.BackgroundColor3 = Palette.Accent
        FloatingOrb.TextColor3 = Palette.Card
    end, nil, RootJanitor)

    -- 拖拽心跳：仅在拖拽中或存在待应用位移时才同步位置
    local renderConnection
    renderConnection = RunService.RenderStepped:Connect(function()
        if not ScreenGui.Parent then
            renderConnection:Disconnect()
            return
        end

        if activeDragCount <= 0 and not dragPending then
            return
        end

        for _, flush in ipairs(windowDragRegistry) do
            pcall(flush)
        end
        dragPending = false
    end)
    RootJanitor:Add(renderConnection)

    windowDragger(TitleBar, MainWindow, RootJanitor)

    local function restoreWindow()
        MainWindow.Visible = true
        FloatingOrb.Visible = false
    end
    windowDragger(FloatingOrb, FloatingOrb, RootJanitor, nil, restoreWindow)

    RootJanitor:Add(MinButton.Activated:Connect(function()
        MainWindow.Visible = false
        FloatingOrb.Visible = true
    end))

    RootJanitor:Add(CloseButton.Activated:Connect(function()
        RootJanitor:Cleanup()
        pcall(function() ScreenGui:Destroy() end)
    end))

    ------------------------------------------------------------
    -- 2.20 通知
    ------------------------------------------------------------
    local NOTIFY_STYLES = {
        success = { color = Color3.fromRGB(96, 196, 132), icon = "✓" },
        warning = { color = Color3.fromRGB(238, 180, 82),  icon = "!" },
        error   = { color = Color3.fromRGB(232, 102, 102), icon = "✕" },
        info    = { color = nil,                          icon = "i" },
    }

    local function Notify(title, message, kind, duration)
        if not ScreenGui.Parent then
            return
        end

        local style = NOTIFY_STYLES[kind] or NOTIFY_STYLES.info
        local accentColor = style.color or Palette.Accent

        local cardJanitor = Janitor()
        local card = glassFrame("Notify", NotifyHolder, 0.05, cardJanitor)
        cardJanitor:Add(card)
        addShadow(card, 10, 0.55, cardJanitor)
        card.Size = UDim2.new(1, 0, 0, 62)
        card.ZIndex = 8

        local cleanupHook = function()
            cardJanitor:Cleanup()
        end
        RootJanitor:Add(cleanupHook)

        local bar = new("Frame", {
            BackgroundColor3 = accentColor,
            BorderSizePixel = 0,
            Position = UDim2.new(0, 0, 0, 10),
            Size = UDim2.new(0, 4, 1, -20),
        }, card)
        new("UICorner", { CornerRadius = UDim.new(1, 0) }, bar)

        local iconLabel = makeLabel(card, style.icon, 16, accentColor, {
            Position = UDim2.new(0, 12, 0, 8), Size = UDim2.new(0, 20, 0, 20),
        }, cardJanitor)

        -- 主题切换后，色条与图标同步换成新强调色
        bindRefresh(function()
            local live = NOTIFY_STYLES[kind] or NOTIFY_STYLES.info
            local color = live.color or Palette.Accent
            bar.BackgroundColor3 = color
            iconLabel.TextColor3 = color
        end, function()
            return card.Parent ~= nil
        end, cardJanitor)

        local titleLabel = makeLabel(card, title, 14, "Text", {
            TextXAlignment = Enum.TextXAlignment.Left,
            TextWrapped = false,
            Position = UDim2.new(0, 38, 0, 8), Size = UDim2.new(1, -64, 0, 18),
        }, cardJanitor)
        ellipsize(titleLabel, tostring(title or ""), 200)

        makeLabel(card, tostring(message or ""), 12, "SubText", {
            TextXAlignment = Enum.TextXAlignment.Left,
            Position = UDim2.new(0, 38, 0, 28), Size = UDim2.new(1, -50, 0, 28),
        }, cardJanitor)

        local close = new("TextButton", {
            Text = "×", Font = currentFont(), TextSize = 14,
            TextColor3 = Palette.SubText, BackgroundTransparency = 1,
            AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 6),
            Size = UDim2.new(0, 20, 0, 20),
        }, card)
        registerText(close, cardJanitor)

        local popScale = new("UIScale", { Scale = Config.NotifySlideOffset }, card)
        tween(popScale, Config.AnimNotifyIn, { Scale = 1 })

        local alive = true
        local function remove()
            if not alive then
                return
            end
            alive = false

            if not card.Parent or not popScale.Parent then
                cardJanitor:Cleanup()
                RootJanitor:Untrack(cleanupHook)
                return
            end

            tween(popScale, Config.AnimNotifyOut, { Scale = Config.NotifyExitScale })
            tween(card, Config.AnimNotifyOut, { BackgroundTransparency = 1 })
            task.delay(Config.Animations and Config.AnimNotifyOut or 0, function()
                cardJanitor:Cleanup()
                RootJanitor:Untrack(cleanupHook)
            end)
        end

        cardJanitor:Add(close.Activated:Connect(remove))
        task.delay(duration or Config.NotifyDuration, remove)
    end

    -- 通知的业务包装：任何异常都不允许打断主流程
    local function safeNotify(title, message, kind, duration)
        local ok, err = pcall(Notify, title, message, kind, duration)
        if not ok then
            warn("[XLTranslator] 通知渲染异常: " .. tostring(err))
        end
    end

    ------------------------------------------------------------
    -- 2.21 功能搜索索引
    ------------------------------------------------------------
    local searchIndex = {}

    local function registerSearch(name, kind, focusFn)
        table.insert(searchIndex, {
            name = name,
            kind = kind,
            focus = focusFn,
        })
    end

    ------------------------------------------------------------
    -- 2.22 翻译核心：分段 / 多引擎 / 覆盖率
    ------------------------------------------------------------
    local TRANS_ERROR_COLOR = Color3.fromRGB(232, 102, 102)
    local TRANS_OK_COLOR    = Color3.fromRGB(96, 196, 132)

    -- 单次请求的字节预算：过长会被接口截断，出现「只翻了一半」
    local TRANS_BREAK_MARKS = { "。", "！", "？", "，", "；", "：", "、", "…", "!", "?", ".", ",", ";", ":" }

    -- 落在多字节字符中间时，回退到该字符的起始字节
    local function alignToCharStart(text, pos)
        if pos <= 1 then
            return 1
        end
        local byte = string.byte(text, pos)
        if not byte or byte < 0x80 or byte > 0xBF then
            return pos
        end
        local cursor = pos
        while cursor > 1 do
            local prev = string.byte(text, cursor)
            if prev and prev >= 0x80 and prev <= 0xBF then
                cursor = cursor - 1
            else
                break
            end
        end
        return cursor
    end

    local function splitText(text, limit)
        limit = limit or Config.TransChunkSize
        if not limit or limit < 16 then
            limit = 16
        end

        local chunks = {}
        local total = #text
        local start = 1

        while start <= total do
            local remain = total - start + 1
            if remain <= limit then
                table.insert(chunks, string.sub(text, start, total))
                break
            end

            local windowEnd = start + limit - 1
            local cut

            -- 1) 换行最贴近原文结构
            for index = windowEnd, start, -1 do
                if string.byte(text, index) == 10 then
                    cut = index
                    break
                end
            end

            -- 2) 中英文标点，切在标点之后
            if not cut then
                for index = windowEnd, start, -1 do
                    local tail = string.sub(text, index - 2, index)
                    local matched = false
                    for _, mark in ipairs(TRANS_BREAK_MARKS) do
                        if tail == mark then
                            matched = true
                            break
                        end
                    end
                    if matched then
                        cut = index
                        break
                    end

                    local code = string.byte(text, index)
                    if code == 32 or code == 44 or code == 46 or code == 59
                        or code == 33 or code == 63 then
                        cut = index
                        break
                    end
                end
            end

            -- 3) 找不到边界才硬切
            if not cut then
                cut = windowEnd
            end

            local nextStart = alignToCharStart(text, cut + 1)
            if nextStart <= start then
                nextStart = cut + 1
                while nextStart <= total do
                    local code = string.byte(text, nextStart)
                    if code and code >= 0x80 and code <= 0xBF then
                        nextStart = nextStart + 1
                    else
                        break
                    end
                end
            end

            table.insert(chunks, string.sub(text, start, nextStart - 1))
            start = nextStart
        end

        if #chunks == 0 then
            table.insert(chunks, text)
        end
        return chunks
    end

    local function decodeEntities(text)
        local map = {
            ["&quot;"] = '"', ["&#39;"] = "'", ["&apos;"] = "'", ["&#x27;"] = "'",
            ["&amp;"] = "&", ["&lt;"] = "<", ["&gt;"] = ">", ["&nbsp;"] = " ",
        }
        return (string.gsub(text, "&[#%w]+;", function(entity)
            local named = map[entity]
            if named then
                return named
            end

            -- 数字实体（&#8230; / &#x2026;）也还原，接口偶尔会返回
            local body = string.sub(entity, 2, -2)
            if string.sub(body, 1, 1) == "#" then
                local value = string.sub(body, 2)
                local number
                if string.match(value, "^[xX]") then
                    number = tonumber(string.sub(value, 2), 16)
                else
                    number = tonumber(value)
                end
                if number and number > 0 and number <= 0x10FFFF then
                    local ok, char = pcall(utf8.char, number)
                    if ok and char then
                        return char
                    end
                end
            end

            return entity
        end))
    end

    -- 源语言探测：mymemory 不支持 auto，必须给出具体代码
    local function detectLangByText(text)
        local cjk, kana, hangul, cyrillic = false, false, false, false
        local ok = pcall(function()
            for _, code in utf8.codes(text) do
                if code >= 0x3040 and code <= 0x30FF then
                    kana = true
                elseif code >= 0xAC00 and code <= 0xD7A3 then
                    hangul = true
                elseif code >= 0x4E00 and code <= 0x9FFF then
                    cjk = true
                elseif code >= 0x0400 and code <= 0x04FF then
                    cyrillic = true
                end
            end
        end)
        if not ok then
            return "en"
        end
        if kana then
            return "ja"
        elseif hangul then
            return "ko"
        elseif cjk then
            return "zh-CN"
        elseif cyrillic then
            return "ru"
        end
        return "en"
    end

    ------------------------------------------------------------
    -- 网络层：执行器扩展优先，失败再退回 HttpService
    ------------------------------------------------------------
    local function httpGetText(url)
        -- 先走执行器 HttpGet（只传 URL，兼容性最好）；失败再退回 HttpService
        local ok, body = pcall(function()
            return game:HttpGet(url)
        end)
        if ok and type(body) == "string" and #body > 0 then
            return body
        end

        ok, body = pcall(function()
            return HttpService:GetAsync(url, true)
        end)
        if ok and type(body) == "string" and #body > 0 then
            return body
        end

        return nil
    end

    ------------------------------------------------------------
    -- 解析层
    ------------------------------------------------------------
    -- gtx: [[["译文","原文",...],...],null,"en",...]
    local function parseGoogleSingle(body)
        local ok, decoded = pcall(function()
            return HttpService:JSONDecode(body)
        end)

        if ok and type(decoded) == "table" and type(decoded[1]) == "table" then
            local parts = {}
            for _, segment in ipairs(decoded[1]) do
                if type(segment) == "table" and type(segment[1]) == "string" then
                    table.insert(parts, segment[1])
                end
            end
            if #parts > 0 then
                local detected = type(decoded[3]) == "string" and decoded[3] or nil
                return table.concat(parts), detected
            end
        end

        -- 正则兜底：结构异常时至少保住第一段，避免整次作废
        local fallback = string.match(body, '%[%[%["(.-)"')
        return fallback, nil
    end

    -- clients5 镜像: [["译文","en"],...]
    local function parseDictChrome(body)
        local ok, decoded = pcall(function()
            return HttpService:JSONDecode(body)
        end)
        if not ok or type(decoded) ~= "table" then
            return nil
        end

        local parts = {}
        for _, segment in ipairs(decoded) do
            if type(segment) == "table" and type(segment[1]) == "string" then
                table.insert(parts, segment[1])
            elseif type(segment) == "string" then
                table.insert(parts, segment)
            end
        end
        if #parts == 0 then
            return nil
        end
        return table.concat(parts)
    end

    -- mymemory: { responseData = { translatedText = "..." } }
    local function parseMyMemory(body)
        local ok, decoded = pcall(function()
            return HttpService:JSONDecode(body)
        end)
        if not ok or type(decoded) ~= "table" or type(decoded.responseData) ~= "table" then
            return nil, "返回结构异常"
        end

        local text = decoded.responseData.translatedText
        if type(text) ~= "string" or #text == 0 then
            return nil, "空译文"
        end
        -- 配额 / 长度超限时接口会把提示语当译文返回，必须识别为失败
        if string.find(text, "MYMEMORY WARNING", 1, true)
            or string.find(text, "QUERY LENGTH LIMIT", 1, true) then
            return nil, "接口限流或长度超限"
        end

        return decodeEntities(text)
    end

    ------------------------------------------------------------
    -- URL 构造
    ------------------------------------------------------------
    local function buildGoogleUrl(text, sourceCode, targetCode)
        return "https://translate.googleapis.com/translate_a/single?client=gtx&sl="
            .. sourceCode .. "&tl=" .. targetCode .. "&dt=t&q=" .. HttpService:UrlEncode(text)
    end

    local function buildMirrorUrl(text, sourceCode, targetCode)
        return "https://clients5.google.com/translate_a/t?client=dict-chrome-ex&sl="
            .. sourceCode .. "&tl=" .. targetCode .. "&q=" .. HttpService:UrlEncode(text)
    end

    local function buildMyMemoryUrl(text, sourceCode, targetCode)
        local source = sourceCode
        if source == "auto" then
            source = detectLangByText(text)
        end
        if source == targetCode then
            return nil
        end
        return "https://api.mymemory.translated.net/get?q="
            .. HttpService:UrlEncode(text)
            .. "&langpair=" .. HttpService:UrlEncode(source .. "|" .. targetCode)
    end

    ------------------------------------------------------------
    -- 节流：两次请求之间保持最小间隔（用墙钟 tick，os.clock 是 CPU 时间会算错）
    ------------------------------------------------------------
    local lastRequestClock = 0

    local function throttleRequest()
        local gap = math.max(0, Config.TransInterval)
        if gap > 0 then
            local remain = lastRequestClock + gap - tick()
            if remain > 0 then
                task.wait(remain)
            end
        end
        lastRequestClock = tick()
    end

    ------------------------------------------------------------
    -- 三个引擎的调用封装：统一返回 译文 或 nil, 原因
    ------------------------------------------------------------
    local function gtxTranslate(chunk, sourceCode, targetCode)
        throttleRequest()
        local body = httpGetText(buildGoogleUrl(chunk, sourceCode, targetCode))
        if not body then
            return nil, "gtx 无响应"
        end
        local text, detected = parseGoogleSingle(body)
        if not text or text == "" then
            return nil, "gtx 解析为空"
        end
        return decodeEntities(text), nil, detected
    end

    local function mirrorTranslate(chunk, sourceCode, targetCode)
        throttleRequest()
        local body = httpGetText(buildMirrorUrl(chunk, sourceCode, targetCode))
        if not body then
            return nil, "镜像无响应"
        end
        local text = parseDictChrome(body)
        if not text or text == "" then
            return nil, "镜像解析为空"
        end
        return decodeEntities(text)
    end

    local function myMemoryTranslate(chunk, sourceCode, targetCode)
        local url = buildMyMemoryUrl(chunk, sourceCode, targetCode)
        if not url then
            return chunk -- 已是目标语言，原样返回，不发请求
        end
        throttleRequest()
        local body = httpGetText(url)
        if not body then
            return nil, "mymemory 无响应"
        end
        local text, err = parseMyMemory(body)
        if not text then
            return nil, err or "mymemory 解析失败"
        end
        return text
    end

    local ENGINES = {
        { name = "gtx",      fn = gtxTranslate },
        { name = "mirror",   fn = mirrorTranslate },
        { name = "mymemory", fn = myMemoryTranslate },
    }

    ------------------------------------------------------------
    -- 缓存：按「分段 + 语言对」存储，FIFO 淘汰
    ------------------------------------------------------------
    local transCache, transCacheOrder = {}, {}

    local function cacheGet(key)
        return transCache[key]
    end

    local function cachePut(key, value)
        if transCache[key] == nil then
            table.insert(transCacheOrder, key)
        end
        transCache[key] = value

        while #transCacheOrder > Config.TransCacheLimit do
            local oldest = table.remove(transCacheOrder, 1)
            if oldest then
                transCache[oldest] = nil
            end
        end
    end

    ------------------------------------------------------------
    -- 单段翻译：三引擎依次尝试，每个引擎两次机会
    ------------------------------------------------------------
    local function translateChunk(chunk, sourceCode, targetCode, deadEngines)
        local lastError = "无可用引擎"

        -- 本轮已被判定不可用的引擎直接跳过，避免整篇逐段重复超时
        local alive = 0
        for _, engine in ipairs(ENGINES) do
            if not (deadEngines and deadEngines[engine.name]) then
                alive = alive + 1
            end
        end
        if alive == 0 then
            return nil, "全部引擎不可用"
        end

        for _, engine in ipairs(ENGINES) do
            if not (deadEngines and deadEngines[engine.name]) then
                for attempt = 1, 2 do
                    local ok, text, err = pcall(engine.fn, chunk, sourceCode, targetCode)
                    if ok and type(text) == "string" and #text > 0 then
                        return text, engine.name
                    end

                    lastError = tostring(err or text)
                    if attempt < 2 then
                        task.wait(0.3)
                    end
                end

                if deadEngines then
                    -- 两次都失败，本轮不再尝试该引擎
                    deadEngines[engine.name] = true
                end
            end
        end

        return nil, lastError
    end

    ------------------------------------------------------------
    -- 全量翻译：逐段翻译 + 原序拼接；失败段保留原文并计数
    ------------------------------------------------------------
    local function translateText(text, sourceCode, targetCode, onProgress)
        local chunks = splitText(text, Config.TransChunkSize)
        local total = #chunks
        local parts = {}
        local failedFlags = {}
        local failed = 0
        local cachedHits = 0
        local firstError = nil
        local deadEngines = {}

        local function reportProgress(index)
            if onProgress then
                local ok, err = pcall(onProgress, index, total)
                if not ok then
                    warn("[XLTranslator] 进度回调异常: " .. tostring(err))
                end
            end
        end

        for index, chunk in ipairs(chunks) do
            if not chunk or chunk == "" or string.gsub(chunk, "%s", "") == "" then
                -- 纯空白段不请求，原样保留
                table.insert(parts, chunk)
            else
                local key = sourceCode .. ">" .. targetCode .. "|" .. chunk
                local cached = cacheGet(key)

                if cached then
                    table.insert(parts, cached)
                    cachedHits = cachedHits + 1
                else
                    local piece, engineName = translateChunk(chunk, sourceCode, targetCode, deadEngines)
                    if piece and piece ~= "" then
                        cachePut(key, piece)
                        table.insert(parts, piece)
                    else
                        -- 全部引擎失败：保留原文并计入漏译，绝不静默丢弃
                        table.insert(parts, chunk)
                        failed = failed + 1
                        failedFlags[index] = true
                        if not firstError then
                            firstError = engineName
                        end
                    end
                end
            end

            reportProgress(index)
        end

        -- 第二遍：只补译失败段。先用第一段做探针，链路仍不可用时立刻停止，不再逐段空等
        local retried = 0
        if failed > 0 and failed < total then
            local probeIndex = nil
            for index = 1, total do
                if failedFlags[index] then
                    probeIndex = index
                    break
                end
            end

            if probeIndex then
                task.wait(0.6)
                deadEngines = {}

                local probe = translateChunk(chunks[probeIndex], sourceCode, targetCode, deadEngines)
                if probe and probe ~= "" then
                    local key = sourceCode .. ">" .. targetCode .. "|" .. chunks[probeIndex]
                    cachePut(key, probe)
                    parts[probeIndex] = probe
                    failedFlags[probeIndex] = nil
                    failed = failed - 1
                    retried = retried + 1

                    for index, chunk in ipairs(chunks) do
                        if failedFlags[index] then
                            local piece = translateChunk(chunk, sourceCode, targetCode, deadEngines)
                            if piece and piece ~= "" then
                                cachePut(sourceCode .. ">" .. targetCode .. "|" .. chunk, piece)
                                parts[index] = piece
                                failedFlags[index] = nil
                                failed = failed - 1
                                retried = retried + 1
                            end
                        end
                    end
                end
            end
        end

        -- 原序拼接：中日韩直接相连，拉丁语系在缺失空白处补一个空格
        local targetIsCJK = (targetCode == "zh-CN" or targetCode == "ja" or targetCode == "ko")
        local buffer = {}
        for index, part in ipairs(parts) do
            table.insert(buffer, part)
            local nextPart = parts[index + 1]
            if nextPart and not targetIsCJK then
                local tail = string.sub(part, -1)
                local head = string.sub(nextPart, 1, 1)
                if tail ~= "" and head ~= "" and tail ~= " " and head ~= " "
                    and tail ~= "\n" and head ~= "\n" then
                    table.insert(buffer, " ")
                end
            end
        end

        local result = table.concat(buffer)

        return {
            ok = (failed == 0),
            text = result,
            failed = failed,
            total = total,
            cachedHits = cachedHits,
            retried = retried,
            error = firstError,
        }
    end

    ------------------------------------------------------------
    -- 引擎自检：逐个接口发一条短请求，把结果写回界面
    ------------------------------------------------------------
    local engineCheckReport = nil

    local function runEngineCheck(onDone)
        task.spawn(function()
            local report = {}

            for _, engine in ipairs(ENGINES) do
                local started = tick()
                local ok, text, err = pcall(engine.fn, "Hello world", "en", "zh-CN")
                local elapsed = tick() - started
                local success = ok and type(text) == "string" and #text > 0
                local detail = success and tostring(text) or tostring(err or text or "无返回")
                if #detail > 80 then
                    detail = string.sub(detail, 1, 80) .. "…"
                end
                table.insert(report, {
                    name = engine.name,
                    success = success,
                    elapsed = elapsed,
                    detail = detail,
                })
                task.wait(0.3)
            end

            engineCheckReport = report
            if onDone then
                pcall(onDone, report)
            end
        end)
    end

    ------------------------------------------------------------
    -- 前置声明：首页回调会用到，实体在翻译页内定义
    ------------------------------------------------------------
    local copyToClipboard
    local transInputFocus

    ------------------------------------------------------------
    -- 2.23 首页：概览 / 引擎自检 / 使用提示
    ------------------------------------------------------------
    local HomePage = tabPages[1]

    local homeCard = glassFrame("HomeCard", HomePage, 0.12, RootJanitor)
    homeCard.Size = UDim2.new(1, -6, 0, 0)
    homeCard.AutomaticSize = Enum.AutomaticSize.Y
    new("UIPadding", {
        PaddingTop = UDim.new(0, 12), PaddingBottom = UDim.new(0, 12),
        PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12),
    }, homeCard)
    new("UIListLayout", { Padding = UDim.new(0, 10) }, homeCard)

    makeLabel(homeCard, "XL 翻译器 · Ultra", 16, "Text", {
        TextXAlignment = Enum.TextXAlignment.Left, Size = UDim.new(1, 0, 0, 22),
    }, RootJanitor)

    makeLabel(homeCard,
        "长文本自动分段、多引擎降级；失败段会先自动补译一次，仍有漏译则保留原文并计数。",
        12, "SubText", {
        TextXAlignment = Enum.TextXAlignment.Left,
        TextWrapped = true,
        Size = UDim2.new(1, 0, 0, 60),
    }, RootJanitor)

    makeButton(homeCard, RootJanitor, "进入翻译", function()
        selectTab(3)
        pcall(function() transInputFocus() end)
    end)

    local homeCheckStatus = makeLabel(homeCard, "接口自检：未运行", 12, "SubText", {
        TextXAlignment = Enum.TextXAlignment.Left,
        TextWrapped = true,
        Size = UDim2.new(1, 0, 0, 56),
    }, RootJanitor)

    makeButton(homeCard, RootJanitor, "检测翻译接口", function()
        homeCheckStatus.Text = "接口自检：请求中…"
        homeCheckStatus.TextColor3 = Palette.SubText
        runEngineCheck(function(report)
            local lines = {}
            local allOk = true
            for _, item in ipairs(report) do
                table.insert(lines, string.format("%s %s %.2fs",
                    item.name, item.success and "✓" or "✕", item.elapsed))
                if not item.success then
                    allOk = false
                end
            end
            homeCheckStatus.Text = "接口自检：" .. table.concat(lines, "  ")
            homeCheckStatus.TextColor3 = allOk and TRANS_OK_COLOR or TRANS_ERROR_COLOR
            safeNotify("接口自检", allOk and "全部引擎可达" or "部分引擎不可达，翻译会自动降级",
                allOk and "success" or "warning", 4)
        end)
    end)

    local homeGroupCard = glassFrame("HomeGroup", HomePage, 0.12, RootJanitor)
    homeGroupCard.Size = UDim2.new(1, -6, 0, 0)
    homeGroupCard.AutomaticSize = Enum.AutomaticSize.Y
    new("UIPadding", {
        PaddingTop = UDim.new(0, 12), PaddingBottom = UDim.new(0, 12),
        PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12),
    }, homeGroupCard)
    new("UIListLayout", { Padding = UDim.new(0, 8) }, homeGroupCard)

    makeLabel(homeGroupCard, "交流群", 15, "Text", {
        TextXAlignment = Enum.TextXAlignment.Left, Size = UDim.new(1, 0, 0, 20),
    }, RootJanitor)
    makeLabel(homeGroupCard, "QQ群号：1127732624", 14, "Accent", {
        TextXAlignment = Enum.TextXAlignment.Left, Size = UDim.new(1, 0, 0, 20),
    }, RootJanitor)
    makeLabel(homeGroupCard, "有需要的加，群内可解卡", 12, "SubText", {
        TextXAlignment = Enum.TextXAlignment.Left, Size = UDim.new(1, 0, 0, 18),
    }, RootJanitor)
    makeButton(homeGroupCard, RootJanitor, "复制群号", function()
        if copyToClipboard(GROUP_NUMBER) then
            safeNotify("已复制", "群号 " .. GROUP_NUMBER .. " 已写入剪贴板", "success", 3)
        else
            safeNotify("请手动复制", "群号：" .. GROUP_NUMBER, "warning", 4)
        end
    end)

    registerSearch("进入翻译", "首页", function() selectTab(3) end)
    registerSearch("检测翻译接口", "首页 · 自检", function() selectTab(1) end)
    registerSearch("交流群", "首页", function() selectTab(1) end)

    ------------------------------------------------------------
    -- 2.24 搜索页
    ------------------------------------------------------------
    local SearchPage = tabPages[2]

    makeLabel(SearchPage, "功能搜索", 15, "Text", {
        TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, -6, 0, 20),
    }, RootJanitor)

    local searchBox = makeInput(SearchPage, RootJanitor, "输入关键词，如 翻译 / 主题 / 通知…", "", nil)
    searchBox.Size = UDim2.new(1, -6, 0, 34)

    local resultHolder = new("Frame", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -6, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
    }, SearchPage)
    new("UIListLayout", { Padding = UDim.new(0, 6) }, resultHolder)

    local resultJanitor = Janitor()

    local function clearResults()
        resultJanitor:Cleanup()
        resultJanitor = Janitor()
        for _, child in ipairs(resultHolder:GetChildren()) do
            pcall(function() child:Destroy() end)
        end
    end

    local function runSearch(keyword)
        clearResults()
        local word = string.lower(tostring(keyword or ""))
        if word == "" then
            return
        end

        local matched = 0
        for _, entry in ipairs(searchIndex) do
            if string.find(string.lower(entry.name), word, 1, true)
                or string.find(string.lower(entry.kind), word, 1, true) then
                matched = matched + 1
                local result = new("TextButton", {
                    Text = "",
                    BackgroundColor3 = Palette.Surface,
                    BackgroundTransparency = 0.15,
                    AutoButtonColor = false,
                    BorderSizePixel = 0,
                    Size = UDim2.new(1, 0, 0, 38),
                }, resultHolder)
                new("UICorner", { CornerRadius = UDim.new(0, 10) }, result)
                bindRefresh(function()
                    result.BackgroundColor3 = Palette.Surface
                end, function()
                    return result.Parent ~= nil
                end, resultJanitor)
                makeLabel(result, entry.name, 14, "Text", {
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Position = UDim2.new(0, 10, 0, 4), Size = UDim2.new(1, -70, 0, 16),
                }, resultJanitor)
                makeLabel(result, entry.kind, 12, "SubText", {
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Position = UDim2.new(0, 10, 0, 20), Size = UDim2.new(1, -20, 0, 14),
                }, resultJanitor)

                resultJanitor:Add(result.Activated:Connect(function()
                    local ok, err = pcall(entry.focus)
                    if not ok then
                        warn("[XLTranslator] 搜索定位失败: " .. tostring(err))
                    end
                    safeNotify("已定位", entry.name, "success", 2)
                end))

                if matched >= 12 then
                    break
                end
            end
        end

        if matched == 0 then
            makeLabel(resultHolder, "未找到匹配的功能", 13, "SubText", {
                Size = UDim2.new(1, 0, 0, 24),
            }, resultJanitor)
        end
    end

    RootJanitor:Add(searchBox:GetPropertyChangedSignal("Text"):Connect(function()
        runSearch(searchBox.Text)
    end))

    ------------------------------------------------------------
    -- 2.25 控件状态同步器（导入配置后反写界面显示）
    ------------------------------------------------------------
    local uiSyncers = {}

    local function addSyncer(fn)
        table.insert(uiSyncers, fn)
    end

    local function syncUIState()
        for _, fn in ipairs(uiSyncers) do
            local ok, err = pcall(fn)
            if not ok then
                warn("[XLTranslator] 控件同步异常: " .. tostring(err))
            end
        end
    end

    ------------------------------------------------------------
    -- 2.26 翻译页
    ------------------------------------------------------------
    local TranslatePage = tabPages[3]

    local TRANS_TARGETS = {
        { label = "中文（简体）", code = "zh-CN" },
        { label = "英文",         code = "en" },
        { label = "日文",         code = "ja" },
        { label = "韩文",         code = "ko" },
        { label = "俄文",         code = "ru" },
        { label = "法文",         code = "fr" },
        { label = "德文",         code = "de" },
        { label = "西班牙文",     code = "es" },
    }

    local TRANS_SOURCES = {
        { label = "自动检测", code = "auto" },
        { label = "中文",     code = "zh-CN" },
        { label = "英文",     code = "en" },
        { label = "日文",     code = "ja" },
    }

    local function transLabelList(list)
        local labels = {}
        for index, item in ipairs(list) do
            labels[index] = item.label
        end
        return labels
    end

    local function transCodeOf(list, label)
        for _, item in ipairs(list) do
            if item.label == label then
                return item.code
            end
        end
        return list[1].code
    end

    local function transLabelOf(list, code)
        for _, item in ipairs(list) do
            if item.code == code then
                return item.label
            end
        end
        return list[1].label
    end

    -- 按字符（非字节）截断，避免把中文 / 日文切成半个字
    local function shortText(text, limit)
        local length = utf8.len(text)
        if not length or length <= limit then
            return text
        end
        local cut = utf8.offset(text, limit + 1)
        if not cut then
            return text
        end
        return string.sub(text, 1, cut - 1) .. "…"
    end

    local transState = {
        Source   = Config.TransSource or "auto",
        Target   = Config.TransTarget or "zh-CN",
        AutoCopy = Config.TransAutoCopy ~= false,
        Busy     = false,
    }

    local transHistory = {}
    local renderHistory

    -- 剪贴板：多级回退，取不到权限时由界面提示手动复制
    copyToClipboard = function(text)
        if type(text) ~= "string" or text == "" then
            return false
        end

        local candidates = {}
        if type(setclipboard) == "function" then table.insert(candidates, setclipboard) end
        if type(toclipboard) == "function" then table.insert(candidates, toclipboard) end
        if type(writeclipboard) == "function" then table.insert(candidates, writeclipboard) end
        if #candidates == 0 then
            return false
        end

        for _, fn in ipairs(candidates) do
            local ok = pcall(fn, text)
            if ok then
                return true
            end
        end
        return false
    end

    ------------------------------------------------------------
    -- 输入卡片
    ------------------------------------------------------------
    local transInputCard = glassFrame("TransInput", TranslatePage, 0.12, RootJanitor)
    transInputCard.Size = UDim2.new(1, -6, 0, 0)
    transInputCard.AutomaticSize = Enum.AutomaticSize.Y
    new("UIPadding", {
        PaddingTop = UDim.new(0, 12), PaddingBottom = UDim.new(0, 12),
        PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12),
    }, transInputCard)
    new("UIListLayout", { Padding = UDim.new(0, 10) }, transInputCard)

    local transInputHead = new("Frame", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 18),
    }, transInputCard)
    makeLabel(transInputHead, "源文本", 14, "Text", {
        TextXAlignment = Enum.TextXAlignment.Left,
        Size = UDim2.new(0.5, 0, 1, 0),
    }, RootJanitor)

    local transCounter = makeLabel(transInputHead, "0 / " .. tostring(Config.TransMaxChars), 12, "SubText", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, 0, 0, 0),
        Size = UDim2.new(0.5, 0, 1, 0),
        TextXAlignment = Enum.TextXAlignment.Right,
    }, RootJanitor)

    local transInput = makeTextArea(transInputCard, RootJanitor,
        "粘贴或输入要翻译的内容…", "", 96, false)

    local function updateCounter()
        local length = utf8.len(transInput.Text) or #transInput.Text
        transCounter.Text = length .. " / " .. Config.TransMaxChars
        if length > Config.TransMaxChars then
            transCounter.TextColor3 = TRANS_ERROR_COLOR
        else
            transCounter.TextColor3 = Palette.SubText
        end
    end

    RootJanitor:Add(transInput:GetPropertyChangedSignal("Text"):Connect(updateCounter))
    bindRefresh(updateCounter, nil, RootJanitor)

    -- 按钮行：两枚等宽按钮
    local function makeActionRow(parent, leftText, leftCallback, rightText, rightCallback)
        local row = new("Frame", {
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 34),
        }, parent)
        new("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            Padding = UDim.new(0, 8),
            VerticalAlignment = Enum.VerticalAlignment.Center,
        }, row)

        local left = makeButton(row, RootJanitor, leftText, leftCallback,
            { Size = UDim2.new(0.5, -4, 1, 0) })
        local right = makeButton(row, RootJanitor, rightText, rightCallback,
            { Size = UDim2.new(0.5, -4, 1, 0) })
        return left, right
    end

    local runTranslate

    local transButton = makeActionRow(transInputCard,
        "开始翻译", function()
            runTranslate()
        end,
        "清空", function()
            transInput.Text = ""
            updateCounter()
        end)

    transInputFocus = function()
        pcall(function() transInput:CaptureFocus() end)
    end

    ------------------------------------------------------------
    -- 语言与请求卡片
    ------------------------------------------------------------
    local transLangCard = glassFrame("TransOptions", TranslatePage, 0.12, RootJanitor)
    transLangCard.Size = UDim2.new(1, -6, 0, 0)
    transLangCard.AutomaticSize = Enum.AutomaticSize.Y
    new("UIPadding", {
        PaddingTop = UDim.new(0, 12), PaddingBottom = UDim.new(0, 12),
        PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12),
    }, transLangCard)
    new("UIListLayout", { Padding = UDim.new(0, 8) }, transLangCard)

    makeLabel(transLangCard, "语言与请求", 14, "Text", {
        TextXAlignment = Enum.TextXAlignment.Left,
        Size = UDim2.new(1, 0, 0, 18),
    }, RootJanitor)

    makeLabel(transLangCard, "源语言", 12, "SubText", {
        TextXAlignment = Enum.TextXAlignment.Left,
        Size = UDim2.new(1, 0, 0, 14),
    }, RootJanitor)

    local transSourceDropdown = makeDropdown(transLangCard, RootJanitor,
        transLabelList(TRANS_SOURCES), transLabelOf(TRANS_SOURCES, transState.Source),
        function(choice)
            transState.Source = transCodeOf(TRANS_SOURCES, choice)
            Config.TransSource = transState.Source
        end)

    makeLabel(transLangCard, "目标语言", 12, "SubText", {
        TextXAlignment = Enum.TextXAlignment.Left,
        Size = UDim2.new(1, 0, 0, 14),
    }, RootJanitor)

    local transTargetDropdown = makeDropdown(transLangCard, RootJanitor,
        transLabelList(TRANS_TARGETS), transLabelOf(TRANS_TARGETS, transState.Target),
        function(choice)
            transState.Target = transCodeOf(TRANS_TARGETS, choice)
            Config.TransTarget = transState.Target
        end)

    local transIntervalSlider = makeSlider(transLangCard, RootJanitor, {
        label = "请求间隔 (秒)",
        min = 0, max = 3, decimals = 1,
        default = Config.TransInterval,
        callback = function(value)
            Config.TransInterval = value
        end,
    })

    local transAutoToggle = makeToggle(transLangCard, RootJanitor, "翻译后自动复制",
        transState.AutoCopy, function(state)
            transState.AutoCopy = state
            Config.TransAutoCopy = state
        end)

    addSyncer(function()
        transSourceDropdown.Set(transLabelOf(TRANS_SOURCES, transState.Source))
    end)
    addSyncer(function()
        transTargetDropdown.Set(transLabelOf(TRANS_TARGETS, transState.Target))
    end)
    addSyncer(function()
        transIntervalSlider.Set(Config.TransInterval)
    end)
    addSyncer(function()
        transAutoToggle.Set(transState.AutoCopy)
    end)

    ------------------------------------------------------------
    -- 结果卡片
    ------------------------------------------------------------
    local transResultCard = glassFrame("TransResult", TranslatePage, 0.12, RootJanitor)
    transResultCard.Size = UDim2.new(1, -6, 0, 0)
    transResultCard.AutomaticSize = Enum.AutomaticSize.Y
    new("UIPadding", {
        PaddingTop = UDim.new(0, 12), PaddingBottom = UDim.new(0, 12),
        PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12),
    }, transResultCard)
    new("UIListLayout", { Padding = UDim.new(0, 8) }, transResultCard)

    local transResultHead = new("Frame", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 18),
    }, transResultCard)
    makeLabel(transResultHead, "译文", 14, "Text", {
        TextXAlignment = Enum.TextXAlignment.Left,
        Size = UDim2.new(1, 0, 1, 0),
    }, RootJanitor)

    -- 状态单独占一整行：窄屏下不再被「译文」标题挤掉
    local transStatus = makeLabel(transResultCard, "待翻译", 11, "SubText", {
        TextXAlignment = Enum.TextXAlignment.Left,
        TextWrapped = true,
        Size = UDim2.new(1, 0, 0, 30),
    }, RootJanitor)

    local transOutput = makeTextArea(transResultCard, RootJanitor,
        "译文会显示在这里，可手动选中复制", "", 110, true)

    -- 剪贴板不可用时，把结果全选，至少能长按复制
    local function selectOutputAll()
        pcall(function()
            transOutput.TextEditable = true
            transOutput:CaptureFocus()
            transOutput.SelectionStart = 1
            transOutput.CursorPosition = #transOutput.Text + 1
        end)
    end

    makeActionRow(transResultCard,
        "复制译文", function()
            local text = transOutput.Text
            if not text or text == "" then
                safeNotify("没有内容", "先翻译一次再复制", "warning", 2)
                return
            end
            if copyToClipboard(text) then
                safeNotify("已复制", "译文已写入剪贴板", "success", 2)
            else
                selectOutputAll()
                safeNotify("需要手动复制", "当前环境没有剪贴板权限，结果已全选，请长按复制", "warning", 3)
            end
        end,
        "清空结果", function()
            transOutput.Text = ""
            transStatus.Text = "待翻译"
            transStatus.TextColor3 = Palette.SubText
        end)

    makeLabel(transResultCard, "最近记录", 12, "SubText", {
        TextXAlignment = Enum.TextXAlignment.Left,
        Size = UDim2.new(1, 0, 0, 16),
    }, RootJanitor)

    local historyHolder = new("Frame", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
    }, transResultCard)
    new("UIListLayout", { Padding = UDim.new(0, 6) }, historyHolder)

    local historyEmpty = makeLabel(historyHolder, "翻译一次后，这里会出现最近记录", 12, "SubText", {
        TextXAlignment = Enum.TextXAlignment.Left,
        Size = UDim2.new(1, 0, 0, 18),
        LayoutOrder = 0,
    }, RootJanitor)

    local historyConnections = {}
    RootJanitor:Add(function()
        for _, connection in ipairs(historyConnections) do
            pcall(function() connection:Disconnect() end)
        end
        table.clear(historyConnections)
    end)

    makeLabel(transResultCard,
        "失败段会自动补译一次；仍有漏译时再点「开始翻译」，只补失败段（已翻段命中缓存）。",
        12, "SubText", {
        TextXAlignment = Enum.TextXAlignment.Left,
        TextWrapped = true,
        Size = UDim2.new(1, 0, 0, 48),
    }, RootJanitor)

    renderHistory = function()
        for _, connection in ipairs(historyConnections) do
            pcall(function() connection:Disconnect() end)
        end
        table.clear(historyConnections)

        for _, child in ipairs(historyHolder:GetChildren()) do
            if child:IsA("TextButton") then
                pcall(function() child:Destroy() end)
            end
        end

        historyEmpty.Visible = (#transHistory == 0)

        for index, item in ipairs(transHistory) do
            local entry = new("TextButton", {
                Name = "HistoryItem",
                Text = "",
                BackgroundColor3 = Palette.Surface,
                BackgroundTransparency = 0.3,
                BorderSizePixel = 0,
                AutoButtonColor = false,
                Size = UDim2.new(1, 0, 0, 30),
                LayoutOrder = index,
            }, historyHolder)
            new("UICorner", { CornerRadius = UDim.new(0, 8) }, entry)

            new("TextLabel", {
                Text = shortText(item.result, 26),
                Font = currentFont(),
                TextSize = 12,
                TextColor3 = Palette.Text,
                BackgroundTransparency = 1,
                TextXAlignment = Enum.TextXAlignment.Left,
                Position = UDim2.new(0, 10, 0, 0),
                Size = UDim2.new(1, -20, 1, 0),
            }, entry)

            local captured = item
            table.insert(historyConnections, entry.Activated:Connect(function()
                transInput.Text = captured.source
                transOutput.Text = captured.result
                updateCounter()
                transStatus.Text = "已载入历史"
                transStatus.TextColor3 = Palette.SubText
            end))
        end
    end

    renderHistory()

    bindRefresh(function()
        for _, child in ipairs(historyHolder:GetChildren()) do
            if child:IsA("TextButton") then
                child.BackgroundColor3 = Palette.Surface
                for _, label in ipairs(child:GetChildren()) do
                    if label:IsA("TextLabel") then
                        label.TextColor3 = Palette.Text
                        label.Font = currentFont()
                    end
                end
            end
        end
        historyEmpty.TextColor3 = Palette.SubText
        if not transState.Busy then
            transStatus.TextColor3 = Palette.SubText
        end
    end, function()
        return historyHolder.Parent ~= nil
    end, RootJanitor)

    ------------------------------------------------------------
    -- 执行流程
    ------------------------------------------------------------
    runTranslate = function()
        if transState.Busy then
            safeNotify("正在翻译", "上一轮还没结束，请稍候", "warning", 2)
            return
        end

        local text = transInput.Text or ""
        if string.gsub(text, "%s", "") == "" then
            safeNotify("无法翻译", "请先输入要翻译的文本", "warning", 2)
            transInputFocus()
            return
        end

        local length = utf8.len(text) or #text
        if length > Config.TransMaxChars then
            safeNotify("文本过长",
                "最多 " .. Config.TransMaxChars .. " 字符，当前 " .. length, "warning", 3)
            return
        end

        transState.Busy = true
        transButton.Text = "翻译中…"
        transStatus.Text = "准备请求…"
        transStatus.TextColor3 = Palette.SubText

        task.spawn(function()
            local started = tick()

            local callOk, outcome = pcall(translateText, text,
                transState.Source, transState.Target,
                function(done, total)
                    if total > 1 then
                        transStatus.Text = "翻译中 " .. done .. "/" .. total .. " 段"
                    else
                        transStatus.Text = "请求中…"
                    end
                end)

            transState.Busy = false

            -- 界面已被关闭时直接收尾，不再回写已销毁的控件
            if not ScreenGui.Parent then
                return
            end

            transButton.Text = "开始翻译"

            if not callOk then
                transStatus.Text = "内部错误"
                transStatus.TextColor3 = TRANS_ERROR_COLOR
                transOutput.Text = "翻译流程异常：" .. tostring(outcome)
                safeNotify("翻译异常", tostring(outcome), "error", 4)
                return
            end

            if not outcome then
                transStatus.Text = "失败"
                transStatus.TextColor3 = TRANS_ERROR_COLOR
                safeNotify("翻译失败", "接口无有效返回", "error", 4)
                return
            end

            local elapsed = string.format("%.2f", tick() - started)
            transOutput.Text = outcome.text or ""

            local total = outcome.total or 0
            local failed = outcome.failed or 0
            local cachedHits = outcome.cachedHits or 0
            local retried = outcome.retried or 0

            if failed > 0 and failed >= total then
                -- 全部失败：仍把原文放出来，用户不至于丢失内容
                transStatus.Text = "全部失败 · " .. elapsed .. "s"
                transStatus.TextColor3 = TRANS_ERROR_COLOR
                safeNotify("翻译失败",
                    "接口全部不可用，已保留原文（" .. tostring(outcome.error or "未知原因") .. "）",
                    "error", 5)
                return
            end

            local statusParts = {}
            if failed > 0 then
                table.insert(statusParts, "共 " .. total .. " 段 · 漏译 " .. failed .. " 段")
            elseif cachedHits > 0 and cachedHits == total then
                table.insert(statusParts, "缓存命中 " .. cachedHits .. " 段")
            else
                table.insert(statusParts, "共 " .. total .. " 段")
            end
            if retried > 0 then
                table.insert(statusParts, "自动补译 " .. retried .. " 段")
            end
            table.insert(statusParts, "耗时 " .. elapsed .. "s")
            table.insert(statusParts, (utf8.len(outcome.text) or #outcome.text) .. " 字符")

            transStatus.Text = table.concat(statusParts, " · ")
            transStatus.TextColor3 = failed > 0 and Color3.fromRGB(238, 180, 82) or Palette.SubText

            table.insert(transHistory, 1, { source = text, result = outcome.text })
            while #transHistory > Config.TransHistoryLimit do
                table.remove(transHistory)
            end
            renderHistory()

            if failed > 0 then
                local message = failed .. " / " .. total .. " 段仍保留原文，可再次点击开始翻译重试"
                if retried > 0 then
                    message = "已自动补译 " .. retried .. " 段，" .. message
                end
                safeNotify("部分片段未翻译", message, "warning", 5)
            elseif transState.AutoCopy then
                if copyToClipboard(outcome.text) then
                    safeNotify("翻译成功", "已复制到剪贴板 · " .. elapsed .. "s", "success", 3)
                else
                    safeNotify("翻译成功",
                        "当前环境没有剪贴板权限，可手动复制结果", "warning", 4)
                end
            else
                safeNotify("翻译成功", "耗时 " .. elapsed .. " 秒", "success", 2)
            end
        end)
    end

    registerSearch("文本翻译", "翻译", function()
        selectTab(3)
        transInputFocus()
    end)
    registerSearch("目标语言", "翻译", function() selectTab(3) end)
    registerSearch("翻译历史", "翻译", function() selectTab(3) end)
    registerSearch("请求间隔", "翻译", function() selectTab(3) end)
    registerSearch("自动复制", "翻译", function() selectTab(3) end)

    ------------------------------------------------------------
    -- 2.27 分组折叠（修复原版缺少 UIListLayout 导致内容压住标题）
    ------------------------------------------------------------
    local function makeGroup(parent, title, buildContent)
        local card = glassFrame("Group", parent, 0.12, RootJanitor)
        card.Size = UDim2.new(1, -6, 0, 0)
        card.AutomaticSize = Enum.AutomaticSize.Y

        new("UIListLayout", {
            Padding = UDim.new(0, 0),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }, card)

        local header = new("TextButton", {
            Text = "",
            BackgroundTransparency = 1,
            AutoButtonColor = false,
            Size = UDim2.new(1, 0, 0, 36),
            BorderSizePixel = 0,
            LayoutOrder = 1,
        }, card)
        makeLabel(header, title, 14, "Text", {
            TextXAlignment = Enum.TextXAlignment.Left,
            Position = UDim2.new(0, 12, 0, 0), Size = UDim2.new(1, -40, 1, 0),
        }, RootJanitor)

        local arrow = makeLabel(header, "▾", 14, "SubText", {
            AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0),
            Size = UDim2.new(0, 16, 1, 0),
        }, RootJanitor)

        local content = new("Frame", {
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            LayoutOrder = 2,
        }, card)
        new("UIPadding", {
            PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12),
            PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 10),
        }, content)
        new("UIListLayout", { Padding = UDim.new(0, 10) }, content)

        local expanded = true
        RootJanitor:Add(header.Activated:Connect(function()
            expanded = not expanded
            content.Visible = expanded
            arrow.Text = expanded and "▾" or "▸"
        end))

        buildContent(content)

        return card, content, function()
            if not expanded then
                expanded = true
                content.Visible = true
                arrow.Text = "▾"
            end
        end
    end

    ------------------------------------------------------------
    -- 2.28 配置序列化与还原
    ------------------------------------------------------------
    local function serializeConfig()
        local accent = Config.Accent
        local data = {
            version = "1.0-ultra",
            theme = Config.Theme,
            accent = {
                math.round(accent.R * 255),
                math.round(accent.G * 255),
                math.round(accent.B * 255),
            },
            opacity = Config.Opacity,
            layout = Config.Layout,
            animations = Config.Animations,
            font = Config.FontName,
            scaleBoost = Config.ScaleBoost,
            trans = {
                source = transState.Source,
                target = transState.Target,
                interval = Config.TransInterval,
                autocopy = transState.AutoCopy,
            },
        }
        local ok, encoded = pcall(function()
            return HttpService:JSONEncode(data)
        end)
        return ok and encoded or "{}"
    end

    local function isFiniteNumber(value)
        return type(value) == "number" and value == value
            and value ~= math.huge and value ~= -math.huge
    end

    local function applyImportedConfig(text)
        local ok, decoded = pcall(function()
            return HttpService:JSONDecode(text or "")
        end)
        if not ok or type(decoded) ~= "table" then
            safeNotify("导入失败", "配置文本格式错误", "error", 3)
            return
        end

        if decoded.theme == "light" or decoded.theme == "dark" or decoded.theme == "xlpurple" then
            Config.Theme = decoded.theme
        end

        if type(decoded.accent) == "table" and #decoded.accent == 3 then
            local r, g, b = decoded.accent[1], decoded.accent[2], decoded.accent[3]
            if isFiniteNumber(r) and isFiniteNumber(g) and isFiniteNumber(b) then
                Config.Accent = Color3.fromRGB(
                    math.clamp(math.round(r), 0, 255),
                    math.clamp(math.round(g), 0, 255),
                    math.clamp(math.round(b), 0, 255))
            end
        end

        if isFiniteNumber(decoded.opacity) then
            Config.Opacity = math.clamp(decoded.opacity, -0.1, 0.35)
        end
        if decoded.layout == "cozy" or decoded.layout == "compact" then
            Config.Layout = decoded.layout
        end
        if type(decoded.animations) == "boolean" then
            Config.Animations = decoded.animations
        end
        if isFiniteNumber(decoded.scaleBoost) then
            Config.ScaleBoost = math.clamp(decoded.scaleBoost, -0.2, 0.2)
        end

        if type(decoded.font) == "string" then
            local valid = false
            for _, option in ipairs(FONT_OPTIONS) do
                if option.name == decoded.font then
                    valid = true
                    break
                end
            end
            Config.FontName = valid and decoded.font or "Gotham"
        end

        if type(decoded.trans) == "table" then
            local trans = decoded.trans
            if isFiniteNumber(trans.interval) then
                Config.TransInterval = math.clamp(trans.interval, 0, 3)
            end
            if type(trans.autocopy) == "boolean" then
                transState.AutoCopy = trans.autocopy
                Config.TransAutoCopy = trans.autocopy
            end
            for _, item in ipairs(TRANS_SOURCES) do
                if item.code == trans.source then
                    transState.Source = trans.source
                    Config.TransSource = trans.source
                    break
                end
            end
            for _, item in ipairs(TRANS_TARGETS) do
                if item.code == trans.target then
                    transState.Target = trans.target
                    Config.TransTarget = trans.target
                    break
                end
            end
        end

        applyPalette()
        refreshAll()
        rootScale.Scale = computeUIScale()
        syncUIState()
        safeNotify("导入成功", "界面与翻译配置已还原", "success", 3)
    end

    ------------------------------------------------------------
    -- 2.29 设置页
    ------------------------------------------------------------
    local SettingsPage = tabPages[4]

    local fontNames = {}
    for _, option in ipairs(FONT_OPTIONS) do
        table.insert(fontNames, option.name)
    end

    local expandAppearance
    do
        local _, _, expander = makeGroup(SettingsPage, "外观", function(body)
            local themeLabelOf = { light = "浅色", dark = "深色", xlpurple = "XL 紫" }
            local themeKeyOf = { ["浅色"] = "light", ["深色"] = "dark", ["XL 紫"] = "xlpurple" }

            local accentPicker

            local themeDropdown = makeDropdown(body, RootJanitor, { "浅色", "深色", "XL 紫" },
                themeLabelOf[Config.Theme] or "XL 紫", function(choice)
                    local key = themeKeyOf[choice] or "light"
                    Config.Theme = key
                    Config.Accent = THEME_ACCENTS[key] or Config.Accent
                    applyPalette()
                    refreshAll()
                    if accentPicker then
                        accentPicker.Render(Config.Accent)
                    end
                end)
            addSyncer(function()
                themeDropdown.Set(themeLabelOf[Config.Theme] or "XL 紫")
            end)

            accentPicker = makeColorPicker(body, RootJanitor, Config.Accent, function(color)
                Config.Accent = color
                applyPalette()
                refreshAll()
            end)
            addSyncer(function()
                accentPicker.Render(Config.Accent)
            end)

            local opacitySlider = makeSlider(body, RootJanitor, {
                label = "面板透明度", min = -10, max = 35,
                default = math.round(Config.Opacity * 100),
                callback = function(value)
                    Config.Opacity = value / 100
                    refreshAll()
                end,
            })
            addSyncer(function()
                opacitySlider.Set(math.round(Config.Opacity * 100))
            end)
        end)
        expandAppearance = expander
    end

    local expandLayout
    do
        local _, _, expander = makeGroup(SettingsPage, "布局", function(body)
            local layoutDropdown = makeDropdown(body, RootJanitor, { "宽松", "紧凑" },
                Config.Layout == "compact" and "紧凑" or "宽松", function(choice)
                    Config.Layout = (choice == "紧凑") and "compact" or "cozy"
                    refreshAll()
                    safeNotify("布局预设", "已切换为" .. choice .. "布局", "info", 2)
                end)
            addSyncer(function()
                layoutDropdown.Set(Config.Layout == "compact" and "紧凑" or "宽松")
            end)
        end)
        expandLayout = expander
    end

    local expandFont
    do
        local _, _, expander = makeGroup(SettingsPage, "字体", function(body)
            local fontDropdown = makeDropdown(body, RootJanitor, fontNames, Config.FontName,
                function(choice)
                    Config.FontName = choice
                    refreshAll()
                end)
            addSyncer(function()
                fontDropdown.Set(Config.FontName)
            end)
        end)
        expandFont = expander
    end

    local expandAnim
    do
        local _, _, expander = makeGroup(SettingsPage, "动画", function(body)
            local animToggle = makeToggle(body, RootJanitor, "启用过渡动画",
                Config.Animations, function(state)
                    Config.Animations = state
                    safeNotify("动画", state and "动画已开启" or "动画已关闭", "info", 2)
                end)
            addSyncer(function()
                animToggle.Set(Config.Animations)
            end)
        end)
        expandAnim = expander
    end

    local expandConfig
    do
        local _, _, expander = makeGroup(SettingsPage, "配置导入导出", function(body)
            local exportBox = new("TextBox", {
                BackgroundColor3 = Palette.Surface, BackgroundTransparency = 0.15,
                BorderSizePixel = 0, Font = Enum.Font.Code, TextSize = 11,
                TextColor3 = Palette.SubText, TextWrapped = true,
                Text = "点击下方按钮生成配置文本",
                ClearTextOnFocus = false, Size = UDim2.new(1, 0, 0, 70),
                TextEditable = false,
            }, body)
            new("UICorner", { CornerRadius = UDim.new(0, 8) }, exportBox)

            makeButton(body, RootJanitor, "导出配置", function()
                exportBox.Text = serializeConfig()
                safeNotify("导出成功", "配置文本已生成，可复制保存", "success", 2)
            end)

            local importBox = new("TextBox", {
                BackgroundColor3 = Palette.Surface, BackgroundTransparency = 0.15,
                BorderSizePixel = 0, Font = Enum.Font.Code, TextSize = 11,
                TextColor3 = Palette.Text, TextWrapped = true,
                PlaceholderText = "在此粘贴配置文本…",
                PlaceholderColor3 = Palette.Placeholder,
                Text = "", ClearTextOnFocus = false,
                Size = UDim2.new(1, 0, 0, 70),
            }, body)
            new("UICorner", { CornerRadius = UDim.new(0, 8) }, importBox)

            bindRefresh(function()
                exportBox.BackgroundColor3 = Palette.Surface
                exportBox.TextColor3 = Palette.SubText
                importBox.BackgroundColor3 = Palette.Surface
                importBox.TextColor3 = Palette.Text
                importBox.PlaceholderColor3 = Palette.Placeholder
            end, function()
                return exportBox.Parent ~= nil
            end)

            makeButton(body, RootJanitor, "导入配置", function()
                applyImportedConfig(importBox.Text)
            end)
        end)
        expandConfig = expander
    end

    local expandAbout
    do
        local _, _, expander = makeGroup(SettingsPage, "关于与群", function(body)
            makeLabel(body, "XL 翻译器 · Ultra", 14, "Text", {
                TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, 0, 0, 20),
            }, RootJanitor)
            makeLabel(body, "三引擎降级 · 长文本分段 · 漏译可见", 12, "SubText", {
                TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, 0, 0, 18),
            }, RootJanitor)
            makeLabel(body, "QQ群号：1127732624（有需要的加，群内可解卡）", 12, "Accent", {
                TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, 0, 0, 32),
            }, RootJanitor)
            makeButton(body, RootJanitor, "复制群号", function()
                if copyToClipboard(GROUP_NUMBER) then
                    safeNotify("已复制", "群号 " .. GROUP_NUMBER .. " 已写入剪贴板", "success", 3)
                else
                    safeNotify("请手动复制", "群号：" .. GROUP_NUMBER, "warning", 4)
                end
            end)
        end)
        expandAbout = expander
    end

    registerSearch("主题切换", "设置 · 外观", function()
        selectTab(4)
        expandAppearance()
    end)
    registerSearch("强调色拾取", "设置 · 外观", function()
        selectTab(4)
        expandAppearance()
    end)
    registerSearch("面板透明度", "设置 · 外观", function()
        selectTab(4)
        expandAppearance()
    end)
    registerSearch("布局预设", "设置 · 布局", function()
        selectTab(4)
        expandLayout()
    end)
    registerSearch("字体切换", "设置 · 字体", function()
        selectTab(4)
        expandFont()
    end)
    registerSearch("动画开关", "设置 · 动画", function()
        selectTab(4)
        expandAnim()
    end)
    registerSearch("配置导入导出", "设置 · 配置", function()
        selectTab(4)
        expandConfig()
    end)
    registerSearch("关于与群", "设置 · 关于", function()
        selectTab(4)
        expandAbout()
    end)

    makeLabel(SettingsPage, "PC 按 RightShift 或 K 切换显隐；手机端用悬浮球与标题栏按钮", 12, "SubText", {
        Size = UDim2.new(1, -6, 0, 32),
    }, RootJanitor)

    ------------------------------------------------------------
    -- 2.30 群公告点击复制
    ------------------------------------------------------------
    RootJanitor:Add(GroupBanner.Activated:Connect(function()
        if copyToClipboard(GROUP_NUMBER) then
            safeNotify("已复制群号", "QQ群：" .. GROUP_NUMBER, "success", 3)
        else
            safeNotify("群号", GROUP_NUMBER .. "（当前环境无剪贴板权限）", "info", 4)
        end
    end))

    ------------------------------------------------------------
    -- 2.31 PC 快捷键
    ------------------------------------------------------------
    RootJanitor:Add(UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then
            return
        end

        -- 输入框正在输入时不要抢按键
        if UserInputService.GetFocusedTextBox then
            local ok, focused = pcall(function()
                return UserInputService:GetFocusedTextBox()
            end)
            if ok and focused then
                return
            end
        end

        if input.KeyCode == Enum.KeyCode.RightShift or input.KeyCode == Enum.KeyCode.K then
            if MainWindow.Visible then
                MainWindow.Visible = false
                FloatingOrb.Visible = true
            else
                MainWindow.Visible = true
                FloatingOrb.Visible = false
            end
        end
    end))

    ------------------------------------------------------------
    -- 2.32 视口 / 相机变化时更新缩放
    ------------------------------------------------------------
    local cameraScaleConnection = nil

    local function bindScaleUpdate()
        if cameraScaleConnection then
            pcall(function() cameraScaleConnection:Disconnect() end)
            RootJanitor:Untrack(cameraScaleConnection)
            cameraScaleConnection = nil
        end

        local camera = getCamera()
        if camera then
            cameraScaleConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
                rootScale.Scale = computeUIScale()
            end)
            RootJanitor:Add(cameraScaleConnection)
        end
    end
    bindScaleUpdate()
    RootJanitor:Add(Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindScaleUpdate))

    ------------------------------------------------------------
    -- 2.33 对外接口
    ------------------------------------------------------------
    return {
        Notify = safeNotify,
        ScreenGui = ScreenGui,
        Destroy = function()
            RootJanitor:Cleanup()
            pcall(function() ScreenGui:Destroy() end)
        end,
    }
end

------------------------------------------------------------
-- 三、启动编排：加载页 → 构建 → 成功提示 / 失败重试
------------------------------------------------------------
local panel = nil
local loading = false

local function startLoad()
    if loading then
        return
    end
    loading = true
    splash.SetLoading()

    task.spawn(function()
        local begin = tick()
        local lastError = "未知错误"

        for attempt = 1, BUILD_RETRY do
            if runtime.XLTranslatorRunId ~= RUN_ID then
                return
            end

            local ok, result = pcall(buildPanel)

            if ok and type(result) == "table" then
                -- 加载动画最少展示 5 秒；构建本身更慢则以实际耗时为准
                local used = tick() - begin
                local remain = SPLASH_MIN - used
                if remain > 0 then
                    task.wait(remain)
                end

                if runtime.XLTranslatorRunId ~= RUN_ID then
                    pcall(result.Destroy)
                    return
                end

                panel = result
                loading = false

                pcall(function() splash.Destroy() end)
                pcall(result.Notify, "XL 翻译器",
                    "加载成功！按右 Shift 或 K 键可隐藏 / 显示界面。", "success", 4)
                返回返回
XL翻译器·Ultra（毛玻璃面板版）

lastError = result
警告(string.format “[XLTranslator] 第 %d 次构建失败: %s”,“[XLTranslator] 第 %d 次构建失败: %s”,
尝试，toString结果)))
如果 attempt < BUILD_RETRY，那么
                任务等待(0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)0.8)
            结束
结束结束

加载中 = 虚假
如果 runtime.XLTranslatorRunId 不等于 RUN_ID，那么
            返回返回
结束结束

        -- 构建彻底失败时清掉半成品，只保留加载页
如果 type(runtime.XLTranslatorCleanup) == “功能” 那么
pcall(runtime.XLTranslatorCleanup)
结束结束
runtime.XLTranslatorCleanup =
pcall(
            本地剩余值 = PlayerGui:FindFirstChild(PANEL_ID)
            如果有剩余的话，那么
剩余部分：Destroy()
            结束
        结束)
splash.SetFailed(lastError)
    结束)
结束

splash.BindRetry(startLoad)
startLoad()

-- 便于执行器二次调用时拿到面板对象（不做任何远程上报）
runtime.XLTranslatorPanel = {
get = 函数()
返回面板返回面板
结束，
}
