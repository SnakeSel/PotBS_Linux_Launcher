
# PotBS Linux Launcher
Script to simplify wine environment creation, download, run game and check for updates.

## Dependencies
 - curl 
 - wget
 - winetrics (optional)

## Install
1. Set the variable `potbs_wineprefix` of your choice.  
    If the game is already installed, check the correct path in the variable `potbs_dir` (defauilt: "${potbs_wineprefix}/drive_c/PotBS")
2. Grant execution rights for files: `chmod +x launcher.sh jq-linux64 potbs_hash`
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

#### Example clean install:
1. Create new wineprefix and installing dependencies: `./launcher.sh n`
2. Download Game: `./launcher.sh d`
3. Run game: `./launcher.sh r` or `./launcher.sh`

## Wine
To successfully launch the game for wine, install:
 - d3dx9, d3dcompiler_43 from WineTricks
 - [PhysX legacy](https://www.nvidia.com/en-us/drivers/physx/physx-9-13-0604-legacy-driver/) (`winetricks -q PhysxLegacy.verb`)
