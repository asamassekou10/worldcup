--!strict
-- TriviaService: head-to-head World Cup Trivia.
-- Tap the "TriviaKiosk" prompt to join a quick-match QUEUE. The moment a second
-- player is ready you're paired into a 5-question DUEL on the SAME questions:
-- each correct answer scores points + a SPEED bonus (faster = more), and the higher
-- total wins a coin bonus. If no opponent joins within a few seconds you fall back
-- to a SOLO round for coins, so there's always something to do.
--
-- Net payloads (all server -> client tables):
--   TriviaQuestion { index, total, question, options, deadline, isDuel,
--                    opponentName?, yourScore, oppScore }
--   TriviaResult   { correct, correctAnswer, timedOut, isDuel, yourScore, oppScore }
--   TriviaOver     { isDuel, correct, total, totalCoins, won?, tie?, yourScore,
--                    oppScore, opponentName? }
--   TriviaSubmit   client -> server { answer = "A"|"B"|"C"|"D" }

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net        = require(Shared:WaitForChild("Net"))
local TriviaBank = require(Shared:WaitForChild("TriviaBank"))
local Config     = require(Shared:WaitForChild("Config"))
local MapLayout  = require(Shared:WaitForChild("MapLayout"))

local DataService = require(script.Parent:WaitForChild("DataService"))
local Assets      = require(script.Parent:WaitForChild("Assets"))

local TriviaService = {}

local QUESTION_SECONDS = 15
local RESULT_PAUSE     = 2.6
local QUEUE_WAIT       = 6 -- seconds to wait for an opponent before the solo fallback
local COIN_CORRECT     = 10
local COIN_PERFECT     = 30 -- solo: all 5 correct
local COIN_WIN         = 50 -- duel: win bonus
local XP_CORRECT       = 5
local PTS_CORRECT      = 100 -- duel: base points for a correct answer
local PTS_SPEED        = 100 -- duel: max additional points for answering instantly

type PlayerState = {
	player: Player,
	answer: string?,
	answeredAt: number?, -- server time the answer landed (for the speed bonus)
	correctCount: number,
	points: number,
	coins: number,
}

type Session = {
	states: { PlayerState },
	isDuel: boolean,
	questions: { TriviaBank.Question },
	resolve: (() -> ())?, -- fired when everyone answered the current question (or timeout)
	answeredThisQ: number,
}

TriviaService.sessionByPlayer = {} :: { [Player]: Session }
local queue: { Player } = {}

local function notify(player: Player, message: string)
	Net.getEvent(Net.Events.Notify):FireClient(player, { message = message })
end

local function inPlay(player: Player): boolean
	return TriviaService.sessionByPlayer[player] ~= nil or table.find(queue, player) ~= nil
end

local function opponentOf(session: Session, state: PlayerState): PlayerState?
	for _, s in session.states do
		if s ~= state then
			return s
		end
	end
	return nil
end

local function aliveCount(session: Session): number
	local n = 0
	for _, s in session.states do
		if s.player.Parent == Players then
			n += 1
		end
	end
	return n
end

local function newState(player: Player): PlayerState
	return { player = player, answer = nil, answeredAt = nil, correctCount = 0, points = 0, coins = 0 }
end

local function runSession(session: Session)
	for i, q in session.questions do
		if aliveCount(session) == 0 then
			break
		end

		for _, s in session.states do
			s.answer = nil
			s.answeredAt = nil
		end
		session.answeredThisQ = 0

		local deadline = Workspace:GetServerTimeNow() + QUESTION_SECONDS
		for _, s in session.states do
			if s.player.Parent == Players then
				local opp = opponentOf(session, s)
				Net.getEvent(Net.Events.TriviaQuestion):FireClient(s.player, {
					index        = i,
					total        = #session.questions,
					question     = q.q,
					options      = q.options,
					deadline     = deadline,
					isDuel       = session.isDuel,
					opponentName = if opp then opp.player.DisplayName else nil,
					yourScore    = s.points,
					oppScore     = if opp then opp.points else 0,
				})
			end
		end

		-- Wait until everyone still here has answered, or the question times out.
		local evt = Instance.new("BindableEvent")
		local resolved = false
		local function resolve()
			if resolved then
				return
			end
			resolved = true
			evt:Fire()
		end
		session.resolve = resolve
		task.delay(QUESTION_SECONDS, resolve)
		evt.Event:Wait()
		session.resolve = nil
		evt:Destroy()

		-- Score + per-player result.
		for _, s in session.states do
			local correct = s.answer == q.answer
			if correct then
				s.correctCount += 1
				s.coins += COIN_CORRECT
				local bonus = 0
				if session.isDuel and s.answeredAt then
					local remaining = math.clamp(deadline - s.answeredAt, 0, QUESTION_SECONDS)
					bonus = math.floor((remaining / QUESTION_SECONDS) * PTS_SPEED)
				end
				s.points += PTS_CORRECT + bonus
			end
		end
		for _, s in session.states do
			if s.player.Parent == Players then
				local opp = opponentOf(session, s)
				Net.getEvent(Net.Events.TriviaResult):FireClient(s.player, {
					correct       = s.answer == q.answer,
					correctAnswer = q.answer,
					timedOut      = s.answer == nil,
					isDuel        = session.isDuel,
					yourScore     = s.points,
					oppScore      = if opp then opp.points else 0,
				})
			end
		end

		task.wait(RESULT_PAUSE)
	end

	for _, s in session.states do
		TriviaService.sessionByPlayer[s.player] = nil
	end

	if session.isDuel then
		local a, b = session.states[1], session.states[2]
		local winner: PlayerState? = nil
		if a.points > b.points then
			winner = a
		elseif b.points > a.points then
			winner = b
		end
		for _, s in session.states do
			if s.player.Parent == Players then
				local opp = opponentOf(session, s)
				local won = winner == s
				local coins = s.coins + (if won then COIN_WIN else 0)
				local xp = s.correctCount * XP_CORRECT
				if coins > 0 or xp > 0 then
					DataService.grantReward(s.player, coins, xp)
				end
				Net.getEvent(Net.Events.TriviaOver):FireClient(s.player, {
					isDuel       = true,
					won          = won,
					tie          = winner == nil,
					correct      = s.correctCount,
					total        = #session.questions,
					totalCoins   = coins,
					yourScore    = s.points,
					oppScore     = if opp then opp.points else 0,
					opponentName = if opp then opp.player.DisplayName else "Opponent",
				})
			end
		end
	else
		local s = session.states[1]
		if s.correctCount == #session.questions then
			s.coins += COIN_PERFECT
		end
		local xp = s.correctCount * XP_CORRECT
		if s.player.Parent == Players then
			if s.coins > 0 or xp > 0 then
				DataService.grantReward(s.player, s.coins, xp)
			end
			Net.getEvent(Net.Events.TriviaOver):FireClient(s.player, {
				isDuel     = false,
				correct    = s.correctCount,
				total      = #session.questions,
				totalCoins = s.coins,
			})
		end
	end
end

local function startSession(states: { PlayerState }, isDuel: boolean)
	local session: Session = {
		states        = states,
		isDuel        = isDuel,
		questions     = TriviaBank.dailySet(),
		resolve       = nil,
		answeredThisQ = 0,
	}
	for _, s in states do
		TriviaService.sessionByPlayer[s.player] = session
	end
	task.spawn(runSession, session)
end

local function joinQueue(player: Player)
	if inPlay(player) then
		return
	end
	table.insert(queue, player)
	notify(player, "🧠 Trivia: finding an opponent…")

	if #queue >= 2 then
		local a = table.remove(queue, 1) :: Player
		local b = table.remove(queue, 1) :: Player
		notify(a, "⚔️ Opponent found — good luck!")
		notify(b, "⚔️ Opponent found — good luck!")
		startSession({ newState(a), newState(b) }, true)
	else
		-- Solo fallback if still alone after the wait.
		task.delay(QUEUE_WAIT, function()
			local idx = table.find(queue, player)
			if idx then
				table.remove(queue, idx)
				notify(player, "🧠 No opponent — solo round!")
				startSession({ newState(player) }, false)
			end
		end)
	end
end

-- Called from init.server.luau when TriviaSubmit fires.
function TriviaService.submit(player: Player, payload: unknown)
	local session = TriviaService.sessionByPlayer[player]
	if not session then
		return
	end
	if typeof(payload) ~= "table" then
		return
	end
	local answer = (payload :: { [string]: unknown }).answer
	if answer ~= "A" and answer ~= "B" and answer ~= "C" and answer ~= "D" then
		return
	end

	local state: PlayerState? = nil
	for _, s in session.states do
		if s.player == player then
			state = s
		end
	end
	if not state or state.answer ~= nil then
		return -- not in this session, or already answered this question
	end
	state.answer = answer :: string
	state.answeredAt = Workspace:GetServerTimeNow()
	session.answeredThisQ += 1

	-- Everyone still here has answered -> end the question early.
	if session.answeredThisQ >= aliveCount(session) and session.resolve then
		session.resolve()
	end
end

function TriviaService.start()
	-- Runtime-only guards (plain locals, so they can NEVER be saved into the place and
	-- get stuck -- an earlier version stored the "placed" flag as a BoolValue on the
	-- marker, which a Cmd-S during play baked in, making every run skip the move/flip).
	local kioskPlaced = false
	local wiredPrompts: { [Instance]: boolean } = {}

	local function setupKiosk(part: BasePart)
		-- Move the kiosk to the activities row on the far (-side) touchline (MapLayout),
		-- drop the "Quiz Game Show" model on it, and hide the plain marker so only the
		-- model shows. (The invisible marker still carries the prompt.)
		if Config.Models.TriviaKiosk ~= 0 and not kioskPlaced then
			-- Clean up the old baked guard if it's there, plus any stale trivia model
			-- (a copy accidentally saved into the place on a previous run) so we don't
			-- end up with duplicates -- that's why the old, unmoved set kept showing.
			local oldFlag = part:FindFirstChild("_TriviaModelPlaced")
			if oldFlag then
				oldFlag:Destroy()
			end
			for _, d in Workspace:GetChildren() do
				if d.Name == "TriviaKioskModel" then
					d:Destroy()
				end
			end
			local target = MapLayout.activity("trivia") or part.CFrame
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { part }
			local hit = Workspace:Raycast(target.Position + Vector3.new(0, 80, 0), Vector3.new(0, -240, 0), params)
			local groundY = if hit then hit.Position.Y else target.Position.Y
			local base = Vector3.new(target.Position.X, groundY, target.Position.Z)
			-- Reposition the (invisible) marker so its prompt sits at the model.
			part.CFrame = CFrame.new(base + Vector3.new(0, 2, 0)) * target.Rotation
			-- The quiz-show set's front is its +Z, opposite the slot's facing, so spin it
			-- 180° to face the players approaching from the pitch.
			local modelCF = CFrame.new(base) * target.Rotation * CFrame.Angles(0, math.pi, 0)
			local placed = Assets.place(Workspace, Config.Models.TriviaKiosk, modelCF, 8)
			if placed then
				placed.Name = "TriviaKioskModel"
				part.Transparency = 1
				kioskPlaced = true
			end
		end

		local prompt = part:FindFirstChildOfClass("ProximityPrompt")
		if not prompt then
			prompt = Instance.new("ProximityPrompt")
			prompt.ActionText  = "Trivia Duel"
			prompt.ObjectText  = "Beat a rival · 5 questions!"
			prompt.MaxActivationDistance = 8
			prompt.HoldDuration = 0
			prompt.Parent = part
		end
		-- Wire Triggered exactly once per prompt (setupKiosk may run again via
		-- DescendantAdded), regardless of whether the prompt was found or created.
		local pp = prompt :: ProximityPrompt
		if not wiredPrompts[pp] then
			wiredPrompts[pp] = true
			pp.Triggered:Connect(joinQueue)
		end
	end

	local function tryFind()
		local kiosk = Workspace:FindFirstChild("TriviaKiosk", true)
		if kiosk and kiosk:IsA("BasePart") then
			setupKiosk(kiosk :: BasePart)
			return
		end
		-- No marker placed in the world -> create one (like the other pads do).
		-- setupKiosk then moves it to the activities row and drops the quiz set on it.
		local marker = Instance.new("Part")
		marker.Name         = "TriviaKiosk"
		marker.Size         = Vector3.new(3, 4, 3)
		marker.Anchored     = true
		marker.CanCollide   = false
		marker.Transparency = 1
		marker.CFrame       = MapLayout.activity("trivia") or CFrame.new(0, 5, 0)
		marker.Parent       = Workspace
		setupKiosk(marker)
	end
	tryFind()
	Workspace.DescendantAdded:Connect(function(inst)
		if inst.Name == "TriviaKiosk" and inst:IsA("BasePart") then
			setupKiosk(inst :: BasePart)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		local idx = table.find(queue, player)
		if idx then
			table.remove(queue, idx)
		end
		local session = TriviaService.sessionByPlayer[player]
		if session then
			TriviaService.sessionByPlayer[player] = nil
			-- Unblock the current question so the remaining player isn't stuck.
			if session.resolve then
				session.resolve()
			end
		end
	end)

	Net.getEvent(Net.Events.TriviaSubmit).OnServerEvent:Connect(
		function(player: Player, payload: unknown)
			TriviaService.submit(player, payload)
		end
	)
end

return TriviaService
