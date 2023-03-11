#!/bin/sh

GUI=1

uiTitle="PotBS Linux Launcher"
uiIcon="${DATA_DIR}/PotBS.png"

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

    # TODO: save new WINEPREFIX

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
            --text="Create new wineprefix in:" \
            --radiolist \
            --column="" --column="Description" \
            1 "Install DXVK" \
            2 "Download updated locale files" \
            3 "Launch winecfg" \
            3 "Debug" \
        )
    then
        return
    fi

    case $ans in
            "Debug") DEBUGGING=1;;
            "Install DXVK") install_dxvk | zenity --progress --title="${uiTitle}" --window-icon="${uiIcon}" --width "400" --text="install DXVK..." --no-cancel --auto-close;;
            "Download updated locale files") downloadlangUI;;
            "Launch winecfg") env WINEARCH="${WINEARCH}" WINEDEBUG="-all" WINEPREFIX="${WINEPREFIX}" "${WINE}" winecfg;;
            *) echo "$ans";;
    esac

}

mainUI(){
    local buttons=()

    btn(){
        local notRun=false
        if [ -f "${POTBS_DIR}/PotBS.exe" ];then
            buttons+=("--extra-button" "Verify")
        else
            buttons+=("--extra-button" "Download")
            notRun=true
        fi

        if [ ! -f "${WINEPREFIX}/system.reg" ];then
            buttons+=("--extra-button" "Create PFX")
            notRun=true
        fi

        if ${notRun};then
            return
        fi

        if isGameUpdated;then
            buttons+=("--extra-button" "Run")
        else
            buttons+=("--extra-button" "Update")
        fi

    }

    btn

    local ans
    # OK button return code=0, all others=1
    if ans=$(zenity --info --title="${uiTitle}" --window-icon="${uiIcon}" \
        --icon-name="wine" \
        --text="Installed version: ${POTBS_VERSION_INSTALLED}\n\nGame dir: ${POTBS_DIR}\nGame PFX: ${WINEPREFIX}" \
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

if ! POTBS_VERSION_INSTALLED=$(potbs_getlocalversion "$POTBS_DIR");then
    echo_err "$POTBS_VERSION_INSTALLED"
fi

while true; do
    if main=$(mainUI);then
        break
    fi

    case $main in
        "Run") rungame;break;;
        "Create PFX") createPFXUI;;
        "Verify") verifyUI;;
        "Other") otherUI;;
        *) echo "$main";break;;
    esac

done


