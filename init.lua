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
PlayerLost = true

OldHp = -1
OldHpMax = -1


function OnModPreInit()
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
	if hp_per >= 99 then
		return
	end
	if hp<OldHp then
		local delta = math.floor(OldHp-hp)
		if delta == 0 then
			delta =  1
		end
		SetTime(delta)
		TriggerShock()
	end

	local intensity = CalculateIntensity(hp, hp_max)
	print("Player HP: " .. hp .. " / " .. hp_max)
	print("Current intensity: ", intensity)
	SetIntentsity(math.floor(intensity))

	ResetShock()
end

function CalculateIntensity(hp, hp_max)
	local intensity = 1
	local hp_per = math.floor(100*hp/hp_max)
	print("HP Percentage: ", hp_per)
	if (Linear) then
		
		intensity = math.floor(-hp_per/4 + 25) -- 1/4 * hp% + 25 , 25 being the max intensity
	else
		if hp_per <= 5 then
			intensity = 25
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
		SetIntentsity(25)
		TriggerShock()
	end
	ResetAllFlags()
end


-- Utility Functions and short hands

function SetTime(value)
    print("SetTime", value)

	StoreInt("shock_mod_time", 4, value)
end

function SetIntentsity(value)
    print("SetIntentsity", value)

	StoreInt("shock_mod_intensity", 5, value)
end

function TriggerShock()
    print("TriggerShock")

	StoreInt("shock_mod_shocking", 1 , 1)
	
end

function ResetShock()
    print("ResetShock")

	StoreInt("shock_mod_shocking", 1 , 0)
	
end

function ResetAllFlags()
	print("resetting Flags")
	SetIntentsity(0)
	SetTime(0)
	ResetShock()
	print("resetting Flags sucessfully")
end


-- Incredible hack thanks to Horscht
function StoreInt(name, num_bits, val)
	if type(val) ~= "number" then
	  error("value must be a number")
	end
  
	for i=1, num_bits do
	  if bit.band(val, 1) == 1 then
		AddFlagPersistent(name .. "_" .. i)
	  else
		RemoveFlagPersistent(name .. "_" .. i)
	  end
	  val = bit.rshift(val, 1)
	end
  end
  
function RetrieveInt(name, num_bits)
	local value = 0
	for i=1, num_bits do
	  local bit = HasFlagPersistent(name .. "_" .. i) and 1 or 0
	  if bit > 0 then
		value = value + 2 ^ (i - 1)
	  end
	end
	return value
end



function OnMagicNumbersAndWorldSeedInitialized() -- this is the last point where the Mod* API is available. after this materials.xml will be loaded.
	local x = ProceduralRandom(0,0)
	print( "===================================== random " .. tostring(x) )
end


-- This code runs when all mods' filesystems are registered
-- ModLuaFileAppend( "data/scripts/gun/gun_actions.lua", "mods/example/files/actions.lua" ) -- Basically dofile("mods/example/files/actions.lua") will appear at the end of gun_actions.lua
-- ModMagicNumbersFileAdd( "mods/example/files/magic_numbers.xml" ) -- Will override some magic numbers using the specified file

-- see tools_modding/noita_fmod_project/ for the project that defines the audio events used in this mod
-- ModRegisterAudioEventMappings( "mods/example/files/audio_events.txt" ) -- Use this to register custom fmod events. Event mapping files can be generated via File -> Export GUIDs in FMOD Studio.
-- ModRegisterMusicBank( "mods/example/files/music.bank" ) -- Use this to register custom banks in the music system. ModRegisterAudioEventMappings also needs to be called to make the game recognize the events.

ModMaterialsFileAdd( "mods/example/files/materials_rainbow.xml" ) -- Adds a new 'rainbow' material to materials
ModLuaFileAppend( "data/scripts/items/potion.lua", "mods/example/files/potion_appends.lua" )

-- make coalmine play music from the new bank
local coal_xml = ModTextFileGetContent( "data/biome/coalmine.xml" )
coal_xml = coal_xml:gsub([[audio_music_2="coalmine"]], [[audio_music_2="thebiome"]] )
ModTextFileSetContent( "data/biome/coalmine.xml", coal_xml )


if ModImageMakeEditable ~= nil then -- needed to avoid error if this file is hotloaded after init
	-- make the player sprite green
	local t1 = GameGetRealWorldTimeSinceStarted();

	local recolor = function( filename)
		local id,w,h = ModImageMakeEditable( filename, 0, 0 )
		for y=0,h do 
			for x=0,w do
				local c = ModImageGetPixel( id, x, y )
	    		local r,g,b,a = color_abgr_split( c )
	    		r = r / 2
	    		b = b / 2
	    		c = color_abgr_merge(r,g,b,a)
				ModImageSetPixel( id, x, y, c )
			end
		end
	end

	-- using different slots here to test the feature works, 
	-- but you could use the same slot when editing images independent of each other like this
	recolor( "data/enemies_gfx/player.png" )
	recolor( "data/enemies_gfx/player_arm.png" )
	recolor( "data/enemies_gfx/player_arm_no_item.png" )

	t1 = GameGetRealWorldTimeSinceStarted() -t1
	print("ModImage stuff took " .. t1 .. " seconds")

	local who_edited = ModImageWhoSetContent( "data/enemies_gfx/player.png" )
	local ok = " - fail"
	if who_edited == "example" then ok = " - ok" end

	print( "Who edited? " .. who_edited .. ok )
end

--print("Example mod init done")