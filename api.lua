local bit32 = require("bit") 

local api = {}

local flr = math.floor

local function color(c)
	c = flr(c or 0) % 16
	pico8.color = c
	setColor(c)
end

local function warning(msg)
	log(debug.traceback("WARNING: " .. msg, 3))
end

local function _horizontal_line(lines, x0, y, x1)
	table.insert(lines, { x0 + 0.5, y + 0.5, x1 + 1.5, y + 0.5 })
end

local function _plot4points(lines, cx, cy, x, y)
	_horizontal_line(lines, cx - x, cy + y, cx + x)
	if y ~= 0 then
		_horizontal_line(lines, cx - x, cy - y, cx + x)
	end
end

local function scroll(pixels)
	if pixels > 128 then pixels = 128 end
	local base = 0x6000
	local delta = base + pixels * 0x40
	local basehigh = 0x8000
	api.memcpy(base, delta, basehigh - delta)
end

local function setfps(fps)
	pico8.fps = flr(fps)
	if pico8.fps <= 0 then
		pico8.fps = 30
	end
	pico8.frametime = 1 / pico8.fps
end

local function getmousex()
	return flr((love.mouse.getX() - xpadding) / scale)
end

local function getmousey()
	return flr((love.mouse.getY() - ypadding) / scale)
end

-- extra functions provided by picolove
api.warning = warning
api.setfps = setfps

function api._picolove_end()
	if
		not pico8.cart._update
		and not pico8.cart._update60
		and not pico8.cart._draw
	then
		api.printh("cart finished")
	end
end

function api._getpicoloveversion()
	return __picolove_version
end

function api._hasfocus()
	return pico8.has_focus
end

function api._getcursorx()
	return pico8.cursor[1]
end

function api._getcursory()
	return pico8.cursor[2]
end

function api._call(code)
	code = patch_lua(code)

	local ok, f, e = pcall(load, code, "repl")
	if not ok or f == nil then
		api.rectfill(0, api._getcursory(), 128, api._getcursory() + 5 + 6, 0)
		api.print("syntax error", 14)
		api.print(api.sub(e, 20), 6)
		return false
	else
		setfenv(f, pico8.cart)
		ok, e = pcall(f)
		if not ok then
			api.rectfill(0, api._getcursory(), 128, api._getcursory() + 5 + 6, 0)
			api.print("runtime error", 14)
			api.print(api.sub(e, 20), 6)
		end
	end
	return true
end

--------------------------------------------------------------------------------
-- PICO-8 API

-- TODO: only apply if fps is 15, 30 or 60
api._set_fps = setfps


function api.reset()
	api.clip()
	api.camera()
	api.pal()
	api.color(6)
	api.fillp()
end

function api.flip()
	-- 1. 把内容绘制到屏幕上
    flip_screen() 
    -- 注意：flip_screen 结束时会把 Canvas 设回 pico8.screen

    -- 2. 暂时取消 Canvas，否则无法调用 pump
    love.graphics.setCanvas()

    -- 3. 手动更新音频（解决声音卡顿/不播放问题）
    if pico8.update_audio then
        pico8.update_audio(pico8.frametime)
    end

    -- 4. 处理系统事件（解决窗口未响应，现在调用是安全的）
    if love.event then
        love.event.pump()
    end

    -- 5. 恢复 Canvas，确保后续的 print/spr 等指令能画对地方
    if pico8.screen then
        love.graphics.setCanvas(pico8.screen)
    end

    -- 6. 等待帧同步
    love.timer.sleep(pico8.frametime)

	-- 吃掉时间增量
    -- 调用 step() 会重置 LÖVE 的内部计时器。
    -- 这样当代码回到 main.lua 的主循环时，getDelta() 返回的将是 0 (或极小值)，
    -- 就不会触发“疯狂追赶”的 update 循环了。
    if love.timer then
        love.timer.step()
    end
end

function api.camera(x, y)
	pico8.camera_x = flr(tonumber(x) or 0)
	pico8.camera_y = flr(tonumber(y) or 0)
	-- restore_camera()
end

function api.clip(x, y, w, h)
	if type(x) == "number" then
		--love.graphics.setScissor(x, y, w, h)
		pico8.clip = { x, y, w, h }
	else
		--love.graphics.setScissor(0, 0, pico8.resolution[1], pico8.resolution[2])
		pico8.clip = { 0, 0, pico8.resolution[1], pico8.resolution[2] }
	end
end

function api.cls(col)
	api.clip()
	col = flr(tonumber(col) or 0) % 16
	for y=0,127 do
		for x=0,127 do
			pico8.fb[y][x] = col
		end
	end
	pico8.cursor = { 0, 0 }
end

function api.folder(dir)
	if dir == nil then
		love.system.openURL(
			"file://" .. love.filesystem.getWorkingDirectory() .. currentDirectory
		)
	elseif dir == "bbs" then
		api.print("not implemented", 14)
	elseif dir == "backups" then
		api.print("not implemented", 14)
	elseif dir == "config" then
		api.print("not implemented", 14)
	elseif dir == "desktop" then
		love.system.openURL(
			"file://" .. love.filesystem.getUserDirectory() .. "Desktop"
		)
	else
		api.print("useage: folder [location]", 14)
		api.print("locations:", 6)
		api.print("backups bbs config desktop", 6)
	end
end

function api._completecommand(command, path)
	-- TODO: handle depending on command

	local startDir = ""
	local pos = path:find("/", 1, true)
	if pos ~= nil then
		startDir = startDir .. path:sub(1, pos)
		path = path:sub(pos + 1)
	end
	local files = love.filesystem.getDirectoryItems(currentDirectory .. startDir)

	local filteredFiles = {}
	for _, file in ipairs(files) do
		if string.sub(file:lower(), 1, string.len(path)) == path then
			filteredFiles[#filteredFiles + 1] = file
		end
	end
	files = filteredFiles

	local result
	if #files == 0 then
		result = path
	elseif #files == 1 then
		if
			love.filesystem.isDirectory(currentDirectory .. startDir .. files[1])
		then
			result = files[1]:lower() .. "/"
		else
			result = files[1]:lower()
		end
	else
		local matches
		local match = path

		repeat
			result = match
			if #match == #files[1] then
				break
			end

			match = files[1]:sub(1, #match + 1)
			matches = 0
			for _, file in ipairs(files) do
				if string.sub(file:lower(), 1, string.len(match)) == match then
					matches = matches + 1
				end
			end
		until matches ~= #files

		result = result:lower()

		if #result == #path then
			-- TODO: remove duplicate code (see api.ls())
			local output = {}
			for _, file in ipairs(files) do
				if love.filesystem.isDirectory(currentDirectory .. file) then
					output[#output + 1] = { name = file:lower(), color = 14 }
				elseif file:sub(-3) == ".p8" or file:sub(-4) == ".png" then
					output[#output + 1] = { name = file:lower(), color = 6 }
				else
					output[#output + 1] = { name = file:lower(), color = 5 }
				end
			end

			local count = 0
			love.keyboard.setTextInput(false)
			api.rectfill(0, api._getcursory(), 127, api._getcursory() + 6, 0)
			api.print(#output .. " files", 12)
			for _, item in ipairs(output) do
				for j = 1, #item.name, 32 do
					api.rectfill(0, api._getcursory(), 127, api._getcursory() + 6, 0)
					api.print(item.name:sub(j, j + 32), item.color)
					flip_screen()
					count = count + 1
					if count == 20 then
						api.rectfill(0, api._getcursory(), 127, api._getcursory() + 6, 0)
						api.print("--more--", 12)
						flip_screen()
						local y = api._getcursory() - 6
						api.cursor(0, y)
						api.rectfill(0, y, 127, y + 6, 0)
						api.color(item.color)
						local canvas = love.graphics.getCanvas()
						love.graphics.setCanvas()
						while true do
							local e = love.event.wait()
							if e == "keypressed" then
								break
							end
						end
						love.graphics.setCanvas(canvas)
						count = 0
					end
				end
			end
			love.keyboard.setTextInput(true)
		end
	end

	return command .. " " .. startDir .. result
end

-- TODO: move interactive implementation into nocart
-- TODO: should return table of strings
function api.ls()
	local files = love.filesystem.getDirectoryItems(currentDirectory)
	api.rectfill(0, api._getcursory(), 128, api._getcursory() + 5, 0)
	api.print("directory: " .. currentDirectory, 12)
	local output = {}
	for _, file in ipairs(files) do
		if love.filesystem.isDirectory(currentDirectory .. file) then
			output[#output + 1] = { name = file:lower(), color = 14 }
		elseif file:sub(-3) == ".p8" or file:sub(-4) == ".png" then
			output[#output + 1] = { name = file:lower(), color = 6 }
		else
			output[#output + 1] = { name = file:lower(), color = 5 }
		end
	end
	local count = 0
	love.keyboard.setTextInput(false)
	for _, item in ipairs(output) do
		for j = 1, #item.name, 32 do
			api.rectfill(0, api._getcursory(), 128, api._getcursory() + 5, 0)
			api.print(item.name:sub(j, j + 32), item.color)
			flip_screen()
			count = count + 1
			if count == 19 then
				api.rectfill(0, api._getcursory(), 128, api._getcursory() + 5, 0)
				api.print("--more--", 12)
				flip_screen()
				local y = api._getcursory() - 6
				api.cursor(0, y)
				api.rectfill(0, y, 127, y + 6, 0)
				api.color(item.color)
				local canvas = love.graphics.getCanvas()
				love.graphics.setCanvas()
				while true do
					local e, a = love.event.wait()
					if e == "keypressed" then
						if a == "escape" then
							love.keyboard.setTextInput(true)
							return
						else
							love.event.clear() -- consume keypress
						end
						break
					end
				end
				love.graphics.setCanvas(canvas)
				count = 0
			end
		end
	end
	love.keyboard.setTextInput(true)
end

api.dir = api.ls

function api.cd(name)
	local output, count

	if #name > 0 then
		name = name .. "/"
	end

	-- filter /TEXT//$ -> /
	count = 1
	while count > 0 do
		name, count = name:gsub("//", "/")
	end

	local newDirectory = currentDirectory .. name

	if name == "/" then
		newDirectory = "/"
	end

	-- filter /TEXT/../ -> /
	count = 1
	while count > 0 do
		newDirectory, count = newDirectory:gsub("/[^/]*/%.%./", "/")
	end

	-- filter /TEXT/..$ -> /
	count = 1
	while count > 0 do
		newDirectory, count = newDirectory:gsub("/[^/]*/%.%.$", "/")
	end

	local failed = newDirectory:find("%.%.") ~= nil
	failed = failed or newDirectory:find("/[ ]+/") ~= nil

	if #name == 0 then
		output = "directory: " .. currentDirectory
	elseif failed then
		if newDirectory == "/../" then
			output = "cd: failed"
		else
			output = "directory not found"
		end
	elseif love.filesystem.exists(newDirectory) then
		currentDirectory = newDirectory
		output = currentDirectory
	else
		failed = true
		output = "directory not found"
	end

	if not failed then
		api.rectfill(
			0,
			api._getcursory(),
			128,
			api._getcursory() + 5 + api.flr(#output / 32) * 6,
			0
		)
		api.color(12)
		for i = 1, #output, 32 do
			api.print(output:sub(i, i + 32))
		end
	else
		api.rectfill(0, api._getcursory(), 128, api._getcursory() + 5, 0)
		api.print(output, 7)
	end
end

function api.mkdir(...)
	local name = select(1, ...)
	if select("#", ...) == 0 then
		api.rectfill(0, api._getcursory(), 128, api._getcursory() + 5, 0)
		api.print("mkdir [name]", 6)
	elseif name ~= nil then
		love.filesystem.createDirectory(currentDirectory .. name)
	end
end

-- function api.install_demos()
-- 	-- TODO: implement this
-- end

-- function api.install_games()
-- 	-- TODO: implement this
-- end

-- function api.keyconfig()
-- 	-- TODO: implement this
-- end

-- function api.splore()
-- 	-- TODO: implement this
-- end

function draw_fb(x,y,col) 

	if x < 0 or x > 127 or y < 0 or y > 127 then
		return
	end

	if x < pico8.clip[1] or x > pico8.clip[1]+pico8.clip[3]-1 or y <  pico8.clip[2] or y > pico8.clip[2]+pico8.clip[4]-1 then
		return
	end

	local p = pico8.fill_pattern
    
    -- 只有当 pattern 存在且不为 0 时才进行计算
    -- p=0 在 PICO-8 中代表实心填充（默认），所以跳过此检查直接绘制
	if p and p ~= 0 then

		local pat = flr(p) -- 整数部分：纹理形状
		
		-- 计算当前像素的位
		local px = x % 4
		local py = y % 4
		local bit_pos = 15 - (py * 4 + px)
		
		-- 检查 Pattern 在该位置是否为 1
		local bit_set = bit.band(bit.rshift(pat, bit_pos), 1) == 1
	
		if bit_set then
			
			-- 获取小数部分：p - 整数部分
			local frac = p - pat
			
			-- 检查第一位小数 (.1 也就是 0.5)
			-- 如果 frac >= 0.5，说明二进制小数点后第一位是 1
			if frac >= 0.5 then
				return -- 透明：直接返回，不绘制
			else
				col = 0 -- 不透明：绘制黑色（第二种颜色）
			end
		end
		-- 如果 bit_set 为 true，则保持原有的 col 进行绘制
	end

	pico8.fb[y][x] = col

end

function api.pset(x, y, col)
	if col then
		color(col)
	end

	x = flr(x)
	y = flr(y)
	x = x-pico8.camera_x
	y = y-pico8.camera_y

	local c = col
	if c == nil then
		c = pico8.color
	end
	c = flr(c or 0) % 16

	draw_fb(x,y,c)

end

function api.pget(x, y)
    x = flr(x)
    y = flr(y)
	x = x-pico8.camera_x
	y = y-pico8.camera_y

    if
        x >= 0 and x < pico8.resolution[1] and
        y >= 0 and y < pico8.resolution[2]
    then
        return pico8.fb[y][x] or 0
    else
        --warning(string.format("pget out of screen %d, %d", x, y))
        return 0
    end
end

function api.color(col)
	color(col)
end


-- workaround for non printable chars
local tostring_org = tostring
local function tostring(str)
	return tostring_org(str)
	--return (tostring_org(str):gsub("[^%z\32-\127]", "8"))
end

api.tostring = tostring

local utf8 = require("utf8")

function api.print(...)
	-- TODO: support printing special pico8 chars

	local argc = select("#", ...)
	if argc == 0 then return end

	local x, y, col
	local str = select(1, ...)

	-- ===== 参数解析 =====
	if argc == 2 then
		col = select(2, ...)
	elseif argc > 2 then
		x = select(2, ...)
		y = select(3, ...)
		if argc >= 4 then
			col = select(4, ...)
		end
	end

	local c = col

	if c == nil then
		c = pico8.color
	else
		color(c)
	end	
	c = flr(c or 0) % 16

	local canscroll = (y == nil)

	if y == nil then
		y = pico8.cursor[2]
		--pico8.cursor[2] = pico8.cursor[2] + 6
	end

	if x == nil then
		x = pico8.cursor[1]
	end

	x = x-pico8.camera_x
	y = y-pico8.camera_y

	local ry = y + 6

	if canscroll and y > 116 then

		ry = y

		local h
		if y < 122 then h = 6 else  h = y- 116 end
		scroll(h)

		--local c = col or pico8.color

		y=y-6
		if y>115 then y = 115 end

		api.rectfill(0, 127-h+1, 127, 127, 0)
		--api.color(c)
		--api.cursor(x, y)
	end

	-- ===== fb 字体绘制 =====

	local text = tostring(api.tostr(str))
	local cx = flr(x)
	local cy = flr(y)

	local start_x = flr(x)

	for _, code in utf8.codes(text) do

		--log(code)
		if code == 10 then
			cx = start_x
			cy = cy + 6
			ry = cy
			goto continue
		end

		local glyph = pico8.font[code]

		local column = 3
		if code==9450 or code==10006 or code==8592 or code==8594 or code==8593 or code==8595 then -- 🅾️❎⬅️➡️⬆️⬇️
			column = 7
		end

		if glyph then
			for row = 1, 5 do
				local bits = glyph[row]
				if bits and bits ~= 0 then
					for b = 0, column-1 do
						if bit32.band(bit32.rshift(bits, column-1 - b), 1) ~= 0 then
							local px = cx + b
							local py = cy + row - 1
							draw_fb(px,py,pico8.draw_palette[c+1]-1)
						end
					end
				end
			end
		end
		
		cx = cx + column + 1

		::continue::
	end

	pico8.cursor[1] = x
	pico8.cursor[2] = ry

	return cx, ry

end

api.printh = print

function api.cursor(x, y, col)
	if col then
		color(col)
	end
	x = flr(tonumber(x) or 0) % 256
	y = flr(tonumber(y) or 0) % 256
	pico8.cursor = { x, y }
end

function api.tonum(val, format)
	local kind = type(val)
	if kind ~= "number" and kind ~= "string" and kind ~= "boolean" then
		return
	elseif kind == "number" then
		return val
	end

	if type(format) == "string" then
		format = tonumber(format)
	elseif type(format) ~= "number" then
		format = nil
	end

	local base = 10
	local shift = false
	local zeroreturn = false
	if type(format) == "number" then
		base = bit.band(format, 1) ~= 0 and 16 or 10
		shift = bit.band(format, 2) ~= 0
		zeroreturn = bit.band(format, 4) ~= 0
	end

	if kind == "boolean" then
		val = val and 1 or 0
		return shift and 0 or val
	end

	local result = tonumber(val, base)
	if result ~= nil then
		return shift and result / 0x10000 or result
	elseif zeroreturn then
		return 0
	end
end

function api.chr(num)
	local n = tonumber(num)
	if n == nil then
		return
	end
	n = n % 256
	return tostring(string.char(n))
end

function api.ord(...)
	local str = select(1, ...)
	if str == nil then
		return nil
	end

	local argc = select("#", ...)
	local index = select(2, ...) or 0
	local count = select(3, ...) or 0

	if argc == 1 then
		return string.byte(str)
	elseif argc == 2 then
		return string.byte(str, index)
	elseif argc >= 3 then
		local values = {}
		for i = 1, count do
			if index + i > 1 then
				values[i] = string.byte(str, index + i - 1)
				api.printh(values[i], i)
			end
		end
		return unpack(values, 1, count)
	end

	return nil
end

function api.tostr(...)
	if select("#", ...) == 0 then
		return ""
	end

	local val = select(1, ...)
	local kind = type(val)

	if kind == "string" then
		return val
	elseif kind == "number" then
		local format = select(2, ...)
		if format == true then
			format = 1
		end

		if format and bit.band(format, 1) ~= 0 then
			val = val * 0x10000
			local part1 = bit.rshift(bit.band(val, 0xFFFF0000), 16)
			local part2 = bit.band(val, 0xFFFF)
			if bit.band(format, 2) ~= 0 then
				return string.format("0x%04x%04x", part1, part2)
			else
				return string.format("0x%04x.%04x", part1, part2)
			end
		else
			if format and bit.band(format, 2) ~= 0 then
				val = val * 0x10000
			end
			return tostring(val)
		end
	elseif kind == "boolean" then
		return tostring(val)
	else
		return "[" .. kind .. "]"
	end
end

local function sprite_pixel(sx, sy)
	if sx < 0 or sx > 127 or sy < 0 or sy > 127 then
		return 0
	end

	local r, g, b, a = pico8.spritesheet_data:getPixel(sx, sy)

	-- r 是 0–255，之前你存的是 v*16
	return flr(r / 16)
end

function api.spr(n, x, y, w, h, flip_x, flip_y)

	if x ~= x or y ~= y then --x或y为nan
    	return
	end

	x = flr(x)
	y = flr(y)
	x = x - pico8.camera_x
	y = y - pico8.camera_y
	n = flr(n)
	w = w or 1
	h = h or 1
	flip_x = flip_x or false
	flip_y = flip_y or false

	local sx0 = (n % 16) * 8
	local sy0 = flr(n / 16) * 8

	for ty = 0, h * 8 - 1 do
		for tx = 0, w * 8 - 1 do
			local sx = flip_x and (sx0 + w*8 - 1 - tx) or (sx0 + tx)
			local sy = flip_y and (sy0 + h*8 - 1 - ty) or (sy0 + ty)

			local pixel_index = sprite_pixel(sx, sy)  -- 返回0~15
			local col = pico8.draw_palette[pixel_index+1]  -- 如果 draw_palette从1开始索引
			local dx = x + tx
			local dy = y + ty

			if pico8.pal_transparent[pixel_index+1] ~= 0 then
				draw_fb(dx,dy,col-1)
				-- log(dx..","..dy..","..col)
			end

		end
	end
end

function api.sspr(sx, sy, sw, sh, dx, dy, dw, dh, flip_x, flip_y)
	-- 1. 处理默认值
	dw = dw or sw
	dh = dh or sh
	
	-- 2. 如果宽度或高度为0，直接返回
	if dw == 0 or dh == 0 then return end

	-- 3. 应用相机偏移
	dx = flr(dx) - pico8.camera_x
	dy = flr(dy) - pico8.camera_y
	
	-- 4. 获取绝对值用于循环次数
	local adw = math.abs(dw)
	local adh = math.abs(dh)
	
	-- 5. 计算缩放比例 (源尺寸 / 目标绝对尺寸)
	local ratio_x = sw / adw
	local ratio_y = sh / adh

	-- 6. 确定屏幕绘制方向
	-- 如果宽度是负数，我们需要向左绘制 (x - 1 - ix)
	-- 这样可以保证正反面占据相同的像素区域 (例如 8~39 和 39~8)
	local x_dir = dw < 0 and -1 or 1
	local y_dir = dh < 0 and -1 or 1

	-- 如果是负方向，通常起始点要偏移 -1 以匹配像素网格行为
	local start_x = dw < 0 and (dx - 1) or dx
	local start_y = dh < 0 and (dy - 1) or dy

	-- 7. 遍历目标像素 (使用绝对值循环)
	for iy = 0, adh - 1 do
		for ix = 0, adw - 1 do
			
			-- === 计算源纹理坐标 (Texture Coords) ===
			-- 只有当显式指定 flip_x/y 参数时才反转纹理读取顺序
			-- 注意：dw/dh 的正负通过改变屏幕绘制顺序已经实现了翻转效果，
			-- 所以这里不需要根据 dw 的正负来改变纹理读取。
			
			local tx = ix
			if flip_x then tx = adw - 1 - ix end
			
			local ty = iy
			if flip_y then ty = adh - 1 - iy end

			local sample_x = sx + tx * ratio_x
			local sample_y = sy + ty * ratio_y

			-- === 获取颜色 ===
			local pixel_index = sprite_pixel(flr(sample_x), flr(sample_y))
			local col = pico8.draw_palette[pixel_index + 1]
			col = col - 1

			-- === 计算屏幕坐标 (Screen Coords) ===
			-- 这里的 x_dir 决定了是向右画还是向左画
			local screen_x = start_x + ix * x_dir
			local screen_y = start_y + iy * y_dir

			-- === 绘制 ===
			if pico8.pal_transparent[col + 1] ~= 0 then
				draw_fb(screen_x, screen_y, col)
			end
		end
	end
end

function api.rect(x0, y0, x1, y1, col)
	x0 = x0 - pico8.camera_x
	x1 = x1 - pico8.camera_x
	y0 = y0 - pico8.camera_y
	y1 = y1 - pico8.camera_y

	local c = col
	if c == nil then
		c = pico8.color
	else
		color(c)
	end	
	c = flr(c or 0) % 16

	if x1 < x0 then x0, x1 = x1, x0 end
	if y1 < y0 then y0, y1 = y1, y0 end

	x0, y0 = flr(x0), flr(y0)
	x1, y1 = flr(x1), flr(y1)

	for x = x0, x1 do
		draw_fb(x,y0,c)
		draw_fb(x,y1,c)
	end

	for y = y0 + 1, y1 - 1 do
		draw_fb(x0,y,c)
		draw_fb(x1,y,c)
	end
end

function api.rectfill(x0, y0, x1, y1, col)
	x0 = x0 - pico8.camera_x
	x1 = x1 - pico8.camera_x
	y0 = y0 - pico8.camera_y
	y1 = y1 - pico8.camera_y

	local c = col
	if c == nil then
		c = pico8.color
	else
		color(c)
	end	
	c = flr(c or 0) % 16

	if x1 < x0 then x0, x1 = x1, x0 end
	if y1 < y0 then y0, y1 = y1, y0 end
	for y = flr(y0), flr(y1) do
		for x = flr(x0), flr(x1) do
			draw_fb(x,y,pico8.draw_palette[c+1]-1)
		end
	end
end

function api.circ(ox, oy, r, col)
	local c = col
	if c == nil then
		c = pico8.color
	else
		color(c)
	end	
	c = flr(c or 0) % 16

	ox = flr(ox) + 1
	oy = flr(oy) + 1
	ox = ox - pico8.camera_x
	oy = oy - pico8.camera_y
	r = flr(r)
	local points = {}
	local x = r
	local y = 0
	local decisionOver2 = 1 - x

	while y <= x do
		table.insert(points, { ox + x, oy + y })
		table.insert(points, { ox + y, oy + x })
		table.insert(points, { ox - x, oy + y })
		table.insert(points, { ox - y, oy + x })

		table.insert(points, { ox - x, oy - y })
		table.insert(points, { ox - y, oy - x })
		table.insert(points, { ox + x, oy - y })
		table.insert(points, { ox + y, oy - x })
		y = y + 1
		if decisionOver2 < 0 then
			decisionOver2 = decisionOver2 + 2 * y + 1
		else
			x = x - 1
			decisionOver2 = decisionOver2 + 2 * (y - x) + 1
		end
	end
	if #points > 0 then
		for i = 1, #points do
			local p = points[i]
			draw_fb(p[1], p[2], c)
		end
	end
end

function api.circfill(cx, cy, r, col)
	local c = col
	if c == nil then
		c = pico8.color
	else
		color(c)
	end	
	c = flr(c or 0) % 16

	cx = flr(cx)
	cy = flr(cy)
	cx = cx - pico8.camera_x
	cy = cy - pico8.camera_y
	r = flr(r)
	local x = r
	local y = 0
	local err = 1 - r

	local lines = {}

	while y <= x do
		_plot4points(lines, cx, cy, x, y)
		if err < 0 then
			err = err + 2 * y + 3
		else
			if x ~= y then
				_plot4points(lines, cx, cy, y, x)
			end
			x = x - 1
			err = err + 2 * (y - x) + 3
		end
		y = y + 1
	end
	for i=1,#lines do
		local l = lines[i]
		local y  = flr(l[2])
		local x0 = flr(l[1])
		local x1 = flr(l[3])
		for x = x0, x1 do
			draw_fb(x,y,pico8.draw_palette[c+1]-1)
		end
	end
end

function api.line(x0, y0, x1, y1, col)

	local c = col
	if c == nil then
		c = pico8.color
	else
		color(c)
	end	
	c = flr(c or 0) % 16

	if x0 ~= x0 or y0 ~= y0 or x1 ~= x1 or y1 ~= y1 then
		warning("line has NaN value")
		return
	end

	x0 = flr(x0)  - pico8.camera_x
	y0 = flr(y0)  - pico8.camera_y
	x1 = flr(x1)  - pico8.camera_x
	y1 = flr(y1)  - pico8.camera_y

	local dx = x1 - x0
	local dy = y1 - y0
	local stepx, stepy

	local points = { { x0, y0 } }

	if dx == 0 then
		-- simple case draw a vertical line
		points = {}
		if y0 > y1 then
			y0, y1 = y1, y0
		end
		for y = y0, y1 do
			table.insert(points, { x0, y })
		end
	elseif dy == 0 then
		-- simple case draw a horizontal line
		points = {}
		if x0 > x1 then
			x0, x1 = x1, x0
		end
		for x = x0, x1 do
			table.insert(points, { x, y0 })
		end
	else
		if dy < 0 then
			dy = -dy
			stepy = -1
		else
			stepy = 1
		end

		if dx < 0 then
			dx = -dx
			stepx = -1
		else
			stepx = 1
		end

		if dx > dy then
			local fraction = dy - bit.rshift(dx, 1)
			while x0 ~= x1 do
				if fraction >= 0 then
					y0 = y0 + stepy
					fraction = fraction - dx
				end
				x0 = x0 + stepx
				fraction = fraction + dy
				table.insert(points, { flr(x0), flr(y0) })
			end
		else
			local fraction = dx - bit.rshift(dy, 1)
			while y0 ~= y1 do
				if fraction >= 0 then
					x0 = x0 + stepx
					fraction = fraction - dy
				end
				y0 = y0 + stepy
				fraction = fraction + dx
				table.insert(points, { flr(x0), flr(y0) })
			end
		end
	end

	for i, p in ipairs(points) do
		local x = p[1]
		local y = p[2]
		draw_fb(x,y,pico8.draw_palette[c+1]-1)
	end
	
	--love.graphics.points(points)
end

-- local __palette_modified = true

function api.pal(c0, c1, p)
	if type(c0) ~= "number" then
		-- if __palette_modified == false then
		-- 	return
		-- end

		for i = 1, 16 do
			pico8.draw_palette[i] = i
			pico8.pal_transparent[i] = i == 1 and 0 or 1
			pico8.display_palette[i] = pico8.palette[i]
		end

		-- pico8.draw_shader:send("palette", shdr_unpack(pico8.draw_palette))
		-- pico8.sprite_shader:send("palette", shdr_unpack(pico8.draw_palette))
		-- pico8.text_shader:send("palette", shdr_unpack(pico8.draw_palette))
		-- pico8.display_shader:send("palette", shdr_unpack(pico8.display_palette))

		-- __palette_modified = false

		-- According to PICO-8 manual:
		-- pal() to reset to system defaults (including transparency values)
		api.palt()
	elseif p == 1 and c1 ~= nil then
		c0 = flr(c0) % 16
		c1 = flr(c1) % 16
		pico8.display_palette[c0+1] = pico8.palette[c1+1]
		-- pico8.display_shader:send("palette", shdr_unpack(pico8.display_palette))
		-- __palette_modified = true
	elseif c1 ~= nil then
		c0 = flr(c0) % 16
		c1 = flr(c1) % 16
		pico8.draw_palette[c0+1] = c1+1
		-- pico8.draw_shader:send("palette", shdr_unpack(pico8.draw_palette))
		-- pico8.sprite_shader:send("palette", shdr_unpack(pico8.draw_palette))
		-- pico8.text_shader:send("palette", shdr_unpack(pico8.draw_palette))
		-- __palette_modified = true
	end
end

function api.palt(c, t)
	if type(c) ~= "number" then
		for i = 1, 16 do
			pico8.pal_transparent[i] = i == 1 and 0 or 1
		end
	else
		c = flr(c) % 16
		pico8.pal_transparent[c + 1] = t and 0 or 1
	end
	-- pico8.sprite_shader:send("transparent", shdr_unpack(pico8.pal_transparent))
end

function api.fillp(p)
	p = tonumber(p) or 0
	pico8.fill_pattern = p
end

function api.map(cel_x, cel_y, sx, sy, cel_w, cel_h, bitmask)
	cel_x = flr(cel_x or 0)
	cel_y = flr(cel_y or 0)
	sx    = flr(sx or 0)
	sy    = flr(sy or 0)
	cel_w = flr(cel_w or 128)
	cel_h = flr(cel_h or 64)

	for my = 0, cel_h - 1 do
		local map_y = cel_y + my
		if map_y >= 0 and map_y < 64 then
			for mx = 0, cel_w - 1 do
				local map_x = cel_x + mx
				if map_x >= 0 and map_x < 128 then
					local v = pico8.map[map_y][map_x]

					if v and v > 0 then
						if bitmask == nil or bitmask == 0
							or bit.band(pico8.spriteflags[v], bitmask) ~= 0
						then
							api.spr(
								v,
								sx + mx * 8,
								sy + my * 8
							)
						end
					end
				end
			end
		end
	end
end

-- deprecated pico-8 function
api.mapdraw = api.map

function api.mget(x, y)
	x = flr(x or 0)
	y = flr(y or 0)
	if x >= 0 and x < 128 and y >= 0 and y < 64 then
		return pico8.map[y][x]
	end
	return 0
end

function api.mset(x, y, v)
	x = flr(x or 0)
	y = flr(y or 0)
	v = flr(v or 0) % 256
	if x >= 0 and x < 128 and y >= 0 and y < 64 then
		pico8.map[y][x] = v
	end
end

function api.fget(n, f)
	if n == nil then
		return nil
	end
	if f ~= nil then
		-- return just that bit as a boolean
		if not pico8.spriteflags[flr(n)] then
			warning(string.format("fget(%d, %d)", n, f))
			return false
		end
		return bit.band(pico8.spriteflags[flr(n)], bit.lshift(1, flr(f))) ~= 0
	end
	return pico8.spriteflags[flr(n)] or 0
end

function api.fset(n, f, v)
	-- fset n [f] v
	-- f is the flag index 0..7
	-- v is boolean
	if v == nil then
		v, f = f, nil
	end
	if f then
		-- set specific bit to v (true or false)
		if v then
			pico8.spriteflags[n] = bit.bor(pico8.spriteflags[n], bit.lshift(1, f))
		else
			pico8.spriteflags[n] =
				bit.band(pico8.spriteflags[n], bit.bnot(bit.lshift(1, f)))
		end
	else
		-- set bitfield to v (number)
		pico8.spriteflags[n] = v
	end
end

function api.sget(x, y)
	-- return the color from the spritesheet
	x = flr(tonumber(x) or 0)
	y = flr(tonumber(y) or 0)

	if x >= 0 and x < 128 and y >= 0 and y < 128 then
		local c = pico8.spritesheet_data:getPixel(x, y)
		return flr(c / 16)
	end
	return 0
end

function api.sset(x, y, c)
	x = flr(tonumber(x) or 0)
	y = flr(tonumber(y) or 0)
	c = flr(tonumber(c) or 0)

	pico8.spritesheet_data:setPixel(x, y, c * 16, 0, 0, 255)

	-- 把 ImageData 推送到 GPU
	pico8.spritesheet:replacePixels(pico8.spritesheet_data)
end

function api.music(n, fade_len, channel_mask) -- luacheck: no unused

	if n == -1 then

		if fade_len and fade_len > 0 and pico8.current_music then
			local f = pico8.music_fade
			f.start = f.vol
			f.target = 0
			f.time = 0
			f.duration = fade_len / 1000 -- ms → 秒
			f.stop_after = true
			return
		end

		if pico8.current_music then
			for i = 4, 7 do
				if pico8.music[pico8.current_music.music][i-4] < 64 then
					pico8.audio_channels[i].sfx = nil
					pico8.audio_channels[i].offset = 0
					pico8.audio_channels[i].last_step = -1
				end
			end
			pico8.current_music = nil
		end
		return
	end
	local m = pico8.music[n]
	if not m then
		warning(string.format("music %d does not exist", n))
		return
	end
	local music_speed = nil
	local music_channel = nil
	for i = 4, 7 do
		if m[i-4] < 64 then
			local sfx = pico8.sfx[m[i-4]]
			if music_speed == nil or music_speed > sfx.speed then
				music_speed = sfx.speed
				music_channel = i
			end
		end
	end
	pico8.audio_channels[music_channel].loop = false
	pico8.current_music = {
		music = n,
		offset = 0,
		--channel_mask = channel_mask or 15,
		speed = music_speed,
	}
	pico8.music_fade = pico8.music_fade or {}
	local f = pico8.music_fade
	if fade_len and fade_len > 0 then
		f.vol = 0
		f.start = 0
		f.target = 1
		f.time = 0
		f.duration = fade_len / 1000
		f.stop_after = false
	else
		f.vol = 1
		f.start = 1
		f.target = 1
		f.time = 0
		f.duration = 0
		f.stop_after = false
	end
	for i = 4, 7 do
		if pico8.music[n][i-4] < 64 then
			pico8.audio_channels[i].sfx = pico8.music[n][i-4]
			pico8.audio_channels[i].offset = 0
			pico8.audio_channels[i].last_step = -1
		end
	end
end

function api.sfx(n, channel, offset)
	-- n = -1 stop sound on channel
	-- n = -2 to stop looping on channel
	channel = channel or -1
    if n == -1 then
        if channel >= 0 then
            -- stop specific channel
            pico8.audio_channels[channel].sfx = nil
        else
            -- stop all channels
            for i = 0, 3 do
                pico8.audio_channels[i].sfx = nil
            end
        end
        return
    end
	offset = offset or 0
	if channel == -1 then
		-- find a free channel
		for i = 0, 3 do
			if pico8.audio_channels[i].sfx == nil then
				channel = i
				break
			end
		end
	end
	if channel == -1 then --抢占一个通道
		local best_channel = nil
		local best_remaining = math.huge
		for i = 0, 3 do
			local ch = pico8.audio_channels[i]
			if ch.sfx then
				local sfx = pico8.sfx[ch.sfx]
				local remaining
				if sfx.loop_end ~= 0 and ch.loop then
					-- 循环音效：尽量不要抢
					remaining = math.huge
				else
					-- 非循环：按剩余步数
					remaining = 32 - ch.offset
				end
				if remaining < best_remaining then
					best_remaining = remaining
					best_channel = i
				end
			end
		end
		channel = best_channel or 0
	end
	local ch = pico8.audio_channels[channel]
	ch.sfx = n
	ch.offset = offset
	ch.last_step = offset - 1
	ch.loop = true
end

function api.peek(addr)
	addr = flr(tonumber(addr) or 0)
	if addr < 0 then
		return 0
	elseif addr < 0x2000 then -- luacheck: ignore 542
		-- TODO: spritesheet data
	elseif addr < 0x3000 then
		addr = addr - 0x2000
		return pico8.map[flr(addr / 128)][addr % 128]
	elseif addr < 0x3100 then
		return pico8.spriteflags[addr - 0x3000]
	elseif addr < 0x3200 then -- luacheck: ignore 542
		-- TODO: music data
	elseif addr < 0x4300 then -- luacheck: ignore 542
		-- TODO: sfx data
	elseif addr < 0x5e00 then
		return pico8.usermemory[addr - 0x4300]
	elseif addr < 0x5f00 then
		local val = pico8.cartdata[flr((addr - 0x5e00) / 4)] * 0x10000
		local shift = (addr % 4) * 8
		return bit.rshift(bit.band(val, bit.lshift(0xFF, shift)), shift)
	elseif addr < 0x5f40 then
		-- TODO: draw state
		if addr == 0x5f20 then
			return pico8.clip[1]
		elseif addr == 0x5f21 then
			return pico8.clip[2]
		elseif addr == 0x5f22 then
			return pico8.clip[1] + pico8.clip[3]
		elseif addr == 0x5f23 then
			return pico8.clip[2] + pico8.clip[4]
		elseif addr == 0x5f25 then
			return pico8.color
		elseif addr == 0x5f26 then
			return pico8.cursor[1]
		elseif addr == 0x5f27 then
			return pico8.cursor[2]
		elseif addr == 0x5f28 then
			return pico8.camera_x % 256
		elseif addr == 0x5f29 then
			return flr(pico8.camera_x / 256)
		elseif addr == 0x5f2a then
			return pico8.camera_y % 256
		elseif addr == 0x5f2b then
			return flr(pico8.camera_y / 256)
		elseif addr == 0x5f2c then -- luacheck: ignore 542
			-- TODO: screen transformation mode
		elseif addr == 0x5f2d then
			-- TODO: fully implement
			return love.keyboard.hasTextInput()
		end
	elseif addr < 0x5f80 then -- luacheck: ignore 542
		-- TODO: hardware state
	elseif addr < 0x6000 then -- luacheck: ignore 542
		-- TODO: gpio pins
	elseif addr < 0x8000 then
		-- screen data
		local dx = (addr - 0x6000) % 64
		local dy = flr((addr - 0x6000) / 64)
		local low = api.pget(dx, dy)
		local high = bit.lshift(api.pget(dx + 1, dy), 4)
		return bit.bor(low, high)
	end
	return 0
end

function api.poke(addr, val)
	if tonumber(val) == nil then
		return
	end
	addr, val = flr(tonumber(addr) or 0), flr(val) % 256
	if addr < 0 or addr >= 0x8000 then
		error("bad memory access")
	elseif addr < 0x1000 then -- luacheck: ignore 542
	elseif addr < 0x2000 then -- luacheck: ignore 542
		-- TODO: spritesheet data
	elseif addr < 0x3000 then
		addr = addr - 0x2000
		pico8.map[flr(addr / 128)][addr % 128] = val
	elseif addr < 0x3100 then
		pico8.spriteflags[addr - 0x3000] = val
	elseif addr < 0x3200 then -- luacheck: ignore 542
		-- TODO: music data
	elseif addr < 0x4300 then -- luacheck: ignore 542
		-- TODO: sfx data
	elseif addr < 0x5e00 then
		pico8.usermemory[addr - 0x4300] = val
	elseif addr < 0x5f00 then -- luacheck: ignore 542
		-- TODO: cart data
	elseif addr < 0x5f40 then -- luacheck: ignore 542
		-- TODO: draw state
		if addr == 0x5f26 then
			pico8.cursor[1] = val
		elseif addr == 0x5f27 then
			pico8.cursor[2] = val
		elseif addr == 0x5f28 then
			pico8.camera_x = flr(pico8.camera_x / 256) + val % 256
		elseif addr == 0x5f29 then
			pico8.camera_x = flr((val % 256) * 256) + pico8.camera_x % 256
		elseif addr == 0x5f2a then
			pico8.camera_y = flr(pico8.camera_y / 256) + val % 256
		elseif addr == 0x5f2b then
			pico8.camera_y = flr((val % 256) * 256) + pico8.camera_y % 256
		elseif addr == 0x5f2c then -- luacheck: ignore 542
			-- TODO: screen transformation mode
		elseif addr == 0x5f2d then
			love.keyboard.setTextInput(bit.band(val, 1) == 1)

			if bit.band(val, 2) == 1 then -- luacheck: ignore 542
				-- TODO mouse buttons
			else -- luacheck: ignore 542
			end

			if bit.band(val, 4) == 1 then -- luacheck: ignore 542
				-- TODO pointer lock
			else -- luacheck: ignore 542
			end
		end
	elseif addr < 0x5f80 then -- luacheck: ignore 542
		-- TODO: hardware state
	elseif addr < 0x6000 then -- luacheck: ignore 542
		-- TODO: gpio pins
	elseif addr < 0x8000 then
		addr = addr - 0x6000
		local dx = addr % 64 * 2
		local dy = flr(addr / 64)
		api.pset(dx, dy, bit.band(val, 15))
		api.pset(dx + 1, dy, bit.rshift(val, 4))
	end
end

function api.peek2(addr)
	local val = 0
	val = val + api.peek(addr + 0)
	val = val + api.peek(addr + 1) * 0x100
	return val
end

function api.peek4(addr)
	local val = 0
	val = val + api.peek(addr + 0) / 0x10000
	val = val + api.peek(addr + 1) / 0x100
	val = val + api.peek(addr + 2)
	val = val + api.peek(addr + 3) * 0x100
	return val
end

function api.poke2(addr, val)
	api.poke(addr + 0, bit.rshift(bit.band(val, 0x00FF), 0))
	api.poke(addr + 1, bit.rshift(bit.band(val, 0xFF00), 8))
end

function api.poke4(addr, val)
	val = val * 0x10000
	api.poke(addr + 0, bit.rshift(bit.band(val, 0x000000FF), 0))
	api.poke(addr + 1, bit.rshift(bit.band(val, 0x0000FF00), 8))
	api.poke(addr + 2, bit.rshift(bit.band(val, 0x00FF0000), 16))
	api.poke(addr + 3, bit.rshift(bit.band(val, 0xFF000000), 24))
end



function api.memcpy(dest_addr, source_addr, len)

    if len < 1 or dest_addr == source_addr then
        return
    end

    -- 辅助函数：读取任意地址的一个字节
    local function peek_byte(addr)
        -- [0x1000 - 0x1FFF] Map 下半部分 (Row 32-63)
        if addr >= 0x1000 and addr < 0x2000 then
            local offset = addr - 0x1000
            local y = 32 + math.floor(offset / 128) -- 注意这里加了32
            local x = offset % 128
            return (pico8.map[y] and pico8.map[y][x]) or 0
        
        -- [0x2000 - 0x2FFF] Map 上半部分 (Row 0-31)
        elseif addr >= 0x2000 and addr < 0x3000 then
            local offset = addr - 0x2000
            local y = math.floor(offset / 128) -- 这里从 0 开始
            local x = offset % 128
            return (pico8.map[y] and pico8.map[y][x]) or 0
        
        -- [0x6000 - 0x7FFF] Screen
        elseif addr >= 0x6000 and addr < 0x8000 then
            local offset = addr - 0x6000
            local y = math.floor(offset / 64)
            local x = (offset % 64) * 2
            local p1 = (pico8.fb[y] and pico8.fb[y][x]) or 0
            local p2 = (pico8.fb[y] and pico8.fb[y][x+1]) or 0
            return bit.bor(p1, bit.lshift(p2, 4))
		else
			error("not implemented")
        end
        return 0
    end

    -- 辅助函数：写入任意地址
    local function poke_byte(addr, val)
        -- [0x1000 - 0x1FFF] Map 下半部分 (Row 32-63)
        if addr >= 0x1000 and addr < 0x2000 then
            local offset = addr - 0x1000
            local y = 32 + math.floor(offset / 128)
            local x = offset % 128
            if not pico8.map[y] then pico8.map[y] = {} end
            pico8.map[y][x] = val

        -- [0x2000 - 0x2FFF] Map 上半部分 (Row 0-31)
        elseif addr >= 0x2000 and addr < 0x3000 then
            local offset = addr - 0x2000
            local y = math.floor(offset / 128)
            local x = offset % 128
            if not pico8.map[y] then pico8.map[y] = {} end
            pico8.map[y][x] = val

        -- [0x6000 - 0x7FFF] Screen
        elseif addr >= 0x6000 and addr < 0x8000 then
            local offset = addr - 0x6000
            local y = math.floor(offset / 64)
            local x = (offset % 64) * 2
            local p1 = bit.band(val, 0x0F)
            local p2 = bit.rshift(val, 4)
            if pico8.fb[y] then
                pico8.fb[y][x] = p1
                pico8.fb[y][x+1] = p2
            end
		else
			error("not implemented")
        end
    end

    -- 执行拷贝循环
    for i = 0, len - 1 do
        local val = peek_byte(source_addr + i)
        poke_byte(dest_addr + i, val)
    end
end

function api.memset(dest_addr, val, len)
	if len < 1 then
		return
	end

	for i = dest_addr, dest_addr + len - 1 do
		api.poke(i, val)
	end
end

--function api.reload(dest_addr, source_addr, len, filepath) 
function api.reload() -- luacheck: no unused
	-- FIXME: doesn't handle ranges, we should keep a "cart rom"
	-- FIXME: doesn't handle filepaths
	--_load(cartname)

	--恢复数据
    for y = 0, 63 do
        for x = 0, 127 do
            pico8.map[y][x] = pico8_copy.map[y][x]
        end
    end

	for i = 0, 255 do
		pico8.spriteflags[i] = pico8_copy.spriteflags[i]
	end

	for i = 0, 63 do
		pico8.sfx[i] = {
			editor_mode = pico8_copy.sfx[i].editor_mode,
			speed =  pico8_copy.sfx[i].speed,
			loop_start =  pico8_copy.sfx[i].loop_start,
			loop_end =  pico8_copy.sfx[i].loop_end
		}
		for j = 0, 31 do
			pico8.sfx[i][j] = { pico8_copy.sfx[i][j][1], pico8_copy.sfx[i][j][2], pico8_copy.sfx[i][j][3], pico8_copy.sfx[i][j][4] }
		end
	end

	for i = 0, 63 do
		pico8.music[i] = {
			loop = pico8_copy.music[i].loop,
			[0] = pico8_copy.music[i][0],
			[1] = pico8_copy.music[i][1],
			[2] = pico8_copy.music[i][2],
			[3] = pico8_copy.music[i][3],
		}
	end

end

-- function api.cstore(dest_addr, source_addr, len) -- luacheck: no unused
-- 	-- TODO: implement this
-- end

function api.rnd(x)
	return love.math.random() * (x or 1)
end

function api.srand(seed)
	if seed == 0 then
		seed = 1
	end
	return love.math.setRandomSeed(flr(seed * 0x8000))
end

api.flr = math.floor
api.ceil = math.ceil

function api.sgn(x)
	x = tonumber(x) or 0
	return x < 0 and -1 or 1
end

api.abs = math.abs

function api.min(a, b)
	a = tonumber(a) or 0
	b = tonumber(b) or 0
	return a < b and a or b
end

function api.max(a, b)
	a = tonumber(a) or 0
	b = tonumber(b) or 0
	return a > b and a or b
end

function api.mid(x, y, z)
	x = tonumber(x) or 0
	y = tonumber(y) or 0
	z = tonumber(z) or 0
	if x > y then
		x, y = y, x
	end
	return api.max(x, api.min(y, z))
end

function api.cos(x)
	return math.cos((x or 0) * math.pi * 2)
end

function api.sin(x)
	return -math.sin((x or 0) * math.pi * 2)
end

api.sqrt = math.sqrt

function api.atan2(x, y)
	return (0.75 + math.atan2(x, y) / (math.pi * 2)) % 1.0
end

local bit = require("bit")

api.band = bit.band
api.bor = bit.bor
api.bxor = bit.bxor
api.bnot = bit.bnot
api.shl = bit.lshift
api.shr = bit.rshift

function api.load(filename)
	local hasloaded = _load(filename)
	if hasloaded then
		love.window.setTitle(
			string.upper(cartname)
				.. " (PICOLÖVE) - LÖVE "
				.. __picolove_love_version
		)
	end
	return hasloaded
end

-- function api.save()
-- 	-- TODO: implement this
-- end

function api.run()
	if not cartname then
		return
	end

	love.graphics.setCanvas(pico8.screen)
	love.graphics.setShader(pico8.draw_shader)
	--restore_clip()
	love.graphics.origin()

	api.clip()
	pico8.cart = new_sandbox()

	pico8.can_pause = true
	pico8.can_shutdown = false

	for addr = 0x4300, 0x5e00 - 1 do
		pico8.usermemory[addr - 0x4300] = 0
	end

	for i = 0, 63 do
		pico8.cartdata[i] = 0
	end

	local ok, f, e = pcall(load, loaded_code, cartname)
	if not ok or f == nil then
		-- log("=======8<========")
		-- log(loaded_code)
		-- log("=======>8========")
		error("Error loading lua: " .. tostring(e))
	else
		setfenv(f, pico8.cart)
		love.graphics.setShader(pico8.draw_shader)
		love.graphics.setCanvas(pico8.screen)
		love.graphics.origin()
		--restore_clip()
		ok, e = pcall(f)
		if not ok then
			error("Error running lua: " .. tostring(e))
		else
			--log("lua completed")
		end
	end

	if pico8.cart._init then
		pico8.cart._init()
	end
	if pico8.cart._update60 then
		setfps(60)
	else
		setfps(30)
	end
end

-- function api.stop(message, x, y, col) -- luacheck: no unused
-- 	-- TODO: implement this
-- end

function api.reboot()
	love.window.setTitle("UNTITLED.P8 (PICOLÖVE)")
	_load("nocart.p8")
	api.run()
	cartname = nil
end

function api.shutdown()
	if pico8.can_shutdown then
		love.event.quit()
	end
end

api.exit = api.shutdown

-- function api.info()
-- 	-- TODO: implement this
-- end

-- function api.export()
-- 	-- TODO: implement this
-- end

-- function api.import()
-- 	-- TODO: implement this
-- end

-- TODO: dummy api implementation should just return return null
--function api.help()
--	return nil
--end
-- TODO: move implementatn into nocart
function api.help()
	local commandKey = "ctrl"
	if love.system.getOS() == "OS X" then
		commandKey = "control"
	end

	api.rectfill(0, api._getcursory(), 128, 128, 0)
	api.print("")
	api.color(12)
	api.print("commands")
	api.print("")
	api.color(6)
	api.print("load <filename>  save <filename>")
	api.print("run              resume")
	api.print("shutdown         reboot")
	api.print("install_demos    ls")
	api.print("cd <dirname>     mkdir <dirname>")
	api.print("cd ..     to go up a directory")
	api.print("")
	api.print("alt+enter to toggle fullscreen")
	api.print("alt+f4 or " .. commandKey .. "+q to fastquit")
	api.print("")
	api.color(12)
	api.print("see readme.md for more info")
	api.print("or visit: github.com/picolove")
	api.print("")
end

function api.time()
	return host_time
end
api.t = api.time

function api.login()
	return nil
end

function api.logout()
	return nil
end

function api.bbsreq()
	return nil
end

function api.scoresub()
	return nil, 0
end

-- function api.extcmd(_)
-- 	-- TODO: Implement this?
-- end

function api.radio()
	return nil, 0
end

function api.btn(i, p)
	if type(i) == "number" then
		p = p or 0
		if pico8.keymap[p] and pico8.keymap[p][i] then
			return pico8.keypressed[p][i] ~= nil
		end
		return false
	else
		-- return bitfield of buttons
		local bitfield = 0
		for j = 0, 7 do
			if pico8.keypressed[0][j] then
				bitfield = bitfield + bit.lshift(1, j)
			end
		end
		for j = 0, 7 do
			if pico8.keypressed[1][j] then
				bitfield = bitfield + bit.lshift(1, j + 8)
			end
		end
		return bitfield
	end
end

function api.btnp(i, p)
	if type(i) == "number" then
		p = p or 0
		if pico8.keymap[p] and pico8.keymap[p][i] then
			local v = pico8.keypressed[p][i]
			if v and (v == 0 or (v >= 12 and v % 4 == 0)) then
				return true
			end
		end
		return false
	else
		-- return bitfield of buttons
		local bitfield = 0
		for j = 0, 7 do
			if pico8.keypressed[0][j] then
				bitfield = bitfield + bit.lshift(1, j)
			end
		end
		for j = 0, 7 do
			if pico8.keypressed[1][j] then
				bitfield = bitfield + bit.lshift(1, j + 8)
			end
		end
		return bitfield
	end
end

function api.cartdata(id) -- luacheck: no unused
	-- TODO: handle global cartdata properly
	-- TODO: handle cartdata() from console should not work
	pico8.can_cartdata = true
	-- if cartdata exists
	-- return true
	return false
end

function api.dget(index)
	-- TODO: handle global cartdata properly
	-- TODO: handle missing cartdata(id) call
	index = flr(index)
	if not pico8.can_cartdata then
		api.print("** dget called before cartdata()", 6)
		return ""
	end
	if index < 0 or index > 63 then
		warning("cartdata index out of range")
		return 0
	end
	return pico8.cartdata[index]
end

function api.dset(index, value)
	-- TODO: handle global cartdata properly
	-- TODO: handle missing cartdata(id) call
	index = flr(index)
	if not pico8.can_cartdata then
		api.print("** dget called before cartdata()", 6)
		return ""
	end
	if value >= 0x8000 or value < -0x8000 then
		value = -0x8000
	end
	if index < 0 or index > 63 then
		warning("cartdata index out of range")
		return
	end
	pico8.cartdata[index] = value
end

local tfield = { [0] = "year", "month", "day", "hour", "min", "sec" }
function api.stat(x)
	-- TODO: implement this
	if x == 1 then
		return 0 -- TODO total cpu usage  
	-- elseif x == 0 then
	-- 	return 0 -- TODO memory usage
	-- elseif x == 2 then
	-- 	return 0 -- TODO system cpu usage
	-- elseif x == 3 then
	-- 	return 0 -- TODO current display (0..3)
	-- elseif x == 4 then
	-- 	return pico8.clipboard
	-- elseif x == 5 then
	-- 	return 41 -- pico-8 version - using latest
	-- elseif x == 7 then
	-- 	return pico8.fps -- current fps
	-- elseif x == 8 then
	-- 	return pico8.fps -- target fps
	-- elseif x == 9 then
	-- 	return love.timer.getFPS()
	-- elseif x == 32 then
	-- 	return getmousex()
	-- elseif x == 33 then
	-- 	return getmousey()
	-- elseif x == 34 then
	-- 	local btns = 0
	-- 	for i = 0, 2 do
	-- 		if love.mouse.isDown(i + 1) then
	-- 			btns = bit.bor(btns, bit.lshift(1, i))
	-- 		end
	-- 	end
	-- 	return btns
	-- elseif x == 36 then
	-- 	return pico8.mwheel
	-- elseif (x >= 80 and x <= 85) or (x >= 90 and x <= 95) then
	-- 	local tinfo
	-- 	if x < 90 then
	-- 		tinfo = os.date("!*t")
	-- 	else
	-- 		tinfo = os.date("*t")
	-- 	end
	-- 	return tinfo[tfield[x % 10]]
	-- elseif x == 100 then
	-- 	return nil -- TODO: breadcrumb not supported
	-- elseif x == 101 then
	-- 	return nil -- TODO: bbs id not supported
	-- elseif x == 102 then
	-- 	return 0 -- TODO: bbs site not supported
	-- elseif x == 103 then -- UNKNOWN
	-- 	return "0000000000000000000000000000000000000000"
	-- elseif x == 104 then -- UNKNOWN
	-- 	return false
	-- elseif x == 106 then -- UNKNOWN
	-- 	return "0000000000000000000000000000000000000000"
	-- elseif x == 122 then -- UNKNOWN
	-- 	return false
	end

	error("not implemented")
end

function api.holdframe()
	-- TODO: Implement this
end

function api.menuitem(index, label, fn) -- luacheck: no unused
	-- TODO: implement this
end

api.sub = string.sub
api.pairs = pairs
api.type = type
api.assert = assert
api.setmetatable = setmetatable
api.getmetatable = getmetatable
api.cocreate = coroutine.create
api.coresume = coroutine.resume
api.yield = coroutine.yield
api.costatus = coroutine.status
api.trace = debug.traceback
api.rawset = rawset
api.rawget = rawget
-- function api.rawlen(table) -- luacheck: no unused
-- 	-- TODO: implement this
-- end
api.rawequal = rawequal
api.next = next

-- function api.all(a)
-- 	if a == nil then
-- 		return function() end
-- 	end

-- 	local i = 0
-- 	local len = #a
-- 	return function()
-- 		len = len - 1
-- 		i = #a - len
-- 		while a[i] == nil and len > 0 do
-- 			len = len - 1
-- 			i = #a - len
-- 		end
-- 		return a[i]
-- 	end
-- end

function api.foreach(a, f)
	if not a then
		warning("foreach got a nil value")
		return
	end

	local i = 1
	while i <= #a do
		local item = a[i]
		
		if item ~= nil then
			-- 执行回调函数
			f(item)
			
			-- 关键修正逻辑：
			-- 在执行完 f(item) 后，检查当前位置 a[i] 是否还是原来的 item。
			-- 情况 1：如果 f 中执行了 del(a, item)，后面的元素会移上来，此时 a[i] 变成了下一个元素。
			--        这种情况下，我们 *不* 增加 i，下次循环直接处理这个移上来的新元素。
			-- 情况 2：如果没有删除，a[i] 还是 item。
			--        这种情况下，我们正常增加 i，处理下一个位置。
			if a[i] == item then
				i = i + 1
			end
		else
			-- 如果遇到 nil (稀疏表)，直接跳过
			i = i + 1
		end
	end
end

-- legacy function
function api.count(a, val)
	if val ~= nil then
		local count = 0
		for _, v in pairs(a) do
			if v == val then
				count = count + 1
			end
		end
		return count
	else
		return #a
	end
end

function api.add(a, v, index)
	if a == nil then
		warning("add to nil")
		return
	elseif index == nil then
		table.insert(a, v)
	else
		table.insert(a, index, v)
	end
	return v
end

function api.del(a, dv)
	if a == nil then
		warning("del from nil")
		return
	end
	for i, v in ipairs(a) do
		if v == dv then
			table.remove(a, i)
			return dv
		end
	end
end
function api.deli(...)
	local argc = select("#", ...)
	local a = select(1, ...)
	local index = select(2, ...)

	if argc == 0 or type(a) ~= "table" or #a < 1 then
		return
	end

	if argc == 1 then
		return table.remove(a, #a)
	end

	index = tonumber(index)
	if type(index) ~= "number" then
		return
	end

	local len = #a
	for i = 1, len do
		if i == index then
			return table.remove(a, i)
		end
	end
end

-- function api.serial(channel, address, length) -- luacheck: no unused
-- 	-- TODO: implement this
-- end

function api.flush()
	for y=0,127 do
		for x=0,127 do
			setColor(pico8.fb[y][x])
			love.graphics.point(x, y)
		end
	end
end

function api.bitband(c, t)
	return bit.band(c, t)
end 

return api
