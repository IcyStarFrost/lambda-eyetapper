AddCSLuaFile()

local IsValid = IsValid
local Trace = util.TraceLine
local tracetbl = {}
local net = net

TOOL.Tab = "Lambda Player"
TOOL.Category = "Tools"
TOOL.Name = "#tool.lambdaeyetapper"
TOOL.ClientConVar = {
    [ "tpzoom" ] = "128"
}

if ( CLIENT ) then

    local DrawText = draw.DrawText
    local uiscale = GetConVar( "lambdaplayers_uiscale" )
    local displayArmor = GetConVar( "lambdaplayers_displayarmor" )
    local ScrW = ScrW
    local ScrH = ScrH
    local tostring = tostring
    local LocalPlayer = LocalPlayer

    --- Fonts ---
    local function UpdateFont()
        surface.CreateFont( "lambdaplayers_eyetapperfont", {
            font = "ChatFont",
            size = LambdaScreenScale( 15 + uiscale:GetFloat() ),
            weight = 0,
            shadow = true
        })
    end
    UpdateFont()
    cvars.AddChangeCallback( "lambdaplayers_uiscale", UpdateFont, "lambdaeyetapperfont" )
    ---

    -- Tool info
    TOOL.Information = {
        { name = "left" },
        { name = "reload" },
        { name = "right" }
    }
        
    language.Add("tool.lambdaeyetapper", "Lambda Eye Tapper")
    language.Add("tool.lambdaeyetapper.name", "Lambda Eye Tapper")
    language.Add("tool.lambdaeyetapper.desc", "Allows you to view through what a Lambda Player sees" )
    language.Add("tool.lambdaeyetapper.left", "Fire onto a Lambda Player to see what they are seeing. Fire again to exit a Lambda's view" )
    language.Add("tool.lambdaeyetapper.right", "Right click to toggle from first person to third person camera views" )
    language.Add("tool.lambdaeyetapper.reload", "Reload to tap into a random Lambda Player's view" )
    --

    local self
    local fpMode = false
    local viewTbl = {}

    -- Gets the position and angles of entity's eyes. Returns false if none is found.
    local function GetEyePosition( ent )
        if ent.IsLambdaPlayer then
            local eyesData = self:GetAttachmentPoint( "eyes" )

            local ene = ent:GetEnemy()
            if IsValid( ene ) then 
                local enePos = ( ene.IsLambdaPlayer and ene:GetAttachmentPoint( "eyes" ).Pos or ( isfunction( ene.EyePos ) and ene:EyePos() or ene:WorldSpaceCenter() ) )
                eyesData.Ang = ( enePos - eyesData.Pos ):Angle()
            end

            return eyesData 
        end

        local eyesID = ent:LookupAttachment( "eyes" )
        if eyesID == 0 then
            local headBone = ent:LookupBone( "ValveBiped.Bip01_Head1" )
            if headBone then
                local headPos, headAng = ent:GetBonePosition( headBone )
                return { Pos = headPos, Ang = headAng }
            end
        else
            return ent:GetAttachment( eyesID )
        end

        return false
    end

    -- Changes the view from first to third or likewise
    net.Receive( "lambdaeyetapper_changeview", function() fpMode = !fpMode end )

    -- Eye tapping main code
    net.Receive( "lambdaeyetapper_changetarget", function()
        local entindex = net.ReadInt( 32 )
        if entindex == -1 then self = nil return end -- Exit eye tapping
        
        self = Entity( entindex )
        if !IsValid( self ) then return end

        -- Eye tap HUD showing health, armor, and the Lambda
        hook.Add( "HUDPaint", "lambdaeyetapperHUD", function() 
            if !IsValid( self ) or ( !IsValid( LocalPlayer() ) or !LocalPlayer():Alive() ) then hook.Remove( "HUDPaint", "lambdaeyetapperHUD" ) return end 

            local sw, sh = ScrW(), ScrH()

            local name = self:GetLambdaName()
            local color = self:GetDisplayColor()
            local hp = self:GetNW2Float( "lambda_health", "NAN" )
            local hpW = 2
            local armor = self:GetArmor()
            hp = hp == "NAN" and self:GetNWFloat( "lambda_health", "NAN" ) or hp

            if armor > 0 and displayArmor:GetBool() then
                hpW = 2.1
                DrawText( tostring( armor ) .. "%", "lambdaplayers_eyetapperfont", ( sw / 1.9 ), ( sh / 1.2 ) + LambdaScreenScale( 1 + uiscale:GetFloat() ), color, TEXT_ALIGN_CENTER )
            end

            DrawText( name, "lambdaplayers_displayname", ( sw / 2 ), ( sh / 1.3 ) , color, TEXT_ALIGN_CENTER )
            DrawText( ( self:Alive() and tostring( hp ) .. "%" or "*DEAD*" ), "lambdaplayers_eyetapperfont", ( sw / hpW ), ( sh / 1.2 ) + LambdaScreenScale( 1 + uiscale:GetFloat() ), color, TEXT_ALIGN_CENTER )
        end )

        -- The view code
        local vecOffset = Vector( 0, 0, 32 )
        local vecRagOffset = Vector( 0, 0, 16 )
        hook.Add( "CalcView", "lambdaeyetapperCalcView", function( ply, origin, angles, fov, znear, zfar )
            if !IsValid( self ) or !IsValid( ply ) or !ply:Alive() then hook.Remove( "CalcView", "lambdaeyetapperCalcView" ) return end 

            local ragdoll = self.ragdoll
            local targetEnt = ( ( self.IsLambdaPlayer and self:GetIsDead() and IsValid( ragdoll ) ) and ragdoll or self )

            local eyePos, eyeAng
            local eyeData = GetEyePosition( targetEnt )
            if fpMode and ( targetEnt != ragdoll or eyeData ) then
                eyePos = eyeData.Pos
                eyeAng = eyeData.Ang
                if targetEnt != ragdoll then eyeAng.z = 0 end
            else
                local aimVec = ply:GetAimVector()
                local tpZoom = ply:GetInfo( "lambdaeyetapper_tpzoom" )
                local zOffset = ( targetEnt == ragdoll and vecRagOffset or vecOffset )

                tracetbl.start = targetEnt:WorldSpaceCenter()
                tracetbl.endpos = ( ( tracetbl.start + zOffset ) - aimVec * tpZoom )
                tracetbl.filter = targetEnt
                local collCheck = Trace( tracetbl )

                eyePos = ( ( tracetbl.start + zOffset ) - aimVec * ( tpZoom * ( collCheck.Fraction - 0.1 ) ) )
                eyeAng = ply:EyeAngles(); eyeAng.z = 0
            end

            viewTbl.origin = eyePos
            viewTbl.angles = eyeAng
            viewTbl.fov = fov
            viewTbl.znear = znear
            viewTbl.zfar = zfar
            viewTbl.drawviewer = true

            return viewTbl
        end )
    end )

    -- Builds the tool's spawnmenu settings.
    function TOOL.BuildCPanel( cpanel )
        cpanel:NumSlider( "Third Person Zoom", "lambdaeyetapper_tpzoom", 64, 256, 0 )
        cpanel:ControlHelp( "Determines how far camera should be from Lambda Player when viewing from third person view." )
    end

end

if ( SERVER ) then

    local AddOriginToPVS = AddOriginToPVS
    local table_Empty = table.Empty
    local table_Count = table.Count
    local RandomPairs = RandomPairs

    util.AddNetworkString( "lambdaeyetapper_changetarget" )
    util.AddNetworkString( "lambdaeyetapper_changeview" )

    -- Add the Eye tapped entity's position to the PVS stuff
    hook.Add( "SetupPlayerVisibility", "lambdaeyetapperVis", function( ply, viewEnt )
        if !IsValid( ply.l_eyetapperent ) then return end
        AddOriginToPVS( ply.l_eyetapperent:GetPos() )
    end )

    -- When the player dies, stop and exit eye tapper.
    hook.Add( "PlayerDeath", "lambdaeyetapperPlayerDeath", function( ply )
        ply.l_eyetapperent = NULL
        if ply.l_eyetapperrolls then table_Empty( ply.l_eyetapperrolls ) end
    end )

    -- Eye tap to a Lambda Player we're aiming at.
    function TOOL:LeftClick( tr )
        local owner = self:GetOwner()
        if !owner.l_eyetapperrolls then 
            owner.l_eyetapperrolls = {} 
        else
            table_Empty( owner.l_eyetapperrolls ) 
        end

        if IsValid( owner.l_eyetapperent ) then
            net.Start( "lambdaeyetapper_changetarget" )
                net.WriteInt( -1, 32 )
            net.Send( owner )

            owner.l_eyetapperent = nil        
            return false
        end

        local ent = tr.Entity
        if !IsValid( ent ) or !ent.IsLambdaPlayer or ent:GetIsDead() then return end

        net.Start( "lambdaeyetapper_changetarget" )
            net.WriteInt( ent:EntIndex(), 32 )
        net.Send( owner )

        owner.l_eyetapperent = ent
        return true
    end

    -- Eye tap to a random alive Lambda Player.
    function TOOL:Reload()
        local owner = self:GetOwner()
        local lambdas = GetLambdaPlayers()
        
        if !owner.l_eyetapperrolls then 
            owner.l_eyetapperrolls = {} 
        elseif table_Count( owner.l_eyetapperrolls ) == #lambdas then 
            table_Empty( owner.l_eyetapperrolls ) 
        end

        local wasEyeTapping = IsValid( owner.l_eyetapperent )
        for _, v in RandomPairs( lambdas ) do
            if v == owner.l_eyetapperent or owner.l_eyetapperrolls[ v ] then continue end

            net.Start( "lambdaeyetapper_changetarget" )
                net.WriteInt( v:EntIndex(), 32 )
            net.Send( owner )

            owner.l_eyetapperrolls[ v ] = true
            owner.l_eyetapperent = v
            break
        end
        return !wasEyeTapping
    end

    -- Toggle between first and third person camera views.
    -- Stupid Prediction
    function TOOL:RightClick( tr )
        net.Start( "lambdaeyetapper_changeview" )
        net.Send( self:GetOwner() )
    end

end