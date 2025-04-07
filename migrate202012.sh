source .env
source env/database.env

# Source the Docker Compose utility functions
source "$(dirname "$0")/scripts/docker_compose_utils.sh"

# Store the appropriate docker compose command
DOCKER_COMPOSE_CMD=$(get_docker_compose_cmd)

if [ -s dump_5.6.sql ]
then 
echo "Migration  is already done"
echo "If you want to fallback to old  database,Please run fallback_to_5.6.sh"
exit 1
fi

# Step 1: dump mysql data
$DOCKER_COMPOSE_CMD exec -T database mysqldump -uroot -p${MYSQL_ROOT_PASSWORD} --create-options --add-drop-table --single-transaction --databases s3_auths s3_cdets s3_communications s3_controller s3_genie s3_groups s3_history s3_jenkinsengine s3_laas s3_labvpn s3_management s3_monitors s3_plugins s3_qmgr s3_registry s3_requests s3_results s3_sessions s3_testbeds s3_topoman s3_users  --skip-comments > dump_5.6.sql

if [ -s dump_5.6.sql ]
then
    echo "Dump file is not empty, continuing migration..."
    # Step 2: stopping database service
    $DOCKER_COMPOSE_CMD stop database
   
    # Step 3:  rm data bases container
    $DOCKER_COMPOSE_CMD rm -f database
    
    # Step 4: copy mysql data into a new dir
    echo "Backing up mysql data dir"
    mkdir -p mysql_backup && cp -rf  data/mysql ./mysql_backup/ && docker pull mysql/mysql-server:8.0
    
    #Step 5: remove mysql data dir 
    
    rm -rf data/mysql/*
    
    #Step 6: fix database logs persmission
    chmod -R 777 logs/database
else
    echo "Error: Dump file was empty, Please run the Script again" 
    exit 1
fi

# Step 7: starting database with mysql 8.0
$DOCKER_COMPOSE_CMD up -d database

echo "Sleeping 90 seconds for the database to be up..."
sleep 90

# Step 8: restoring data to mysql 8.0
echo "Restoring MySQL data back to database..."
$DOCKER_COMPOSE_CMD exec -T database mysql -u root -p${MYSQL_ROOT_PASSWORD} < dump_5.6.sql

# Step 9: results migration
docker pull ${DOCKER_REGISTRY}/pyats-web-results:${TAG}
$DOCKER_COMPOSE_CMD stop results results-celery results-beat
sleep 10
$DOCKER_COMPOSE_CMD rm -f results results-celery results-beat
echo "Sleeping 30 seconds for results service to stop"
sleep 30
$DOCKER_COMPOSE_CMD up -d management results
echo "Sleeping 40 seconds for results service to start"
sleep 40
$DOCKER_COMPOSE_CMD exec results python manage.py generate_snapshot
mkdir -p logs/results2 && mv logs/results/result_snapshot.json logs/results2/result_snapshot.json
mv data/archives/cached data/archives/cached_old && mkdir data/archives/cached
echo "Results service migration is done!"

# Step 10: stop all services
$DOCKER_COMPOSE_CMD stop 

# Step 11: pull new images
$DOCKER_COMPOSE_CMD pull 

# sleep a few seconds
sleep 5

# Step 12: start all services
$DOCKER_COMPOSE_CMD up -d

# Step 13: stop old results service
$DOCKER_COMPOSE_CMD stop results results-celery results-beat
$DOCKER_COMPOSE_CMD rm -f results results-celery results-beat

# Step 14: pull pyats-image-builder docker image
docker pull ${DOCKER_REGISTRY}/image-builder:${TAG}
