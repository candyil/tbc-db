#!/bin/bash

####################################################################################################
#
#   Simple helper script to insert clean TBC-DB
#
####################################################################################################

# need to be changed on each official DB/CORE release
FULLDB_FILE_ZIP="TBCDB_1.9.0_TheLastVengeance.sql.gz"
FULLDB_FILE=${FULLDB_FILE_ZIP%.gz}
DB_TITLE="v1.8 'Vengeance Strikes Back'"
NEXT_MILESTONES="0.12.4 0.13"

#internal use
SCRIPT_FILE="InstallFullDB.sh"
CONFIG_FILE="InstallFullDB.config"

# testing only
ADDITIONAL_PATH=""

#variables assigned and read from $CONFIG_FILE
DB_HOST="localhost"
DB_PORT="3306"
DATABASE=""
USERNAME=""
PASSWORD=""
MYSQL=""
CORE_PATH=""
LOCALES="YES"
DEV_UPDATES="NO"
FORCE_WAIT="YES"

function create_config {
# Re(create) config file
cat >  $CONFIG_FILE << EOF
####################################################################################################
# This is the config file for the '$SCRIPT_FILE' script
#
# You need to insert
#   DB_HOST:      Host on which the database resides
#   DB_PORT:      Port on which the database is running
#   DATABASE:     Your database
#   USERNAME:     Your username
#   PASSWORD:     Your password
#   CORE_PATH:    Your path to core's directory (OPTIONAL: Use if you want to apply remaining core updates automatically)
#   MYSQL:        Your mysql command (usually mysql)
#
####################################################################################################

## Define the host on which the mangos database resides (typically localhost)
DB_HOST="localhost"

## Define the port on which the mangos database is running (typically 3306)
DB_PORT="3306"

## Define the database in which you want to add clean TBC-DB
DATABASE="tbcmangos"

## Define your username
USERNAME="mangos"

## Define your password (It is suggested to restrict read access to this file!)
PASSWORD="mangos"

## Define the path to your core's folder
##   If set the core updates located under sql/updates from this mangos-directory will be added automatically
CORE_PATH=""

## Define your mysql programm if this differs
MYSQL="mysql"

## Define if you want to wait a bit before applying the full database
FORCE_WAIT="YES"

## Define if the 'locales' directory for processing localization/multi-language SQL files needs to be used
##   Set the variable to "YES" to use the locales directory
LOCALES="YES"

## Define if the 'dev' directory for processing development SQL files needs to be used
##   Set the variable to "YES" to use the dev directory
DEV_UPDATES="NO"

## Define if AHBot SQL updates need to be applied (by default, assume the core is built without AHBot)
## Requires CORE_PATH to be set to a proper value. Set the variable to "YES" to import SQL updates.
AHBOT="NO"

# Enjoy using the tool
EOF
}

function display_help {
echo
echo "Welcome to the TBC-DB helper $SCRIPT_FILE"
echo
echo "Run this tool from a bash compatible terminal (on windows like Git Bash)"
echo
echo "To configure edit the file $CONFIG_FILE"
echo
}

# Check if config file present
if [ ! -f $CONFIG_FILE ]
then
  create_config
  display_help
  exit 1
fi

. $CONFIG_FILE
export MYSQL_PWD="$PASSWORD"
MYSQL_COMMAND="$MYSQL -h$DB_HOST -P$DB_PORT -u$USERNAME $DATABASE"

## Print header
echo
echo "Welcome to the TBC-DB helper $SCRIPT_FILE"
echo

if [ "$FORCE_WAIT" != "NO" ]
then
  echo "ATTENTION: Your database $DATABASE will be reset to TBC-DB!"
  echo "Please bring your repositories up-to-date!"
  echo "Press CTRL+C to exit"
  # show a mini progress bar
  for i in {1..10}
  do
   echo -ne .
   sleep 1
  done
  echo .
fi

## Full Database
echo "> Processing TBC database $DB_TITLE ..."
echo "  - Unziping $FULLDB_FILE_ZIP"
gzip -kdf "${ADDITIONAL_PATH}Full_DB/$FULLDB_FILE_ZIP"
if [[ $? != 0 ]]
then
  echo "ERROR: cannot unzip ${ADDITIONAL_PATH}Full_DB/$FULLDB_FILE_ZIP"
  echo "GZIP 1.6 or greater should be installed"
  exit 1
fi
echo "  - Applying $FULLDB_FILE"
$MYSQL_COMMAND < "${ADDITIONAL_PATH}Full_DB/$FULLDB_FILE"
if [[ $? != 0 ]]
then
  echo "ERROR: cannot apply ${ADDITIONAL_PATH}Full_DB/$FULLDB_FILE"
  exit 1
fi
echo "  $DB_TITLE is applied!"
echo
echo

## Updates
echo "> Processing database updates ..."
COUNT=0
for UPDATE in "${ADDITIONAL_PATH}Updates/"[0-9]*.sql
do
  if [ -e "$UPDATE" ]
  then
    echo "    Appending $UPDATE"
    $MYSQL_COMMAND < "$UPDATE"
    if [[ $? != 0 ]]
    then
      echo "ERROR: cannot apply $UPDATE"
      exit 1
    fi
    ((COUNT++))
  fi
done
if [ "$COUNT" != 0 ]
then
  echo "  $COUNT DB updates applied successfully"
else
  echo "  Did not find any new DB update to apply"
fi
echo
echo

## Instances
echo "> Processing instance files ..."
COUNT=0
for INSTANCE in "${ADDITIONAL_PATH}Updates/Instances/"[0-9]*.sql
do
  if [ -e "$INSTANCE" ]
  then
    echo "    Appending $INSTANCE"
    $MYSQL_COMMAND < "$INSTANCE"
    if [[ $? != 0 ]]
    then
      echo "ERROR: cannot apply $INSTANCE"
      exit 1
    fi
    ((COUNT++))
  fi
done
if [ "$COUNT" != 0 ]
then
  echo "  $COUNT Instance files applied successfully"
else
  echo "  Did not find any instance file to apply"
fi
echo
echo

#
#               Core updates
#

echo "> Trying to retrieve last core update packaged in database ..."
LAST_CORE_REV=0
CORE_REVS="$(grep -r "^.*required_s[0-9]*.* DEFAULT NULL" ${ADDITIONAL_PATH}Full_DB/* | sed 's/.*required_s\([0-9]*\).*/\1/') "
CORE_REVS+=$(grep -ri '.*alter table.*required_s' ${ADDITIONAL_PATH}Updates/* | sed 's/.*required_s\([0-9]*\).*required_s\([0-9]*\).*/\1 \2/')
if [ "$CORE_REVS" != "" ]
then
  for rev in $CORE_REVS
  do
    if [ "$rev" -gt "$LAST_CORE_REV" ]
    then
      LAST_CORE_REV=$rev
    fi
  done
fi

if [ "$LAST_CORE_REV" -eq "0" ]
then
  echo "ERROR: cannot get last core revision in DB"
  exit 1
else
  echo "  Found last core revision in DB is $LAST_CORE_REV"
fi
echo
echo

# process future release folders
if [ "$CORE_PATH" != "" ]
then
  if [ ! -e $CORE_PATH ]
  then
    echo "Path to core provided, but directory not found! $CORE_PATH"
    exit 1
  fi
  UPD_PROCESSED=0
  UPD_FOUND=0

  for NEXT_MILESTONE in ${NEXT_MILESTONES};
  do
    # A new milestone was released, apply additional updates
    if [ -e ${CORE_PATH}/sql/updates/${NEXT_MILESTONE}/ ]
    then
      echo "> Trying to apply core updates from milestone $NEXT_MILESTONE ..."
      for f in "${CORE_PATH}/sql/archives/${NEXT_MILESTONE}/"s*_mangos_*.sql
      do
        CUR_REV=$(basename $f | sed 's/^s\([0-9]*\)_.*/\1/')
        if [ "$CUR_REV" -gt "$LAST_CORE_REV" ]
        then
          # found a newer core update file
          echo "    Appending core update `basename $f` to database $DATABASE"
          $MYSQL_COMMAND < $f
          if [[ $? != 0 ]]
          then
            echo "ERROR: cannot apply $f"
            exit 1
          fi
          ((UPD_PROCESSED++))
        else
          ((UPD_FOUND++))
        fi
      done
    fi
  done

  # Apply remaining files from main folder
  echo "> Trying to apply additional core updates from path $CORE_PATH ..."
  for f in "$CORE_PATH/sql/updates/mangos/"*_mangos_*.sql
  do
    CUR_REV=$(basename "$f" | sed 's/^s\([0-9]*\).*/\1/')
    if [ "$CUR_REV" -gt "$LAST_CORE_REV" ]
    then
      # found a newer core update file
      echo "    Appending core update `basename $f` to database $DATABASE"
      $MYSQL_COMMAND < $f
      if [[ $? != 0 ]]
      then
        echo "ERROR: cannot apply $f"
        exit 1
      fi
      ((UPD_PROCESSED++))
    else
      ((UPD_FOUND++))
    fi
  done
  echo "  CORE UPDATE PROCESSED: $UPD_PROCESSED"
  echo "  CORE UPDATE FOUND BUT ALREADY IN DB: $UPD_FOUND"
  echo
  echo
  
  # Apply optional AHBot commands documentation
  if [ "$AHBOT" == "YES" ]
  then
	  echo "> Trying to apply $CORE_PATH/sql/base/ahbot ..."
	  for f in "$CORE_PATH/sql/base/ahbot/"*.sql
	  do
		echo "    Appending AHBot SQL file `basename $f` to database $DATABASE"
		$MYSQL_COMMAND < $f
		if [[ $? != 0 ]]
		then
		  echo "ERROR: cannot apply $f"
		  exit 1
		fi
	  done
	  echo "  AHBot SQL files successfully applied"
	  echo
	  echo  
  fi

  # Apply dbc folder
  echo "> Trying to apply $CORE_PATH/sql/base/dbc/original_data ..."
  for f in "$CORE_PATH/sql/base/dbc/original_data/"*.sql
  do
    echo "    Appending DBC file update `basename $f` to database $DATABASE"
    $MYSQL_COMMAND < $f
    if [[ $? != 0 ]]
    then
      echo "ERROR: cannot apply $f"
      exit 1
    fi
  done
  echo "  DBC datas successfully applied"
  echo
  echo
  # Apply dbc changes (specific fixes to known wrong/missing data)
  echo "> Trying to apply $CORE_PATH/sql/base/dbc/cmangos_fixes ..."
  for f in "$CORE_PATH/sql/base/dbc/cmangos_fixes/"*.sql
  do
    echo "    Appending CMaNGOS DBC file fixes `basename $f` to database $DATABASE"
    $MYSQL_COMMAND < $f
    if [[ $? != 0 ]]
    then
      echo "ERROR: cannot apply $f"
      exit 1
    fi
  done
  echo "  DBC changes successfully applied"
  echo
  echo

  # Apply ScriptDev2 data
  echo "> Trying to apply $CORE_PATH/sql/scriptdev2 ..."
  for f in "$CORE_PATH/sql/scriptdev2/"*.sql
  do
    echo "    Appending SD2 file update `basename $f` to database $DATABASE"
    $MYSQL_COMMAND < $f
    if [[ $? != 0 ]]
    then
      echo "ERROR: cannot apply $f"
      exit 1
    fi
  done
  echo "  ScriptDev2 data successfully applied"
  echo
  echo
fi

#
#               ACID Full file
#
# Apply acid_tbc.sql
echo "> Trying to apply ${ADDITIONAL_PATH}ACID/acid_tbc.sql ..."
$MYSQL_COMMAND < ${ADDITIONAL_PATH}ACID/acid_tbc.sql
if [[ $? != 0 ]]
then
  echo "ERROR: cannot apply ${ADDITIONAL_PATH}ACID/acid_tbc.sql"
  exit 1
fi
echo "  ACID successfully applied"
echo
echo

#
#               CMaNGOS custom updates file
#
# Apply cmangos_custom.sql
echo "> Trying to apply ${ADDITIONAL_PATH}utilities/cmangos_custom.sql ..."
$MYSQL_COMMAND < ${ADDITIONAL_PATH}utilities/cmangos_custom.sql
if [[ $? != 0 ]]
then
  echo "ERROR: cannot apply ${ADDITIONAL_PATH}utilities/cmangos_custom.sql"
  exit 1
fi
echo "  CMaNGOS custom updates successfully applied"
echo
echo

#
#    LOCALES
#
if [ "$LOCALES" == "YES" ]
then
  echo "> Trying to apply locales data..."
  for UPDATEFILE in ${ADDITIONAL_PATH}locales/*.sql
  do
    if [ -e "$UPDATEFILE" ]
    then
        for UPDATE in ${ADDITIONAL_PATH}locales/*.sql
        do
            echo "    process update $UPDATE"
            $MYSQL_COMMAND < $UPDATE
            [[ $? != 0 ]] && exit 1
        done
        echo "  Locales data applied"
    else
        echo "  No locales data to process"
    fi
    break
  done
fi

#
#    DEVELOPERS UPDATES
#
if [ "$DEV_UPDATES" == "YES" ]
then
  echo "> Trying to apply development updates ..."
  for UPDATEFILE in ${ADDITIONAL_PATH}dev/*.sql
  do
    if [ -e "$UPDATEFILE" ]
    then
        for UPDATE in ${ADDITIONAL_PATH}dev/*.sql
        do
            echo "    process update $UPDATE"
            $MYSQL_COMMAND < $UPDATE
            [[ $? != 0 ]] && exit 1
        done
        echo "  Development updates applied"
    else
        echo "  No development update to process"
    fi
    break
  done
  for UPDATEFILE in ${ADDITIONAL_PATH}dev/*/*.sql
  do
    if [ -e "$UPDATEFILE" ]
    then
        for UPDATE in ${ADDITIONAL_PATH}dev/*/*.sql
        do
            echo "    process update $UPDATE"
            $MYSQL_COMMAND < $UPDATE
            [[ $? != 0 ]] && exit 1
        done
        echo "  Development subupdates applied"
    else
        echo "  No development subupdate to process"
    fi
    break
  done
  echo
  echo
fi

echo "You have now a clean and recent TBC-DB database loaded into $DATABASE"
echo "Enjoy using TBC-DB"
echo
