<script setup>
const features = [
  'Vue 3 Composition API',
  'Vite development server',
  'Ready for Jenkins builds',
]
</script>

<template>
  <main class="app-shell">
    <section class="hero">
      <p class="eyebrow">Vue 3 Project</p>
      <h1>jenkins-test-pro</h1>
      <p class="intro">
        A clean Vue 3 starter is ready. Edit <code>src/App.vue</code> to begin building.
      </p>

      <div class="actions">
        <a href="https://vuejs.org/" target="_blank" rel="noreferrer">Vue Docs</a>
        <a href="https://vitejs.dev/" target="_blank" rel="noreferrer">Vite Docs</a>
      </div>
    </section>

    <section class="feature-grid" aria-label="Project features">
      <article v-for="feature in features" :key="feature">
        {{ feature }}
      </article>
    </section>
  </main>
</template>
