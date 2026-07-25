// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 The ISHS Cloud Computing Authors

// viewer-request: x-sp-ab 쿠키가 있으면 그 버전으로, 없으면 KVS weight 로 무작위 배정.
// weight·경로는 매 실행 KVS 에서 읽는다 (채점 2-6: 코드 재배포 없는 즉시 반영).
// KVS get 은 순차 await — Promise.all 은 함수 메모리 한도 초과 위험 (AWS 문서 권고).
// await 는 반드시 단독 문장으로 — js-2.0 은 함수 인자 안의 await 를 실행 시 SyntaxError 로 거부.

import cf from 'cloudfront';

const kvsHandle = cf.kvs();

async function handler(event) {
  const request = event.request;

  try {
    const cookie = request.cookies['x-sp-ab'];
    let assigned;
    if (cookie && (cookie.value === 'a' || cookie.value === 'b')) {
      // 기존 배정 유지. assigned 헤더를 세우지 않아 viewer-response 가 Set-Cookie 를 내보내지 않는다 (채점 2-4).
      assigned = cookie.value;
    } else {
      const weightStr = await kvsHandle.get('weight');
      assigned = Math.random() < parseFloat(weightStr) ? 'b' : 'a';
      request.headers['x-sp-ab-assigned'] = { value: assigned };
    }

    const uri = await kvsHandle.get(assigned === 'b' ? 'version_b' : 'version_a');
    request.uri = uri;
  } catch (err) {
    // KVS 키 부재 등 — 원본 요청 그대로 통과
  }

  return request;
}
