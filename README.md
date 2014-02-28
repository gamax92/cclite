CCLite ComputerCraft Emulator
=============================

Description:
------------

This is a ComputerCraft Emulator written in Love2D. It is not complete, and is still a work in progress.

If you have installed Love2D you can just double click on the supplied cclite-latest-beta.love file to run it.

Visit the [forum topic](http://www.computercraft.info/forums2/index.php?/topic/16823-cclite-computercraft-emulator/) for CCLite.

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

From LuaSec: [Binaries](http://50.116.63.25/public/LuaSec-Binaries/), [Lua Code](http://www.inf.puc-rio.br/~brunoos/luasec/download/luasec-0.4.1.tar.gz):

  * ssl.dll -> ssl.dll
  
  * luasec-luasec-0.4.1/src/ssl.lua -> ssl.lua
  
  * luasec-luasec-0.4.1/src/https.lua -> ssl/https.lua
  
You also need to install OpenSSL: [Windows](http://slproweb.com/products/Win32OpenSSL.html)

Place these files where the love executable can get to them, where love is installed or the lua path.

Then go into conf.lua and set useLuaSec to true

**Mac:**

I dunno. Try the ssl.so file on the binaries page.

Screenshots:
------------

![Demonstration](http://i.imgur.com/87PL9Nb.png)

NOTES:
------

My fork of CCLite has a different save directory than Sorroko's version. Mine will save to the "ccemu" folder while his saves to "cclite"

TODO:
-----

Add in more error checking

Make a functional virtual redstone system

Make Error Levels report C functions properly

Make peripheralAttach only add valid sides

Have virtual Disk Drives work with Treasure disks

Timers need to use love.timer.getTime() and not os.clock()

**Add in missing globals:**

  * __inext
