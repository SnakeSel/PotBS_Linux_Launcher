#!/bin/bash
set -eu

# PotBS Linux Launcher
# Script to simplify wine environment creation, download, run game and check\install updates.
#
# Author: SnakeSel
# git: https://github.com/SnakeSel/PotBS_Linux_Launcher

version=20230311

### Script Directory
work_dir=$(dirname "$(readlink -e "$0")")
#work_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)
BIN_DIR="${work_dir}/bin"
DATA_DIR="${work_dir}/data"
CACHE_DIR="${work_dir}/cache"

### load modules
modules=(util.sh wine.sh PotBS.sh)

for module in "${modules[@]}"; do
    if ! source "${DATA_DIR}/${module}";then
        echo "Not load ${DATA_DIR}/${module}"
        exit 1
    fi
done

############################
### EDIT THIS SETTINGS ####

POTBS_DIR="${HOME}/Games/PotBS"

# If LEGACY client
POTBSLEGACY=0

#WINE="wine"
WINE="${HOME}/.local/wine/wine-tkg/bin/wine"

WINEPREFIX="$HOME/.local/winepfx/PotBS"

# win64 | win32
WINEARCH=win64

# show debug msg
#DEBUGGING=1

#### NOT EDIT ##############
############################
script_name=${0##*/}

jq="${BIN_DIR}/jq-linux64"
hash="${BIN_DIR}/potbs_hash"
patch4gb="${BIN_DIR}/4gb_patch.exe"

#POTBS_VERSION_INSTALLED=""
#POTBS_VERSION_SERVER=""
#POTBS_UPDATE_REQUIRED=0
######################################################

######################################################
help(){
    cat << EOF
$script_name [command] <args>
command:
    r  run game
    v  display the currently installed version of the game
    n  create new wineprefix
    d  download Game
    u  check and install updates
    c  check local files for compliance
    p  apply 4gb patch
    l  download updated locale files (RU only)
    dxvk install dxvk
    desc create desktop entry
    cfg launch winecfg

examples:
Run game:
    $script_name
    or
    $script_name r

Check update and install:
    $script_name u
EOF
}

# verify launcher dir and bin
verifying(){
    local error=0

    type "wget" >/dev/null 2>&1 || { echo >&2 "[ERR] No wget found."; error=1; }
    type "${jq}" >/dev/null 2>&1 || { echo >&2 "[ERR] No jq found."; error=1; }
    type "${hash}" >/dev/null 2>&1 || { echo >&2 "[ERR] No hash found."; error=1; }
    type "${WINE}" >/dev/null 2>&1 || { echo >&2 "[ERR] No wine found."; error=1; }


    if [ $error -eq 1 ]; then
        exit 1
    fi

}

# $1 title
# $2 text
# return: 0 yes; 1 no
dialog_yesno(){
    if (type zenity >/dev/null 2>&1);then
        zenity --question --title="$1" --text "$2" --no-wrap --ok-label "Yes" --cancel-label "No"
        return $?
    fi

    if (type whiptail >/dev/null 2>&1);then
        whiptail --title "$1" --yesno "${2}" 10 90
        return $?
    fi

    while true; do
        echo "$1"
        read -r -p "$(echo -e "$2") (y\n):" yn
            case $yn in
                [Yy]* ) return 0;;
                [Nn]* ) return 1;;
                * ) echo "Please answer yes or no.";;
        esac
    done

}


patchinstall(){
    echo "${ClMagenta}Install game pathes...${Clreset}"

    if [ -n "${1}" ];then
        echo "Manual select update to ${1}"
    fi

    if ! potbs_patchesInstall "${POTBS_DIR}" "$1";then
        case "$?" in
            200) echo_err "Not found update patch";;
            *) echo_err "Pathes not installed";;
        esac
        return 1
    fi
    echo_ok "All patches installed!"

    checkGameFiles
}

# Check update on server
# return 0 - game updated
# return 1 - game NOT update
# return 2 - error
isGameUpdated(){
    local serverVersion

    if ! serverVersion=$(potbs_getServerVersion);then
        echo_err "Not load server version"
        return 2
    fi

    if ! gameVersion=$(potbs_getlocalversion "$POTBS_DIR");then
        echo_err "Not load game version"
        return 2
    fi

    if [ "${gameVersion}" == "${serverVersion}" ];then
        #echo_ok "Update not required."
        return 0
    fi

    echo "Check update version"
    echo "Server Version: ${serverVersion}"

    currenthash=$(cat "${POTBS_DIR}/version.data")
    buildhash=$(wget --quiet -O - "${POTBS_URL}/Builds/${serverVersion}/version.data")

    if [ "${currenthash}" = "${buildhash}" ];then
        #echo_ok "Current version last updated"
        return 0
    fi

    echo "Installed version: ${gameVersion}"
    echo "Update required"
    return 1
}


checkGameFiles(){
    echo "${ClMagenta}Verify games files...${Clreset}"

    if potbs_checkLocalFiles "${POTBS_DIR}";then
        echo_ok "No corrupted files."
        return 0
    fi

    cat "$CORRUPTEDFILES"

    while true; do
        read -r -p "Download corrupted file? (y\n):" yn
        case $yn in
            [Yy]* )
                potbs_downloadCorruptedFiles "${POTBS_DIR}"
                break;;
            [Nn]* ) break;;
            * ) echo "Please answer yes or no.";;
        esac
    done

}


# Full dowload potbs
fullDownload(){
    local gameVersion
    if ! gameVersion=$(potbs_getServerVersion);then
        echo_err "$gameVersion"
        return 1
    fi

    echo "Install PotBS ${gameVersion}"
    echo "to: ${POTBS_DIR}"

    if ! potbs_downloadGame "${POTBS_DIR}" "${gameVersion}";then
        echo_err "Game NOT downloaded."
        return 1
    fi

    echo_ok "Game version ${POTBS_VERSION_SERVER} downloaded"

    checkGameFiles
}

createwinepfx(){
    if [ -f "${WINEPREFIX}/system.reg" ];then
        echo_wrn "${WINEPREFIX} exist"
        while true; do
            read -r -p "Remove ${WINEPREFIX}? (y\n):" yn
            case $yn in
                [Yy]* )
                    rm -rf "${WINEPREFIX}"
                    break;;
                [Nn]* ) return 0;;
                * ) echo "Please answer yes or no.";;
            esac
        done
    fi

    echo "${ClMagenta}Create new wineprefix...${Clreset}"

    if ! winever=$("${WINE}" --version);then
        echo_err "Wine not found"
        return 1
    fi

    echo "${winever}, WINEARCH=${WINEARCH}"
    echo ""
    echo "${ClCyan}Enter patch to wineprefix or empty to default${Clreset}"
    read -e -r -p "(default patch: ${WINEPREFIX}) :"  ptch
    if [ "${ptch}" != "" ];then
        WINEPREFIX=${ptch}
    fi
    echo "Init wine to ${WINEPREFIX}"

    if ! initWinePrefix;then
        echo_err "createWinePrefix"
        return 1
    fi

    echo "${ClMagenta}install Dependence...${Clreset}"
    if ! installWineDependence;then
        echo_err "Dependence NOT installed. Aborted"
        return 1
    fi

    echo "--------------------------"
    echo_ok "Wineprefix create"

    if ! [ -f "${POTBS_DIR}/PotBS.exe" ];then
        echo "${ClMagenta}Download Game...${Clreset}"
        while true; do
            read -r -p "Download Full Game? (y\n):" yn
            case $yn in
                [Yy]* )
                    if ! fullDownload;then
                        exit 1
                    fi
                    break;;
                [Nn]* ) break;;
                * ) echo "Please answer yes or no.";;
            esac
        done
    fi

    return 0

}

rungame(){
    if [ "${GUI:-0}" -eq 0 ];then
        if ! [ -f "${WINEPREFIX}/system.reg" ];then
            if ! createwinepfx;then
                return 1
            fi
        fi

        if ! isGameUpdated; then
            echo "[ERR] Current version NOT updated"
            if (dialog_yesno "Current version NOT updated!\n\nInstall update?");then
                patchinstall
            else
                exit 1
            fi
        else
            echo_ok "Update not required."
        fi
    fi

    if [ "${DEBUGGING:-0}" -eq 1 ]; then
        local PARAM=(DXVK_HUD="devinfo,fps,version," DXVK_LOG_LEVEL="info")
        local WINEDEBUG="fixme-all,err+loaddll,err+dll,err+file,err+reg"
        local out="${POTBS_DIR}/PotBS.exe.log"
    else
        local PARAM=(DXVK_LOG_LEVEL="none")
        local WINEDEBUG="-all"
        local out="/dev/null"
    fi

    cd "${POTBS_DIR}" || { echo "[err] cd to ${POTBS_DIR}";exit 1; }
    echo_debug "env ${PARAM[*]} WINEARCH=\"${WINEARCH}\" WINEDEBUG=\"${WINEDEBUG}\" WINEPREFIX=\"${WINEPREFIX}\" WINE_LARGE_ADDRESS_AWARE=1 nohup \"${WINE}\" PotBS.exe &>\"${out}\" &"
    env "${PARAM[@]}" WINEARCH="${WINEARCH}" WINEDEBUG="${WINEDEBUG}" WINEPREFIX="${WINEPREFIX}" WINE_LARGE_ADDRESS_AWARE=1 nohup "${WINE}" PotBS.exe &>"${out}" &
    sleep 2
}

downloadLocale(){
    echo "${ClMagenta}Download Updated RU locale${Clreset}"
    potsb_downloadLocale "${POTBS_DIR}"
}

apply4gb(){
    echo "${ClMagenta}Apply 4gb patch to PotBS.exe${Clreset}"

    if [ ! -f "${patch4gb}" ];then
        echo_err "4gb patch not found in: ${patch4gb}"
        exit 1
    fi

    if WINEARCH="${WINEARCH}" WINEDEBUG="-all" WINEPREFIX="${WINEPREFIX}" ${WINE} "${patch4gb}" "${POTBS_DIR}/PotBS.exe";then
        echo_ok "4gb patch"
    else
        echo_err "4gb patch NOT apply"
        exit 1
    fi

}

create_desktop(){

cat << EOF > PotBS.desktop
[Desktop Entry]
Type=Application
Name=PotBS
Comment=PotBS Linux Launcher
Exec=${work_dir}/launcher.sh
Icon=${DATA_DIR}/PotBS.png
Terminal=true
EOF

    chmod +x PotBS.desktop
    if type "xdg-user-dir" >/dev/null 2>&1;then
        local desctopDir
        desctopDir=$(xdg-user-dir "DESKTOP")
        cp -f "PotBS.desktop" "${desctopDir}"
    fi

}

show_version(){
    gameVer=$(potbs_getlocalversion "$POTBS_DIR")

    echo -e "${ClMagenta}PotBS launcher from SnakeSel${Clreset}
version: ${version}

${ClCyan}PotBS version: ${gameVer}${Clreset}
PotBS game dir: ${POTBS_DIR}

wine:\t$WINE
pfx:\t${WINEPREFIX}
arch:\t$WINEARCH
"
}

#####################################################################################
# verify launcher dir and bin
verifying

if ! [ -d "${CACHE_DIR}" ]; then
    mkdir -p "${CACHE_DIR}"
fi

if [ "${POTBSLEGACY:-0}" -eq 1 ]; then
    echo "${ClMagenta}Legacy client${Clreset}"
    POTBS_URL="$LEGACY_URL"
fi

#Если запуск без параметров - запуск игры
if [ "$#" -eq 0 ];then
    rungame
    exit 0
fi

case "$1" in
    v) show_version;;
    n)  if ! createwinepfx;then
            exit 1
        fi
    ;;
    d)  if ! fullDownload;then
            exit 1
        fi
    ;;
    u)  if isGameUpdated; then
            return 0
        fi
        echo ""
        while true; do
        read -r -p "Install update? (y\n):" yn
        case $yn in
            [Yy]* )
                if [ "${2}" ];then
                    patchinstall "${2}"
                else
                    patchinstall
                fi
                checklocalfiles
                break;;
            [Nn]* ) break;;
            * ) echo "Please answer yes or no.";;
        esac
        done
    ;;
    c) checkGameFiles;;
    r) rungame;;
    l) downloadLocale;;
    p) apply4gb;;
    dxvk) install_dxvk;;
    desc) create_desktop;;
    cfg) env WINEARCH="${WINEARCH}" WINEDEBUG="-all" WINEPREFIX="${WINEPREFIX}" "${WINE}" winecfg;;
    reg) env WINEARCH="${WINEARCH}" WINEDEBUG="-all" WINEPREFIX="${WINEPREFIX}" "${WINE}" regedit;;
    gui) source "${DATA_DIR}/gui.sh";;
    *) help;;
esac

exit 0
