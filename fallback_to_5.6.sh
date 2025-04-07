# Source the Docker Compose utility functions
source "$(dirname "$0")/scripts/docker_compose_utils.sh"

# Store the appropriate docker compose command
DOCKER_COMPOSE_CMD=$(get_docker_compose_cmd)

#Pre Step   changes  image of Mysql back to 5.6  in docker-compose.yml

if [ ! -d ./mysql_backup ] 
then
    echo "mysql_backup  dir doesnt exists, You missed  to take up the backup"
    exit 1 
fi

#step 1  Stopping the database  if it is already running
echo " Stop the database if running"
$DOCKER_COMPOSE_CMD stop database

$DOCKER_COMPOSE_CMD rm -f database


#Step 2 Remove the data/mysql/* 
echo "Remove the data from mysql/"
rm  -rf data/mysql/*

#Step 2   Copy the backup data again to  data/mysql
echo "copy the data from backup"
cp -rf mysql_backup/  data/mysql/

#Copy the old configs
echo "Copy old configs"
cp -f old_configs/docker-compose.yml .
cp -f old_configs/nginx.conf ./etc/
cp -f old_configs/1-user.sql initializers/docker-entrypoint-initdb.d/1-user.sql

#start the database container
$DOCKER_COMPOSE_CMD up -d database

echo "Sleeping for 30 seconds"
sleep 30

# Stop the containers 
echo " Stopping all containers" 
$DOCKER_COMPOSE_CMD stop 

echo "********************************************"
echo "Change the  TAG in .env file as v20.6"
echo "After this change  bring up the containers using $DOCKER_COMPOSE_CMD up -d"
