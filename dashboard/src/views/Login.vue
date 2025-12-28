<script setup lang="ts">
import { ref, reactive } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { ElMessage } from 'element-plus'
import { User, Lock } from '@element-plus/icons-vue'

const router = useRouter()
const authStore = useAuthStore()

const form = reactive({
  username: '',
  password: '',
})

const loading = ref(false)

async function handleLogin() {
  if (!form.username || !form.password) {
    ElMessage.warning('Please enter username and password')
    return
  }

  loading.value = true
  try {
    await authStore.login(form.username, form.password)
    ElMessage.success('Login successful')
    router.push('/dashboard')
  } catch (error) {
    ElMessage.error('Login failed. Please check your credentials.')
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <div class="login-container">
    <el-card class="login-card">
      <template #header>
        <div class="login-header">
          <img src="/vite.svg" alt="Logo" class="login-logo" />
          <h2>zigQuant Dashboard</h2>
        </div>
      </template>

      <el-form
        :model="form"
        @submit.prevent="handleLogin"
        class="login-form"
      >
        <el-form-item>
          <el-input
            v-model="form.username"
            placeholder="Username"
            :prefix-icon="User"
            size="large"
          />
        </el-form-item>

        <el-form-item>
          <el-input
            v-model="form.password"
            type="password"
            placeholder="Password"
            :prefix-icon="Lock"
            size="large"
            show-password
          />
        </el-form-item>

        <el-form-item>
          <el-button
            type="primary"
            native-type="submit"
            :loading="loading"
            size="large"
            class="login-button"
          >
            Login
          </el-button>
        </el-form-item>
      </el-form>

      <div class="login-footer">
        <p>Demo credentials: admin / admin123</p>
      </div>
    </el-card>
  </div>
</template>

<style scoped lang="scss">
.login-container {
  height: 100vh;
  display: flex;
  align-items: center;
  justify-content: center;
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
}

.login-card {
  width: 400px;

  .login-header {
    text-align: center;

    .login-logo {
      width: 64px;
      height: 64px;
      margin-bottom: 16px;
    }

    h2 {
      margin: 0;
      color: #303133;
    }
  }

  .login-form {
    margin-top: 20px;
  }

  .login-button {
    width: 100%;
  }

  .login-footer {
    text-align: center;
    margin-top: 20px;
    color: #909399;
    font-size: 12px;
  }
}
</style>
