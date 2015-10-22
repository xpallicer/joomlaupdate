#!/bin/bash
#!/bin/sh

# joomlaupdate
# Updates your Joomla 2.5/3.1 website to the latest version.
#
# Usage: joomlaupdate [-s] [-b] [-h] [-l]
#
# Default action is verbose on, no backup.
# -s Silent. Do not display any informational messages.
# -b Backup. Create a backup before updating.
# -l Log. Write messages to logile /var/log/joomlaupdate.log.
# -h Help. Display this info.
# Run joomlaupdate at the root of your website, where the configuration.php is.
#
# Copyright 2013 Rene Kreijveld - email@renekreijveld.nl
#
# This program is free software; you may redistribute it and/or modify it.
#
# Necessary tools for this script: wget, unzip, tar and perl. Install these if they are not available.
#
# Version history
# 1.0: - Initial version.
# 1.1: - Added support for Joomla 3.0 and 3.1.
#      - Better logging, added -l parameter.
#      - Clode cleanup.
# 1.2: - Added backup path (suggestion by Remco Janssen).
# 1.3: - Removed support for Joomla 3.0.
#      - Fixed bug of not all SQL updates being run (thanks Xavier Pallicer).
# 1.4: - Added updating of #__schemas table. This was missing (thanks Xavier Pallicer).
# 1.5: - Added updating of #__extensions table. This was missing (thanks Xavier Pallicer).
#

# general variables
version=1.5
logfile=/var/log/joomlaupdate.log
backuppath=../

# find mysql socket
if [ -S /var/lib/mysql/mysql.sock ]; then
  mysock=/var/lib/mysql/mysql.sock
elif [ -S /var/run/mysqld/mysqld.sock ]; then
  mysock=/var/run/mysqld/mysqld.sock
elif [ -S /Applications/XAMPP/xamppfiles/var/mysql/mysql.sock ]; then
  mysock=/Applications/XAMPP/xamppfiles/var/mysql/mysql.sock
elif [ -S /tmp/mysql.sock ]; then
  mysock=/tmp/mysql.sock
fi

# display usage information
usage() {
  echo "joomlaupdate version $version, written by Rene Kreijveld."
  echo " "
  echo "Usage: joomlaupdate [-s] [-b] [-l] [-h]"
  echo " "
  echo "Default action is verbose on, no backup."
  echo "-s Silent. Do not display any informational messages."
  echo "-b Backup. Create a backup before updating."
  echo "-l Log. Write messages to logile /var/log/joomlaupdate.log."
  echo "-h Help. Display this info."
  echo " "
  echo "Run joomlaupdate at the root of your website, where the configuration.php is."
  echo " "
  exit 0
}

# process the arguments
while getopts sblh opt
do
   case "$opt" in
      s) silent="yes";;
      b) backup="yes";;
      l) logging="yes";;
      h) usage;;
      \?) usage;;
   esac
done

# echo out messages to screen and/or logfile
eout() {
  mesg=$1
  stdout=$2

  # if logfile doesn't exist, create it first
  if [ ! -f "$logfile" ]; then
    touch $logfile
  fi

  # if not silent display message
  if [ "$silent" != "yes" ]; then
    if [ ! -z "$stdout" ]; then
      echo "$mesg"
    fi
  fi

  # if logging enabled message to logfile
  if [ "$logging" == "yes" ]; then
    echo "$mesg" >> $logfile
  fi
}

# grab information from Joomla 2.5/3.1 configuration.
do_joomla() {
  sitename=`grep '$sitename =' configuration.php | cut -d \' -f 2 | sed 's/ /_/g'`
  versr=`grep '$RELEASE' libraries/cms/version/version.php | cut -d \' -f 2`
  versd=`grep '$DEV_LEVEL' libraries/cms/version/version.php | cut -d \' -f 2`
  verss=`grep '$DEV_STATUS' libraries/cms/version/version.php | cut -d \' -f 2`
  database=`grep '$db =' configuration.php | cut -d \' -f 2`
  dbuser=`grep '$user =' configuration.php | cut -d \' -f 2`
  password=`grep '$password =' configuration.php | cut -d \' -f 2`
  host=`grep '$host =' configuration.php | cut -d \' -f 2`
  prefix=`grep '$dbprefix =' configuration.php | cut -d \' -f 2`
}

# cleanup all temporary files
do_cleanup() {
  if [ -f list1.xml ]; then
    rm -f list1.xml
  fi
  if [ -f list2.xml ]; then
    rm -f list2.xml
  fi
  if [ -f update.zip ]; then
    rm -f update.zip
  fi
  if [ -f tmp/sqlupdate.sql ]; then
    rm -f tmp/sqlupdate.sql
  fi
  if [ -f $backuppath$database.sql ]; then
    rm -f $backuppath$database.sql
  fi
  if [ -f joomla.xml ]; then
    rm -f joomla.xml
  fi
}

# create a full backup of the joomla website
do_backup() {
  # dump the database to a .sql file
  eout "Backup requested." 1
  eout "Creating database backup." 1

  # check if sql dumpfile already exists
  if [ -f $backuppath$database.sql ]; then
    eout "Database backup file $backuppath$database.sql already exists. Exiting." 1
    do_cleanup
    datestamp=`date +"%d-%m-%Y, %H:%M:%S"`
    eout "$datestamp: End joomlaupdate."
    exit 1
  fi

  # create mysqldump
  if mysqldump --skip-opt --add-drop-table --add-locks --create-options --disable-keys --lock-tables --quick --set-charset --host=$host --user=$dbuser --password=$password --socket=$mysock $database > $backuppath$database.sql; then
    eout "$backuppath$database.sql created." 1
  else
    eout "Error creating database dump, exiting." 1
    do_cleanup
    datestamp=`date +"%d-%m-%Y, %H:%M:%S"`
    eout "$datestamp: End joomlaupdate."
    exit 1
  fi

  # check if tgz backupfile doesn't already exist
  if [ -f $backuppath$sitename.tgz ]; then
    eout "Backup file $backuppath$sitename already exists. Exiting." 1
    do_cleanup
    datestamp=`date +"%d-%m-%Y, %H:%M:%S"`
    eout "$datestamp: End joomlaupdate."
    exit 1
  fi

  # create the .tgz backup
  eout "Creating files backup." 1
  tar czf $backuppath$sitename.tgz .htaccess *
  eout "Your website backup is ready in $backuppath$sitename.tgz." 1
  eout " " 1
}

get_joomla_info() {
  # Grab owner and group of current configuration.php
  owner=`ls -l configuration.php | awk '{print$3}'`
  group=`ls -l configuration.php | awk '{print$4}'`

  # Testing for Joomla version 2.5 or 3.1
  if [ -f libraries/cms/version/version.php ]; then
    release=`grep '$RELEASE' libraries/cms/version/version.php | cut -d \' -f 2`
    if [ "$release" == "1.5" ]; then
      echo "This Joomla version cannot be updated. Exiting."
      exit 0
    fi
    # grab information about joomla
    do_joomla
  fi
}

datestamp=`date +"%d-%m-%Y, %H:%M:%S"`
if [ "$logging" == "yes" ]; then
  eout " "
  eout "$datestamp: Start joomlaupdate."
fi

eout "joomlaupdate version $version, written by Rene Kreijveld." 1
eout " " 1

# if configuration.php present then proceed
if [ -f configuration.php ]; then
  # display information about current website
  get_joomla_info
  eout "This Joomla! website:" 1
  eout "Sitename    : $sitename" 1
  eout "Version     : $versr.$versd" 1
  eout "DB Name     : $database" 1
  eout "DB User     : $dbuser" 1
  eout "DB Password : $password" 1
  eout "DB Host     : $host" 1
  eout "DB Prefix   : $prefix" 1
  eout "Path        : `pwd`" 1
  eout "Owner       : $owner" 1
  eout "Group       : $group" 1
  eout " " 1

  # store old development version
  oldversd=$versd
  oldversfull="$versr.$versd"

  # get update list from joomla.org
  updatelist=`grep "<server" -m 1 administrator/manifests/files/joomla.xml | awk -F"<server type=\"collection\">" '{print$2}' | awk -F"</server>" '{print$1}'`
  wget $updatelist -q -O list1.xml >/dev/null 2>/dev/null
  updatelist="unknown"

  # grab information about update file and latest version number
  updatelist=`grep "targetplatformversion=\"$versr\"" -m 1 list1.xml | awk -F"detailsurl=\"" '{print$2}' | awk -F"\" />" '{print$1}'`
  newversion=`grep "targetplatformversion=\"$versr\"" -m 1 list1.xml | awk -F"version=\"" '{print$2}' | awk -F"\"" '{print$1}'`

  # this website is not 2.5/3.1, exiting
  if [ "$updatelist" == "unknown" ]; then
    eout "This Joomla version cannot be updated. Exiting." 1
    do_cleanup
    datestamp=`date +"%d-%m-%Y, %H:%M:%S"`
    eout "$datestamp: End joomlaupdate."
    exit 0
  fi

  # if current version number equals latest version number no update is necessary
  if [ "$versr.$versd" == "$newversion" ]; then
    eout "This Joomla website is already up-to-date. Exiting." 1
    do_cleanup
    datestamp=`date +"%d-%m-%Y, %H:%M:%S"`
    eout "$datestamp: End joomlaupdate."
    exit 0
  else
    # if backup needed, create backup first
    if [ "$backup" == "yes" ]; then
      do_backup
    fi

    eout "This website will be updated to version $newversion." 1
    wget $updatelist -q -O list2.xml >/dev/null 2>/dev/null

    # get url of update zipfile
    updatefile=`grep "x_to_$newversion" -m 1 list2.xml | awk -F">" '{print$2}' | awk -F"</downloadurl" '{print$1}'`
    eout "Downloading updatefile: $updatefile." 1

    # download update zipfile
    wget $updatefile -O update.zip >/dev/null 2>/dev/null

    # Updating files
    eout "Extracting zipfile, updating files." 1

    # update files
    unzip -q -o update.zip

    # retrieve new version info
    get_joomla_info

    # set rights
    eout "Setting file ownership." 1
    chown -R $owner:$group .htaccess *

    # execute all mysql updates frm previous version to current version
    oldversd=`expr $oldversd + 1`
    eout " " 1
    for (( u=oldversd; u<=versd; u++ )); do
      for sqlfile in `ls administrator/components/com_admin/sql/updates/mysql/$versr.$u*sql`; do
        eout "Running SQL update $sqlfile." 1

        # copy sql update file to temporary directory
        cp $sqlfile tmp/sqlupdate.sql

        # modify prefix so it matches for this website
        perl -pi -e "s/#__/$prefix/g" tmp/sqlupdate.sql

        # run sql updates
        if mysql --host=$host --user=$dbuser --password=$password --socket=$mysock $database < tmp/sqlupdate.sql
        then
          eout "SQL update completed." 1
          rm -f tmp/sqlupdate.sql
        else
          eout "Error running SQL update. Exiting." 1
          do_cleanup
          datestamp=`date +"%d-%m-%Y, %H:%M:%S"`
          eout "$datestamp: End joomlaupdate."
          exit 1
        fi
      done
    done

    # fix joomla version in #__schema and #__extension tables
    sql="UPDATE #__schemas SET version_id = \"$versr.$versd\" WHERE extension_id = 700;"
    echo $sql | sed -e "s/#__/$prefix/" > tmp/sqlupdate.sql
    sql="UPDATE #__extensions SET manifest_cache = REPLACE(manifest_cache, '\"version\":\"$oldversfull\"', '\"version\":\"$versr.$versd\"') WHERE extension_id = 700;"
    echo $sql | sed -e "s/#__/$prefix/" >> tmp/sqlupdate.sql

    if mysql --host=$host --user=$dbuser --password=$password --socket=$mysock $database < tmp/sqlupdate.sql
    then
      eout "Succesfully updated #__schemas and #__extension tables." 1
      rm -f tmp/sqlupdate.sql
    else
      eout "Error updating #__schemas and #__extensions tables. Exiting." 1
      do_cleanup
      datestamp=`date +"%d-%m-%Y, %H:%M:%S"`
      eout "$datestamp: End joomlaupdate."
      exit 1
    fi

    eout " " 1
    eout "Cleaning up temporary files." 1
    do_cleanup

    # update and display joomla info
    eout " " 1
    eout "Joomla update finished. Website info:" 1
    eout "Sitename    : $sitename" 1
    eout "Version     : $versr.$versd" 1
    eout "Do not forget to update your language files." 1

    # finished
    datestamp=`date +"%d-%m-%Y, %H:%M:%S"`
    eout "$datestamp: End joomlaupdate."
  fi
else
  eout "File configuration.php not found. Are you at the root of the site?" 1
  datestamp=`date +"%d-%m-%Y, %H:%M:%S"`
  eout "$datestamp: End joomlaupdate."
  eout " "
  exit 1
fi
