# 사용 가이드

Docker 이미지 실행 후 PostgreSQL을 설정하고 사용하는 상세 가이드.

---

## 1. ROOT 계정(postgres superuser) 설정

### 1-1. 컨테이너 실행 시 비밀번호 설정

PostgreSQL의 기본 superuser는 `postgres`이다. 컨테이너 실행 시 `POSTGRES_PASSWORD` 환경변수로 반드시 비밀번호를 설정해야 한다.

**docker run**

```shell
docker run -d \
  --restart=unless-stopped \
  -p 5432:5432 \
  -e POSTGRES_PASSWORD=my_secure_password \
  --name postgres \
  knw1234/postgres
```

**docker-compose.yml**

```yaml
services:
  postgres:
    image: knw1234/postgres
    environment:
      POSTGRES_PASSWORD: my_secure_password
```

> **주의**: `POSTGRES_PASSWORD`를 설정하지 않으면 컨테이너가 실행되지 않는다.

### 1-2. 컨테이너에 접속

```shell
# psql 클라이언트로 직접 접속
docker exec -it postgres psql -U postgres

# 특정 데이터베이스에 직접 접속
docker exec -it postgres psql -U postgres -d myapp
```

### 1-3. superuser 비밀번호 변경

이미 실행 중인 컨테이너에서 비밀번호를 변경할 때:

```sql
ALTER USER postgres WITH PASSWORD 'new_secure_password';
```

---

## 2. 데이터베이스 생성 및 사용자 관리

> **예시 네이밍**: 아래 예시에서는 사용자와 데이터베이스를 구분하기 위해 서로 다른 이름을 사용한다.
> - 사용자(ROLE): `app_user`
> - 데이터베이스: `myapp`

### 2-1. 사용자(ROLE) 생성

```sql
-- 비밀번호를 가진 일반 사용자 생성
CREATE USER app_user WITH PASSWORD 'app_password';

-- 옵션: 데이터베이스 생성 권한 부여 (필요한 경우)
CREATE USER app_user WITH PASSWORD 'app_password' CREATEDB;
```

### 2-2. 데이터베이스 생성

```sql
-- 사용자를 소유자로 지정하여 데이터베이스 생성
CREATE DATABASE myapp
    OWNER app_user
    ENCODING 'UTF8';
```

이 이미지는 Dockerfile의 `POSTGRES_INITDB_ARGS`로 클러스터 기본 locale이 `ko_KR.UTF-8`로 설정되어 있다.
`LC_COLLATE`와 `LC_CTYPE`을 별도로 지정하지 않아도 한글 가나다 순 정렬이 기본 적용된다.

**COLLATE 동작 확인**

```sql
-- 클러스터 기본 locale 확인
SELECT datcollate, datctype FROM pg_database WHERE datname = 'template0';
-- 결과: ko_KR.UTF-8, ko_KR.UTF-8

-- 생성된 데이터베이스의 locale 확인
SELECT datcollate, datctype FROM pg_database WHERE datname = 'myapp';
-- 결과: ko_KR.UTF-8, ko_KR.UTF-8
```

> **참고**: 이 이미지의 `init.sql`은 `template1`에 pg_bigm, pg_trgm, citext, pg_stat_statements를 미리 설치한다.
> `CREATE DATABASE`로 생성한 모든 데이터베이스에 이 확장들이 자동으로 포함된다.

### 2-3. 데이터베이스 권한 부여

```sql
-- 데이터베이스 전체 권한 부여
GRANT ALL PRIVILEGES ON DATABASE myapp TO app_user;
```

### 2-4. PostgreSQL 15+ public 스키마 권한 문제

PostgreSQL 15부터 `public` 스키마에 대한 기본 권한 정책이 변경되었다.
이전에는 모든 사용자가 `public` 스키마에 객체를 생성할 수 있었지만,
15부터는 데이터베이스 소유자만 가능하다.

사용자가 `public` 스키마에 테이블을 생성하려면 명시적으로 권한을 부여해야 한다:

```sql
-- 해당 데이터베이스로 전환 후 실행
\c myapp

GRANT ALL ON SCHEMA public TO app_user;
```

**전체 설정 흐름 (postgres superuser로 실행)**

```sql
-- 1. 사용자 생성
CREATE USER app_user WITH PASSWORD 'app_password';

-- 2. 데이터베이스 생성
CREATE DATABASE myapp
    OWNER app_user
    ENCODING 'UTF8';

-- 3. 데이터베이스 권한 부여
GRANT ALL PRIVILEGES ON DATABASE myapp TO app_user;

-- 4. public 스키마 권한 부여 (PostgreSQL 15+)
\c myapp
GRANT ALL ON SCHEMA public TO app_user;
```

---

## 3. 스키마 생성 및 디폴트 스키마 지정

### 3-1. 스키마를 왜 사용해야 하는가

PostgreSQL에서 스키마(Schema)는 데이터베이스 안에서 테이블, 뷰, 함수 등 객체를 묶는 **논리적 네임스페이스**이다.

| 목적 | 설명 |
|------|------|
| **논리적 분리** | 하나의 DB 안에서 기능별·모듈별로 테이블을 구분 (`auth.users`, `order.items`) |
| **권한 분리** | 스키마 단위로 접근 권한을 제어하여 보안 경계를 명확히 설정 |
| **네임스페이스 충돌 방지** | 서로 다른 스키마에 같은 이름의 테이블 공존 가능 |
| **멀티테넌시** | 테넌트별 스키마로 완전한 데이터 격리 (`tenant_a.users`, `tenant_b.users`) |
| **마이그레이션 도구 호환** | Flyway, Liquibase 등이 스키마 단위로 마이그레이션 이력 관리 |

기본 스키마인 `public`만 사용하면 테이블이 많아질수록 관리가 어렵고 권한 제어도 복잡해진다.
애플리케이션 스키마를 별도로 만들어 사용하는 것을 권장한다.

### 3-2. 스키마 생성

```sql
-- 해당 데이터베이스로 전환
\c myapp

-- 스키마 생성 (소유자 지정)
CREATE SCHEMA app AUTHORIZATION app_user;

-- 스키마에 대한 권한 부여
GRANT ALL ON SCHEMA app TO app_user;

-- 이후 생성되는 모든 테이블에 대한 권한도 미리 설정
ALTER DEFAULT PRIVILEGES IN SCHEMA app
    GRANT ALL ON TABLES TO app_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA app
    GRANT ALL ON SEQUENCES TO app_user;
```

### 3-3. 디폴트 스키마(search_path) 설정

PostgreSQL은 스키마를 명시하지 않고 테이블을 조회할 때 `search_path`에 지정된 순서로 스키마를 탐색한다.
`search_path`를 설정하면 `app.users` 대신 `users`만으로 조회할 수 있다.

**세션 레벨** (현재 접속에만 적용)

```sql
SET search_path TO app, public;
```

**사용자 레벨** (해당 사용자가 접속할 때마다 자동 적용)

```sql
ALTER USER app_user SET search_path TO app, public;
```

**데이터베이스 레벨** (해당 DB에 접속하는 모든 사용자에게 적용)

```sql
ALTER DATABASE myapp SET search_path TO app, public;
```

> **권장**: 사용자 레벨 설정을 사용하면 애플리케이션 접속 시 별도 설정 없이 스키마가 자동 적용된다.

### 3-4. 설정 확인

```sql
-- 현재 search_path 확인
SHOW search_path;

-- 현재 스키마 확인
SELECT current_schema();

-- 데이터베이스에 존재하는 스키마 목록
SELECT schema_name FROM information_schema.schemata;
```

### 3-5. Spring / JPA에서 스키마 설정

Spring Boot `application.properties` 또는 `application.yml`에서 기본 스키마를 지정할 수 있다.

```properties
# application.properties
spring.datasource.url=jdbc:postgresql://localhost:5432/myapp?currentSchema=app
```

또는 Hibernate 설정으로 지정:

```properties
spring.jpa.properties.hibernate.default_schema=app
```

---

## 전체 설정 예시 (처음부터 끝까지)

```sql
-- [1단계] postgres superuser로 접속
-- docker exec -it postgres psql -U postgres

-- [2단계] 사용자 생성
CREATE USER app_user WITH PASSWORD 'app_password';

-- [3단계] 데이터베이스 생성 (클러스터 기본 ko_KR.UTF-8 자동 적용)
CREATE DATABASE myapp
    OWNER app_user
    ENCODING 'UTF8';

-- [4단계] 데이터베이스 권한 부여
GRANT ALL PRIVILEGES ON DATABASE myapp TO app_user;

-- [5단계] 해당 데이터베이스로 전환
\c myapp

-- [6단계] public 스키마 권한 부여 (PostgreSQL 15+)
GRANT ALL ON SCHEMA public TO app_user;

-- [7단계] 애플리케이션 전용 스키마 생성
CREATE SCHEMA app AUTHORIZATION app_user;
GRANT ALL ON SCHEMA app TO app_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA app GRANT ALL ON TABLES TO app_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA app GRANT ALL ON SEQUENCES TO app_user;

-- [8단계] 사용자의 디폴트 스키마 지정
ALTER USER app_user SET search_path TO app, public;
```

이후 `app_user`로 접속하면 `app` 스키마가 기본 스키마로 자동 적용된다.
