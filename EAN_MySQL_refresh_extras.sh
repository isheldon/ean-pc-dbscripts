#!/bin/bash
### Environment ###
STARTTIME=$(date +%s)
#
MYSQL_DIR=/usr/bin/
#MySQL user, password, host (Server)
MYSQL_USER=eanuser
MYSQL_PASS=Passw@rd1
MYSQL_HOST=localhost
MYSQL_DB=eanextras
# home directory of the user (in our case "eanuser")
HOME_DIR=${HOME}
# protocol TCP All, SOCKET Unix only, PIPE Windows only, MEMORY Windows only
MYSQL_PROTOCOL=SOCKET
# 3336 as default,MAC using MAMP is 8889
MYSQL_PORT=3306
## directory under HOME_DIR
FILES_DIR=eanextras

CMD_MYSQL="${MYSQL_DIR}mysql  --local-infile=1 --default-character-set=utf8 --protocol=${MYSQL_PROTOCOL} --port=${MYSQL_PORT} --user=${MYSQL_USER} --password=${MYSQL_PASS} --host=${MYSQL_HOST} --database=${MYSQL_DB}"

### Import files ###
############################################
# the list should match the tables        ##
# created by create_ean_extras.sql script ##
############################################
TABLES=(
airports
countries
regions

openflightsairports
activepropertybusinessmodel
propertyidcrossreference
destinationids
landmark
geonames
)

download_file() {
    file_url=$1
    parts=$2
    ts_not_change=$(wget -t10 -N --server-response --spider ${file_url} 2>&1 | grep "no newer" | wc -l | tr -d ' ')
    if [ "${ts_not_change}" -eq 0 ]; then
        # remote file timestamp changed, download the file
        axel -n ${parts} ${file_url}
    else
        echo "Remote file not changed, ignore downloading"
    fi
}

update_data() {
    tablename=$1
    echo "Updating ($MYSQL_DB.$tablename) with REPLACE option..."
    if [ "$tablename" == "geonames" ]; then
        $CMD_MYSQL --execute="SET SESSION sql_mode = ''; LOAD DATA LOCAL INFILE '$tablename.txt' REPLACE INTO TABLE $tablename CHARACTER SET utf8 FIELDS TERMINATED BY '\t';"
    else
        $CMD_MYSQL --execute="SET SESSION sql_mode = ''; LOAD DATA LOCAL INFILE '$tablename.txt' REPLACE INTO TABLE $tablename CHARACTER SET utf8 FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '\"' IGNORE 1 LINES;"
    fi
    echo "erasing old records from ($tablename)..."
    $CMD_MYSQL --execute="DELETE FROM $tablename WHERE datediff(TimeStamp, now()) < 0;"
}

cd ${HOME_DIR}

echo "Starting at working directory..."
pwd
## create subdirectory if required
if [ ! -d ${FILES_DIR} ]; then
   echo "creating download files directory..."
   mkdir ${FILES_DIR}
fi
## all clear, move into the working directory
cd ${FILES_DIR}

### Download Data ###
for TABLE in ${TABLES[@]}
do
    if [ "${TABLE}" == "airports" ] || [ "${TABLE}" == "countries" ] || [ "${TABLE}" == "regions" ]; then
        download_file http://www.ourairports.com/data/${TABLE}.csv 5 &
    fi

    if [ "${TABLE}" == "openflightsairports" ]; then
        download_file http://sourceforge.net/p/openflights/code/757/tree/openflights/data/airports.dat?format=raw 5 &
    fi

    if [ "${TABLE}" == "activepropertybusinessmodel" ]; then
        download_file http://www.ian.com/affiliatecenter/include/V2/ActivePropertyBusinessModel.zip 5 &
    fi

    if [ "${TABLE}" == "propertyidcrossreference" ]; then
        download_file http://www.ian.com/affiliatecenter/include/PropertyID_Cross_Reference_Report.zip 5 &
    fi

    if [ "${TABLE}" == "destinationids" ]; then
        download_file http://www.ian.com/affiliatecenter/include/v2/Destination_Detail.zip 5 &
    fi

    if [ "${TABLE}" == "landmark" ]; then
        download_file http://www.ian.com/affiliatecenter/include/Landmark.zip 5 &
    fi

    if [ "${TABLE}" == "geonames" ]; then
        download_file http://download.geonames.org/export/dump/allCountries.zip 10 &
    fi
done
wait # until all files are downloaded
echo "downloading files done."

# rename downloaded files to <table_name>.txt
mv airports.csv airports.txt
mv countries.csv countries.txt
mv regions.csv regions.txt
mv -f airports.dat* openflightsairports.txt
unzip -L -o ActivePropertyBusinessModel.zip
unzip -L -o PropertyID_Cross_Reference_Report.zip
mv -f propertyid*.csv propertyidcrossreference.txt
unzip -L -o Destination_Detail.zip
mv -f destination_detail*.txt destinationids.txt
unzip -L -o Landmark.zip
unzip -L -o allCountries.zip
mv -f allcountries.txt geonames.txt

### Update MySQL Data ###
echo "Uploading Data to MySQL..."

for TABLE in ${TABLES[@]}
do
    update_data $TABLE &
done
wait # until all data is updated
echo "Updating done."


echo -e "\n"
echo "Verify database against files..."
### Verify entries in tables against files ###
CMD_MYSQL="${MYSQL_DIR}mysqlshow --count ${MYSQL_DB} --protocol=${MYSQL_PROTOCOL} --port=${MYSQL_PORT} --user=${MYSQL_USER} --password=${MYSQL_PASS} --host=${MYSQL_HOST}"
$CMD_MYSQL

### find the amount of records per datafile
### should match to the amount of database records
echo "+---------------------------------+----------+------------+"
echo "|             File                |       Records         |"
echo "+---------------------------------+----------+------------+"
for TABLE in ${TABLES[@]}
do
   ## records=`head --lines=-1 $FILE.txt | wc -l`
   ## To count the number of output records minus the header
   records=$(($(wc -l $TABLE.txt | awk '{print $1}')-1))
   { printf "|" && printf "%33s" $TABLE && printf "|" && printf "%23d" $records && printf "|\n"; }
done
echo "+---------------------------------+----------+------------+"
echo "Verify done."

echo "script (import_db.sh) done."

## display endtime for the script
ENDTIME=$(date +%s)
secs=$(( $ENDTIME - $STARTTIME ))
h=$(( secs / 3600 ))
m=$(( ( secs / 60 ) % 60 ))
s=$(( secs % 60 ))
printf "total script time: %02d:%02d:%02d\n" $h $m $s

