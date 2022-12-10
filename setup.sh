#!/bin/bash

# Warning Colour Highlighting
red="\e[1;31m%s\e[0m\n"
green="\e[1;32m%s\e[0m\n"
yellow="\e[1;33m%s\e[0m\n"

function for-trap {

rm "${playbook}"
clear
exit
}

trap 'for-trap' SIGINT

read -rp "Name of new playbook? " playbook
cp playbook-template/template.yaml "$playbook"
printf "\n$green\n" "Check the hosts.yaml matches the config"
cat hosts.yaml
echo
grep "container-name" config
echo
read -rp "Edit any files? Container-name should be under hosts in hosts.yaml. y/N " ans
if [[ $ans =~ ^[yY][eE]?[sS]?$ ]] ; then exit ; fi

printf '%s\n' "Before beginning, ensure the config file has been updated"

read -rp "Config file updated? Y/n " ans
if [[ $ans =~ ^[nN][oO]?$ ]]; then
  echo "please update the config file"
  exit
fi

##### Something HERE for nextcloud latest or tar archive to copy over

if [[ ! -f latest.zip ]] ; then
  read -rp "Do you need to download nextclouds latest? y/N " ans
  if [[ $ans =~ ^[yY][eE]?[sS]?$ ]]; then
    wget https://download.nextcloud.com/server/releases/latest.zip
    nextcloud_source='latest.zip'
  else
    read -rp "Do you have a TAR archive Databse and Nextcloud backup to copy over? y/N " ans
    if [[ $ans =~ ^[yY][eE]?[sS]?$ ]]; then
      printf "\n$red\n" "Please provide the name and path of the archive in the config file" 
      cat config
      echo -e "\n\n"
      read -rp "Does your config have the necessary paths for the database and nextcloud backup? y/N " ans
      if [[ $ans =~ ^[yY][eE]?[sS]?$ ]]; then
        echo "Ok, we'll continue with the script"
        nextcloud_path=$(awk -F '=' '/nextcloud-source/{print $2}' config)
        nextcloud_source=$(cut -d "/" -f 7 <<< "${nextcloud_path}")
        tar_db=$(awk -F '=' '/tar-db/{print $2}' config)
        sed -i "s|DATABASE\.BK|$tar_db|" "$playbook"
      else
        echo 'Better edit the config with the database and nextcloud backup data'
        exit
      fi
    else
      printf "\n$red\n" "This script requires nextcloud latest zip or a backup of nextcloud to continue..."
      exit
    fi
  fi
fi

## importing variables from the config file ## THIS LIST MIGHT GROW

cont_name=$(awk -F '=' '/container-name/{print $2}' config)
nextcloud_dir=$(awk -F '=' '/www-dir/{print $2}' config)

sed -i "s/nc-new/${cont_name}/" "${playbook}"

# Ensuring ansible with ansible galaxy packages are installed
os_dist=$(awk -F '"' '/^NAME=/{print $2}' /etc/os-release)

if [[ "$os_dist" == "Arch Linux" ]]; then
  pkg_in="sudo pacman -S --noconfirm"
  pkg_q="sudo pacman -Qq"
elif [[ "$os_dist" == "Ubuntu" ]]; then
  pkg_in='sudo apt install -y'
  pkg_q='dpkg -l'
fi

if ! $pkg_q ansible > /dev/null ; then
  $pkg_in ansible
fi

if ! ansible-galaxy collection list | grep -q community.general ; then
  ansible-galaxy collection install comminity.general
fi
if ! ansible-galaxy collection list | grep -q ansible.posix ; then
  ansible-galaxy collection install ansible.posix
fi

if ! lxc list | grep -q "$cont_name" ; then
  echo "Creating new ubuntu container called $cont_name"
  lxc launch images:ubuntu/22.04 "$cont_name"
  wait
fi
cat << EOF
  
  Pre-requisites for mounting shares in container:
  
  1) Set up a samba share on the host in /etc/fstab. I've had better success with permissions using samba
  2) You might need to do some further mapping with /etc/subuid & /etc/subgid. I don't need to, I mount samba with the users option, not sure if this helps

EOF

read -rp "Do you want to map your user and setup / mount a network share? y/N " ans

if [[ "$ans" =~ ^[yY][eE]?[sS]?$ ]]; then
  h_share=$(awk -F '=' '/host-share/{print $2}' config)
  c_mount=$(awk -F '=' '/cont-mount/{print $2}' config)
  share_name=$(awk -F '=' '/share-name/{print $2}' config)
  lxc config device add "$cont_name" "$share_name" disk source="$h_share" path="$c_mount"
  lxc config set "$cont_name"  raw.idmap "both 1000 33" # This allows nextcloud to write to the network share. 
fi

# Replacing placeholders with variables in the yaml playbook

virtual_host=$(awk -F '=' '/virtual-hosts-file/{print $2}' config)
domain=$(awk -F '=' '/domain/{print $2}' config)
cp virtual-host.bk "$virtual_host"
sed -i "s|nc-source|${nextcloud_source}|" "${playbook}"
sed -i "s|nc-path|${nextcloud_path}|" "${playbook}"
sed -i "s|nc-dir|${nextcloud_dir}|" "${playbook}"
sed -i "s|nc-dir|${nextcloud_dir}|" "${virtual_host}"
sed -i "s|domain|${domain}|" "${virtual_host}"
sed -i "s|vi-file|${virtual_host}|" "${playbook}"
sed -i "s|virtual\.conf|${virtual_host}|" "${playbook}"

ansible-playbook -i hosts.yaml "${playbook}"

wait

printf "$green\n" "You can run this playbook again using this command..."
printf "$red\n" "**** ansible-playbook -i hosts.yaml $playbook ****"
printf "$green\n" "More likely you'll only need to run the update nodes_update playbook for patching containers"
printf "$green\n" "On the host run -- lxc exec $cont_name bash -- to enter the terminal of the container"

read -rp "Do you want to archive the playbook setup? y/N  " ans

if [[ $ans =~ ^[yY][eE]?[sS]?$ ]]; then
  mkdir -p archived-playbooks
  mv "$playbook" archived-playbooks/
fi

cat << EOF

  ############################################################################################

  Answers for mariadb secure installation:

    - enter for none
    - no for unix
    - root pass Y
    - remove anonymous Y
    - disallow root login Y
    - remove test db Y
    - reload Y

  ############################################################################################
EOF

lxc exec "$cont_name" mysql_secure_installation

cat << EOF

  #############################################################################################

  Commands for mariadb database and user creation:

  Change the password from my password to something a bit more secure.... :-)

    - CREATE DATABASE nextcloud;
    - SHOW DATABASES;
    - GRANT ALL PRIVILEGES ON nextcloud.* TO 'nextcloud'@'localhost' IDENTIFIED BY 'mypassword';
    - FLUSH PRIVILEGES;

    ctrl+d should escape out, or type exit and press enter.

  ##############################################################################################
EOF

lxc exec "$cont_name" mariadb
