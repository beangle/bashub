<template>
  <div class="mobile-metric" :class="`is-${level}`">
    <div class="mobile-metric__head">
      <span class="mobile-metric__label">{{ props.label }}</span>
      <span class="mobile-metric__value">{{ props.value === undefined ? '—' : `${percent}%` }}</span>
    </div>
    <t-progress
      class="mobile-metric__progress"
      :percentage="percent"
      :label="false"
      :stroke-width="6"
      :status="progressStatus"
    />
    <span v-if="props.detail" class="mobile-metric__detail">{{ props.detail }}</span>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import { clampResourcePercent } from '@/monitor-model'

const props = withDefaults(
  defineProps<{
    label: string
    value?: number
    detail?: string
  }>(),
  { value: undefined, detail: '' },
)

const percent = computed(() => clampResourcePercent(props.value))

const level = computed(() => {
  if (props.value === undefined) return 'unknown'
  if (percent.value >= 90) return 'danger'
  if (percent.value >= 80) return 'warning'
  return 'normal'
})

const progressStatus = computed<'active' | 'warning' | 'error'>(() => {
  if (level.value === 'danger') return 'error'
  if (level.value === 'warning') return 'warning'
  return 'active'
})
</script>
