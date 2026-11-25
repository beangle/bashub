<template>
  <p v-if="message" class="mobile-notice" :class="`is-${theme}`">{{ message }}</p>
</template>

<script setup lang="ts">
withDefaults(
  defineProps<{
    message: string
    theme?: 'error' | 'success' | 'warning' | 'info'
  }>(),
  { theme: 'error' },
)
</script>
