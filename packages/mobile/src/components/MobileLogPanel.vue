<template>
  <section class="mobile-log">
    <header class="mobile-log__head">
      <div class="mobile-log__heading">
        <h4 class="mobile-log__title">{{ props.title || '日志' }}</h4>
        <p class="mobile-log__meta">
          共 {{ props.total }} 行 · 显示 {{ props.lines.length }} 行
          <span v-if="props.following" class="mobile-log__following">跟随中</span>
          <span v-else-if="props.reconnecting" class="mobile-log__reconnecting">重连中</span>
        </p>
      </div>
      <div class="mobile-log__actions">
        <t-button size="small" variant="outline" :loading="props.loading" @click="emit('read')">
          读取尾部
        </t-button>
        <t-button
          v-if="!props.following"
          size="small"
          variant="outline"
          :disabled="props.loading || !props.canFollow"
          @click="emit('follow')"
        >
          跟随
        </t-button>
        <t-button
          v-else
          size="small"
          theme="danger"
          variant="outline"
          @click="emit('stop')"
        >
          停止
        </t-button>
      </div>
    </header>

    <MobileNotice v-if="props.error" :message="props.error" class="mobile-log__error" />

    <pre class="mobile-log__body">{{ text }}</pre>
  </section>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import MobileNotice from '@/components/MobileNotice.vue'

const props = withDefaults(
  defineProps<{
    title?: string
    lines: string[]
    total: number
    loading?: boolean
    following?: boolean
    reconnecting?: boolean
    error?: string
    canFollow?: boolean
  }>(),
  {
    title: '日志',
    loading: false,
    following: false,
    reconnecting: false,
    error: '',
    canFollow: true,
  },
)

const emit = defineEmits<{
  read: []
  follow: []
  stop: []
}>()

const text = computed(() => (props.lines.length > 0 ? props.lines.join('\n') : '（暂无日志）'))
</script>
