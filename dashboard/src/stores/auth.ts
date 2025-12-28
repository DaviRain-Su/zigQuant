import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import * as authApi from '@/api/auth'

export const useAuthStore = defineStore('auth', () => {
  const token = ref<string | null>(localStorage.getItem('token'))
  const user = ref<authApi.UserInfo | null>(null)
  const loading = ref(false)
  const error = ref<string | null>(null)

  const isAuthenticated = computed(() => !!token.value)

  async function login(username: string, password: string) {
    loading.value = true
    error.value = null
    try {
      const response = await authApi.login({ username, password })
      token.value = response.token
      localStorage.setItem('token', response.token)
      await fetchUser()
    } catch (e) {
      error.value = (e as Error).message || 'Login failed'
      throw e
    } finally {
      loading.value = false
    }
  }

  async function fetchUser() {
    if (!token.value) return
    try {
      user.value = await authApi.getCurrentUser()
    } catch (e) {
      console.error('Failed to fetch user:', e)
    }
  }

  async function refreshToken() {
    try {
      const response = await authApi.refreshToken()
      token.value = response.token
      localStorage.setItem('token', response.token)
    } catch (e) {
      logout()
      throw e
    }
  }

  function logout() {
    token.value = null
    user.value = null
    localStorage.removeItem('token')
  }

  return {
    token,
    user,
    loading,
    error,
    isAuthenticated,
    login,
    fetchUser,
    refreshToken,
    logout,
  }
})
