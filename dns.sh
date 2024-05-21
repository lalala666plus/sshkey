#!/bin/bash

# Author : 1Stream
# Website : https://1stream.icu

if [ "$1" != 'restore' ]; then
    DNS1=$1
    DNS2=$2
fi

function Get_OSName(){
    if grep -Eqi "CentOS" /etc/issue || grep -Eq "CentOS" /etc/*-release; then
        DISTRO='CentOS'
    elif grep -Eqi "Debian" /etc/issue || grep -Eq "Debian" /etc/*-release; then
        DISTRO='Debian'
    elif grep -Eqi "Ubuntu" /etc/issue || grep -Eq "Ubuntu" /etc/*-release; then
        DISTRO='Ubuntu'
    else
        DISTRO='unknown'
    fi
    if [ "$DISTRO" != 'unknown' ]; then
        echo -e '检测到您的系统为: '$DISTRO''
    else
        echo -e '不支持的操作系统，请更换为 CentOS / Debian / Ubuntu 后重试。'
        exit 1
    fi
}

function get_char(){
    SAVEDSTTY=$(stty -g)
    stty -echo
    stty cbreak
    dd if=/dev/tty bs=1 count=1 2> /dev/null
    stty -raw
    stty echo
    stty "$SAVEDSTTY"
}

function Welcome(){
    echo -e '正在检测您的操作系统...'
    Get_OSName
    echo -e '您确定要使用下面的DNS地址吗？'
    echo -e '主DNS: '$DNS1''
    if [ "$DNS2" != '' ]; then
        echo -e '备DNS: '$DNS2''
    fi
    echo
    read -p "是否使用TCP DNS (y/N):" tcp
    if [[ -n "${tcp}" ]]; then
        if [[ "$tcp" == 'y' ]] || [[ "$tcp" == 'Y' ]]; then
            echo -e '使用TCP DNS'
        fi
    fi
    echo -e '请按任意键继续，如有配置错误请使用 Ctrl+C 退出。'
    char=$(get_char)
}

function ChangeDNS(){
    if grep -Eqi "CentOS" /etc/issue || grep -Eq "CentOS" /etc/*-release; then
        echo -e '正在备份当前DNS配置文件...'
        cp /etc/resolv.conf /etc/resolv.conf.backup
        echo -e '备份完成，正在修改DNS配置文件...'
        if [ "$(cat /etc/redhat-release | sed -r 's/.* ([0-9]+)\..*/\1/')" == 7 ];then
            sed -i '/\[main\]/a dns=none' /etc/NetworkManager/NetworkManager.conf
            systemctl restart NetworkManager.service
        fi
        echo -e 'nameserver '$DNS1'' > /etc/resolv.conf
        if [ "$DNS2" != '' ];then
            echo -e 'nameserver '$DNS2'' >> /etc/resolv.conf
        fi
        echo -e 'DNS配置文件修改完成。'
    elif grep -Eqi "Debian" /etc/issue || grep -Eq "Debian" /etc/*-release; then
        echo -e '正在备份当前DNS配置文件...'
        cp /etc/resolv.conf /etc/resolv.conf.backup
        echo -e '备份完成，正在修改DNS配置文件...'
        echo "" > /etc/resolv.conf
        if [[ -n "${tcp}" ]]; then
            if [[ "$tcp" == 'y' ]] || [[ "$tcp" == 'Y' ]]; then
                echo -e 'options use-vc' >> /etc/resolv.conf
            fi
        fi
        echo -e 'nameserver '$DNS1'' >> /etc/resolv.conf
        if [ "$DNS2" != '' ];then
            echo -e 'nameserver '$DNS2'' >> /etc/resolv.conf
        fi
        echo -e 'DNS配置文件修改完成。'
    elif grep -Eqi "Ubuntu" /etc/issue || grep -Eq "Ubuntu" /etc/*-release; then
        echo -e '正在修改DNS配置文件...'
        if [ "$(cat /etc/issue | awk '{print $2}' | awk -F'.' '{print $1}')" -le 17 ]; then
            echo -e 'nameserver '$DNS1'' > /etc/resolvconf/resolv.conf.d/base
            if [ "$DNS2" != '' ];then
                echo -e 'nameserver '$DNS2'' >> /etc/resolvconf/resolv.conf.d/base
            fi
            resolvconf -u
        else
            echo -e 'nameserver '$DNS1'' > /etc/systemd/resolved.conf
            if [ "$DNS2" != '' ];then
                echo -e 'nameserver '$DNS2'' >> /etc/systemd/resolved.conf
            fi
            systemctl restart systemd-resolved.service
        fi
        echo -e 'DNS配置文件修改完成。'
    fi
    echo -e '感谢您的使用, 如果您想恢复备份，请在执行脚本文件时使用参数 restore 。'
}

function ResolvePortIssue(){
    if [ -L /etc/resolv.conf ] && [ "$(readlink /etc/resolv.conf)" = "/run/systemd/resolve/resolv.conf" ]; then
        echo -e '检测到systemd-resolved正在使用/etc/resolv.conf，正在处理...'
        systemctl stop systemd-resolved
        sed -i 's/#DNS=/DNS='$DNS1'/' /etc/systemd/resolved.conf
        sed -i 's/#DNSStubListener=yes/DNSStubListener=no/' /etc/systemd/resolved.conf
        ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
        echo -e 'systemd-resolved 配置修改完成，已释放53端口。'
    fi
}

function RestoreDNS(){
    if grep -Eqi "CentOS" /etc/issue || grep -Eq "CentOS" /etc/*-release; then
        echo -e '正在恢复默认DNS配置文件...'
        rm -rf /etc/resolv.conf
        mv /etc/resolv.conf.backup /etc/resolv.conf
        if [ "$(cat /etc/redhat-release | sed -r 's/.* ([0-9]+)\..*/\1/')" == 7 ]; then
            sed -i 's/dns=none//g' /etc/NetworkManager/NetworkManager.conf
            systemctl restart NetworkManager.service
        fi
        echo -e 'DNS配置文件恢复完成。'
    elif grep -Eqi "Debian" /etc/issue || grep -Eq "Debian" /etc/*-release; then
        echo -e '正在恢复默认DNS配置文件...'
        rm -rf /etc/resolv.conf
        mv /etc/resolv.conf.backup /etc/resolv.conf
        echo -e 'DNS配置文件恢复完成。'
    elif grep -Eqi "Ubuntu" /etc/issue || grep -Eq "Ubuntu" /etc/*-release; then
        echo -e '正在恢复默认DNS配置文件...'
        if [ "$(cat /etc/issue | awk '{print $2}' | awk -F'.' '{print $1}')" -le 17 ]; then
            echo -e '' > /etc/resolvconf/resolv.conf.d/base
            resolvconf -u
        else
            sed -i '/nameserver/d' /etc/systemd/resolved.conf
            systemctl restart systemd-resolved.service
        fi
        echo -e 'DNS配置文件恢复完成。'
    fi
}

function addDNS(){
    Welcome
    ResolvePortIssue
    ChangeDNS
}

if [ "$1" != 'restore' ]; then
    addDNS
elif [ "$1" == 'restore' ]; then
    RestoreDNS
else
    echo '用法错误！'
fi
