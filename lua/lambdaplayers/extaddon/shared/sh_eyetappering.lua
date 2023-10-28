local IsValid = IsValid
local net = net
local LocalPlayer = ( CLIENT and LocalPlayer )
local RandomPairs = RandomPairs
local ipairs = ipairs
local GetHumans = player.GetHumans
local surface_PlaySound = ( CLIENT and surface.PlaySound )
local AngleDifference = math.AngleDifference
local table_KeyFromValue = table.KeyFromValue

--

local smoothCamera = CreateClientConVar( "lambdaplayers_eyetapper_smoothcamera", "1", true, false, "If the camera should switch between views smoothly by the use of interpolation", 0, 1 )
local followKillerTime = CreateClientConVar( "lambdaplayers_eyetapper_followkillertime", "0", true, false, "If non-zero, after our Lambda Player dies, the camera will follow its killer for this period of time in seconds", 0, 60 )
local switchFromFPonDeath = CreateClientConVar( "lambdaplayers_eyetapper_switchfromfpondeath", "0", true, false, "If the camera should immediately switch from the first person view mode when a Lambda Player dies?", 0, 1 )
local dontStopOnTargetDeleted = CreateClientConVar( "lambdaplayers_eyetapper_dontquitontargetdeleted", "1", true, true, "If our current view target is deleted, should we switch to a random available one instead?", 0, 1 )
local viewPunching = CreateClientConVar( "lambdaplayers_eyetapper_viewpunching", "1", true, false, "If the camera view should receive a punch when the Lambda Player's weapon fires a bullet similar to real player one", 0, 1 )

local useCustomFPFov = CreateClientConVar( "lambdaplayers_eyetapper_usecustomfpfov", "0", true, false, "Should the first person camera view use custom field of view instead of the user one?", 0, 1 )
local firstPersonFov = CreateClientConVar( "lambdaplayers_eyetapper_fpfov", "90", true, false, "Custom first person camera view field of view", 0, 180 )

local tpCamOffset_Up = CreateClientConVar( "lambdaplayers_eyetapper_tpcamoffset_up", "0", true, false, "The up offset of the camera when using the third person camera mode.", -500, 500 )
local tpCamOffset_Right = CreateClientConVar( "lambdaplayers_eyetapper_tpcamoffset_right", "0", true, false, "The right offset of the camera when using the third person camera mode.", -500, 500 )
local tpCamOffset_Forward = CreateClientConVar( "lambdaplayers_eyetapper_tpcamoffset_forward", "-100", true, false, "The forward offset of the camera when using the third person camera mode.", -500, 500 )

local fixedCamOffset_Up = CreateClientConVar( "lambdaplayers_eyetapper_fixedcamoffset_up", "0", true, false, "The up offset of the camera when using the fixed camera mode.", -500, 500 )
local fixedCamOffset_Right = CreateClientConVar( "lambdaplayers_eyetapper_fixedcamoffset_right", "0", true, false, "The right offset of the camera when using the fixed camera mode.", -500, 500 )
local fixedCamOffset_Forward = CreateClientConVar( "lambdaplayers_eyetapper_fixedcamoffset_forward", "-100", true, false, "The forward offset of the camera when using the fixed camera mode.", -500, 500 )

--

LET = LET or {}

function LET:SetTarget( target, ply )
    if !ply and CLIENT then ply = LocalPlayer() end
    ply:SetNW2Entity( "lambda_eyetaptarget", target )

    if ( SERVER ) then
        net.Start( "lambdaeyetapper_settarget" )
            net.WriteEntity( target == nil and NULL or target )
        net.Send( ply )
    end
end

function LET:GetTarget( ply )
    if !ply and CLIENT then 
        ply = LocalPlayer() 
        if !IsValid( ply ) then return end
    end
    return ply:GetNW2Entity( "lambda_eyetaptarget" )
end

function LET:SetKiller( target, killer )
    target:SetNW2Entity( "lambda_eyetapkiller", killer )
    target:SetNW2Float( "lambda_eyetapkilltime", CurTime() )
end

function LET:GetKiller( target )
    return target:GetNW2Entity( "lambda_eyetapkiller" ), target:GetNW2Float( "lambda_eyetapkilltime" )
end

function LET:GetEyeTappers( target )
    local tappers = {}
    for _, ply in ipairs( GetHumans() ) do
        if LET:GetTarget( ply ) != target then continue end
        tappers[ #tappers + 1 ] = ply
    end
    return tappers
end

--

if ( CLIENT ) then
    local Lerp = Lerp
    local LerpVector = LerpVector
    local LerpAngle = LerpAngle
    local min = math.min
    local max = math.max
    local TraceLine = util.TraceLine
    local TraceHull = util.TraceHull
    local ScrW = ScrW
    local ScrH = ScrH
    local DrawText = draw.DrawText
    local tostring = tostring
    local uiScale = GetConVar( "lambdaplayers_uiscale" )
    local displayArmor = GetConVar( "lambdaplayers_displayarmor" )

    local calcViewTbl = { drawviewer = true }
    local camTrTbl = { filter = {}, mins = Vector( -10, -10, -5 ), maxs = Vector( 10, 10, 5 ) }
    local camOffVec = Vector()

    --

    net.Receive( "lambdaeyetapper_settarget", function()
        local target = net.ReadEntity()
        local prevTarget = LET.PrevTarget

        if !IsValid( prevTarget ) then 
            LET.CameraMode = 1
            LET.PrevTarget = nil
            LET.LastCamTarget = nil
            LET.ViewAngles = LocalPlayer():EyeAngles()
            LET.ViewPosition = LocalPlayer():EyePos()
            LET.ViewFOV = nil
        else
            LET:DrawTargetHead( prevTarget, true )
        end

        LET:SetTarget( target )
        LET.PrevTarget = target

        LET:SetCamInterpTime( 1 )
        surface_PlaySound( !IsValid( target ) and "buttons/combine_button2.wav" or "buttons/combine_button1.wav" )
    end )

    net.Receive( "lambdaeyetapper_setviewmode", function()
        local target = LET:GetTarget()
        if !IsValid( target ) then return end

        local camMode = LET.CameraMode
        if target:GetNoDraw() then
            LET.CameraMode = ( camMode != 3 and 3 or 1 )
        else
            LET.CameraMode = ( camMode + ( 1 * ( LocalPlayer():KeyDown( IN_SPEED ) and -1 or 1 ) ) )

            if LET.CameraMode > 3 then 
                LET.CameraMode = 1 
            elseif LET.CameraMode < 1 then
                LET.CameraMode = 3
            end
        end

        LET:SetCamInterpTime( 0.5 )
        surface_PlaySound( "buttons/lightswitch2.wav" )
    end )

    net.Receive( "lambdaeyetapper_weaponpunch", function()
        if ( CurTime() - LET.CamInterpStartTime ) < ( LET.CamInterpEndTime - 0.25 ) or !viewPunching:GetBool() then return end

        local camMode = LET.CameraMode
        if camMode == 1 then return end

        local force = net.ReadFloat()
        local num = net.ReadUInt( 12 )

        local punch = ( ( force / ( camMode != 3 and 5 or 4 ) ) * num )
        LET.ViewAngles:RotateAroundAxis( LET.ViewAngles:Right(), punch )
    end )

    --

    local function UpdateFonts()
        surface.CreateFont( "lambdaplayers_eyetapperfont", {
            font = "ChatFont",
            size = LambdaScreenScale( 15 + uiScale:GetFloat() ),
            weight = 0,
            shadow = true
        } )
    end

    UpdateFonts()
    cvars.AddChangeCallback( "lambdaplayers_uiscale", UpdateFonts, "LambdaET_UpdateFonts" )

    --

    local vector_fullscale = Vector( 1, 1, 1 )
    local function DrawChildrenBoneSize( target, parentId, draw )
        target:ManipulateBoneScale( parentId, draw and vector_fullscale or vector_origin )

        for _, childID in ipairs( target:GetChildBones( parentId ) ) do
            DrawChildrenBoneSize( target, childID, draw )
        end
    end
    
    function LET:DrawTargetHead( target, draw )
        local headBone = target:LookupBone( "ValveBiped.Bip01_Head1" )
        if !headBone then return end
        DrawChildrenBoneSize( target, headBone, draw )
    end

    function LET:SetCamInterpTime( duration )
        LET.CamInterpStartTime = CurTime()
        LET.CamInterpEndTime = duration
    end

    --

    local function LET_DrawHUD()
        local target = LET:GetTarget()
        if !IsValid( target ) then return end

		local sw, sh = ScrW(), ScrH()
		local dispClr = target:GetDisplayColor()
        local screenScale = LambdaScreenScale( 1 + uiScale:GetFloat() )

        DrawText( target:GetLambdaName(), "lambdaplayers_displayname", ( sw / 2 ), ( sh / 1.4 ), dispClr, TEXT_ALIGN_CENTER )

		if target:GetIsDead() then
			DrawText( "*DEAD*", "lambdaplayers_eyetapperfont", ( sw / 2 ), ( ( sh / 1.35 ) + screenScale ), dispClr, TEXT_ALIGN_CENTER )
        else
			DrawText( "State: " .. target:GetState(), "lambdaplayers_displayname", ( sw / 2 ), ( sh / 1.35 ), dispClr, TEXT_ALIGN_CENTER )

            local wepName = _LAMBDAPLAYERSWEAPONS[ target:GetWeaponName() ]
			if wepName and wepName.prettyname then
				wepName = wepName.prettyname
			else
				wepName = target:GetWeaponName()
			end
			DrawText( "Weapon: " .. wepName, "lambdaplayers_displayname", ( sw / 2 ), ( sh / 1.3 ), dispClr, TEXT_ALIGN_CENTER )

			local enemy = target:GetEnemy()
			if IsValid( enemy ) and ( target:IsPanicking() or target:InCombat() ) then
				local enemyName = ( ( enemy.IsLambdaPlayer or enemy:IsPlayer() ) and enemy:Nick() or language.GetPhrase( "#" .. enemy:GetClass() ) )
				if enemyName[ 1 ] == "#" then enemyName = enemy:GetClass() end
				DrawText( "Enemy: " .. enemyName .. " (" .. tostring( enemy ) .. ")", "lambdaplayers_displayname", ( sw / 2 ), ( sh / 1.25 ), dispClr, TEXT_ALIGN_CENTER )
			end

            local hp = target:GetNW2Float( "lambda_health", "NAN" )
			hp = ( hp == "NAN" and target:GetNWFloat( "lambda_health", "NAN" ) or hp )

            local hpW, armor = 2, target:GetArmor()
			if armor > 0 and displayArmor:GetBool() then
				hpW = 2.2
				DrawText( tostring( armor ) .. "%", "lambdaplayers_eyetapperfont", ( sw / 1.8 ), ( ( sh / 1.2 ) + screenScale ), dispClr, TEXT_ALIGN_CENTER )
			end
			DrawText( tostring( hp ) .. "%", "lambdaplayers_eyetapperfont", ( sw / hpW ), ( ( sh / 1.2 ) + screenScale ), dispClr, TEXT_ALIGN_CENTER )
        end
    end

    local function LET_CalcView( ply, origin, angles, fov, znear, zfar )
        if _LambdaIsTakingViewShot then return end

        local lambda = LET:GetTarget( ply )
        if !IsValid( lambda ) then return end
        
        local target = lambda
        local lastTarget = LET.LastCamTarget
        if target != lastTarget then
            LET.LastCamTarget = target
            if IsValid( lastTarget ) then LET:DrawTargetHead( lastTarget, true ) end
        end

        local camMode = LET.CameraMode
        local isRagdoll = false
        local prevTarget = target
        if lambda:GetNoDraw() then
            local ragdoll = lambda:GetRagdollEntity()
            if IsValid( ragdoll ) then 
                if !LET.DiedInFP and target == lastTarget and camMode == 3 and switchFromFPonDeath:GetBool() then
                    LET.DiedInFP = true
                    LET:SetCamInterpTime( 0.5 )

                    camMode = 1
                    LET.CameraMode = camMode
                end

                target = ragdoll
                isRagdoll = true
            end
        elseif LET.DiedInFP then
            LET.DiedInFP = false
            
            if target == lastTarget then
                LET:SetCamInterpTime( 0.5 )
                camMode = 3
                LET.CameraMode = camMode
            end
        end
        
        if camMode == 3 and lambda:IsPlayingTaunt() then
            camMode = 1

            if !LET.WasTaunting then
                LET.WasTaunting = true
                LET:SetCamInterpTime( 0.5 )
            end
        elseif LET.WasTaunting then
            LET.WasTaunting = false
            LET:SetCamInterpTime( 0.5 )
        end

        local viewPos, viewAng = LET.ViewPosition, LET.ViewAngles
        local targEyes = lambda:GetAttachmentPoint( "eyes", target )
        local facePos = lambda:GetNW2Vector( "lambda_facepos" )
        if camMode == 3 then
            viewPos = targEyes.Pos

            local eyeAng = targEyes.Ang
            if !isRagdoll then 
                local yawLimit = eyeAng.y
                if !facePos:IsZero() then
                    eyeAng = ( facePos - viewPos ):Angle()
                else
                    eyeAng.y = target:GetAngles().y
                end

                local angDiffY = AngleDifference( viewAng.y, yawLimit )
                if angDiffY > 75 then
                    viewAng.y = ( viewAng.y - ( angDiffY - 75 ) )
                elseif angDiffY < -75 then
                    viewAng.y = ( viewAng.y - ( angDiffY + 75 ) )
                end

                eyeAng.z = 0
                eyeAng = LerpAngle( 0.25, viewAng, eyeAng )
            end
            
            viewAng = eyeAng
        else
            local targPos = ( ( isRagdoll or camMode == 1 ) and target:WorldSpaceCenter() or targEyes.Pos )
            local camHeight = ( !isRagdoll and ( camMode == 1 and 32 or 8 ) or 16 )
            local camPos = ( targPos + vector_up * camHeight )
            local camAng = angles

            if isRagdoll then
                local followTime = followKillerTime:GetInt()
                local killer, killTime = LET:GetKiller( lambda )
    
                if killTime and followTime > 0 and IsValid( killer ) then 
                    local followPos
                    if ( killer.IsLambdaPlayer or killer:IsPlayer() ) and !killer:Alive() then
                        local killerRag = killer:GetRagdollEntity()
                        if IsValid( killerRag ) then followPos = killerRag:GetPos() end
                    end

                    if ( CurTime() - killTime ) <= followTime then
                        camAng = LerpAngle( 0.15, viewAng, ( ( followPos or lambda:GetAttachmentPoint( "eyes", killer ).Pos ) - viewPos ):Angle() )
                        LET.IsFollowingKiller = true
                    elseif LET.IsFollowingKiller then
                        LET.IsFollowingKiller = false
                        LET:SetCamInterpTime( 0.5 )
                    end
                end
            end

            camTrTbl.start = targPos
            camTrTbl.filter[ 1 ] = lambda
            camTrTbl.filter[ 2 ] = target
    
            local camOffset = ( camAng:Forward() * tpCamOffset_Forward:GetInt() + camAng:Right() * tpCamOffset_Right:GetInt() + camAng:Up() * tpCamOffset_Up:GetInt() )            
            local isFixedCam = ( camMode == 2 and !isRagdoll )
            if isFixedCam then
                if !facePos:IsZero() then
                    camAng = ( ( facePos - vector_up * camHeight ) - targPos ):Angle()
                else
                    camAng.x = targEyes.Ang.x
                    camAng.y = target:GetAngles().y
                    camAng.z = 0
                end
                camOffset = ( camAng:Forward() * fixedCamOffset_Forward:GetInt() + camAng:Right() * fixedCamOffset_Right:GetInt() + camAng:Up() * fixedCamOffset_Up:GetInt() )

                camTrTbl.endpos = ( targPos + camOffset + camAng:Forward() * 32756 )
                camAng = LerpAngle( 0.25, viewAng, ( TraceLine( camTrTbl ).HitPos - targPos ):Angle() )
            end

            camTrTbl.endpos = ( camPos + camOffset )
            camPos = TraceHull( camTrTbl ).HitPos

            viewPos = ( !isFixedCam and camPos or LerpVector( 0.25, viewPos, camPos ) )
            viewAng = camAng 
        end

        local camFov = ( ( camMode == 3 and useCustomFPFov:GetBool() ) and firstPersonFov:GetInt() or fov )
        local drawHead = true
        if smoothCamera:GetBool() then
            local duration = LET.CamInterpEndTime
            local timeElapsed = ( CurTime() - LET.CamInterpStartTime )
            local lerpFact = ( timeElapsed < duration and ( timeElapsed / duration ) or 1 )

            LET.ViewPosition = LerpVector( lerpFact, LET.ViewPosition, viewPos )
            LET.ViewAngles = LerpAngle( lerpFact, LET.ViewAngles, viewAng )

            local viewFOV = LET.ViewFOV
            LET.ViewFOV = ( !viewFOV and camFov or Lerp( lerpFact, viewFOV, camFov ) )

            drawHead = ( camMode != 3 or lerpFact < 0.5 )
        else
            LET.ViewPosition = viewPos
            LET.ViewAngles = viewAng
            LET.ViewFOV = camFov
            drawHead = ( camMode != 3 )
        end

        if !viewFOV then
            viewFOV = fov
        end

        LET:DrawTargetHead( target, drawHead )

        calcViewTbl.origin = LET.ViewPosition
        calcViewTbl.angles = LET.ViewAngles
        calcViewTbl.fov = LET.ViewFOV
        return calcViewTbl
    end

    hook.Add( "HUDPaint", "LambdaET_DrawHUD", LET_DrawHUD )
    hook.Add( "CalcView", "LambdaET_CalcView", LET_CalcView )
end

--

if ( SERVER ) then
    local AddOriginToPVS = AddOriginToPVS

    util.AddNetworkString( "lambdaeyetapper_settarget" )
    util.AddNetworkString( "lambdaeyetapper_setviewmode" )
    util.AddNetworkString( "lambdaeyetapper_weaponpunch" )

    local function LET_KeepTargetInPVS( ply )
        local target = LET:GetTarget( ply )
        if IsValid( target ) then 
            AddOriginToPVS( target:GetPos() )

            local killer = LET:GetKiller( target )
            if target:Alive() and IsValid( killer ) then
                AddOriginToPVS( killer:GetPos() )
            end
        end
    end

    local function LET_OnPlayerDeath( ply )
        LET:SetTarget( nil, ply )
    end

    local function LET_OnLambdaKilled( lambda, dmginfo )
        local attacker = dmginfo:GetAttacker()
        if attacker == lambda or !LambdaIsValid( attacker ) or !attacker:IsNPC() and !attacker:IsNextBot() and !attacker:IsPlayer() then return end
        LET:SetKiller( lambda, attacker )
    end

    local function LET_OnEntityFireBullets( ent, data )
        if !ent.IsLambdaWeapon then return end

        local owner = ent:GetParent()
        if !IsValid( owner ) or !owner.IsLambdaPlayer then return end

        local tappers = LET:GetEyeTappers( owner )
        if #tappers == 0 then return end

        net.Start( "lambdaeyetapper_weaponpunch" )
            net.WriteFloat( data.Force or 1 )
            net.WriteUInt( data.Num, 12 )
        net.Send( tappers )
    end

    hook.Add( "SetupPlayerVisibility", "LambdaET_KeepTargetInPVS", LET_KeepTargetInPVS )
    hook.Add( "PlayerDeath", "LambdaET_OnPlayerDeath", LET_OnPlayerDeath )
    hook.Add( "LambdaOnKilled", "LambdaET_OnLambdaKilled", LET_OnLambdaKilled )
    hook.Add( "EntityFireBullets", "LambdaET_OnEntityFireBullets", LET_OnEntityFireBullets )
end

local function LET_OnLambdaRemoved( lambda )
    if ( SERVER ) then
        local tappers = LET:GetEyeTappers( lambda )
        if #tappers == 0 then return end

        local switchTarget = lambda.l_recreatedlambda
        if !IsValid( switchTarget ) then 
            local lambdas = GetLambdaPlayers()
            if #lambdas == 1 then
                switchTarget = lambdas[ 1 ]
            else
                local curIndex = lambda:GetCreationID()
                for index, target in ipairs( lambdas ) do
                    if #lambdas == 1 or target:GetCreationID() > curIndex then
                        switchTarget = target
                        break
                    end
                    if index != #lambdas then continue end

                    local firstLambda = lambdas[ 1 ]
                    if firstLambda != target then switchTarget = lambdas[ 1 ] end
                end
                if !IsValid( switchTarget ) then return end
            end
        end

        for _, ply in ipairs( tappers ) do
            if ply:GetInfoNum( "lambdaplayers_eyetapper_dontquitontargetdeleted", 0 ) == 0 then continue end
            LET:SetTarget( switchTarget, ply )
        end
    elseif lambda == LET:GetTarget() and ( !dontStopOnTargetDeleted:GetBool() or #GetLambdaPlayers() <= 1 ) then
        surface_PlaySound( "buttons/combine_button_locked.wav" )
    end
end

hook.Add( "LambdaOnRemove", "LambdaET_OnLambdaRemoved", LET_OnLambdaRemoved )