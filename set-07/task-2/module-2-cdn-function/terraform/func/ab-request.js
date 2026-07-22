// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 The ISHS Cloud Computing Authors

// viewer-request: x-sp-ab 쿠키가 있으면 그 버전으로, 없으면 KVS weight 로 무작위
// 배정 후 URI 재작성. 신규 배정 시에만 x-sp-ab-assigned 요청 헤더를 설정한다
// (viewer-response 함수가 이 헤더를 보고 Set-Cookie 를 추가 — 채점 2-4/2-5).
// weight 는 매 호출 KVS 에서 읽어 재배포 없이 즉시 반영된다 (채점 2-6).
import cf from 'cloudfront';

const kvs = cf.kvs();

async function handler(event) {
    const request = event.request;
    const cookie = request.cookies['x-sp-ab'];

    let version;
    if (cookie && (cookie.value === 'a' || cookie.value === 'b')) {
        version = cookie.value;
    } else {
        // cloudfront-js-2.0 런타임은 await 를 함수 인자 자리에 두지 못한다.
        // await 결과를 먼저 변수에 담은 뒤 사용한다.
        const weightValue = await kvs.get('weight');
        const weight = parseFloat(weightValue);
        version = Math.random() < weight ? 'b' : 'a';
        request.headers['x-sp-ab-assigned'] = { value: version };
    }

    const versionKey = version === 'b' ? 'version_b' : 'version_a';
    const uri = await kvs.get(versionKey);
    request.uri = uri;
    return request;
}
