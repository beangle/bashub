<template>
  <component :is="isWujie ? MicroShell : StandaloneShell" />
</template>

<script setup lang="ts">
import { isWujieMicroApp, MicroShell } from '@beangle/ems-app'
import StandaloneShell from '@/components/StandaloneShell.vue'

const isWujie = isWujieMicroApp()
</script>
