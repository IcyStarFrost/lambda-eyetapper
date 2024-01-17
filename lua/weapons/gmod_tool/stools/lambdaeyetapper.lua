AddCSLuaFile()

TOOL.Tab = "Lambda Player"
TOOL.Category = "Tools"
TOOL.Name = "#tool.lambdaeyetapper"

if ( CLIENT ) then
    -- Tool info
    TOOL.Information = {
        { name = "left" },
        { name = "right" }
    }

    -- Tool localizations
    language.Add( "tool.lambdaeyetapper", "Lambda Eye Tapper")
    language.Add( "tool.lambdaeyetapper.name", "Lambda Eye Tapper")
    language.Add( "tool.lambdaeyetapper.desc", "Allows you to view through what a Lambda Player sees" )
    language.Add( "tool.lambdaeyetapper.left", "Fire onto a Lambda Player to see what they are seeing" )
    language.Add( "tool.lambdaeyetapper.right", "Press to tap into a random Lambda Player's view" )

    local cvarList = {
        [ "lambdaplayers_eyetapper_smoothcamera" ] = "1",
        [ "lambdaplayers_eyetapper_followkillertime" ] = "0",
        [ "lambdaplayers_eyetapper_switchfromfpondeath" ] = "0",
        [ "lambdaplayers_eyetapper_dontquitontargetdeleted" ] = "1",
        [ "lambdaplayers_eyetapper_viewpunching" ] = "1",
        [ "lambdaplayers_eyetapper_forcetpontaunting" ] = "0",
        [ "lambdaplayers_eyetapper_drawhaloonenemy" ] = "1",
        [ "lambdaplayers_eyetapper_weaponoriginonname" ] = "1",
        [ "lambdaplayers_eyetapper_displaystateenemy" ] = "1",
        [ "lambdaplayers_eyetapper_usecustomfpfov" ] = "0",
        [ "lambdaplayers_eyetapper_fpfov" ] = "90",
        [ "lambdaplayers_eyetapper_tpcamoffset_up" ] = "0",
        [ "lambdaplayers_eyetapper_tpcamoffset_right" ] = "0",
        [ "lambdaplayers_eyetapper_tpcamoffset_forward" ] = "-100",
        [ "lambdaplayers_eyetapper_fixedcamoffset_up" ] = "0",
        [ "lambdaplayers_eyetapper_fixedcamoffset_right" ] = "0",
        [ "lambdaplayers_eyetapper_fixedcamoffset_forward" ] = "-100",
        [ "lambdaplayers_eyetapper_fpcamoffset_up" ] = "0",
        [ "lambdaplayers_eyetapper_fpcamoffset_right" ] = "0",
        [ "lambdaplayers_eyetapper_fpcamoffset_forward" ] = "0",
    }

    -- Builds the tool's spawnmenu settings.
    function TOOL.BuildCPanel( panel )
        panel:ToolPresets( "lambdaeyetapper", cvarList )
        
        panel:CheckBox( "Smooth Camera View Switching", "lambdaplayers_eyetapper_smoothcamera" )
        panel:ControlHelp( "If the camera should switch between views smoothly by the use of interpolation" )

        panel:CheckBox( "Prevent Exit On Target Removal", "lambdaplayers_eyetapper_dontquitontargetdeleted" )
        panel:ControlHelp( "If our current view target is deleted, should we switch to a random available one instead" )

        panel:CheckBox( "Force Third Person On Death", "lambdaplayers_eyetapper_switchfromfpondeath" )
        panel:ControlHelp( "If the camera should be forced from first person to third person when the Lambda Player is dead" )
        
        panel:CheckBox( "Force Third Person On Animations", "lambdaplayers_eyetapper_forcetpontaunting" )
        panel:ControlHelp( "If the camera should be forced from first person to third person when the Lambda Player is playing special animation" )

        panel:CheckBox( "Draw Halo On Enemy/Killer", "lambdaplayers_eyetapper_drawhaloonenemy" )
        panel:ControlHelp( "If Lambda Player's current enemy/killer should have halo on them for user's easier tracking" )

        panel:NumSlider( "Follow Killer On Death Time", "lambdaplayers_eyetapper_followkillertime", 0, 60, 0 )
        panel:ControlHelp( "If non-zero, after our Lambda Player dies, the camera will follow its killer for the given amount of time in seconds" )

        panel:CheckBox( "Enable View Punching", "lambdaplayers_eyetapper_viewpunching" )
        panel:ControlHelp( "If the camera view should receive a punch when the Lambda Player's weapon fires a bullet similar to real player one" )

        panel:CheckBox( "Include Weapon's Category In HUD", "lambdaplayers_eyetapper_weaponoriginonname" )
        panel:ControlHelp( "If Lambda Player's weapon name on HUD should also include the category its located in" )
        
        panel:CheckBox( "Display State And Enemy In HUD", "lambdaplayers_eyetapper_displaystateenemy" )
        panel:ControlHelp( "If Lambda Player's current state and valid enemy should display alongside its name above the HUD" )

        panel:CheckBox( "Use Custom First Person FOV", "lambdaplayers_eyetapper_usecustomfpfov" )
        panel:ControlHelp( "Should the first person camera view use custom field of view instead of the user one" )

        panel:NumSlider( "First Person FOV", "lambdaplayers_eyetapper_fpfov", 54, 130, 0 )
        panel:ControlHelp( "Custom first person camera view field of view" )

        panel:Help( "Third Person Camera Offsets:" )
        panel:NumSlider( "Up", "lambdaplayers_eyetapper_tpcamoffset_up", -500, 500, 0 )
        panel:NumSlider( "Right", "lambdaplayers_eyetapper_tpcamoffset_right", -500, 500, 0 )
        panel:NumSlider( "Forward", "lambdaplayers_eyetapper_tpcamoffset_forward", -500, 500, 0 )

        panel:Help( "Fixed Camera Offsets:" )
        panel:NumSlider( "Up", "lambdaplayers_eyetapper_fixedcamoffset_up", -500, 500, 0 )
        panel:NumSlider( "Right", "lambdaplayers_eyetapper_fixedcamoffset_right", -500, 500, 0 )
        panel:NumSlider( "Forward", "lambdaplayers_eyetapper_fixedcamoffset_forward", -500, 500, 0 )
        
        panel:Help( "First Person Camera Offsets:" )
        panel:NumSlider( "Up", "lambdaplayers_eyetapper_fpcamoffset_up", -500, 500, 0 )
        panel:NumSlider( "Right", "lambdaplayers_eyetapper_fpcamoffset_right", -500, 500, 0 )
        panel:NumSlider( "Forward", "lambdaplayers_eyetapper_fpcamoffset_forward", -500, 500, 0 )
    end
end

local IsValid = IsValid
local RandomPairs = RandomPairs

-- Eye tap to a Lambda Player we're aiming at.
function TOOL:LeftClick( tr )
    if ( SERVER ) then
        local owner = self:GetOwner()
        if IsValid( LET:GetTarget( owner ) ) then return end

        local ent = tr.Entity
        if !LambdaIsValid( ent ) or !ent.IsLambdaPlayer then return end

        LET:SetTarget( ent, owner )
    end

    return false
end

-- Eye tap to a random alive Lambda Player.
function TOOL:RightClick( tr )
    if ( SERVER ) then
        local owner = self:GetOwner()
        if IsValid( LET:GetTarget( owner ) ) then return end

        for _, lambda in RandomPairs( GetLambdaPlayers() ) do
            LET:SetTarget( lambda, owner )
            break
        end
    end

    return false
end