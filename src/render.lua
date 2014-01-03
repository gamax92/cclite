COLOUR_RGB = {
	WHITE = {240, 240, 240},
	ORANGE = {242, 178, 51},
	MAGENTA = {229, 127, 216},
	LIGHT_BLUE = {153, 178, 242},
	YELLOW = {222, 222, 108},
	LIME = {127, 204, 25},
	PINK = {242, 178, 204},
	GRAY = {76, 76, 76},
	LIGHT_GRAY = {153, 153, 153},
	CYAN = {76, 153, 178},
	PURPLE = {178, 102, 229},
	BLUE = {37, 49, 146},
	BROWN = {127, 102, 76},
	GREEN = {87, 166, 78},
	RED = {204, 76, 76},
	BLACK = {0, 0, 0},
}

COLOUR_CODE = {
	[1] = COLOUR_RGB.WHITE,
	[2] = COLOUR_RGB.ORANGE,
	[4] =  COLOUR_RGB.MAGENTA,
	[8] = COLOUR_RGB.LIGHT_BLUE,
	[16] = COLOUR_RGB.YELLOW,
	[32] = COLOUR_RGB.LIME,
	[64] = COLOUR_RGB.PINK,
	[128] = COLOUR_RGB.GRAY,
	[256] = COLOUR_RGB.LIGHT_GRAY,
	[512] = COLOUR_RGB.CYAN,
	[1024] = COLOUR_RGB.PURPLE,
	[2048] = COLOUR_RGB.BLUE,
	[4096] = COLOUR_RGB.BROWN,
	[8192] = COLOUR_RGB.GREEN,
	[16384] = COLOUR_RGB.RED,
	[32768] = COLOUR_RGB.BLACK,
}

Screen = {
	width = 51,
	height = 19,
	textB = {},
	backgroundColourB = {},
	textColourB = {},
	font = nil,
	pixelWidth = 12,
	pixelHeight = 18,
	showCursor = false,
	textOffset = -3, -- Small correction for font, align the bottom of font with bottom of pixel.
	lastCursor = nil,
	dirty = true,
	tOffset = {},
}
function Screen:init()
	for y = 1, self.height do
		self.textB[y] = {}
		self.backgroundColourB[y] = {}
		self.textColourB[y] = {}
		for x = 1, self.width do
			self.textB[y][x] = " "
			self.backgroundColourB[y][x] = 32768
			self.textColourB[y][x] = 1
		end
	end

	self.font = love.graphics.getFont()
	for i = 32,126 do Screen.tOffset[string.char(i)] = math.floor(self.pixelWidth / 4 - self.font:getWidth(string.char(i)) / 4) * 2 end
	Screen.tOffset["@"] = 0
	Screen.tOffset["~"] = 0
end

-- Local functions are faster than global
local lsetCol = love.graphics.setColor
local ldrawRect = love.graphics.rectangle
local ldrawLine = love.graphics.line
local lprint = love.graphics.print
local tOffset = Screen.tOffset

local lastColor
local function setColor(c,f)
	if f or lastColor ~= c then
		lastColor = c
		lsetCol(c)
	end
end

function Screen:draw()
	if not Emulator.running then
		lsetCol({0,0,0})
		ldrawRect("fill", 0, 0, self.width * self.pixelWidth, self.height * self.pixelHeight )
		lsetCol({240, 240, 240})
		local text = "Press any key..."
		lprint(text, ((self.width * self.pixelWidth) / 2) - (font:getWidth(text) / 2), (self.height * self.pixelHeight) / 2)
		return
	end

	-- TODO Better damn rendering!
	-- Should only update sections that changed.

	setColor( COLOUR_CODE[ self.backgroundColourB[1][1] ], true )
	for y = 0, self.height - 1 do
		for x = 0, self.width - 1 do

			setColor( COLOUR_CODE[ self.backgroundColourB[y + 1][x + 1] ] ) -- TODO COLOUR_CODE lookup might be too slow?
			ldrawRect("fill", x * self.pixelWidth, y * self.pixelHeight, self.pixelWidth, self.pixelHeight )

		end
	end

	-- Two seperate for loops to not setColor all the time and allow batch gl calls.
	-- Is this actually a performance improvement?
	for y = 0, self.height - 1 do
		for x = 0, self.width - 1 do
			local text = self.textB[y + 1][x + 1]
			local sByte = string.byte(text)
			if sByte == 9 then
				text = " "
			elseif (sByte < 32 or sByte > 126 or sByte == 96) and sByte ~= 166 then
				text = "?"
			end
			if text ~= " " then
				setColor( COLOUR_CODE[ self.textColourB[y + 1][x + 1] ] )
				lprint( text, (x * self.pixelWidth) + tOffset[text], (y * self.pixelHeight) + self.textOffset)
			end
		end
	end

	if api.comp.blink and self.showCursor then
		local offset = self.pixelWidth / 2 - self.font:getWidth("_") / 2
		setColor(COLOUR_CODE[ api.comp.fg ])
		lprint("_", (api.comp.cursorX - 1) * self.pixelWidth + offset, (api.comp.cursorY - 1) * self.pixelHeight + self.textOffset)
	end
end
