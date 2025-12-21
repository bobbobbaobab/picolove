local patch = {}

function patch_includes(lua, folder)
	local startpos
	local endpos = 0
	startpos, endpos = string.find(lua, "#include (%S+)", endpos)
	while startpos ~= nil do
		local filename = lua:match("#include (%S+)", startpos)
		local filepath = folder .. "/" .. filename
		local content, size = love.filesystem.read(filepath)
		if not content then
			print("Failed to load file:", filepath)
		end
		if content then
			if content:sub(-1) == "\n" then
				content = content:sub(1, -2)
				size = size - 1
			end
			lua = lua:sub(1, startpos - 1) .. content .. lua:sub(endpos + 1)
			endpos = endpos + size - endpos + startpos + 1
		end
		startpos, endpos = string.find(lua, "#include (%S+)", endpos)
	end
	return lua
end

function patch_lua(lua, folder)
    
    lua = modify_game_code(lua)
	-- patch lua code
	lua = patch_includes(lua, folder)
	lua = lua:gsub("!=", "~=")
	lua = lua:gsub("//", "--")
	-- rewrite broken up while statements eg:
	-- while fn
	-- (0,0,
	-- 0,0) do
	-- end
	lua = lua:gsub("while%s*(.-)%s*do", function(a)
		a = a:gsub("%s*\n%s*", " ")
		return "while " .. a .. " do"
	end)
	-- rewrite shorthand if statements eg. if (not b) i=1 j=2
	lua = lua:gsub("if%s*(%b())%s*([^\n]*)\n", function(a, b)
		local nl = a:find("\n", nil, true)
		local th = b:find("%f[%w]then%f[%W]")
		local an = b:find("%f[%w]and%f[%W]")
		local o = b:find("%f[%w]or%f[%W]")
		local ce = b:find("--", nil, true)
		if not (nl or th or an or o) then
			if ce then
				local c, t = b:match("(.-)(%s-%-%-.*)")
				return "if " .. a:sub(2, -2) .. " then " .. c .. " end" .. t .. "\n"
			else
				return "if " .. a:sub(2, -2) .. " then " .. b .. " end\n"
			end
		end
	end)
	-- rewrite assignment operators
	-- TODO: handle edge case "if x then i += 1 % 2 end" with % as +-*/%(^.:#)[
	--lua = lua:gsub("([\n\r]%s*)(%a[%a%d]*)%s*([%+-%*/%%])=(%s*%S*)([^\n\r]*)", "%1%2 = %2 %3 (%4)%5")
	--lua = lua:gsub("^(%s*)(%a[%a%d]*)%s*([%+-%*/%%])=(%s*%S*)([^\n\r]*)", "%1%2 = %2 %3 (%4)%5")
	lua = lua:gsub("(%S+)%s*([%+-%*/%%])=", "%1 = %1 %2 ")
	lua = lua:gsub("(%S+)%s*(%.%.)=", "%1 = %1 %2 ")

	--address operators (not ready yet - issues with strings)
	--lua = lua:gsub("@%s*([^\n\r%s]*)", "peek(%1)")
	--lua = lua:gsub("%%%s*([^\n\r%s]*)", "peek2(%1)")
	--lua = lua:gsub("%$%s*([^\n\r%s]*)", "peek4(%1)")

	--[[
	2\2
	test\test
	test_test\test_test
	(test+kfjdf)\(ahb\k39)
	--]]
	-- TODO: nested expressions, function calls, etc
	lua = lua:gsub("([%w_%[%]*/]+)%s*\\%s*([%w_%[%]*/]+)", " flr(%1/%2) ")
	-- rewrite inspect operator "?"
	lua = lua:gsub("([\n\r]%s*)?([^\n\r]*)", "%1print(%2)")
	lua = lua:gsub("^(%s*)?([^\n\r]*)", "%1print(%2)")
	-- convert binary literals to hex literals
	lua = lua:gsub("([^%w_])0[bB]([01.]+)", function(a, b)
		local p1, p2 = b, ""
		if b:find(".", nil, true) then
			p1, p2 = b:match("(.-)%.(.*)")
		end
		-- pad to 4 characters
		p2 = p2 .. string.rep("0", 3 - ((#p2 - 1) % 4))
		p1, p2 = tonumber(p1, 2), tonumber(p2, 2)
		if p1 then
			if p2 then
				return string.format("%s0x%x.%x", a, p1, p2)
			else
				return string.format("%s0x%x", a, p1)
			end
		end
	end)

	lua = lua:gsub(
		"(btnp?%b())", -- 匹配 btn(...) 或 btnp(...)
		function(call)
			call = call
				:gsub("⬅️", "0")
				:gsub("➡️", "1")
				:gsub("⬆️", "2")
				:gsub("⬇️", "3")
				:gsub("🅾️", "4")
				:gsub("❎", "5")
			return call
		end
	)

	lua = lua
    :gsub("⬅️", "←")
    :gsub("➡️", "→") 
    :gsub("⬆️", "↑") 
    :gsub("⬇️", "↓") 
    :gsub("🅾️", "⓪") 
    :gsub("❎", "✖") 
	
	--fillp
	lua = lua:gsub("(fillp%s*%b())", function(func_block)
		local replaced = func_block:gsub("░", "32125.5")
		return replaced
	end)

	-- rewrite for .. in all() loops
	lua = lua:gsub("for%s+(%w+)%s+in%s+all%s*%((.-)%)%s+do","for _, %1 in __pico8_all(%2) do")

	-- 把 'x & y' 替换为 'bitband(x, y)'
	lua = lua:gsub("(%w+)%s*&%s*(%w+)", "bitband(%1, %2)")





	return lua
end

function modify_game_code(lua)

    --cast.p8
    lua = lua:gsub(
        "(spd%s*=%s*sqrt%([^)]*%)%s*\n%s*if%s*%(%s*spd%s*%)%s*then)",
        function(match)
            return match:gsub("if%s*%(%s*spd%s*%)%s*then", "if (spd~=0) then")
        end)


    --jelpi.p8
    lua = lua:gsub(
        "for%s+k%s*,%s*v%s+in%s+pairs%(%s*actor_dat%[k%]%s*%)%s*\n%s*do%s*\n%s*a%[k%]%s*=%s*v%s*\n%s*end",
        function(block)
            return
                "if (actor_dat[k]) then\n\t\t" ..
                block:gsub("\n", "\n\t\t") ..
                "\n\tend"
        end)
    lua = lua:gsub(
        "while%s*%(%s*ta%s*<%s*a%-%s*%.5%s*%)%s*ta%s*%+=%s*1%s*\n%s*while%s*%(%s*ta%s*>%s*a%+%s*%.5%s*%)%s*ta%s*%-=%s*1",
        "while (ta < a-.5) do ta += 1 end\nwhile (ta > a+.5) do ta -= 1 end"
        )
    lua = lua:gsub("if (a.standing) ah.x-=a.d/2","if (a.standing) then ah.x-=a.d/2 end")
    lua = lua:gsub("follow player while close","follow player when close")
	lua = lua:gsub(
		"and%s*a%.life%s*>%s*1%s*%)%s*or%s*a%.life%s*==%s*0%s*%)%s*and%s*abs%s*%(%s*a%.x%s*-%s*tx%s*<%s*12%s*%)%s*then",
		"and a.life > 1)\n\t\t\t\tor a.life==0) and\n\t\t\t\tabs(a.x-tx)<12 then"
		)

    return lua
end

return patch