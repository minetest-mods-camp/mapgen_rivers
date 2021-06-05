local worldpath = mapgen_rivers.world_data_path

function mapgen_rivers.load_map(filename, bytes, signed, size)
	local file = io.open(worldpath .. filename, 'rb')
	local data = file:read('*all')
	if #data < bytes*size then
		data = minetest.decompress(data)
	end

	local map = {}

	for i=1, size do
		local i0, i1 = (i-1)*bytes+1, i*bytes
		local elements = {data:byte(i0, i1)}
		local n = elements[1]
		if signed and n >= 128 then
			n = n - 256
		end

		for j=2, bytes do
			n = n*256 + elements[j]
		end

		map[i] = n
	end
	file:close()

	return map
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
