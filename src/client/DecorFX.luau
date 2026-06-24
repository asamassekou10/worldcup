--!strict
-- DecorFX: client-side cosmetic animation for stadium decorations.
--   • Flag sway: all `WCFlag`-tagged Parts gently wave in a procedural breeze.
--   • Net billow: `NetPart`-tagged Parts surge forward on a goal, then settle.
-- Everything is anchored and client-local, so there's zero network cost.

local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local DecorFX = {}

type Flag = { part: BasePart, base: CFrame, offset: number }

local flags: { Flag } = {}

local function track(inst: Instance)
	if inst:IsA("BasePart") then
		table.insert(flags, { part = inst, base = inst.CFrame, offset = math.random() * 6.28 })
	end
end

function DecorFX.start()
	for _, inst in CollectionService:GetTagged("WCFlag") do
		track(inst)
	end
	CollectionService:GetInstanceAddedSignal("WCFlag"):Connect(track)
	CollectionService:GetInstanceRemovedSignal("WCFlag"):Connect(function(inst)
		for i = #flags, 1, -1 do
			if rawequal(flags[i].part, inst) then
				table.remove(flags, i)
			end
		end
	end)

	RunService.RenderStepped:Connect(function()
		local t = os.clock() * 2
		for _, f in flags do
			f.part.CFrame = f.base
				* CFrame.Angles(
					0,
					math.sin(t + f.offset) * 0.22,
					math.sin(t * 1.4 + f.offset) * 0.13
				)
		end
	end)
end

-- ===== Goal net billow =====
-- Call after a goal is scored. `shotX` (-1..1) biases the bulge toward the
-- side the ball entered. The map builder tags each net section Part "NetPart".
-- Falls back gracefully if no NetParts exist (they're optional polish geometry).

local NET_SURGE_CF   = 0.45 -- studs forward on impact
local NET_SURGE_TIME = 0.12 -- seconds to surge
local NET_SETTLE_TIME = 0.55 -- seconds to settle back

function DecorFX.billow(shotX: number, _shotY: number)
	local netParts = CollectionService:GetTagged("NetPart")
	if #netParts == 0 then return end
	for _, inst in netParts do
		if not inst:IsA("BasePart") then continue end
		local baseCF = inst.CFrame
		-- Bulge magnitude: stronger toward the ball-entry side.
		local bias = 1 + math.abs(shotX) * 0.4
		local surge = baseCF * CFrame.new(0, 0, -NET_SURGE_CF * bias)
		-- Snap forward fast, then ease back to rest.
		TweenService:Create(
			inst,
			TweenInfo.new(NET_SURGE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ CFrame = surge }
		):Play()
		task.delay(NET_SURGE_TIME, function()
			TweenService:Create(
				inst,
				TweenInfo.new(NET_SETTLE_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
				{ CFrame = baseCF }
			):Play()
		end)
	end
end

return DecorFX
