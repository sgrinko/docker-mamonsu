# Based on:
# https://hub.docker.com/_/debian
#
FROM debian:buster-slim

LABEL maintainer="Sergey Grinko <sergey.grinko@gmail.com>"

ENV DEBIAN_RELEASE buster
ENV PG_MAJOR 13
ENV BACKUP_PATH /mnt/pgbak
# version mamonsu
ENV VERSION 2.7.1

# explicitly set user/group IDs
RUN set -eux; \
    groupadd -r postgres --gid=999; \
    useradd -r -g postgres --uid=999 --home-dir=/var/lib/postgresql --shell=/bin/bash postgres; \
    mkdir -p /var/lib/postgresql/data;

RUN apt-get update \
      && apt-get install -y wget gnupg sendemail dumb-init \
      # ... install psql ...
      && echo "deb http://apt.postgresql.org/pub/repos/apt $DEBIAN_RELEASE-pgdg main" > /etc/apt/sources.list.d/pgdg.list \
      && wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - \
      && apt-get update \
      && apt-get install -y postgresql-client-$PG_MAJOR \
      # ... install mamonsu ...
      && wget  https://repo.postgrespro.ru/mamonsu/keys/apt-repo-add.sh \
      && chmod 700 ./apt-repo-add.sh \
      && ./apt-repo-add.sh \
      && apt-get install -y mamonsu \
      && chown -R postgres:postgres /var/log/mamonsu \
      # ... install pg_probackup ...
      && echo "deb [arch=amd64] https://repo.postgrespro.ru/pg_probackup/deb/ $DEBIAN_RELEASE main-$DEBIAN_RELEASE" > /etc/apt/sources.list.d/pg_probackup.list \
      && wget -O - https://repo.postgrespro.ru/pg_probackup/keys/GPG-KEY-PG_PROBACKUP | apt-key add - \
      && apt-get update \
      && apt-get install -y \
           pg-probackup-$PG_MAJOR \
      && mkdir -p $BACKUP_PATH \
      && chown -R postgres:postgres $BACKUP_PATH \
      && chown -R postgres:postgres /etc/mamonsu /var/log/mamonsu \
      # ... cleaning ...
      && rm -rf /etc/mamonsu/* \
      && rm -rf /var/lib/apt/lists/* \
      && apt-get -f install \
      && apt-get -y autoremove \
      && apt-get -y clean \
      && apt-get -y autoclean

COPY ./mamonsu_start.sh /usr/local/bin
COPY ./agent.conf /usr/local/bin/agent.conf.tmpl
COPY ./pg_stat_replication.py /usr/local/bin/pg_stat_replication.py.tmpl
COPY ./pg_partition.py /usr/local/bin/pg_partition.py.tmpl
COPY ./pre.sql /var/lib/postgresql
COPY ./mamonsu_right_add.sql /var/lib/postgresql
COPY ./pg_probackup.py /usr/lib/python3/dist-packages/mamonsu/plugins/system/linux/pg_probackup.py
COPY ./const.py /usr/lib/python3/dist-packages/mamonsu/lib/const.py

RUN chown postgres:postgres /var/lib/postgresql/*.sql \
    && chmod +x /usr/local/bin/*.sh

USER postgres
ENTRYPOINT [ "dumb-init", "/usr/local/bin/mamonsu_start.sh" ]
