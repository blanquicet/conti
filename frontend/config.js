/**
 * Frontend Configuration
 *
 * Centralized configuration for the frontend application.
 */

/**
 * API URL auto-detection
 * - localhost: uses empty string (relative URLs to same server:port)
 * - production: uses full API URL
 */
export const API_URL = window.location.hostname === "localhost"
  ? ""
  : "https://api.gastos.blanquicet.com.co";
