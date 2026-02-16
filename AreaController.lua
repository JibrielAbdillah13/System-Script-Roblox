-- Script 1: Anti-Glitch Zone Controller
local Zone = script.Parent
local RunService = game:GetService("RunService")

local function checkPlayersInZone()
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	-- Hanya mendeteksi objek yang ada di dalam folder 'Characters' atau Workspace
	params.FilterDescendantsInstances = {workspace} 

	-- Mendapatkan semua part yang berada di dalam area part ini
	local partsInZone = workspace:GetPartBoundsInBox(Zone.CFrame, Zone.Size, params)

	local playerFound = false
	for _, part in pairs(partsInZone) do
		local character = part.Parent
		local humanoid = character:FindFirstChild("Humanoid")
		if humanoid and game.Players:GetPlayerFromCharacter(character) then
			-- Cek apakah player masih hidup
			if humanoid.Health > 0 then
				playerFound = true
				break
			end
		end
	end

	-- Update status zona
	if Zone:GetAttribute("IsActive") ~= playerFound then
		Zone:SetAttribute("IsActive", playerFound)
	end
end

-- Mengecek zona setiap 0.1 detik (lebih stabil dan hemat performa)
task.spawn(function()
	while true do
		checkPlayersInZone()
		task.wait(0.1)
	end
end)
