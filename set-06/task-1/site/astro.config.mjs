// set-06/task-1 설계 문서 사이트 (plan.md §8)
// Netlify 배포 — 루트 도메인 서빙이라 base 불필요. site 는 첫 배포 후 실제 도메인으로 교체
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

export default defineConfig({
  site: 'https://skills-2026-docs.netlify.app',
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
        { label: '설계 개요', link: '/' },
        { label: '런북', autogenerate: { directory: 'runbook' } },
        { label: '설계', autogenerate: { directory: 'design' } },
      ],
      tableOfContents: { minHeadingLevel: 2, maxHeadingLevel: 4 },
    }),
  ],
});
