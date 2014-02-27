function love.conf(t)
	t.identity = "ccemu"
	t.console = false -- Enable this to see why you get emulator messages.
	t.window.title = "ComputerCraft Emulator"
	t.window.icon = "res/icon.png"
	t.window.width = 800
	t.window.height = 600
	t.window.resizable = true
	t.window.vsync = false
	t.modules.audio = false
	t.modules.joystick = false
	t.modules.physics = false
	t.modules.sound = false
	t.modules.math = false
end
