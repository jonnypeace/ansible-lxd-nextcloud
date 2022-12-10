#!/bin/bash

#Bare Metal wireguard script to add new users.
#my wireguard uses the 10.6.0.0/24 subnet, so you'll have to update this accordingly.
#to save myself some typing time, for the $num variable, i just increment by 1 and this is the last digit of the IP.
#check the wg0.conf file to see which clients are using which IP's.
#also update your endpoint ip address, or i use dynamic dns for this
#choose which DNS you'd like to use.

# Creating server side keys

if [[ ! -f privatekey && ! -f publickey ]] ; then
	umask 077; wg genkey | tee privatekey | wg pubkey > publickey
	echo 'Created new Server Keys'
fi

# Create server side wg0.conf file
if [[ ! -f wg0.conf ]] ; then
cat << EOF > wg0.conf
[Interface]
Address = 10.6.0.1/24
ListenPort = 51820
PrivateKey = $(< privatekey)
EOF
if [[ $? -eq 0 ]]; then echo "wg0.conf created" ; fi
systemctl enable --now wg-quick@wg0
fi

#ubuntu server doesn't allow the edit of the wg0.conf file unless wireguard service has stopped running.
read -rp "Warning, this script will halt your wireguard server while adding new users. Proceed? [y/N]? " ans
mkdir -p /etc/wireguard/configs

if [[ "$ans" =~ ^(yes|y)$ ]]; then

	systemctl stop wg-quick@wg0
	read -rp "Enter peer name: " name
	read -rp "Enter subnet last digit, i.e. 10.6.0.2, last digit being 2: " num
	umask 077
	wg genkey | tee "$name"'_priv' | wg pubkey > "$name"'_pub'
	wg genpsk > "$name"'_psk'
	priv=$(cat "$name"'_priv')
	psk=$(cat "$name"'_psk')
	server_pub=$(< publickey)

	touch /etc/wireguard/configs/"$name".conf

	cat <<- EOF >> /etc/wireguard/configs/"$name".conf
	[Interface]
	PrivateKey = $priv
	Address = 10.6.0.$num/24
	ListenPort = 51820
	DNS = 103.86.96.100, 103.86.99.100
	[Peer]
	PublicKey = $server_pub
	PresharedKey = $psk
	Endpoint = MYDNS.ORMY.IP:51820
	AllowedIPs = 0.0.0.0/0, ::0/0
	PersistentKeepalive = 25
	EOF

	pub=$(cat "$name"_pub)

	cat <<- EOF >> /etc/wireguard/wg0.conf
	###$name###
	[peer]
	PublicKey = $pub
	PresharedKey = $psk
	AllowedIPs = 10.6.0.$num/32
	###end $name### 
	EOF

	systemctl start wg-quick@wg0

	echo "$name has been added to wireguard,config file located /etc/wireguard/configs" ; else
	echo "Exiting Script....."
	exit 0 ;
fi


######Some configurations for UFW#############################################################################################
#ufw route allow in on wg0 out on eth0 from 10.6.0.0/24
#nano /etc/ufw/sysctl.conf and uncomment net.ipv4.ip_forward=1
#Set up nat routing and edit /etc/ufw/before.rules and include these lines before the filter rules.
##############################################################################
#		# nat Table rules
#		*nat
#		:POSTROUTING ACCEPT [0:0]

#		# Forward traffic from wg0 through eth0.
#		-A POSTROUTING -s 10.10.10.0/24 -o eth0 -j MASQUERADE

#		don't delete the 'COMMIT' line or these nat table rules won't be processed
#		COMMIT
##############################################################################

#Directly under the MASQUERADE rule, the rule for that table must have COMMIT. This is the case for each table in these rules.
##############################################################################################################################
