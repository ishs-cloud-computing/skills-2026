-- GET /v1/user?email= 인덱스 — 0.2s SLO 성패를 가르는 필수 단계.
-- dump가 DROP/CREATE TABLE을 포함할 수 있으므로 반드시 dump 적재 후에 실행한다.
ALTER TABLE user ADD INDEX idx_email (email);
