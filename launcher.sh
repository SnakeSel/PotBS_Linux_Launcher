#!/bin/bash

# PotBS Linux Launcher
# Script to simplify wine environment creation, download, run game and check\install updates.
#
# Author: SnakeSel
# git: https://github.com/SnakeSel/PotBS_Linux_Launcher

version=20230305

#### EDIT THIS SETTINGS ####
potbs_wineprefix="$HOME/.local/winepfx/PotBS"
#potbs_dir="${potbs_wineprefix}/drive_c/PotBS"
potbs_dir="${HOME}/Games/PotBS"

# If LEGACY client
POTBSLEGACY=0

WINE="wine"
#WINE="${HOME}/.local/wine/wine-tkg/bin/wine"
#WINE="${HOME}/.local/wine/Wine-GE/bin/wine"

# win64 | win32
WINEARCH=win64

# show debug msg
#debugging=1

# use test mode, not apply change
#testing=1

#### NOT EDIT ##############
script_name=${0##*/}
# полный путь до скрипта
abs_filename=$(readlink -e "$0")
# каталог в котором лежит скрипт
work_dir=$(dirname "$abs_filename")
bin_dir="${work_dir}/bin"
data_dir="${work_dir}/data"
buildsversion="${data_dir}/builds"
corruptedfiles="${data_dir}/corrupted"

jq="${bin_dir}/jq-linux64"
hash="${bin_dir}/potbs_hash"
patch4gb="${bin_dir}/4gb_patch.exe"

potbs_url="https://cdn.visiononlinegames.com/potbs/launcher"
legacy_url="https://cdn.visiononlinegames.com/potbs/legacy/launcher"

POTBS_VERSION_INSTALLED=""
POTBS_VERSION_SERVER=""
POTBS_UPDATE_REQUIRED=0
######################################################
## Colors
ClRed=$(tput setaf 1)
ClGreen=$(tput setaf 2)
ClYellow=$(tput setaf 3)
#ClBlue=$(tput setaf 4)
ClMagenta=$(tput setaf 5)
ClCyan=$(tput setaf 6)
#ClWhite=$(tput setaf 7)
Clreset=$(tput sgr0) #сброс цвета на стандартный
#Cltoend=$(tput hpa $(tput cols))$(tput cub 6) # сдвигает послед. текст до конца экрана
######################################################
press_and_cont(){
    echo ""
    read -n 1 -s -r -p "Press any key to continue."
    echo ""
}

echo_err(){
    echo -e "${ClRed}[ERR] ${1}${Clreset}"
    press_and_cont
}
echo_wrn(){
    echo -e "${ClYellow}[WRN] ${1}${Clreset}"
}
echo_ok(){
    echo -e "${ClGreen}${1} OK${Clreset}"
}

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

debug() {
    if [ "${debugging:-0}" -eq 1 ]; then
        #echo "$(date +'%Y-%m-%d %H:%M:%S')" "$@" >> "${logfile}/${script_name}.log"
        echo "[DBG:${BASH_LINENO[0]}] $*"
    fi
}

# verify launcher dir and bin
verifying(){
    local error=0

    type "wget" >/dev/null 2>&1 || { echo >&2 "[ERR] No wget found."; error=1; }
    type "${jq}" >/dev/null 2>&1 || { echo >&2 "[ERR] No jq found."; error=1; }
    type "${hash}" >/dev/null 2>&1 || { echo >&2 "[ERR] No hash found."; error=1; }

    if ! [ -d "${data_dir}" ]; then
        #echo "No ${data_dir}"
        mkdir -p "${data_dir}"
    fi

    if [ $error -eq 1 ]; then
        exit 1
    fi

}

# $1 - "{owner}/{repo}"
get_latest_release() {
    #wget --quiet -O - "https://api.github.com/repos/$1/releases/latest" | # Get latest release from GitHub api
    #grep '"tag_name":' |                                            # Get tag line
    #sed -E 's/.*"([^"]+)".*/\1/'                                    # Pluck JSON value
    wget --quiet -O - "https://api.github.com/repos/$1/releases/latest" | "${jq}" -r '.tag_name'

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


# since applying patches requires a separate application, then
# read the modified files and download them entirely
# 
# Patch Operation:
# 0 = no change
# 1 = deleted
# 2 = updated
# 3 = changed attributes
# 4 = added
patchinstall(){

    if [ -n "${1}" ];then
        echo "Manual select update to ${1}"
        POTBS_VERSION_SERVER="${1}"
    else
        getServerVersion
    fi

    if [ "${testing:-0}" -eq 1 ];then
        POTBS_VERSION_INSTALLED="2.17.7"
        echo "test: POTBS_VERSION_INSTALLED=$POTBS_VERSION_INSTALLED"
    else
        getlocalversion
    fi


    if [ "${POTBS_VERSION_INSTALLED}" == "${POTBS_VERSION_SERVER}" ];then
        echo "Update not required."
        return
    fi

    echo "Cheking patches ${POTBS_VERSION_INSTALLED} to ${POTBS_VERSION_SERVER} ..."
    patchesindex=$(wget --quiet -O - "${potbs_url}/Patches/patches_index.json")
    echo "${patchesindex}" | grep "Not Found" > /dev/null
    if [ $? -eq 0 ];then
        echo "[ERR] patches_index.json not found"
        exit 1
    fi

    # before we install all the patches 
    while [ "${POTBS_VERSION_INSTALLED}" != "${POTBS_VERSION_SERVER}" ];do
        if [ -n "${1}" ];then
            echo "Manual select update to ${1}"
            patchTo="${1}"
        else
            patchTo=$(echo "${patchesindex}" | "${jq}" -r --arg POTBS_VERSION_INSTALLED "${POTBS_VERSION_INSTALLED}" '.["Patches"] | .[] | select(.From==$POTBS_VERSION_INSTALLED) |.To' 2> /dev/null )
        fi
        # echo '''


        debug "patchTo: ${patchTo}"
        if [ -z "${patchTo}" ];then
            # Если не нашли патча, а текущая версия предпоследняя, то можем сами подставить версию
            # ситуация когда Vision сломали patches_index.json
            prerel=$(wget --quiet -O - "${potbs_url}/Builds/builds_index.json" | "${jq}" -r '.["AvailableBuilds"] | .[-2]')
            if [ "${prerel}" == "${POTBS_VERSION_INSTALLED}" ];then
                patchTo="${POTBS_VERSION_SERVER}"
            else
                echo "[ERR] Not found update patch from ${POTBS_VERSION_INSTALLED} in patches_index.json"
                echo "If you are sure that the patch from version ${POTBS_VERSION_INSTALLED} exists, start the launcher specifying which patch you need to install:"
                echo "$script_name u <pathTO>"
                exit 1
            fi
        fi

        echo ""
        echo "patch from ${POTBS_VERSION_INSTALLED} to ${patchTo}"

        patchName="${POTBS_VERSION_INSTALLED}_${patchTo}"
        debug "patchName: ${patchName}"

        patchlist=$(wget --quiet -O - "${potbs_url}/Patches/${patchName}.json")
        echo "${patchlist}" | grep "Not Found" > /dev/null
        if [ $? -eq 0 ];then
            echo "[ERR] Patch ${patchName}.json not found"
            exit 1
        fi

        pathDel=$(echo "${patchlist}" | "${jq}" -r '.["Entries"] | .[] | select(.Operation==1) | .RelativePath')
        debug "pathDel: ${pathDel}"

        pathUpdate=$(echo "${patchlist}" | "${jq}" -r '.["Entries"] | .[] | select(.Operation==2) | .RelativePath')
        debug "pathUpdate: $pathUpdate"

        pathAdd=$(echo "${patchlist}" | "${jq}" -r '.["Entries"] | .[] | select(.Operation==4) | .RelativePath')
        debug "pathAdd: $pathAdd"

        # echo '''

        echo "Apply the patch ..."

        # Если тестируем то пропускаем примененеие
        if [ "${testing:-0}" -ne 1 ]; then
            echo "Remove deleted files..."
            while read -r LINE;do
                if [ "$LINE" == "" ];then
                    continue
                fi
                rm -f "${potbs_dir}/${LINE}"
            done < <(printf '%s\n' "${pathDel}")

            echo "Remove old and download updated files"
            while read -r fullfile;do
                if [ "$fullfile" == "" ];then
                    continue
                fi
                filedir=$(dirname "$fullfile")
                rm -f "${potbs_dir}/${fullfile}"
                wget -c -nH -q --show-progress -P "${potbs_dir}/${filedir}" "${potbs_url}/Builds/${patchTo}/${fullfile}"
            done < <(printf '%s\n' "$pathUpdate")

            echo "Download added files"
            while read -r fullfile;do
                filedir=$(dirname "$fullfile")
                wget -c -nH -q --show-progress -P "${potbs_dir}/${filedir}" "${potbs_url}/Builds/${patchTo}/${fullfile}"
            done < <(printf '%s\n' "${pathAdd}")
        fi

        echo "patch apply finished"

        POTBS_VERSION_INSTALLED=${patchTo}

    done
    echo""
    echo "All patches installed!"
    echo""

}

# Check update on server
# and write to POTBS_UPDATE_REQUIRED
checkupdate(){
    getServerVersion

    if [ "${POTBS_VERSION_INSTALLED}" == "${POTBS_VERSION_SERVER}" ];then
        echo "Update not required."
        return
    fi

    echo "Check update version"
    echo "Server Version: ${POTBS_VERSION_SERVER}"

    currenthash=$(cat "${potbs_dir}/version.data")
    buildhash=$(wget --quiet -O - "${potbs_url}/Builds/${POTBS_VERSION_SERVER}/version.data")

    if [ "${currenthash}" = "${buildhash}" ];then
        echo "Current version last updated"
        POTBS_UPDATE_REQUIRED=0
        return
    fi

    getlocalversion
    if [ $? -ne 0 ];then
        debug "[ERR] checkupdate:getlocalversion"
        exit 1
    fi

    echo "Installed version: ${POTBS_VERSION_INSTALLED}"
    echo "Update required"
    POTBS_UPDATE_REQUIRED=1

}

# determine server game version
# and write it to POTBS_VERSION_SERVER
getServerVersion(){
    debug "getServerVersion"
    POTBS_VERSION_SERVER=$(wget --quiet -O - "${potbs_url}/Builds/builds_index.json" | "${jq}" -r '.["AvailableBuilds"] | .[-1]')
    if [ -n "$POTBS_VERSION_SERVER" ];then
        return 0
    else
        echo "[ERR] failed to get server version"
        #return 1
        exit 1
    fi
}

# determine installed game version
# and write it to POTBS_VERSION_INSTALLED
getlocalversion(){
    # get version hash installed game
    debug "getlocalversion"
    localhash=$(cat "${potbs_dir}/version.data")
    if [ $? -ne 0 ];then
        echo "[ERR] Not found: ${potbs_dir}/version.data"
        echo "Maybe Game not installed?"
        #return 1
        exit 1
    fi

    debug "localhash = ${localhash}"

    # if version number is in the file $buildsversion, return it
    if [ -f "${buildsversion}" ];then
        # Убираем пробелы в начале и комментарии:
        raw_param=$(grep "${localhash}" "${buildsversion}" | sed 's/^[ \t]*//' | grep -v "^#" )
        # Берем значение и убираем пробелы в начале и конце
        param=$(echo "${raw_param}" | cut -d"=" -f1 | sed 's/^[ \t]*//' | sed 's/[ \t]*$//')

        # if installed version found, exit function
        if [ "${param}" != "" ];then
            POTBS_VERSION_INSTALLED=${param}
            debug "POTBS_VERSION_INSTALLED=${param}"
            #echo "${result}"
            return 0
        fi
    else
        echo "Builds file not exist"
    fi

    echo "Builds file does not contain version"
    echo "recreate Builds file"

    # if version nomber not in file, recreate file
    echo "File create: $(date +'%Y-%m-%d %H:%M:%S')" > "${buildsversion}"

    # get an array of all versions
    oldIFS=$IFS
    IFS=', ' # разделитель запятая или пробел
    read -r -a allbuilds <<< "$(wget --quiet -O - "${potbs_url}/Builds/builds_index.json" | "${jq}" -r -c '.["AvailableBuilds"]' | sed 's/\[//' | sed 's/]//' | sed 's/"//g')"
    IFS=$oldIFS

    debug "read allbuilds finish"

    for build in "${allbuilds[@]}"; do
        buildhash=$(wget --quiet -O - "${potbs_url}/Builds/${build}/version.data")

        echo "${buildhash}" | grep "Not Found" > /dev/null
        if [ $? -eq 0 ];then
            debug "Version ${build} not found"
            continue
        fi

        if [ "${localhash}" = "${buildhash}" ];then
            result="${build}"
        fi
        debug "$build=${buildhash}"
        echo "$build=${buildhash}" >> "${buildsversion}"
    done

    if [ "${result}" != "" ];then
        POTBS_VERSION_INSTALLED=${result}
        debug "POTBS_VERSION_INSTALLED=${result}"
        #echo "${result}"
        return 0
    else
        echo "[ERR] Installed Game version unspecified"
    fi

    #return 1
    exit 1
}


checklocalfiles(){
    getlocalversion
    hashFile="${data_dir}/hashsum_${POTBS_VERSION_INSTALLED}"

    echo "${ClMagenta}Checking game files started...${Clreset}"

    wget --quiet -O - "${potbs_url}/Builds/build_${POTBS_VERSION_INSTALLED}.json" | "${jq}" -r '.["Entries"] | .[] | {"Hash","RelativePath"} | join("  ")' > "${hashFile}"

    cd "${potbs_dir}" || exit

    "${hash}" -c "${hashFile}" | grep "FAIL" | tee "${corruptedfiles}"
    if [ ! -s "${corruptedfiles}" ];then
        echo_ok "No corrupted file. "
        rm -f "${corruptedfiles}"
        cd "${work_dir}" || exit
        return
    fi

    cd "${work_dir}" || exit

    echo ""
    while true; do
        read -r -p "Download corrupted file? (y\n):" yn
        case $yn in
            [Yy]* )
                while read -r LINE;do
                    fullfile=$(echo "$LINE" | awk '{ print $2 }')
                    #filename=$(basename "$fullfile")
                    filedir=$(dirname "$fullfile")
                    rm -f "${potbs_dir}/${fullfile}"
                    wget -c -nH -q --show-progress -P "${potbs_dir}/${filedir}" "${potbs_url}/Builds/${POTBS_VERSION_INSTALLED}/${fullfile}"
                done < "${corruptedfiles}"
                rm -f "${corruptedfiles}"
                break;;
            [Nn]* ) break;;
            * ) echo "Please answer yes or no.";;
        esac
    done

}


# Full dowload potbs
fullinstall(){
    getServerVersion

    local _cutdirs
    _cutdirs=4
    if [ "${POTBSLEGACY:-0}" -eq 1 ]; then
        _cutdirs=5
    fi

    echo "Install PotBS ${POTBS_VERSION_SERVER}"
    echo "to: ${potbs_dir}"
    wget -c -r -nH --cut-dirs=${_cutdirs} --no-parent -q --show-progress -P "${potbs_dir}" --reject="index.html*" "${potbs_url}/Builds/${POTBS_VERSION_SERVER}/"
    if [ $? -eq 0 ];then
        echo_ok "Game version ${POTBS_VERSION_SERVER} installed"
    else
        echo_err "Error download"
    fi

    checklocalfiles
}

winetricksInstall(){
    debug "WINEARCH=\"${WINEARCH}\" WINEPREFIX=\"${potbs_wineprefix}\" WINE=\"${WINE}\" winetricks -q -f $1"
    env WINEARCH="${WINEARCH}" WINEDEBUG="-all" WINEPREFIX="${potbs_wineprefix}" WINE="${WINE}" winetricks -q -f "$1"
}


installDependence(){
    cont(){
        echo ""
        while true; do
        read -r -p "Continue install? (y\n):" yn
        case $yn in
            [Yy]* )
                break;;
            [Nn]* )
                exit 1
                break;;
            * ) echo "Please answer yes or no.";;
        esac
        done
    }

    if ! type winetricks >/dev/null 2>&1;then
        echo_err "No winetricks found. Aborting."
        return 1
    fi

    if ! winetricksInstall "d3dx9";then
        echo_err "d3dx9 NOT installed"
        cont
    fi

    if ! winetricksInstall "d3dcompiler_43";then
        echo_err "d3dcompiler_43 NOT installed"
        cont
    fi

    if ! winetricksInstall "vcrun2019";then
        echo_err "vcrun2019 NOT installed"
        cont
    fi

    if ! winetricksInstall "${work_dir}/PhysxLegacy.verb";then
        echo_err "PhysxLegacy NOT installed"
        cont
    fi

    return 0
}

createwineprefix(){
    echo "${ClMagenta}Create new wineprefix...${Clreset}"

    if ! type "${WINE}" >/dev/null 2>&1;then
        echo_err "No wine found.  Aborting."
        return 1
    fi

    if ! winever=$("${WINE}" --version);then
        echo_err "Wine not found"
        return 1
    fi

    echo "${winever}, WINEARCH=${WINEARCH}"
    echo ""
    echo "${ClCyan}Enter patch to wineprefix or empty to default${Clreset}"
    read -e -r -p "(default patch: ${potbs_wineprefix}) :"  ptch
    if [ "${ptch}" != "" ];then
        potbs_wineprefix=${ptch}
    fi
    echo "Init wine to ${potbs_wineprefix}"

    if ! [ -d "${potbs_wineprefix}" ]; then
        mkdir -p "${potbs_wineprefix}"
    fi


    #WINEARCH="${WINEARCH}" WINEPREFIX="${potbs_wineprefix}" wineboot --init
    if ! env WINEARCH="${WINEARCH}" WINEDEBUG="-all" WINEPREFIX="${potbs_wineprefix}" ${WINE} wineboot -u;then
        echo_err "Create wineprefix"
        return 1
    fi

    echo "${ClMagenta}install Dependence...${Clreset}"
    if ! installDependence;then
        echo_err "Dependence NOT installed. Aborted"
        return 1
    fi

    echo "--------------------------"
    echo_ok "Wineprefix create"

    if ! [ -f "${potbs_dir}/PotBS.exe" ];then 
        echo "${ClMagenta}Download Game...${Clreset}"
        while true; do
            read -r -p "Download Full Game? (y\n):" yn
            case $yn in
                [Yy]* )
                    fullinstall
                    break;;
                [Nn]* ) break;;
                * ) echo "Please answer yes or no.";;
            esac
        done
    fi

    return 0

}

rungame(){
    if ! [ -f "${potbs_wineprefix}/system.reg" ];then
        if ! createwineprefix;then
            return 1
        fi
    fi

    checkupdate

    if [ "${POTBS_UPDATE_REQUIRED}" -eq 1 ]; then
        echo "[ERR] Current version NOT updated"

        if (dialog_yesno "Current version NOT updated" "version ${POTBS_VERSION_SERVER} available.\n\nInstall update?");then
            patchinstall
            checklocalfiles
        else
            exit 1
        fi

    fi

    if [ "${debugging:-0}" -eq 1 ]; then
        local PARAM=(DXVK_HUD="devinfo,fps,version," DXVK_LOG_LEVEL="info")
        local WINEDEBUG="fixme-all,err+loaddll,err+dll,err+file,err+reg"
        local out="${potbs_dir}/PotBS.exe.log"
    else
        local PARAM=(DXVK_LOG_LEVEL="none")
        local WINEDEBUG="-all"
        local out="/dev/null"
    fi

    cd "${potbs_dir}" || { echo "[err] cd to ${potbs_dir}";exit 1; }
    env "${PARAM[@]}" WINEARCH="${WINEARCH}" WINEDEBUG="${WINEDEBUG}" WINEPREFIX="${potbs_wineprefix}" WINE_LARGE_ADDRESS_AWARE=1 nohup "${WINE}" PotBS.exe &>"${out}" &
    sleep 2

}

downloadLocale(){
    echo "${ClMagenta}Download Updated RU locale${Clreset}"

    rm "${potbs_dir}/locale/ru_ru_data.dat"
    wget -c -nH -q --show-progress -P "${potbs_dir}/locale" "https://github.com/SnakeSel/PotBS_Russian/raw/master/ru_ru_data.dat"

    rm "${potbs_dir}/locale/ru_ru_data.dir"
    wget -c -nH -q --show-progress -P "${potbs_dir}/locale" "https://github.com/SnakeSel/PotBS_Russian/raw/master/ru_ru_data.dir"

}

apply4gb(){
    echo "${ClMagenta}Apply 4gb patch to PotBS.exe${Clreset}"

    if [ ! -f "${patch4gb}" ];then
        echo_err "4gb patch not found in: ${patch4gb}"
        exit 1
    fi

    if WINEARCH="${WINEARCH}" WINEDEBUG="-all" WINEPREFIX="${potbs_wineprefix}" ${WINE} "${patch4gb}" "${potbs_dir}/PotBS.exe";then
        echo_ok "4gb patch"
    else
        echo_err "4gb patch NOT apply"
        exit 1
    fi

}

installDXVKgit(){
    local repo="doitsujin/dxvk"

    echo "Get release DXVK ..."
    latestTag=$(get_latest_release "$repo")
    echo "Latest version: ${latestTag}"

    echo "Remove old dxvk*"
    rm -R "${data_dir}"/dxvk-*

    taginfo=$(wget --quiet -O - "https://api.github.com/repos/${repo}/releases/tags/${latestTag}")
    debug "$taginfo"
    file_uri=$(echo "$taginfo" | "${jq}" -r '.assets[0].browser_download_url')
    file_name=$(echo "$taginfo" | "${jq}" -r '.assets[0].name')

    echo "Download ${latestTag} to ${data_dir}/${file_name}"
    debug "from ${file_uri}"
    echo ""

    wget -c -nH -q --show-progress -P "${data_dir}" "${file_uri}"

    echo "Extract tar.gz ..."

    if [ ! -s "${data_dir}/${file_name}" ];then
        echo "[ERR] dxvk not found. (${data_dir}/${file_name})"
        read -r -p "Any key to exit"
        #return
        exit 1
    fi

    tar -C "${data_dir}" -xvf "${data_dir}/${file_name}"
    if [ $? -ne 0 ];then
        echo "[ERR] extract ${data_dir}/${file_name}"
        read -r -p "Any key to continue"
        exit 1
    fi

    cd "${data_dir}"/dxvk-*/ || { echo "[err] cd to ${data_dir}/dxvk-*/";exit 1; }
    WINEPREFIX="${potbs_wineprefix}" ./setup_dxvk.sh install --without-dxgi

    echo "Clean tar.gz"
    rm -f "${data_dir}"/"${file_name}"

}

install_dxvk(){
    if type winetricks >/dev/null 2>&1;then
        if ! winetricksInstall "dxvk";then
            echo_err "dxvk NOT installed"
            return 1
        fi
    else
        installDXVKgit
    fi
}

create_desktop(){

cat << EOF > PotBS.desktop
[Desktop Entry]
Type=Application
Name=PotBS
Comment=PotBS Linux Launcher
Exec=${work_dir}/launcher.sh
Icon=${work_dir}/PotBS.png
Terminal=true
EOF

chmod +x PotBS.desktop

}

show_version(){
    getlocalversion
    echo -e "
${ClMagenta}PotBS launcher from SnakeSel${Clreset}
version: ${version}

${ClCyan}PotBS version: ${POTBS_VERSION_INSTALLED}${Clreset}
PotBS game dir: ${potbs_dir}

wine:\t$WINE
pfx:\t${potbs_wineprefix}
arch:\t$WINEARCH
"
}

#####################################################################################
# verify launcher dir and bin
verifying

if [ "${POTBSLEGACY:-0}" -eq 1 ]; then
    echo "${ClMagenta}Legacy client${Clreset}"
    potbs_url="$legacy_url"
fi

#Если параметр 1 не существует, запуск игры
if [ -z "$1" ]
then
    rungame
    exit 0
fi

case "$1" in
    v) show_version;;
    n) createwineprefix;;
    d) fullinstall;;
    u)
        if [ "${testing:-0}" -eq 1 ];then
            POTBS_UPDATE_REQUIRED=1
            echo "test mode"
        else
            checkupdate
        fi
        if [ "${POTBS_UPDATE_REQUIRED}" -eq 1 ]; then
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
        fi
    ;;
    c) checklocalfiles;;
    r) rungame;;
    l) downloadLocale;;
    p) apply4gb;;
    dxvk) install_dxvk;;
    desc) create_desktop;;
    cfg) env WINEARCH="${WINEARCH}" WINEDEBUG="-all" WINEPREFIX="${potbs_wineprefix}" "${WINE}" winecfg;;
    reg) env WINEARCH="${WINEARCH}" WINEDEBUG="-all" WINEPREFIX="${potbs_wineprefix}" "${WINE}" regedit;;
    *) help;;
esac

exit 0
