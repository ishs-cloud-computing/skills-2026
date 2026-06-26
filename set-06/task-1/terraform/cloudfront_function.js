// 요구사항 12: URL 에 확장자가 없는 경우 index.html 로 자동 라우팅.
// (정적 콘텐츠는 S3 버킷 루트에 있으므로 항상 /index.html 로 rewrite)
// CloudFront 기본 동작(S3)에만 viewer-request 로 연결한다.
function handler(event) {
  var request = event.request;
  var uri = request.uri;

  if (uri === '/') {
    request.uri = '/index.html';
    return request;
  }

  var lastSegment = uri.substring(uri.lastIndexOf('/') + 1);
  if (lastSegment.indexOf('.') === -1) {
    request.uri = '/index.html';
  }
  return request;
}
