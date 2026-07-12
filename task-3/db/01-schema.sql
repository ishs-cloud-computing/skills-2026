-- 과제지 SQL 그대로 (수정 금지). 직결 엔드포인트로 적재 — db/README.md 참고.
CREATE TABLE user (
    id VARCHAR(255) NOT NULL,
    username VARCHAR(255) NOT NULL,
    email VARCHAR(255) NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uk_username (username)
);
CREATE TABLE product (
    id VARCHAR(255) NOT NULL,
    name VARCHAR(255) NOT NULL,
    price FLOAT(8) NOT NULL,
    image_path VARCHAR(500) DEFAULT NULL,
    PRIMARY KEY (id)
);
