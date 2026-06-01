import { defineConfig, loadEnv } from 'vite'
import vue from '@vitejs/plugin-vue'

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '')
  const publicPath = env.VITE_PUBLIC_PATH || '/'

  return {
    plugins: [vue()],
    base: publicPath.endsWith('/') ? publicPath : `${publicPath}/`,
  }
})
