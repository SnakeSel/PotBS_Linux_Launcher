#!/bin/bash

POTBS_URL="https://cdn.visiononlinegames.com/potbs/launcher"
LEGACY_URL="https://cdn.visiononlinegames.com/potbs/legacy/launcher"

BUILDSHASHFILE="${CACHE_DIR}/builds"
CORRUPTEDFILES="${CACHE_DIR}/corrupted"

#POTBS_VERSION_INSTALLED=0

# determine server game version
potbs_getServerVersion(){
    if [ "${POTBSLEGACY:-0}" -eq 1 ]; then
        POTBS_URL="$LEGACY_URL"
    fi

    local _version
    _version=$(wget --quiet -O - "${POTBS_URL}/Builds/builds_index.json" | "${jq}" -r '.["AvailableBuilds"] | .[-1]')
    if [ -n "$_version" ];then
        echo "$_version"
        return 0
    else
        echo "failed to get server version"
        return 1
    fi
}


# Create builds hash file
# $1 - builds hash file
potbs_createBuildsHash(){
    if [ "${POTBSLEGACY:-0}" -eq 1 ]; then
        POTBS_URL="$LEGACY_URL"
    fi

    local _file
    local allbuilds
    local oldIFS
    local buildhash

    _file="$1"

    # get an array of all versions
    oldIFS=$IFS
    IFS=', ' # разделитель запятая или пробел
    read -r -a allbuilds <<< "$(wget --quiet -O - "${POTBS_URL}/Builds/builds_index.json" | "${jq}" -r -c '.["AvailableBuilds"]' | sed 's/\[//' | sed 's/]//' | sed 's/"//g')"
    IFS=$oldIFS	

    if [ -z "$allbuilds" ];then
        echo "NOT get AvailableBuilds from ${POTBS_URL}/Builds/builds_index.json"
        return 1
    fi

    echo "File create: $(date +'%Y-%m-%d %H:%M:%S')" > "${_file}"

    for build in "${allbuilds[@]}"; do
        buildhash=$(wget --quiet -O - "${POTBS_URL}/Builds/${build}/version.data")

        echo "${buildhash}" | grep "Not Found" > /dev/null
        if [ $? -eq 0 ];then
            echo "Version ${build} not found" >&2
            continue
        fi

        echo "$build=${buildhash}" >> "${_file}"
    done
}

# determine installed game version
# $1 - Game dir
potbs_getlocalversion(){
    readVersion(){
        local raw_param
        # Убираем пробелы в начале и комментарии:
        raw_param=$(grep "${localHash}" "${BUILDSHASHFILE}" | sed 's/^[ \t]*//' | grep -v "^#" )
        # Берем значение и убираем пробелы в начале и конце
        echo "${raw_param}" | cut -d"=" -f1 | sed 's/^[ \t]*//' | sed 's/[ \t]*$//'
    }

    local potbsDir
    local localHash
    local _version

    potbsDir="$1"

    if ! [ -f "${potbsDir}/version.data" ];then
        echo "Game files NOT found!"
        return 1
    fi

    if ! localHash=$(cat "${potbsDir}/version.data");then
        echo "Not read ${potbsDir}/version.data"
        return 1
    fi


    # create Builds file
    if ! [ -f "${BUILDSHASHFILE}" ];then
        if ! createBuildsHash "${BUILDSHASHFILE}";then
            echo "createBuildsHash ${BUILDSHASHFILE}"
            return 1
        fi
    fi

    _version=$(readVersion)
    # if installed version found, exit function
    if [ "${_version}" != "" ];then
        echo "${_version}"
        return 0
    fi

    echo "Builds file does not contain version" >&2
    echo "recreate Builds file" >&2

    if ! createBuildsHash "${BUILDSHASHFILE}";then
        echo "createBuildsHash ${BUILDSHASHFILE}"
        return 1
    fi

    _version=$(readVersion)
    if [ "${_version}" != "" ];then
        echo "${_version}"
        return 0
    else
        echo "Installed Game version unspecified"
        return 1
    fi

    return 1
}

# Full dowload potbs
# $1 - game dir
# $2 - game version
potbs_downloadGame(){
    if [ -z "$1" ];then
        echo "param 1: Game dir not set"
        return 1
    fi
    if [ -z "$2" ];then
        echo "param 2: Game version not set"
        return 1
    fi

    local gameDir
    local gameVersion
    local _cutdirs

    gameDir="$1"
    gameVersion="$2"
    _cutdirs=4

    if [ "${POTBSLEGACY:-0}" -eq 1 ]; then
        _cutdirs=5
        POTBS_URL="$LEGACY_URL"
    fi

    #echo "Install PotBS ${POTBS_VERSION_SERVER}"
    #echo "to: ${potbs_dir}"
    if wget -c -r -nH --cut-dirs=${_cutdirs} --no-parent -q --show-progress -P "${gameDir}" --reject="index.html*" "${POTBS_URL}/Builds/${gameVersion}/";then
        return 0
    else
        return 1
    fi

}

# $1 - game dir
# return 0 - no corrupted
# return 1 corrupted files. list in ${CORRUPTEDFILES}
potbs_checkLocalFiles(){
    if [ -z "$1" ];then
        echo "param 1: Game dir not set"
        return 1
    fi

    if [ "${POTBSLEGACY:-0}" -eq 1 ]; then
        POTBS_URL="$LEGACY_URL"
    fi

    local gameDir
    local gameVersion
    local hashFile
    local _dir

    gameDir="$1"
    if ! gameVersion=$(potbs_getlocalversion "$gameDir");then
        return 1
    fi

    hashFile="${CACHE_DIR}/hashsum_${gameVersion}"

    if ! [ -f "$hashFile" ];then
        if ! wget --quiet -O - "${POTBS_URL}/Builds/build_${gameVersion}.json" | "${jq}" -r '.["Entries"] | .[] | {"Hash","RelativePath"} | join("  ")' > "${hashFile}";then
            echo "Not download hash file"
            return 1
        fi

        # TMP FIX DUBLICAT FILE ENTRIE
        local _tmphash
        _tmphash="${hashFile}_tmp"
        mv "${hashFile}" "${_tmphash}"
        # copy unique entrie
        sort -k2 "${_tmphash}" | uniq -u --skip-fields=1 > "${hashFile}"
        # copy last non uniq entrie
        sort -k2 "${_tmphash}" | uniq -d --skip-fields=1 >> "${hashFile}"
        rm -f "${_tmphash}"
        # /END TMP
    fi

    _dir=$(pwd)
    cd "${gameDir}" || exit

    "${hash}" -c "${hashFile}" | grep "FAIL" | tee "${CORRUPTEDFILES}"
    #"${hash}" -c "${hashFile}" | grep "FAIL" > "${CORRUPTEDFILES}"
    if [ ! -s "${CORRUPTEDFILES}" ];then
        #echo "No corrupted file. "
        rm -f "${CORRUPTEDFILES}"
        cd "${_dir}" || exit
        return 0
    fi

    cd "${_dir}" || exit

    return 1

}

# Download files from corrupted list
# $1 - game dir
potbs_downloadCorruptedFiles(){
    if [ -z "$1" ];then
        echo "param 1: Game dir not set"
        return 1
    fi

    if [ "${POTBSLEGACY:-0}" -eq 1 ]; then
        POTBS_URL="$LEGACY_URL"
    fi

    local gameDir
    local gameVersion

    gameDir="$1"
    if ! gameVersion=$(potbs_getlocalversion "$gameDir");then
        return 1
    fi

    local totalLines
    local i=0
    totalLines=$(wc -l < "${CORRUPTEDFILES}")
    while read -r LINE;do
        fullfile=$(echo "$LINE" | awk '{ print $2 }')

        if [ "${GUI:-0}" -eq 1 ];then echo "$(($i*100/${totalLines}))";echo "# Download: $fullfile";fi

        #filename=$(basename "$fullfile")
        filedir=$(dirname "$fullfile")
        rm -f "${gameDir}/${fullfile}"
        if ! wget -c -nH -q --show-progress -P "${gameDir}/${filedir}" "${POTBS_URL}/Builds/${gameVersion}/${fullfile}";then
            echo "Not download $fullfile"
            return 1
        fi
        ((++i))
    done < "${CORRUPTEDFILES}"

    rm -f "${CORRUPTEDFILES}"

    if [ "${GUI:-0}" -eq 1 ];then echo "100";echo "# All files downloaded";fi

    return 0
}

# $1 - game dir
potsb_downloadLocale(){
    if [ -z "$1" ];then
        echo "param 1: Game dir not set"
        return 1
    fi
    local gameDir
    gameDir="$1"

    rm -f "${gameDir}/locale/ru_ru_data.dat"
    if [ "${GUI:-0}" -eq 1 ];then echo "10";echo "# Download: ru_ru_data.dat";fi
    wget -c -nH -q --show-progress -P "${gameDir}/locale" "https://github.com/SnakeSel/PotBS_Russian/raw/master/ru_ru_data.dat"

    rm -f "${gameDir}/locale/ru_ru_data.dir"
    if [ "${GUI:-0}" -eq 1 ];then echo "50";echo "# Download: ru_ru_data.dir";fi
    wget -c -nH -q --show-progress -P "${gameDir}/locale" "https://github.com/SnakeSel/PotBS_Russian/raw/master/ru_ru_data.dir"

    if [ "${GUI:-0}" -eq 1 ];then echo "100";echo "# All files downloaded";fi
}


# since applying patches requires a separate application, then
# read the modified files and download them entirely
# $1 - game dir
# $2 - update to version
# Return 0 - patches installed
# return 1 - error
# return 200 - Not found update patch
potbs_patchesInstall(){
    #$1 - name patch
    #$2 - patch to version
    installPatch(){
        if [ -z "$1" ];then
            echo "param 1: name patch arhive not set"
            return 1
        fi
        local patchName
        local patchlist

        patchName="$1"
        patchlist=$(wget --quiet -O - "${POTBS_URL}/Patches/${patchName}.json")
        echo "${patchlist}" | grep "Not Found" > /dev/null
        if [ $? -eq 0 ];then
            echo "[ERR] Patch ${patchName}.json not found"
            return 1
        fi

        # Patch Operation:
        # 0 = no change
        # 1 = deleted
        # 2 = updated
        # 3 = changed attributes
        # 4 = added

        local pathDel
        local pathUpdate
        local pathAdd

        pathDel=$(echo "${patchlist}" | "${jq}" -r '.["Entries"] | .[] | select(.Operation==1) | .RelativePath')
        debug "pathDel: ${pathDel}"

        pathUpdate=$(echo "${patchlist}" | "${jq}" -r '.["Entries"] | .[] | select(.Operation==2) | .RelativePath')
        debug "pathUpdate: $pathUpdate"

        pathAdd=$(echo "${patchlist}" | "${jq}" -r '.["Entries"] | .[] | select(.Operation==4) | .RelativePath')
        debug "pathAdd: $pathAdd"

        # echo '''

        echo "Apply the patch ..."

        echo "Remove deleted files..."
        while read -r LINE;do
            if [ "$LINE" == "" ];then
                continue
            fi
            rm -f "${gameDir}/${LINE}"
        done < <(printf '%s\n' "${pathDel}")

            echo "Remove old and download updated files"
            while read -r fullfile;do
                if [ "$fullfile" == "" ];then
                    continue
                fi
                filedir=$(dirname "$fullfile")
                rm -f "${gameDir}/${fullfile}"
                wget -c -nH -q --show-progress -P "${gameDir}/${filedir}" "${POTBS_URL}/Builds/${patchTo}/${fullfile}"
            done < <(printf '%s\n' "$pathUpdate")

            echo "Download added files"
            while read -r fullfile;do
                filedir=$(dirname "$fullfile")
                wget -c -nH -q --show-progress -P "${gameDir}/${filedir}" "${POTBS_URL}/Builds/${patchTo}/${fullfile}"
            done < <(printf '%s\n' "${pathAdd}")

    }

    if [ -z "$1" ];then
        echo "param 1: Game dir not set"
        return 1
    fi
    local gameDir
    gameDir="$1"

    if [ "${POTBSLEGACY:-0}" -eq 1 ]; then
        POTBS_URL="$LEGACY_URL"
    fi

    if [ -n "${2}" ];then
        echo "Manual select update to ${2}"
        POTBS_VERSION_SERVER="${2}"
    else
        if ! POTBS_VERSION_SERVER=$(potbs_getServerVersion);then
            echo "Not load server version"
            return 1
        fi
    fi

    if ! POTBS_VERSION_INSTALLED=$(potbs_getlocalversion "$gameDir");then
        echo "Not load game version"
        return 1
    fi


    if [ "${POTBS_VERSION_INSTALLED}" == "${POTBS_VERSION_SERVER}" ];then
        echo "Update not required."
        return 0
    fi

    echo "Cheking patches ${POTBS_VERSION_INSTALLED} to ${POTBS_VERSION_SERVER} ..."
    patchesindex=$(wget --quiet -O - "${POTBS_URL}/Patches/patches_index.json")
    echo "${patchesindex}" | grep "Not Found" > /dev/null
    if [ $? -eq 0 ];then
        echo "[ERR] patches_index.json not found"
        return 1
    fi

    # before we install all the patches.
    while [ "${POTBS_VERSION_INSTALLED}" != "${POTBS_VERSION_SERVER}" ];do
        if [ -n "${2}" ];then
            echo "Manual select update to ${2}"
            patchTo="${2}"
        else
            patchTo=$(echo "${patchesindex}" | "${jq}" -r --arg POTBS_VERSION_INSTALLED "${POTBS_VERSION_INSTALLED}" '.["Patches"] | .[] | select(.From==$POTBS_VERSION_INSTALLED) |.To' 2> /dev/null)
        fi
        # echo '''


        #echo "patchTo: ${patchTo}"
        if [ -z "${patchTo}" ];then
            # Если не нашли патча, а текущая версия предпоследняя, то можем сами подставить версию
            # ситуация когда Vision сломали patches_index.json
            prerel=$(wget --quiet -O - "${POTBS_URL}/Builds/builds_index.json" | "${jq}" -r '.["AvailableBuilds"] | .[-2]')
            if [ "${prerel}" == "${POTBS_VERSION_INSTALLED}" ];then
                patchTo="${POTBS_VERSION_SERVER}"
            else
                echo "[ERR] Not found update patch from ${POTBS_VERSION_INSTALLED} in patches_index.json"
                echo "If you are sure that the patch from version ${POTBS_VERSION_INSTALLED} exists, start the launcher specifying which patch you need to install:"
                echo "$script_name u <pathTO>"
                return 200
            fi
        fi

        echo ""
        echo "patch from ${POTBS_VERSION_INSTALLED} to ${patchTo}"

        patchName="${POTBS_VERSION_INSTALLED}_${patchTo}"
        #debug "patchName: ${patchName}"

        if ! installPatch "$patchName";then
            echo "Can not install $patchName"
            return 1
        fi
        #echo ""
        POTBS_VERSION_INSTALLED=${patchTo}

    done
}
