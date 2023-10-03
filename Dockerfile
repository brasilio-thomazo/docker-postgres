FROM alpine as postgres
ENV UID=1000
ENV GID=1000
ENV TZ=America/Sao_Paulo
ENV LANG=pt_BR.UTF-8
ENV LANGUAGE pt_BR.UTF-8
ENV LC_ALL pt_BR.UTF-8
ENV POSTGRES_PASSWORD=postgres
ENV POSTGRES_USERNAME=postgres

COPY postgresql.conf /etc/postgresql/postgresql.conf
COPY pg_hba.conf /etc/postgresql/pg_hba.conf
COPY entrypoint /usr/bin/entrypoint

RUN apk add --no-cache icu-data-full tzdata bash tzdata musl-locales \
    postgresql postgresql-contrib  \
    && cp  /usr/share/zoneinfo/America/Sao_Paulo /etc/localtime \
    && addgroup -g ${GID} app \
    && adduser -G app -u ${UID} -s /bin/bash -D app \
    && mkdir -p /var/run/postgresql \
    && touch /etc/postgresql/pg_ident.conf \
    && chown app:app -R /var/run/postgresql /var/lib/postgresql \
    /etc/postgresql

WORKDIR /var/lib/postgresql
USER app

CMD [ "entrypoint" ]

FROM postgres as jit
USER root
RUN apk add --no-cache postgresql-jit
USER app

FROM postgres