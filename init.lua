dofile_once( "data/scripts/lib/utilities.lua" )

-- all functions below are optional and can be left out

--[[

function OnModPreInit()
	print("Mod - OnModPreInit()") -- First this is called for all mods
end

function OnModInit()
	print("Mod - OnModInit()") -- After that this is called for all mods
end

function OnModPostInit()
	print("Mod - OnModPostInit()") -- Then this is called for all mods
end

function OnPlayerSpawned( player_entity ) -- This runs when player entity has been created
	GamePrint( "OnPlayerSpawned() - Player entity id: " .. tostring(player_entity) )
end

function OnWorldInitialized() -- This is called once the game world is initialized. Doesn't ensure any world chunks actually exist. Use OnPlayerSpawned to ensure the chunks around player have been loaded or created.
	GamePrint( "OnWorldInitialized() " .. tostring(GameGetFrameNum()) )
end

function OnWorldPreUpdate() -- This is called every time the game is about to start updating the world
	GamePrint( "Pre-update hook " .. tostring(GameGetFrameNum()) )
end

function OnWorldPostUpdate() -- This is called every time the game has finished updating the world
	GamePrint( "Post-update hook " .. tostring(GameGetFrameNum()) )
end

]]--




-- TODO: Make toggles in UI
TestMode = false
Linear  = true
MaxIntense = 25
DeltaMultiplier = 2000
ModIdent = "shockmod"



-- Default Values
PlayerLost = true
OldHp = -1
OldHpMax = -1
OldTime = 0
OldIntense = 0
OldTrigger = -1


function OnWorldInitialized()
	print("Init called")
	ResetAllFlags()
end

function OnPlayerSpawned()
	print("Player Spawned")
	
end


function OnWorldPostUpdate()
    local player = EntityGetWithTag("player_unit")[1]
    
    if player ~= nil then
		PlayerLost = false
        local player_health_component = EntityGetFirstComponent(player, "DamageModelComponent")
        
        if player_health_component ~= nil then
            local hp = math.floor(ComponentGetValueFloat(player_health_component, "hp") * 25)
			local hp_max = math.floor(ComponentGetValueFloat(player_health_component, "max_hp") * 25)
			
			if OldHp == -1 then
				OldHp = hp
				OldHpMax = hp_max
			end
			if hp == OldHp then
				return
			else
				OnHPChange(hp, hp_max)
			end
			OldHp = hp
			OldHpMax = hp_max

            
        else
            print("Player health component not found")
        end
    else
        print("Player not found")
		PlayerLost = true
		-- Likely Polymorphed, Shock?
    end
end

function OnHPChange(hp, hp_max)
	print("HP Changed")
	

	local hp_per = math.floor(100*hp/hp_max)
	print("HP Percentage: "..hp_per)
	if hp_per >= 99 then
		local intensity = CalculateIntensity(hp, hp_max)
		print("Player HP: " .. hp .. " / " .. hp_max)
		print("Current intensity: ", intensity)
		SetIntentsity(intensity)
		return
	end
	if hp<OldHp then
		local delta = math.floor(DeltaMultiplier*(OldHp-hp)/(hp_max))
		print("HP delta: ".. delta)
		if delta == 0 then
			delta =  1
		end
		SetTime(delta)
		TriggerShock()
	end
	print("Calculating intensity")

	local intensity = CalculateIntensity(hp, hp_max)
	print("Player HP: " .. hp .. " / " .. hp_max)
	print("Current intensity: ", intensity)
	SetIntentsity(intensity)

	
end

function CalculateIntensity(hp, hp_max)
	local intensity = 1
	local hp_per = math.floor(100*hp/hp_max)
	print("HP Percentage: ", hp_per)
	if hp_per == 100 then
		print("Full HP, setting intensity to 1")
		return 1
	end
	if (Linear) then
		
		intensity = math.floor(((-MaxIntense/100) * hp_per) + MaxIntense) -- -1/4 * hp% + max_intense , max_intense being the max intensity
	else
		if hp_per <= 5 then
			intensity = MaxIntense
		else
			intensity = math.floor(100/hp_per)
		end
		
	end
	if intensity == 0 then
		print("intensity was: ", intensity, " setting to 1")
		intensity = 1
	end
	return intensity
end



function OnPlayerSpawned()
    print("Player Spawned")
end

-- Hooking into player spawn event
function OnPlayerInitialized()
    print("Player Init")
    
end

function OnPlayerDied( player_entity )
	if PlayerLost then
		SetIntentsity(MaxIntense)
		TriggerShock()
	end
	ResetAllFlags()
end


-- Utility Functions and short hands

function SetTime(value)
    print("SetTime", value)

	if OldTime ~= value then
		AddFlagPersistent(ModIdent.."_time_" .. value)
		if OldTime ~= 0 then
			RemoveFlagPersistent(ModIdent.."_time_" .. OldTime)
		end
		OldTime = value
	end

	--StoreInt("shock_mod_time", 4, value)
end

function SetIntentsity(value)
    print("SetIntentsity", value)
	if OldIntense ~= value then
		AddFlagPersistent(ModIdent.."_intensity_" .. value)
		if OldIntense ~= 0 then
			RemoveFlagPersistent(ModIdent.."_intensity_" .. OldIntense)
		end
		OldIntense = value
	end



	--StoreInt("shock_mod_intensity", 5, value)
end

function TriggerShock()
    print("TriggerShock, setting flag: ".. ModIdent.."_trigger" .. "_" .. 1)
	if(AddFlagPersistent(ModIdent.."_trigger" .. "_" .. 1)) then
		print("flag set successfully")
	else
		print("flag set unsuccessfully, removing, readding")
		RemoveFlagPersistent(ModIdent.."_trigger" .. "_" .. 1)
		print("flag removed successfully")

		AddFlagPersistent(ModIdent.."_trigger" .. "_" .. 1)
		print("flag reset successfully")

	end
	-- StoreInt("shock_mod_shocking", 1 , 1)
	
end




function ResetAllFlags()
	print("resetting Flags")
	RequestCleanUp() -- this grew like this ok???
	print("resetting Flags sucessfully")
end


function RequestCleanUp()
	print("Cleaning up Flags")
	AddFlagPersistent("shockmod_cleanup")
end




--print("Example mod init done")