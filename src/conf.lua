function love.conf(t)
	t.identity = "ccemu"
	t.console = false -- Enable this to see why you get emulator messages.
	t.modules.audio = false
	t.modules.joystick = false
	t.modules.physics = false
	t.modules.sound = false
	t.modules.math = false
	t.modules.window = false
end
