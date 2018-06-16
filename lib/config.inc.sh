#!/bin/bash
# Library that allow to manage a configuration file

set_entry(){
        local key=""
        local value=""
        local config_file=""
        while getopts "k:v:f:" opt; do
                case $opt in
                k)
                        key=$OPTARG
                ;;
                v)
                        value=$OPTARG
                ;;
                f)
                        config_file=$OPTARG
                ;;
                esac
        done

        if [ $( cat $config_file | grep $key | wc -l ) -gt 0 ]; then
                sudo sed -i "s|^\("$key"\s*=\s*\).*\$|\1\"$value\"|" $config_file
        else
                echo $key"="\"$value\" >> $config_file
        fi
        OPTIND=1
}
