AddCSLuaFile()

TOOL.Tab = "Lambda Player"
TOOL.Category = "Tools"
TOOL.Name = "#tool.lambdaeyetapper"

if ( CLIENT ) then
    -- Tool info
    TOOL.Information = {
        { name = "left" },
        { name = "right" },
        { name = "reload" },
        { name = "info" }
    }

    -- Tool localizations
    language.Add( "tool.lambdaeyetapper", "Lambda Eye Tapper")
    language.Add( "tool.lambdaeyetapper.name", "Lambda Eye Tapper")
    language.Add( "tool.lambdaeyetapper.desc", "Allows you to view through what a Lambda Player sees" )
    language.Add( "tool.lambdaeyetapper.left", "Fire onto a Lambda Player to see what they are seeing. Press again while viewing to exit" )
    language.Add( "tool.lambdaeyetapper.right", "When viewing no one or holding 'Left Alt' or the button assigned for walking, taps into a random Lambda Player. Otherwise, taps into a Lambda Player whose spawn index is lower or higher than ours" )
    language.Add( "tool.lambdaeyetapper.reload", "Reload to toggle between the camera view modes." )
    language.Add( "tool.lambdaeyetapper.0", "While holding 'Left Shift' or the button assigned for sprinting, both camera view mode and next lambda player toggles are reversed" )

    -- Builds the tool's spawnmenu settings.
    function TOOL.BuildCPanel( panel )
        panel:CheckBox( "Smooth Camera View Switching", "lambdaplayers_eyetapper_smoothcamera" )
        panel:ControlHelp( "If the camera should switch between views smoothly by the use of interpolation" )

        panel:CheckBox( "Prevent Exit On Target Removal", "lambdaplayers_eyetapper_dontquitontargetdeleted" )
        panel:ControlHelp( "If our current view target is deleted, should we switch to a random available one instead?" )

        panel:CheckBox( "Switch From First Person On Death", "lambdaplayers_eyetapper_switchfromfpondeath" )
        panel:ControlHelp( "If the camera should immediately switch from the first person view mode when a Lambda Player dies?" )

        panel:CheckBox( "Enable View Punching", "lambdaplayers_eyetapper_viewpunching" )
        panel:ControlHelp( "If the camera view should receive a punch when the Lambda Player's weapon fires a bullet similar to real player one" )

        panel:NumSlider( "Follow Killer On Death Time", "lambdaplayers_eyetapper_followkillertime", 0, 60, 0 )
        panel:ControlHelp( "If non-zero, after our Lambda Player dies, the camera will follow its killer for the given amount of time in seconds" )

        panel:CheckBox( "Use Custom First Person FOV", "lambdaplayers_eyetapper_usecustomfpfov" )
        panel:ControlHelp( "Should the first person camera view use custom field of view instead of the user one?" )

        panel:NumSlider( "First Person FOV", "lambdaplayers_eyetapper_fpfov", 54, 130, 0 )
        panel:ControlHelp( "Custom first person camera view field of view" )

        panel:Help( "Third Person Camera Offsets:" )
        panel:NumSlider( "Camera Offset - Up", "lambdaplayers_eyetapper_tpcamoffset_up", -500, 500, 0 )
        panel:NumSlider( "Camera Offset - Right", "lambdaplayers_eyetapper_tpcamoffset_right", -500, 500, 0 )
        panel:NumSlider( "Camera Offset - Forward", "lambdaplayers_eyetapper_tpcamoffset_forward", -500, 500, 0 )

        panel:Help( "Fixed Camera Offsets:" )
        panel:NumSlider( "Camera Offset - Up", "lambdaplayers_eyetapper_fixedcamoffset_up", -500, 500, 0 )
        panel:NumSlider( "Camera Offset - Right", "lambdaplayers_eyetapper_fixedcamoffset_right", -500, 500, 0 )
        panel:NumSlider( "Camera Offset - Forward", "lambdaplayers_eyetapper_fixedcamoffset_forward", -500, 500, 0 )
    end
end

local IsValid = IsValid
local table_Reverse = table.Reverse
local RandomPairs = RandomPairs
local ipairs = ipairs
local net = net
local table_KeyFromValue = table.KeyFromValue

-- Eye tap to a Lambda Player we're aiming at.
function TOOL:LeftClick( tr )
    if ( SERVER ) then
        local owner = self:GetOwner()
        local ent = ( !IsValid( LET:GetTarget( owner ) ) and tr.Entity )

        if ent and ( !LambdaIsValid( ent ) or !ent.IsLambdaPlayer ) then return end
        LET:SetTarget( ent, self:GetOwner() )
    end

    return false
end

-- Eye tap to a random alive Lambda Player.
function TOOL:RightClick( tr )
    if ( SERVER ) then
        local owner = self:GetOwner()
        local curTarg = LET:GetTarget( owner )

        if !IsValid( curTarg ) or owner:KeyDown( IN_WALK ) then
            for _, lambda in RandomPairs( GetLambdaPlayers() ) do
                LET:SetTarget( lambda, owner ); break
            end
        else
            local lambdas = GetLambdaPlayers()
            if owner:KeyDown( IN_SPEED ) then lambdas = table_Reverse( lambdas ) end

            local curIndex = table_KeyFromValue( lambdas, curTarg )
            for index, lambda in ipairs( lambdas ) do
                if index > curIndex then
                    LET:SetTarget( lambda, owner )
                    break
                end
                if index != #lambdas then continue end

                local firstLambda = lambdas[ 1 ]
                if firstLambda != curTarg then LET:SetTarget( lambdas[ 1 ], owner ) end
            end
        end
    end

    return false
end

function TOOL:Reload()
    if ( SERVER ) then
        net.Start( "lambdaeyetapper_setviewmode" )
        net.Send( self:GetOwner() )
    end
end