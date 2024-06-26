#!/usr/bin/env bash
#=============================================================
# https://github.com/P3TERX/SSH_Key_Installer
# Description: Install SSH keys via GitHub, URL or local files
# Version: 2.7
# Author: P3TERX
# Blog: https://p3terx.com
#=============================================================

VERSION=2.7
RED_FONT_PREFIX="\033[31m"
LIGHT_GREEN_FONT_PREFIX="\033[1;32m"
FONT_COLOR_SUFFIX="\033[0m"
INFO="[${LIGHT_GREEN_FONT_PREFIX}INFO${FONT_COLOR_SUFFIX}]"
ERROR="[${RED_FONT_PREFIX}ERROR${FONT_COLOR_SUFFIX}]"
[ $EUID != 0 ] && SUDO=sudo

USAGE() {
    echo "
SSH Key Installer $VERSION

Usage:
  bash <(curl -fsSL git.io/key.sh) [options...] <arg>

Options:
  -o  Overwrite mode, this option is valid at the top
  -g  Get the public key from GitHub, the arguments is the GitHub ID
  -u  Get the public key from the URL, the arguments is the URL
  -f  Get the public key from the local file, the arguments is the local file path
  -p  Change SSH port, the arguments is port number
  -d  Disable password login
  -r  Restrict root login to key-based authentication only"
}

# Check if no arguments were passed
if [ $# -eq 0 ]; then
    USAGE
    exit 1
fi

get_github_key() {
    if [ "${KEY_ID}" == '' ]; then
        read -e -p "Please enter the GitHub account:" KEY_ID
        [ "${KEY_ID}" == '' ] && echo -e "${ERROR} Invalid input." && exit 1
    fi
    echo -e "${INFO} The GitHub account is: ${KEY_ID}"
    echo -e "${INFO} Get key from GitHub..."
    PUB_KEYS=$(curl -fsSL https://github.com/${KEY_ID}.keys)
    if [ "${PUB_KEYS}" == 'Not Found' ]; then
        echo -e "${ERROR} GitHub account not found."
        exit 1
    elif [ -z "${PUB_KEYS}" ]; then
        echo -e "${ERROR} This account has no SSH keys available."
        exit 1
    else
        echo "Raw keys output:"
        echo "${PUB_KEYS}"
        echo "Processing keys..."
        key_array=()
        while IFS= read -r line; do
            key_array+=("$line")
        done <<< "$PUB_KEYS"
        echo "Number of keys fetched: ${#key_array[@]}"
        echo "Available keys:"
        for i in "${!key_array[@]}"; do
            echo "$((i+1))) ${key_array[i]}"
        done
        read -p "Enter the number of the key you want to use: " key_choice
        if [[ key_choice -lt 1 || key_choice -gt ${#key_array[@]} ]]; then
            echo -e "${ERROR} Invalid key choice."
            exit 1
        fi
        PUB_KEY="${key_array[$((key_choice-1))]}"
        echo "Selected SSH Key:"
        echo "${PUB_KEY}"
    fi
}

get_url_key() {
    if [ "${KEY_URL}" == '' ]; then
        read -e -p "Please enter the URL:" KEY_URL
        [ "${KEY_URL}" == '' ] && echo -e "${ERROR} Invalid input." && exit 1
    fi
    echo -e "${INFO} Get key from URL..."
    PUB_KEY=$(curl -fsSL ${KEY_URL})
}

get_loacl_key() {
    if [ "${KEY_PATH}" == '' ]; then
        read -e -p "Please enter the path:" KEY_PATH
        [ "${KEY_PATH}" == '' ] && echo -e "${ERROR} Invalid input." && exit 1
    fi
    echo -e "${INFO} Get key from $(${KEY_PATH})..."
    PUB_KEY=$(cat ${KEY_PATH})
}

install_key() {
    [ "${PUB_KEY}" == '' ] && echo "${ERROR} ssh key does not exist." && exit 1
    if [ ! -f "${HOME}/.ssh/authorized_keys" ]; then
        echo -e "${INFO} '${HOME}/.ssh/authorized_keys' is missing..."
        echo -e "${INFO} Creating ${HOME}/.ssh/authorized_keys..."
        mkdir -p ${HOME}/.ssh/
        touch ${HOME}/.ssh/authorized_keys
        if [ ! -f "${HOME}/.ssh/authorized_keys" ]; then
            echo -e "${ERROR} Failed to create SSH key file."
        else
            echo -e "${INFO} Key file created, proceeding..."
        fi
    fi
    if [ "${OVERWRITE}" == 1 ]; then
        echo -e "${INFO} Overwriting SSH key..."
        echo -e "${PUB_KEY}\n" >${HOME}/.ssh/authorized_keys
    else
        echo -e "${INFO} Adding SSH key..."
        echo -e "\n${PUB_KEY}\n" >>${HOME}/.ssh/authorized_keys
    fi
    chmod 700 ${HOME}/.ssh/
    chmod 600 ${HOME}/.ssh/authorized_keys
    [[ $(grep "${PUB_KEY}" "${HOME}/.ssh/authorized_keys") ]] &&
        echo -e "${INFO} SSH Key installed successfully!" || {
        echo -e "${ERROR} SSH key installation failed!"
        exit 1
    }
}

disable_password() {
    if [ $(uname -o) == Android ]; then
        # 删除所有存在的PasswordAuthentication和PubkeyAuthentication行，包括被注释的行
        sed -i "/^[#]*\s*PasswordAuthentication/d" $PREFIX/etc/ssh/sshd_config
        sed -i "/^[#]*\s*PubkeyAuthentication/d" $PREFIX/etc/ssh/sshd_config
        
        # 在文件末尾添加我们的配置
        echo "PasswordAuthentication no" >> $PREFIX/etc/ssh/sshd_config
        echo "PubkeyAuthentication yes" >> $PREFIX/etc/ssh/sshd_config
        
        RESTART_SSHD=2
        echo -e "${INFO} Disabled password login and enabled SSH key authentication in SSH."
        
    else
        # 删除所有存在的PasswordAuthentication和PubkeyAuthentication行，包括被注释的行
        $SUDO sed -i "/^[#]*\s*PasswordAuthentication/d" /etc/ssh/sshd_config
        $SUDO sed -i "/^[#]*\s*PubkeyAuthentication/d" /etc/ssh/sshd_config

        # 在文件末尾添加我们的配置
        $SUDO bash -c 'echo "PasswordAuthentication no" >> /etc/ssh/sshd_config'
        $SUDO bash -c 'echo "PubkeyAuthentication yes" >> /etc/ssh/sshd_config'
        
        RESTART_SSHD=1
        echo -e "${INFO} Disabled password login and enabled SSH key authentication in SSH."
    fi
}

restrict_root_login() {
    if [ $(uname -o) == Android ]; then
        # 删除所有存在的PermitRootLogin行，包括被注释的行
        sed -i "/^[#]*\s*PermitRootLogin/d" $PREFIX/etc/ssh/sshd_config
        
        # 在文件末尾添加我们的配置
        echo "PermitRootLogin without-password" >> $PREFIX/etc/ssh/sshd_config
        
        RESTART_SSHD=2
        echo -e "${INFO} Restricted root login to key-based authentication in SSH."
        
    else
        # 删除所有存在的PermitRootLogin行，包括被注释的行
        $SUDO sed -i "/^[#]*\s*PermitRootLogin/d" /etc/ssh/sshd_config

        # 在文件末尾添加我们的配置
        $SUDO bash -c 'echo "PermitRootLogin without-password" >> /etc/ssh/sshd_config'
        
        RESTART_SSHD=1
        echo -e "${INFO} Restricted root login to key-based authentication in SSH."
    fi
}

change_port() {
    echo -e "${INFO} Changing SSH port to ${SSH_PORT} ..."
    if [ $(uname -o) == Android ]; then
        [[ -z $(grep "Port " "$PREFIX/etc/ssh/sshd_config") ]] &&
            echo -e "${INFO} Port ${SSH_PORT}" >>$PREFIX/etc/ssh/sshd_config ||
            sed -i "s@.*\(Port \).*@\1${SSH_PORT}@" $PREFIX/etc/ssh/sshd_config
        [[ $(grep "Port " "$PREFIX/etc/ssh/sshd_config") ]] && {
            echo -e "${INFO} SSH port changed successfully!"
            RESTART_SSHD=2
        } || {
            RESTART_SSHD=0
            echo -e "${ERROR} SSH port change failed!"
            exit 1
        }
    else
        $SUDO sed -i "s@.*\(Port \).*@\1${SSH_PORT}@" /etc/ssh/sshd_config && {
            echo -e "${INFO} SSH port changed successfully!"
            RESTART_SSHD=1
        } || {
            RESTART_SSHD=0
            echo -e "${ERROR} SSH port change failed!"
            exit 1
        }
    fi
}

while getopts "og:u:f:p:dr" OPT; do
    case $OPT in
    o)
        OVERWRITE=1
        ;;
    g)
        KEY_ID=$OPTARG
        get_github_key
        install_key
        ;;
    u)
        KEY_URL=$OPTARG
        get_url_key
        install_key
        ;;
    f)
        KEY_PATH=$OPTARG
        get_loacl_key
        install_key
        ;;
    p)
        SSH_PORT=$OPTARG
        change_port
        ;;
    d)
        disable_password
        ;;
    r)
        restrict_root_login
        ;;
    ?)
        USAGE
        exit 1
        ;;
    :)
        USAGE
        exit 1
        ;;
    *)
        USAGE
        exit 1
        ;;
    esac
done

if [ "$RESTART_SSHD" = 1 ]; then
    echo -e "${INFO} Restarting sshd..."
    $SUDO systemctl restart sshd && echo -e "${INFO} Done."
elif [ "$RESTART_SSHD" = 2 ]; then
    echo -e "${INFO} Restart sshd or Termux App to take effect."
fi
