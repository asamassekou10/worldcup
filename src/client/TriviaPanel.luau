--!strict
-- TriviaPanel: the World Cup Trivia overlay, extracted out of UI.luau so the giant
-- UI.create function stays under Luau's 200-local-per-function limit. It owns its
-- own panel + the show/result/hide controls. The host (UI.create) injects styling
-- helpers + a lobby toggle and wires `onAnswer` to the network callback.

local Workspace = game:GetService("Workspace")

local Sound = require(script.Parent:WaitForChild("Sound"))

local TriviaPanel = {}

export type QuestionInfo = {
	index: number,
	total: number,
	question: string,
	options: { A: string, B: string, C: string, D: string },
	deadline: number,
	-- Duel fields (head-to-head); absent/false for a solo round.
	isDuel: boolean?,
	opponentName: string?,
	yourScore: number?,
	oppScore: number?,
}

export type Deps = {
	corner: (g: GuiObject, r: number) -> (),
	pressable: (b: GuiButton) -> (),
	setLobbyVisible: (visible: boolean) -> (),
}

export type Controller = {
	onAnswer: ((answer: string) -> ())?,
	showQuestion: (info: QuestionInfo) -> (),
	showResult: (
		correct: boolean,
		correctAnswer: string,
		timedOut: boolean,
		yourScore: number?,
		oppScore: number?
	) -> (),
	hide: () -> (),
}

local ANSWER_LETTERS = { "A", "B", "C", "D" }
local ANSWER_COLORS = {
	Color3.fromRGB(45, 80, 160),
	Color3.fromRGB(140, 60, 140),
	Color3.fromRGB(50, 120, 60),
	Color3.fromRGB(160, 90, 30),
}
function TriviaPanel.build(screen: ScreenGui, deps: Deps): Controller
	local corner = deps.corner
	local pressable = deps.pressable

	-- Declared up front so the answer buttons can read `controller.onAnswer` (set by
	-- the host) at click time; the show/result/hide methods are added below.
	local controller = { onAnswer = nil :: ((answer: string) -> ())? }

	local panel = Instance.new("Frame")
	panel.Name = "TriviaPanel"
	panel.Size = UDim2.fromScale(1, 1)
	panel.BackgroundColor3 = Color3.fromRGB(14, 16, 26)
	panel.BackgroundTransparency = 0.06
	panel.Visible = false
	panel.ZIndex = 20
	panel.Parent = screen

	local progress = Instance.new("TextLabel")
	progress.Size = UDim2.fromScale(1, 0.06)
	progress.Position = UDim2.fromScale(0, 0.03)
	progress.BackgroundTransparency = 1
	progress.Font = Enum.Font.GothamBold
	progress.TextScaled = true
	progress.TextColor3 = Color3.fromRGB(240, 200, 40)
	progress.Text = "QUESTION 1 / 5"
	progress.ZIndex = 21
	progress.Parent = panel

	-- Duel header: "🆚 Opponent · You X — Y Opp" (hidden in solo rounds).
	local versus = Instance.new("TextLabel")
	versus.Name = "Versus"
	versus.Size = UDim2.fromScale(1, 0.028)
	versus.Position = UDim2.fromScale(0, 0.072)
	versus.BackgroundTransparency = 1
	versus.Font = Enum.Font.GothamBold
	versus.TextScaled = true
	versus.TextColor3 = Color3.fromRGB(150, 210, 255)
	versus.Text = ""
	versus.Visible = false
	versus.ZIndex = 21
	versus.Parent = panel

	local currentOpp: string? = nil
	local function setVersus(yourScore: number?, oppScore: number?)
		if currentOpp then
			versus.Visible = true
			versus.Text = string.format(
				"🆚 %s   ·   You %d — %d",
				currentOpp,
				yourScore or 0,
				oppScore or 0
			)
		else
			versus.Visible = false
		end
	end

	local timerBg = Instance.new("Frame")
	timerBg.Size = UDim2.fromScale(0.88, 0.018)
	timerBg.Position = UDim2.fromScale(0.06, 0.10)
	timerBg.BackgroundColor3 = Color3.fromRGB(30, 34, 50)
	timerBg.ZIndex = 21
	corner(timerBg, 6)
	timerBg.Parent = panel

	local timerFill = Instance.new("Frame")
	timerFill.Size = UDim2.fromScale(1, 1)
	timerFill.BackgroundColor3 = Color3.fromRGB(240, 200, 40)
	timerFill.ZIndex = 22
	corner(timerFill, 6)
	timerFill.Parent = timerBg

	local question = Instance.new("TextLabel")
	question.Size = UDim2.fromScale(0.88, 0.18)
	question.Position = UDim2.fromScale(0.06, 0.13)
	question.BackgroundTransparency = 1
	question.Font = Enum.Font.GothamBold
	question.TextScaled = true
	question.TextWrapped = true
	question.TextXAlignment = Enum.TextXAlignment.Left
	question.TextColor3 = Color3.fromRGB(235, 238, 248)
	question.Text = ""
	question.ZIndex = 21
	question.Parent = panel

	local answerBtns: { TextButton } = {}
	local answerLabels: { TextLabel } = {}
	for i, letter in ANSWER_LETTERS do
		local y = 0.34 + (i - 1) * 0.145
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.fromScale(0.88, 0.12)
		btn.Position = UDim2.fromScale(0.06, y)
		btn.BackgroundColor3 = ANSWER_COLORS[i]
		btn.BackgroundTransparency = 0.15
		btn.Text = ""
		btn.ZIndex = 21
		corner(btn, 10)
		btn.Parent = panel
		pressable(btn)
		table.insert(answerBtns, btn)

		-- Letter badge pinned to the left.
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.fromScale(0.1, 1)
		lbl.BackgroundTransparency = 1
		lbl.Font = Enum.Font.GothamBlack
		lbl.TextScaled = true
		lbl.TextColor3 = Color3.fromRGB(240, 200, 40)
		lbl.Text = letter
		lbl.ZIndex = 22
		lbl.Parent = btn

		-- Option text in its OWN region to the right of the badge, so wrapped lines
		-- (long answers) never run back under the letter.
		local optLabel = Instance.new("TextLabel")
		optLabel.Size = UDim2.fromScale(0.85, 0.86)
		optLabel.Position = UDim2.fromScale(0.13, 0.07)
		optLabel.BackgroundTransparency = 1
		optLabel.Font = Enum.Font.GothamBlack
		optLabel.TextScaled = true
		optLabel.TextWrapped = true
		optLabel.TextXAlignment = Enum.TextXAlignment.Left
		optLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		optLabel.Text = ""
		optLabel.ZIndex = 22
		optLabel.Parent = btn
		table.insert(answerLabels, optLabel)

		local capturedLetter = letter
		btn.Activated:Connect(function()
			Sound.play("Click")
			if controller.onAnswer then
				controller.onAnswer(capturedLetter)
			end
			-- Dim all buttons to prevent double-submit.
			for _, b in answerBtns do
				b.BackgroundTransparency = 0.6
				b.AutoButtonColor = false
			end
		end)
	end

	local feedback = Instance.new("TextLabel")
	feedback.Size = UDim2.fromScale(0.88, 0.07)
	feedback.Position = UDim2.fromScale(0.06, 0.92)
	feedback.BackgroundTransparency = 1
	feedback.Font = Enum.Font.GothamBlack
	feedback.TextScaled = true
	feedback.TextColor3 = Color3.fromRGB(120, 230, 120)
	feedback.Text = ""
	feedback.ZIndex = 21
	feedback.Parent = panel

	local timerToken = 0

	function controller.showQuestion(info: QuestionInfo)
		deps.setLobbyVisible(false)
		panel.Visible = true

		currentOpp = info.opponentName
		setVersus(info.yourScore, info.oppScore)

		progress.Text = string.format("QUESTION %d / %d", info.index, info.total)
		question.Text = info.question

		local optList = { info.options.A, info.options.B, info.options.C, info.options.D }
		for i, btn in answerBtns do
			answerLabels[i].Text = optList[i]
			btn.BackgroundColor3 = ANSWER_COLORS[i]
			btn.BackgroundTransparency = 0.15
			btn.AutoButtonColor = true
		end
		feedback.Text = ""

		-- Animated countdown bar.
		timerToken += 1
		local tok = timerToken
		timerFill.Size = UDim2.fromScale(1, 1)
		local timeLeft = info.deadline - Workspace:GetServerTimeNow()
		local start = os.clock()
		task.spawn(function()
			while timerToken == tok and panel.Visible do
				local elapsed = os.clock() - start
				local ratio = math.clamp(1 - elapsed / timeLeft, 0, 1)
				timerFill.Size = UDim2.fromScale(ratio, 1)
				if ratio <= 0.3 then
					timerFill.BackgroundColor3 = Color3.fromRGB(220, 80, 60)
				else
					timerFill.BackgroundColor3 = Color3.fromRGB(240, 200, 40)
				end
				task.wait(0.05)
			end
		end)
	end

	function controller.showResult(
		correct: boolean,
		correctAnswer: string,
		timedOut: boolean,
		yourScore: number?,
		oppScore: number?
	)
		timerToken += 1 -- stop the timer tween
		setVersus(yourScore, oppScore) -- refresh the duel scoreline
		if timedOut then
			feedback.TextColor3 = Color3.fromRGB(220, 140, 40)
			feedback.Text = string.format("Time's up! The answer was %s", correctAnswer)
		elseif correct then
			feedback.TextColor3 = Color3.fromRGB(100, 220, 100)
			feedback.Text = string.format("Correct! +%d coins", 10)
		else
			feedback.TextColor3 = Color3.fromRGB(220, 80, 60)
			feedback.Text = string.format("Wrong — answer was %s", correctAnswer)
		end
		-- Highlight the correct button green.
		for i, btn in answerBtns do
			if ANSWER_LETTERS[i] == correctAnswer then
				btn.BackgroundColor3 = Color3.fromRGB(40, 140, 60)
				btn.BackgroundTransparency = 0
			end
		end
	end

	function controller.hide()
		panel.Visible = false
		timerToken += 1
		deps.setLobbyVisible(true)
	end

	return controller
end

return TriviaPanel
