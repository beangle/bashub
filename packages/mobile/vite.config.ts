import vue from '@vitejs/plugin-vue'
import { fileURLToPath, URL } from 'node:url'
import { defineConfig, loadEnv } from 'vite'
import Components from 'unplugin-vue-components/vite'
import { VitePWA } from 'vite-plugin-pwa'
import { TDesignResolver } from 'unplugin-vue-components/resolvers'

export default defineConfig(({ mode }) => {
  const repoRoot = fileURLToPath(new URL('../..', import.meta.url))
  const rootEnv = loadEnv(mode, repoRoot, '')
  const localEnv = loadEnv(mode, process.cwd(), '')
  const env = { ...rootEnv, ...localEnv }
  const appBase = env.VITE_APP_BASE || '/m/bashub/'

  return {
    plugins: [
      vue(),
      // TDesign Mobile 组件按需引入（模板里的 <t-*> 自动解析），JS 产物只含实际用到的组件。
      Components({
        resolvers: [TDesignResolver({ library: 'mobile-vue' })],
      }),
      VitePWA({
        // 新版本由页面里的确认框提示刷新，不静默接管。
        registerType: 'prompt',
        injectRegister: false,
        manifest: {
          name: 'BAS 手机监控',
          short_name: 'BAS 监控',
          description: 'BAS 项目监控手机端',
          lang: 'zh-CN',
          start_url: appBase,
          scope: appBase,
          display: 'standalone',
          background_color: '#f5f5f5',
          theme_color: '#0052d9',
          icons: [
            { src: 'icons/icon-192.png', sizes: '192x192', type: 'image/png' },
            { src: 'icons/icon-512.png', sizes: '512x512', type: 'image/png' },
            { src: 'icons/maskable-512.png', sizes: '512x512', type: 'image/png', purpose: 'maskable' },
          ],
        },
        workbox: {
          // 只缓存应用壳；/api 永远走网络，避免缓存登录态和业务数据。
          globPatterns: ['**/*.{js,css,html,png,svg,woff2}'],
          navigateFallback: `${appBase}index.html`,
          navigateFallbackDenylist: [/^\/api\//],
          cleanupOutdatedCaches: true,
        },
        devOptions: { enabled: false },
      }),
    ],
    envDir: repoRoot,
    // 独立手机端站点；部署目录必须与 VITE_APP_BASE 一致。
    base: appBase,
    resolve: {
      alias: { '@': fileURLToPath(new URL('./src', import.meta.url)) },
      dedupe: ['vue', 'vue-router', 'tdesign-vue-next', 'tdesign-icons-vue-next'],
    },
    server: {
      ...(env.VITE_API_BASE
        ? {
            proxy: {
              '/api': {
                target: env.VITE_API_BASE,
                changeOrigin: true,
                configure: (proxy) => {
                  proxy.on('proxyReq', (proxyReq) => {
                    proxyReq.removeHeader('origin')
                  })
                },
              },
            },
          }
        : {}),
    },
    build: {
      chunkSizeWarningLimit: 1400,
      rollupOptions: {
        output: {
          manualChunks(id) {
            if (!id.includes('node_modules')) return
            if (id.includes('tdesign')) return 'tdesign'
            if (id.includes('/vue/') || id.includes('@vue/') || id.includes('vue-router')) return 'vue-vendor'
            return 'vendor'
          },
        },
      },
    },
  }
})
