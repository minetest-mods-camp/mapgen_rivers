-- erosion.lua

local function erode(model, time)
	--local tinsert = table.insert
	local mmin, mmax = math.min, math.max
	local dem = model.dem
	local dirs = model.dirs
	local lakes = model.lakes
	local rivers = model.rivers
	local sea_level = model.params.sea_level
	local K = model.params.K
	local m = model.params.m
	local X, Y = dem.X, dem.Y
	local scalars = type(K) == "number" and type(m) == "number"

	local erosion_time
	if model.params.variable_erosion then
		erosion_time = {}
	else
		erosion_time = model.erosion_time or {}
	end

	if scalars then
		for i=1, X*Y do
			local etime = 1 / (K*rivers[i]^m)
			erosion_time[i] = etime
			lakes[i] = mmax(lakes[i], dem[i], sea_level)
		end
	else
		for i=1, X*Y do
			local etime = 1 / (K[i]*rivers[i]^m[i])
			erosion_time[i] = etime
			lakes[i] = mmax(lakes[i], dem[i], sea_level)
		end
	end

	for i=1, X*Y do
		local iw = i
		local remaining = time
		local new_elev
		while true do
			local inext = iw
			local d = dirs[iw]

			if d == 0 then
				new_elev = lakes[iw]
				break
			elseif d == 1 then
				inext = iw+X
			elseif d == 2 then
				inext = iw+1
			elseif d == 3 then
				inext = iw-X
			elseif d == 4 then
				inext = iw-1
			end

			local etime = erosion_time[iw]
			if remaining <= etime then
				local c = remaining / etime
				new_elev = (1-c) * lakes[iw] + c * lakes[inext]
				break
			end

			remaining = remaining - etime
			iw = inext
		end

		dem[i] = mmin(dem[i], new_elev)
	end
end

local function diffuse(model, time)
    local mmax = math.max
    local dem = model.dem
    local X, Y = dem.X, dem.Y
    local d = model.params.d
    local dmax = d
    if type(d) == "table" then
        dmax = -math.huge
        for i=1, X*Y do
            dmax = mmax(dmax, d[i])
        end
    end

    local diff = dmax * time
    local niter = math.floor(diff) + 1
    local ddiff = diff / niter

    local temp = {}
    for n=1, niter do
        local i = 1
        for y=1, Y do
            local iN = (y==1) and 0 or -X
            local iS = (y==Y) and 0 or X
            for x=1, X do
                local iW = (x==1) and 0 or -1
                local iE = (x==X) and 0 or 1
                temp[i] = (dem[i+iN]+dem[i+iE]+dem[i+iS]+dem[i+iW])*0.25 - dem[i]
                i = i + 1
            end
        end

        for i=1, X*Y do
            dem[i] = dem[i] + temp[i]*ddiff
        end
    end
    -- TODO Test this
end

local modpath = ""
if minetest then
    if minetest.global_exists('mapgen_rivers') then
        modpath = mapgen_rivers.modpath .. "terrainlib_lua/"
    else
        modpath = minetest.get_modpath(minetest.get_current_modname()) .. "terrainlib_lua/"
    end
end

local rivermapper = dofile(modpath .. "rivermapper.lua")
local gaussian = dofile(modpath .. "gaussian.lua")

local function flow(model)
	model.dirs, model.lakes = rivermapper.flow_routing(model.dem, model.dirs, model.lakes, 'semirandom')
	model.rivers = rivermapper.accumulate(model.dirs, model.rivers)
end

local function uplift(model, time)
	local dem = model.dem
	local X, Y = dem.X, dem.Y
	local uplift_rate = model.params.uplift
	if type(uplift_rate) == "number" then
		local uplift_total = uplift_rate * time
		for i=1, X*Y do
			dem[i] = dem[i] + uplift_total
		end
	else
		for i=1, X*Y do
			dem[i] = dem[i] + uplift_rate[i]*time
		end
	end
end

local function noise(model, time)
	local random = math.random
	local dem = model.dem
	local noise_depth = model.params.noise * 2 * time
	local X, Y = dem.X, dem.Y
	for i=1, X*Y do
		dem[i] = dem[i] + (random()-0.5) * noise_depth
	end
end

local function define_isostasy(model, ref, link)
    ref = ref or model.dem
    if link then
        model.isostasy_ref = ref
        return
    end

    local X, Y = ref.X, ref.Y
    local ref2 = model.isostasy_ref or {X=X, Y=Y}
    model.isostasy_ref = ref2
    for i=1, X*Y do
        ref2[i] = ref[i]
    end

    return ref2
end

local function isostasy(model)
	local dem = model.dem
	local X, Y = dem.X, dem.Y
	local temp = {X=X, Y=Y}
	local ref = model.isostasy_ref
	for i=1, X*Y do
		temp[i] = ref[i] - dem[i]
	end

	gaussian.gaussian_blur_approx(temp, model.params.compensation_radius, 4)
	for i=1, X*Y do
		dem[i] = dem[i] + temp[i]
	end
end

local evol_model_mt = {
	erode = erode,
	diffuse = diffuse,
	flow = flow,
	uplift = uplift,
	noise = noise,
	isostasy = isostasy,
	define_isostasy = define_isostasy,
}

evol_model_mt.__index = evol_model_mt

local defaults = {
	K = 1,
	m = 0.5,
	d = 1,
	variable_erosion = false,
	sea_level = 0,
	uplift = 10,
	noise = 0.001,
	compensation_radius = 50,
}

local function EvolutionModel(params)
	params = params or {}
	local o = {params = params}
	for k, v in pairs(defaults) do
		if params[k] == nil then
			params[k] = v
		end
	end
	o.dem = params.dem
	return setmetatable(o, evol_model_mt)
end

return EvolutionModel
