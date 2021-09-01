FROM python:3.8-slim

# Never prompts the user for choices on installation/configuration of packages
ENV DEBIAN_FRONTEND noninteractive
ENV TERM linux

# Airflow 
ARG AIRFLOW_VERSION=1.10.14
ARG AIRFLOW_HOME=/usr/local/airflow
ARG AIRFLOW_DEPS=""
ARG PYTHON_DEPS=""
ENV AIRFLOW_GPL_UNIDECODE yes
ENV AIRFLOW__WEBSERVER__BASE_URL http://localhost:8080

# Define en_US.
ENV LANGUAGE en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LC_ALL en_US.UTF-8
ENV LC_CTYPE en_US.UTF-8
ENV LC_MESSAGES en_US.UTF-8
ENV AIRFLOW_HOME ${AIRFLOW_HOME}

# Submodules under /efs/ path not picked up by python interpreter must be added.
ENV PYTHONPATH=${AIRFLOW_HOME}/efs/dags:${PYTHONPATH}

RUN set -ex \
    && buildDeps=' \
        freetds-dev \
        libkrb5-dev \
        libsasl2-dev \
        libssl-dev \
        libffi-dev \
        libpq-dev \
        git \
    ' \
    && apt-get update -yqq \
    && apt-get upgrade -yqq \
    && apt-get install -yqq --no-install-recommends \
        $buildDeps \
        freetds-bin \
        build-essential \
        default-libmysqlclient-dev \
        apt-utils \
        curl \
        rsync \
        netcat \
        locales \
    && sed -i 's/^# en_US.UTF-8 UTF-8$/en_US.UTF-8 UTF-8/g' /etc/locale.gen \
    && locale-gen \
    && update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 \
    && useradd -ms /bin/bash -d ${AIRFLOW_HOME} airflow \
    && pip install -U pip setuptools wheel \
    && pip install pytz \
    && pip install pyOpenSSL \
    && pip install ndg-httpsclient \
    && pip install pyasn1 \
    && pip install boto3 \
    && pip install arrow \
    && pip install aanalytics2==0.1.3 \
    && pip install --no-cache-dir apache-airflow[slack,crypto,celery,postgres,hive,jdbc,ssh${AIRFLOW_DEPS:+,}${AIRFLOW_DEPS}]==${AIRFLOW_VERSION} flower WTForms==2.2.1 \
    && pip install 'redis==3.2.0' \
    && if [ -n "${PYTHON_DEPS}" ]; then pip install ${PYTHON_DEPS}; fi \
    && apt-get purge --autoremove -yqq $buildDeps \
    && apt-get autoremove -yqq --purge \
    && apt-get clean \
    && rm -rf \
        /var/lib/apt/lists/* \
        /tmp/* \
        /var/tmp/* \
        /usr/share/man \
        /usr/share/doc \
        /usr/share/doc-base

# Install Rest Plugin
RUN curl -OL https://github.com/beamly/airflow-rest-api-plugin/tarball/8551fac \
    && tar -C ${AIRFLOW_HOME} --strip-components 1 -xzvf 8551fac beamly-airflow-rest-api-plugin-8551fac/plugins/ \
    && rm -fr 8551fac

# Install additional requirements
COPY config/requirements.txt ${AIRFLOW_HOME}/requirements.txt
RUN pip install --upgrade -r ${AIRFLOW_HOME}/requirements.txt \
    && rm -f ${AIRFLOW_HOME}/requirements.txt

# entrypoint dynamically symlinks airflow.cfg at runtime
COPY config/airflow.cfg ${AIRFLOW_HOME}/airflow.cfg
COPY config/webserver_config.py ${AIRFLOW_HOME}/webserver_config.py
COPY config/entrypoint.sh /entrypoint.sh

# Create log directories for local executor
RUN mkdir -pv ${AIRFLOW_HOME}/efs/dags \
    && mkdir -p ${AIRFLOW_HOME}/efs/logs \
    && mkdir -p ${AIRFLOW_HOME}/efs/logs/scheduler \
    && mkdir -p ${AIRFLOW_HOME}/efs/logs/dag_processor_manager \
    && chown -R airflow:airflow ${AIRFLOW_HOME}

EXPOSE 8080 5555 8793

USER airflow
WORKDIR ${AIRFLOW_HOME}
ENTRYPOINT ["/entrypoint.sh"]
CMD ["webserver"] # set default arg for entrypoint
