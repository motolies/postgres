# knw1234/postgres ([dockerhub](https://hub.docker.com/r/knw1234/postgres))

MariaDB(`knw1234/mariadb`)에서 PostgreSQL로 전환한 커스텀 이미지.
`my.cnf` 설정을 PostgreSQL 등가 설정으로 매핑하고, 한글+영문 대소문자 무관 검색을 지원하기 위한 확장(pg_trgm, pg_bigm, citext)을 포함한다.

## Quick Start

```shell
docker run -d \
  --restart=unless-stopped \
  -p 5432:5432 \
  -e POSTGRES_PASSWORD=1234 \
  --name postgres \
  knw1234/postgres
```

또는 docker-compose:

```shell
docker compose up -d
```

## 로컬 빌드

```shell
export POSTGRES_VERSION=18
docker build \
  -t knw1234/postgres \
  -t knw1234/postgres:${POSTGRES_VERSION} \
  --build-arg POSTGRES_VERSION=${POSTGRES_VERSION} \
  .
```

---

## MariaDB → PostgreSQL 설정 매핑표

| MariaDB (`my.cnf`)                       | 값                    | PostgreSQL (`postgresql.conf`)  | 값                    | 비고                         |
|------------------------------------------|----------------------|---------------------------------|----------------------|----------------------------|
| `character-set-server`                   | `utf8mb4`            | `client_encoding`               | `UTF8`               | PG Docker 이미지 기본값이 UTF8    |
| `collation-server`                       | `utf8mb4_unicode_ci` | DB 생성 옵션                        | (init.sql)           | DB/컬럼 레벨 설정                |
| `skip-character-set-client-handshake`    | enabled              | N/A                             | -                    | PG는 항상 올바르게 인코딩 협상         |
| `init_connect="SET NAMES utf8mb4;"`      | utf8mb4              | `client_encoding`               | UTF8                 | 설정 파일에서 영구 적용              |
| `port`                                   | 3306                 | `port`                          | 5432                 | 각 RDBMS 표준 포트              |
| `lower_case_table_names`                 | 1                    | 기본 동작                           | -                    | PG는 따옴표 없는 식별자를 자동 소문자 변환  |
| `innodb_buffer_pool_size`                | 2G                   | `shared_buffers`                | 2GB                  | 주 데이터/인덱스 캐시               |
| `max_connections`                        | 2048                 | `max_connections`               | 2048                 | 동일                         |
| `thread_pool_max_threads`                | 2048                 | N/A                             | -                    | PG는 프로세스 모델 → PgBouncer 권장 |
| `thread_handling`                        | pool-of-threads      | N/A                             | -                    | 위와 동일                      |
| `sql_mode`                               | STRICT_...           | 기본 동작                           | -                    | PG는 기본적으로 strict           |
| `default_storage_engine`                 | innodb               | N/A                             | -                    | PG는 단일 스토리지 엔진             |
| `innodb_log_file_size`                   | 50M                  | `max_wal_size`                  | 1GB                  | WAL = redo log 대응          |
| `skip-name-resolve`                      | enabled              | `log_hostname`                  | off                  | DNS 조회 회피                  |
| `max_allowed_packet`                     | 1G                   | N/A                             | -                    | PG TOAST가 자동 처리            |
| `performance_schema`                     | 1                    | `shared_preload_libraries`      | `pg_stat_statements` | 확장 기반 모니터링                 |
| `transaction-isolation`                  | READ-COMMITTED       | `default_transaction_isolation` | `read committed`     | PG 기본값과 동일                 |
| `slow-query-log` + `long_query_time=0.1` | 100ms                | `log_min_duration_statement`    | 100                  | 단위: ms                     |
| `tmp_table_size`                         | 1024M                | `work_mem`                      | 64MB                 | ⚠️ PG는 **연산 단위** 할당        |
| `max_heap_table_size`                    | 1024M                | `temp_buffers`                  | 256MB                | 세션별 임시 테이블                 |
| `table_open_cache`                       | 8192                 | `max_files_per_process`         | 8192                 | 파일 핸들 캐싱                   |
| `innodb_sync_spin_loops`                 | 10                   | `effective_io_concurrency`      | 200                  | I/O 동시성 (SSD 최적화)          |

### PostgreSQL 전용 추가 설정 (MariaDB에 없는 개념)

| 설정                     | 값     | 이유                           |
|------------------------|-------|------------------------------|
| `effective_cache_size` | 6GB   | OS 캐시 포함 가용 메모리 힌트 (쿼리 플래너용) |
| `maintenance_work_mem` | 512MB | VACUUM, CREATE INDEX 메모리     |
| `huge_pages`           | try   | 대용량 shared_buffers 성능 향상     |
| `autovacuum` 관련        | 튜닝값   | MVCC 정리 필수 (MariaDB에는 없음)    |
| `logging_collector`    | on    | 일별 로그 파일 로테이션                |

---

## 포함된 확장 (Extensions)

### pg_bigm - 한글/CJK 2-gram 전문 검색 (v1.2-20250903)

```sql
SELECT * FROM pg_extension WHERE extname = 'pg_bigm';
```

**왜 필요한가**: PostgreSQL에서 한글 검색에는 pg_bigm이 필수다.

| | pg_trgm (3-gram) | pg_bigm (2-gram) |
|---|---|---|
| N-gram 크기 | 3글자 | 2글자 |
| 한글/CJK 지원 | **미지원** | **완전 지원** |
| 1~2글자 검색 | 인덱스 불가 (seq scan) | 인덱스 사용 가능 |
| 지원 연산자 | LIKE, ILIKE, ~, ~* | LIKE만 지원 |

**이유**: UTF-8에서 한글 1글자는 3바이트를 차지한다. pg_trgm의 트라이그램(3글자 단위)은 한글 1글자 = 트라이그램 1개가 되어 실질적으로 한글 2글자 이상의 패턴 검색 인덱스가 불가능하다. pg_bigm의 바이그램(2글자 단위)은 "검색" 같은 2글자 한글 단어도 인덱스로 처리한다.

```sql
-- 인덱스 생성
CREATE INDEX idx_users_name_bigm ON users USING GIN (name gin_bigm_ops);

-- 검색 (GIN 인덱스 자동 사용)
SELECT * FROM users WHERE name LIKE '%검색%';

-- 바이그램 확인
SELECT show_bigm('한글 검색');
-- 결과: {" 한", "한글", "글 ", " 검", "검색", "색 "}
```

### pg_trgm - 영문 ILIKE 및 유사도 검색

```sql
SELECT * FROM pg_extension WHERE extname = 'pg_trgm';
```

- 영문 `ILIKE '%pattern%'` 검색에 GIN 인덱스 사용 가능
- `similarity()`, `word_similarity()` 등 유사도 함수 제공
- 정규식 `~`, `~*` 연산자 인덱싱 지원

```sql
-- GIN 인덱스 생성 (영문 전용 컬럼)
CREATE INDEX idx_users_email_trgm ON users USING GIN (email gin_trgm_ops);

-- 검색
SELECT * FROM users WHERE email ILIKE '%@gmail%';
```

### citext - 대소문자 무관 텍스트 타입

```sql
SELECT * FROM pg_extension WHERE extname = 'citext';
```

- `CITEXT` 타입 컬럼은 `=`, `LIKE`, `UNIQUE` 등 모든 비교 연산이 자동으로 대소문자 무관
- 이메일 주소처럼 항상 대소문자 무관 비교가 필요한 컬럼에 적합

```sql
CREATE TABLE users (
    id    SERIAL PRIMARY KEY,
    email CITEXT NOT NULL UNIQUE  -- 대소문자 구분 없이 중복 체크
);
```

### pg_stat_statements - 쿼리 성능 모니터링

```sql
-- 느린 쿼리 Top 10 조회
SELECT query, calls, mean_exec_time, total_exec_time
FROM pg_stat_statements
ORDER BY mean_exec_time DESC
LIMIT 10;
```

---

## 한글 + 영문 대소문자 무관 검색 가이드

### 문제: 각 확장의 한계

| 방법 | 영문 대소문자 무관 | 한글 인덱스 |
|------|-----------------|-----------|
| pg_trgm + ILIKE | OK | **안 됨** |
| pg_bigm + LIKE | **구분됨** | OK |
| 둘 중 하나만으로는 한글+영문 대소문자 무관을 동시에 해결 불가 |

### 권장 해법: pg_bigm + LOWER() 함수형 인덱스

**한글+영문 컬럼에 대한 통합 권장 패턴**:

```sql
-- 인덱스: LOWER()로 소문자 변환 후 bigm 인덱스 적용
-- 한글은 LOWER()에 영향 없음, 영문은 소문자로 정규화됨
CREATE INDEX idx_users_name_bigm ON users USING GIN (LOWER(name) gin_bigm_ops);
```

```sql
-- 쿼리: 양쪽을 LOWER()로 소문자 변환
-- 한글 검색 → pg_bigm 2-gram 인덱스 활용
-- 영문 검색 → 대소문자 무관 (LOWER로 정규화)
SELECT * FROM users WHERE LOWER(name) LIKE '%홍길동%';       -- 한글
SELECT * FROM users WHERE LOWER(name) LIKE LOWER('%Test%'); -- 영문 대소문자 무관
SELECT * FROM users WHERE LOWER(name) LIKE '%test%';        -- 이미 소문자면 동일
```

### Spring Data JPA 완벽 호환

`findByNameContainingIgnoreCase(String keyword)` 메서드가 생성하는 SQL:
```sql
WHERE LOWER(name) LIKE LOWER(?)
```
이 패턴이 위의 `LOWER(name) gin_bigm_ops` 인덱스와 **정확히 일치**하므로 인덱스가 자동으로 사용된다.

```java
// 아래 메서드는 한글+영문 대소문자 무관 검색을 인덱스와 함께 지원
List<User> findByNameContainingIgnoreCase(String keyword);
```

### Hibernate 6 HQL + Criteria API

```java
// Hibernate 6 HQL: 한글 검색
@Query("SELECT u FROM User u WHERE LOWER(u.name) LIKE LOWER(CONCAT('%', :keyword, '%'))")
List<User> searchByName(@Param("keyword") String keyword);

// Criteria API
CriteriaBuilder cb = em.getCriteriaBuilder();
CriteriaQuery<User> query = cb.createQuery(User.class);
Root<User> root = query.from(User.class);
String pattern = "%" + keyword.toLowerCase() + "%";
query.where(cb.like(cb.lower(root.get("name")), pattern));
```

> **참고**: `ILIKE`는 pg_bigm 인덱스를 사용하지 못한다. 한글+영문 혼합 컬럼에서는 위의 `LOWER()` + `LIKE` 패턴을 사용해야 한다.

### 영문 전용 컬럼은 pg_trgm + ILIKE 유지

영문만 있는 컬럼(예: 코드, 영문 이름)은 pg_trgm + ILIKE가 더 단순하다:

```sql
-- 영문 전용 컬럼: pg_trgm 사용
CREATE INDEX idx_code_trgm ON products USING GIN (code gin_trgm_ops);
WHERE code ILIKE '%ABC%'

-- Hibernate 6 HQL ilike 활용 가능
FROM Product p WHERE p.code ilike :keyword
```

### 인덱스 전략 요약

| 컬럼 내용 | 검색 패턴 | 권장 인덱스 | 쿼리 |
|----------|-----------|-----------|------|
| 한글+영문 혼합 | `%name%` | `GIN (LOWER(col) gin_bigm_ops)` | `LOWER(col) LIKE LOWER(?)` |
| 영문 전용 | `%name%` | `GIN (col gin_trgm_ops)` | `col ILIKE ?` |
| 이메일 등 | 정확 매칭 | `CITEXT` 컬럼 타입 | `col = ?` |
| 접두사만 | `name%` | `(LOWER(col))` B-tree | `LOWER(col) LIKE 'prefix%'` |

---

## Hibernate / Spring Data JPA ILIKE 가이드

### 핵심: MariaDB와 PostgreSQL의 LIKE 동작 차이

|              | MariaDB (utf8mb4_unicode_ci) | PostgreSQL                |
|--------------|------------------------------|---------------------------|
| `LIKE` 기본 동작 | **대소문자 무관**                  | **대소문자 구분**               |
| 대소문자 무관 검색   | 자동 제공                        | `ILIKE` 또는 `LOWER()` 필요   |
| 마이그레이션 위험    | -                            | 기존 `LIKE` 쿼리 결과가 달라질 수 있음 |

> **⚠️ 마이그레이션 주의**: MariaDB에서 `LIKE` 검색이 대소문자 무관하게 동작했다면,
> PostgreSQL로 전환 시 반드시 `ILIKE` 또는 `LOWER()` 패턴으로 변경해야 한다.

### Hibernate 6에서 ILIKE 사용법 (영문 전용 컬럼)

| 방법                  | 코드                                        | 생성 SQL                            |
|---------------------|-------------------------------------------|-----------------------------------|
| **HQL ilike** (권장)  | `WHERE e.name ilike :pattern`             | `WHERE name ILIKE ?`              |
| **Criteria API**    | `HibernateCriteriaBuilder.ilike()`        | `WHERE name ILIKE ?`              |
| **Spring Data JPA** | `findByNameContainingIgnoreCase()`        | `WHERE LOWER(name) LIKE LOWER(?)` |
| **Native Query**    | `@Query(nativeQuery=true, "...ILIKE...")` | `WHERE name ILIKE ?`              |

#### Hibernate 6 HQL (네이티브 ilike 지원)

```java
// Hibernate 6부터 HQL에서 ilike 네이티브 지원 (영문 전용 컬럼)
@Query("SELECT u FROM User u WHERE u.email ilike %:keyword%")
List<User> searchByEmail(@Param("keyword") String keyword);
```

#### Hibernate 6 Criteria API
```java
HibernateCriteriaBuilder cb = session.getCriteriaBuilder();
CriteriaQuery<User> query = cb.createQuery(User.class);
Root<User> root = query.from(User.class);
query.where(cb.ilike(root.get("email"), "%" + keyword + "%"));
```

---

## 주요 아키텍처 차이점

### 1. 프로세스 vs 쓰레드 모델
- **MariaDB**: 쓰레드 풀 (`thread_handling=pool-of-threads`)
- **PostgreSQL**: 프로세스-per-커넥션 모델
- `max_connections=2048`을 유지하되, 프로덕션에서는 **PgBouncer** 사용 강력 권장

### 2. work_mem 주의사항
- **MariaDB** `tmp_table_size=1G`: 커넥션 단위 메모리 제한
- **PostgreSQL** `work_mem=64MB`: **연산(operation) 단위** 할당
- 단일 쿼리가 여러 정렬/해시 연산 수행 시 각각 `work_mem` 사용 → OOM 위험

### 3. VACUUM 필수 (MariaDB에 없는 개념)
- PostgreSQL은 MVCC 방식으로 이전 행 버전을 유지하며, `autovacuum`으로 정리 필요
- MariaDB InnoDB는 내부 purge 쓰레드가 자동 처리하여 별도 관리 불필요
- autovacuum 비활성화 금지

### 4. 식별자 대소문자 처리
- **MariaDB** `lower_case_table_names=1`: 명시적 설정
- **PostgreSQL**: 따옴표 없는 식별자를 기본으로 소문자 변환 (동일 효과)
- **주의**: DDL에서 `"UserTable"` 같이 큰따옴표 사용 시 대소문자 구분 → 사용 금지 권장

---

## 사용법

> [사용가이드](USAGE.md)



## DB 덤프 / 복구

```shell
# 덤프 생성
docker exec postgres pg_dump -U postgres skyscape | gzip > skyscape-$(date +"%Y-%m-%d").sql.gz

# 복구
gunzip < skyscape-2024-01-01.sql.gz | docker exec -i postgres psql -U postgres skyscape
```

---

## CI/CD (GitHub Actions)

`main` 브랜치 push 시 자동 빌드 및 멀티플랫폼 이미지 배포:
- `linux/amd64`, `linux/arm64` 동시 빌드
- DockerHub (`knw1234/postgres`) 및 GHCR (`ghcr.io/motolies/postgres`)에 Push
- `.env`의 `ENV_POSTGRES_VERSION`으로 버전 태그 자동 설정

필요한 GitHub Secrets:
- `DOCKERHUB_TOKEN`: DockerHub 액세스 토큰
- `GHCR_PAT`: GitHub Personal Access Token (`write:packages` 권한)
