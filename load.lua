local worldpath = mapgen_rivers.world_data_path

function mapgen_rivers.load_map(filename, bytes, signed, size, converter)
	local file = io.open(worldpath .. filename, 'rb')
	local data = file:read('*all')
	if #data < bytes*size then
		data = minetest.decompress(data)
	end
	local sbyte = string.byte

	local map = {}

	for i=1, size do
		local i0 = (i-1)*bytes+1
		local elements = {data:byte(i0, i1)}
		local n = sbyte(data, i0)
		if signed and n >= 128 then
			n = n - 256
		end

		for j=1, bytes-1 do
			n = n*256 + sbyte(data, i0+j)
		end

		map[i] = n
	end
	file:close()

	if converter then
		for i=1, size do
			map[i] = converter(map[i])
		end
	end

	return map
end

local sbyte = string.byte

local loader_mt = {
	__index = function(loader, i)
		local file = loader.file
		local bytes = loader.bytes
		file:seek('set', (i-1)*bytes)
		local strnum = file:read(bytes)

		local n = sbyte(strnum, 1)
		if loader.signed and n >= 128 then
			n = n - 256
		end

		for j=2, bytes do
			n = n*256 + sbyte(strnum, j)
		end

		if loader.conv then
			n = loader.conv(n)
		end
		loader[i] = n
		return n
	end,
}

function mapgen_rivers.interactive_loader(filename, bytes, signed, size, converter)
	local file = io.open(worldpath .. filename, 'rb')
	if file then
		converter = converter or false
		return setmetatable({file=file, bytes=bytes, signed=signed, size=size, conv=converter}, loader_mt)
	end
end

function mapgen_rivers.write_map(filename, data, bytes)
    local size = #data
    local file = io.open(worldpath .. filename, 'wb')
    local mfloor = math.floor
    local schar = string.char
    local upack = unpack

    local bytelist = {}
    for j=1, bytes do
        bytelist[j] = 0
    end

    for i=1, size do
        local n = mfloor(data[i])
        data[i] = n
        for j=bytes, 2, -1 do
            bytelist[j] = n % 256
            n = mfloor(n / 256)
        end
        bytelist[1] = n % 256

        file:write(schar(upack(bytelist)))
    end

    file:close()
end
