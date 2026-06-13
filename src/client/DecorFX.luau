--!strict
-- DecorFX: gently sways the World Cup flags (tagged `WCFlag` by the server). Run
-- locally on each client -- the flags are anchored decorations, so animating
-- their CFrame client-side costs no network and looks alive for everyone.

local CollectionService = game:GetService("CollectionService")
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

return DecorFX
