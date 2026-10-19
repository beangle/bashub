#!/usr/bin/env node
/**
 * 跨平台打包助手：把当前目录的 dist 压缩为指定路径的 zip。
 * 用法：node scripts/zip-dist.mjs <输出相对路径>
 */
import { ZipArchive } from 'archiver'
import { createWriteStream, existsSync, mkdirSync, rmSync } from 'node:fs'
import { dirname, resolve } from 'node:path'

const outputPath = process.argv[2]
if (!outputPath) {
  console.error('用法：node scripts/zip-dist.mjs <输出相对路径>')
  process.exit(1)
}

const distDir = resolve('dist')
if (!existsSync(distDir)) {
  console.error(`未找到 ${distDir}，请先执行 pnpm run build`)
  process.exit(1)
}

const zipPath = resolve(outputPath)
rmSync(zipPath, { force: true })
mkdirSync(dirname(zipPath), { recursive: true })

await new Promise((resolveDone, reject) => {
  const output = createWriteStream(zipPath)
  const archive = new ZipArchive({ zlib: { level: 9 } })
  output.on('close', resolveDone)
  archive.on('error', reject)
  archive.pipe(output)
  archive.directory(distDir, false)
  void archive.finalize()
})

console.log(`==> 已生成 ${zipPath}`)
