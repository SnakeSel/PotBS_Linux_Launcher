#!/bin/bash

# PotBS Linux Launcher
# Script to simplify wine environment creation, download, run game and check\install updates.
#
# Author: SnakeSel
# git: https://github.com/SnakeSel/PotBS_Linux_Launcher

version=20210420

#### EDIT THIS SETTINGS ####

potbs_wineprefix="$HOME/.PlayOnLinux/wineprefix/PotBS"
#potbs_wineprefix="$HOME/PotBS"
potbs_dir="${potbs_wineprefix}/drive_c/PotBS"

# win64 | win32
WINEARCH=win32

debugging=0

#### NOT EDIT ##############
script_name=${0##*/}
# полный путь до скрипта
abs_filename=$(readlink -e "$0")
# каталог в котором лежит скрипт
work_dir=$(dirname "$abs_filename")
bin_dir="${work_dir}/bin"
data_dir="${work_dir}/data"

potbs_url="https://cdn.visiononlinegames.com/potbs/launcher"

buildsversion="${data_dir}/builds"
corruptedfiles="${data_dir}/corrupted"

jq="${bin_dir}/jq-linux64"
hash="${bin_dir}/potbs_hash"
patch4gb="${bin_dir}/4gb_patch.exe"


POTBS_VERSION_INSTALLED=""
POTBS_VERSION_SERVER=""
POTBS_UPDATE_REQUIRED=0
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

# Full dowload potbs
fullinstall(){
    getServerVersion

    echo "Install PotBS ${POTBS_VERSION_SERVER}"
    echo "to: ${potbs_dir}"
    #wget -c -r -nH --cut-dirs=4 --no-parent --show-progress -o wget.txt  -P "${potbs_dir}/test" --reject="index.html*" "${potbs_url}/Builds/${build}/"
    wget -c -r -nH --cut-dirs=4 --no-parent --show-progress -P "${potbs_dir}" --reject="index.html*" "${potbs_url}/Builds/${POTBS_VERSION_SERVER}/"
    if [ $? -eq 0 ];then
        echo "Game version ${POTBS_VERSION_SERVER} installed"
    else
        echo "Error download"
    fi

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
    getServerVersion
    getlocalversion

    if [ "$debugging" ];then
        POTBS_VERSION_INSTALLED="2.17.7"
    fi

    if [ "${POTBS_VERSION_INSTALLED}" == "${POTBS_VERSION_SERVER}" ];then
        echo "Update not required."
        return
    fi

    echo "Cheking patch ${POTBS_VERSION_INSTALLED} to ${POTBS_VERSION_SERVER}"
    patchlist=$(curl -s "${potbs_url}/Patches/${POTBS_VERSION_INSTALLED}_${POTBS_VERSION_SERVER}.json")
    echo "${patchlist}" | grep "Not Found" > /dev/null
    if [ $? -eq 0 ];then
        echo "[ERR] Patch ${POTBS_VERSION_INSTALLED}_${POTBS_VERSION_SERVER}.json not found"
        exit 1
    fi

    pathDel=$(echo "${patchlist}" | "${jq}" -r '.["Entries"] | .[] | select(.Operation==1) | .RelativePath')
    debug "pathDel: ${pathDel}"

    pathUpdate=$(echo "${patchlist}" | "${jq}" -r '.["Entries"] | .[] | select(.Operation==2) | .RelativePath')
    debug "pathUpdate: $pathUpdate"

    pathAdd=$(echo "${patchlist}" | "${jq}" -r '.["Entries"] | .[] | select(.Operation==4) | .RelativePath')
    debug "pathAdd: $pathAdd"

    echo "Apply the patch"

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
        wget -c -nH -P "${potbs_dir}/${filedir}" "${potbs_url}/Builds/${POTBS_VERSION_SERVER}/${fullfile}"
    done < <(printf '%s\n' "$pathUpdate")

    echo "Download added files"
    while read -r fullfile;do
        filedir=$(dirname "$fullfile")
        wget -c -nH -P "${potbs_dir}/${filedir}" "${potbs_url}/Builds/${POTBS_VERSION_SERVER}/${fullfile}"
    done < <(printf '%s\n' "${pathAdd}")

    echo "patch apply finished"
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
    buildhash=$(curl -s "${potbs_url}/Builds/${POTBS_VERSION_SERVER}/version.data")

    if [ "${currenthash}" = "${buildhash}" ];then
        echo "Current version last updated"
        POTBS_UPDATE_REQUIRED=0
        return
    fi

    getlocalversion
    echo "Installed version: ${POTBS_VERSION_INSTALLED}"
    echo "Update required"
    POTBS_UPDATE_REQUIRED=1

}

# determine server game version
# and write it to POTBS_VERSION_SERVER
getServerVersion(){
    POTBS_VERSION_SERVER=$(curl -s "${potbs_url}/Builds/builds_index.json" | "${jq}" -r '.["AvailableBuilds"] | .[-1]')
}

# determine installed game version
# and write it to POTBS_VERSION_INSTALLED
getlocalversion(){
    # get version hash installed game
    localhash=$(cat "${potbs_dir}/version.data")
    if [ $? -ne 0 ];then
        echo "[ERR] Not found: ${potbs_dir}/version.data"
        echo "Maybe Game not installed?"
        return
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
            return
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
    read -r -a allbuilds <<< "$(curl -s "${potbs_url}/Builds/builds_index.json" | "${jq}" -r -c '.["AvailableBuilds"]' | sed 's/\[//' | sed 's/]//' | sed 's/"//g')"
    IFS=$oldIFS

    debug "read allbuilds finish"

    for build in "${allbuilds[@]}"; do
        buildhash=$(curl -s "${potbs_url}/Builds/${build}/version.data")

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
        POTBS_VERSION_INSTALLED=${param}
        debug "POTBS_VERSION_INSTALLED=${param}"
        #echo "${result}"
        return
    else
        echo "[ERR] Installed Game verison unspecified"
    fi
}


checklocalfiles(){
    getlocalversion
    hashFile="${data_dir}/hashsum_${POTBS_VERSION_INSTALLED}"

    echo "Checking files started..."

    curl -s "${potbs_url}/Builds/build_${POTBS_VERSION_INSTALLED}.json" | "${jq}" -r '.["Entries"] | .[] | {"Hash","RelativePath"} | join("  ")' > "${hashFile}"

    cd "${potbs_dir}" || exit

    "${hash}" -c "${hashFile}" | grep "FAIL" | tee "${corruptedfiles}"
    if [ ! -s "${corruptedfiles}" ];then
        echo "No corrupted file"
        rm "${corruptedfiles}"
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
                    wget -c -nH -P "${potbs_dir}/${filedir}" "${potbs_url}/Builds/${POTBS_VERSION_INSTALLED}/${fullfile}"
                done < "${corruptedfiles}"

                break;;
            [Nn]* ) break;;
            * ) echo "Please answer yes or no.";;
        esac
    done

}


createwineprefix(){

    type wine >/dev/null 2>&1 || { echo >&2 "[Warn] No wine found.  Aborting."; return; }

    winever=$(wine --version)
    if [ $? -ne 0 ];then
        echo "[ERR] Wine not found"
        read -r -p "Any key to continue"
        return
    fi

    echo "Create new wineprefix..."
    echo "${winever}, WINEARCH=${WINEARCH}"
    echo ""
    echo "Enter patch to wineprefix or empty to default"
    read -e -r -p "(default patch: ${potbs_wineprefix}) :"  ptch
    if [ "${ptch}" != "" ];then
        potbs_wineprefix=${ptch}
    fi
    echo "Init wine to ${potbs_wineprefix}"

    #WINEARCH=win32 WINEPREFIX="${potbs_wineprefix}" winecfg
    WINEARCH="${WINEARCH}" WINEPREFIX="${potbs_wineprefix}" wineboot --init
    if [ $? -ne 0 ];then
        echo "[ERR] Create wineprefix"
        read -r -p "Any key to continue"
        return
    fi

    type winetricks >/dev/null 2>&1 || { echo >&2 "[Warn] No winetricks found.  Aborting."; return; }

    WINEARCH=${WINEARCH} WINEPREFIX="${potbs_wineprefix}" winetricks -q d3dx9 d3dcompiler_43 vcrun2019
    if [ $? -ne 0 ];then
        echo "[ERR] no install d3dx9 d3dcompiler_43"
        read -r -p "Any key to continue"
        return
    fi

    WINEARCH=${WINEARCH} WINEPREFIX="${potbs_wineprefix}" winetricks -q vcrun2019
    if [ $? -ne 0 ];then
        echo "[ERR] no install vcrun2019"
        read -r -p "Any key to continue"
        return
    fi

    WINEARCH=${WINEARCH} WINEPREFIX="${potbs_wineprefix}" winetricks -q "${work_dir}"/PhysxLegacy.verb
    if [ $? -ne 0 ];then
        echo "[ERR] no install PhysX"
        read -r -p "Any key to continue"
        return
    fi

    echo "Wineprefix create success!"
    echo ""
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

    #read -p "Any key to continue"
    return

}

rungame(){
    checkupdate
    if [ "${POTBS_UPDATE_REQUIRED}" -eq 1 ]; then
        echo "[ERR] Current version NOT updated"
        read -r -p "Any key to exit"
        #return
        exit 1
    fi

    cd "${potbs_dir}" || exit 1
    WINEARCH="${WINEARCH}" WINEDEBUG="-all" WINEPREFIX="${potbs_wineprefix}" wine PotBS.exe &

}

downloadLocale(){
    echo "Download Updated RU locale"

    rm "${potbs_dir}/locale/ru_ru_data.dat"
    wget -c -nH -P "${potbs_dir}/locale" "https://github.com/SnakeSel/PotBS_Russian/raw/master/ru_ru_data.dat"

    rm "${potbs_dir}/locale/ru_ru_data.dir"
    wget -c -nH -P "${potbs_dir}/locale" "https://github.com/SnakeSel/PotBS_Russian/raw/master/ru_ru_data.dir"

}

apply4gb(){
    echo "apply 4gb patch to PotBS.exe"

    WINEARCH="${WINEARCH}" WINEDEBUG="-all" WINEPREFIX="${potbs_wineprefix}" wine "${patch4gb}" "${potbs_dir}/PotBS.exe"


}
#####################################################################################
# verify launcher dir and bin
verifying

#Если параметр 1 не существует, ошибка
if [ -z "$1" ]
then
    #echo "Error. Неверные параметры."
    #help
    rungame
    exit 0
fi

case "$1" in
    v)
        getlocalversion
        if [ "${POTBS_VERSION_INSTALLED}" == "" ];then
            echo "[ERR] Installed Game verison unspecified"
            exit 1
        fi
        echo "PotBS Installed: ${POTBS_VERSION_INSTALLED}"
        echo "Launcher: ${version}"
    ;;
    n) createwineprefix;;
    d)
        fullinstall
        checklocalfiles
    ;;
    u)
        checkupdate
        if [ "${POTBS_UPDATE_REQUIRED}" -eq 1 ]; then
            echo ""
            while true; do
            read -r -p "Install update? (y\n):" yn
            case $yn in
                [Yy]* )
                    patchinstall
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
    *) help;;
esac

exit 0
