<template>
  <section class="mobile-page">
    <header class="mobile-page__head">
      <div class="mobile-page__heading">
        <h2 class="mobile-page__title">我的</h2>
      </div>
    </header>

    <section class="mobile-card">
      <header class="mobile-card__head">
        <h3 class="mobile-card__title">当前用户</h3>
      </header>
      <div v-if="currentUser" class="mobile-profile">
        <span class="mobile-profile__avatar">{{ initials(currentUser.name || currentUser.code || '我') }}</span>
        <div>
          <p class="mobile-profile__name">{{ currentUser.name || '未命名用户' }}</p>
          <p class="mobile-profile__code">{{ currentUser.code || '' }}</p>
        </div>
      </div>
      <t-empty v-else description="未登录。" />
      <div class="mobile-actions">
        <t-button v-if="!currentUser" size="small" theme="primary" @click="handleLogin">登录</t-button>
        <t-button v-else size="small" variant="outline" @click="handleLogout()">退出登录</t-button>
      </div>
    </section>

    <section v-if="canInstall && !isStandalone" class="mobile-card">
      <header class="mobile-card__head">
        <h3 class="mobile-card__title">安装到桌面</h3>
      </header>
      <div class="mobile-actions">
        <t-button size="small" theme="primary" @click="installApp">安装</t-button>
      </div>
    </section>

    <section class="mobile-card">
      <header class="mobile-card__head">
        <h3 class="mobile-card__title">PC 控制台</h3>
      </header>
      <a class="mobile-link-button" :href="pcOverviewPath">打开 PC 项目总览</a>
    </section>
  </section>
</template>

<script setup lang="ts">
import { auth } from '@/auth'
import { initials } from '@/monitor-model'
import { canInstall, installApp, isStandalone } from '@/pwa'

const { currentUser, handleLogin, handleLogout } = auth.useAuth()

/** PC 控制台的部署前缀；手机端是独立 SPA，跨应用跳转必须用普通链接。 */
const pcBase = (import.meta.env.VITE_PC_BASE || '/bashub/').replace(/\/+$/, '')
const pcOverviewPath = `${pcBase}/monitor/overview`
</script>
