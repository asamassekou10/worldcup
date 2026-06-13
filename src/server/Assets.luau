--!strict
-- Assets: loads toolbox mesh models at runtime (InsertService), caches one
-- template per id, and stamps anchored, scaled clones into the world. Every call
-- is pcall'd and returns nil on failure, so callers fall back to built geometry
-- (Studio without API access, or a private/unavailable asset, never breaks).

local InsertService = game:GetService("InsertService")

local Assets = {}

local cache: { [number]: Instance | false } = {}

-- The detached template for an id (the first Model/MeshPart/Part in the asset).
function Assets.template(id: number): Instance?
	if id <= 0 then
		return nil
	end
	local cached = cache[id]
	if cached == false then
		return nil -- previously failed
	elseif cached ~= nil then
		return cached :: Instance
	end
	local inner: Instance? = nil
	local ok, container = pcall(function()
		return InsertService:LoadAsset(id)
	end)
	if ok and container then
		local found = container:FindFirstChildWhichIsA("Model")
			or container:FindFirstChildWhichIsA("BasePart")
		if found then
			inner = found:Clone()
		end
		container:Destroy()
	end
	cache[id] = inner or false
	return inner
end

local function configure(inst: Instance)
	local function setup(p: BasePart)
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
	end
	if inst:IsA("BasePart") then
		setup(inst)
	end
	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") then
			setup(d)
		end
	end
end

local function sizeOf(inst: Instance): Vector3
	if inst:IsA("Model") then
		local _, s = inst:GetBoundingBox()
		return s
	elseif inst:IsA("BasePart") then
		return inst.Size
	end
	return Vector3.one
end

local function pivot(inst: Instance, cf: CFrame)
	if inst:IsA("Model") then
		inst:PivotTo(cf)
	elseif inst:IsA("BasePart") then
		inst.CFrame = cf
	end
end

-- Stamp a clone at `cf` (its BASE sits on cf), optionally scaled to `targetHeight`
-- studs. Returns the clone (or nil if the asset isn't available).
function Assets.place(parent: Instance, id: number, cf: CFrame, targetHeight: number?): Instance?
	local template = Assets.template(id)
	if not template then
		return nil
	end
	local clone = template:Clone()
	configure(clone)

	if targetHeight then
		local s = sizeOf(clone)
		if s.Y > 0.1 then
			local factor = targetHeight / s.Y
			if clone:IsA("Model") then
				pcall(function()
					(clone :: Model):ScaleTo(factor)
				end)
			elseif clone:IsA("BasePart") then
				local p = clone :: BasePart
				p.Size = p.Size * factor
			end
		end
	end

	local s2 = sizeOf(clone)
	pivot(clone, cf * CFrame.new(0, s2.Y / 2, 0)) -- raise so the base rests on cf
	clone.Parent = parent
	return clone
end

-- A representative BasePart of a placed asset (to attach a prompt/sign to).
function Assets.anchor(inst: Instance): BasePart?
	if inst:IsA("BasePart") then
		return inst
	elseif inst:IsA("Model") then
		return inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

return Assets
