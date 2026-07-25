// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 The ISHS Cloud Computing Authors

// viewer-response: viewer-request 가 세운 x-sp-ab-assigned 헤더가 있을 때만 Set-Cookie.
// Set-Cookie 는 headers 가 아니라 response.cookies 객체로만 설정 가능 (CloudFront Functions 이벤트 구조).

function handler(event) {
  const response = event.response;
  const assigned = event.request.headers['x-sp-ab-assigned'];

  if (assigned && assigned.value) {
    response.cookies['x-sp-ab'] = {
      value: assigned.value,
      attributes: 'Path=/; Max-Age=86400'
    };
  }

  return response;
}
