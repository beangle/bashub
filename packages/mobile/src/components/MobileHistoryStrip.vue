<template>
  <section class="mobile-history">
    <div class="mobile-history__meta">
      <span>可用率 <strong>{{ availabilityText }}</strong></span>
      <span>采样 {{ props.history.sampledDays }} 天</span>
      <span v-if="props.history.lastAt">最近 {{ shortTime(props.history.lastAt) }}</span>
    </div>

    <div class="mobile-history__strip" :aria-label="`最近 ${props.days} 天运行状态`">
      <span
        v-for="cell in props.history.cells"
        :key="cell.date"
        class="mobile-history__cell"
        :class="`is-${cell.state}`"
        :title="`${cell.date} · ${cell.title}`"
      ></span>
    </div>
    <div class="mobile-history__axis">
      <span>{{ props.history.firstDate }}</span>
      <span>{{ props.history.lastDate }}</span>
    </div>

    <ul class="mobile-history__legend">
      <li><i class="is-running"></i>运行</li>
      <li><i class="is-stopped"></i>停止</li>
      <li><i class="is-error"></i>异常</li>
      <li><i class="is-unknown"></i>无采样</li>
    </ul>

    <div v-if="props.history.changes.length > 0" class="mobile-history__changes">
      <span class="mobile-history__changes-title">最近状态变化</span>
      <span
        v-for="change in props.history.changes.slice(0, 6)"
        :key="`${change.at}-${change.state}`"
        class="mobile-history__change"
      >
        {{ shortTime(change.at) }} {{ stateLabel(change.state) }}
      </span>
    </div>
  </section>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import { shortTime, stateLabel, type InstanceHistory } from '@/monitor-model'

const props = defineProps<{
  history: InstanceHistory
  days: number
}>()

const availabilityText = computed(() => {
  if (props.history.total === 0) return '无采样'
  return `${props.history.availability.toFixed(1)}%`
})
</script>
