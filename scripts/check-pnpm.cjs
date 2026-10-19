#!/usr/bin/env node

const npmExecPath = process.env.npm_execpath || ''
const userAgent = process.env.npm_config_user_agent || ''

if (!/pnpm/.test(npmExecPath) && !/pnpm/.test(userAgent)) {
  console.error('错误：本仓库仅允许使用 pnpm 管理依赖，请勿使用 npm / yarn。')
  console.error('  安装依赖：pnpm install')
  console.error('  常用命令：pnpm dev:web / pnpm build:web / pnpm run package')
  process.exit(1)
}
