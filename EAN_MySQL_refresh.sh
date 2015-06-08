#!/bin/bash
#########################################################################
## Pre-requisite:                                                      ##
## -> wget                                                             ##
## -> axel (fast download one file using multiple connections          ##
## -> unzip                                                            ##
## -> database client MySQL                                            ##
#########################################################################

### Environment ###
STARTTIME=$(date +%s)
CHKSUM_CMD=md5sum
MYSQL_DIR=/usr/bin/
MYSQL_LOGINPATH=local
#MySQL user, password, host (Server)
MYSQL_USER=eanuser
MYSQL_PASS=Passw@rd1
MYSQL_HOST=localhost
MYSQL_DB=eanprod
# home directory of the user (in our case "eanuser")
HOME_DIR=${HOME}
# protocol TCP All, SOCKET Unix only, PIPE Windows only, MEMORY Windows only
MYSQL_PROTOCOL=SOCKET
# 3336 as default,MAC using MAMP is 8889
MYSQL_PORT=3306
## directory under HOME_DIR
FILES_DIR=eanfiles
## retention period in DAYS for the log of ActivePropertyList changes
LOG_DAYS=30

### Parameters that you may need:
### If you use LOW_PRIORITY, execution of the LOAD DATA statement is delayed until no other clients are reading from the table.
CMD_MYSQL="${MYSQL_DIR}mysql  --local-infile=1 --default-character-set=utf8 --protocol=${MYSQL_PROTOCOL} --port=${MYSQL_PORT} --user=${MYSQL_USER} --password=${MYSQL_PASS} --host=${MYSQL_HOST} --database=${MYSQL_DB}"
# for version 5.6.6+ you will need this line instead to use stored credentials
#CMD_MYSQL="${MYSQL_DIR}mysql --login-path=${MYSQL_LOGINPATH} --local-infile=1 --default-character-set=utf8 --protocol=${MYSQL_PROTOCOL} --port=${MYSQL_PORT} --database=${MYSQL_DB}"

# mysql command to run stored procedure
CMDSP_MYSQL="${MYSQL_DIR}mysql  --default-character-set=utf8 --protocol=${MYSQL_PROTOCOL} --port=${MYSQL_PORT} --user=${MYSQL_USER} --password=${MYSQL_PASS} --host=${MYSQL_HOST} --database=eanprod"
# for version 5.6.6+ you will need this line instead to use stored credentials
#CMDSP_MYSQL="${MYSQL_DIR}mysql --login-path=${MYSQL_LOGINPATH} --default-character-set=utf8 --protocol=${MYSQL_PROTOCOL} --port=${MYSQL_PORT} --database=eanprod"

## Import files ###
#####################################
# the list should match the tables ##
# created by create_ean.sql script ##
#####################################
#LANG=es_ES
FILES=(
ActivePropertyList
AirportCoordinatesList
AliasRegionList
AreaAttractionsList
AttributeList
ChainList
CityCoordinatesList
CountryList
DiningDescriptionList
HotelImageList
NeighborhoodCoordinatesList
ParentRegionList
PointsOfInterestCoordinatesList
PolicyDescriptionList
PropertyAttributeLink
PropertyDescriptionList
PropertyTypeList
RecreationDescriptionList
RegionCenterCoordinatesList
RegionEANHotelIDMapping
RoomTypeList
SpaDescriptionList
WhatToExpectList
#
# minorRev=25 added files
#
PropertyLocationList
PropertyAmenitiesList
PropertyRoomsList
PropertyBusinessAmenitiesList
PropertyNationalRatingsList
PropertyFeesList
PropertyMandatoryFeesList
PropertyRenovationsList
)

download_file() {
    file_url=$1
    ts_not_change=$(wget -t10 -N --server-response --spider ${file_url} 2>&1 | grep "no newer" | wc -l | tr -d ' ')
    if [ "${ts_not_change}" -eq 0 ]; then
        # remote file timestamp changed, download the file
        axel -n 5 ${file_url}
    else
        echo "Remote file not changed, ignore downloading"
    fi
}

temporary_fix_data() {
    # Temporary FIX for "|" inside data
    if [ $FILE = "ActivePropertyList" ] && [ -f "ActivePropertyList.txt" ]; then
       sed -i "s/Off Langata | Karen Road/Off Langata - Karen Road/" ActivePropertyList.txt
    fi
    # Temporary FIX for "|" inside data
    if [ $FILE = "ActivePropertyBusinessModel" ] && [ -f "ActivePropertyBusinessModel.txt" ]; then
       sed -i "s/\"Off Langata | Karen Road\"/Off Langata - Karen Road/" ActivePropertyBusinessModel.txt
    fi
}

update_data() {
    echo "Updating as integrity is ok & checksum change ($CHKSUM_PREV) to ($CHKSUM_NOW) on file ($FILE.txt)..."
    ## table name are lowercase
    tablename=`echo $FILE | tr "[[:upper:]]" "[[:lower:]]"`

    ## checking if working with activepropertybusinessmodel to make a backup of it before changes
    if [ $tablename = "activepropertybusinessmodel" ]; then
        echo "Running a backup of ActivePropertyBusinessModel..."
        $CMDSP_MYSQL --execute="CALL eanprod.sp_log_createcopy();"
        echo "ActivePropertyBusinessModel backup done."
    fi

    ### Update MySQL Data ###
    echo "Uploading ($FILE.txt) to ($MYSQL_DB.$tablename) with REPLACE option..."
    ## if you have limited resources use this line instead to avoid creating the transaction log
    ## you will need to give grant SUPER to the user, for it to work
    ## $CMD_MYSQL --execute="set foreign_key_checks=0; set sql_log_bin=0; set unique_checks=0; LOAD DATA LOCAL INFILE '$FILE.txt' REPLACE INTO TABLE $tablename CHARACTER SET utf8 FIELDS TERMINATED BY '|' IGNORE 1 LINES;"
    $CMD_MYSQL --execute="SET SESSION sql_mode = ''; LOAD DATA LOCAL INFILE '$FILE.txt' REPLACE INTO TABLE $tablename CHARACTER SET utf8 FIELDS TERMINATED BY '|' IGNORE 1 LINES;"
    ## we need to erase the records, NOT updated today
    echo "erasing old records from ($tablename)..."
    $CMD_MYSQL --execute="DELETE FROM $tablename WHERE datediff(TimeStamp, now()) < 0;"

    ## checking if working with activepropertybusinessmodel to fill the changed log table
    if [ $tablename = "activepropertybusinessmodel" ]; then
        echo "Creating log of changes for ActivePropertyBusinessModel..."
        $CMDSP_MYSQL --execute="CALL eanprod.sp_log_addedrecords();"
        $CMDSP_MYSQL --execute="CALL eanprod.sp_log_erasedrecords();"
        $CMDSP_MYSQL --execute="CALL eanprod.sp_log_erase_common();"
        $CMDSP_MYSQL --execute="CALL eanprod.sp_log_erase_deleted();"
        $CMDSP_MYSQL --execute="CALL eanprod.sp_log_changedrecords();"
        ### erase records before retention period
        $CMDSP_MYSQL --execute="DELETE FROM log_activeproperty_changes WHERE TimeStamp < DATE_SUB(NOW(), INTERVAL $LOG_DAYS DAY);"
        echo "Log for ActivePropertyBusinessModel done."
    fi
}

## home where the process will execute
cd ${HOME_DIR}

echo "Starting at working directory..."
pwd
## create subdirectory if required
if [ ! -d ${FILES_DIR} ]; then
   echo "creating download files directory..."
   mkdir ${FILES_DIR}
fi

cd ${FILES_DIR}

### Download Data ###
for FILE in ${FILES[@]}
do
    ## download the files via HTTP (no need for https), using time-stamping, -nd no host directories
    download_file http://www.ian.com/affiliatecenter/include/V2/$FILE.zip &
done
wait # wait untill all files are downloaded
rm *.zip.* # remove temp files
echo "Downloading files done."

### Update Data ###
for FILE in ${FILES[@]}
do
    ## capture the current file checksum
    if [ -e ${FILE}.txt ]; then
        echo "File exist $FILE.txt and using chksum command $CHKSUM_CMD... saving checksum for comparison..."
        CHKSUM_PREV=`$CHKSUM_CMD $FILE.txt | cut -f1 -d' '`
    else
        CHKSUM_PREV=0
    fi
    ## unzip the files, save the exit value to check for errors
    ## BSD does not support same syntax, but there is no need in MAC OS as Linux (unzip -L `find -iname $FILE.zip`)
    unzip -L -o $FILE.zip
    ZIPOUT=$?
    ## rename files to CamelCase format
    mv `echo $FILE | tr \[A-Z\] \[a-z\]`.txt $FILE.txt

    temporary_fix_data

    ## some integrity tests to avoid processing 'bad' files
    CHKSUM_NOW=`$CHKSUM_CMD $FILE.txt | cut -f1 -d' '`

    records=`wc -l < $FILE.txt | tr -d ' '`
    (( records-- ))

    ## check if we need to update or not based on file changed, file contains at least 1x record
    ## file is readeable, file NOT empty, file unzipped w/o errors
    if [ "$ZIPOUT" -eq 0 ] && [ "$CHKSUM_PREV" != "$CHKSUM_NOW" ] && [ "$records" -gt 0 ] && [ -s ${FILE}.txt ] && [ -r ${FILE}.txt ]; then
        update_data &
    fi
done
wait # wait until all data is updated
echo "Updates done."

echo "Verify database against files..."
### Verify entries in tables against files ###
CMD_MYSQL="${MYSQL_DIR}mysqlshow --count ${MYSQL_DB} --protocol=${MYSQL_PROTOCOL} --port=${MYSQL_PORT} --user=${MYSQL_USER} --password=${MYSQL_PASS} --host=${MYSQL_HOST}"
# for version 5.6.6+ you will need this line instead to use stored credentials
#CMD_MYSQL="${MYSQL_DIR}mysqlshow --login-path=${MYSQL_LOGINPATH} --count ${MYSQL_DB} --protocol=${MYSQL_PROTOCOL} --port=${MYSQL_PORT} --user=${MYSQL_USER} --password=${MYSQL_PASS} --host=${MYSQL_HOST}"
$CMD_MYSQL

### find the amount of records per datafile
### should match to the amount of database records
echo "+---------------------------------+----------+------------+"
echo "|             File                |       Records         |"
echo "+---------------------------------+----------+------------+"
for FILE in ${FILES[@]}
do
## to count the number of output records minus the header
   records=`wc -l < $FILE.txt | tr -d ' '`
   (( records-- ))
   { printf "|" && printf "%33s" $FILE && printf "|" && printf "%23d" $records && printf "|\n"; }
done
echo "+---------------------------------+----------+------------+"
echo "Verify done."

## display endtime for the script
ENDTIME=$(date +%s)
secs=$(( $ENDTIME - $STARTTIME ))
h=$(( secs / 3600 ))
m=$(( ( secs / 60 ) % 60 ))
s=$(( secs % 60 ))
printf "total script time: %02d:%02d:%02d\n" $h $m $s
echo "script (import_db.sh) done."

