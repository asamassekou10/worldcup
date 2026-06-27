--!strict
-- TradeService: same-server, two-sided card trading with a lock + confirm handshake. The dangerous
-- part (the actual ownership swap) lives in DataService.executeTrade, which validates BOTH offers in
-- full and only then mutates with no yields in between -- so cards can never be duped. This module
-- is just the session state machine: invites, building offers, lock, confirm, cancel.
--
-- Flow: A invites B -> B accepts -> both add cards to their offer -> both LOCK -> both CONFIRM ->
-- the swap runs. Any offer change while building clears both locks (so you can't be tricked by a
-- last-second swap of the goods -- the classic trade scam).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local CardBank = require(Shared:WaitForChild("CardBank"))
local DataService = require(script.Parent:WaitForChild("DataService"))

local TradeService = {}

local INVITE_TTL = 30 -- seconds an invite stays open

type Session = {
	a: Player,
	b: Player,
	offer: { [Player]: { [string]: number } },
	locked: { [Player]: boolean },
	confirmed: { [Player]: boolean },
}

local sessionOf: { [Player]: Session } = {}
-- Outgoing invites: invitee -> { from = Player, at = number }.
local invites: { [Player]: { from: Player, at: number } } = {}

local function notify(player: Player, message: string)
	Net.getEvent(Net.Events.Notify):FireClient(player, { message = message })
end

local function partner(session: Session, player: Player): Player
	return if session.a == player then session.b else session.a
end

local function pushState(session: Session, player: Player)
	local other = partner(session, player)
	Net.getEvent(Net.Events.TradeState):FireClient(player, {
		active = true,
		partnerName = other.Name,
		partnerId = other.UserId,
		mine = session.offer[player],
		theirs = session.offer[other],
		myLock = session.locked[player],
		theirLock = session.locked[other],
		bothLocked = session.locked[player] and session.locked[other],
	})
end

local function pushBoth(session: Session)
	pushState(session, session.a)
	pushState(session, session.b)
end

local function closeState(player: Player)
	Net.getEvent(Net.Events.TradeState):FireClient(player, { active = false })
end

-- Tear a session down (optionally telling each side why), leaving both free to trade again.
local function endSession(session: Session, message: string?)
	sessionOf[session.a] = nil
	sessionOf[session.b] = nil
	for _, p in { session.a, session.b } do
		if p.Parent then
			closeState(p)
			if message then
				notify(p, message)
			end
		end
	end
end

-- Any change to an offer clears BOTH locks/confirms (anti scam-swap).
local function resetLocks(session: Session)
	session.locked[session.a] = false
	session.locked[session.b] = false
	session.confirmed[session.a] = false
	session.confirmed[session.b] = false
end

local function propose(from: Player, targetUserId: number)
	if sessionOf[from] then
		notify(from, "Finish your current trade first.")
		return
	end
	local target = Players:GetPlayerByUserId(targetUserId)
	if not target or target == from then
		notify(from, "That player isn't here.")
		return
	end
	if sessionOf[target] then
		notify(from, target.Name .. " is already trading.")
		return
	end
	invites[target] = { from = from, at = os.time() }
	Net.getEvent(Net.Events.TradeInvite):FireClient(target, {
		fromUserId = from.UserId,
		fromName = from.Name,
	})
	notify(from, "Trade request sent to " .. target.Name .. ".")
end

local function respond(player: Player, accept: boolean)
	local invite = invites[player]
	invites[player] = nil
	if not invite then
		return
	end
	local from = invite.from
	if not accept then
		if from.Parent then
			notify(from, player.Name .. " declined the trade.")
		end
		return
	end
	if os.time() - invite.at > INVITE_TTL then
		notify(player, "That trade request expired.")
		return
	end
	if not from.Parent or sessionOf[from] or sessionOf[player] then
		notify(player, "That trade is no longer available.")
		return
	end
	local session: Session = {
		a = from,
		b = player,
		offer = { [from] = {}, [player] = {} },
		locked = { [from] = false, [player] = false },
		confirmed = { [from] = false, [player] = false },
	}
	sessionOf[from] = session
	sessionOf[player] = session
	pushBoth(session)
end

-- Adjust a card in the player's offer by `delta` (+1 add, -1 remove), validated against what they
-- actually own right now. Clears locks because the goods changed.
local function setOffer(session: Session, player: Player, id: string, delta: number)
	if not CardBank.byId[id] then
		return
	end
	local mine = session.offer[player]
	local current = mine[id] or 0
	local want = math.clamp(current + delta, 0, DataService.cardCount(player, id))
	if want == current then
		return
	end
	if want <= 0 then
		mine[id] = nil
	else
		mine[id] = want
	end
	resetLocks(session)
	pushBoth(session)
end

local function tryExecute(session: Session)
	if not (session.confirmed[session.a] and session.confirmed[session.b]) then
		return
	end
	local ok, message = DataService.executeTrade(
		session.a,
		session.offer[session.a],
		session.b,
		session.offer[session.b]
	)
	if ok then
		endSession(session, "✅ " .. message)
	else
		-- Someone's cards changed underneath us: reset and let them rebuild.
		resetLocks(session)
		pushBoth(session)
		notify(session.a, "⚠️ " .. message)
		notify(session.b, "⚠️ " .. message)
	end
end

local function handleAction(player: Player, payload: { [string]: any })
	local session = sessionOf[player]
	if not session then
		return
	end
	local action = payload.action
	if action == "offer" then
		local id = payload.id
		local delta = payload.delta
		if type(id) == "string" and type(delta) == "number" then
			setOffer(session, player, id, if delta > 0 then 1 else -1)
		end
	elseif action == "lock" then
		session.locked[player] = not session.locked[player]
		if not session.locked[player] then
			session.confirmed[player] = false
		end
		pushBoth(session)
	elseif action == "confirm" then
		if session.locked[player] and session.locked[partner(session, player)] then
			session.confirmed[player] = true
			tryExecute(session)
		end
	elseif action == "cancel" then
		endSession(session, player.Name .. " cancelled the trade.")
	end
end

function TradeService.start()
	Net.getEvent(Net.Events.TradeInvite).OnServerEvent
		:Connect(function(player: Player, payload: unknown)
			if typeof(payload) ~= "table" then
				return
			end
			local target = (payload :: { targetUserId: unknown }).targetUserId
			if type(target) == "number" then
				propose(player, target)
			end
		end)

	Net.getEvent(Net.Events.TradeRespond).OnServerEvent
		:Connect(function(player: Player, payload: unknown)
			if typeof(payload) ~= "table" then
				return
			end
			respond(player, (payload :: { accept: boolean }).accept == true)
		end)

	Net.getEvent(Net.Events.TradeAction).OnServerEvent
		:Connect(function(player: Player, payload: unknown)
			if typeof(payload) == "table" then
				handleAction(player, payload :: { [string]: any })
			end
		end)

	Players.PlayerRemoving:Connect(function(player: Player)
		invites[player] = nil
		local session = sessionOf[player]
		if session then
			endSession(session, player.Name .. " left — trade cancelled.")
		end
	end)
end

return TradeService
