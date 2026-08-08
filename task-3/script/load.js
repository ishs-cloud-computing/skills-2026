// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 The ISHS Cloud Computing Authors

// 대회 전 연습용 부하 스크립트. 당일 런북(README)에는 포함되지 않는다.
//
//   BASE_URL=https://<cloudfront_domain> VUS=20 DURATION=2m k6 run load.js
//   # k6 미설치 시: docker run --rm -i -e BASE_URL=... grafana/k6:2.1.0 run - < load.js
//
// BASE_URL은 반드시 CloudFront(https). ALB를 직접 때리면 WAF·CloudFront 캐시를 건너뛰어
// 채점 경로와 다른 것을 재게 되고, http로 부르면 redirect-to-https의 301을 측정하게 된다.
// 종료 후 정리: DELETE FROM user WHERE username LIKE 'k6-%'; DELETE FROM product WHERE id LIKE 'k6-%';

import http from 'k6/http';
import { check } from 'k6';

const BASE = __ENV.BASE_URL;
if (!BASE) throw new Error('BASE_URL required (예: https://d111111abcdef8.cloudfront.net)');

// 변조 방지 파라미터(task.md 5절). 앱이 어느 쪽을 읽는지 불명확해 쿼리스트링·body 양쪽에 넣는다.
const REQUESTID = '999999999999';
const UUID = '7c5a3c6a-758f-4bc5-9bdf-3e573a0ad729';
const Q = `requestid=${REQUESTID}&uuid=${UUID}`;

export const options = {
  vus: Number(__ENV.VUS || 20),
  duration: __ENV.DURATION || '2m',

  // 채점표를 그대로 옮긴 것. p(90)<200 = "90%가 0.2초 미만" = 채점 3-1/3-9/3-17 만점 조건.
  // 여기서 빨간불이면 당일 그 항목을 못 먹는다는 뜻이다.
  thresholds: {
    'http_req_duration{app:user}': ['p(90)<200'],
    'http_req_duration{app:product}': ['p(90)<200'],
    'http_req_duration{app:stress}': ['p(90)<1000'],
    http_req_failed: ['rate<0.1'], // availability >= 90% (채점 2-1/2-9/2-17)
  },
};

const opts = (app) => ({ tags: { app }, headers: { 'Content-Type': 'application/json' } });

export default function () {
  const id = `k6-${__VU}-${__ITER}`; // user.uk_username·product.PK 충돌 방지 + 정리용 prefix
  const email = `${id}@example.org`;

  let r = http.post(
    `${BASE}/v1/user?${Q}`,
    JSON.stringify({ requestid: REQUESTID, uuid: UUID, username: id, email: email }),
    opts('user'),
  );
  check(r, { 'POST /v1/user → 201': (r) => r.status === 201 });

  r = http.get(`${BASE}/v1/user?email=${email}&${Q}`, opts('user'));
  check(r, { 'GET /v1/user → 200': (r) => r.status === 200 });

  r = http.post(
    `${BASE}/v1/product?${Q}`,
    JSON.stringify({ requestid: REQUESTID, uuid: UUID, id: id, name: id, price: 1234 }),
    opts('product'),
  );
  check(r, { 'POST /v1/product → 201': (r) => r.status === 201 });

  r = http.get(`${BASE}/v1/product?id=${id}&${Q}`, opts('product'));
  check(r, { 'GET /v1/product → 200': (r) => r.status === 200 });

  r = http.post(
    `${BASE}/v1/stress?${Q}`,
    JSON.stringify({ requestid: REQUESTID, uuid: UUID, length: 256 }),
    opts('stress'),
  );
  check(r, { 'POST /v1/stress → 201': (r) => r.status === 201 });
}
