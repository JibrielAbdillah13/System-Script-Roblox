--[[
    Venus Flytrap Manager - Professional System
    Logic: Individual Trigger, Kill on Mouth Touch, Zone-based Idle
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local TAG_NAME = "VenusTrap"
local ZONE_PART = workspace:WaitForChild("RatZone") -- Menggunakan zona yang sama dengan sistem tikus

local function SetupVenus(model)
	local humanoid = model:WaitForChild("Humanoid")
	local root = model:WaitForChild("HumanoidRootPart")
	local akar = model:WaitForChild("Akar")

	-- Asset Animasi
	local animIdle = model:WaitForChild("AnimationIdle")
	local animMakan = model:WaitForChild("AnimationMakan")

	-- Efek Suara (Pastikan ada Sound di dalam model)
	local chompSound = root:FindFirstChild("ChompSound")

	-- Part Mulut (berada di dalam folder Anim sesuai screenshot)
	local animFolder = model:WaitForChild("Anim")
	local mulutKanan = animFolder:WaitForChild("MulutKanan")
	local mulutKiri = animFolder:WaitForChild("MulutKiri")

	-- Load Animasi
	local trackIdle = humanoid:LoadAnimation(animIdle)
	local trackMakan = humanoid:LoadAnimation(animMakan)

	local isEating = false -- State Machine: Apakah sedang makan?

	-- 1. LOGIKA IDLE (BERDASARKAN ZONA)
	task.spawn(function()
		while model.Parent do
			local isZoneActive = ZONE_PART:GetAttribute("IsActive")

			if isZoneActive and not isEating then
				if not trackIdle.IsPlaying then trackIdle:Play() end
			else
				trackIdle:Stop()
			end
			task.wait(0.5)
		end
	end)

	-- 2. LOGIKA KILL (Hanya aktif saat animasi makan)
	local function killPlayer(hit)
		if not isEating then return end -- Jika tidak sedang makan, jangan bunuh

		local char = hit.Parent
		local hum = char:FindFirstChild("Humanoid")
		if hum and hum.Health > 0 then
			if Players:GetPlayerFromCharacter(char) then
				hum.Health = 0 -- Mati seketika
			end
		end
	end

	mulutKanan.Touched:Connect(killPlayer)
	mulutKiri.Touched:Connect(killPlayer)

	-- 3. LOGIKA TRIGGER AKAR
	akar.Touched:Connect(function(hit)
		local char = hit.Parent
		if Players:GetPlayerFromCharacter(char) and not isEating then
			isEating = true

			-- Hentikan Idle, Jalankan Makan
			trackIdle:Stop()
			if chompSound then chompSound:Play() end
			trackMakan:Play()

			-- Tunggu sampai animasi makan selesai (misal durasi 1.5 detik)
			-- Kamu bisa menggunakan trackMakan.Stopped:Wait() jika animasinya tidak looping
			task.wait(trackMakan.Length > 0 and trackMakan.Length or 1.5)

			isEating = false
		end
	end)
end

-- Inisialisasi
for _, venus in pairs(CollectionService:GetTagged(TAG_NAME)) do
	task.spawn(SetupVenus, venus)
end

CollectionService:GetInstanceAddedSignal(TAG_NAME):Connect(function(instance)
	task.spawn(SetupVenus, instance)
end)
