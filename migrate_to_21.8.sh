source .env
source env/database.env

# Source the Docker Compose utility functions
source "$(dirname "$0")/scripts/docker_compose_utils.sh"

# Store the appropriate docker compose command
DOCKER_COMPOSE_CMD=$(get_docker_compose_cmd)

echo "Take Backup of existing Data in DB"

if [[ -f backup_before_migration.sql ]]; then
        echo "You have already taken the backup before migrations.. rename this file"
else
        docker exec -i xpresso_database_1 mysqldump -uroot -p ${MYSQL_ROOT_PASSWORD} --create-options --add-drop-table --single-transaction  --all-databases  > backup_before_migration.sql
	sleep 1
	rsync data data_v21.3/

fi

echo "Update REDIS password and other configs.."
sleep 2

#first stepto update or add REDIS_AUTH

$DOCKER_COMPOSE_CMD exec -T requests curl -X PATCH -H "Content-Type: application/json" -d '{"CELERY_REDIS_PASSWORD":  "'"$REDIS_PASS"'"}'  http://management:8000/management/api/v1/settings/common

sleep 2

$DOCKER_COMPOSE_CMD exec -T requests curl -X PATCH -H "Content-Type: application/json" -d '{"CELERY_BROKER_PASSWORD": "'"$REDIS_PASS"'"}' http://management:8000/management/api/v1/settings/common

sleep 2

$DOCKER_COMPOSE_CMD exec -T requests  curl -X PATCH -H "Content-Type: application/json" -d '{"REDIS": {"DB":0, "PORT":6379, "password": "'"${REDIS_PASS}"'" ,"PASSWORD": "'"${REDIS_PASS}"'","HOST": "cache"}}' http://management:8000/management/api/v1/settings/common


$DOCKER_COMPOSE_CMD down
$DOCKER_COMPOSE_CMD down

echo  "Waiting for complete shutdown...."

sleep 10

echo "Bringing Database up"

$DOCKER_COMPOSE_CMD up -d database cache elasticsearch

echo "Wait for Database up and running..."

sleep 50


$DOCKER_COMPOSE_CMD up -d management


echo "Wait for management to be Up..."

sleep  60

echo "Bringing up all remaining ones..."
$DOCKER_COMPOSE_CMD up -d


echo "Wait for all services to be UP ...."

sleep 150


echo "Migrate data from old results.."

$DOCKER_COMPOSE_CMD exec -T results2 curl -L -X GET http://results2:8000/results/api/v1/results?limit=9999999  --output /s3/logs/output.json

if [[ -f ./logs/results2/output.json ]]; then

      sleep 2

      cp migration_scripts/generate_mapping.py  ./logs/results2/

      echo "continue..."

      $DOCKER_COMPOSE_CMD exec -T results2  python /s3/logs/generate_mapping.py /s3/logs/output.json

      sleep 5 

      if [[ -f ./logs/results2/mapping.json ]]; then
              cp ./logs/results2/mapping.json ./logs/requests/
	      echo "Migrate old data in requests...."
              $DOCKER_COMPOSE_CMD exec -T requests python manage.py shell --command="from request_result_migration import *;migrate();update_elastic()"
      else
              echo "Mapping file not created"
              exit
      fi

else
        echo "Output not generated"

fi

echo "Migrate old data in resources..."
sleep 10 

cp migration_scripts/migrate_resources.sh ./logs/resources/
$DOCKER_COMPOSE_CMD exec -T resources cp /s3/logs/migrate_resources.sh .
$DOCKER_COMPOSE_CMD exec -T resources bash ./migrate_resources.sh

sleep 5 

$DOCKER_COMPOSE_CMD exec -T cache redis-cli -a ${REDIS_PASS} flushall
