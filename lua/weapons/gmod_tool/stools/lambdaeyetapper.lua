AddCSLuaFile()

local IsValid = IsValid
local Trace = util.TraceLine
local tracetbl = {}
local net = net

TOOL.Tab = "Lambda Player"
TOOL.Category = "Tools"
TOOL.Name = "#tool.lambdaeyetapper"
TOOL.ClientConVar = {
    [ "tpzoom" ] = "128",
    [ "tpondeath" ] = "0"
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
    local lastMode = fpMode
    local viewTbl = {}
    local curLookAng = angle_zero
    local snapAngles = false
    local targetShrinkBoneTbl = {}
    local prevTarget = self

    local function ResetEyeTapperInfo()
        self = NULL
        fpMode = false
        lastMode = fpMode
        viewTbl = {}
        curLookAng = angle_zero
        snapAngles = false
        targetShrinkBoneTbl = {}
        prevTarget = self
    end

    -- Gets the position and angles of entity's eyes. Returns false if none is found.
    local function GetEyePosition( ent )
        if ent.IsLambdaPlayer then
            local eyesData = self:GetAttachmentPoint( "eyes" )
            local yawLimit = eyesData.Ang.y
            
            if ent:InCombat() and ent:GetIsFiring() then
                local ene = ent:GetEnemy()
                local enePos = ( ene.IsLambdaPlayer and ene:GetAttachmentPoint( "eyes" ).Pos or ( isfunction( ene.EyePos ) and ene:EyePos() or ene:WorldSpaceCenter() ) )
                eyesData.Ang = ( enePos - eyesData.Pos ):Angle()
            end

            return eyesData, yawLimit
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

    local vector_fullscale = Vector( 1, 1, 1 )

    local function ChangeHeadBoneScale( full, target )
        target = target or self
        for _, bone in ipairs( targetShrinkBoneTbl ) do
            target:ManipulateBoneScale( bone, ( !full and vector_origin or vector_fullscale ) )
        end
    end

    -- Changes the view from first to third or likewise
    net.Receive( "lambdaeyetapper_changeview", function() 
        ChangeHeadBoneScale( fpMode )
        fpMode = !fpMode
    end )

    -- Eye tapping main code
    net.Receive( "lambdaeyetapper_changetarget", function( len, ply )
        local entindex = net.ReadInt( 32 )
        if entindex == -1 then 
            ChangeHeadBoneScale( true )
            ResetEyeTapperInfo()
            return 
        end -- Exit eye tapping

        if IsValid( self ) and fpMode then
            snapAngles = true
            ChangeHeadBoneScale( true )
        end

        self = Entity( entindex )
        if !IsValid( self ) then return end

        prevTarget = self
        targetShrinkBoneTbl = net.ReadTable()

        ChangeHeadBoneScale( !fpMode )

        -- Eye tap HUD showing health, armor, and the Lambda
        hook.Add( "HUDPaint", "lambdaeyetapperHUD", function() 
            if !IsValid( self ) or ( !IsValid( LocalPlayer() ) or !LocalPlayer():Alive() ) then 
                hook.Remove( "HUDPaint", "lambdaeyetapperHUD" ) 
                ResetEyeTapperInfo()
                return 
            end 

            local sw, sh = ScrW(), ScrH()
            local name = self:GetLambdaName()
            local color = self:GetDisplayColor()
            
            DrawText( name, "lambdaplayers_displayname", ( sw / 2 ), ( sh / 1.3 ) , color, TEXT_ALIGN_CENTER )

            if !self:Alive() then
                DrawText( "*DEAD*", "lambdaplayers_eyetapperfont", ( sw / 2 ), ( sh / 1.2 ) + LambdaScreenScale( 1 + uiscale:GetFloat() ), color, TEXT_ALIGN_CENTER )
            else
                local hp = self:GetNW2Float( "lambda_health", "NAN" )
                hp = ( hp == "NAN" and self:GetNWFloat( "lambda_health", "NAN" ) or hp )
                
                local hpW = 2
                local armor = self:GetArmor()
                if armor > 0 and displayArmor:GetBool() then
                    hpW = 2.1
                    DrawText( tostring( armor ) .. "%", "lambdaplayers_eyetapperfont", ( sw / 1.9 ), ( sh / 1.2 ) + LambdaScreenScale( 1 + uiscale:GetFloat() ), color, TEXT_ALIGN_CENTER )
                end

                DrawText( tostring( hp ) .. "%", "lambdaplayers_eyetapperfont", ( sw / hpW ), ( sh / 1.2 ) + LambdaScreenScale( 1 + uiscale:GetFloat() ), color, TEXT_ALIGN_CENTER )
            end
        end )

        -- The view code
        local vecOffset = Vector( 0, 0, 32 )
        local vecRagOffset = Vector( 0, 0, 16 )
        hook.Add( "CalcView", "lambdaeyetapperCalcView", function( ply, origin, angles, fov, znear, zfar )
            if !IsValid( self ) or !IsValid( ply ) or !ply:Alive() then 
                hook.Remove( "CalcView", "lambdaeyetapperCalcView" ) 
                ResetEyeTapperInfo()
                return 
            end 

            local ragdoll = self.ragdoll
            if !IsValid( ragdoll ) then ragdoll = self:GetNW2Entity( "lambda_serversideragdoll" ) end
            local targetEnt = ( ( self.IsLambdaPlayer and self:GetIsDead() and IsValid( ragdoll ) ) and ragdoll or self )

            local eyePos, eyeAng
            local eyeData, yawLimit = GetEyePosition( targetEnt )
            local tpOnDeath = ply:GetInfo( "lambdaeyetapper_tpondeath" )
            local cameraView = fpMode

            if cameraView and ( targetEnt != ragdoll or eyeData and !tobool( tpOnDeath ) ) then
                eyePos = eyeData.Pos
                eyeAng = eyeData.Ang
                
                if yawLimit then
                    local angDiffY = math.AngleDifference( eyeAng.y, yawLimit )
                    if angDiffY > 90 then
                        eyeAng.y = ( eyeAng.y - ( angDiffY - 90 ) )
                    elseif angDiffY < -90 then
                        eyeAng.y = ( eyeAng.y - ( angDiffY + 90 ) )
                    end
                end

                if targetEnt != ragdoll then eyeAng.z = 0 end
                curLookAng = ( ( snapAngles or targetEnt == ragdoll ) and eyeAng or LerpAngle( 6 * FrameTime(), curLookAng, eyeAng ) )
            else
                local aimVec = ply:GetAimVector()
                local tpZoom = ply:GetInfo( "lambdaeyetapper_tpzoom" )
                local zOffset = ( targetEnt == ragdoll and vecRagOffset or vecOffset )

                tracetbl.start = targetEnt:WorldSpaceCenter()
                tracetbl.endpos = ( ( tracetbl.start + zOffset ) - aimVec * tpZoom )
                tracetbl.filter = targetEnt
                local collCheck = Trace( tracetbl )

                cameraView = false
                eyePos = ( ( tracetbl.start + zOffset ) - aimVec * ( tpZoom * ( collCheck.Fraction - 0.1 ) ) )
                eyeAng = ply:EyeAngles(); eyeAng.z = 0
                curLookAng = eyeAng
            end

            if lastMode != cameraView or targetEnt != prevTarget then
                if IsValid( prevTarget ) then
                    ChangeHeadBoneScale( true, prevTarget )
                    ChangeHeadBoneScale( !cameraView, targetEnt )
                end

                prevTarget = targetEnt
            end

            snapAngles = ( cameraView != lastMode or targetEnt == ragdoll )
            lastMode = cameraView

            viewTbl.origin = eyePos
            viewTbl.angles = curLookAng
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

        cpanel:CheckBox( "Force Third Person On Death", "lambdaeyetapper_tpondeath" )
        cpanel:ControlHelp( "If camera view should be in third person while viewing a dead Lambda Player" )
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

    local function ShrinkChildBones( target, parentId, boneTbl )
        for _, childID in ipairs( target:GetChildBones( parentId ) ) do
            boneTbl[ #boneTbl + 1 ] = childID
            ShrinkChildBones( target, childID, boneTbl )
        end
    end

    local function GetShrinkHeadBones( target )
        local headBone = target:LookupBone( "ValveBiped.Bip01_Head1" )
        if !headBone then return end

        local boneTbl = {}
        boneTbl[ #boneTbl + 1 ] = headBone
        ShrinkChildBones( target, headBone, boneTbl )
        return boneTbl
    end

    -- Eye tap to a Lambda Player we're aiming at.
    function TOOL:LeftClick( tr )
        local owner = self:GetOwner()
        
        local rolls = owner.l_eyetapperrolls
        if !rolls then
            rolls = {}
            owner.l_eyetapperrolls = rolls
        else
            table_Empty( rolls ) 
        end

        if IsValid( owner.l_eyetapperent ) then
            net.Start( "lambdaeyetapper_changetarget" )
                net.WriteInt( -1, 32 )
            net.Send( owner )

            owner.l_eyetapperent = nil        
            return false
        end

        local ent = tr.Entity
        if !LambdaIsValid( ent ) or !ent.IsLambdaPlayer then return end

        net.Start( "lambdaeyetapper_changetarget" )
            net.WriteInt( ent:EntIndex(), 32 )
            net.WriteTable( GetShrinkHeadBones( ent ) )
        net.Send( owner )

        owner.l_eyetapperent = ent
        return true
    end

    -- Eye tap to a random alive Lambda Player.
    function TOOL:Reload()
        local owner = self:GetOwner()
        local lambdas = GetLambdaPlayers()

        local rolls = owner.l_eyetapperrolls
        if !rolls then
            rolls = {}
            owner.l_eyetapperrolls = rolls
        elseif table_Count( rolls ) == #lambdas then 
            table_Empty( rolls ) 
        end

        local prevEnt = owner.l_eyetapperent
        local wasEyeTapping = IsValid( prevEnt )
        
        for _, v in RandomPairs( lambdas ) do
            if v == prevEnt or rolls[ v ] then continue end

            net.Start( "lambdaeyetapper_changetarget" )
                net.WriteInt( v:EntIndex(), 32 )
                net.WriteTable( GetShrinkHeadBones( v ) )
            net.Send( owner )

            rolls[ v ] = true
            owner.l_eyetapperent = v

            return !wasEyeTapping
        end
        
        return false
    end

    -- Toggle between first and third person camera views.
    -- Stupid Prediction
    function TOOL:RightClick( tr )
        net.Start( "lambdaeyetapper_changeview" )
        net.Send( self:GetOwner() )
    end

end