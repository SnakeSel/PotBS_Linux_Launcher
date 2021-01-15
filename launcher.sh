#!/bin/bash

#### EDIT THIS SETTINGS ####

potbs_wineprefix="$HOME/.PlayOnLinux/wineprefix/PotBS"
#potbs_wineprefix="$HOME/PotBS"
potbs_dir="${potbs_wineprefix}/drive_c/PotBS"


#### NOT EDIT ##############

# полный путь до скрипта
abs_filename=$(readlink -e "$0")
# каталог в котором лежит скрипт
work_dir=$(dirname "$abs_filename")
script_name=${0##*/}

potbs_url="https://cdn.visiononlinegames.com/potbs/launcher"
buildsversion="${work_dir}/builds"
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

patchinstall(){
    echo "in dev"
}

checkupdate(){
    echo "Check update version"
    lastbuild=$(curl -s "${potbs_url}/Builds/builds_index.json" | "${jq}" -r '.["AvailableBuilds"] | .[-1]')
    echo "Last Build: ${lastbuild}"

    currenthash=$(cat "${potbs_dir}/version.data")
    buildhash=$(curl -s "${potbs_url}/Builds/${lastbuild}/version.data")

#for test
#currenthash=="12313"
    if [ "${currenthash}" = "${buildhash}" ];then
        echo "Current version last updated"
        #read -p "Any key to exit"
        #exit 0
        return
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

    if [ $debug ];then
        echo "[DBG] localhash = ${localhash}"
    fi


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
    #if [ -z $1 ];then
    #else
    #fi

    # create md5sum check file
    curl -s "${potbs_url}/Builds/build_${build}.json" | "${jq}" -r '.["Entries"] | .[] | {"Hash","RelativePath"} | join("  ")' > "${work_dir}/hashsum_${build}"

    cd "${potbs_dir}" || exit
    "${hash}" -c "${work_dir}/hashsum_${build}" | grep "FAIL" | tee "${work_dir}/failfile"

#    fl=$(md5sum -c "md5sum_${build}" 2>&1)
    #if [ $? -eq 0 ]; then
    #    echo "No corrupted file"
    #else
#        echo "!!! file corrupted"
#        echo "$fl" | grep "ПОВРЕЖ"
#    fi

    cd "${work_dir}" || exit


    #wget -c -nH --show-progress -P "${potbs_dir}" "${potbs_url}/Builds/${build}/"
}


createwineprefix(){
    winever=$(wine --version)
    if [ $? -ne 0 ];then
        echo "[ERR] Wine not found"
        read -p "Any key to continue"
        return
    fi

    echo "Create new wineprefix ${winever}"
    echo "Enter patch to wineprefix or empty to default"
    read -p "(default patch: ${potbs_wineprefix}) :" ptch
    if [ "${ptch}" != "" ];then
        potbs_wineprefix=${ptch}
    fi

    echo "Init wine to ${potbs_wineprefix}"

    #WINEARCH=win32 WINEPREFIX="${potbs_wineprefix}" winecfg
    WINEARCH=win32 WINEPREFIX="${potbs_wineprefix}" wineboot --init
    if [ $? -ne 0 ];then
        echo "[ERR] Create wineprefix"
        read -p "Any key to continue"
        return
    fi

    winetriksver=$(winetricks -V | cut -d' ' -f1)
    if [ $? -ne 0 ];then
        echo "[Warn] No winetrics found"
        echo "Manual install d3dx9 d3dcompiler_43 vcrun2019 PhysX"
        read -p "Any key to continue"
        return
    fi

    WINEPREFIX="${potbs_wineprefix}" winetricks -q d3dx9 d3dcompiler_43 vcrun2019
    if [ $? -ne 0 ];then
        echo "[ERR] no install d3dx9 d3dcompiler_43 vcrun2019"
        read -p "Any key to continue"
        return
    fi

    WINEPREFIX="${potbs_wineprefix}" winetricks -q ${work_dir}/PhysxLegacy.verb
    if [ $? -ne 0 ];then
        echo "[ERR] no install PhysX"
        read -p "Any key to continue"
        return
    fi

    echo "Wineprefix create success!"
    echo ""
    while true; do
        read -p "Download Full Game?" yn
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
        read -p "Any key to exit"
        return
    fi

    cd "${potbs_dir}"
    WINEPREFIX="${potbs_wineprefix}" wine PotBS.exe &


}
#####################################################################################

#Если параметр 1 не существует, ошибка
if [ -z $1 ]
then
    #echo "Error. Неверные параметры."
    help
    exit 0
fi

if [ $debug ];then
    echo "[DBG] version 20210115"
fi

case "$1" in
    v) getlocalversion;;
    u)
        # if not args, only check
        if [ -z $2 ];then
            checkupdate
        else
            while [ -n "$2" ];do
                case "$2" in
                    -i )
                        patchinstall "$3"
                        shift
                    ;;
                    -f )
                        fullinstall "$3"
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
    *) help;;
esac

exit 0


