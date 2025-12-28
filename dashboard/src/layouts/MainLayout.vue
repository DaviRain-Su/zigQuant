<script setup lang="ts">
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import {
  Menu as IconMenu,
  House,
  Setting,
  DataAnalysis,
  Timer,
  SwitchButton,
} from '@element-plus/icons-vue'

const router = useRouter()
const authStore = useAuthStore()
const isCollapsed = ref(false)

const menuItems = [
  { path: '/dashboard', title: 'Dashboard', icon: House },
  { path: '/strategies', title: 'Strategies', icon: Setting },
  { path: '/backtest', title: 'Backtest', icon: DataAnalysis },
]

function handleLogout() {
  authStore.logout()
  router.push('/login')
}
</script>

<template>
  <el-container class="main-layout">
    <!-- Sidebar -->
    <el-aside :width="isCollapsed ? '64px' : '200px'" class="sidebar">
      <div class="logo">
        <img src="/vite.svg" alt="Logo" class="logo-img" />
        <span v-if="!isCollapsed" class="logo-text">zigQuant</span>
      </div>

      <el-menu
        :default-active="$route.path"
        :collapse="isCollapsed"
        router
        class="sidebar-menu"
      >
        <el-menu-item
          v-for="item in menuItems"
          :key="item.path"
          :index="item.path"
        >
          <el-icon><component :is="item.icon" /></el-icon>
          <template #title>{{ item.title }}</template>
        </el-menu-item>
      </el-menu>
    </el-aside>

    <!-- Main Content -->
    <el-container>
      <!-- Header -->
      <el-header class="header">
        <div class="header-left">
          <el-button
            :icon="IconMenu"
            text
            @click="isCollapsed = !isCollapsed"
          />
          <el-breadcrumb separator="/">
            <el-breadcrumb-item :to="{ path: '/' }">Home</el-breadcrumb-item>
            <el-breadcrumb-item>{{ $route.name }}</el-breadcrumb-item>
          </el-breadcrumb>
        </div>

        <div class="header-right">
          <el-dropdown>
            <span class="user-dropdown">
              <el-icon><Timer /></el-icon>
              {{ authStore.user?.user_id || 'User' }}
            </span>
            <template #dropdown>
              <el-dropdown-menu>
                <el-dropdown-item @click="handleLogout">
                  <el-icon><SwitchButton /></el-icon>
                  Logout
                </el-dropdown-item>
              </el-dropdown-menu>
            </template>
          </el-dropdown>
        </div>
      </el-header>

      <!-- Content -->
      <el-main class="main-content">
        <router-view />
      </el-main>
    </el-container>
  </el-container>
</template>

<style scoped lang="scss">
.main-layout {
  height: 100vh;
}

.sidebar {
  background: #304156;
  transition: width 0.3s;
  overflow: hidden;

  .logo {
    height: 60px;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 0 16px;

    .logo-img {
      width: 32px;
      height: 32px;
    }

    .logo-text {
      color: #fff;
      font-size: 18px;
      font-weight: bold;
      margin-left: 12px;
    }
  }

  .sidebar-menu {
    border-right: none;
    background: transparent;

    :deep(.el-menu-item) {
      color: #bfcbd9;

      &:hover {
        background: #263445;
      }

      &.is-active {
        color: #409eff;
        background: #263445;
      }
    }
  }
}

.header {
  background: #fff;
  border-bottom: 1px solid #e6e6e6;
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 0 20px;

  .header-left {
    display: flex;
    align-items: center;
    gap: 16px;
  }

  .header-right {
    .user-dropdown {
      display: flex;
      align-items: center;
      gap: 8px;
      cursor: pointer;
    }
  }
}

.main-content {
  background: #f5f7fa;
  padding: 20px;
}
</style>
