#!/usr/bin/env bash

set -Eeuo pipefail
trap cleanup SIGINT SIGTERM ERR EXIT

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

usage() {
  cat <<EOF
Usage: $(basename "${BASH_SOURCE[0]}") [-h] [-v] [-f] -d /dev/sdb -u ISO_URL

Simple script to flash an iso from url and optionally store it to file as well.

Available options:

-h, --help      Print this help and exit
-v, --verbose   Print more info
-f, --force      Disables overwrite prompt
-u, --url       URL of the iso
-t, --target       path of the local target
-d, --device    Device path, like "/dev/sdb"
EOF
    exit
}

cleanup() {
    trap - SIGINT SIGTERM ERR EXIT
    # script cleanup here
}

setup_colors() {
    if [[ -t 2 ]] && [[ -z "${NO_COLOR-}" ]] && [[ "${TERM-}" != "dumb" ]]; then
        NOFORMAT='\033[0m' RED='\033[0;31m' GREEN='\033[0;32m' ORANGE='\033[0;33m' BLUE='\033[0;34m' PURPLE='\033[0;35m' CYAN='\033[0;36m' YELLOW='\033[1;33m'
    else
        NOFORMAT='' RED='' GREEN='' ORANGE='' BLUE='' PURPLE='' CYAN='' YELLOW=''
    fi
}

msg() {
    echo >&2 -e "${1-}"
}

die() {
    local msg=$1
    local code=${2-1} # default exit status 1
    msg "$msg"
    exit "$code"
}

check_for_commands() {
    if ! command -v curl &> /dev/null ;then
        die "Missing curl command"
    fi
    
    if ! command -v tee &> /dev/null ;then
        die "Missing tee command"
    fi
    
    if ! command -v dd &> /dev/null ;then
        die "Missing dd command"
    fi
}

parse_params() {
    VERBOSE=0
    # default values of variables set from params
    force=0
    target=''
    skipdownload=0
    
    while :; do
        case "${1-}" in
            -h | --help) usage ;;
            -v | --verbose) VERBOSE=1 ;;
            --no-color) NO_COLOR=1 ;;
            -f | --force) force=1 ;;
            -u | --url)
                url="${2-}"
                shift
            ;;
            -t | --target)
                target="${2-}"
                shift
            ;;
            -d | --device)
                device="${2-}"
                shift
            ;;
            -?*) die "Unknown option: $1" ;;
            *) break ;;
        esac
        shift
    done
    
    args=("$@")
    
    # check required params and arguments
    if [[ -z "${device-}" ]];then
        die "Missing required parameter: device"
    fi
    if [[ -z "${url-}" ]];then
        die "Missing required parameter: url"
    fi
    
    if [[ ! "${url}" =~ http* ]];then
        die "Invalid URL parameter"
    fi
    
    if [[ ! -b "${device}" ]];then
        die "Invalid device parameter"
    fi
    
    if findmnt |grep $device &> /dev/null;then
        die "device $device is mounted"
    fi
    
    return 0
}

get_iso_size() {
    curl --location -sI "$1" | grep -i Content-Length | awk '{print $2}' |sed 's/\r$//' || echo 0
}



check_for_commands
parse_params "$@"
setup_colors

# script logic here
iso_size=$(get_iso_size "$url")
if [[ "$iso_size" = "0" ]];then
    die "invalid iso, failed to get size"
fi

if [[ ! -z ${target} ]];then
    if [ -d "${target}" ];then
        url_basename=$(basename $(curl -L --head -w '%{url_effective}' $url 2>/dev/null | tail -n1))
        if [[ -z "${url_basename}" ]];then
            die 'unable to find correct filename. Please specify a full target including filename.'
        fi
        
        target="$(realpath "${target}")"
        target="${target}"/"$url_basename"
    fi
    
fi

if [[ ${VERBOSE} = 1 ]];then
    msg "${GREEN}Parameters:${NOFORMAT}"
    msg "- device: ${device}"
    msg "- url: ${url}"
    msg "- size: ${iso_size}"
    [[ ! -z ${target} ]] && msg "- target file: ${target}"
fi

if [[ ! -z ${target} ]] && [[ -f ${target} ]];then
    target_size=$(stat --printf="%s" "${target}")
    
    if [[ "${target_size}" == "${iso_size}" ]];then
        while true; do
            read -p "The target file seems to already be downloaded, do you want skip download? `echo $'\n> '`" yn
            case $yn in
                [Yy]* ) skipdownload=1; break;;
                [Nn]* ) break;;
                * ) echo "Please answer yes or no.";;
            esac
        done
        
    fi
fi

if [[ ! ${force} = 1 ]];then
    while true; do
        read -p "This will overwrite everything on ${device}. Do you want to continue?`echo $'\n> '`" yn
        case $yn in
            [Yy]* ) break;;
            [Nn]* ) exit;;
            * ) echo "Please answer yes or no.";;
        esac
    done
fi

# make sudo cache the session before we start the complex pipe
sudo ls &> /dev/null

if [[ ${skipdownload} = 1 ]];then
    sudo dd if="$target" of="$device" bs=1M status=progress conv=fsync oflag=direct;
    exit
fi

if [[ ! -z "$target" ]];then
    curl --silent --location "$url" | tee "$target" |sudo dd iflag=fullblock of="$device" bs=1M status=progress conv=fsync oflag=direct
else
    curl --silent --location "$url" | sudo dd iflag=fullblock of="$device" bs=1M status=progress conv=fsync oflag=direct
fi


