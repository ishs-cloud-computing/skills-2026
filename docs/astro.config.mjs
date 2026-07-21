// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

// https://astro.build/config
export default defineConfig({
	integrations: [
		starlight({
			title: 'skills-2026',
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
					label: "Home",
					"items": [
						{ label: 'Overview', slug:'overview' },
					],
				},
				{
					label: 'Setlist',
					items: [
						// Each item here is one entry in the navigation menu.
						{ label: 'Example Guide', slug: 'guides/example' },
					],
				},
				{
					label: 'Reference',
					items: [{ autogenerate: { directory: 'reference' } }],
				},
			],
		}),
	],
});
