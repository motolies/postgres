ARG POSTGRES_VERSION=latest
FROM postgres:${POSTGRES_VERSION}

RUN echo "postgres image tag is ${POSTGRES_VERSION}"

# pg_bigm 소스 빌드 (공식 패키지 미포함, 한글/CJK 2-gram 검색용)
# v1.2-20250903: PostgreSQL 18 지원 (최신)
# PG_MAJOR는 공식 postgres 이미지에서 기본 제공하는 환경변수 (예: 18)
# USE_PGXS=1 필수 (pg_bigm 빌드 요구사항)
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        curl make gcc \
        postgresql-server-dev-${PG_MAJOR} \
        libicu-dev \
    && curl -L -o /tmp/pg_bigm.tar.gz \
        https://github.com/pgbigm/pg_bigm/archive/refs/tags/v1.2-20250903.tar.gz \
    && cd /tmp && tar xzf pg_bigm.tar.gz \
    && cd pg_bigm-* && make USE_PGXS=1 && make USE_PGXS=1 install \
    && cd / && rm -rf /tmp/pg_bigm* \
    && apt-get purge -y curl make gcc postgresql-server-dev-${PG_MAJOR} libicu-dev \
    && apt-get autoremove -y && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# 커스텀 PostgreSQL 설정 파일 복사
# PGDATA 내부의 기본 postgresql.conf를 덮어쓰지 않고,
# CMD로 별도 경로의 설정 파일을 지정하는 방식 사용
COPY ./postgresql.conf /etc/postgresql/custom/postgresql.conf

# 초기화 스크립트 복사
# /docker-entrypoint-initdb.d/ 내 스크립트는 DB 최초 생성 시 알파벳 순으로 실행됨
# 01- 접두사로 실행 순서를 명시적으로 지정
COPY ./init.sql /docker-entrypoint-initdb.d/01-init.sql

# 커스텀 설정 파일을 사용하도록 postgres 실행 명령 오버라이드
CMD ["postgres", "-c", "config_file=/etc/postgresql/custom/postgresql.conf"]

ENV POSTGRES_VERSION=$POSTGRES_VERSION
ENV BUILD_TIMESTAMP=$BUILD_TIMESTAMP
