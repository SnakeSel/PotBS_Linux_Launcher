
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
 - u  - check for updates
	 - ~~-i - install update (patch)~~ in dev
	 - -f - install update (full)
 - c  - check local files for compliance
 - n  - create new wineprefix and installing dependencies (need winetrics)

#### examples:
Check update and exit:     `./launcher.sh u`  
~~Check update and install:    `./launcher.sh u -i`~~ in dev  
Full install latest version:    `./launcher.sh u -f`  
Full install version 2.17.7:  `./launcher.sh u -f 2.17.7`  


## Wine
To successfully launch the game for wine, install:
 - d3dx9, d3dcompiler_43 from WineTricks
 - [PhysX legacy](https://www.nvidia.com/en-us/drivers/physx/physx-9-13-0604-legacy-driver/) (`winetricks -q PhysxLegacy.verb`)
