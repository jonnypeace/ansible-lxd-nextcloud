#!/bin/bash


# Modify these paths/files to suit your needs. For database password, i recommend using a separate file
# Once you've set the password in that file, run this command on it as root...
# chmod 400 db-password.txt, maybe prefix the password filename with a period, so it's hidden.

nc_backup='/mnt/nextcloud/backup/nextcloud.tar.bz2'
nextcloud_dir='/var/www/domain.com/'
db_pass=$(< .db-password.txt)
db_backup='/mnt/nextcloud/backup'
archive='/mnt/nextcloud/archive'


if [[ $1 == "-h" ]]; then
    cat << EOF
    
    Useage:

    help:    ./backup.sh -h
    backup:  ./backup.sh
    restore: ./backup.sh restore

EOF

fi

if [[ $1 == "backup" ]]; then
    mkdir -p "${archive}"
    mv "${nc_backup}" "${archive}"
    sudo -u www-data php --define apc.enable_cli=1 -f "${nextcloud_dir}"/occ maintenance:mode --on
    tar -vcjf "${nc_backup}" "${nextcloud_dir}"
    
    mysqldump --single-transaction -h localhost -u nextcloud --password="${db_pass}" nextcloud > "$db_backup"/nextcloud-sqlbkp_$(date +"%Y%m%d").bak
    sudo -u www-data php --define apc.enable_cli=1 -f "${nextcloud_dir}"/occ maintenance:mode --off
fi

if [[ $1 == "restore" ]]; then

#   change into /var/www and extract backup files
    cd /var/www/ && tar -xf "${nc_backup}"
#   Remove any previous nextcloud databases and create a new one.
    mysql -h localhost -u nextcloud --password="${db_pass}" -e "DROP DATABASE nextcloud"
    mysql -h localhost -u nextcloud --password="${db_pass}" -e "CREATE DATABASE nextcloud"
#   Restore mariadb from backup
    find "$db_backup"/*sqlbkp*.bak
    read -rp "Enter Path and file name for mariadb backup: " ans
    mysql -h localhost -u nextcloud --password="${db_pass}" nextcloud < "${ans}"
    sudo -u www-data php --define apc.enable_cli=1 -f "${nextcloud_dir}"/occ maintenance:mode --off
    sudo -u www-data php --define apc.enable_cli=1 -f "${nextcloud_dir}"/occ maintenance:data-fingerprint
fi
