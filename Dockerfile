ARG UID=1000
ARG GID=1000
ARG TZ=America/Sao_Paulo
ARG LANG=en_US.uf8
ARG POSTGRES_DOWNLOAD_URL=https://ftp.postgresql.org/pub/source/v16.2/postgresql-16.2.tar.bz2
ARG PG_BOUNCER_DOWNLOAD_URL=https://www.pgbouncer.org/downloads/files/1.22.1/pgbouncer-1.22.1.tar.gz
ARG HAPROXY_DOWNLOAD_URL=https://www.haproxy.org/download/2.9/src/haproxy-2.9.6.tar.gz
ARG LUA_DOWNLOAD_URL=https://www.lua.org/ftp/lua-5.4.6.tar.gz

FROM alpine:latest as base
ARG TZ
ARG LANG
ARG UID
ARG GID

RUN apk add --no-cache tzdata doas musl musl-locales \
	icu-libs readline zlib openssl ossp-uuid-libs libxml2 libxslt \
	&& mkdir -p /var/lib/postgresql/data /etc/postgresql/conf.d \
	/var/run/postgresql /entrypoint.d \
	&& touch /etc/postgresql/pg_ident.conf \
	&& addgroup -g ${UID} postgres \
	&& adduser -D -u ${GID} -G postgres -h /var/lib/postgresql postgres \
	&& adduser postgres wheel \
	&& echo "permit nopass keepenv :wheel as root" > /etc/doas.conf \
	&& chown -R postgres:postgres /var/lib/postgresql /var/run/postgresql \
	/etc/postgresql /entrypoint.d

ENV LANG ${LANG}
ENV TZ ${TZ}
ENV PG_COLOR always


#
# Build postgresql without JIT
#
FROM base as builder
ARG POSTGRES_DOWNLOAD_URL
RUN apk add --no-cache curl build-base icu-dev linux-headers readline-dev zlib-dev \
	openssl-dev ossp-uuid-dev libxml2-dev libxslt-dev \
	&& cd /tmp \
	&& curl -sSL ${POSTGRES_DOWNLOAD_URL} | tar -xjvf - \
	&& mv $(ls -C | grep postgresql) postgresql

WORKDIR /tmp/postgresql
RUN ./configure --prefix=/usr/local --sysconfdir=/etc/postgresql --with-icu --with-openssl --with-uuid=ossp \
	--with-zlib --with-system-tzdata=/usr/share/zoneinfo --with-libxml --with-libxslt \
	&& make clean \
	&& make -j$(nproc) \
	&& make install \
	&& make -C contrib install \
	&& sed -i "s/#unix_socket_directories = .*/unix_socket_directories = '\/var\/run\/postgresql'/" /usr/local/share/postgresql/postgresql.conf.sample

COPY --chown=postgres:postgres src/postgresql.conf /etc/postgresql/postgresql.conf
COPY --chown=postgres:postgres src/pg_hba.conf /etc/postgresql/pg_hba.conf
COPY --chown=postgres:postgres src/server-start.sh /usr/local/bin/server-start
COPY --chown=postgres:postgres  src/entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh /usr/local/bin/server-start

#
# Build postgresql with JIT
#
FROM builder as build_jit
RUN apk add --no-cache llvm17-dev clang17-dev

WORKDIR /tmp/postgresql
RUN ./configure --prefix=/usr/local --sysconfdir=/etc/postgresql --with-icu --with-openssl --with-uuid=ossp \
	--with-zlib --with-system-tzdata=/usr/share/zoneinfo --with-libxml --with-libxslt --with-llvm \
	&& make clean \
	&& make -j$(nproc) \
	&& make install \
	&& make -j$(nproc) -C contrib install \
	&& sed -i "s/#unix_socket_directories = .*/unix_socket_directories = '\/var\/run\/postgresql'/" /usr/local/share/postgresql/postgresql.conf.sample

#
# Image postgresql with JIT
#
FROM base as jit
ENV PGDATA /var/lib/postgresql/data
ENV POSTGRES_PORT 5432
WORKDIR /var/lib/postgresql/data
COPY --from=build_jit /usr/local /usr/local
COPY --from=build_jit /etc/postgresql /etc/postgresql
COPY --from=build_jit /entrypoint.sh /entrypoint.sh
RUN apk add --no-cache llvm17-libs clang17-libs 
USER postgres
ENTRYPOINT ["/entrypoint.sh"]
CMD ["server-start"]
EXPOSE 5432


#
# Image postgresql without JIT
#
FROM base as default
ENV PGDATA /var/lib/postgresql/data
ENV POSTGRES_PORT 5432
WORKDIR /var/lib/postgresql/data
COPY --from=builder /usr/local /usr/local
COPY --from=builder /etc/postgresql /etc/postgresql
COPY --from=builder /entrypoint.sh /entrypoint.sh
USER postgres
ENTRYPOINT ["/entrypoint.sh"]
CMD ["server-start"]
EXPOSE 5432