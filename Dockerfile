FROM alpine as postgres
ENV TZ=America/Sao_Paulo
ENV LANG=pt_BR.UTF-8
ENV LANGUAGE pt_BR.UTF-8
ENV LC_ALL pt_BR.UTF-8
ENV POSTGRES_PASSWORD=postgres
ENV POSTGRES_USERNAME=postgres
ENV PGDATA=/var/lib/postgresql
ENV MASTER_PORT=5432
ENV REPLICATION_USERNAME=replicant
ENV REPLICATION_PASSWORD=replicant
ENV MAX_WALL_SENDER=10
ENV SLOT_NAME=master
ENV LOG_STATEMENT=all

COPY entrypoint /usr/bin/
COPY postgres-start /usr/bin/

RUN apk add --no-cache icu-data-full tzdata bash tzdata musl-locales \
    postgresql postgresql-contrib shadow doas curl \
    && cp  /usr/share/zoneinfo/America/Sao_Paulo /etc/localtime \
    && mkdir -p /run/postgresql \
    && chown postgres:postgres -R /var/lib/postgresql /run/postgresql \
    /etc/postgresql \
    && usermod -aG wheel postgres \
    && echo "permit nopass :wheel as root" >> /etc/doas.d/doas.conf

STOPSIGNAL SIGINT
WORKDIR ${PGDATA}

USER postgres
ENTRYPOINT [ "entrypoint" ]
CMD [ "postgres" ]
EXPOSE 5432

FROM postgres as jit
RUN doas apk add --no-cache postgresql-jit
EXPOSE 5432

FROM haproxy:alpine as haproxy
COPY haproxy.cfg /usr/local/etc/haproxy/haproxy.cfg