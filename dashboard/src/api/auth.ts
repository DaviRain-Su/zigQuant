import api from './index'

export interface LoginRequest {
  username: string
  password: string
}

export interface LoginResponse {
  token: string
  expires_in: number
  token_type: string
}

export interface UserInfo {
  user_id: string
  issued_at: number
  expires_at: number
  issuer?: string
}

export async function login(data: LoginRequest): Promise<LoginResponse> {
  const response = await api.post('/auth/login', data)
  return response.data
}

export async function refreshToken(): Promise<LoginResponse> {
  const response = await api.post('/auth/refresh')
  return response.data
}

export async function getCurrentUser(): Promise<UserInfo> {
  const response = await api.get('/auth/me')
  return response.data
}
