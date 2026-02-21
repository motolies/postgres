-- =============================================================================
-- PostgreSQL 초기화 스크립트
-- Docker 컨테이너 최초 시작 시 /docker-entrypoint-initdb.d/ 에서 자동 실행
-- =============================================================================

-- -----------------------------------------------
-- 검색 지원 확장
-- -----------------------------------------------

-- pg_trgm: 트라이그램(3글자 분석) 기반 유사도 검색
-- 영문 ILIKE 및 %pattern% 검색에 GIN 인덱스 사용 가능
-- similarity(), word_similarity() 등 유사도 함수 제공
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- pg_bigm: 바이그램(2글자 분석) 기반 전문 검색
-- 한글/CJK 문자에 특화: UTF-8에서 한글 1글자=3바이트이므로
-- 트라이그램(3-gram)은 한글 1글자만 인덱싱 → 사실상 무용
-- 바이그램(2-gram)은 한글 2글자 쌍을 인덱싱 → 정확한 검색 가능
-- ⚠️ LIKE만 지원 (ILIKE 미지원) - 한글은 대소문자 개념이 없으므로 무관
-- ⚠️ shared_preload_libraries에 등록 필수 (postgresql.conf 설정됨)
CREATE EXTENSION IF NOT EXISTS pg_bigm;

-- citext: 대소문자 무관 텍스트 타입
-- citext 컬럼은 일반 LIKE도 자동으로 대소문자 무관하게 동작
-- 항상 대소문자 무관 비교가 필요한 컬럼 (예: email)에 적합
CREATE EXTENSION IF NOT EXISTS citext;

-- pg_stat_statements: 쿼리 성능 모니터링
-- MariaDB의 performance_schema에 해당
-- postgresql.conf의 shared_preload_libraries와 함께 사용
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- -----------------------------------------------
-- template1에도 확장 설치
-- 이후 CREATE DATABASE로 생성되는 모든 DB에 자동 상속
-- -----------------------------------------------
\c template1

CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS pg_bigm;
CREATE EXTENSION IF NOT EXISTS citext;
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

\c postgres

-- =============================================================================
-- 사용 예시 (필요에 따라 주석 해제)
-- =============================================================================

-- [예시 1] 한글+영문 대소문자 무관 검색 (권장 패턴)
-- LOWER() + gin_bigm_ops 조합: 한글 2-gram 인덱스 + 영문 소문자 정규화
-- Spring Data JPA findByNameContainingIgnoreCase() 와 자동 호환
-- CREATE TABLE users (id SERIAL PRIMARY KEY, name TEXT NOT NULL);
-- CREATE INDEX idx_users_name_bigm ON users USING GIN (LOWER(name) gin_bigm_ops);
-- 검색: WHERE LOWER(name) LIKE LOWER('%검색어%')
-- 검색: WHERE LOWER(name) LIKE '%한글%'

-- [예시 2] 영문만 있는 컬럼 (ILIKE 사용 시 pg_trgm)
-- CREATE INDEX idx_users_email_trgm ON users USING GIN (email gin_trgm_ops);
-- 검색: WHERE email ILIKE '%pattern%'
-- Hibernate 6 HQL: FROM User u WHERE u.email ilike :keyword

-- [예시 3] citext 컬럼 (이메일 등 항상 대소문자 무관 비교가 필요한 경우)
-- CREATE TABLE users (
--     id     SERIAL  PRIMARY KEY,
--     email  CITEXT  NOT NULL UNIQUE,  -- LIKE, =, UNIQUE 모두 대소문자 무관
--     name   TEXT    NOT NULL
-- );

-- [예시 4] 사용자 생성 (MariaDB readme.md의 skyscape 예시 대응)
-- CREATE USER skyscape WITH PASSWORD 'skyscape';
-- CREATE DATABASE skyscape OWNER skyscape ENCODING 'UTF8';
-- GRANT ALL PRIVILEGES ON DATABASE skyscape TO skyscape;
