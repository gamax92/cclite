-- demo library
demo = {}

-- table to store available examples
demo.examples = {}
demo.examples[1] = {category_title = "Object Demonstrations", registered = {}}
demo.examples[2] = {category_title = "Example Implementations", registered = {}}

demo.exampleslist = nil
demo.examplesbutton = nil
demo.centerarea = {5, 40, 540, 555}

function demo.Load()

	-- require all example files
	local files = loveframes.util.GetDirectoryContents("examples")
	for k, v in ipairs(files) do
		if v.extension == "lua" then
			require(v.requirepath)
		end
	end
	
	-- create demo gui
	demo.CreateToolbar()
	demo.CreateExamplesList()
	
end

function demo.CreateToolbar()

	local width = love.graphics.getWidth()
	local version = loveframes.version
	local stage = loveframes.stage
	
	local toolbar = loveframes.Create("panel")
	toolbar:SetSize(width, 35)
	toolbar:SetPos(0, 0)
	
	local info = loveframes.Create("text", toolbar)
	info:SetPos(5, 3)
	info:SetText({{0, 0, 0, 255}, "Love Frames (version " ..version.. " - " ..stage.. ") \n ", {255, 102, 0, 255}, "F1", {0, 0, 0, 255}, ": Toggle debug mode - ", {255, 102, 0, 255}, "F2", {0, 0, 0, 255}, ": Remove all objects"})
	
	demo.examplesbutton = loveframes.Create("button", toolbar)
	demo.examplesbutton:SetPos(toolbar:GetWidth() - 105, 5)
	demo.examplesbutton:SetSize(100, 25)
	demo.examplesbutton:SetText("Show Examples")
	demo.examplesbutton.OnClick = function()
		demo.ToggleExamplesList()
	end
	
	local skinslist = loveframes.Create("multichoice", toolbar)
	skinslist:SetPos(toolbar:GetWidth() - 250, 5)
	skinslist:SetWidth(140)
	skinslist:SetChoice("Choose a skin")
	skinslist.OnChoiceSelected = function(object, choice)
		loveframes.util.SetActiveSkin(choice)
	end
	
	local skins = loveframes.skins.available
	for k, v in pairs(skins) do
		skinslist:AddChoice(v.name)
	end
	skinslist:Sort()

end

function demo.RegisterExample(example)
	
	local examples = demo.examples
	local category = example.category
	
	for k, v in ipairs(examples) do
		if v.category_title == category then
			table.insert(examples[k].registered, example)
		end
	end
	
end

function demo.CreateExamplesList()

	local examples = demo.examples
	local width = love.graphics.getWidth()
	local height = love.graphics.getHeight()
	
	demo.exampleslist = loveframes.Create("list")
	demo.exampleslist:SetPos(width + 10, 35)
	demo.exampleslist:SetSize(250, height - 35)
	demo.exampleslist:SetPadding(5)
	demo.exampleslist:SetSpacing(5)
	demo.exampleslist:SetVisible(false)
	demo.exampleslist.toggled = false
	
	for k, v in ipairs(examples) do
		local panelheight = 0
		local category = loveframes.Create("collapsiblecategory")
		category:SetText(v.category_title)
		local panel = loveframes.Create("panel")
		panel.Draw = function() end
		demo.exampleslist:AddItem(category)
		for key, value in ipairs(v.registered) do
			local button = loveframes.Create("button", panel)
			button:SetWidth(210)
			button:SetPos(0, panelheight)
			button:SetText(value.title)
			button.OnClick = function()
				value.func()
			end
			panelheight = panelheight + 30
		end
		panel:SetHeight(panelheight)
		category:SetObject(panel)
		category:SetOpen(true)
	end
	
end

function demo.ToggleExamplesList()

	local toggled = demo.exampleslist.toggled
	local width = love.graphics.getWidth()
	local listwidth = demo.exampleslist:GetWidth()
	
	tween.stopAll()
	
	if not toggled then
		local listwidth = demo.exampleslist:GetWidth()
		demo.exampleslist.toggled = true
		demo.exampleslist:SetVisible(true)
		tween(0.10, demo.exampleslist, {x = (width - listwidth)})
		demo.examplesbutton:SetText("Hide Examples")
	else
		demo.exampleslist.toggled = false
		tween(0.10, demo.exampleslist, {x = (width + 10)}, "linear", function() demo.exampleslist:SetVisible(false) end)
		demo.examplesbutton:SetText("Show Examples")
	end
	
end

demo.Load()