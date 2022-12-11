# ansible-lxd-nextcloud

---
title: Ansible / Bash - Nextcloud Deployment - LXD
date: 2022-12-10 13:00:00
categories: [bash,ansible,scripting,ubuntu,lxd,nextcloud,mariadb,backup]
tags: [bash,ansible,lxd,nextcloud]
---

# Easy Nextcloud Deployment using bash with ansible.

There are probably ways to make this work with ansible only, but I thought I would use a mix of skills, and it seems to work with just a few configuration adjustments.

If not done so already, perhaps explore the idea of an LXD host, as i've written this for remote LXD hosts. You could just as easily modify this for a local LXD host.

Since this is taking place over LXD, there's no need to use SSH. You can use _lxc remote switch 'host'_ and this will work. This means you don't need ansible vault.

I have used docker for such instances, but I quite like what Ubuntu are doing right now with snaps, LXD, microceph and microcloud. If you are now aware of these applications, I encourage you to have a look.

## Github

Clone my repo for this...

```bash
git clone https://github.com/jonnypeace/ansible-lxd-nextcloud.git
```

## hosts.yaml

The hosts.yaml file needs updated where the comments are, but as you can see you could modify this for local use.

```yaml
---
all:
  vars:
    ansible_connection: lxd
    ansible_user: root
    ansible_become: no
  children:
    local:
      vars:
        ansible_lxd_remote: local
        ansible_lxd_project: homelab
      hosts:
    lxd-host:  # Adjust to same name as anible_lxd_remote
      vars:
        ansible_lxd_remote: lxd-host # Enter your lxd remote host, check with 'lxc remote list' 
      hosts:
        new-container: # This will be the name of the LXD container, so will need adjusted.

```

## backup.sh

This is a simple backup and restore script for mariadb and nextcloud. The ansible playbook will use this to restore an old/existing nextcloud, but you will be prompted as to whether this is required. You could always use it to backup and restore day-to-day.

However, this section at the top of the script needs modified to suit your needs.

```bash
nc_backup='/mnt/nextcloud/backup/nextcloud.tar.bz2'
nextcloud_dir='/var/www/domain.com/'
db_pass=$(< .db-password.txt)
db_backup='/mnt/nextcloud/backup' # this is a directory
```

## Config

This should hopefully be self explanatory, comments are already provided in the script to help guide.

```bash
# Container Name
container-name=nc-new

# Shared directory/external storage for nextcloud on LXD host
host-share=/mnt/shares/nextcloud

# Where to mount the directory/external storage in the container
cont-mount=/mnt/nextcloud

# For LXD... a name for the device being added to LXD
share-name=nextcloud

# Nextcloud backup, used for restoring an existing nextcloud installation
nextcloud-source=/mnt/shares/nextcloud/backup/nextcloud.tar.bz2

# Database backup, used for restoring the database from an existing nextcloud installation - 
# Will only work with the same nextcloud instance described above.
tar-db=/mnt/shares/nextcloud/backup/nextcloud-sqlbkp_20221126.bak

# This will be used in your /var/www directory
www-dir=domain.com

# This will be used in your virtual hosts file.
domain=domain.com

# This is for your apache2 server.
virtual-hosts-file=domain.com.conf
```

## nodes_update.yaml

This is used to update nodes. Since this is a baremetal nextcloud/mariadb, a simple apt package manager will update most of the container. Nextcloud will need manual updates either via the nextcloud admin page, or something a little more manual.

```yaml
---
- name: Update and Upgrade LXD cluster nodes
  hosts: nc-new
  tasks:
  - name: Update and upgrade apt packages
    apt:
      upgrade: yes
      update_cache: yes
      cache_valid_time: 86400
```

## .db-password.txt

I would create this file and use this for your mariadb nextcloud password. Once the password has been added, run... 

```bash
chmod 400 .db-password.txt
```

## template.yaml

You shouldn't need to make any modifications, the script will make the modifications covered in the config files, but feel free to make your own improvements or tweaks that you require. This template will be used to create your nextcloud container playbook file.

## setup.sh

Ok, once all config files are ready, this script will guide you through the setup.

```bash
./setup.sh
```

## Wireguard Script

I have left this script in, as originally I would reverse proxy with a VPS directly from nextcloud, but now I put nextcloud behind a second proxy and this proxy takes care of the wireguard traffic (much easier). I will eventually write something with how I do this.

## Extras

If you want to upload files larger than 10MB (where I was having problems), chunk size issues may arise with Nextcloud. Try this inside your lxd container...

```bash
sudo -u www-data php --define apc.enable_cli=1 occ config:app:set files max_chunk_size --value 0
```
