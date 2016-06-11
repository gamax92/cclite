CCLite ComputerCraft Emulator
=============================

Description:
------------

This is a ComputerCraft Emulator written in Love2D. It is not complete, and is still a work in progress.

Visit the [forum topic](http://www.computercraft.info/forums2/index.php?/topic/16823-cclite-computercraft-emulator/) for CCLite downloads.

HTTPS Support:
----------------

**Linux:**

```
apt-get install lua-sec
```

This should get everything you need.

Then go into conf.lua and set useLuaSec to true

**Windows:**

You can try LuaRocks to see if it has LuaSec, I did it manually

For HTTPS support, you'll need to grab:

From LuaSec: [Binaries](http://50.116.63.25/public/LuaSec-Binaries/), [Lua Code](https://github.com/brunoos/luasec/tree/master/src):

  * [ssl.dll](http://50.116.63.25/public/LuaSec-Binaries/windows/x86_64/ssl.dll) -> ssl.dll
  
  * [/src/ssl.lua](https://raw.githubusercontent.com/brunoos/luasec/master/src/ssl.lua) -> ssl.lua
  
  * [/src/https.lua](https://raw.githubusercontent.com/brunoos/luasec/master/src/https.lua) -> ssl/https.lua
  
(right-click -> save as)

You also need to install OpenSSL: [Windows](http://slproweb.com/products/Win32OpenSSL.html)

Place these files where the love executable can get to them, where love is installed or the lua path.

Then go into conf.lua and set useLuaSec to true

**Mac:**

The easiest method is probably to install luarocks through homebrew:
```
brew install lua
luarocks install luasec
```
(lua brew package comes with luarocks)

otherwise you can try installing the so and lua files in the binaries page simmilar to windows

Screenshots:
------------

![Demonstration](http://i.imgur.com/VSCl7IN.png)

NOTES:
------

My fork of CCLite has a different save directory than Sorroko's version. Mine will save to the "ccemu" folder while his saves to "cclite"

TODO:
-----

Add in more error checking

Make peripheralAttach only add valid sides

Have virtual Disk Drives work with Treasure disks

