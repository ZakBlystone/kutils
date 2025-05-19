AddCSLuaFile()

local LOAD_MDL = 1
local LOAD_PHY = 2

__modelinfo_cache = __modelinfo_cache or {}

local str_byte, str_sub, str_find = string.byte, string.sub, string.find
local lshift, rshift, ldexp = bit.lshift, bit.rshift, math.ldexp
local band, bor, bnot = bit.band, bit.bor, bit.bnot
local m_ptr, m_data, m_stk, m_size = 1, nil, nil, 0

local function open_data( filename, path )
    m_data = file.Read(filename, path or "GAME")
    m_ptr, m_stk, m_size = 1, {}, #(m_data or "")
    return m_data ~= nil
end

local function end_data() m_data, m_stk, m_size = nil, nil, 0 end
local function seek_data( pos ) m_ptr = pos + 1 end
local function tell_data() return m_ptr - 1 end
local function push_data(addr) m_stk[#m_stk+1] = tell_data() seek_data(addr) end
local function pop_data() m_ptr = m_stk[#m_stk] + 1 m_stk[#m_stk] = nil end
local function array_of( f,n ) local t={} for i=1,n do t[i]=f() end return t end
local function skip(n) m_ptr = m_ptr + n end

local function float32()
	local a,b,c,d = str_byte(m_data, m_ptr, m_ptr + 4) m_ptr = m_ptr + 4
	local fr = bor( lshift( band(c, 0x7F), 16), lshift(b, 8), a )
	local exp = bor( band( d, 0x7F ) * 2, rshift( c, 7 ) )
	if exp == 0 then return 0 end
	return ldexp( ( ldexp(fr, -23) + 1 ) * (d > 127 and -1 or 1), exp - 127 )
end

local function uint32()
    local a,b,c,d = str_byte(m_data, m_ptr, m_ptr + 4) m_ptr = m_ptr + 4
    local n = bor( lshift(d,24), lshift(c,16), lshift(b, 8), a )
    if n < 0 then n = (0x1p32) - 1 - bnot(n) end
    return n
end

local function uint16()
    local a,b = str_byte(m_data, m_ptr, m_ptr + 2) m_ptr = m_ptr + 2
    return bor( lshift(b, 8), a )
end

local function uint8()
    local a = str_byte(m_data, m_ptr, m_ptr) m_ptr = m_ptr + 1
    return a
end

local function int32()
    local a,b,c,d = str_byte(m_data, m_ptr, m_ptr + 4) m_ptr = m_ptr + 4
    return bor( lshift(d,24), lshift(c,16), lshift(b, 8), a )
end

local function int16()
    local a,b = str_byte(m_data, m_ptr, m_ptr + 2) m_ptr = m_ptr + 2
    local n = bor( lshift(b, 8), a )
    return band( b, 0x80 ) ~= 0 and (-(0x1p16) + n) or n
end

local function int8()
    local a = str_byte(m_data, m_ptr, m_ptr) m_ptr = m_ptr + 1
    return band( a, 0x80 ) ~= 0 and (-(0x1p8) + a) or a
end

local function char()
    local a = str_sub(m_data, m_ptr, m_ptr) m_ptr = m_ptr + 1
    return a
end

local function charstr(n)
    local a = str_sub(m_data, m_ptr, m_ptr + n - 1) m_ptr = m_ptr + n
    return a
end

local function nullstr()
    local k = str_find(m_data, "\0", m_ptr, true)
    if not k then return end
    local str = str_sub(m_data, m_ptr, k-1)
    m_ptr = k+1
    return str
end

local function vcharstr(n)
    local str = charstr(n)
    local k = str_find(str, "\0", 0, true)
    return k and str_sub(str, 1, k-1) or str
end

local function indirect_array( dtype )
    return { num = int32(), offset = int32(), dtype = dtype }
end

local function load_indirect_array( tbl, base, field, aux, ... )
    local arr = aux or tbl[field]
    local num, offset, dtype = arr.num, arr.offset, arr.dtype
    arr.num, arr.offset, arr.dtype = nil, nil, nil
    assert(offset ~= 0 or num == 0) if num == 0 then return tbl end
    push_data(base + offset) for i=1, num do arr[i] = dtype(...) end pop_data()
    return arr
end

local function indirect_name( tbl, base, field, num )
    field = field or "nameidx"
    local new = field:gsub("idx", "")
    local empty = tbl[field] == 0 or (num and tbl[num] == 0)
    push_data(base + tbl[field])
    tbl[new], tbl[field], tbl[num or -1] = empty and "" or nullstr() , nil, nil
    pop_data()
    return tbl[new]
end

local function vector32() return Vector( float32(), float32(), float32() ) end
local function vector48() return Vector( float16(), float16(), float16() ) end
local function angle32() return Angle( float32(), float32(), float32() ) end
local function matrix3x4()
    local f,i = float32, {0,0,0,1}
    return Matrix({{f(),f(),f(),f()},{f(),f(),f(),f()},{f(),f(),f(),f()},i})
end
local function quat128()
    local x,y,z,w = float32(), float32(), float32(), float32()
    return Quat(x,y,z,w)
end

local function mdl_bone()
    local base = tell_data()
    local bone = {
        nameidx = int32(),
        parent = int32(),
        bonecontroller = array_of(int32, 6),
        pos = vector32(),
        quat = quat128(),
        rot = angle32() * (180 / math.pi),
        posscale = vector32(),
        rotscale = vector32(),
        poseToBone = matrix3x4(),
        qAlignment = quat128(),
        flags = int32(),
        is_jiggle = int32() == 5, _ = skip(4),
        physicsbone = int32(),
        surfacepropidx = int32(),
        contents = int32(),
    }
    bone.invPoseToBone = Matrix(bone.poseToBone)
    bone.invPoseToBone:Invert()
    array_of(int32, 8) -- unused
    indirect_name(bone, base)
    indirect_name(bone, base, "surfacepropidx")
    return bone
end

local function mdl_bonecontroller()
    local ctrl = {
        bone = int32(),
        type = int32(),
        _start = float32(),
        _end = float32(),
        rest = int32(),
        inputfield = int32(),
    }
    array_of(int32, 8) -- unused
    return ctrl
end

local function mdl_hitbox()
    local base = tell_data()
    local bbox = {
        bone = int32(),
        group = int32(),
        bbmin = vector32(),
        bbmax = vector32(),
        nameidx = int32(),
    }
    array_of(int32, 8) -- unused
    indirect_name(bbox, base)
    return bbox
end

local function mdl_hitboxset()
    local base = tell_data()
    local set = {
        nameidx = int32(),
        hitboxes = indirect_array(mdl_hitbox),
    }
    indirect_name(set, base)
    load_indirect_array(set, base, "hitboxes")
    return set
end

local function mdl_mesh()
    local base = tell_data()
    local mesh = {
        material = int32(),
        modelindex = int32(),
        numvertices = int32(),
        vertexoffset = int32(), _ = skip(8),
        materialtype = int32(),
        materialparam = int32(),
        meshid = int32(),
        center = vector32(),
        modelvertexdata = int32(),
        numLODVertexes = array_of(int32, 8),
    }
    array_of(int32, 8) -- unused
    mesh.modelindex = mesh.modelindex + base
    return mesh
end

local function mdl_eyeball()
    local base = tell_data()
    local eyeball = {
        nameidx = int32(),
        bone = int32(),
        org = vector32(),
        zoffset = float32(),
        radius = float32(),
        up = vector32(),
        forward = vector32(),
        texture = int32(), _ = skip(4),
        iris_scale = float32(), _ = skip(4),
        upperflexdesc = array_of(int32, 3),
        lowerflexdesc = array_of(int32, 3),
        uppertarget = array_of(float32, 3),
        lowertarget = array_of(float32, 3),
        upperlidflexdesc = int32(),
        lowerlidflexdesc = int32(), _ = skip(16),
        nonFACS = uint8(), _ = skip(31),
    }
    indirect_name(eyeball, base)
    return eyeball
end

local function mdl_model()
    local base = tell_data()
    local model = {
        ptr = base,
        name = vcharstr(64),
        type = int32(),
        boundingradius = float32(),
        meshes = indirect_array(mdl_mesh),
        numvertices = int32(),
        vertexindex = int32(),
        tangentsindex = int32(),
        numattachments = int32(),
        attachmentindex = int32() + base,
        eyeballs = indirect_array(mdl_eyeball),
        pVertexData = int32(),
        pTangentData = int32(),
    }
    array_of(int32, 8) -- unused
    load_indirect_array(model, base, "meshes")
    load_indirect_array(model, base, "eyeballs")
    return model
end

local function mdl_bodypart()
    local base = tell_data()
    local part = {
        nameidx = int32(),
        nummodels = int32(),
        base = int32(),
        modelindex = int32(),
    }
    indirect_name(part, base)
    part.models = load_indirect_array(part, base, "models", { 
        num = part.nummodels, 
        offset = part.modelindex, 
        dtype = mdl_model, 
    })
    part.nummodels = nil
    part.modelindex = nil
    return part
end

local function mdl_attachment()
    local base = tell_data()
    local attach = {
        nameidx = int32(),
        flags = uint32(),
        localbone = int32(),
        _local = matrix3x4(),
    }
    array_of(int32, 8) -- unused
    indirect_name(attach, base)
    return attach
end

local function mdl_flexcontroller()
    local base = tell_data()
    local flexctrl = {
        typeidx = int32(),
        nameidx = int32(),
        localToGlobal = int32(),
        min = float32(),
        max = float32(),
    }
    indirect_name(flexctrl, base, "typeidx")
    indirect_name(flexctrl, base, "nameidx")
    return flexctrl
end

local function mdl_poseparamdesc()
    local base = tell_data()
    local poseparam = {
        nameidx = int32(),
        flags = int32(),
        _start = float32(),
        _end = float32(),
        _loop = float32(),
    }
    indirect_name(poseparam, base)
    return poseparam
end

local function mdl_modelgroup()
    local base = tell_data()
    local group = {
        labelidx = int32(),
        nameidx = int32(),
    }
    indirect_name(group, base, "labelidx")
    indirect_name(group, base, "nameidx")
    return group
end

local function mdl_texture()
    local base = tell_data()
    local tex = {
        nameidx = int32(),
        flags = int32(),
        used = int32(),
        unused1 = int32(),
    }
    array_of(int32, 12) -- unused
    indirect_name(tex, base)
    return tex
end

local function mdl_cdtexture()
    local base = tell_data()
    local cdtex = { nameidx = int32(), }
    indirect_name(cdtex, 0)
    return cdtex.name
end

local function mdl_header()
    local base = tell_data()
    local header = {
        id = int32(),
        version = int32(),
        checksum = int32(),
        name = vcharstr(64), _ = skip(4),
        eyeposition = vector32(),
        illumposition = vector32(),
        hull_min = vector32(),
        hull_max = vector32(),
        view_bbmin = vector32(),
        view_bbmax = vector32(),
        flags = int32(),
        bones = indirect_array(mdl_bone),
        bone_controllers = indirect_array(mdl_bonecontroller),
        hitbox_sets = indirect_array(mdl_hitboxset), _ = skip(24),
        textures = indirect_array(mdl_texture),
        cdtextures = indirect_array(mdl_cdtexture),
        numskinref = int32(),
        numskinfamilies = int32(),
        skinindex = int32(),
        bodyparts = indirect_array(mdl_bodypart),
        attachments = indirect_array(mdl_attachment), _ = skip(12),
        flexes = indirect_array(mdl_flexdesc),
        flexcontrollers = indirect_array(mdl_flexcontroller), _ = skip(24),
        poseparams = indirect_array(mdl_poseparamdesc),
        surfacepropidx = int32(), _ = skip(16),
        mass = float32(),
        contents = int32(),
        includemodels = indirect_array(mdl_modelgroup), _ = skip(20),
        bonetablebynameindex = int32(), _ = skip(40),
    }

    push_data(base + header.bonetablebynameindex)
    header.bonetablebynameindex = array_of(uint8, header.bones.num)
    pop_data()

    header.skins = {}
    if header.numskinfamilies ~= 0 then
        push_data(base + header.skinindex)
        for i=1, header.numskinfamilies do
            header.skins[i] = array_of(int16, header.numskinref)
        end
        pop_data()
    end

    indirect_name(header, base, "surfacepropidx")

    load_indirect_array(header, 0, "bones")
    load_indirect_array(header, 0, "bone_controllers")
    load_indirect_array(header, 0, "hitbox_sets")
    load_indirect_array(header, 0, "bodyparts")
    load_indirect_array(header, 0, "attachments")
    load_indirect_array(header, 0, "flexcontrollers")
    load_indirect_array(header, 0, "includemodels")
    load_indirect_array(header, 0, "poseparams")
    load_indirect_array(header, 0, "textures")
    load_indirect_array(header, 0, "cdtextures")
    return header
end

function get(model, parts)

    parts = bor((parts or 0), LOAD_MDL)

    if __modelinfo_cache[model] then return __modelinfo_cache[model] end
    if open_data(model) then
        local mdl_data = mdl_header()
        __modelinfo_cache[model] = mdl_data
        end_data()

        local phy_file = model:gsub("%.mdl", ".phy")
        if band(parts, LOAD_PHY) ~= 0 and open_data(phy_file) then

            local size, id, count, crc = int32(), int32(), int32(), int32(4)
            for i=1, count do skip( int32() ) end
            local q, t, i, buf, k = 0, {{}}, 1, ""
            for ch in charstr(m_size - tell_data()):gmatch('.') do
                if ch:match("%s") then 
                    if q % 2 == 1 then buf = buf .. ch end
                elseif ch == '}' then
                    table.insert(t[i-1][t[i][t]], t[i])
                    i, t[i][t] = i - 1
                elseif ch == '{' then
                    t[i][buf] = t[i][buf] or {}
                    t[i+1], i, buf = {[t]=buf}, i + 1, ""
                elseif ch == '"' then
                    q = q + 1
                    if q % 2 == 1 then continue end
                    if q % 4 == 2 then k = buf else t[i][k] = buf end
                    buf = ""
                else 
                    buf = buf .. ch
                end
            end
            t = t[1], end_data()
    
            local bone_lut = {}
            for k, v in ipairs(mdl_data.bones) do
                bone_lut[v.name] = k-1
            end

            mdl_data.bone_solids = {}
            mdl_data.constraint_solids = {}
            mdl_data.solids = {}
            mdl_data.num_solids = 0
            mdl_data.constraints = {}
            mdl_data.num_constraints = 0
            for k, solid in ipairs(t.solid or {}) do
                local bone_idx = bone_lut[solid.name]
                if not bone_idx then continue end
                local data = {
                    name = solid.name,
                    index = tonumber(solid.index),
                    inertia = tonumber(solid.inertia),
                    damping = tonumber(solid.damping),
                    rotdamping = tonumber(solid.rotdamping),
                    mass = tonumber(solid.mass),
                    bone = bone_idx,
                    parent = (bone_lut[solid.parent] or -1),
                    volume = tonumber(solid.volume),
                    surfaceprop = solid.surfaceprop,
                }
                mdl_data.bone_solids[bone_idx] = k-1
                mdl_data.solids[k-1] = data
                mdl_data.num_solids = mdl_data.num_solids + 1
            end

            for k, cst in ipairs(t.ragdollconstraint or {}) do
                local data = {
                    child = tonumber(cst.child),
                    parent = tonumber(cst.parent),
                    xfriction = tonumber(cst.xfriction),
                    yfriction = tonumber(cst.yfriction),
                    zfriction = tonumber(cst.zfriction),
                    xmin = tonumber(cst.xmin),
                    xmax = tonumber(cst.xmax),
                    ymin = tonumber(cst.ymin),
                    ymax = tonumber(cst.ymax),
                    zmin = tonumber(cst.zmin),
                    zmax = tonumber(cst.zmax),
                }
                mdl_data.constraint_solids[data.child] = k-1
                mdl_data.constraints[k-1] = data
                mdl_data.num_constraints = mdl_data.num_constraints + 1
            end

        end

    end
    return __modelinfo_cache[model]

end

return {
    get = get,
    LOAD_MDL = LOAD_MDL,
    LOAD_PHY = LOAD_PHY,
}
