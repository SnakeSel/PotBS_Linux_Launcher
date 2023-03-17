# PotBS Linux Launcher
Script to simplify wine environment creation, download, run game and check for updates.

## Dependencies
 - wine
 - wget
 - winetrics
 - zenity (optional for GUI)

## Install
1. Customize the script as you wish.
    Main settings:
    * `potbs_wineprefix` = path to wineprefix directory (default: "${HOME}/.local/winepfx/PotBS")
    * `potbs_dir` = path to game directory (default: "${HOME}/Games/PotBS")
    * `POTBSLEGACY` = set to 1 if you want to load legacy game. (default: 0)
2. Grant execution rights for files: `chmod +x launcher.sh bin/jq-linux64 bin/potbs_hash`
3. Run `./launcher.sh`


## Usage
    launcher.sh [command] <args>
command:
 - r  - run game
 - v  - display the currently installed version of the game
 - n  - create new wineprefix and installing dependencies (need winetrics)
 - d  - dowload game
 - u  - check for updates and install it
 - c  - check local files for compliance
 - dxvk - install dxvk
 - desc - create desktop entry
 - cfg - launch winecfg
 - gui - launch GUI mode (develop)

#### Example clean install:
1. Create new wineprefix and installing dependencies: `./launcher.sh n`
2. Download Game: `./launcher.sh d`
3. Run game: `./launcher.sh r` or `./launcher.sh`

## Wine
To successfully launch the game for wine, install:
 - d3dx9, d3dcompiler_43 from WineTricks
 - [PhysX legacy](https://www.nvidia.com/en-us/drivers/physx/physx-9-13-0604-legacy-driver/) (`winetricks -q PhysxLegacy.verb`)

## ERROR Memory: memory allocation failed for pool Main.Default
Try lowering the `[MemoryPools]` `preSize_*` settings in the `pirates.ini` file.  
It is better to create an additional settings file `pirates_local.ini` and add to it:
```
[MemoryPools]
;; size in MB
preSize_Bootstrap=2
preSize_Default=256
preSize_Image=486
preSize_Vertex=128
preSize_Audio=64
preSize_Room=486
preSize_UI=64
preSize_Anim=486
```
