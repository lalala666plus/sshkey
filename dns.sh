#!/bin/bash

# 停止 systemd-resolved 服务
sudo systemctl stop systemd-resolved

# 备份 /etc/systemd/resolved.conf 文件
if [ -f /etc/systemd/resolved.conf ]; then
    sudo cp /etc/systemd/resolved.conf /etc/systemd/resolved.conf.bak
fi

# 修改 /etc/systemd/resolved.conf 文件
sudo bash -c 'cat << EOF > /etc/systemd/resolved.conf
[Resolve]
DNS=127.0.0.1  #取消注释，增加dns
#FallbackDNS=
#Domains=
#LLMNR=no
#MulticastDNS=no
#DNSSEC=no
#Cache=yes
DNSStubListener=no  #取消注释，把yes改为no
EOF'

# 创建符号链接 /etc/resolv.conf
sudo ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf

# 重启 systemd-resolved 服务
sudo systemctl restart systemd-resolved

# 创建 /root/checkdns.sh 脚本
sudo bash -c 'cat << EOF > /root/checkdns.sh
#!/bin/bash
if ! grep -q "^nameserver 127.0.0.1$" /etc/resolv.conf || [ "\$(wc -l < /etc/resolv.conf)" -ne 1 ]; then
    echo "nameserver 127.0.0.1" > /etc/resolv.conf
fi
EOF'

# 给予 /root/checkdns.sh 可执行权限
sudo chmod +x /root/checkdns.sh

# 将 /root/checkdns.sh 脚本添加到 crontab 中，每两分钟运行一次
(crontab -l 2>/dev/null | grep -v -F "/root/checkdns.sh"; echo "*/2 * * * * /root/checkdns.sh") | crontab -

# 显示当前的 crontab 任务
sudo crontab -l

echo "脚本已完成设置。/root/checkdns.sh 将每两分钟运行一次。"
