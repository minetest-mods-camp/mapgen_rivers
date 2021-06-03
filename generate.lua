local EvolutionModel = dofile(mapgen_rivers.modpath .. '/erosion.lua')
local twist = dofile(mapgen_rivers.modpath .. '/twist.lua')

local size = {x=1000, y=1000}
local blocksize = 12

local np_base = {
	offset = 0,
	scale = 200,
	seed = 2469,
	octaves = 8,
	spread = {x=4000/blocksize, y=4000/blocksize, z=5},
	persist = 0.6,
	lacunarity = 2,
}

local time = 10
local time_step = 1
local niter = math.ceil(time/time_step)
time_step = time / niter

local function generate()
	local nobj_base = minetest.get_perlin_map(np_base, size)
	nobj_base:calc_3d_map({x=0, y=0, z=0})

	local dem = nobj_base:get_map_slice({z=1}, {z=1})
	dem.X = size.x
	dem.Y = size.y

	local model = EvolutionModel()
	model.dem = dem
	local ref_dem = model:define_isostasy(dem)

	for i=1, niter do
		nobj_base:get_map_slice({z=i+1}, {z=1}, ref_dem)

		model:diffuse(time_step)
		model:flow()
		model:erode(time_step)
		model:isostasy()
	end
	model:flow()

	local mfloor = math.floor
	local mmin, mmax = math.min, math.max
	local offset_x, offset_y = twist(model.dirs, model.rivers, 5)
	for i=1, X*Y do
		offset_x[i] = mmin(mmax(offset_x[i]*256, -128), 127)
		offset_y[i] = mmin(mmax(offset_y[i]*256, -128), 127)
	end

	mapgen_rivers.write_map('dem', model.dem, 2)
	mapgen_rivers.write_map('lakes', model.lakes, 2)
	mapgen_rivers.write_map('dirs', model.dirs, 1)
	mapgen_rivers.write_map('rivers', model.rivers, 4)
	mapgen_rivers.write_map('offset_x', offset_x, 1)
	mapgen_rivers.write_map('offset_y', offset_y, 1)
	local sfile = io.open(mapgen_rivers.world_data_path .. 'size', "w")
	sfile:write(X..'\n'..Y)
	sfile:close()
end

return generate
