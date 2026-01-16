--[[
    Flower Obstacle Manager - Centralized System
    Logika: Toggle Transparency, Sound, & Particles
    Versi 01
]]

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris") -- Untuk mengatur pembersihan efek jika perlu

local TAG_NAME = "FlowerTrap"
local COOLDOWN_TIME = 3 -- Durasi bunga menjadi bunga bangkai sebelum reset

-- Fungsi untuk mengubah transparansi seluruh bagian model
local function setModelTransparency(model, targetValue)
	for _, part in pairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Transparency = targetValue
			-- Opsional: Matikan CanCollide agar player tidak tersangkut di model yang tidak terlihat
			part.CanCollide = (targetValue == 0) 
		end
	end
end

local function SetupFlower(flowerModel)
	local trigger = flowerModel:FindFirstChild("TriggerPart")
	local bangkai = flowerModel:FindFirstChild("Bangkai")
	local raflesia = flowerModel:FindFirstChild("raflesia")
	local particle = trigger:FindFirstChild("SmellParticle")
	local sound = trigger:FindFirstChild("CessSound")

	local isActive = false -- Debounce agar tidak trigger berkali-kali

	if not (trigger and bangkai and raflesia) then return end

	trigger.Touched:Connect(function(hit)
		local character = hit.Parent
		if character:FindFirstChild("Humanoid") and not isActive then
			isActive = true

			-- 1. Jalankan Efek Visual (Berubah ke Bangkai)
			setModelTransparency(raflesia, 1) -- Hilangkan Raflesia
			setModelTransparency(bangkai, 0) -- Munculkan Bangkai

			-- 2. Jalankan Partikel & Suara
			if particle then particle.Enabled = true end
			if sound then sound:Play() end

			-- 3. Tunggu beberapa detik (Aroma tercium)
			task.wait(COOLDOWN_TIME)

			-- 4. Reset ke kondisi semula (Kembali ke Raflesia)
			if particle then particle.Enabled = false end
			setModelTransparency(bangkai, 1)
			setModelTransparency(raflesia, 0)

			isActive = false
		end
	end)
end

-- Inisialisasi semua bunga yang memiliki tag
for _, flower in pairs(CollectionService:GetTagged(TAG_NAME)) do
	SetupFlower(flower)
end

-- Deteksi jika ada bunga baru yang di-spawn
CollectionService:GetInstanceAddedSignal(TAG_NAME):Connect(function(instance)
	SetupFlower(instance)
end)
