// set-06/task-1 설계 문서 사이트 (plan.md §8)
// GitHub Pages 프로젝트 페이지 — site/base 는 저장소 경로 기준
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

export default defineConfig({
  site: 'https://ishs-cloud-computing.github.io',
  base: '/skills-2026',
  integrations: [
    starlight({
      title: 'set-06 / task-1',
      description:
        'EKS(Bottlerocket) + CloudFront 단일 엔드포인트 — 설계 문서·런북',
      defaultLocale: 'root',
      locales: {
        root: { label: '한국어', lang: 'ko' },
      },
      sidebar: [
        // 파일 frontmatter 의 sidebar.order 로 정렬
        { label: '문서', autogenerate: { directory: '.' } },
      ],
      tableOfContents: { minHeadingLevel: 2, maxHeadingLevel: 4 },
    }),
  ],
});
