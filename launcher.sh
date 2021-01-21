#!/bin/bash

#### EDIT THIS SETTINGS ####

#potbs_wineprefix="$HOME/.PlayOnLinux/wineprefix/PotBS"
potbs_wineprefix="$HOME/PotBS"
potbs_dir="${potbs_wineprefix}/drive_c/PotBS"

# win64 | win32
WINEARCH=win32

#### NOT EDIT ##############

# полный путь до скрипта
abs_filename=$(readlink -e "$0")
# каталог в котором лежит скрипт
work_dir=$(dirname "$abs_filename")
script_name=${0##*/}

potbs_url="https://cdn.visiononlinegames.com/potbs/launcher"
buildsversion="${work_dir}/builds"
corruptedfiles="${work_dir}/corrupted"
jq="${work_dir}/jq-linux64"
hash="${work_dir}/potbs_hash"

#debug=1

######################################################

help(){
    cat << EOF
$script_name [command] <args>
command:
    r  run game
    v  display the currently installed version of the game
    u  check for updates
        -i install update (patch)
        -f install update (full)
    c  check local files for compliance
    n  create new wineprefix

examples:

Check update and exit:
    $script_name u

Check update and install:
    $script_name u -i

Full install latest version:
    $script_name u -f

EOF
}


# Full dowload potbs $1 version
fullinstall(){
    if [ -z "$1" ];then
        build=$(curl -s "${potbs_url}/Builds/builds_index.json" | "${jq}" -r '.["AvailableBuilds"] | .[-1]')
    else
        build=$1
    fi
    echo "Install PotBS version: ${build}"
    echo "to: ${potbs_dir}"
    #wget -c -r -nH --cut-dirs=4 --no-parent --show-progress -o wget.txt  -P "${potbs_dir}/test" --reject="index.html*" "${potbs_url}/Builds/${build}/"
    wget -c -r -nH --cut-dirs=4 --no-parent --show-progress -P "${potbs_dir}" --reject="index.html*" "${potbs_url}/Builds/${build}/"
    if [ $? -eq 0 ];then
        echo "Game version ${build} installed"
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
    build=$(curl -s "${potbs_url}/Builds/builds_index.json" | "${jq}" -r '.["AvailableBuilds"] | .[-1]')
    localbuild=$(getlocalversion)

    if [ "$debug" ];then
        localbuild="2.17.7"
        echo "[DBG] localbuild=${localbuild}"
    fi

    if [ "$localbuild" == "$build" ];then
        echo "Update not required."
        return
    fi

    echo "Cheking patch ${localbuild} to ${build}"
    patchlist=$(curl -s "${potbs_url}/Patches/${localbuild}_${build}.json")
    echo "${patchlist}" | grep "Not Found" > /dev/null
    if [ $? -eq 0 ];then
        echo "[ERR] Patch ${localbuild}_${build}.json not found"
        exit 1
    fi

    pathDel=$(echo "${patchlist}" | "${jq}" -r '.["Entries"] | .[] | select(.Operation==1) | .RelativePath')
    if [ "$debug" ];then
        echo "[DBG] pathDel:"
        echo "${pathDel}"

    fi

    pathUpdate=$(echo "${patchlist}" | "${jq}" -r '.["Entries"] | .[] | select(.Operation==2) | .RelativePath')
    if [ "$debug" ];then
        echo "[DBG] pathUpdate:"
        echo "$pathUpdate"
    fi

    pathAdd=$(echo "${patchlist}" | "${jq}" -r '.["Entries"] | .[] | select(.Operation==4) | .RelativePath')
    if [ "$debug" ];then
        echo "[DBG] pathAdd:"
        echo "$pathAdd"
    fi

    echo "Apply the patch"

    echo "Remove deleted files..."
    while read -r LINE;do
        if [ "$LINE" == "" ];then
            continue
        fi
        rm "${potbs_dir}/${LINE}"
    done < <(printf '%s\n' "${pathDel}")

    echo "Remove old and download updated files"
    while read -r fullfile;do
        if [ "$fullfile" == "" ];then
            continue
        fi
        filedir=$(dirname "$fullfile")
        rm "${potbs_dir}/${fullfile}"
        wget -c -nH --show-progress -P "${potbs_dir}/${filedir}" "${potbs_url}/Builds/${build}/${fullfile}"
    done < <(printf '%s\n' "$pathUpdate")

    echo "Download added files"
    while read -r fullfile;do
        filedir=$(dirname "$fullfile")
        wget -c -nH --show-progress -P "${potbs_dir}/${filedir}" "${potbs_url}/Builds/${build}/${fullfile}"
    done < <(printf '%s\n' "${pathAdd}")


    echo "patch apply finished"

}

checkupdate(){
    echo "Check update version"
    lastbuild=$(curl -s "${potbs_url}/Builds/builds_index.json" | "${jq}" -r '.["AvailableBuilds"] | .[-1]')
    echo "Last Build: ${lastbuild}"

    currenthash=$(cat "${potbs_dir}/version.data")
    buildhash=$(curl -s "${potbs_url}/Builds/${lastbuild}/version.data")

    if [ "${currenthash}" = "${buildhash}" ];then
        echo "Current version last updated"
        #read -p "Any key to exit"
        exit 0
        #return
    fi

    carrent=$(getlocalversion)
    echo "Local version: ${carrent}"
    #echo "${lastbuild} > ${carrent}" | bc
    echo "Update required"

}

getlocalversion(){
    localhash=$(cat "${potbs_dir}/version.data")
    if [ $? -ne 0 ];then
        echo "[ERR] Not found: ${potbs_dir}/version.data"
        echo "Maybe Game not installed?"
        return
    fi

    #if [ $debug ];then
    #    echo "[DBG] localhash = ${localhash}"
    #fi

    # if version number is in the file $localhash, return it
    if [ -f "${buildsversion}" ];then
        # Убираем пробелы в начале и комментарии:
        raw_param=$(grep "${localhash}" "${buildsversion}" | sed 's/^[ \t]*//' | grep -v "^#" )
        #echo "$raw_param"
        # Берем значение и убираем пробелы в начале и конце
        param=$(echo "${raw_param}" | cut -d"=" -f1 | sed 's/^[ \t]*//' | sed 's/[ \t]*$//')

        if [ "${param}" != "" ];then
            echo "${param}"
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

    if [ $debug ];then
        echo "[DBG] read allbuilds finish"
    fi

    #
    for build in "${allbuilds[@]}"; do
        buildhash=$(curl -s "${potbs_url}/Builds/${build}/version.data")

        echo "${buildhash}" | grep "Not Found" > /dev/null
        if [ $? -eq 0 ];then
            if [ $debug ];then
                echo "[DBG] Version ${build} not found"
            fi
            continue
        fi

        if [ "${localhash}" = "${buildhash}" ];then
            result="${build}"
        fi
        if [ $debug ];then
            echo "[DBG] $build=${buildhash}"
        fi
        echo "$build=${buildhash}" >> "${buildsversion}"
    done

    if [ "${result}" != "" ];then
        echo "${result}"
        return
    else
        echo "Not found"
    fi
}


checklocalfiles(){
    build=$(getlocalversion)

    echo "Checking files started..."

    curl -s "${potbs_url}/Builds/build_${build}.json" | "${jq}" -r '.["Entries"] | .[] | {"Hash","RelativePath"} | join("  ")' > "${work_dir}/hashsum_${build}"

    cd "${potbs_dir}" || exit

    "${hash}" -c "${work_dir}/hashsum_${build}" | grep "FAIL" | tee "${corruptedfiles}"
#    if [ $? -eq 0 ]; then
    if [ ! -s "${corruptedfiles}" ];then
        echo "No corrupted file"
        rm "${corruptedfiles}"
        cd "${work_dir}" || exit
        return
    fi

    cd "${work_dir}" || exit

    while true; do
        read -r -p "Download corrupted file? (y\n):" yn
        case $yn in
            [Yy]* )
                while read -r LINE;do
                    fullfile=$(echo "$LINE" | awk '{ print $2 }')
                    #filename=$(basename "$fullfile")
                    filedir=$(dirname "$fullfile")
                    rm "${potbs_dir}/${fullfile}"
                    wget -c -nH --show-progress -P "${potbs_dir}/${filedir}" "${potbs_url}/Builds/${build}/${fullfile}"
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
    WINEARCH=${WINEARCH} WINEPREFIX="${potbs_wineprefix}" wineboot --init
    if [ $? -ne 0 ];then
        echo "[ERR] Create wineprefix"
        read -r -p "Any key to continue"
        return
    fi

    type winetricks >/dev/null 2>&1 || { echo >&2 "[Warn] No winetricks found.  Aborting."; return; }

    WINEARCH=${WINEARCH} WINEPREFIX="${potbs_wineprefix}" winetricks -q d3dx9 d3dcompiler_43 vcrun2019
    if [ $? -ne 0 ];then
        echo "[ERR] no install d3dx9 d3dcompiler_43 vcrun2019"
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
    lastbuild=$(curl -s "${potbs_url}/Builds/builds_index.json" | "${jq}" -r '.["AvailableBuilds"] | .[-1]')
    currenthash=$(cat "${potbs_dir}/version.data")
    buildhash=$(curl -s "${potbs_url}/Builds/${lastbuild}/version.data")

    if [ "${currenthash}" != "${buildhash}" ];then
        echo "Current version NOT updated"
        read -r -p "Any key to exit"
        return
    fi

    cd "${potbs_dir}" || exit 1
    WINEARCH=${WINEARCH} WINEDEBUG="-all" WINEPREFIX="${potbs_wineprefix}" wine PotBS.exe &


}

downloadLocale(){
    echo "Download Updated RU locale"

    rm "${potbs_dir}/locale/ru_ru_data.dat"
    wget -c -nH --show-progress -P "${potbs_dir}/locale" "https://github.com/SnakeSel/PotBS_Russian/blob/master/ru_ru_data.dat"

    rm "${potbs_dir}/locale/ru_ru_data.dir"
    wget -c -nH --show-progress -P "${potbs_dir}/locale" "https://github.com/SnakeSel/PotBS_Russian/blob/master/ru_ru_data.dir"

}

#####################################################################################

#Если параметр 1 не существует, ошибка
if [ -z "$1" ]
then
    #echo "Error. Неверные параметры."
    help
    exit 0
fi

if [ "$debug" ];then
    echo "[DBG] version 20210117"
fi

case "$1" in
    v) getlocalversion;;
    u)
        # if not args, only check
        if [ -z "$2" ];then
            checkupdate
        else
            while [ -n "$2" ];do
                case "$2" in
                    -i )
                        #checkupdate
                        patchinstall
                        checklocalfiles
                        shift
                    ;;
                    -f )
                        fullinstall "$3"
                        checklocalfiles
                        shift
                    ;;
                    *) echo "not args $2";;
                esac
                shift
            done
        fi
    ;;
    c) checklocalfiles;;
    n) createwineprefix;;
    r) rungame;;
    l) downloadLocale;;
    *) help;;
esac

exit 0


