#!/bin/bash

# Author : 1Stream
# Website : https://1stream.icu

if [ "$1" != 'restore' ]; then
    DNS1=$1
    DNS2=$2
fi

function Get_OSName() {
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
        exit 1;
    fi
}

function get_char() {
    SAVEDSTTY=`stty -g`
    stty -echo
    stty cbreak
    dd if=/dev/tty bs=1 count=1 2> /dev/null
    stty -raw
    stty echo
    stty $SAVEDSTTY
}

function chooseNetworkTool() {
    if command -v ss > /dev/null 2>&1; then
        NETWORK_TOOL="ss"
    elif command -v netstat > /dev/null 2>&1; then
        NETWORK_TOOL="netstat"
    else
        echo "未找到可用的网络工具 (ss 或 netstat)，请安装之后再运行脚本。"
        exit 1
    fi
}

function check53PortUsage() {
    if [ "$NETWORK_TOOL" == "ss" ]; then
        if ss -tulnp | grep ":53 " | grep -q "systemd-resolved"; then
            echo 1
        else
            echo 0
        fi
    elif [ "$NETWORK_TOOL" == "netstat" ]; then
        if netstat -tlunp | grep ":53 " | grep -q "systemd-resolved"; then
            echo 1
        else
            echo 0
        fi
    fi
}

function Welcome() {
    echo -e '正在检测您的操作系统...'
    Get_OSName
    chooseNetworkTool
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
    if [ $(check53PortUsage) -eq 1 ]; then
        read -p "检测到 systemd-resolved 占用了 53 端口，需要处理吗？(y/N): " fix53
        if [[ "$fix53" == 'y' ]] || [[ "$fix53" == 'Y' ]]; then
            handleSystemdResolvedPortConflict
        fi
    fi
    echo -e '请按任意键继续，如有配置错误请使用 Ctrl+C 退出。'
    char=`get_char`
}

function handleSystemdResolvedPortConflict() {
    echo "正在处理 systemd-resolved 占用的 53 端口问题..."
    systemctl stop systemd-resolved
    sed -i 's/^#DNS=/DNS=8.8.8.8/' /etc/systemd/resolved.conf
    sed -i 's/^#DNSStubListener=yes/DNSStubListener=no/' /etc/systemd/resolved.conf
    ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
    echo "已处理 systemd-resolved 的 53 端口冲突。"
}

function ChangeDNS() {
    if grep -Eqi "CentOS" /etc/issue || grep -Eq "CentOS" /etc/*-release; then
        echo
        echo -e '正在备份当前DNS配置文件...'
        cp /etc/resolv.conf /etc/resolv.conf.backup || { echo "备份失败"; exit 1; }
        echo
        echo -e '备份完成，正在修改DNS配置文件...'
        chattr -i /etc/resolv.conf
        if [ `cat /etc/redhat-release|sed -r 's/.* ([0-9]+)\..*/\1/'` == 7 ]; then
            sed -i '/\[main\]/a dns=none' /etc/NetworkManager/NetworkManager.conf
            systemctl restart NetworkManager.service || { echo "NetworkManager 重启失败"; exit 1; }
        fi
        echo -e 'nameserver '$DNS1'' > /etc/resolv.conf || { echo "修改DNS失败"; exit 1; }
        if [ "$DNS2" != '' ]; then
            echo -e 'nameserver '$DNS2'' >> /etc/resolv.conf || { echo "添加备用DNS失败"; exit 1; }
        fi
        if [[ -n "${tcp}" && ( "$tcp" == 'y' || "$tcp" == 'Y' ) ]]; then
            echo -e 'options use-vc' >> /etc/resolv.conf
        fi
        echo
        echo -e 'DNS配置文件修改完成。'
    elif grep -Eqi "Debian" /etc/issue || grep -Eq "Debian" /etc/*-release; then
        echo
        echo -e '正在备份当前DNS配置文件...'
        cp /etc/resolv.conf /etc/resolv.conf.backup || { echo "备份失败"; exit 1; }
        echo
        echo -e '备份完成，正在修改DNS配置文件...'
        chattr -i /etc/resolv.conf
        echo "" > /etc/resolv.conf || { echo "清空resolv.conf失败"; exit 1; }
        if [[ -n "${tcp}" ]]; then
            if [[ "$tcp" == 'y' ]] || [[ "$tcp" == 'Y' ]]; then
                echo -e 'options use-vc' >> /etc/resolv.conf
            fi
        fi
        echo -e 'nameserver '$DNS1'' >> /etc/resolv.conf || { echo "添加主DNS失败"; exit 1; }
        if [ "$DNS2" != '' ]; then
            echo -e 'nameserver '$DNS2'' >> /etc/resolv.conf || { echo "添加备用DNS失败"; exit 1; }
        fi
        echo
        echo -e 'DNS配置文件修改完成。'
    elif grep -Eqi "Ubuntu" /etc/issue || grep -Eq "Ubuntu" /etc/*-release; then
        echo
        echo -e '正在修改DNS配置文件...'
        if [ `cat /etc/issue|awk '{print $2}'|awk -F'.' '{print $1}'` -le 17 ]; then
            echo -e 'nameserver '$DNS1'' > /etc/resolvconf/resolv.conf.d/base || { echo "修改base文件失败"; exit 1; }
            if [ "$DNS2" != '' ]; then
                echo -e 'nameserver '$DNS2'' >> /etc/resolvconf/resolv.conf.d/base || { echo "添加备用DNS失败"; exit 1; }
            fi
            resolvconf -u || { echo "更新resolvconf失败"; exit 1; }
        else
            if [ -L /etc/resolv.conf ]; then
                RESOLV_CONF_TARGET=$(readlink /etc/resolv.conf)
                RESOLV_CONF_PATH="${RESOLV_CONF_TARGET:-/run/systemd/resolve/resolv.conf}"
            else
                chattr -i /etc/resolv.conf
                RESOLV_CONF_PATH="/etc/resolv.conf"
            fi
            echo -e 'nameserver '$DNS1'' > $RESOLV_CONF_PATH || { echo "修改resolv.conf失败"; exit 1; }
            if [ "$DNS2" != '' ]; then
                echo -e 'nameserver '$DNS2'' >> $RESOLV_CONF_PATH || { echo "添加备用DNS失败"; exit 1; }
            fi
            systemctl restart systemd-resolved.service || { echo "systemd-resolved 重启失败"; exit 1; }
        fi
        echo
        echo -e 'DNS配置文件修改完成。'
    fi
    echo
    echo -e '感谢您的使用, 如果您想恢复备份，请在执行脚本文件时使用参数 restore 。'
}

function RestoreDNS() {
    if grep -Eqi "CentOS" /etc/issue || grep -Eq "CentOS" /etc/*-release; then
        echo -e '正在恢复默认DNS配置文件...'
        chattr -i /etc/resolv.conf
        rm -rf /etc/resolv.conf
        mv /etc/resolv.conf.backup /etc/resolv.conf || { echo "恢复备份失败"; exit 1; }
        if [ `cat /etc/redhat-release|sed -r 's/.* ([0-9]+)\..*/\1/'` == 7 ]; then
            sed -i 's/dns=none//g' /etc/NetworkManager/NetworkManager.conf
            systemctl restart NetworkManager.service || { echo "NetworkManager 重启失败"; exit 1; }
        fi
        echo
        echo -e 'DNS配置文件恢复完成。'
    elif grep -Eqi "Debian" /etc/issue || grep -Eq "Debian" /etc/*-release; then
        echo -e '正在恢复默认DNS配置文件...'
        chattr -i /etc/resolv.conf
        rm -rf /etc/resolv.conf
        mv /etc/resolv.conf.backup /etc/resolv.conf || { echo "恢复备份失败"; exit 1; }
        echo
        echo -e 'DNS配置文件恢复完成。'
    elif grep -Eqi "Ubuntu" /etc/issue or grep -Eq "Ubuntu" /etc/*-release; then
        echo -e '正在恢复默认DNS配置文件...'
        if [ `cat /etc/issue|awk '{print $2}'|awk -F'.' '{print $1}'` -le 17 ]; then
            echo -e '' > /etc/resolvconf/resolv.conf.d/base || { echo "清空base文件失败"; exit 1; }
            resolvconf -u || { echo "更新resolvconf失败"; exit 1; }
        else
            if [ -L /etc/resolv.conf ]; then
                RESOLV_CONF_TARGET=$(readlink /etc/resolv.conf)
                RESOLV_CONF_PATH="${RESOLV_CONF_TARGET:-/run/systemd/resolve/resolv.conf}"
            else
                chattr -i /etc/resolv.conf
                RESOLV_CONF_PATH="/etc/resolv.conf"
            fi
            sed -i '/nameserver/d' $RESOLV_CONF_PATH || { echo "删除nameserver条目失败"; exit 1; }
            systemctl restart systemd-resolved.service || { echo "systemd-resolved 重启失败"; exit 1; }
        fi
        echo
        echo -e 'DNS配置文件恢复完成。'
    fi
}

function addDNS() {
    Welcome
    ChangeDNS
}

if [ "$1" != 'restore' ]; then
    addDNS
elif [ "$1" == 'restore' ]; then
    RestoreDNS
else
    echo '用法错误！'
fi
