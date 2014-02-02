emu = {}
function emu.newComputer()
	local Emulator = {}
	Emulator.frame = loveframes.Create("frame")
	Emulator.frame.emu = Emulator
	Emulator.frame:SetName("Advanced Computer")
	Emulator.frame:SetSize((_conf.terminal_width * 6 * _conf.terminal_guiScale) + (_conf.terminal_guiScale * 2) + 2, (_conf.terminal_height * 9 * _conf.terminal_guiScale) + (_conf.terminal_guiScale * 2) + 26)
	Emulator.frame:CenterWithinArea(0,0,L2DScreenW, L2DScreenH)
	Emulator.frame.olddraw = Emulator.frame.draw
	function Emulator.frame:draw()
		self:olddraw()
		love.graphics.translate(self.x + 1, self.y + 25)
		Screen:draw(self.emu)
		love.graphics.translate(-self.x - 1, -self.y - 25)
	end
	return Emulator
end