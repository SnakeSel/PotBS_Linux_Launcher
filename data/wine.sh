#!/bin/bash

#if ! source ./util.sh;then
#    echo "Not load ./util.sh"
#    exit 1
#fi

winetricksInstall(){
    if ! type winetricks >/dev/null 2>&1;then
        echo_err "No winetricks found. Aborting."
        return 1
    fi

    echo_debug "WINEARCH=\"${WINEARCH}\" WINEPREFIX=\"${WINEPREFIX}\" WINE=\"${WINE}\" winetricks -q -f $1"
    env WINEARCH="${WINEARCH}" WINEDEBUG="-all" WINEPREFIX="${WINEPREFIX}" WINE="${WINE}" winetricks -q -f "$1"
}

installDXVKgit(){
    local repo="doitsujin/dxvk"

    echo "Get release DXVK ..."
    local latestTag=$(get_latest_release "$repo")
    echo "Latest version: ${latestTag}"

    echo "Remove old dxvk*"
    rm -R "${CACHE_DIR}"/dxvk-*

    local taginfo=$(wget --quiet -O - "https://api.github.com/repos/${repo}/releases/tags/${latestTag}")
    echo_debug "$taginfo"
    local file_uri=$(echo "$taginfo" | "${jq}" -r '.assets[0].browser_download_url')
    local file_name=$(echo "$taginfo" | "${jq}" -r '.assets[0].name')

    echo "Download ${latestTag} to ${data_dir}/${file_name}"
    echo_debug "from ${file_uri}"
    echo ""

    if ! wget -c -nH -q --show-progress -P "${CACHE_DIR}" "${file_uri}";then
        echo_err "Not load ${file_uri}"
    fi

    echo "Extract tar.gz ..."

    if [ ! -s "${CACHE_DIR}/${file_name}" ];then
        echo "[ERR] dxvk not found. (${CACHE_DIR}/${file_name})"
        read -r -p "Any key to exit"
        #return
        exit 1
    fi

    tar -C "${CACHE_DIR}" -xvf "${CACHE_DIR}/${file_name}"
    if [ $? -ne 0 ];then
        echo "[ERR] extract ${CACHE_DIR}/${file_name}"
        read -r -p "Any key to continue"
        exit 1
    fi

    cd "${CACHE_DIR}"/dxvk-*/ || { echo "[err] cd to ${CACHE_DIR}/dxvk-*/";exit 1; }
    WINEPREFIX="${WINEPREFIX}" ./setup_dxvk.sh install --without-dxgi

    echo "Clean tar.gz"
    rm -f "${CACHE_DIR}"/"${file_name}"

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

installWineDependence(){
    cont(){
        echo ""
        while true; do
        read -r -p "Continue install? (y\n):" yn
        case $yn in
            [Yy]* )
                break;;
            [Nn]* )
                exit 1;;
            * ) echo "Please answer yes or no.";;
        esac
        done
    }

    local dependence=(d3dx9 d3dcompiler_43 vcrun2019 "${DATA_DIR}/PhysxLegacy.verb")

    local totalDep=${#dependence[*]}
    local i=0
    for dep in "${dependence[@]}"; do
        if [ "${GUI:-0}" -eq 1 ];then echo "$(($i*100/${totalDep}))";echo "# Install: $dep";fi
        if ! winetricksInstall "$dep";then
            echo_err "$dep NOT installed"
            cont
        fi
        ((++i))
    done

    if [ "${GUI:-0}" -eq 1 ];then echo "100";echo "# All dependence installed";fi

    return 0
}

initWinePrefix(){
    if ! [ -d "${WINEPREFIX}" ]; then
        mkdir -p "${WINEPREFIX}"
    fi

    #WINEARCH="${WINEARCH}" WINEPREFIX="${potbs_wineprefix}" wineboot --init
    if ! env WINEARCH="${WINEARCH}" WINEDEBUG="-all" WINEPREFIX="${WINEPREFIX}" "${WINE}" wineboot -u;then
        echo_err "Create wineprefix"
        return 1
    fi

    return 0
}
