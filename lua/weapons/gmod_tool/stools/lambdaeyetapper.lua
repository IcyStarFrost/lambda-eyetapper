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

    LET = LET or {}

    local function SetupLETTable( reset )
        LET.Lambda = ( !reset and LET.Lambda or NULL ) 
        LET.CamTarget = ( !reset and LET.CamTarget or LET.Lambda )
        LET.PreviousTarget = ( !reset and LET.PreviousTarget or LET.Lambda )

        LET.FirstPersonCam = ( !reset and LET.FirstPersonCam or false )
        LET.LastCamMode = ( !reset and LET.LastCamMode or LET.FirstPersonCam )
        LET.SnapAngles = ( !reset and LET.SnapAngles or false )
        
        LET.CurrentAngles = ( !reset and LET.CurrentAngles or Angle() )
        LET.CalcViewTbl = ( !reset and LET.CalcViewTbl or {} )
        LET.ShrinkBoneTbl = ( !reset and LET.ShrinkBoneTbl or {} )
    end
    SetupLETTable()

    -- Gets the position and angles of entity's eyes. Returns false if none is found.
    local function GetEyePosition( ent )
        if ent.IsLambdaPlayer then
            local eyesData = LET.Lambda:GetAttachmentPoint( "eyes" )
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
        target = target or LET.Lambda
        if !IsValid( target ) then return end

        for _, bone in ipairs( LET.ShrinkBoneTbl ) do
            target:ManipulateBoneScale( bone, ( !full and vector_origin or vector_fullscale ) )
        end
    end

    -- Changes the view from first to third or likewise
    net.Receive( "lambdaeyetapper_changeview", function() 
        ChangeHeadBoneScale( LET.FirstPersonCam )
        LET.FirstPersonCam = !LET.FirstPersonCam
    end )

    -- Eye tapping main code
    net.Receive( "lambdaeyetapper_changetarget", function( len, ply )
        local entindex = net.ReadInt( 32 )
        if entindex == -1 then 
            ChangeHeadBoneScale( true )
            ChangeHeadBoneScale( true, LET.CamTarget )
            SetupLETTable( true )
            return 
        end -- Exit eye tapping

        if IsValid( LET.Lambda ) and LET.FirstPersonCam then
            LET.SnapAngles = true
            ChangeHeadBoneScale( true )
            ChangeHeadBoneScale( true, LET.CamTarget )
        end

        LET.Lambda = Entity( entindex )
        if !IsValid( LET.Lambda ) then return end

        LET.PreviousTarget = LET.Lambda
        LET.ShrinkBoneTbl = net.ReadTable()

        ChangeHeadBoneScale( !LET.FirstPersonCam )

        -- Eye tap HUD showing health, armor, and the Lambda
        hook.Add( "HUDPaint", "lambdaeyetapperHUD", function() 
            if !IsValid( LET.Lambda ) or ( !IsValid( LocalPlayer() ) or !LocalPlayer():Alive() ) then 
                hook.Remove( "HUDPaint", "lambdaeyetapperHUD" ) 
                SetupLETTable( true )
                return 
            end 

            local sw, sh = ScrW(), ScrH()
            local name = LET.Lambda:GetLambdaName()
            local color = LET.Lambda:GetDisplayColor()
            
            DrawText( name, "lambdaplayers_displayname", ( sw / 2 ), ( sh / 1.4 ) , color, TEXT_ALIGN_CENTER )

            if !LET.Lambda:Alive() then
                DrawText( "*DEAD*", "lambdaplayers_eyetapperfont", ( sw / 2 ), ( sh / 1.35 ) + LambdaScreenScale( 1 + uiscale:GetFloat() ), color, TEXT_ALIGN_CENTER )
            else
                DrawText( "State: " .. LET.Lambda:GetState(), "lambdaplayers_displayname", ( sw / 2 ), ( sh / 1.35 ) , color, TEXT_ALIGN_CENTER )

                local wepName = _LAMBDAPLAYERSWEAPONS[ LET.Lambda:GetWeaponName() ]
                if wepName and wepName.prettyname then
                    wepName = wepName.prettyname
                else
                    wepName = LET.Lambda:GetWeaponName()
                end
                DrawText( "Weapon: " .. wepName, "lambdaplayers_displayname", ( sw / 2 ), ( sh / 1.3 ) , color, TEXT_ALIGN_CENTER )

                local enemy = LET.Lambda:GetEnemy()
                if IsValid( enemy ) and ( LET.Lambda:IsPanicking() or LET.Lambda:InCombat() ) then
                    local enemyName = ( ( enemy.IsLambdaPlayer or enemy:IsPlayer() ) and enemy:Nick() or language.GetPhrase( "#" .. enemy:GetClass() ) )
                    if enemyName[ 1 ] == "#" then enemyName = enemy:GetClass() end
                    DrawText( "Enemy: " .. enemyName .. " (" .. tostring( enemy ) .. ")", "lambdaplayers_displayname", ( sw / 2 ), ( sh / 1.25 ), color, TEXT_ALIGN_CENTER )
                end

                local hp = LET.Lambda:GetNW2Float( "lambda_health", "NAN" )
                hp = ( hp == "NAN" and LET.Lambda:GetNWFloat( "lambda_health", "NAN" ) or hp )
                
                local hpW = 2
                local armor = LET.Lambda:GetArmor()
                if armor > 0 and displayArmor:GetBool() then
                    hpW = 2.2
                    DrawText( tostring( armor ) .. "%", "lambdaplayers_eyetapperfont", ( sw / 1.8 ), ( sh / 1.2 ) + LambdaScreenScale( 1 + uiscale:GetFloat() ), color, TEXT_ALIGN_CENTER )
                end

                DrawText( tostring( hp ) .. "%", "lambdaplayers_eyetapperfont", ( sw / hpW ), ( sh / 1.2 ) + LambdaScreenScale( 1 + uiscale:GetFloat() ), color, TEXT_ALIGN_CENTER )
            end
        end )

        -- The view code
        local vecOffset = Vector( 0, 0, 32 )
        local vecRagOffset = Vector( 0, 0, 16 )
        hook.Add( "CalcView", "lambdaeyetapperCalcView", function( ply, origin, angles, fov, znear, zfar )
            if !IsValid( LET.Lambda ) or !IsValid( ply ) or !ply:Alive() then 
                hook.Remove( "CalcView", "lambdaeyetapperCalcView" ) 
                SetupLETTable( true )
                return 
            end 

            local ragdoll = LET.Lambda.ragdoll
            if !IsValid( ragdoll ) then ragdoll = LET.Lambda:GetNW2Entity( "lambda_serversideragdoll" ) end

            local eyePos, eyeAng
            local tpOnDeath = ply:GetInfo( "lambdaeyetapper_tpondeath" )
            local cameraView = LET.FirstPersonCam

            LET.CamTarget = ( ( LET.Lambda.IsLambdaPlayer and LET.Lambda:GetNoDraw() and IsValid( ragdoll ) ) and ragdoll or LET.Lambda )
            local eyeData, yawLimit = GetEyePosition( LET.CamTarget )

            if cameraView and ( LET.CamTarget != ragdoll or eyeData and !tobool( tpOnDeath ) ) then
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

                if LET.CamTarget != ragdoll then eyeAng.z = 0 end
                LET.CurrentAngles = ( ( LET.SnapAngles or LET.CamTarget == ragdoll ) and eyeAng or LerpAngle( 6 * FrameTime(), LET.CurrentAngles, eyeAng ) )
            else
                local aimVec = ply:GetAimVector()
                local tpZoom = ply:GetInfo( "lambdaeyetapper_tpzoom" )
                local zOffset = ( LET.CamTarget == ragdoll and vecRagOffset or vecOffset )

                tracetbl.start = LET.CamTarget:WorldSpaceCenter()
                tracetbl.endpos = ( ( tracetbl.start + zOffset ) - aimVec * tpZoom )
                tracetbl.filter = LET.CamTarget
                local collCheck = Trace( tracetbl )

                cameraView = false
                eyePos = ( ( tracetbl.start + zOffset ) - aimVec * ( tpZoom * ( collCheck.Fraction - 0.1 ) ) )
                eyeAng = ply:EyeAngles(); eyeAng.z = 0
                LET.CurrentAngles = eyeAng
            end

            if LET.LastCamMode != cameraView or LET.CamTarget != LET.PreviousTarget then
                if IsValid( LET.PreviousTarget ) then
                    ChangeHeadBoneScale( true, LET.PreviousTarget )
                    ChangeHeadBoneScale( !cameraView, LET.CamTarget )
                end

                LET.PreviousTarget = LET.CamTarget
            end

            LET.SnapAngles = ( cameraView != LET.LastCamMode or LET.CamTarget == ragdoll )
            LET.LastCamMode = cameraView

            LET.CalcViewTbl.origin = eyePos
            LET.CalcViewTbl.angles = LET.CurrentAngles
            LET.CalcViewTbl.fov = fov
            LET.CalcViewTbl.znear = znear
            LET.CalcViewTbl.zfar = zfar
            LET.CalcViewTbl.drawviewer = true

            return LET.CalcViewTbl
        end )
    end )

    -- Builds the tool's spawnmenu settings.
    function TOOL.BuildCPanel( cpanel )
        cpanel:NumSlider( "Third Person Zoom", "lambdaeyetapper_tpzoom", 64, 256, 0 )
        cpanel:ControlHelp( "Determines how far camera should be from Lambda Player when viewing from the third person view." )

        cpanel:CheckBox( "Force Third Person On Death", "lambdaeyetapper_tpondeath" )
        cpanel:ControlHelp( "If camera view should be in third person while viewing a currently dead Lambda Player" )
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
        local boneTbl = {}

        local headBone = target:LookupBone( "ValveBiped.Bip01_Head1" )
        if headBone then
            boneTbl[ #boneTbl + 1 ] = headBone
            ShrinkChildBones( target, headBone, boneTbl )
        end
        
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