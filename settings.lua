local mtsettings = minetest.settings
local mgrsettings = Settings(minetest.get_worldpath() .. '/mapgen_rivers.conf')
function mapgen_rivers.define_setting(name, dtype, default)
	if dtype == "number" or dtype == "string" then
		local v = mgrsettings:get(name)
		if v == nil then
			v = mtsettings:get('mapgen_rivers_' .. name)
			if v == nil then
				v = default
			end
			mgrsettings:set(name, v)
		end
		if dtype == "number" then
			return tonumber(v)
		else
			return v
		end
	elseif dtype == "bool" then
		local v = mgrsettings:get_bool(name)
		if v == nil then
			v = mtsettings:get_bool('mapgen_rivers_' .. name)
			if v == nil then
				v = default
			end
			mgrsettings:set_bool(name, v)
		end
		return v
	elseif dtype == "noise" then
		local v = mgrsettings:get_np_group(name)
		if v == nil then
			v = mtsettings:get_np_group('mapgen_rivers_' .. name)
			if v == nil then
				v = default
			end
			mgrsettings:set_np_group(name, v)
		end
		return v
	end
end

local def_setting = mapgen_rivers.define_setting

mapgen_rivers.settings = {
	center = def_setting('center', 'bool', false),
	blocksize = def_setting('blocksize', 'number', 12),
	sea_level = tonumber(minetest.get_mapgen_setting('water_level')),
	min_catchment = def_setting('min_catchment', 'number', 25),
	max_catchment = def_setting('max_catchment', 'number', 40000),
	riverbed_slope = def_setting('riverbed_slope', 'number', 0.4),
	distort = def_setting('distort', 'bool', true),
	biomes = def_setting('biomes', 'bool', true),
	glaciers = def_setting('glaciers', 'bool', false),
	glacier_factor = def_setting('glacier_factor', 'number', 8),
	elevation_chill = def_setting('elevation_chill', 'number', 0.25),

	evol_params = {
		K = def_setting('river_erosion_coef', 'number', 0.5),
		m = def_setting('river_erosion_power', 'number', 0.4),
		d = def_setting('diffusive_erosion', 'number', 0.5),
	},
	tectonic_speed = def_setting('tectonic_speed', 'number', 70),
	evol_time = def_setting('evol_time', 'number', 10),
	evol_time_step = def_setting('evol_time_step', 'number', 1),
}

local function write_settings()
	mgrsettings:write()
end

minetest.register_on_mods_loaded(write_settings)
minetest.register_on_shutdown(write_settings)
