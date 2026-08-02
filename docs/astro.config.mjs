// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 The ISHS Cloud Computing Authors

// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

// https://astro.build/config
export default defineConfig({
	integrations: [
		starlight({
			title: 'skills-2026',
			defaultLocale: "kr",
			customCss: [
				'./src/fonts/font-face.css',
				'@fontsource/ibm-plex-mono/400.css',
				'@fontsource/ibm-plex-mono/700.css',
				'@fontsource/ibm-plex-mono/400-italic.css',
				'@fontsource/ibm-plex-mono/700-italic.css',
				'./src/styles/font.css'
			],
			social: [{ icon: 'github', label: 'GitHub', href: 'https://github.com/ishs-cloud-computing/skills-2026' }],
			sidebar: [
				{
					label: "홈",
					"items": [
						{ label: '개요', slug:'home/overview' },
						{ label: "환경설정", slug:'home/setup'},
					],
				},
				{
					label: '세트 리스트',
					items: [
						{
							label: "2세트",
							items: [
								{ label: "1과제", items: [{ autogenerate: { directory: "setlist/set-02/task-1" } }] },
								{ label: "2과제", items: [{ autogenerate: { directory: "setlist/set-02/task-2" } }] },
							],
						},
						{
							label: "3세트",
							items: [
								{ label: "1과제", items: [{ autogenerate: { directory: "setlist/set-03/task-1" } }] },
							],
						},
						{
							label: "7세트",
							items: [
								{ label: "2과제", items: [{ autogenerate: { directory: "setlist/set-07/task-2" } }] },
							],
						},
						{
							label: "8세트",
							items: [
								{ label: "2과제", items: [{ autogenerate: { directory: "setlist/set-08/task-2" } }] },
							],
						},
					],
				},
				{
					label: '레퍼런스',
					items: [{ autogenerate: { directory: 'reference' } }],
				},
			],
		}),
	],
});
