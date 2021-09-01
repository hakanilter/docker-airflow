#!/usr/bin/env bash

TRY_LOOP="20"

: "${REDIS_HOST:=$REDIS_URL}"
: "${REDIS_PORT:="6379"}"
: "${REDIS_PASSWORD:=""}"

: "${POSTGRES_HOST:=$DB_HOST}"
: "${POSTGRES_PORT:="5432"}"
: "${POSTGRES_USER:=$DB_USER}"
: "${POSTGRES_PASSWORD:=$DB_PASSWORD}"
: "${POSTGRES_DB:=$DB_NAME}"

# Executor
AIRFLOW__CORE__EXECUTOR="LocalExecutor"
: "${AIRFLOW__CORE__EXECUTOR:=${EXECUTOR:-Sequential}Executor}"

export \
  AIRFLOW__WEBSERVER__BASE_URL \
  AIRFLOW__CELERY__BROKER_URL \
  AIRFLOW__CELERY__RESULT_BACKEND \
  AIRFLOW__CORE__EXECUTOR \
  AIRFLOW__CORE__FERNET_KEY \
  AIRFLOW__CORE__LOAD_EXAMPLES \
  AIRFLOW__CORE__SQL_ALCHEMY_CONN

# Change ownership of airflow home and swap user
# Note, this is not done recursively to avoid slow boots when EFS is mounted under airflow home
# chown airflow: ${AIRFLOW_HOME} ${AIRFLOW_HOME}/* ${AIRFLOW_HOME}/efs/dags ${AIRFLOW_HOME}/efs/logs

# Load DAGs exemples (default: Yes)
if [[ -z "$AIRFLOW__CORE__LOAD_EXAMPLES" && "${LOAD_EX:=n}" == n ]]
then
  AIRFLOW__CORE__LOAD_EXAMPLES=False
fi

# Sync dags ands plugins if a remote dags bucket provided
if [[ -z "${REMOTE_DAGS_BUCKET}" ]]; then
  echo "No remote dags bucket provided"
else
  echo "Found a remote dags bucket: ${REMOTE_DAGS_BUCKET}"
  aws s3 sync s3://${REMOTE_DAGS_BUCKET}/dags ${AIRFLOW_HOME}/efs/dags || echo "No dags folder found on the bucket"
  aws s3 sync s3://${REMOTE_DAGS_BUCKET}/plugins ${AIRFLOW_HOME}/plugins || echo "No plugins folder found on the bucket"
  aws s3 cp s3://${REMOTE_DAGS_BUCKET}/requirements.txt /requirements.txt || echo "No requirements file found on the bucket"
  echo "Sync completed"
fi

# Install custom python package if requirements.txt is present
if [ -e "/requirements.txt" ]; then
    su airflow -c "$(which pip) install --user -r /requirements.txt"
fi

if [ -n "$REDIS_PASSWORD" ]; then
    REDIS_PREFIX=:${REDIS_PASSWORD}@
else
    REDIS_PREFIX=
fi

wait_for_port() {
  local name="$1" host="$2" port="$3"
  local j=0
  while ! nc -z "$host" "$port" >/dev/null 2>&1 < /dev/null; do
    j=$((j+1))
    if [ $j -ge $TRY_LOOP ]; then
      echo >&2 "$(date) - $host:$port still not reachable, giving up"
      exit 1
    fi
    echo "$(date) - waiting for $name... $j/$TRY_LOOP"
    sleep 5
  done
}

if [ "$AIRFLOW__CORE__EXECUTOR" != "SequentialExecutor" ]; then
  AIRFLOW__CORE__SQL_ALCHEMY_CONN="postgresql+psycopg2://$POSTGRES_USER:$POSTGRES_PASSWORD@$POSTGRES_HOST:$POSTGRES_PORT/$POSTGRES_DB"
  AIRFLOW__CELERY__RESULT_BACKEND="db+postgresql://$POSTGRES_USER:$POSTGRES_PASSWORD@$POSTGRES_HOST:$POSTGRES_PORT/$POSTGRES_DB"
  wait_for_port "Postgres" "$POSTGRES_HOST" "$POSTGRES_PORT"
fi

if [ "$AIRFLOW__CORE__EXECUTOR" = "CeleryExecutor" ]; then
  AIRFLOW__CORE__SQL_ALCHEMY_CONN="postgresql://$POSTGRES_USER:$POSTGRES_PASSWORD@$POSTGRES_HOST:$POSTGRES_PORT"
  AIRFLOW__CELERY__BROKER_URL="redis://$REDIS_PREFIX$REDIS_HOST:$REDIS_PORT/1"
  wait_for_port "Redis" "$REDIS_HOST" "$REDIS_PORT"
fi

case "$1" in
  webserver)
    echo "Initialising DB..."
    airflow db init || exit
    airflow upgradedb || exit    
    airflow create_user -r Admin -u admin -e admin@example.com -f admin -l user -p admin || exit

    if [ "$AIRFLOW__CORE__EXECUTOR" = "LocalExecutor" ]; then
      # With the "Local" executor it should all run in one container.
      echo "Starting scheduler..."
      airflow scheduler &
    fi
    echo "Running webserver..."
    airflow webserver
    ;;
  worker|scheduler|flower|version)
    # To give the webserver time to run initdb.
    sleep 10
    exec airflow '$@'
    ;;
  cmd)
    airflow -c "${@:2}"
    ;;
  *)
    # The command is something like bash, not an airflow subcommand. Just run it in the right environment.
    exec '$@'
    ;;
esac
