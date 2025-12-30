/**
 * Auth Utilities Module
 * 
 * Provides reusable authentication functions for SPA pages.
 * Maintains API_URL auto-detection for local vs production environments.
 */

import { API_URL } from './config.js';

// Email validation regex - requires format: text@text.text
const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

// Cache for auth check (valid for 100ms to avoid multiple calls during page load)
let authCache = null;
let authCacheTime = 0;
const CACHE_DURATION = 100; // milliseconds

/**
 * Check if user is authenticated
 * @returns {Promise<{authenticated: boolean, user: Object|null}>}
 */
export async function checkAuth() {
  // Return cached result if recent
  const now = Date.now();
  if (authCache && (now - authCacheTime) < CACHE_DURATION) {
    return authCache;
  }

  try {
    const response = await fetch(`${API_URL}/me`, {
      credentials: "include",
    });

    if (response.ok) {
      const user = await response.json();
      authCache = { authenticated: true, user };
      authCacheTime = now;
      return authCache;
    } else {
      authCache = { authenticated: false, user: null };
      authCacheTime = now;
      return authCache;
    }
  } catch (error) {
    console.error("Auth check failed:", error);
    authCache = { authenticated: false, user: null };
    authCacheTime = now;
    return authCache;
  }
}

/**
 * Clear auth cache (call after login/logout)
 */
export function clearAuthCache() {
  authCache = null;
  authCacheTime = 0;
}

/**
 * Login user with email and password
 * @param {string} email 
 * @param {string} password 
 * @returns {Promise<{success: boolean, user?: Object, error?: string}>}
 */
export async function login(email, password) {
  email = email.trim();

  if (!email || !password) {
    return { success: false, error: "Por favor ingresa email y contraseña" };
  }

  if (!EMAIL_REGEX.test(email)) {
    return { success: false, error: "Por favor ingresa un email válido (ej: usuario@ejemplo.com)" };
  }

  try {
    const response = await fetch(`${API_URL}/auth/login`, {
      method: "POST",
      credentials: "include",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ email, password }),
    });

    const data = await response.json();

    if (response.ok) {
      clearAuthCache(); // Clear cache so next checkAuth() fetches fresh user data
      return { success: true, user: data };
    } else {
      return { success: false, error: data.error || "Error al iniciar sesión" };
    }
  } catch (error) {
    console.error("Login failed:", error);
    return { success: false, error: "Error de conexión. Intenta de nuevo." };
  }
}

/**
 * Register new user
 * @param {string} name 
 * @param {string} email 
 * @param {string} password 
 * @param {string} confirmPassword 
 * @returns {Promise<{success: boolean, user?: Object, error?: string}>}
 */
export async function register(name, email, password, confirmPassword) {
  name = name.trim();
  email = email.trim();

  if (!name || !email || !password) {
    return { success: false, error: "Por favor completa todos los campos" };
  }

  if (!EMAIL_REGEX.test(email)) {
    return { success: false, error: "Por favor ingresa un email válido (ej: usuario@ejemplo.com)" };
  }

  if (password !== confirmPassword) {
    return { success: false, error: "Las contraseñas no coinciden" };
  }

  // Validate password strength
  const validation = validatePasswordRequirements(password);
  if (!validation.valid) {
    return { success: false, error: validation.error };
  }

  try {
    const response = await fetch(`${API_URL}/auth/register`, {
      method: "POST",
      credentials: "include",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        email,
        name,
        password,
        password_confirm: confirmPassword
      }),
    });

    const data = await response.json();

    if (response.ok) {
      return { success: true, user: data };
    } else {
      return { success: false, error: data.error || "Error al registrarse" };
    }
  } catch (error) {
    console.error("Register failed:", error);
    return { success: false, error: "Error de conexión. Intenta de nuevo." };
  }
}

/**
 * Logout current user
 * @returns {Promise<void>}
 */
export async function logout() {
  try {
    await fetch(`${API_URL}/auth/logout`, {
      method: "POST",
      credentials: "include",
    });
    clearAuthCache();
  } catch (error) {
    console.error("Logout failed:", error);
    clearAuthCache();
  }
}

/**
 * Validate email format
 * @param {string} email 
 * @returns {boolean}
 */
export function validateEmail(email) {
  if (!email || email.trim() === "") return false;
  return EMAIL_REGEX.test(email.trim());
}

/**
 * Check password strength
 * @param {string} password 
 * @returns {{level: number, text: string, width: string, className: string}}
 */
export function checkPasswordStrength(password) {
  if (!password || password.length === 0) {
    return { level: 0, text: "", width: "0%", className: "" };
  }

  // Check basic requirements
  const hasMinLength = password.length >= 8;
  const hasLowerCase = /[a-z]/.test(password);
  const hasUpperCase = /[A-Z]/.test(password);
  const hasNumber = /[0-9]/.test(password);
  const hasSpecialChar = /[^a-zA-Z0-9]/.test(password);

  // Basic requirements: 8+ chars + lowercase + uppercase + (number OR symbol)
  const meetsBasicRequirements = hasMinLength && hasLowerCase && hasUpperCase && (hasNumber || hasSpecialChar);

  let strength = 0;

  if (meetsBasicRequirements) {
    strength = 2; // Start at "Aceptable"
    if (password.length >= 12) strength++; // Longer password
    if (hasNumber && hasSpecialChar) strength++; // Both numbers AND special chars
  }

  // Map strength to display values
  const strengthMap = {
    0: { text: "Débil", width: "25%", className: "weak" },
    2: { text: "Aceptable", width: "50%", className: "acceptable" },
    3: { text: "Buena", width: "75%", className: "good" },
    4: { text: "Fuerte", width: "100%", className: "strong" }
  };

  return { level: strength, ...strengthMap[strength] };
}

/**
 * Validate password meets minimum requirements
 * @param {string} password
 * @returns {{valid: boolean, error: string}}
 */
export function validatePasswordRequirements(password) {
  if (!password || password.length === 0) {
    return { valid: false, error: "La contraseña es requerida" };
  }

  if (password.length < 8) {
    return { valid: false, error: "La contraseña debe tener al menos 8 caracteres" };
  }

  const hasLower = /[a-z]/.test(password);
  const hasUpper = /[A-Z]/.test(password);
  const hasNumber = /[0-9]/.test(password);
  const hasSymbol = /[^a-zA-Z0-9]/.test(password);

  if (!hasLower || !hasUpper || (!hasNumber && !hasSymbol)) {
    return { valid: false, error: "La contraseña debe tener: mayúsculas, minúsculas y números o símbolos" };
  }

  return { valid: true, error: "" };
}

/**
 * Get API URL for movements endpoint
 * @returns {string}
 */
export function getMovementsApiUrl() {
  return `${API_URL}/movements`;
}

/**
 * Get current API URL
 * @returns {string}
 */
export function getApiUrl() {
  return API_URL;
}
