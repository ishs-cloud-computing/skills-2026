-- 과제지 SQL 그대로. 프록시가 아니라 RDS 직결 엔드포인트로 적재한다(README STEP 4).
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
