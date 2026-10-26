#!/bin/bash
# Starts the COD Zombies server (ps4srv, Minecraft PS4) from this folder. Ctrl+C, or typing "stop", saves the world and stops it;
# "help" lists the console's commands. On Windows double-click start.bat (it runs this in WSL Ubuntu).
#
# The folder, laid out like a Java server:
#   start.bat / start.sh  this
#   ps4srv                the server itself (Linux) - the game's own server code, run outside a PS4
#   new_block.prx         the game plugin it runs inside the game (the PS4s that join need the same version)
#   server.properties     the settings: world size and type, game mode, difficulty, PvP, motd, port...
#   ops.txt               the operators, one PSN name a line
#   plugins/              Lua plugins - a folder each with its plugin.lua (none to start with); /plugins in the console
#   worlds/               the world (world.0: level and players; world.1, ...: its regions) - delete it for a new one
#   logs/                 latest.log, the older ones gzipped; crash-reports/ should it crash
# (data/, temp0/ and download0/ appear while it runs: the plugin's own files - settings, log, world keys.)
# The game's own files stay where they are (below); the server only reads them.
GAME="/mnt/c/Users/wwasd/Documents/CUSA00744-app0"
PATCH="/mnt/c/Users/wwasd/Documents/CUSA00744-patch0"

cd "$(dirname "$0")" || exit 1
chmod +x ./ps4srv 2>/dev/null
exec ./ps4srv --game "$GAME" --code "$PATCH" --plugin ./new_block.prx --data "$PWD" "$@"
