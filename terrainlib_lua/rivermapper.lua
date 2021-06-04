-- rivermapper.lua

local function flow_local_semirandom(plist)
	local sum = 0
	for i=1, #plist do
		sum = sum + plist[i]
	end
	--for _, p in ipairs(plist) do
		--sum = sum + p
	--end
	if sum == 0 then
		return 0
	end
	local r = math.random() * sum
	for i=1, #plist do
		local p = plist[i]
	--for i, p in ipairs(plist) do
		if r < p then
			return i
		end
		r = r - p
	end
	return 0
end

local flow_methods = {
	semirandom = flow_local_semirandom,
}

local function flow_routing(dem, dirs, lakes, method)
	method = method or 'semirandom'
	local flow_local = flow_methods[method] or flow_local_semirandom

	dirs = dirs or {}
	lakes = lakes or {}

	-- Localize for performance
	--local tinsert = table.insert
	local tremove = table.remove
	local mmax = math.max

	local X, Y = dem.X, dem.Y
	dirs.X = X
	dirs.Y = Y
	lakes.X = X
	lakes.Y = Y
	--print(X, Y)
	local i = 1
	local dirs2 = {}
	for i=1, X*Y do
		dirs2[i] = 0
	end

	local singular = {}
	for y=1, Y do
		for x=1, X do
			local zi = dem[i]
			local plist = {
				y<Y and mmax(zi-dem[i+X], 0) or 0, -- Southward
				x<X and mmax(zi-dem[i+1], 0) or 0, -- Eastward
				y>1 and mmax(zi-dem[i-X], 0) or 0, -- Northward
				x>1 and mmax(zi-dem[i-1], 0) or 0, -- Westward
			}

			local d = flow_local(plist)
			dirs[i] = d
			if d == 0 then
				singular[#singular+1] = i
			elseif d == 1 then
				dirs2[i+X] = dirs2[i+X] + 1
			elseif d == 2 then
				dirs2[i+1] = dirs2[i+1] + 2
			elseif d == 3 then
				dirs2[i-X] = dirs2[i-X] + 4
			elseif d == 4 then
				dirs2[i-1] = dirs2[i-1] + 8
			end
			i = i + 1
		end
	end

	-- Compute basins and links
	local nbasins = #singular
	print(nbasins)
	local basin_id = {}
	local links = {}
	local basin_links

	local function add_link(i1, i2, b1, isY)
		local b2
		if i2 == 0 then
			b2 = 0
		else
			b2 = basin_id[i2]
			if b2 == 0 then
				return
			end
		end
		if b2 ~= b1 then
			local elev = i2 == 0 and dem[i1] or mmax(dem[i1], dem[i2])
			local l2 = basin_links[b2]
			if not l2 then
				l2 = {}
				basin_links[b2] = l2
			end
			if not l2.elev or l2.elev > elev then
				l2.elev = elev
				l2.i = mmax(i1,i2)
				l2.is_y = isY
				l2[1] = b2
				l2[2] = b1
			end
		end
	end

	for i=1, X*Y do
		basin_id[i] = 0
	end
	--for ib, s in ipairs(singular) do
	for ib=1, nbasins do
		--local s = singular[ib]
		local queue = {singular[ib]}
		basin_links = {}
		links[#links+1] = basin_links
		--tinsert(links, basin_links)
		while #queue > 0 do
			local i = tremove(queue)
			basin_id[i] = ib
			local d = dirs2[i]

			if d >= 8 then -- River coming from East
				d = d - 8
				queue[#queue+1] = i+1
				--tinsert(queue, i+X)
			elseif i%X > 0 then
				add_link(i, i+1, ib, false)
			else
				add_link(i, 0, ib, false)
			end

			if d >= 4 then -- River coming from South
				d = d - 4
				queue[#queue+1] = i+X
				--tinsert(queue, i+1)
			elseif i <= X*(Y-1) then
				add_link(i, i+X, ib, true)
			else
				add_link(i, 0, ib, true)
			end

			if d >= 2 then -- River coming from West
				d = d - 2
				queue[#queue+1] = i-1
				--tinsert(queue, i-X)
			elseif i%X ~= 1 then
				add_link(i, i-1, ib, false)
			else
				add_link(i, 0, ib, false)
			end

			if d >= 1 then -- River coming from North
				queue[#queue+1] = i-X
				--tinsert(queue, i-1)
			elseif i > X then
				add_link(i, i-X, ib, true)
			else
				add_link(i, 0, ib, true)
			end
		end
	end
	dirs2 = nil

	links[0] = {}
	local nlinks = {}
	for i=0, nbasins do
		nlinks[i] = 0
	end

	--for ib1, blinks in ipairs(links) do
	for ib1=1, #links do
		for ib2, link in pairs(links[ib1]) do
			if ib2 < ib1 then
				links[ib2][ib1] = link
				nlinks[ib1] = nlinks[ib1] + 1
				nlinks[ib2] = nlinks[ib2] + 1
			end
		end
	end

	local lowlevel = {}
	for i, n in pairs(nlinks) do
		if n <= 8 then
			lowlevel[i] = links[i]
		end
	end

	local basin_graph = {}
	for n=1, nbasins do
		--print(n, nbasins)
		local b1, lnk1 = next(lowlevel)
		lowlevel[b1] = nil

		local b2
		local lowest = math.huge
		local lnk1 = links[b1]
		local i = 0
		--print('Scanning basin '..b1)
		for bn, bdata in pairs(lnk1) do
			--print('- Link '..bn)
			i = i + 1
			if bdata.elev < lowest then
				lowest = bdata.elev
				b2 = bn
			end
		end
		--print('Number of links: '..i..' vs '..nlinks[b1])

		-- Add link to the graph
		local bound = lnk1[b2]
		local bb1, bb2 = bound[1], bound[2]
		if not basin_graph[bb1] then
			basin_graph[bb1] = {}
		end
		if not basin_graph[bb2] then
			basin_graph[bb2] = {}
		end
		basin_graph[bb1][bb2] = bound
		basin_graph[bb2][bb1] = bound
		--if bb1 == 0 then
		--	print(bb2)
		--elseif bb2 == 0 then
		--	print(bb1)
		--end

		-- Merge basin b1 into b2
		--print("Merging "..b1.." into "..b2)
		local lnk2 = links[b2]
		-- First, remove the link between b1 and b2
		lnk1[b2] = nil
		lnk2[b1] = nil
		nlinks[b2] = nlinks[b2] - 1
		--print('Decreasing link count of '..b2..' ('..nlinks[b2]..')')
		if nlinks[b2] == 8 then
			--print('Added to lowlevel')
			lowlevel[b2] = lnk2
		end
		--print('Scanning neighbourg of '..b1..' to fix links')
		-- Look for basin 1's neighbours, and add them to basin 2 if they have a lower pass
		for bn, bdata in pairs(lnk1) do
			--print('- Neighbour '..bn)
			local lnkn = links[bn]
			lnkn[b1] = nil

			if lnkn[b2] then
				nlinks[bn] = nlinks[bn] - 1
				--print('Decreasing link count of '..bn..' ('..nlinks[bn]..')')
				if nlinks[bn] == 8 then
					--print('Added to lowlevel')
					lowlevel[bn] = lnkn
				end
			else
				nlinks[b2] = nlinks[b2] + 1
				--print('Increasing link count of '..b2..' ('..nlinks[b2]..')')
				if nlinks[b2] == 9 then
					--print('Removed from lowlevel')
					lowlevel[b2] = nil
				end
			end

			if not lnkn[b2] or lnkn[b2].elev > bdata.elev then
				--print('  - Redirecting link')
				lnkn[b2] = bdata
				lnk2[bn] = bdata
			end
		end
	end

	local queue = {[0] = -math.huge}
	local basin_lake = {}
	for n=1, nbasins do
		basin_lake[n] = 0
	end
	local reverse = {3, 4, 1, 2, [0]=0}
	for n=1, nbasins do
		--print(n, nbasins)
		local b1, elev1 = next(queue)
		queue[b1] = nil
		basin_lake[b1] = elev1
		--print('Scanning basin '..b1)
		for b2, bound in pairs(basin_graph[b1]) do
			--print('Flow '..b2..' into '..b1)
			-- Make b2 flow into b1
			local i = bound.i
			local dir = bound.is_y and 3 or 4
			--print(basin_id[i])
			if basin_id[i] ~= b2 then
				dir = dir - 2
				if bound.is_y then
					i = i - X
				else
					i = i - 1
				end
			elseif b1 == 0 then
				dir = 0
			end
			--print(basin_id[i])
			--print('Reversing directions')
			repeat
				dir, dirs[i] = dirs[i], dir
				if dir == 1 then
					i = i + X
				elseif dir == 2 then
					i = i + 1
				elseif dir == 3 then
					i = i - X
				elseif dir == 4 then
					i = i - 1
				end
				dir = reverse[dir]
			until dir == 0
			-- Add b2 into the queue
			queue[b2] = mmax(elev1, bound.elev)
			basin_graph[b2][b1] = nil
		end
		basin_graph[b1] = nil
	end

	for i=1, X*Y do
		lakes[i] = basin_lake[basin_id[i]]
	end

	return dirs, lakes
end

local function accumulate(dirs, waterq)
	waterq = waterq or {}
	local X, Y = dirs.X, dirs.Y
	--local tinsert = table.insert

	local ndonors = {}
	local waterq = {X=X, Y=Y}
	for i=1, X*Y do
		ndonors[i] = 0
		waterq[i] = 1
	end

	--for i1, dir in ipairs(dirs) do
	for i1=1, X*Y do
		local i2
		local dir = dirs[i1]
		if dir == 1 then
			i2 = i1+X
		elseif dir == 2 then
			i2 = i1+1
		elseif dir == 3 then
			i2 = i1-X
		elseif dir == 4 then
			i2 = i1-1
		end
		if i2 then
			ndonors[i2] = ndonors[i2] + 1
		end
	end

	for i1=1, X*Y do
		--print(i1, ndonors[i1])
		if ndonors[i1] == 0 then
			local i2 = i1
			local dir = dirs[i2]
			local w = waterq[i2]
			--print(dir)
			while dir > 0 do
				if dir == 1 then
					i2 = i2 + X
				elseif dir == 2 then
					i2 = i2 + 1
				elseif dir == 3 then
					i2 = i2 - X
				elseif dir == 4 then
					i2 = i2 - 1
				end
				--print('Incrementing '..i2)
				w = w + waterq[i2]
				waterq[i2] = w

				if ndonors[i2] > 1 then
					ndonors[i2] = ndonors[i2] - 1
					break
				end
				dir = dirs[i2]
			end
		end
	end

	return waterq
end

return {
	flow_routing = flow_routing,
	accumulate = accumulate,
	flow_methods = flow_methods,
}
