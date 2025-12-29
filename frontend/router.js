// Simple vanilla JavaScript SPA router
class Router {
  constructor() {
    this.routes = {};
    this.currentRoute = null;
    this.authCheckCallback = null;
  }

  // Register a route
  route(path, handler) {
    this.routes[path] = handler;
    return this;
  }

  // Set auth check callback (runs before every route)
  beforeEach(callback) {
    this.authCheckCallback = callback;
    return this;
  }

  // Navigate to a path
  async navigate(path, replaceState = false) {
    // Extract pathname and search from path if it contains query params
    let pathname = path;
    let search = '';
    if (path.includes('?')) {
      [pathname, search] = path.split('?');
      search = '?' + search;
    }
    
    if (this.currentRoute === pathname) return;

    // Run auth check if registered
    if (this.authCheckCallback) {
      const shouldContinue = await this.authCheckCallback(pathname);
      if (!shouldContinue) return;
    }

    const handler = this.routes[pathname];
    if (!handler) {
      console.warn(`No route registered for: ${pathname}`);
      return;
    }

    this.currentRoute = pathname;

    // Update browser history (preserve query params)
    const fullPath = pathname + search;
    if (replaceState) {
      window.history.replaceState({ path: pathname }, '', fullPath);
    } else {
      window.history.pushState({ path: pathname }, '', fullPath);
    }

    // Clear app container and render new page
    const appContainer = document.getElementById('app');
    if (appContainer) {
      appContainer.innerHTML = '';
      await handler(appContainer);
    }
  }

  // Handle browser back/forward buttons
  init() {
    window.addEventListener('popstate', async (e) => {
      const path = e.state?.path || window.location.pathname;
      const search = window.location.search;
      await this.navigate(path + search, true);
    });

    // Handle initial page load
    const initialPath = window.location.pathname;
    this.navigate(initialPath, true);
  }
}

// Export singleton instance
const router = new Router();
export default router;
