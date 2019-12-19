public_ip=`curl -s ifconfig.me/ip`
read -p "Pre-Shared Kesy:   " shared_key
read -p "Username:  " username
read -p "Password:  " password

#安装必要包
yum install -y epel-release
yum install -y xl2tpd libreswan lsof

#5.编辑xl2tpd配置文件
mv /etc/xl2tpd/xl2tpd.conf /etc/xl2tpd/xl2tpd.conf_bak
cat >/etc/xl2tpd/xl2tpd.conf<<EOF
[global]
listen-addr = 45.88.40.112 

[lns default]
ip range = 192.168.1.128-192.168.1.254
local ip = 192.168.1.99
require chap = yes
refuse pap = yes
require authentication = yes
name = LinuxVPNserver
ppp debug = yes
pppoptfile = /etc/ppp/options.xl2tpd
length bit = yes
EOF

#6.编辑pppoptfile文件
mv /etc/ppp/options.xl2tpd /etc/ppp/options.xl2tpd_bak
cat >/etc/ppp/options.xl2tpd<<EOF
pcp-accept-local
ipcp-accept-remote
ms-dns  114.114.114.114
ms-dns  223.5.5.5
# ms-wins 192.168.1.2
# ms-wins 192.168.1.4
name xl2tpd
#noccp
auth
#crtscts
idle 1800
mtu 1410
mru 1410
nodefaultroute
debug
#lock
proxyarp
connect-delay 5000
refuse-pap
refuse-mschap
require-mschap-v2
persist
logfile /var/log/xl2tpd.log
EOF

#7-8.编辑ipsec配置文件
mv /etc/ipsec.conf /etc/ipsec.conf_bak
cat >/etc/ipsec.conf<<EOF
config setup
    nat_traversal=yes
    virtual_private=%v4:10.0.0.0/8,%v4:192.168.0.0/16,%v4:172.16.0.0/12,%v4:!192.168.18.0/24
    oe=off
    protostack=netkey
    plutostderrlog=/var/log/ipsec.log
conn L2TP-PSK-NAT
    rightsubnet=vhost:%priv
    also=L2TP-PSK-noNAT
conn L2TP-PSK-noNAT
    authby=secret
    type=transport
    pfs=no
    auto=add
    keyingtries=3
    rekey=no
    ikelifetime=8h
    keylife=1h
    left=$public_ip
    leftprotoport=17/1701
    right=%any
    rightprotoport=17/%any
    rightsubnetwithin=0.0.0.0/0
    forceencaps=yes  #此项必须开启，否则NAT设备无法上网
EOF

#9.设置用户名密码
mv /etc/ppp/chap-secrets /etc/ppp/chap-secrets_bak
cat >/etc/ppp/chap-secrets<<EOF
$username  *   $password  *
# 格式为： 用户名  类型  密码  允许访问的ip
# 这个配置文件，也是pptpd的用户密码配置文件，直接类型上用*表示所有。因为这里我们只搭建l2tp/ipsec
EOF

#10.设置预共享密钥PSK
mv /etc/ipsec.d/default.secrets /etc/ipsec.d/default.secrets_bak
cat >/etc/ipsec.d/default.secrets<<EOF
: PSK $shared_key   # 就一行，填上自定义的PSK，连接时会使用到。
EOF

#11.CentOS7 防火墙设置
firewall-cmd --permanent --add-service=ipsec      # 放行ipsec服务，安装时会自定生成此服务
firewall-cmd --permanent --add-port=1701/udp      # xl2tp 的端口，默认1701. 
firewall-cmd --permanent --add-port=4500/udp 
firewall-cmd --permanent --add-masquerade      # 启用NAT转发功能。必须启用此功能
firewall-cmd --reload      # 重载配置

#12.修改内核参数
cat >>/etc/sysctl.conf<<EOF
net.ipv4.ip_forward = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.rp_filter = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.default.rp_filter = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.eth0.accept_redirects = 0
net.ipv4.conf.eth0.rp_filter = 0
net.ipv4.conf.eth0.send_redirects = 0
net.ipv4.conf.eth1.accept_redirects = 0
net.ipv4.conf.eth1.rp_filter = 0
net.ipv4.conf.eth1.send_redirects = 0
net.ipv4.conf.eth2.accept_redirects = 0
net.ipv4.conf.eth2.rp_filter = 0
net.ipv4.conf.eth2.send_redirects = 0
net.ipv4.conf.ip_vti0.accept_redirects = 0
net.ipv4.conf.ip_vti0.rp_filter = 0
net.ipv4.conf.ip_vti0.send_redirects = 0
net.ipv4.conf.lo.accept_redirects = 0
net.ipv4.conf.lo.rp_filter = 0
net.ipv4.conf.lo.send_redirects = 0
EOF

sysctl -p

systemctl enable ipsec     # 设为开机启动
systemctl start ipsec     # 启动服务
systemctl enable xl2tpd      # 设为卡机启动
systemctl start xl2tpd      # 启动xl2tp
