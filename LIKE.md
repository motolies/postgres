# 한글 + 영문 대소문자 무관 LIKE 검색 가이드

## 왜 별도 설정이 필요한가

PostgreSQL의 `LIKE`는 **대소문자를 구분**한다. MariaDB에서는 collation(`utf8mb4_unicode_ci`)에 의해 `LIKE`가 자동으로 대소문자 무관하게 동작하지만, PostgreSQL은 그렇지 않다.

|              | MariaDB (`utf8mb4_unicode_ci`) | PostgreSQL              |
|--------------|--------------------------------|-------------------------|
| `LIKE` 기본 동작 | 대소문자 **무관**                    | 대소문자 **구분**             |
| 한글 중간 검색 인덱스 | 가능                             | 확장 없이 불가                |
| 대소문자 무관 검색   | 자동                             | `ILIKE` 또는 `LOWER()` 필요 |

> **⚠️ 마이그레이션 주의**: MariaDB에서 `LIKE '%검색어%'`가 대소문자 무관하게 동작했다면,
> PostgreSQL로 전환 시 반드시 아래 가이드의 패턴으로 교체해야 한다.

---

## 핵심 원리

### 왜 pg_bigm인가 (한글 인덱스)

PostgreSQL에서 `LIKE '%패턴%'` 인덱스는 N-gram 분석 방식을 사용한다.

| 확장      | N-gram | UTF-8 한글 처리                       | 결과                      |
|---------|--------|-----------------------------------|-------------------------|
| pg_trgm | 3-gram | 한글 1글자 = 3바이트 → 트라이그램 1개 = 한글 1글자 | **한글 2글자 검색도 인덱스 불가**   |
| pg_bigm | 2-gram | 한글 2글자 쌍을 토큰으로 인덱싱                | **한글 1글자 이상 모두 인덱스 사용** |

```sql
-- pg_bigm 토큰 확인
SELECT show_bigm('한글 검색');
-- { " 한", "한글", "글 ", " 검", "검색", "색 "}

SELECT show_trgm('한글 검색');
-- {"  한", " 검", " 한글", "검색", "글 ", "한글 "}
-- → 한글 1글자 단위 토큰 = 2글자 검색어도 인덱스 미사용
```

### 왜 LOWER() 함수형 인덱스인가 (영문 대소문자)

pg_bigm은 `LIKE`만 지원하고 `ILIKE`(대소문자 무관 LIKE)는 지원하지 않는다.
대신 **LOWER()로 소문자 정규화**한 값에 인덱스를 걸고, 검색 시에도 LOWER()를 적용하면
동일한 효과를 낼 수 있다.

```
한글: LOWER('홍길동') = '홍길동'  → 변화 없음, bigm 인덱스 그대로 동작
영문: LOWER('Hello') = 'hello'  → 소문자 정규화, 대소문자 무관 검색 가능
```

---

## 인덱스 전략

### 컬럼 유형별 권장 방식

| 컬럼 내용           | 인덱스 타입        | 인덱스 생성                          | 쿼리 패턴                       |
|-----------------|---------------|---------------------------------|-----------------------------|
| **한글+영문 혼합**    | GIN + pg_bigm | `GIN (LOWER(col) gin_bigm_ops)` | `LOWER(col) LIKE LOWER(?)`  |
| **영문 전용**       | GIN + pg_trgm | `GIN (col gin_trgm_ops)`        | `col ILIKE ?`               |
| **이메일 등 항등 비교** | CITEXT 타입     | B-tree (자동)                     | `col = ?`                   |
| **접두사 검색만**     | B-tree        | `(LOWER(col))`                  | `LOWER(col) LIKE 'prefix%'` |

### 1. 한글+영문 혼합 컬럼 (이름, 제목, 내용 등)

```sql
-- 인덱스 생성
CREATE INDEX idx_users_name_bigm
  ON users USING GIN (LOWER(name) gin_bigm_ops);

-- 검색 (GIN 인덱스 자동 사용)
SELECT * FROM users WHERE LOWER(name) LIKE '%홍길동%';         -- 한글 검색
SELECT * FROM users WHERE LOWER(name) LIKE LOWER('%Test%');   -- 영문 대소문자 무관
SELECT * FROM users WHERE LOWER(name) LIKE '%test%';          -- 이미 소문자
```

### 2. 영문 전용 컬럼 (코드, 영문 이름 등)

```sql
-- 인덱스 생성 (pg_trgm, ILIKE 지원)
CREATE INDEX idx_products_code_trgm
  ON products USING GIN (code gin_trgm_ops);

-- 검색
SELECT * FROM products WHERE code ILIKE '%ABC%';
```

### 3. 이메일 등 항등 비교 컬럼

```sql
-- CITEXT 타입: =, LIKE, UNIQUE 모두 대소문자 자동 무관
CREATE TABLE users (
    id    SERIAL PRIMARY KEY,
    email CITEXT NOT NULL UNIQUE,  -- 대소문자 무관 중복 체크 포함
    name  TEXT   NOT NULL
);

-- 검색 (별도 인덱스 없이 자동 대소문자 무관)
SELECT * FROM users WHERE email = 'User@Example.com';  -- 'user@example.com' 과 동일
```

---

## 검색 쿼리 패턴

```sql
-- 한글 단독
WHERE LOWER(name) LIKE '%김철수%'

-- 영문 단독 (한글+영문 혼합 컬럼)
WHERE LOWER(name) LIKE '%kim%'

-- 한글+영문 혼합 검색 (단일 인덱스로 처리)
WHERE LOWER(name) LIKE LOWER('%Kim철수%')

-- 인덱스 사용 여부 확인
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM users WHERE LOWER(name) LIKE '%홍길동%';
```

> **pg_bigm 인덱스 최소 길이**: `bigm_similarity` 함수는 1글자 이상에서 작동한다.
> 단, 1글자 검색은 seq scan이 인덱스보다 빠를 수 있다.

---

## Spring Data JPA 연동

### findByNameContainingIgnoreCase (자동 호환)

Spring Data JPA의 `ContainingIgnoreCase`가 생성하는 SQL:
```sql
WHERE LOWER(name) LIKE LOWER(?)
-- ? = '%검색어%'
```
위 패턴이 `LOWER(name) gin_bigm_ops` 인덱스와 **정확히 일치**하므로 인덱스가 자동으로 사용된다.

```java
public interface UserRepository extends JpaRepository<User, Long> {
    // 한글+영문 대소문자 무관 검색 - 인덱스 자동 사용
    List<User> findByNameContainingIgnoreCase(String keyword);
}
```

### Hibernate 6 HQL

```java
// 한글+영문 혼합 컬럼 (LOWER + LIKE)
@Query("SELECT u FROM User u WHERE LOWER(u.name) LIKE LOWER(CONCAT('%', :keyword, '%'))")
List<User> searchByName(@Param("keyword") String keyword);

// 영문 전용 컬럼 (ILIKE - Hibernate 6에서 네이티브 지원)
@Query("SELECT u FROM User u WHERE u.email ilike %:keyword%")
List<User> searchByEmail(@Param("keyword") String keyword);
```

### Hibernate 6 Criteria API

```java
// 한글+영문 혼합 (LOWER + LIKE)
CriteriaBuilder cb = em.getCriteriaBuilder();
CriteriaQuery<User> query = cb.createQuery(User.class);
Root<User> root = query.from(User.class);
String pattern = "%" + keyword.toLowerCase() + "%";
query.where(cb.like(cb.lower(root.get("name")), pattern));

// 영문 전용 (ilike - HibernateCriteriaBuilder 필요)
HibernateCriteriaBuilder hcb = (HibernateCriteriaBuilder) em.getCriteriaBuilder();
query.where(hcb.ilike(root.get("email"), "%" + keyword + "%"));
```

---

## 주의사항

### ILIKE는 pg_bigm 인덱스를 사용하지 않는다

```sql
-- ❌ 인덱스 미사용 (seq scan)
CREATE INDEX idx_name_bigm ON users USING GIN (name gin_bigm_ops);
WHERE name ILIKE '%홍길동%'

-- ✅ 인덱스 사용
CREATE INDEX idx_name_bigm ON users USING GIN (LOWER(name) gin_bigm_ops);
WHERE LOWER(name) LIKE '%홍길동%'
```

### 인덱스 컬럼과 쿼리 패턴이 정확히 일치해야 한다

```sql
-- 인덱스: LOWER(name)
CREATE INDEX idx ON users USING GIN (LOWER(name) gin_bigm_ops);

-- ✅ 인덱스 사용
WHERE LOWER(name) LIKE '%검색%'

-- ❌ 인덱스 미사용 (표현식 불일치)
WHERE name LIKE '%검색%'
WHERE UPPER(name) LIKE '%검색%'
```

### 한글+영문 혼합 컬럼에서 pg_trgm + ILIKE 조합은 피할 것

```sql
-- ❌ 한글은 인덱스 미사용 (pg_trgm은 한글 비효율)
CREATE INDEX idx ON users USING GIN (name gin_trgm_ops);
WHERE name ILIKE '%홍길동%'

-- ✅ 한글+영문 모두 인덱스 사용
CREATE INDEX idx ON users USING GIN (LOWER(name) gin_bigm_ops);
WHERE LOWER(name) LIKE '%홍길동%'
```

---

## 확장 설치 확인

이 이미지는 컨테이너 최초 시작 시 모든 확장을 자동 설치한다.

```sql
-- 설치된 확장 목록 확인
SELECT extname, extversion FROM pg_extension
WHERE extname IN ('pg_bigm', 'pg_trgm', 'citext', 'pg_stat_statements');
```

신규 DB 생성 시에도 `template1`에 확장이 설치되어 있어 자동 상속된다.

```sql
-- 신규 DB 생성 후 확인
CREATE DATABASE mydb;
\c mydb
SELECT extname FROM pg_extension;  -- pg_bigm, pg_trgm, citext 자동 포함
```
