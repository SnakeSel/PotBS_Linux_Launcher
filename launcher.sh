#!/bin/bash

# полный путь до скрипта
abs_filename=$(readlink -e "$0")
# каталог в котором лежит скрипт
work_dir=$(dirname "$abs_filename")
script_name=${0##*/}

#potbs_dir="$HOME/PotBS"
potbs_dir="${work_dir}"
potbs_url="https://cdn.visiononlinegames.com/potbs/launcher"
buildsversion="${work_dir}/builds"
jq="./jq-linux64"



help(){
    cat << EOF
$script_name [command] <args>
command:
    v  display the currently installed version of the game
    u  check for updates
        -i install update (patch)
        -f install update (full)
    c  check local files for compliance

examples:

Check update and exit:
    $script_name u

Check update and install:
    $script_name u -i

Full install latest version:
    $script_name u -f

Full install version 2.17.7:
    $script_name u -f 2.17.7

EOF
}


# Full dowload potbs $1 version
fullinstall(){
    if [ -z "$1" ];then
        build=$(curl -s "${potbs_url}/Builds/builds_index.json" | ${jq} -r '.["AvailableBuilds"] | .[-1]')
    else
        build=$1
    fi
    echo "install version: ${build}"

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
    lastbuild=$(curl -s "${potbs_url}/Builds/builds_index.json" | ${jq} -r '.["AvailableBuilds"] | .[-1]')
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
    echo "File create: $(date +'%Y-%m-%d %H:%M:%S')" > ${buildsversion}

    # get an array of all versions
    oldIFS=$IFS
    IFS=', ' # разделитель запятая или пробел
    read -r -a allbuilds <<< "$(curl -s "${potbs_url}/Builds/builds_index.json" | ${jq} -r -c '.["AvailableBuilds"]' | sed 's/\[//' | sed 's/]//' | sed 's/"//g')"
    IFS=$oldIFS

    #
    for build in "${allbuilds[@]}"; do
        buildhash=$(curl -s "${potbs_url}/Builds/${build}/version.data")

        echo "${buildhash}" | grep "Not Found" > /dev/null
        if [ $? -eq 0 ];then
            #echo "Version ${build} not found"
            continue
        fi

        if [ "${localhash}" = "${buildhash}" ];then
            result="${build}"
        fi
        echo "$build=${buildhash}" >> ${buildsversion}
    done

    if [ "${result}" != "" ];then
        echo "${result}"
        return
    else
        echo "Not found"
    fi
}


checklocalfiles(){
    echo "in dev"
    return

    if [ -z $1 ];then
        build=$(getlocalversion)
    else
        build=$1
    fi

    # create md5sum check file
    curl -s "${potbs_url}/Builds/build_${build}.json" | ${jq} -r '.["Entries"] | .[] | {"Hash","RelativePath"} | join("  ")' > "md5sum_${build}"

    #md5sum -c "md5sum_${build}"
#    fl=$(md5sum -c "md5sum_${build}" 2>&1)
    #if [ $? -eq 0 ]; then
    #    echo "No corrupted file"
    #else
#        echo "!!! file corrupted"
#        echo "$fl" | grep "ПОВРЕЖ"
#    fi



}
#####################################################################################

#Если параметр 1 не существует, ошибка
if [ -z $1 ]
then
    #echo "Error. Неверные параметры."
    help
    exit 0
fi

case "$1" in
    v)
        getlocalversion
        exit 0
    ;;
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
    c)
        checklocalfiles
    ;;
    *)  help
        exit 0
    ;;
esac

exit 0


