// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 The ISHS Cloud Computing Authors

// viewer-response: viewer-request 함수가 신규 배정 시 설정한 x-sp-ab-assigned
// 요청 헤더가 있을 때만 Set-Cookie 를 추가한다. 쿠키를 이미 가진 재방문 요청에는
// Set-Cookie 가 없어야 한다 (채점 2-4 no_setcookie / 2-5 second_visit).
function handler(event) {
    const assigned = event.request.headers['x-sp-ab-assigned'];
    const response = event.response;

    if (assigned && (assigned.value === 'a' || assigned.value === 'b')) {
        response.cookies['x-sp-ab'] = {
            value: assigned.value,
            attributes: 'Path=/; Max-Age=86400'
        };
    }

    return response;
}
