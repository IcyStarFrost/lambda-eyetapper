AddCSLuaFile()

local IsValid = IsValid
local Trace = util.TraceLine
local tracetbl = {}
local random = math.random

if CLIENT then

    local DrawText = draw.DrawText
    local uiscale = GetConVar( "lambdaplayers_uiscale" )
    local displayArmor = GetConVar( "lambdaplayers_displayarmor" )

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
        { name = "right" },
    }

        
    language.Add("tool.lambdaeyetapper", "Lambda Eye Tapper")

    language.Add("tool.lambdaeyetapper.name", "Lambda Eye Tapper")
    language.Add("tool.lambdaeyetapper.desc", "Allows you to view through what a Lambda sees" )
    language.Add("tool.lambdaeyetapper.left", "Fire onto a Lambda Player to see what they are seeing. Fire again to exit a Lambda's view" )
    language.Add("tool.lambdaeyetapper.right", "Right click to toggle from first person to third person" )
    language.Add("tool.lambdaeyetapper.reload", "Reload to tap into a random Lambda's view" )
    --

    local self
    local mode = 1
    local viewtbl = {}

    -- Changes the view from first to third or likewise
    net.Receive( "lambdaeyetapper_changeview", function()
        mode = mode == 1 and 0 or 1
    end )


    -- Eye tapping code
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
                DrawText( tostring( armor ) .. "%", "lambdaplayers_eyetapperfont", ( sw / 1.9 ), ( sh / 1.2 ) + LambdaScreenScale( 1 + uiscale:GetFloat() ), color, TEXT_ALIGN_CENTER)
            end

            DrawText( name, "lambdaplayers_displayname", ( sw / 2 ), ( sh / 1.3 ) , color, TEXT_ALIGN_CENTER )
            DrawText( ( self:Alive() and tostring( hp ) .. "%" or "*DEAD*" ), "lambdaplayers_eyetapperfont", ( sw / hpW ), ( sh / 1.2 ) + LambdaScreenScale( 1 + uiscale:GetFloat() ), color, TEXT_ALIGN_CENTER)
        end )

        -- The view code
        hook.Add( "CalcView", "lambdaeyetapperCalcView", function( ply, origin, angles, fov, znear, zfar )
            if !IsValid( self ) or ( !IsValid( LocalPlayer() ) or !LocalPlayer():Alive() ) then hook.Remove( "CalcView", "lambdaeyetapperCalcView" ) return end 

            tracetbl.start = self:WorldSpaceCenter()
            tracetbl.endpos = ( self:WorldSpaceCenter() - ply:GetAimVector() * 150 ) + Vector( 0, 0, 50 )
            tracetbl.filter = self

            local eyepos = mode == 0 and self:GetAttachmentPoint( "eyes" ).Pos or Trace( tracetbl ).HitPos
            local ang = mode == 0 and self:EyeAngles() or ply:EyeAngles()
            ang[ 3 ] = 0

            viewtbl.origin = eyepos
            viewtbl.angles = ang
            viewtbl.fov = fov
            viewtbl.znear = znear
            viewtbl.zfar = zfar
            viewtbl.drawviewer = true

            return viewtbl
        end )
    end )

elseif SERVER then
    util.AddNetworkString( "lambdaeyetapper_changetarget" )
    util.AddNetworkString( "lambdaeyetapper_changeview" )

    -- Add the Eye tapped entity's position to the PVS stuff
    hook.Add( "SetupPlayerVisibility", "lambdaeyetapperVis", function( ply, viewEnt )
        if IsValid( ply.l_eyetapperent ) then
            AddOriginToPVS( ply.l_eyetapperent:GetPos() )
        end
    end )

    -- When the player dies, exit eye tapper
    hook.Add( "PlayerDeath", "lambdaeyetapperPlayerDeath", function( ply )
        ply.l_eyetapperent = nil
    end )

end

TOOL.Tab = "Lambda Player"
TOOL.Category = "Tools"
TOOL.Name = "#tool.lambdaeyetapper"


-- Eye tap a Lambda
function TOOL:LeftClick( tr )
    local ent = tr.Entity
    local owner = self:GetOwner()
    if CLIENT then return end
    

    if IsValid( owner.l_eyetapperent ) then

        net.Start( "lambdaeyetapper_changetarget" )
        net.WriteInt( -1, 32 )
        net.Send( owner )

        owner.l_eyetapperent = nil

        return true
    end

    if !IsValid( ent ) or !ent.IsLambdaPlayer then return end

    net.Start( "lambdaeyetapper_changetarget" )
    net.WriteInt( ent:EntIndex(), 32 )
    net.Send( owner )

    owner.l_eyetapperent = ent

    return true
end

-- Eye tap a random alive lambda
function TOOL:Reload()
    local owner = self:GetOwner()
    if CLIENT then return end
    local lambdas = GetLambdaPlayers()
    for k, v in RandomPairs( lambdas ) do
        if IsValid( v ) and v != owner.l_eyetapperent then
            net.Start( "lambdaeyetapper_changetarget" )
            net.WriteInt( v:EntIndex(), 32 )
            net.Send( owner )

            owner.l_eyetapperent = v
            break
        end
    end

    return true
end

-- Toggle between first and third person
-- Stupid Prediction
function TOOL:RightClick( tr )
    if CLIENT then return end

    local owner = self:GetOwner()
    net.Start( "lambdaeyetapper_changeview" )
    net.Send( owner )
end
