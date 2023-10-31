local IsValid = IsValid
local net = net
local LocalPlayer = ( CLIENT and LocalPlayer )
local RandomPairs = RandomPairs
local ipairs = ipairs
local GetHumans = player.GetHumans
local surface_PlaySound = ( CLIENT and surface.PlaySound )
local AngleDifference = math.AngleDifference
local ents_GetAll = ents.GetAll
local CurTime = CurTime

--

local smoothCamera = CreateClientConVar( "lambdaplayers_eyetapper_smoothcamera", "1", true, false, "If the camera should switch between views smoothly by the use of interpolation", 0, 1 )
local followKillerTime = CreateClientConVar( "lambdaplayers_eyetapper_followkillertime", "0", true, false, "If non-zero, after our Lambda Player dies, the camera will follow its killer for this period of time in seconds", 0, 60 )
local switchFromFPonDeath = CreateClientConVar( "lambdaplayers_eyetapper_switchfromfpondeath", "0", true, false, "If the camera should be forced from first person to third person when the Lambda Player is dead", 0, 1 )
local dontStopOnTargetDeleted = CreateClientConVar( "lambdaplayers_eyetapper_dontquitontargetdeleted", "1", true, true, "If our current view target is deleted, should we switch to a random available one instead", 0, 1 )
local viewPunching = CreateClientConVar( "lambdaplayers_eyetapper_viewpunching", "1", true, false, "If the camera view should receive a punch when the Lambda Player's weapon fires a bullet similar to real player one", 0, 1 )
local forcetpontaunt = CreateClientConVar( "lambdaplayers_eyetapper_forcetpontaunting", "0", true, false, "If the camera should be forced from first person to third person when the Lambda Player is playing special animation", 0, 1 )
local drawHaloOnEnemy = CreateClientConVar( "lambdaplayers_eyetapper_drawhaloonenemy", "1", true, false, "If Lambda Player's current enemy/killer should have halo on them for user's easier tracking", 0, 1 )

local useCustomFPFov = CreateClientConVar( "lambdaplayers_eyetapper_usecustomfpfov", "0", true, false, "Should the first person camera view use custom field of view instead of the user one", 0, 1 )
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
    if ( SERVER ) then
        if !LET.InEyeTapMode[ ply ] and IsValid( target ) then
            ply:SetNoTarget( true )
            ply:DrawShadow( false )
            ply:SetNoDraw( true )
            ply:SetMoveType( MOVETYPE_OBSERVER )
            ply:SetCollisionGroup( COLLISION_GROUP_IN_VEHICLE )
            ply:DrawViewModel( false )

            local savedWeps = {}
            for _, wep in ipairs( ply:GetWeapons() ) do
                savedWeps[ #savedWeps + 1 ] = { wep:GetClass(), wep:Clip1(), wep:Clip2() }
            end
            ply:StripWeapons()

            LET.PreEyeTapData[ ply ] = {
                ply:EyeAngles(),
                savedWeps
            }
            LET.LastKeyPress[ ply ] = ( CurTime() + 0.5 )
            LET.InEyeTapMode[ ply ] = true

            for _, ent in ipairs( ents_GetAll() ) do
                if ent == ply or !IsValid( ent ) then continue end

                local isNextbot = ent:IsNextBot()
                if !isNextbot and ent:IsNPC() then
                    if ent:GetEnemy() == ply then
                        ent:SetEnemy( NULL )
                    end
                    ent:ClearEnemyMemory( ply )
                elseif isNextbot then
                    if ent.GetEnemy and ent:GetEnemy() == ply then
                        ent:SetEnemy( NULL )

                        if ent.IsLambdaPlayer and ent:GetState( "Combat" ) then
                            ent:CancelMovement()
                            ent:SetState()
                        end
                    end
                end
            end
        end

        net.Start( "lambdaeyetapper_settarget" )
            net.WriteEntity( target == nil and NULL or target )
        net.Send( ply )
    end

    if !ply and CLIENT then ply = LocalPlayer() end
    ply:SetNW2Entity( "lambdaeyetap_target", target )
end

function LET:GetTarget( ply )
    if !ply and CLIENT then 
        ply = LocalPlayer() 
        if !IsValid( ply ) then return end
    end
    return ply:GetNW2Entity( "lambdaeyetap_target" )
end

function LET:SetKiller( target, killer )
    target:SetNW2Entity( "lambdaeyetap_killer", killer )
end

function LET:GetKiller( target )
    return target:GetNW2Entity( "lambdaeyetap_killer" )
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
    local FrameTime = FrameTime
    local min = math.min
    local max = math.max
    local TraceLine = util.TraceLine
    local TraceHull = util.TraceHull
    local ScrW = ScrW
    local ScrH = ScrH
    local DrawText = draw.DrawText
    local RoundedBox = draw.RoundedBox
    local RoundedBoxEx = draw.RoundedBoxEx
    local ceil = math.ceil
    local floor = math.floor
    local sub = string.sub
    local tostring = tostring
    local RealTime = RealTime
    local SetTextFont = surface.SetFont
    local GetTextFontSize = surface.GetTextSize
    local CreateFont = surface.CreateFont
    local halo_Add = halo.Add
    local GetPhrase = language.GetPhrase
    local input_IsKeyDown = input.IsKeyDown
    local input_LookupBinding = input.LookupBinding
    local input_GetKeyCode = input.GetKeyCode

    local calcViewTbl = {}
    local camTrTbl = { filter = {}, mins = Vector( -10, -10, -5 ), maxs = Vector( 10, 10, 5 ) }
    local camOffVec = Vector()
    local hudBoxClr = Color( 0, 0, 0, 125 )

    --

    net.Receive( "lambdaeyetapper_setviewmode", function()
        local target = LET:GetTarget()
        if !IsValid( target ) then return end

        local camMode = LET.CameraMode
        if target:GetNoDraw() then
            LET.CameraMode = ( camMode != 3 and 3 or 1 )
        else
            LET.CameraMode = ( camMode + 1 )

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

        local punch = ( ( force / ( camMode != 3 and 6 or 5 ) ) * num )
        LET.ViewAngles:RotateAroundAxis( LET.ViewAngles:Right(), punch )
    end )

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

            LET.HUD_ReloadStartTime = CurTime()
            LET.HUD_HintsWidth = 0
            LET.HUD_HintsTime = ( CurTime() + 5 )
        else
            LET:DrawTargetHead( prevTarget, true )
        end

        LET:SetTarget( target )
        LET.PrevTarget = target

        LET:SetCamInterpTime( 1 )
        surface_PlaySound( !IsValid( target ) and "buttons/combine_button2.wav" or "buttons/combine_button1.wav" )
    end )

    --

    CreateFont( "letfont_hparmor", {
        font = "BoxRocket",
        size = LambdaScreenScale( 25 ),
        weight = 500
    } )
    CreateFont( "letfont_hparmor_text", {
        font = "Verdana",
        size = LambdaScreenScale( 7.5 ),
        italic = true,
        weight = 1000
    } )
    CreateFont( "letfont_lambdaname", {
        font = "Arial",
        size = LambdaScreenScale( 11 ),
        italic = true,
        weight = 500
    } )
    CreateFont( "letfont_instructions", {
        font = "Consolas",
        size = LambdaScreenScale( 8 ),
        weight = 500
    } )
    CreateFont( "letfont_wpnname", {
        font = "Verdana",
        size = LambdaScreenScale( 7.5 ),
        italic = true,
        weight = 1000
    } )
    CreateFont( "letfont_chatfont", {
        font = "Arial",
        size = LambdaScreenScale( 8 ),
        weight = 1000
    } )
    CreateFont( "letfont_aiinfo", {
        font = "Arial",
        size = LambdaScreenScale( 7 ),
        weight = 1000
    } )
    CreateFont( "letfont_reloading", {
        font = "Verdana",
        size = LambdaScreenScale( 12 ),
        italic = true,
        weight = 500
    } )
    CreateFont( "letfont_ammo", {
        font = "BoxRocket",
        size = LambdaScreenScale( 20 ),
        weight = 1000
    } )

    --

    local function DrawHUD()
        local target = LET:GetTarget()
        if !IsValid( target ) then return end

		local scrW, scrH = ScrW(), ScrH()
		local dispClr = target:GetDisplayColor()

        local hintsTime = LET.HUD_HintsTime
        local scoreBind = input_LookupBinding( "+scoreboard" )
        local keyDown = input_IsKeyDown( scoreBind and input_GetKeyCode( scoreBind ) or KEY_TAB )
        if keyDown then
            hintsTime = max( hintsTime, CurTime() + FrameTime() )
            LET.HUD_HintsTime = hintsTime
        end

        local hintsWidth = LET.HUD_HintsWidth
        local isHiding = ( CurTime() >= hintsTime )
        local slideLerp = Lerp( FrameTime() * ( isHiding and 2 or 3 ), hintsWidth, ( isHiding and -10 or 275 ) )
        LET.HUD_HintsWidth = slideLerp

        if hintsWidth >= 0 then
            RoundedBox( 10, scrW - slideLerp, scrH / 2.5, 250, 117.5, hudBoxClr )
            DrawText( "LMB - Next Tap Target", "letfont_instructions", scrW - slideLerp + 7.5, scrH / 2.466, dispClr, TEXT_ALIGN_LEFT )
            DrawText( "RMB - Previous Tap Target", "letfont_instructions", scrW - slideLerp + 7.5, scrH / 2.3, dispClr, TEXT_ALIGN_LEFT )
            DrawText( "Space - Change Camera View", "letfont_instructions", scrW - slideLerp + 7.5, scrH / 2.166, dispClr, TEXT_ALIGN_LEFT )
            DrawText( "Reload - Exit Eye Tapper", "letfont_instructions", scrW - slideLerp + 7.5, scrH / 2.033, dispClr, TEXT_ALIGN_LEFT )
            DrawText( "TAB - Hide/Show Instructions", "letfont_instructions", scrW - slideLerp + 7.5, scrH / 1.92, dispClr, TEXT_ALIGN_LEFT )
        end

        local lambdaName = target:GetLambdaName()
        SetTextFont( "letfont_lambdaname" )
        local boxWidth = GetTextFontSize( lambdaName ) + 25
        local boxHeight = 40
        
        local stateInfo, enemyInfo
        local isDead = target:GetIsDead()
		if !isDead then
            stateInfo = "State: " .. target:GetState()
            SetTextFont( "letfont_aiinfo" )
            boxWidth = max( boxWidth, GetTextFontSize( stateInfo ) + 15 )
            boxHeight = ( boxHeight + 15 )

            if target:InCombat() or target:IsPanicking() then
                enemyInfo = target:GetEnemy()
                if IsValid( enemyInfo ) then 
                    local enemyName = enemyInfo:GetClass()
                    if enemyInfo.IsLambdaPlayer or enemyInfo:IsPlayer() then
                        enemyName = enemyInfo:Nick()
                    else
                        local langName = GetPhrase( "#" .. enemyName )
                        if langName[ 1 ] != "#" then enemyName = langName end
                        enemyName = enemyName .. " [" .. tostring( enemyInfo ) .. "]"
                    end

                    enemyInfo = "Enemy: " .. enemyName
                    boxWidth = max( boxWidth, GetTextFontSize( enemyInfo ) + 15 )
                    boxHeight = ( boxHeight + 17.5 )
                else
                    enemyInfo = nil
                end
            end
        end

        RoundedBox( 10, ( ( scrW - boxWidth ) / 2 ), scrH / 20, boxWidth + 2.5, boxHeight, hudBoxClr )
        DrawText( lambdaName, "letfont_lambdaname", ( scrW / 2 ), ( scrH / 17.5 ), dispClr, TEXT_ALIGN_CENTER )
        if stateInfo then DrawText( stateInfo, "letfont_aiinfo", ( scrW / 2 ), ( scrH / 11.15 ), dispClr, TEXT_ALIGN_CENTER ) end
        if enemyInfo then DrawText( enemyInfo, "letfont_aiinfo", ( scrW / 2 ), ( scrH / 8.75 ), dispClr, TEXT_ALIGN_CENTER ) end

		if !isDead then
            local wepName = target:GetNW2String( "lambdaeyetap_weaponname", "Holster" )
            if wepName and wepName != "Holster" then
                SetTextFont( "letfont_wpnname" )
                boxWidth = GetTextFontSize( wepName ) + 15

                local maxClip = target:GetNW2Int( "lambdaeyetap_weaponmaxclip", 0 )
                if maxClip > 0 then
                    local reloadText = "Reloading"
                    SetTextFont( "letfont_reloading" )
                    local reloadSize = GetTextFontSize( reloadText .. "..." )

                    for i = 2, ceil( ( RealTime() - LET.HUD_ReloadStartTime ) * 3 % 4 ) do
                        reloadText = reloadText .. "."
                    end

                    SetTextFont( "letfont_ammo" )
                    local clipText = tostring( max( 0, target:GetNW2Int( "lambdaeyetap_weaponcurrentclip", 0 ) ) ) .. "/" .. tostring( maxClip )
                    boxWidth = max( max( boxWidth, reloadSize + 15 ), ( GetTextFontSize( clipText ) + 15 ) )

                    local boxX = ( ( scrW / 1.155 ) - boxWidth / 2 )
                    local offscreenX = max( ( boxX + boxWidth ) - scrW, 0 )
                    RoundedBox( 10, ( boxX - offscreenX * 2 ), scrH / 1.1825, ( boxWidth + offscreenX ), 75, hudBoxClr )
                    
                    local offWepX = ( ( scrW / 1.155 ) - offscreenX )
                    DrawText( wepName, "letfont_wpnname", offWepX, scrH / 1.1725, dispClr, TEXT_ALIGN_CENTER )

                    if target:GetIsReloading() then
                        local reloadText = "Reloading"
                        for i = 2, ceil( ( RealTime() - LET.HUD_ReloadStartTime ) * 3 % 4 ) do
                            reloadText = reloadText .. "."
                        end
                        DrawText( reloadText, "letfont_reloading", offWepX, scrH / 1.1275, dispClr, TEXT_ALIGN_CENTER )
                    else
                        LET.HUD_ReloadStartTime = RealTime()
                        DrawText( clipText, "letfont_ammo", offWepX, scrH / 1.1375, dispClr, TEXT_ALIGN_CENTER )
                    end
                else
                    local boxX = ( ( scrW / 1.155 ) - boxWidth / 2 )
                    local offscreenX = max( ( boxX + boxWidth ) - scrW, 0 )
                    RoundedBox( 10, ( boxX - offscreenX ), scrH / 1.1825, ( boxWidth - offscreenX ), 35, hudBoxClr )
                    DrawText( wepName, "letfont_wpnname", ( ( scrW / 1.155 ) - offscreenX ), scrH / 1.1725, dispClr, TEXT_ALIGN_CENTER )
                end
            end

            local hp = target:GetNW2Float( "lambda_health", "NAN" )
			hp = ( hp == "NAN" and target:GetNWFloat( "lambda_health", "NAN" ) or hp )

            local hpPerc = tostring( ( hp / target:GetNWMaxHealth() ) * 100 ) .. "%"
            SetTextFont( "letfont_hparmor" )
            local hpSize = ( GetTextFontSize( hpPerc ) + 20 )
            SetTextFont( "letfont_hparmor_text" )
            hpSize = max( hpSize, GetTextFontSize( "Health" ) + 20 )

            RoundedBox( 10, ( scrW / 11.1 ) - hpSize / 2, scrH / 1.1825, hpSize, 80, hudBoxClr )
            DrawText( "Health", "letfont_hparmor_text", scrW / 11.1, scrH / 1.175, dispClr, TEXT_ALIGN_CENTER )
            DrawText( hpPerc, "letfont_hparmor", scrW / 11.1, scrH / 1.15, dispClr, TEXT_ALIGN_CENTER )

            local armor = target:GetArmor()
			if armor > 0 then
                local apPerc = tostring( ( armor / target:GetMaxArmor() ) * 100 ) .. "%"
                SetTextFont( "letfont_hparmor" )
                local apSize = GetTextFontSize( apPerc ) + 20
                SetTextFont( "letfont_hparmor_text" )
                apSize = max( apSize, GetTextFontSize( "Armor" ) + 20 )
    
                RoundedBox( 10, ( scrW / 4.45 ) - apSize / 2 , scrH / 1.1825, apSize, 80, hudBoxClr )
                DrawText( "Armor", "letfont_hparmor_text", scrW / 4.45, scrH / 1.175, dispClr, TEXT_ALIGN_CENTER )
                DrawText( apPerc, "letfont_hparmor", scrW / 4.45, scrH / 1.15, dispClr, TEXT_ALIGN_CENTER )
            end
        end

        local chatTyping = target:GetNW2String( "lambdaeyetap_chattyped" )
        if chatTyping and chatTyping != "" then
            RoundedBoxEx( 10, scrW / 20, scrH / 1.46, 75, 25, hudBoxClr, true, true, false, false )
            DrawText( "Typing:", "letfont_chatfont", scrW / 18, scrH / 1.45, dispClr, TEXT_ALIGN_LEFT )

            SetTextFont( "letfont_chatfont" )
            local textSize = max( 75, GetTextFontSize( chatTyping ) + 20 )

            RoundedBoxEx( 10, scrW / 20, scrH / 1.395, textSize, 25, hudBoxClr, false, ( textSize > 75 ), true, true )
            DrawText( chatTyping, "letfont_chatfont", scrW / 18, scrH / 1.3875, dispClr, TEXT_ALIGN_LEFT )
        end
    end

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

    local function CalcView( ply, origin, angles, fov, znear, zfar )
        if _LambdaIsTakingViewShot then return end

        local lambda = LET:GetTarget( ply )
        if !IsValid( lambda ) then return end
        
        local target = lambda
        local lastTarget = LET.LastCamTarget
        if target != lastTarget then
            LET.FollowKillerTime = false
            LET.LastCamTarget = target
            if IsValid( lastTarget ) then LET:DrawTargetHead( lastTarget, true ) end
        end

        local camMode = LET.CameraMode
        local isRagdoll = false
        if lambda:GetNoDraw() then
            local ragdoll = lambda:GetRagdollEntity()
            if IsValid( ragdoll ) then 
                target = ragdoll
                isRagdoll = true

                if switchFromFPonDeath:GetBool() then
                    camMode = 1
                end
            else
                camMode = 1
            end
        end

        local isTaunting = lambda:IsPlayingTaunt()
        if camMode == 3 and isTaunting and forcetpontaunt:GetBool() then
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
            local eyeAng = targEyes.Ang
            if !isRagdoll and !isTaunting then 
                local pitchLimit = target:GetAngles().x
                local yawLimit = target:GetAngles().y
                
                if !facePos:IsZero() then
                    eyeAng = ( facePos - targEyes.Pos ):Angle()
                else
                    eyeAng.y = target:GetAngles().y
                end

                local angDiffX = AngleDifference( eyeAng.x, pitchLimit )
                if angDiffX > 80 then
                    eyeAng.x = ( eyeAng.x - ( angDiffX - 80 ) )
                elseif angDiffX < -80 then
                    eyeAng.x = ( eyeAng.x - ( angDiffX + 80 ) )
                end
                local angDiffY = AngleDifference( eyeAng.y, yawLimit )
                if angDiffY > 75 then
                    eyeAng.y = ( eyeAng.y - ( angDiffY - 75 ) )
                elseif angDiffY < -75 then
                    eyeAng.y = ( eyeAng.y - ( angDiffY + 75 ) )
                end

                eyeAng.z = 0
                eyeAng = LerpAngle( 0.2, viewAng, eyeAng )
            end
            
            viewAng = eyeAng
            viewPos = targEyes.Pos
        else
            local targPos = ( ( isRagdoll or camMode == 1 ) and target:WorldSpaceCenter() or targEyes.Pos )
            local camHeight = ( !isRagdoll and ( camMode == 1 and 32 or 8 ) or 16 )
            local camPos = ( targPos + vector_up * camHeight )
            local camAng = angles

            if isRagdoll then
                local followTime = followKillerTime:GetInt()
                local killer = LET:GetKiller( lambda )
    
                if followTime > 0 and IsValid( killer ) then 
                    local followPos = killer:WorldSpaceCenter()
                    if ( killer.IsLambdaPlayer or killer:IsPlayer() ) and !killer:Alive() then
                        local killerRag = killer:GetRagdollEntity()
                        if IsValid( killerRag ) then followPos = killerRag:WorldSpaceCenter() end
                    end

                    local startTime = LET.FollowKillerTime
                    if startTime == false or startTime and ( CurTime() - startTime ) <= followTime then
                        camAng = LerpAngle( 0.075, viewAng, ( followPos - viewPos ):Angle() )
                        LET.FollowKillerTime = startTime or CurTime()
                    elseif startTime != nil then
                        LET.FollowKillerTime = nil
                        LET:SetCamInterpTime( 3 )
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
                camAng = LerpAngle( 0.2, viewAng, ( TraceLine( camTrTbl ).HitPos - targPos ):Angle() )
            end

            camTrTbl.endpos = ( camPos + camOffset )
            camPos = TraceHull( camTrTbl ).HitPos

            viewPos = ( !isFixedCam and camPos or LerpVector( 0.4, viewPos, camPos ) )
            viewAng = camAng 
        end

        local camFov = ( ( camMode == 3 and useCustomFPFov:GetBool() ) and firstPersonFov:GetInt() or fov )
        local drawHead = true
        if smoothCamera:GetBool() then
            local duration = LET.CamInterpEndTime
            local timeElapsed = ( CurTime() - LET.CamInterpStartTime )
            local lerpFact = ( timeElapsed / duration )
            if lerpFact >= 1 then
                LET.ViewPosition = viewPos
                LET.ViewAngles = viewAng
            else
                LET.ViewPosition = LerpVector( lerpFact, LET.ViewPosition, viewPos )
                LET.ViewAngles = LerpAngle( lerpFact, LET.ViewAngles, viewAng )
            end

            local viewFOV = LET.ViewFOV
            LET.ViewFOV = ( !viewFOV and camFov or Lerp( lerpFact, viewFOV, camFov ) )
        else
            LET.ViewPosition = viewPos
            LET.ViewAngles = viewAng
            LET.ViewFOV = camFov
        end

        if !viewFOV then
            viewFOV = fov
        end

        LET:DrawTargetHead( target, ( LET.ViewPosition:DistToSqr( targEyes.Pos ) > 144 or isRagdoll and camMode != 3 ) )

        calcViewTbl.origin = LET.ViewPosition
        calcViewTbl.angles = LET.ViewAngles
        calcViewTbl.fov = LET.ViewFOV
        return calcViewTbl
    end

    local function OverrideLambdaTargetID( lambda )
        if IsValid( LET:GetTarget() ) then return false end
    end

    local hideElements = {
        [ "CHudBattery" ] = true,
        [ "CHudHealth" ] = true,
        [ "CHudSuitPower" ] = true,
        [ "CHUDQuickInfo" ] = true,
        [ "CHudDamageIndicator" ] = true,
        [ "CHudPoisonDamageIndicator" ] = true,
        [ "CHudSquadStatus" ] = true,
        [ "CHudFlashlight" ] = true,
        [ "CHudLocator" ] = true
    }
    local function HideDefaultHUD( elementName )
        local target = LET:GetTarget()
        if !IsValid( target ) then return end
        if hideElements[ elementName ] then return false end
        if elementName == "CHudCrosshair" then return ( LET.CameraMode != 1 and !target:GetIsDead() ) end
    end

    local function DrawHaloOnEnemy()
        if !drawHaloOnEnemy:GetBool() then return end

        local target = LET:GetTarget()
        if !IsValid( target ) then return end

        local enemy = LET:GetKiller( target )
        if !target:GetIsDead() or !IsValid( enemy ) then
            enemy = target:GetEnemy()
            if !target:InCombat() and !target:IsPanicking() or !IsValid( enemy ) then return end
        end

        local haloClr = target:GetDisplayColor()
        if enemy.IsLambdaPlayer or enemy:IsPlayer() then 
            haloClr = enemy:GetPlayerColor():ToColor()

            if !enemy:Alive() then
                local killerRag = enemy:GetRagdollEntity()
                if IsValid( killerRag ) then enemy = killerRag end
            end
        end

        halo_Add( { enemy }, haloClr, 1, 1, 1, true, true )
    end

    hook.Add( "HUDPaint", "LambdaET_DrawHUD", DrawHUD )
    hook.Add( "CalcView", "LambdaET_CalcView", CalcView )
    hook.Add( "LambdaShowNameDisplay", "LambdaET_OverrideLambdaTargetID", OverrideLambdaTargetID )
    hook.Add( "HUDShouldDraw", "LambdaET_HideDefaultHUD", HideDefaultHUD )
    hook.Add( "PreDrawHalos", "LambdaET_DrawHaloOnEnemy", DrawHaloOnEnemy )
end

--

if ( SERVER ) then
    local AddOriginToPVS = AddOriginToPVS
    local table_Reverse = table.Reverse
    local table_KeyFromValue = table.KeyFromValue

    LET.InEyeTapMode = LET.InEyeTapMode or {}
    LET.LastKeyPress = LET.LastKeyPress or {} 
    LET.PreEyeTapData = LET.PreEyeTapData or {} 

    util.AddNetworkString( "lambdaeyetapper_settarget" )
    util.AddNetworkString( "lambdaeyetapper_setviewmode" )
    util.AddNetworkString( "lambdaeyetapper_weaponpunch" )

    local function OnServerThink()
        for _, ply in ipairs( GetHumans() ) do
            local target = LET:GetTarget( ply )
            if !IsValid( target ) then 
                if LET.InEyeTapMode[ ply ] then
                    LET.InEyeTapMode[ ply ] = false

                    ply:SetNoTarget( false )
                    ply:DrawShadow( true )
                    ply:SetNoDraw( false )
                    ply:SetMoveType( MOVETYPE_WALK )
                    ply:SetCollisionGroup( COLLISION_GROUP_IN_VEHICLE )
                    ply:DrawViewModel( true )
                    
                    local preData = LET.PreEyeTapData[ ply ]
                    if preData then
                        ply:SetEyeAngles( preData[ 1 ] )

                        local hasToolGun = false
                        for _, wep in ipairs( preData[ 2 ] ) do
                            local wepEnt = ply:Give( wep[ 1 ], true )
                            if !IsValid( wepEnt ) then return end

                            wepEnt:SetClip1( wep[ 2 ] )
                            wepEnt:SetClip2( wep[ 3 ] )

                            if !hasToolGun and wep[ 1 ] == "gmod_tool" then 
                                hasToolGun = true
                                ply:SelectWeapon( wepEnt ) 
                            end
                        end
                    end
                end
            else 
                target:SetNW2Int( "lambdaeyetap_weaponcurrentclip", target.l_Clip )
                target:SetNW2String( "lambdaeyetap_chattyped", ( target.l_queuedtext != nil and target.l_typedtext or nil ) )
                
                local lastPress = LET.LastKeyPress[ ply ]
                if CurTime() >= lastPress then
                    local keyPressed = false
                    
                    if ply:KeyPressed( IN_RELOAD ) then
                        LET:SetTarget( nil, ply )
                        keyPressed = true
                    elseif ply:KeyPressed( IN_JUMP ) then
                        net.Start( "lambdaeyetapper_setviewmode" )
                        net.Send( ply )
                        
                        keyPressed = true
                    elseif ply:KeyPressed( IN_ATTACK ) then
                        local lambdas = GetLambdaPlayers()        
                        local curIndex = table_KeyFromValue( lambdas, target )

                        for index, lambda in ipairs( lambdas ) do
                            if index > curIndex then
                                LET:SetTarget( lambda, ply )
                                break
                            end
                            if index != #lambdas then continue end
            
                            local firstLambda = lambdas[ 1 ]
                            if firstLambda != target then LET:SetTarget( lambdas[ 1 ], ply ) end
                        end

                        keyPressed = true
                    elseif ply:KeyPressed( IN_ATTACK2 ) then                  
                        local lambdas = table_Reverse( GetLambdaPlayers() )       
                        local curIndex = table_KeyFromValue( lambdas, target )

                        for index, lambda in ipairs( lambdas ) do
                            if index > curIndex then
                                LET:SetTarget( lambda, ply )
                                break
                            end
                            if index != #lambdas then continue end
            
                            local firstLambda = lambdas[ 1 ]
                            if firstLambda != target then LET:SetTarget( lambdas[ 1 ], ply ) end
                        end

                        keyPressed = true
                    end

                    if keyPressed then
                        LET.LastKeyPress[ ply ] = ( CurTime() + 0.1 )
                    end
                end
            end
        end
    end

    local function OnEntityFireBullets( ent, data )
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

    local function KeepTargetInPVS( ply )
        local target = LET:GetTarget( ply )
        if IsValid( target ) then
            AddOriginToPVS( target:WorldSpaceCenter() )

            local enemy = target:GetEnemy()
            if ( target:InCombat() or target:IsPanicking() ) and IsValid( enemy ) then
                AddOriginToPVS( enemy:WorldSpaceCenter() )
            end

            if !target:Alive() then
                local killer = LET:GetKiller( target )
                if IsValid( killer ) then AddOriginToPVS( killer:WorldSpaceCenter() ) end
            end
        end
    end

    local function OnPlayerDeath( ply )
        if LET.InEyeTapMode[ ply ] then LET:SetTarget( nil, ply ) end
    end

    local function OnLambdaKilled( lambda, dmginfo )
        local attacker = dmginfo:GetAttacker()
        if attacker == lambda or !IsValid( attacker ) or !attacker:IsNPC() and !attacker:IsNextBot() and !attacker:IsPlayer() then 
            LET:SetKiller( lambda, NULL )
            return 
        end
        LET:SetKiller( lambda, attacker )
    end

    local function OnLambdaSwitchWeapon( lambda, wepent, wpnData )
        lambda:SetNW2Int( "lambdaeyetap_weaponmaxclip", lambda.l_MaxClip )
        lambda:SetNW2Int( "lambdaeyetap_weaponname", wpnData.prettyname )
    end

    hook.Add( "Think", "LamndaET_OnServerThink", OnServerThink )
    hook.Add( "SetupPlayerVisibility", "LambdaET_KeepTargetInPVS", KeepTargetInPVS )
    hook.Add( "EntityFireBullets", "LambdaET_OnEntityFireBullets", OnEntityFireBullets )
    hook.Add( "PlayerDeath", "LambdaET_OnPlayerDeath", OnPlayerDeath )
    hook.Add( "LambdaOnKilled", "LambdaET_OnLambdaKilled", OnLambdaKilled )
    hook.Add( "LambdaOnSwitchWeapon", "LambdaET_OnLambdaSwitchWeapon", OnLambdaSwitchWeapon )

    -- what da heeeeeeeeeeeeeeeeeeeeeell oh maaah gawd noo waaaaaaaayy~ --

    local function OnPlayerDisallowStuff( ply )
        if LET.InEyeTapMode[ ply ] then return false end
    end

    hook.Add( "PlayerShouldTakeDamage", "LambdaET_OnPlayerShouldTakeDamage", OnPlayerDisallowStuff )
    hook.Add( "PlayerShouldTaunt", "LambdaET_OnPlayerShouldTaunt", OnPlayerDisallowStuff )
    hook.Add( "CanPlayerEnterVehicle", "LambdaET_OnPlayerCanEnterVehicle", OnPlayerDisallowStuff )
    hook.Add( "PlayerUse", "LambdaET_OnPlayerUse", OnPlayerDisallowStuff )
    hook.Add( "PlayerCanPickupItem", "LambdaET_OnPlayerCanPickupItem", OnPlayerDisallowStuff )
    hook.Add( "PlayerCanPickupWeapon", "LambdaET_OnPlayerCanPickupWeapon", OnPlayerDisallowStuff )
    hook.Add( "PlayerNoClip", "LambdaET_OnPlayerNoClip", OnPlayerDisallowStuff )
    hook.Add( "PlayerSpray", "LambdaET_OnPlayerSpray", OnPlayerDisallowStuff )
    hook.Add( "PlayerSwitchFlashlight", "LambdaET_OnPlayerSwitchFlashlight", OnPlayerDisallowStuff )
    hook.Add( "AllowPlayerPickup", "LambdaET_OnAllowPlayerPickup", OnPlayerDisallowStuff )
    hook.Add( "PlayerSwitchWeapon", "LambdaET_OnPlayerSwitchWeapon", OnPlayerDisallowStuff )
end

local function OnLambdaRemoved( lambda )
    if ( SERVER ) then
        local tappers = LET:GetEyeTappers( lambda )
        if #tappers == 0 then return end

        local lambdas = GetLambdaPlayers()
        local switchTarget = lambda.l_recreatedlambda
        if !IsValid( switchTarget ) then 
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
            if #lambdas > 0 and ply:GetInfoNum( "lambdaplayers_eyetapper_dontquitontargetdeleted", 0 ) == 0 then continue end
            LET:SetTarget( switchTarget, ply )
        end
    elseif lambda == LET:GetTarget() and ( !dontStopOnTargetDeleted:GetBool() or #GetLambdaPlayers() <= 1 ) then
        surface_PlaySound( "buttons/combine_button_locked.wav" )
    end
end

hook.Add( "LambdaOnRemove", "LambdaET_OnLambdaRemoved", OnLambdaRemoved )