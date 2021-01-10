
# PotBS_Linux_Launcher
## Dependencies
 - curl 
 - wget

## Install
1. Put the files in the game folder.  
You can run from any folder, but then write the path to the game in variable `potbs_dir`
2. Grant execution rights for files: `chmod +x launcher.sh jq-linux64`
3. Run `./launcher.sh`

## Usage

    launcher.sh [command] <args>
command:

 - v  - display the currently installed version of the game
 - u  - check for updates
	 - ~~-i - install update (patch)~~ in dev
	 - -f - install update (full)
 - ~~c  - check local files for compliance~~ in dev

#### examples:
Check update and exit:     `./launcher.sh u`  
~~Check update and install:    `./launcher.sh u -i`~~ in dev  
Full install latest version:    `./launcher.sh u -f`  
Full install version 2.17.7:  `./launcher.sh u -f 2.17.7`  
