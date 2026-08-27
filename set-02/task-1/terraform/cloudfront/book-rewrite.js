// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 The ISHS Cloud Computing Authors

// wskorea26-book-rewrite (viewer-request, /book* behavior 전용)
//
// mark 9-1: POST https://<CF>/book 이 book 앱(POST /v1/book 만 서빙)에 도달해야 한다.
// ALB 는 경로 재작성을 지원하지 않으므로 CloudFront Function 에서 URI 를 재작성한다.
// viewer-request 단계의 URI 재작성은 cache behavior 를 다시 매칭하지 않으므로
// 요청은 그대로 wskorea26-alb-origin 으로 전달된다.
//
// GET /book 은 ALB 리스너 규칙에 의해 Lambda TG 로 라우팅되며,
// Lambda 는 경로를 무시하고 쿼리 스트링(concert_name)만 사용하므로 재작성하지 않는다.
function handler(event) {
    var request = event.request;
    if (request.method === 'POST' && request.uri === '/book') {
        request.uri = '/v1/book';
    }
    return request;
}
