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
      // TDesign Mobile 组件按需引入（模板里的 <t-*> 自动解析），JS 产物只含实际用到的组件。
      Components({
        resolvers: [TDesignResolver({ library: 'mobile-vue' })],
      }),
    ],
    envDir: repoRoot,
    // 独立手机端站点；部署目录必须与 VITE_APP_BASE 一致。
    base: env.VITE_APP_BASE || '/m/bashub/',
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
