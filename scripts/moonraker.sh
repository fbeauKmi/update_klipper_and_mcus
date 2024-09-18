#!/bin/bash

function moonraker_query(){
    local key=$2
    local object=$( echo "$1" | sed 's/ /%20/g' )
    moonraker_object="http://127.0.0.1:7125/"
    eval "$key=\$( curl -s \"$moonraker_object$object\" )"
    if [[ ! $( echo ${!key} | grep -o '"result":') == '"result":' ]] ; then
        return 1
    fi
}

function parse_json(){
    local value=$(echo "$json" | grep -o "\"$1\": \"[^\"]*" | cut -d'"' -f4)
    # Use eval to assign the value to the variable name passed as $3
    eval "$2=\"$value\""
}

function list_mcus() {
    local -n result=$1  # Use nameref for indirect reference
    # Use mapfile to read the output of grep and sed directly into an array
     mapfile -t result < <(echo "$json" | grep -oP '"mcu[^"]*' | sed 's/"//g')
}

function get_mcus_version(){

    if moonraker_query "printer/info" json ; then
        parse_json state printer_state
        if [[ $printer_state == "ready" ]] ; then
            parse_json python_path k_venv
            parse_json app k_app
            moonraker_query "printer/objects/list" json
            list_mcus mcus
            for mcu in "${mcus[@]}"
            do
                moonraker_query "printer/objects/query?$mcu" json
                parse_json mcu_version tmp
                for cmcu in "${mcu_order[@]}"
                do 
                    if [[ $mcu == ${mcu_info["$cmcu"]} ]]; then
                        mcu_version["$cmcu"]=$tmp
                    fi
                done
            done
            return 0
        elif [[ $printer_state == "startup" ]] ; then
            echo "Printer is not started! Unable to collect Klipper infos on mcus"
            return 0
        fi
        echo "Printer is not ready ! YOU MUST NOT UPDATE MCUS WHILE PRINTING !"
        exit 1
    fi
    echo "Failed to query Moonraker. Unable to collect Klipper infos on mcus"
    return 0
}
