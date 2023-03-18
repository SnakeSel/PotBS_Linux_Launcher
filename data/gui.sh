#!/bin/sh

GUI=1

uiTitle="PotBS Linux Launcher"
uiIcon="${DATA_DIR}/PotBS.png"


ui_err(){
    zenity --error --title="${uiTitle}" --window-icon="${uiIcon}" --width "400" --text="$*"
}


memoryErrUI(){

    if echo "ERROR Memory: memory allocation failed for pool Main.Default

Add or replace params in file \"pirates_local.ini\":
[MemoryPools]
;; size in MB
preSize_Bootstrap=2
preSize_Default=256
preSize_Image=486
preSize_Vertex=128
preSize_Audio=64
preSize_Room=486
preSize_UI=64
preSize_Anim=486" | zenity --text-info  --title="${uiTitle}" --window-icon="${uiIcon}" \
        --ok-label="Dont show again" --cancel-label="OK" \
        --width "450" --height "400"
    then
        cfg_save_param "${CONFIG}" "SHOWMEMERRINFO" "0"
    fi

}

updateUI(){

    if ! potbs_patchesInstall "${POTBS_DIR}" | zenity --progress --title="${uiTitle}" --window-icon="${uiIcon}" --width "400" --auto-kill
    then
        case "$?" in
            200) ui_err "Not found update patch";;
            *) ui_err "Pathes not installed";;
        esac
        return 1
    fi

    verifyUI
}

changeVersionUI(){
    local ans
    if ! ans=$(zenity --list --title="${uiTitle}" --window-icon="${uiIcon}" \
            --width "400" --height "200" \
            --text="Select game version:" \
            --radiolist \
            --column="" --column="Game version" \
            1 "Live" \
            2 "Legacy" \
        )
    then
        return
    fi

    case $ans in
            "Live") POTBSLEGACY=0;;
            "Legacy") POTBSLEGACY=1;;
            *) echo "$ans";;
    esac

    cfg_save_param "${CONFIG}" "POTBSLEGACY" "${POTBSLEGACY}"
}

changeFolderUI(){
    while true; do
        if ans=$(zenity --entry --title="${uiTitle}" --window-icon="${uiIcon}" --width "400" \
            --icon-name="wine" \
            --text="Change game folder to:" \
            --entry-text="${POTBS_DIR}" \
            --extra-button "Explore" )
        then
            break
        fi

        case $ans in
            "Explore") POTBS_DIR=$(zenity --file-selection --title="Choose a directory" --directory --filename="${POTBS_DIR}");;
            "") return;;
            *) break;;
        esac
    done

    POTBS_DIR=$ans
    cfg_save_param "${CONFIG}" "POTBS_DIR" "${POTBS_DIR}"

}

downloadUI(){
    if ! POTBS_VERSION_SERVER=$(potbs_getServerVersion);then
        ui_err "$gameVersion"
        return 1
    fi

    #potbs_downloadGame "${POTBS_DIR}" "${POTBS_VERSION_SERVER}" | zenity --progress --title="${uiTitle}" --window-icon="${uiIcon}" --width "400" --no-cancel
    potbs_downloadGame "${POTBS_DIR}" "${POTBS_VERSION_SERVER}" 2>&1 | zenity --progress --title="${uiTitle}" --window-icon="${uiIcon}" --width "400" --auto-kill

    verifyUI
}

create_desktopUI(){
cat << EOF > PotBS.desktop
[Desktop Entry]
Type=Application
Name=PotBS
Comment=PotBS Linux Launcher
Exec=${work_dir}/launcher.sh gui
Icon=${DATA_DIR}/PotBS.png
Terminal=false
EOF

    chmod +x PotBS.desktop

    if type "xdg-user-dir" >/dev/null 2>&1;then
        local desctopDir
        desctopDir=$(xdg-user-dir "DESKTOP")
        mv -f "PotBS.desktop" "${desctopDir}"
    fi

}

downloadlangUI(){
    potsb_downloadLocale "${POTBS_DIR}" | zenity --progress --title="${uiTitle}" --window-icon="${uiIcon}" --width "400" --no-cancel
}

verifyUI(){

    potbs_checkLocalFiles "${POTBS_DIR}" | zenity --progress --title="${uiTitle}" --window-icon="${uiIcon}" \
        --width "400" \
        --text="Verify games files..." --percentage=50 \
        --no-cancel --auto-close --time-remaining 5

    if ! [ -f "$CORRUPTEDFILES" ];then
        zenity --info --title="${uiTitle}" --window-icon="${uiIcon}" \
        --icon-name="ok" \
        --text="No corrupted files"
        return 0
    fi

    if cat "$CORRUPTEDFILES" | tr '\t' '\n' | zenity --list --title="${uiTitle}" --window-icon="${uiIcon}" \
        --width "400"  --height "600"\
        --text="Corrupted files found:" \
        --ok-label "Download it" \
        --column="id" --column="File" --column="Hash" \
        --hide-column=1
    then
        potbs_downloadCorruptedFiles "${POTBS_DIR}" | zenity --progress --title="${uiTitle}" --window-icon="${uiIcon}" --width "400" --no-cancel
    fi


}

createPFXUI(){
    local ans

    while true; do
        if ans=$(zenity --entry --title="${uiTitle}" --window-icon="${uiIcon}" --width "400" \
            --icon-name="wine" \
            --text="Create new wineprefix in:" \
            --entry-text="${WINEPREFIX}" \
            --extra-button "Explore" )
        then
            break
        fi

        case $ans in
            "Explore") WINEPREFIX=$(zenity --file-selection --title="Choose a directory" --directory --filename="${WINEPREFIX}");;
            "") return;;
            *) break;;
        esac
    done

    WINEPREFIX=$ans

    if [ -f "${WINEPREFIX}/system.reg" ];then
        if zenity --question --title="${uiTitle}" --window-icon="${uiIcon}" --width "400" \
             --text="Prefix exist\n\nRemove current PFX?"
        then
            rm -fr "${WINEPREFIX}"
        else
            return 0
        fi

    fi

    cfg_save_param "${CONFIG}" "WINEPREFIX" "${WINEPREFIX}"

    initWinePrefix | zenity --progress --title="${uiTitle}" --window-icon="${uiIcon}" \
        --width "400" \
        --text="Create wine prefix..." --percentage=10 \
        --no-cancel --auto-close

    installWineDependence "${POTBS_DIR}" | zenity --progress --title="${uiTitle}" --window-icon="${uiIcon}" --width "400" --text="install Dependence..." --no-cancel

}

otherUI(){

    local ans
    if ! ans=$(zenity --list --title="${uiTitle}" --window-icon="${uiIcon}" \
            --width "400" --height "400" \
            --text="Select command to launch:" \
            --radiolist \
            --column="" --column="Command" \
            1 "Install DXVK" \
            2 "Download updated locale files" \
            3 "Launch winecfg" \
            4 "Create desktop link" \
            6 "Change game version" \
            7 "Change game folder" \
            8 "Recreate PFX" \
            9 "Debug on" \
        )
    then
        return
    fi

    case $ans in
            "Debug on") DEBUGGING=1;;
            "Install DXVK") install_dxvk | zenity --progress --title="${uiTitle}" --window-icon="${uiIcon}" --width "400" --text="install DXVK..." --no-cancel --auto-close;;
            "Download updated locale files") downloadlangUI;;
            "Launch winecfg") env WINEARCH="${WINEARCH}" WINEDEBUG="-all" WINEPREFIX="${WINEPREFIX}" "${WINE}" winecfg;;
            "Create desktop link") create_desktopUI;;
            "Change game version") changeVersionUI;;
            "Change game folder") changeFolderUI;;
            "Recreate PFX") createPFXUI;;
            *) echo "$ans";;
    esac

}

mainUI(){
    local buttons=()
    local updateInfo=""
    local legacy=""

    if [ "${POTBSLEGACY:-0}" -eq 1 ]; then
        legacy="Legacy version\n"
    fi

    btn(){
        local notRun=false
        local notDownload=false

        if [ -f "${POTBS_DIR}/PotBS.exe" ];then
            buttons+=("--extra-button" "Verify")
        else
            buttons+=("--extra-button" "Download")
            notRun=true
            notDownload=true
        fi

        if [ ! -f "${WINEPREFIX}/system.reg" ];then
            buttons+=("--extra-button" "Create PFX")
            notRun=true
        fi

        if ${notDownload};then
            return
        fi

        if isGameUpdated >/dev/null 2>&1;then
            if ! ${notRun};then
                buttons+=("--extra-button" "Run")
            fi
        else
            if [ "${POTBS_VERSION_INSTALLED}" == "Game files NOT found!" ];then
                buttons+=("--extra-button" "Download")
            else
                buttons+=("--extra-button" "Update")
                updateInfo="\nServer version: ${POTBS_VERSION_SERVER}\n\nNeed update game!"
            fi
        fi

    }

    btn

    local ans
    # OK button return code=0, all others=1
    if ans=$(zenity --info --title="${uiTitle}" --window-icon="${uiIcon}" \
        --icon-name="wine" \
        --text="${legacy}Installed version: ${POTBS_VERSION_INSTALLED}${updateInfo}\n\nGame dir: ${POTBS_DIR}\nGame PFX: ${WINEPREFIX}" \
        --ok-label "Quit" \
        --extra-button "Other" \
        "${buttons[@]}")
    then
        echo "$ans"
        return 0
    else
        echo "$ans"
        return 1
    fi
}


type "zenity" >/dev/null 2>&1 || { echo >&2 "[ERR] No zenity found.";exit 1; }


if ! [ -f "${POTBS_DIR}/PotBS.exe" ];then
    if [ ! -f "${WINEPREFIX}/system.reg" ];then
        changeVersionUI
    fi
fi

if [ "${SHOWMEMERRINFO:-1}" -eq 1 ]; then
    if isMemoryErr;then
        memoryErrUI
    fi
fi

while true; do
    if main=$(mainUI);then
        break
    fi

    case $main in
        "Download") downloadUI;;
        "Run") rungame;break;;
        "Update") updateUI;;
        "Create PFX") createPFXUI;;
        "Verify") verifyUI;;
        "Other") otherUI;;
        *) echo "$main";break;;
    esac

done

