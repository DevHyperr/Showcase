-- // 🎮 Entity Controller 🎮 // --

local ReplStorage  = game:GetService('ReplicatedStorage')
local PathService  = game:GetService('PathfindingService')
local TweenService = game:GetService('TweenService')

local Modules     = ReplStorage:WaitForChild('Modules')
local Config      = ReplStorage:WaitForChild('Config')
local DebugConfig = require(Config:WaitForChild('DebugConfig'))
local DataModule  = require(Modules:WaitForChild('EntityData'))

local MapFolder   	  = workspace:WaitForChild('Map')
local EntityFolder 	  = MapFolder:WaitForChild('Entities')
local InvaderFolder   = EntityFolder:WaitForChild('Invader')
local AllyFolder      = EntityFolder:WaitForChild('Ally')
local StructureFolder = EntityFolder:WaitForChild('Structure')
local AnchorFolder    = MapFolder:WaitForChild('Anchors')

local Protocol: {[Entity]: {[string]: any}} = {}
local ActiveTweens: {[Entity]: Tween} = {}
local TotalEntities: number = 0

local Structures: {Entity} = {}
local Invaders: {Entity} = {}
local Entities: {Entity} = {}
local Allies: {Entity} = {}

local RSFolders     = {
	[  'Invader'  ] = ReplStorage:WaitForChild('Invader'),
	[   'Ally'    ] = ReplStorage:WaitForChild('Ally'),
	[ 'Structure' ] = ReplStorage:WaitForChild('Structure'),
}

-- Returns an unique ID (UID) for an entity based on the total amount of entities that have ever existed.
local function getUID()
	return TotalEntities + 1
end

-- Returns the amount of time elapsed between two specified numbers.
local function TimeElapsed(a: number, b: number?): number
	if not b then
		b = tick()
	end
	if a then
		if typeof(a) == "number" then
			return b - a
		else
			warn(`❌: TimeElapsed(a, b) requires at least one parameter. However, a is {a} and b is {b}. Parent function: {debug.info(2, "n")}`)
			return 0
		end
	else
		warn(`❌: TimeElapsed(a, b) requires at least one parameter. However, a is {a} and b is {b}. Parent function: {debug.info(2, "n")}`)
		return 0
	end
end

-- Returns the magnitude between two Vector3 values or two specified Parts.
local function GetDistanceBetween(a: Vector3 | BasePart, b: Vector3 | BasePart, ignoreY: boolean?): number
	if a and b then
		local posA: Vector3 = typeof(a) == "Instance" and a:IsA("BasePart") and a.Position or a
		local posB: Vector3 = typeof(b) == "Instance" and b:IsA("BasePart") and b.Position or b
		if ignoreY then
			posB = Vector3.new(posB.X, posA.Y, posB.Z) -- Use the same Y value as posA
			return (posA - posB).Magnitude
		else
			return (posA - posB).Magnitude
		end
		
	end
end

-- Returns whether all specified parameters match the first.
local function match(value1, ...)
	local values = {...}
	for _, i in pairs(values) do
		if value1 == i then
			return true
		end
	end
	return false
end

type Entity = {
	Class: string,
	Id: string,
	Body: Model,
	Health: number,
	MaxHealth: number,
	MoveToTarget: boolean,
	MoveToTargetPosition: Vector3?,
	IsMovingToTarget: boolean?,
	anchorY: number,
	LastAttack: number,
	ViewDistance: number,
	WalkSpeed: number,
	AttackSpeed: number,
	Damage: number,
	Target: Entity?,
	AnimationController: AnimationController,
	
	Die: (self: Entity) -> (),
	Update: (self: Entity) -> (),
	Spread: (self: Entity) -> (),
	GetData: (self: Entity) -> (any),
	IsAlive: (self: Entity) -> (boolean),
	GetRoot: (self: Entity) -> (BasePart),
	GetAnchor: (self: Entity) -> (BasePart),
	FindNearestTarget: (self: Entity) -> (),
	CancelActiveTweens: (self: Entity) -> (),
	Attack: (self: Entity, target: Entity) -> (),
	Animate: (self: Entity, animName: string) -> (),
	TakeDamage: (self: Entity, amount: number) -> (),
	MoveTo: (self: Entity, target: Vector3 | Entity | BasePart) -> (),
	Face: (self: Entity, location: Vector3 | BasePart, fade: boolean) -> (),
	
}

local Entity = {} :: Entity
Entity.__index  = Entity

-- Returns an Entity's Emoji for prettier Debugging!
function Entity:Emoji()
	return Entity:GetData('Emoji') or ""
end

--[[
Returns the value of a specified key from the Entity's data.
If the specified key couldn't be read, the function returns nil.
]]
function Entity:GetData(key: string): any?
	if DataModule[self.Class] then
		if DataModule[self.Class][self.Id] then
			if DataModule[self.Class][self.Id][key] then
				return DataModule[self.Class][self.Id][key]
			else
				warn(self.Class, self.Id, key)
				return nil
			end
		else
			warn(self.Class, self.Id, key)
			return nil
		end
	else
		warn(self.Class, self.Id, key)
		return nil
	end
end

-- Returns the Entity's HumanoidRootPart or PrimaryPart of the Entity.
function Entity:GetRoot(): BodyPart
	return self.Body:FindFirstChild("HumanoidRootPart") or self.Body.PrimaryPart
end

-- Returns the Entity's nearest target and the distance in studs between them.
function Entity:FindTargets(): (Entity?, number?)
	
	local function findTargetsFrom(folder)
		local nearestTargets = {}
		local closestDistance = math.huge
		for _, target in pairs(folder) do
			local root1 = self:GetRoot()
			local root2 = target:GetRoot()
			if root1 and root2 and target:IsAlive() then
				local distance = GetDistanceBetween(root1, root2)
				if distance < closestDistance and self.ViewDistance >= distance  then
					closestDistance = distance
					table.insert(nearestTargets, target)
				end
			end
		end
		table.sort(nearestTargets, function(a, b)
			return GetDistanceBetween(a:GetRoot().Position, self:GetRoot().Position) < GetDistanceBetween(b:GetRoot().Position, self:GetRoot().Position)
		end)
		return nearestTargets
	end
			
	if self.Class == "Invader" then
		local AllyTargets = findTargetsFrom(Allies)
		local StructureTargets = findTargetsFrom(Structures)
		
		if AllyTargets and StructureTargets then
			if not AllyTargets then   -- Prioritize attacking allies instead of structures!
				return StructureTargets
			else
				return AllyTargets
			end
		else
			if AllyTargets then
				return AllyTargets
			else
				return StructureTargets
			end
		end
		
	elseif self.Class == "Ally" then
		return findTargetsFrom(Invaders)
	end
end

-- Checks every single individual component of the Entity.
function Entity:Debug()
	local log = {"🪲 Advanced Debug Protocol for Entity:", self}
	if self.Class then
		if match(self.Class, "Invader", "Ally", "Structure") then
			table.insert(log, `✅: self.Class is valid! Class: {self.Class}`)
		else
			table.insert(log, `❌: self.Class is not valid! Class: {self.Class}`)
		end
	else
		table.insert(log, "❌: self.Class is nil.")
	end
	if self.Id then
		if DataModule[self.Class][self.Id] then
			table.insert(log, `✅: self.Id is valid! Id: {self.Id}`)
		else
			table.insert(log, `❌: No data registry found for Id: {self.Id}`)
		end
	else
		table.insert(log, "❌: self.Id is nil.")
	end
	if self.UID then
		local entitiesWithSameUID = {}
		for _, entity in pairs(Entities) do
			if entity.UID == self.UID then
				table.insert(entitiesWithSameUID, entity)
			end
		end
		if #entitiesWithSameUID > 0 then
			table.insert(log, `❌: self.UID is not valid! The following {#entitiesWithSameUID} Entities have the same UID:`)
			table.insert(log, entitiesWithSameUID)
		else
			table.insert(log, `✅: self.UID is valid! UID: {self.UID}`)
		end
	else
		table.insert(log, "❌: self.UID is nil.")
	end
	if self.Body then
		table.insert(log, `✅: self.Body is valid!`)
	else
		table.insert(log, "❌: self.Body is nil.")
	end
	if self:GetAnchor() then
		table.insert(log, `✅: Entity has an AnchorPart!`)
	else
		table.insert(log, `❌: Entity has no AnchorPart!`)
	end

	warn(log)
end

-- Returns the Entity's anchor part.
function Entity:GetAnchor(): BasePart
	local Anchor = AnchorFolder:FindFirstChild(tostring(self.UID))
	if not Anchor then
		warn(`❌: The AnchorPart ⚓ of Entity {self.UID} ({self.Id}{self:Emoji() or ''}) does not exist. This error was caused by function: {debug.info(2, "n")}. Click here for more information:`)
		warn(self)
	end
	return Anchor
end

-- Make the Entity face a specified BasePart or Vector3.
function Entity:Face(location: Vector3 | BasePart, fade: boolean?)
	if not location then
		warn(`⚠️: Can't make Entity face a nil value.`)
		return
	end
	local anchor = self:GetAnchor() :: BasePart
	if anchor then
		
		local position
		if typeof(location) == "Instance" and location:IsA("BasePart") then
			
			position = Vector3.new(location.Position.X, self.anchorY, location.Position.Z)
		elseif typeof(location) == "Vector3" then
		
			position = location
		else
		
			position = Vector3.new( location:GetAnchor().Position.X, self.anchorY,  location:GetAnchor().Position.Z)
			
		end
		
		if not position then
			return
		end

		local origin = anchor.Position
		local direction = Vector3.new(
			position.X - origin.X,
			0,
			position.Z - origin.Z
		)

		if direction.Magnitude == 0 then return end -- Prevent NaNs

		-- Use LookVector math but strip Y rotation only
		local flatTarget = origin + direction.Unit
		anchor.CFrame = CFrame.new(origin, flatTarget)
		
	else
		warn(`⚠️: AnchorPart not found in Entity {self.UID} ({self.Id}).`)
		return
	end
end

-- This function makes the Entity walk to the nearest free position.
function Entity:Spread()
	if #self.Targets > 0 then return end

	-- 🕒 Rate-limit spread attempts
	self._lastSpreadTime = self._lastSpreadTime or 0
	if TimeElapsed(self._lastSpreadTime) < 0.1 then return end
	self._lastSpreadTime = tick()

	self:CancelActiveTweens()

	local myAnchor = self:GetAnchor()
	if not myAnchor then
		warn("anchor is missing")
		return
	end

	local repel = Vector3.zero
	local count = 0

	for _, ally in pairs(Allies) do
		if ally ~= self and not ally.Target then
			local anchor = ally:GetAnchor()
			if anchor then
				local offset = myAnchor.Position - anchor.Position
				offset = Vector3.new(offset.X,  self.anchorY, offset.Z) 
				local dist = offset.Magnitude
				local minDistance = 1.7
				if dist > 0.01 and dist < (minDistance) then
					repel += Vector3.new(offset.X,  self.anchorY, offset.Z).Unit * (2 - dist)
					count += 1
				end
			end
		end
	end

	if count == 0 then
		self:Animate("Idle")
		return
	end

	local moveDir = repel / count
	local targetPos = myAnchor.Position + moveDir

	targetPos = Vector3.new(targetPos.X, self.anchorY, targetPos.Z)
	if myAnchor.Position.Y < -1 then
		warn(myAnchor.Position.Y)
	end
	
	local function isValidVector3(v)
		return v.Magnitude == v.Magnitude and v.Magnitude < 1000
	end

	if isValidVector3(targetPos) and GetDistanceBetween(myAnchor.Position, targetPos) < 30 then
		self:Animate("Walk")
		self:MoveTo(targetPos, true)
	else
		self:Animate("Idle")
		warn("❌ Invalid movement attempt:", targetPos)
	end
end

-- Rounds a specified number to 2 decimal places.
local function float2(num: number)
	return math.round(num * 100) / 100
end

-- Moves the Entity's anchor smoothly to a specified location, Entity or BasePart relative to the its WalkSpeed.
function Entity:MoveTo(target: Vector3 | Entity | BasePart, dontAnimate: boolean)
	
	if not target then
		self:CancelActiveTweens()
		self:Animate("Idle")
		return
	end
	
	local targetPosition
	
	if typeof(target) == "Vector3" then
		targetPosition = target
	elseif typeof(target) == "Instance" and target:IsA("BasePart") then
		targetPosition = target.Position
	else
		targetPosition = target:GetAnchor().Position
	end
	
	targetPosition = Vector3.new(float2(targetPosition.X), self.anchorY, float2(targetPosition.Z))
	
	if GetDistanceBetween(targetPosition, self:GetAnchor().Position) > 300 then
		self:Animate("Idle")
		self.MoveToTarget = false
		self.MoveToTargetPosition = nil
		warn("⚠️ Invalid movement attempt:", targetPosition)
		return
	end
	
	local myAnchor = self:GetAnchor()
	local myAnchorPos = myAnchor.Position
	if myAnchor then
		local distance = GetDistanceBetween(myAnchor.Position, targetPosition)
		if not dontAnimate then
			self:Animate("Run")
		end
		
		
		self:CancelActiveTweens()
		self:Face(targetPosition, true)
		
		local pos = Vector3.new(float2(targetPosition.X), self.anchorY, float2(targetPosition.Z)) -- ALWAYS ensure that the Y is the same
		self.Targets = {}
		local duration = float2(distance / self.WalkSpeed)
		local t = TweenService:Create(myAnchor, TweenInfo.new(duration, Enum.EasingStyle.Linear), {Position = pos})
		t:Play()
		if DebugConfig.Log_Movement then
			local stringPos1 = `({float2(myAnchorPos.X)}, {float2(myAnchorPos.Y)}, {float2(myAnchorPos.Z)})`
			local stringPos2 = `({float2(pos.X)}, {float2(pos.Y)}, {float2(pos.Z)})`
			print(`Moved Entity {self.UID} ({self.Id}) from {stringPos1} to {stringPos2} in {duration} seconds.`)
		end
		ActiveTweens[self] = t
		task.delay(duration, function()
			local tween = ActiveTweens[self] :: Tween
			if tween == t then
				tween:Cancel()
				tween = nil
			end
		end)
	else
		warn(`⚠️ No anchor found for entity {self.UID}. View more information here:`)
		warn(self)
	end
end

-- Deals damage to another Entity.
function Entity:Attack(attack)
	self.Attackig = true
	if attack then
		local General = attack.General
		self:Animate("Attack", attack)
		
		if General.Sound then
			General.Sound:Play()
		end
		
		print("Attack test!")
		
		if General.AttackType.Id == "Single" then
			local targets = self:FindTargets()
			if #targets > 0 then
				local target = targets[1]
				local damage = General.Damage
				target:TakeDamage(self, damage, General.Element)
			end
		elseif General.AttackType.Id == "Multi" then
			local targets = self:FindTargets()
			if #targets > 0 then
				local maxtargets = General.AttackType.MaxTargets
				for _, target in pairs(targets) do
					if maxtargets <= 0 then
						return
					end
					local damage = General.Damage
					target:TakeDamage(self, damage, General.Element)
					maxtargets -= 1
				end
			end
		elseif General.AttackType.Id == "Area" then
			local targets = self:FindTargets()
			if #targets > 0 then
				for _, target in pairs(targets) do
					local damage = General.Damage
					target:TakeDamage(self, damage, General.Element)
				end
			end
		elseif General.AttackType.Id == "Angle" then
			-- Attack all entities within a cone defined by Angle and AttackRange

			local attackerPos = self:GetAnchor().Position
			local attackerDir = self:GetAnchor().CFrame.LookVector
			local halfAngle = math.rad(General.Angle / 2)
			local maxDistance = General.AttackRange

			local tables = {
				["Invader"] = Invaders,
				["Ally"] = Allies,
				["Structure"] = Structures,
			}

			for _, targetCategory in ipairs(self:GetData("Targets") :: {string}) do
				for _, entity in ipairs(tables[targetCategory]) do
					if entity:IsAlive() then
						local targetPos = entity:GetAnchor().Position
						local directionToTarget = (targetPos - attackerPos)
						local distance = directionToTarget.Magnitude

						if distance <= maxDistance then
							directionToTarget = directionToTarget.Unit
							local angle = math.acos(attackerDir:Dot(directionToTarget))

							if angle <= halfAngle then
								local damage = General.Damage
								entity:TakeDamage(self, damage, General.Element)
							end
						end
					end
				end
			end
		end
		task.wait(General.Duration)
		self.Attacking = false
		General.LastTimeAttacked = tick()
	else
		warn(`⚠️ Entity {self.UID} tried to attack Tyler Durden.`)
	end
end

-- Makes the Entity take a specified amount of damage.
function Entity:TakeDamage(who: Entity, amount: number, damageType: string)
	if DebugConfig.Entity.Log_Damage then
		print(`Entity {self.UID} has taken {amount} damage.`)
	end
	Protocol[self]["DamageTaken"] += amount
	self.Health = self.Health - amount
	if not self:IsAlive() then
		self.Health = 0
		self:Die(`Entity {self.UID} was killed by {who.UID}.`)
	end
end

-- Animate the Entity with a given AnimationId.
function Entity:Animate(name: string, info: any): AnimationTrack
	
	-- Ensure that the Entity is not broken
	if not(self.Body and self:GetAnchor() and self:GetRoot()) then
		warn(`❌: Failed to animate Entity.`)
		self:Debug()
		return
	end
	
	-- If no animationName was specified, play Idle animation.
	if not name then
		name = "Idle"
	end

	if self.CurrentAnimName == name then
		if name == "Walk" or name == "Run" or name == "Idle" then
			return
		end
	end
	
	local animationId
	if name == "Attack" then
		animationId = info.General.Animation
		if not animationId or typeof(animationId) ~= "string" or animationId == "rbxassetid://0" then
			return
		end
	else
		animationId = self.Animations[name]
		if not animationId or typeof(animationId) ~= "string" or animationId == "rbxassetid://0" then
			return
		end
	end
	
	-- Ensure that an AnimationController and Animator exist.
	local AnimationController = self.Body:FindFirstChild("AnimationController")
	if not AnimationController then
		AnimationController = Instance.new("AnimationController")
		AnimationController.Name = "AnimationController"
		AnimationController.Parent = self.Body
	end
	self.AnimationController = AnimationController
	
	local animator = self.AnimationController:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Name = "Animator"
		animator.Parent = self.AnimationController
	end
	
	-- Play Animation Track.
	self.CurrentAnimName = name
	self.CurrentAnimId = animationId
	if self.CurrentAnimTrack then
		self.CurrentAnimTrack:Stop()
		self.CurrentAnimTrack = nil
	end
	
	local animation = Instance.new("Animation")
	animation.AnimationId = self.CurrentAnimId
	
	
	local success, track: AnimationTrack = pcall(function()
		return animator:LoadAnimation(animation)
	end)

	if success and track then
		
		if DebugConfig["Log_Animations"] then
			print(`ℹ️: Entity {self.UID} plays animationId {name}.`)
		end

		track.Priority = Enum.AnimationPriority.Action
		track.Looped = false

		if self.CurrentAnimName == "Idle" then
			track.Looped = true
			track.Priority = Enum.AnimationPriority.Idle
		end

		if self.CurrentAnimName == "Run" or self.CurrentAnimName == "Walk" then
			track.Looped = true
			track.Priority = Enum.AnimationPriority.Movement
		end
		track:AdjustSpeed(1)
		if self.CurrentAnimName == "Death" then
			track.Priority = Enum.AnimationPriority.Action4
			track:AdjustWeight(10, -1)
		else
			track:AdjustWeight(1)
		end
		track:Play()
		self.CurrentAnimTrack = track

		if self.CurrentAnimName == "Death" then
			track:GetMarkerReachedSignal("Death"):Connect(function()
				self.AnimationController:Destroy()
				for _, i in pairs(self.Body:GetChildren()) do
					if i:IsA("BasePart") then
						i.Anchored = true
					end
				end
			end)
		end

		track.Ended:Once(function()
			if self.CurrentAnimTrack == track then
				self.CurrentAnimTrack = nil
				self.CurrentAnimName = nil
				self.CurrentAnimId = nil
			end
		end)
	else
		warn("Failed to load animation:", animationId)
	end
end

-- Stops all running tweens on an entity. This forces it to stop moving.
function Entity:CancelActiveTweens()
	local Tween = ActiveTweens[self]
	if Tween then
		Tween:Cancel()
		Tween = nil
	end
end

-- Stops all running animations on an entity.
function Entity:StopAnimation(name: string)
	if self.CurrentAnimName == name then
		self:Animate()
	end
end

-- Recalculates the Entity's actions, targets, etc.
function Entity:Update()
	if self:IsAlive() then
		
		-- Face the current target or destination
		if self.MoveToTarget then
			self:Face(self.MoveToTargetPosition)
		elseif #self.Targets > 0 and self.Targets[1]:IsAlive() then
			self:Face(self.Targets[1])
		end
		
		self.Body:SetAttribute("Health", self.Health)
		self.Body:SetAttribute("MaxHealth", self.MaxHealth)
		
		if self.MoveToTarget and self.MoveToTargetPosition then -- player has selected this unit to move to a certain position
			
			self.Targets = {}
			self.Body:SetAttribute('Target', 0)
			local distance = GetDistanceBetween(self:GetAnchor(), self.MoveToTargetPosition, true)
			if distance > 0.1 then
				
				if not self.IsMovingToTarget or self.OldMoveToTargetPosition ~= self.MoveToTargetPosition then
					self.OldMoveToTargetPosition = self.MoveToTargetPosition
					self.IsMovingToTarget = true
					self:MoveTo(self.MoveToTargetPosition)
				end
				
			else
				if DebugConfig.Entity.Log_MoveTo_Info then
					local str = `({self.MoveToTargetPosition.X}, {self.MoveToTargetPosition.Y}, {self.MoveToTargetPosition.Z})`
					print(`ℹ️: Entity {self.UID} ({self.Id}) has reached their destination at {str}.`)
				end
				
				self.IsMovingToTarget = false
				self:Animate("Idle")
				self:MoveTo()
				self.MoveToTarget = false
				self.MoveToTargetPosition = nil
			end
			
		elseif self.Class ~= "Structure" then
			if self.Attacking then
				return
			end
			local targets = self:FindTargets() -- returns the nearest target or nil, dispite entities viewdistance
			if targets and #targets > 0 then
				self.Targets = targets
				
				if TimeElapsed(self.LastReroute) >= self.RerouteInterval then
					
					self.LastReroute = tick()
					self.Body:SetAttribute('Target', self.Targets[1].UID)
					local Anchor = self:GetAnchor()
					local TargetAnchor = self.Targets[1]:GetAnchor()
					
					local distance = GetDistanceBetween(Anchor.Position, TargetAnchor.Position)
					if distance <= self.ViewDistance then
						
						local ClosestDistance = math.huge
						for Attack, _ in pairs(self.Attacks) do
							if Attack.General.AttackRange < ClosestDistance then
								ClosestDistance = Attack.General.AttackRange
							end
						end
						
						local ChosenAttack = nil
						local LowestPriority = math.huge
						
						for Attack, Priority in pairs(self.Attacks) do
							local AttackRange = Attack.General.AttackRange
							local Cooldown = Attack.General.Cooldown
		
							if TimeElapsed(Attack.General.LastTimeAttacked) >= Cooldown then
								if not ChosenAttack then
									ChosenAttack = Attack
									LowestPriority = Priority
								elseif Priority < LowestPriority then
									ChosenAttack = Attack
									LowestPriority = Priority
								elseif Priority == LowestPriority then
									if math.random(1, 2) == math.random(1, 2) then
										ChosenAttack = Attack
										LowestPriority = Priority
									end
								end
							end
							
						end
						
						if distance > ClosestDistance then
							self:MoveTo(TargetAnchor.Position)
						else
							self:CancelActiveTweens()
							self:StopAnimation("Run")
							self:StopAnimation("Walk")
							if ChosenAttack and distance <= ChosenAttack.General.AttackRange then
								self:Attack(ChosenAttack)
							end
						end
						
					else
						if self.Class == "Ally" then
							self:Spread() -- Allies spread to make sure not to get too close to each othe
						else
							self:CancelActiveTweens() -- Invaders will just stop moving
						end
						self.Targets = {}
					end
				end
				
			else
				self.Body:SetAttribute('Target', 0)
				self.Targets = {}
				if self.Class == "Ally" then
					self:Spread()
				else
					self:MoveTo()
				end
			end
		end
	end
end

-- Kills the Entity.
function Entity:Die(cause: string?)
	if self.Died then
		warn("❌ NPC has already died...")
		self:Debug()
		return
	end
	if cause then
		warn(cause)
	end
	self.Health = 0
	self:CancelActiveTweens()
	self.Died = true
	self.MoveEvent:Disconnect()
	self.MoveEvent = nil
	
	if DebugConfig.Entity["Log_Deaths"] then
		print(`[DEBUG/INFO]: Entity {self.UID} died.`)
		if DebugConfig.Entity["Advanced_Protocol"] then
			Protocol[self]["TimeAlive"] = TimeElapsed(Protocol[self]["TimeAlive"])
			print(Protocol[self])
		end
	end
	
	self.Body:SetAttribute("UID", 0)
	self.Body:SetAttribute("Target", 0)
	self.Body:SetAttribute("Health", 0)

	if not self.AnimationController then
		for _, i in pairs(self.Body:GetChildren()) do
			if i:IsA('BasePart') then
				i.Anchored = false
				i.CollisionGroup = "DestroyedStructure"
			end
		end
	end
	table.remove(Entities, table.find(Entities, self))
	if self.Class == "Invader" then
		table.remove(Invaders, table.find(Invaders, self))
		self:Animate("Death")
		
	elseif self.Class == "Ally" then
		table.remove(Allies, table.find(Allies, self))
		self:Animate("Death")
		
	elseif self.Class == "Structure" then
		table.remove(Structures, table.find(Structures, self))
	end
	
	game:GetService("Debris"):AddItem(self.Body, 2)
	game:GetService("Debris"):AddItem(self:GetAnchor(), 2)
	
	task.delay(2, function()
		self = nil
	end)
	
end

-- Returns whether the Entity is alive or not.
function Entity:IsAlive(): boolean
	return self.Health > 0
end

-- Creates a new Entity object from the provided class, id, cFrame and player.
function Entity.new(class: string, id: string, cFrame: CFrame, player: Player): Entity

	if not(class and id and cFrame) then
		warn(`❌: Failed to create an entity due to invalid parameters. Click here for more information:`)
		warn({class = class, id = id, cFrame = cFrame})
		return nil
	end

	local DataProfile = DataModule[class][id]
	if not DataProfile then
		print(`❌: No data registry for Entity ID: {id} of class: "{class}".`)
		return nil
	end
	
	local body = RSFolders[class]:FindFirstChild(id):Clone() :: Model
	if class == "Invader" then
		body.Parent = InvaderFolder
	elseif class == "Ally" then
		body.Parent = AllyFolder
	elseif class == "Structure" then
		body.Parent = StructureFolder
	else
		warn(`❌ Class "{class}" does not exist.`)
		body:Destroy()
		return
	end
	
	local self = setmetatable({}, Entity) :: Entity
	

	self.Effects = {}
	self.Class = class
	self.Id = id
	self.Attacks = self:GetData("Attacks") -- Stores a table with all attacks
	self.Resistance = self:GetData("Resistance") -- Stores a table with Resistances
	self.Boosts = self:GetData("Boosts") -- Stores a table with Boosts
	self.TargetSelection = "Closest"
	self.Animations = self:GetData("Animations")
	self.CurrentAnimName = nil
	self.CurrentAnimId = nil
	
	self.UID = getUID()
	self.Body = body
	body.Name = self.UID
	
	if self.Id == "Farmer" then -- Only apply SkinColors to the Farmer
		local skinColors = {
			Color3.fromRGB(255, 242, 170),
			Color3.fromRGB(255, 223, 178),
			Color3.fromRGB(255, 213, 193),
			Color3.fromRGB(255, 196, 196),
			Color3.fromRGB(172, 132, 113),
			Color3.fromRGB(127, 110, 102),
			Color3.fromRGB(66, 55, 51),
		}
		
		local skinColor = skinColors[math.random(1, #skinColors)]
		body.Head.Color = skinColor

	end
	
	body:SetAttribute('DisplayName', self:GetData("DisplayName"))
	body:SetAttribute('UID', self.UID)
	
	local anchorPart = Instance.new('Part')
	local pos = cFrame.Position
	local baseplate = workspace.Baseplate
	local modelHeight = body:GetExtentsSize().Y
	anchorPart.Position = pos
	anchorPart.Parent = AnchorFolder
	anchorPart.Name = self.UID
	self.anchorY = self:GetAnchor().Position.Y
	
	if DebugConfig["Entity"]["Show_Anchor"] then
		anchorPart.Transparency = 0
	else
		anchorPart.Transparency = 1
	end
	
	anchorPart.Size = Vector3.new(0.1, 0.1, 0.1)
	anchorPart.Material = Enum.Material.Neon
	anchorPart.Size = Vector3.new(0.3, 0.3, 0.3)
	anchorPart.Color = Color3.new(1,0,0)
	anchorPart.CanCollide = false
	anchorPart.Anchored = true
	anchorPart.Rotation = Vector3.new(0,0,0)
	anchorPart.Massless = true

	body:PivotTo(anchorPart.CFrame)
	anchorPart:SetAttribute('UID', self.UID)
	
	local MovementEvent = anchorPart:GetPropertyChangedSignal('CFrame'):Connect(function()
		local Position = anchorPart.Position
		local Rotation = anchorPart.Rotation
		local cf = anchorPart.CFrame--CFrame.new(Position) * CFrame.Angles(0, math.rad(Rotation.Y), 0)
		body:PivotTo(cf)
	end)

	body.AncestryChanged:Connect(function(_, parent)
		if not parent then
			MovementEvent:Disconnect()
			if self:IsAlive() then
				warn(`⚠️: The Body of Entity {self.UID} ({self.Id}) was deleted by an unknown cause.`)
				self:Die(`❌: Entity {self.UID} was killed due to a corrupted structure.`)
			end
		end
	end)
	
	anchorPart.AncestryChanged:Connect(function(_, parent)
		if not parent then
			MovementEvent:Disconnect()
			if self:IsAlive() then
				warn(`⚠️: The AnchorPart⚓ of Entity {self.UID} ({self.Id}) was deleted by an unknown cause.`)
				self:Die(`❌: Entity {self.UID} was killed due to a corrupted structure.`)
			end
		end
	end)
	
	self.MoveEvent = anchorPart:GetPropertyChangedSignal("CFrame"):Connect(function()
		body:PivotTo(anchorPart.CFrame)
	end)
	
	-- The Hitbox is used to determine wether a player is hovering over the entity with their cursor, not Collisions.

	local hitbox = Instance.new("Part")
	hitbox.Shape = Enum.PartType.Ball
	hitbox.Transparency = 1
	hitbox.Position = self:GetRoot().Position
	hitbox.Anchored = false
	hitbox.CanCollide = false
	hitbox.CanQuery = true
	
	local hitboxSize = 1.5
	
	hitbox.Size = Vector3.new(hitboxSize, hitboxSize, hitboxSize)
	hitbox.Name = "Hitbox"
	hitbox.Parent = self.Body
	self.Hitbox = hitbox
	
	local hitboxWeld = Instance.new("WeldConstraint", self:GetRoot())
	hitboxWeld.Part0 = self:GetRoot()
	hitboxWeld.Part1 = hitbox

	for _, c in pairs(body:GetChildren()) do
		if c:IsA("BasePart") or c:IsA('MeshPart') then
			c.CanCollide = false
			c.Anchored = self.Class == "Structure" and true or false
			--c:SetNetworkOwner(nil)
			c.AssemblyLinearVelocity = Vector3.zero
			c.AssemblyAngularVelocity = Vector3.zero
			c.CustomPhysicalProperties = PhysicalProperties.new(0.0001, 0, 0, 0, 0)
		end
	end

	self.IsMovingToTarget = false -- Determines wether the entity is moving to a specific target location that was assigned to it by a player.
	self.Owner = player -- This is the player that created the entity. If self.Owner is nil, all players are able to assign commands to it.
	self.TrustedPlayers = {} -- This is a table of players that are able to command your units.
	self.Health = self:GetData('Health')
	self.MaxHealth = self:GetData('Health')
	
	self.LastReroute = tick() -- Prevents the entity from reroting every frame after finding a target.
	self.RerouteInterval = 0.2 -- Makes the entity reroute the path to its target every 0.2 seconds.
	
	if class ~= "Structure" then
		self.LastAttack = tick()
		self.ViewDistance = self:GetData('ViewDistance')
		self.AnimationController = body:WaitForChild('AnimationController')
		self.WalkSpeed = self:GetData('WalkSpeed')
	end
	
	body:SetAttribute('Health', self.Health)
	body:SetAttribute('MaxHealth', self.MaxHealth)
	
	table.insert(Entities, self)
	if class == "Structure" then
		table.insert(Structures, self)
	elseif class == "Ally" then
		table.insert(Allies, self)
	elseif class == "Invader" then
		table.insert(Invaders, self)
	end
	
	self.MoveToTargetPosition = nil
	self.MoveToTarget = false
	self.Targets = {}
	
	self:CancelActiveTweens()
	
	Protocol[self] = {
		DamageTaken = 0,
		DamageDealt = 0,
		TimeAlive = tick(),
	}
	
	TotalEntities += 1
	
	if DebugConfig["Entity"]["Log_Creation"] then
		print(`ℹ️: New {class} with ID "{id}" has been created. UID: {self.UID}`)
	end
	
	task.spawn(function()
		while self:IsAlive() do
			self:Update()
			task.wait(0.01)
		end
	end)
	
	return self
end

return Entity
