--!strict
-- Camera: a fixed TV-style penalty camera during a round -- set back behind the
-- ball and raised so the whole goal mouth, the shooter and the keeper are all in
-- frame (instead of the default over-the-shoulder follow cam, which sits too low
-- and close). In the lobby we hand control back to the default camera so players
-- can walk the plaza and see each other.
--
-- Broadcast layer: a decaying screen-shake on strikes, and a short cinematic
-- "goal cam" cut to a side angle on a goal -- driven inside the same render loop.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Venue = require(script.Parent:WaitForChild("Venue"))

local Camera = {}

local BIND = "PenaltyKingsTVCam"
local BASE_FOV = 68
local active = false

-- Shake (trauma model: offset scales with trauma^2, trauma decays over time).
local trauma = 0
local rng = Random.new()

-- Cinematic goal-cam override + eased follow (so cuts glide instead of snapping).
local goalCamCF: CFrame? = nil
local goalCamUntil = 0
local eased: CFrame? = nil

-- FOV "punch": a quick widen on a strike that eases back to the base FOV.
local fovKick = 0

-- The local player keeps this turn -> use the goalkeeper view.
local keeperView = false
local function baseCF(): CFrame?
	return if keeperView then Venue.keeperCameraCFrame() else Venue.cameraCFrame()
end

local function shakeOffset(): CFrame
	local s = trauma * trauma
	if s <= 0 then
		return CFrame.identity
	end
	local pos = 1.6 * s
	local ang = 0.05 * s
	return CFrame.new(rng:NextNumber(-pos, pos), rng:NextNumber(-pos, pos), 0)
		* CFrame.Angles(
			rng:NextNumber(-ang, ang),
			rng:NextNumber(-ang, ang),
			rng:NextNumber(-ang, ang)
		)
end

-- Switch to the fixed TV penalty angle. If the venue markers aren't found we
-- leave the default camera untouched (never strand the player on a black/sky
-- view).
function Camera.toMatch(asKeeper: boolean?)
	keeperView = asKeeper == true
	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end
	local cf = baseCF()
	if not cf then
		return
	end

	active = true
	eased = cf
	fovKick = 0
	cam.CameraType = Enum.CameraType.Scriptable
	cam.FieldOfView = BASE_FOV
	cam.CFrame = cf

	-- Re-assert every frame so the angle holds even as the avatar/animator moves.
	pcall(function()
		RunService:UnbindFromRenderStep(BIND)
	end)
	RunService:BindToRenderStep(BIND, Enum.RenderPriority.Camera.Value + 1, function(dt: number)
		local c = Workspace.CurrentCamera
		if not active or not c then
			return
		end
		local desired = baseCF()
		if not desired then
			return
		end
		-- Cut to the goal cam during its window, else the normal TV angle.
		if goalCamCF and os.clock() < goalCamUntil then
			desired = goalCamCF
		end
		-- Frame-rate-independent smoothing so moves glide instead of snapping.
		local alpha = 1 - math.exp(-dt * 9)
		eased = (eased or desired):Lerp(desired, alpha)
		if trauma > 0 then
			c.CFrame = (eased :: CFrame) * shakeOffset()
			trauma = math.max(0, trauma - dt * 1.8)
		else
			c.CFrame = eased :: CFrame
		end
		-- FOV punch eases back to base.
		fovKick = math.max(0, fovKick - dt * 28)
		c.FieldOfView = BASE_FOV + fovKick
	end)
end

-- Hand control back to the default follow camera (lobby / match over).
function Camera.toLobby()
	active = false
	trauma = 0
	goalCamCF = nil
	pcall(function()
		RunService:UnbindFromRenderStep(BIND)
	end)
	local cam = Workspace.CurrentCamera
	if cam then
		cam.CameraType = Enum.CameraType.Custom
		cam.FieldOfView = 70 -- default
	end
end

-- Add a jolt of shake (0..1). Stacks, clamped.
function Camera.shake(amount: number)
	trauma = math.clamp(trauma + amount, 0, 1)
end

-- Widen the FOV by `amount` degrees, easing back (an impact "punch").
function Camera.fovPunch(amount: number)
	fovKick = math.clamp(fovKick + amount, 0, 16)
end

-- Cut to a dramatic side-on angle on the goal for `seconds` (a goal replay-cam).
function Camera.goalCam(seconds: number)
	local frame = Venue.goalCFrame()
	if not frame then
		return
	end
	local pos = frame.Position
		+ frame.RightVector * 15
		+ frame.LookVector * 7
		+ Vector3.new(0, 3.5, 0)
	local look = frame.Position + Vector3.new(0, 3, 0)
	goalCamCF = CFrame.lookAt(pos, look)
	goalCamUntil = os.clock() + seconds
end

return Camera
