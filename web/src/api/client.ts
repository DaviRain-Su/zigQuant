// ============================================================================
// API Client for zigQuant Backend
// ============================================================================

import type { ApiResponse, ApiError } from '../types/api';

// Use relative URL in development (Vite proxy handles it)
// Use absolute URL in production
const API_BASE_URL = import.meta.env.VITE_API_URL || '';

// ============================================================================
// HTTP Client
// ============================================================================

class ApiClient {
  private baseUrl: string;
  private token: string | null = null;

  constructor(baseUrl: string = API_BASE_URL) {
    this.baseUrl = baseUrl;
    // Try to restore token from localStorage
    this.token = localStorage.getItem('zigquant_token');
  }

  setToken(token: string | null) {
    this.token = token;
    if (token) {
      localStorage.setItem('zigquant_token', token);
    } else {
      localStorage.removeItem('zigquant_token');
    }
  }

  getToken(): string | null {
    return this.token;
  }

  private async request<T>(
    method: string,
    path: string,
    body?: unknown,
    options: RequestInit = {}
  ): Promise<ApiResponse<T>> {
    const url = `${this.baseUrl}${path}`;
    
    const headers: HeadersInit = {
      'Content-Type': 'application/json',
      ...options.headers,
    };

    if (this.token) {
      (headers as Record<string, string>)['Authorization'] = `Bearer ${this.token}`;
    }

    try {
      const response = await fetch(url, {
        method,
        headers,
        body: body ? JSON.stringify(body) : undefined,
        ...options,
      });

      const data = await response.json();

      if (!response.ok) {
        return {
          success: false,
          error: data.error || {
            code: 'HTTP_ERROR',
            message: `HTTP ${response.status}: ${response.statusText}`,
          },
        };
      }

      // Handle both wrapped and unwrapped responses
      if ('success' in data) {
        return data;
      }

      return { success: true, data };
    } catch (error) {
      const apiError: ApiError = {
        code: 'NETWORK_ERROR',
        message: error instanceof Error ? error.message : 'Network error',
      };
      return { success: false, error: apiError };
    }
  }

  // HTTP Methods
  get<T>(path: string): Promise<ApiResponse<T>> {
    return this.request<T>('GET', path);
  }

  post<T>(path: string, body?: unknown): Promise<ApiResponse<T>> {
    return this.request<T>('POST', path, body);
  }

  put<T>(path: string, body?: unknown): Promise<ApiResponse<T>> {
    return this.request<T>('PUT', path, body);
  }

  patch<T>(path: string, body?: unknown): Promise<ApiResponse<T>> {
    return this.request<T>('PATCH', path, body);
  }

  delete<T>(path: string): Promise<ApiResponse<T>> {
    return this.request<T>('DELETE', path);
  }
}

// Singleton instance
export const apiClient = new ApiClient();

export default apiClient;
