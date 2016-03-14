Set = {}

function Set.union (a,b)
	local res = Set.new{}
	for k in pairs(a) do res[k] = true end
	for k in pairs(b) do res[k] = true end
	return res
end

function Set.intersection (a,b)
	local res = Set.new{}
	for k in pairs(a) do
		res[k] = b[k]
	end
	return res
end

function Set.difference (a,b)
	local res = Set.new{}
	for k in pairs(a) do
		if not b[k] then res[k] = true end
	end
    --[[
	for k in pairs(b) do
		if not a[k] then res[k] = true end
	end
    ]]
	return res
end

function Set.size (a)
    local c = 0
    for k in pairs(a) do c = c + 1 end
    return c
end

Set.mt = {}    -- metatable for sets
Set.mt.__add = Set.union
Set.mt.__mul = Set.intersection
Set.mt.__sub = Set.difference
Set.mt.__len = Set.size

function Set.new (t)   -- 2nd version
	local set = {}
	setmetatable(set, Set.mt)
	for _, l in ipairs(t) do set[l] = true end
	return set
end

function Set.tostring (set)
	local s = "{"
	local sep = ""
	for e in pairs(set) do
		s = s .. sep .. e
		sep = ", "
	end
	return s .. "}"
end

function Set.print (s)
	print(Set.tostring(s))
end

return Set
