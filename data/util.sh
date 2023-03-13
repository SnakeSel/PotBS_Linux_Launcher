#!/bin/bash

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

echo_debug() {
    if [ "${DEBUGGING:-0}" -eq 1 ]; then
        #echo "$(date +'%Y-%m-%d %H:%M:%S')" "$@" >> "${logfile}/${script_name}.log"
        echo "[DBG:${BASH_LINENO[0]}] $*" >&2
    fi
}

# $1 - "{owner}/{repo}"
get_latest_release() {
    #wget --quiet -O - "https://api.github.com/repos/$1/releases/latest" | # Get latest release from GitHub api
    #grep '"tag_name":' |                                            # Get tag line
    #sed -E 's/.*"([^"]+)".*/\1/'                                    # Pluck JSON value
    wget --quiet -O - "https://api.github.com/repos/$1/releases/latest" | "${jq}" -r '.tag_name'

}

#Сохранить параметр в файл
# $1: Файл
# $2: Название параметра
# $3: Значение параметра
cfg_save_param() {
    echo_debug "cfg_save_param start"
    echo_debug "$1 $2 $3"
    # проверяем кол-во параметров
    if [ $# -ne 3 ]; then
        echo "[save_cfg_param] переданы не все параметры"
        return 1
    fi

    # Если файла конфига нет, просто пишем в новый файл
    if [ ! -f "${1}" ]; then
        echo_debug "Создаем новый ${1}"
        echo "${2}=${3}" > "${1}"
        return 0
    fi


    # параметр для grep. Экранируем " и []
    grep_param=$(echo "${2}" | sed 's/"/\\"/g' | sed 's/\[/\\\[/g' | sed 's/\]/\\\]/g')

    #local lineN
    #lineN=$(grep -n -e "${2}=" -e "${2} " "${1}" | grep -v "#" | cut -d":" -f1)

    # разделитель конец строки (для считывания вывода grep)
    oldIFS=$IFS
    IFS=$'\n'
    # Считываем все строки из файла содержащие параметр, с указанием номера строки,
    # обрезая текст после #
    alllines=( $(grep -n -e "${grep_param}=" -e "${grep_param} " "${1}" | cut -d"#" -f1) )
    IFS=$oldIFS
    echo_debug "${alllines[*]}"

    # перебираем все найденные строки
    for i in "${alllines[@]}"; do
        _line=$(echo "$i" | cut -d":" -f2)
        # Если строка начинается на параметр - бинго
        # Отрезает пустые строки (когда начинаются с #)
        if [[ "$_line" == "${2}"* ]];then
            lineN=$(echo "$i" | cut -d":" -f1)
            continue
        fi
    done

    echo_debug "lineN: ${lineN:-}"
    # Если нет совпадения, то дописываем в файл
    #if [ -z "${lineN}" ];then
    if [ -z "${lineN:-}" ];then
         echo "${2}=${3}" >> "${1}"
    else
        # Заменяем всю строку на новую
        sed -i "${lineN}s:.*:${2}=${3}:" "${1}"

        # Замена через удаление
        # Удаляем строку
        #sed -i "${lineN}d" "${1}"
        #sed -i "${lineN} i ${2}=${3}" "${1}"
            # i добавляет новую строку перед заданной.
            # a добавляет новую строку после заданной.
    fi
    echo_debug "save_cfg_param end"
}

# Получить параметр ${2} из файла настроек ${1}
# $1: Файл конфига
# $2: Название параметра
# Return: значение параметра
cfg_load_param() {
    echo_debug "$*"
    # проверяем кол-во параметров
    if [ $# -ne 2 ]; then
        echo_err "переданы не все параметры"
        return 1
    fi

    local raw_param
    local config
    local param
    local value

    config="$1"
    param="$2"
    # Убираем пробелы в начале и комментарии:
    raw_param=$(grep "${param}" "${config}" | sed 's/^[ \t]*//' | grep -v "^#" )
    # Берем значение и убираем пробелы в начале и конце
    value=$(echo "${raw_param}" | cut -d"=" -f2 | sed 's/^[ \t]*//' | sed 's/[ \t]*$//')

    echo "${value}"
}
