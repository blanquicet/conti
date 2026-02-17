/**
 * Shared helpers for creating accounts and payment methods via the UI.
 * Used by E2E tests - works with the modal-based UI in /perfil.
 */

/**
 * Navigate to /perfil and wait for the page to load.
 */
async function navigateToProfile(page, appUrl) {
  await page.goto(`${appUrl}/perfil`);
  await page.waitForTimeout(2000);
}

/**
 * Create a savings/checking/cash account via the UI.
 * @param {import('playwright').Page} page
 * @param {string} appUrl
 * @param {Object} options
 * @param {string} options.type - 'savings', 'checking', or 'cash'
 * @param {string} options.name - Account name
 * @param {string} [options.institution] - Bank/institution name
 * @param {string} [options.last4] - Last 4 digits
 * @param {number} [options.balance] - Initial balance (default: 0)
 * @returns {Promise<void>}
 */
export async function createAccountViaUI(page, appUrl, options) {
  await navigateToProfile(page, appUrl);

  // Click "Agregar cuenta" button to open modal
  await page.locator('#add-account-btn').waitFor({ state: 'visible', timeout: 10000 });
  await page.locator('#add-account-btn').click();
  await page.waitForTimeout(500);

  // Fill form in modal
  await page.selectOption('select#account-type', options.type);
  await page.locator('#account-name').fill(options.name);
  
  if (options.institution) {
    await page.locator('#account-institution').fill(options.institution);
  }
  if (options.last4) {
    await page.locator('#account-last4').fill(options.last4);
  }
  if (options.balance !== undefined) {
    await page.locator('#account-balance').fill(String(options.balance));
  }

  // Submit
  await page.locator('#account-form button[type="submit"]').click();
  await page.waitForTimeout(1500);

  // Close success modal if present
  const modalOk = page.locator('#modal-ok');
  if (await modalOk.isVisible()) {
    await modalOk.click();
    await page.waitForTimeout(500);
  }
}

/**
 * Create a payment method via the UI.
 * @param {import('playwright').Page} page
 * @param {string} appUrl
 * @param {Object} options
 * @param {string} options.name - Payment method name
 * @param {string} options.type - 'credit_card', 'debit_card', 'cash', or 'other'
 * @param {string} [options.institution] - Bank/institution name
 * @param {string} [options.last4] - Last 4 digits
 * @param {boolean} [options.isShared] - Share with household (default: false)
 * @param {string} [options.linkedAccountName] - Name of account to link (for debit_card)
 * @returns {Promise<void>}
 */
export async function createPaymentMethodViaUI(page, appUrl, options) {
  await navigateToProfile(page, appUrl);

  // Click "Agregar método" button to open modal
  await page.locator('#add-payment-method-btn').waitFor({ state: 'visible', timeout: 10000 });
  await page.locator('#add-payment-method-btn').click();
  await page.waitForTimeout(500);

  // Fill form in modal
  await page.locator('#pm-name').fill(options.name);
  await page.selectOption('select#pm-type', options.type);
  
  if (options.institution) {
    await page.locator('#pm-institution').fill(options.institution);
  }
  if (options.last4) {
    await page.locator('#pm-last4').fill(options.last4);
  }
  
  // Handle shared checkbox
  const isSharedCheckbox = page.locator('#pm-shared');
  const isChecked = await isSharedCheckbox.isChecked();
  if (options.isShared && !isChecked) {
    await isSharedCheckbox.check();
  } else if (!options.isShared && isChecked) {
    await isSharedCheckbox.uncheck();
  }

  // Handle linked account for debit cards
  if (options.type === 'debit_card' && options.linkedAccountName) {
    await page.waitForTimeout(300); // Wait for account field to appear
    await page.selectOption('select#pm-account', { label: options.linkedAccountName });
  }

  // Submit
  await page.locator('#pm-form button[type="submit"]').click();
  await page.waitForTimeout(1500);

  // Close success modal if present
  const modalOk = page.locator('#modal-ok');
  if (await modalOk.isVisible()) {
    await modalOk.click();
    await page.waitForTimeout(500);
  }
}

/**
 * Create multiple accounts via the UI in one call.
 * @param {import('playwright').Page} page
 * @param {string} appUrl
 * @param {Array<{type: string, name: string, institution?: string, last4?: string, balance?: number}>} accounts
 * @returns {Promise<void>}
 */
export async function createAccountsViaUI(page, appUrl, accounts) {
  for (const account of accounts) {
    await createAccountViaUI(page, appUrl, account);
  }
}

/**
 * Create multiple payment methods via the UI in one call.
 * @param {import('playwright').Page} page
 * @param {string} appUrl
 * @param {Array<{name: string, type: string, institution?: string, last4?: string, isShared?: boolean, linkedAccountName?: string}>} methods
 * @returns {Promise<void>}
 */
export async function createPaymentMethodsViaUI(page, appUrl, methods) {
  for (const method of methods) {
    await createPaymentMethodViaUI(page, appUrl, method);
  }
}

/**
 * Get account ID from the database by name.
 * @param {import('pg').Pool} pool
 * @param {string} ownerId
 * @param {string} accountName
 * @returns {Promise<string|null>}
 */
export async function getAccountIdByName(pool, ownerId, accountName) {
  const result = await pool.query(
    `SELECT id FROM accounts WHERE owner_id = $1 AND name = $2`,
    [ownerId, accountName]
  );
  return result.rows[0]?.id || null;
}

/**
 * Get payment method ID from the database by name.
 * @param {import('pg').Pool} pool
 * @param {string} ownerId
 * @param {string} methodName
 * @returns {Promise<string|null>}
 */
export async function getPaymentMethodIdByName(pool, ownerId, methodName) {
  const result = await pool.query(
    `SELECT id FROM payment_methods WHERE owner_id = $1 AND name = $2`,
    [ownerId, methodName]
  );
  return result.rows[0]?.id || null;
}

/**
 * Get account IDs for multiple accounts.
 * @param {import('pg').Pool} pool
 * @param {string} ownerId
 * @param {string[]} accountNames
 * @returns {Promise<{[name: string]: string}>}
 */
export async function getAccountIds(pool, ownerId, accountNames) {
  const result = await pool.query(
    `SELECT id, name FROM accounts WHERE owner_id = $1 AND name = ANY($2)`,
    [ownerId, accountNames]
  );
  const map = {};
  for (const row of result.rows) {
    map[row.name] = row.id;
  }
  return map;
}

/**
 * Get payment method IDs for multiple methods.
 * @param {import('pg').Pool} pool
 * @param {string} ownerId
 * @param {string[]} methodNames
 * @returns {Promise<{[name: string]: string}>}
 */
export async function getPaymentMethodIds(pool, ownerId, methodNames) {
  const result = await pool.query(
    `SELECT id, name FROM payment_methods WHERE owner_id = $1 AND name = ANY($2)`,
    [ownerId, methodNames]
  );
  const map = {};
  for (const row of result.rows) {
    map[row.name] = row.id;
  }
  return map;
}
