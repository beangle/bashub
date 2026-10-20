import vue from '@vitejs/plugin-vue'
import { fileURLToPath, URL } from 'node:url'
import { defineConfig, loadEnv } from 'vite'
import Components from 'unplugin-vue-components/vite'
import { TDesignResolver } from 'unplugin-vue-components/resolvers'

export default defineConfig(({ mode }) => {
  const repoRoot = fileURLToPath(new URL('../..', import.meta.url))
  const rootEnv = loadEnv(mode, repoRoot, '')
  const localEnv = loadEnv(mode, process.cwd(), '')
  const env = { ...rootEnv, ...localEnv }

  return {
    plugins: [
      vue(),
      // TDesign 组件按需引入（模板里的 <t-*> 自动解析），JS 产物只含实际用到的组件。
      Components({
        resolvers: [TDesignResolver({ library: 'vue-next' })],
      }),
    ],
    envDir: repoRoot,
    // SPA 由独立的 web 服务器部署，该前缀必须与部署目录一致。
    base: env.VITE_APP_BASE || '/bashub/',
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
      // 路由懒加载后各页面独立 chunk，公共依赖按 tdesign/vue 供应商包拆分。
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
