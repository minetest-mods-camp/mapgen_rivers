local modpath = minetest.get_modpath(minetest.get_current_modname()) .. '/'
local mod_data_path = modpath .. 'data/'
if not io.open(mod_data_path .. 'size', 'r') then
	mod_data_path = modpath .. 'demo_data/'
end

local world_data_path = minetest.get_worldpath() .. '/river_data/'
minetest.mkdir(world_data_path)

local load_map = dofile(modpath .. 'load.lua')

local function copy_if_needed(filename)
	local wfilename = world_data_path..filename
	local wfile = io.open(wfilename, 'r')
	if wfile then
		wfile:close()
		return
	end
	local mfilename = mod_data_path..filename
	local mfile = io.open(mfilename, 'r')
	local wfile = io.open(wfilename, 'w')
	wfile:write(mfile:read("*all"))
	mfile:close()
	wfile:close()
end

copy_if_needed('size')
local sfile = io.open(world_data_path..'size')
local X = tonumber(sfile:read('*l'))
local Z = tonumber(sfile:read('*l'))
sfile:close()

copy_if_needed('dem')
local dem = load_map('dem', 2, true, X*Z)
copy_if_needed('lakes')
local lakes = load_map('lakes', 2, true, X*Z)
copy_if_needed('dirs')
local dirs = load_map('dirs', 1, false, X*Z)
copy_if_needed('rivers')
local rivers = load_map('rivers', 4, false, X*Z)

copy_if_needed('offset_x')
local offset_x = load_map('offset_x', 1, true, X*Z)
for k, v in ipairs(offset_x) do
	offset_x[k] = (v+0.5)/256
end

copy_if_needed('offset_y')
local offset_z = load_map('offset_y', 1, true, X*Z)
for k, v in ipairs(offset_z) do
	offset_z[k] = (v+0.5)/256
end

-- To index a flat array representing a 2D map
local function index(x, z)
	return z*X+x+1
end

local blocksize = mapgen_rivers.blocksize
local min_catchment = mapgen_rivers.min_catchment
local max_catchment = mapgen_rivers.max_catchment

-- Width coefficients: coefficients solving
--   wfactor * min_catchment ^ wpower = 1/(2*blocksize)
--   wfactor * max_catchment ^ wpower = 1
local wpower = math.log(2*blocksize)/math.log(max_catchment/min_catchment)
local wfactor = 1 / max_catchment ^ wpower
local function river_width(flow)
	flow = math.abs(flow)
	if flow < min_catchment then
		return 0
	end

	return math.min(wfactor * flow ^ wpower, 1)
end

-- On map generation, determine into which polygon every point (in 2D) will fall.
-- Also store polygon-specific data
local function make_polygons(minp, maxp)
	local chulens = maxp.z - minp.z + 1

	local polygons = {}
	-- Determine the minimum and maximum coordinates of the polygons that could be on the chunk, knowing that they have an average size of 'blocksize' and a maximal offset of 0.5 blocksize.
	local xpmin, xpmax = math.max(math.floor(minp.x/blocksize - 0.5), 0), math.min(math.ceil(maxp.x/blocksize), X-2)
	local zpmin, zpmax = math.max(math.floor(minp.z/blocksize - 0.5), 0), math.min(math.ceil(maxp.z/blocksize), Z-2)

	-- Iterate over the polygons
	for xp = xpmin, xpmax do
		for zp=zpmin, zpmax do
			local iA = index(xp, zp)
			local iB = index(xp+1, zp)
			local iC = index(xp+1, zp+1)
			local iD = index(xp, zp+1)
			-- Extract the vertices of the polygon
			local poly_x = {offset_x[iA]+xp, offset_x[iB]+xp+1, offset_x[iC]+xp+1, offset_x[iD]+xp}
			local poly_z = {offset_z[iA]+zp, offset_z[iB]+zp, offset_z[iC]+zp+1, offset_z[iD]+zp+1}
			local polygon = {x=poly_x, z=poly_z, i={iA, iB, iC, iD}}

			local bounds = {} -- Will be a list of the intercepts of polygon edges for every X position (scanline algorithm)
			-- Calculate the min and max X positions 
			local xmin = math.max(math.floor(blocksize*math.min(unpack(poly_x)))+1, minp.x)
			local xmax = math.min(math.floor(blocksize*math.max(unpack(poly_x))), maxp.x)
			-- And initialize the arrays
			for x=xmin, xmax do
				bounds[x] = {}
			end

			local i1 = 4
			for i2=1, 4 do -- Loop on 4 edges
				local x1, x2 = poly_x[i1], poly_x[i2]
				-- Calculate the integer X positions over which this edge spans
				local lxmin = math.floor(blocksize*math.min(x1, x2))+1
				local lxmax = math.floor(blocksize*math.max(x1, x2))
				if lxmin <= lxmax then -- If there is at least one position in it
					local z1, z2 = poly_z[i1], poly_z[i2]
					-- Calculate coefficient of the equation defining the edge: Z=aX+b
					local a = (z1-z2) / (x1-x2)
					local b = blocksize*(z1 - a*x1)
					for x=math.max(lxmin, minp.x), math.min(lxmax, maxp.x) do
						-- For every X position involved, add the intercepted Z position in the table
						table.insert(bounds[x], a*x+b)
					end
				end
				i1 = i2
			end
			for x=xmin, xmax do
				-- Now sort the bounds list
				local xlist = bounds[x]
				table.sort(xlist)
				local c = math.floor(#xlist/2)
				for l=1, c do
					-- Take pairs of Z coordinates: all positions between them belong to the polygon.
					local zmin = math.max(math.floor(xlist[l*2-1])+1, minp.z)
					local zmax = math.min(math.floor(xlist[l*2]), maxp.z)
					local i = (x-minp.x) * chulens + (zmin-minp.z) + 1
					for z=zmin, zmax do
						-- Fill the map at these places
						polygons[i] = polygon
						i = i + 1
					end
				end
			end

			polygon.dem = {dem[iA], dem[iB], dem[iC], dem[iD]}
			polygon.lake = math.min(lakes[iA], lakes[iB], lakes[iC], lakes[iD])

			-- Now, rivers.
			-- Load river flux values for the 4 corners
			local riverA = river_width(rivers[iA])
			local riverB = river_width(rivers[iB])
			local riverC = river_width(rivers[iC])
			local riverD = river_width(rivers[iD])
			polygon.river_corners = {riverA, riverB, riverC, riverD}

			-- Flow directions
			local dirA, dirB, dirC, dirD = dirs[iA], dirs[iB], dirs[iC], dirs[iD]
			-- Determine the river flux on the edges, by testing dirs values
			local river_west = (dirA==1 and riverA or 0) + (dirD==3 and riverD or 0)
			local river_north = (dirA==2 and riverA or 0) + (dirB==4 and riverB or 0)
			local river_east = 1 - (dirB==1 and riverB or 0) - (dirC==3 and riverC or 0)
			local river_south = 1 - (dirD==2 and riverD or 0) - (dirC==4 and riverC or 0)

			polygon.rivers = {river_west, river_north, river_east, river_south}
		end
	end

	return polygons
end

return make_polygons
